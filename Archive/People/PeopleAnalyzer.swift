import Foundation
import AppKit
import Vision
import ImageIO

public actor PeopleAnalyzer {
    public static let shared = PeopleAnalyzer(
        catalogStore: .shared
    )
    public static let currentEngineVersion = 1

    public typealias ProgressHandler =
        @Sendable (PeopleScanProgress) async -> Void
    public typealias DetectionProvider =
        @Sendable (PhotoAsset) async throws -> [PeopleFaceDetection]

    private let catalogStore: CatalogStore
    private let detectionProvider: DetectionProvider

    public init(
        catalogStore: CatalogStore = .shared,
        detectionProvider: DetectionProvider? = nil
    ) {
        self.catalogStore = catalogStore
        self.detectionProvider = detectionProvider ?? { asset in
            try await Task.detached(priority: .utility) {
                try PeopleImageAnalyzer.analyze(asset: asset)
            }.value
        }
    }

    public func scan(
        photoIDs: Set<PhotoAsset.ID>? = nil,
        forceReanalysis: Bool = false,
        progress: ProgressHandler? = nil
    ) async throws -> PeopleScanResult {
        try catalogStore.refreshMissingStatus(
            photoIDs: photoIDs
        )
        let candidates = try catalogStore.peopleAnalysisCandidates(
            engineVersion: Self.currentEngineVersion,
            photoIDs: photoIDs
        )
        var faces: [CatalogFace] = []
        var analyzedCount = 0
        var cachedCount = 0
        var unavailablePaths: [String] = []

        await progress?(PeopleScanProgress(total: candidates.count))

        for (offset, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress?(PeopleScanProgress(
                completed: offset,
                total: candidates.count,
                filename: candidate.entry.filename,
                analyzedCount: analyzedCount,
                cachedCount: cachedCount,
                faceCount: faces.count,
                unavailableCount: unavailablePaths.count
            ))

            let url = URL(fileURLWithPath: candidate.entry.path)
            guard let before = Self.fileSnapshot(url),
                  before.fileSize == candidate.entry.fileSize,
                  Self.datesMatch(
                    before.modificationDate,
                    candidate.entry.modificationDate
                  ) else {
                try? catalogStore.clearPeopleFaceAnalysis(
                    id: candidate.entry.id
                )
                unavailablePaths.append(candidate.entry.path)
                continue
            }

            if let cached = candidate.cachedFaces,
               !forceReanalysis {
                faces.append(contentsOf: cached)
                cachedCount += 1
                continue
            }

            do {
                let detections = try await detectionProvider(
                    candidate.entry.asset
                )
                try Task.checkCancellation()
                guard let after = Self.fileSnapshot(url),
                      after == before,
                      try catalogStore.recordPeopleFaceAnalysis(
                          detections,
                          id: candidate.entry.id,
                          engineVersion:
                              Self.currentEngineVersion,
                          expectedFileSize:
                              candidate.entry.fileSize,
                          expectedModificationDate:
                              candidate.entry.modificationDate
                      ) else {
                    unavailablePaths.append(candidate.entry.path)
                    continue
                }
                faces.append(contentsOf:
                    try catalogStore.catalogFaces(
                        photoID: candidate.entry.id,
                        includeIgnored: true
                    )
                )
                analyzedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                unavailablePaths.append(candidate.entry.path)
            }
        }

        await progress?(PeopleScanProgress(
            completed: candidates.count,
            total: candidates.count,
            analyzedCount: analyzedCount,
            cachedCount: cachedCount,
            faceCount: faces.count,
            unavailableCount: unavailablePaths.count
        ))
        return PeopleScanResult(
            faces: faces,
            candidateCount: candidates.count,
            analyzedCount: analyzedCount,
            cachedCount: cachedCount,
            unavailablePaths: unavailablePaths
        )
    }

    public nonisolated static func makeSnapshot(
        people: [CatalogPerson],
        faces: [CatalogFace],
        similarityThreshold: Float = 12
    ) -> PeopleSnapshot {
        let activeFaces = faces.filter {
            $0.disposition == .candidate
        }
        let ignoredCount = faces.count - activeFaces.count
        let byPerson = Dictionary(
            grouping: activeFaces.compactMap { face in
                face.personID.map { ($0, face) }
            },
            by: \.0
        )
        let namedGroups = people
            .map { person in
                PeopleGroup(
                    id: "person:\(person.id.uuidString)",
                    name: person.name,
                    kind: .named(personID: person.id),
                    faces: (byPerson[person.id] ?? [])
                        .map(\.1)
                        .sorted(by: faceDisplayOrder)
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }

        let unassigned = activeFaces
            .filter { $0.personID == nil }
            .sorted(by: faceDisplayOrder)
        let clusters = suggestedClusters(
            faces: unassigned,
            similarityThreshold: max(0, similarityThreshold)
        )
        let grouped = clusters.filter { $0.count > 1 }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return ($0.first?.id ?? "") < ($1.first?.id ?? "")
            }
        let suggestedGroups = grouped.enumerated().map {
            offset,
            cluster in
            PeopleGroup(
                id: "suggested:\(cluster.map(\.id).sorted().first ?? UUID().uuidString)",
                name: "Suggested Group \(offset + 1)",
                kind: .suggested,
                faces: cluster.sorted(by: faceDisplayOrder)
            )
        }
        let groupedFaceIDs = Set(
            grouped.flatMap { $0.map(\.id) }
        )
        let singles = unassigned.filter {
            !groupedFaceIDs.contains($0.id)
        }

        return PeopleSnapshot(
            namedGroups: namedGroups,
            suggestedGroups: suggestedGroups,
            singleFaces: singles,
            ignoredFaceCount: ignoredCount
        )
    }

    public nonisolated static func featureDistance(
        _ lhs: Data,
        _ rhs: Data
    ) throws -> Float {
        let left = try featureObservation(from: lhs)
        let right = try featureObservation(from: rhs)
        var distance: Float = 0
        try left.computeDistance(&distance, to: right)
        return distance
    }

    private nonisolated static func suggestedClusters(
        faces: [CatalogFace],
        similarityThreshold: Float
    ) -> [[CatalogFace]] {
        guard !faces.isEmpty else { return [] }
        let observations = Dictionary(
            uniqueKeysWithValues: faces.compactMap { face in
                (try? featureObservation(
                    from: face.featurePrintData
                )).map { (face.id, $0) }
            }
        )
        var clusters: [[CatalogFace]] = []

        for face in faces {
            guard let observation = observations[face.id] else {
                clusters.append([face])
                continue
            }
            var bestIndex: Int?
            var bestMean = Float.greatestFiniteMagnitude

            for index in clusters.indices {
                let cluster = clusters[index]
                let distances = cluster.compactMap { member -> Float? in
                    guard let other = observations[member.id] else {
                        return nil
                    }
                    var distance: Float = 0
                    guard (try? observation.computeDistance(
                        &distance,
                        to: other
                    )) != nil else {
                        return nil
                    }
                    return distance
                }
                guard distances.count == cluster.count,
                      let maximum = distances.max(),
                      maximum <= similarityThreshold else {
                    continue
                }
                let mean =
                    distances.reduce(0, +)
                    / Float(max(1, distances.count))
                if mean < bestMean {
                    bestMean = mean
                    bestIndex = index
                }
            }

            if let bestIndex {
                clusters[bestIndex].append(face)
            } else {
                clusters.append([face])
            }
        }
        return clusters
    }

    private nonisolated static func featureObservation(
        from data: Data
    ) throws -> VNFeaturePrintObservation {
        guard let observation =
                try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: data
                ) else {
            throw PeopleAnalyzerError.invalidFeaturePrint
        }
        return observation
    }

    private nonisolated static func faceDisplayOrder(
        _ lhs: CatalogFace,
        _ rhs: CatalogFace
    ) -> Bool {
        if lhs.photoID != rhs.photoID {
            return lhs.photoID < rhs.photoID
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.id < rhs.id
    }

    private struct FileSnapshot: Equatable {
        var fileSize: Int64
        var modificationDate: Date?
    }

    private nonisolated static func fileSnapshot(
        _ url: URL
    ) -> FileSnapshot? {
        guard let values = try? url.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]
        ),
        values.isRegularFile == true,
        let size = values.fileSize else {
            return nil
        }
        return FileSnapshot(
            fileSize: Int64(size),
            modificationDate: values.contentModificationDate
        )
    }

    private nonisolated static func datesMatch(
        _ lhs: Date?,
        _ rhs: Date?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(
                lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970
            ) < 0.001
        default:
            return false
        }
    }
}

private enum PeopleAnalyzerError: LocalizedError {
    case invalidFeaturePrint
    case faceCropUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidFeaturePrint:
            return "A cached face descriptor could not be read."
        case .faceCropUnavailable:
            return "A detected face could not be cropped."
        }
    }
}

private enum PeopleImageAnalyzer {
    private static let analysisLimit: CGFloat = 1_600

    static func analyze(
        asset: PhotoAsset
    ) throws -> [PeopleFaceDetection] {
        let image = try ThumbnailGenerator.generate(
            for: asset,
            targetPixelSize: analysisLimit,
            quality: .preview
        )
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw SubjectMaskGenerator.GenerationError
                .imageHasNoBitmap
        }
        return try analyze(cgImage: cgImage)
    }

    static func analyze(
        cgImage: CGImage
    ) throws -> [PeopleFaceDetection] {
        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])

        return try (request.results ?? [])
            .filter {
                $0.confidence >= 0.5
                    && $0.boundingBox.width >= 0.025
                    && $0.boundingBox.height >= 0.025
            }
            .prefix(32)
            .map { observation in
                let cropRect = expandedCropRect(
                    observation.boundingBox
                )
                guard let crop = crop(
                    cgImage,
                    normalizedVisionRect: cropRect
                ) else {
                    throw PeopleAnalyzerError.faceCropUnavailable
                }
                let featureRequest =
                    VNGenerateImageFeaturePrintRequest()
                try VNImageRequestHandler(
                    cgImage: crop,
                    orientation: .up,
                    options: [:]
                ).perform([featureRequest])
                guard let feature = featureRequest.results?.first else {
                    throw PeopleAnalyzerError.invalidFeaturePrint
                }
                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: feature,
                    requiringSecureCoding: true
                )
                return PeopleFaceDetection(
                    boundingBox: observation.boundingBox,
                    confidence: Double(observation.confidence),
                    captureQuality:
                        observation.faceCaptureQuality.map(Double.init),
                    featurePrintData: data
                )
            }
    }

    private static func expandedCropRect(
        _ rect: CGRect
    ) -> CGRect {
        let horizontal = rect.width * 0.28
        let bottom = rect.height * 0.25
        let top = rect.height * 0.42
        let minX = max(0, rect.minX - horizontal)
        let maxX = min(1, rect.maxX + horizontal)
        let minY = max(0, rect.minY - bottom)
        let maxY = min(1, rect.maxY + top)
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func crop(
        _ image: CGImage,
        normalizedVisionRect rect: CGRect
    ) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixelRect = CGRect(
            x: rect.minX * width,
            y: (1 - rect.maxY) * height,
            width: rect.width * width,
            height: rect.height * height
        )
        .integral
        .intersection(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard !pixelRect.isNull,
              pixelRect.width >= 2,
              pixelRect.height >= 2 else {
            return nil
        }
        return image.cropping(to: pixelRect)
    }
}
