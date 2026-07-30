import Foundation

public struct PeopleAnalysisPreferences:
    Codable,
    Equatable,
    Sendable
{
    public var automaticAnalysisEnabled: Bool

    public init(
        automaticAnalysisEnabled: Bool = false
    ) {
        self.automaticAnalysisEnabled =
            automaticAnalysisEnabled
    }
}

public enum PeopleScanOrigin:
    String,
    Equatable,
    Sendable
{
    case interactive
    case automatic
}

public final class PeopleAnalysisPreferencesStore:
    @unchecked Sendable
{
    public static let shared =
        PeopleAnalysisPreferencesStore()

    private let storeURL: URL
    private let queue = DispatchQueue(
        label: "rawdesk.people-analysis.preferences"
    )

    public init(directory: URL? = nil) {
        let directory =
            RAWDeskStorageDirectory.resolve(directory)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        storeURL = directory.appendingPathComponent(
            "people_analysis_settings.json"
        )
    }

    public func load() -> PeopleAnalysisPreferences {
        queue.sync {
            guard let data = try? Data(contentsOf: storeURL)
            else {
                return PeopleAnalysisPreferences()
            }
            do {
                return try JSONDecoder().decode(
                    PeopleAnalysisPreferences.self,
                    from: data
                )
            } catch {
                let backup =
                    storeURL.appendingPathExtension(
                        "corrupt.\(Int(Date().timeIntervalSince1970))"
                    )
                try? FileManager.default.moveItem(
                    at: storeURL,
                    to: backup
                )
                return PeopleAnalysisPreferences()
            }
        }
    }

    public func save(
        _ preferences: PeopleAnalysisPreferences
    ) {
        queue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys,
                ]
                let data = try encoder.encode(preferences)
                try data.write(
                    to: storeURL,
                    options: [.atomic]
                )
            } catch {
                // Best effort. The in-memory preference remains authoritative
                // for the current app session.
            }
        }
    }
}

public enum PeopleGroupingSensitivity:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case conservative
    case balanced
    case broad

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced: return "Balanced"
        case .broad: return "Broad"
        }
    }

    public var threshold: Float {
        switch self {
        case .conservative: return 9
        case .balanced: return 12
        case .broad: return 16
        }
    }
}

public enum PeopleFaceDisposition:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case candidate
    case ignored
}

public struct PeopleFaceDetection:
    Equatable,
    Sendable
{
    public var boundingBox: CGRect
    public var confidence: Double
    public var captureQuality: Double?
    public var featurePrintData: Data

    public init(
        boundingBox: CGRect,
        confidence: Double,
        captureQuality: Double?,
        featurePrintData: Data
    ) {
        self.boundingBox = boundingBox
        self.confidence = Self.unit(confidence)
        self.captureQuality = captureQuality.map(Self.unit)
        self.featurePrintData = featurePrintData
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public struct CatalogFace:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String
    public var photoID: String
    public var boundingBox: CGRect
    public var confidence: Double
    public var captureQuality: Double?
    public var featurePrintData: Data
    public var personID: UUID?
    public var disposition: PeopleFaceDisposition
    public var analyzedAt: Date

    public init(
        id: String = UUID().uuidString,
        photoID: String,
        boundingBox: CGRect,
        confidence: Double,
        captureQuality: Double?,
        featurePrintData: Data,
        personID: UUID? = nil,
        disposition: PeopleFaceDisposition = .candidate,
        analyzedAt: Date = Date()
    ) {
        self.id = id
        self.photoID = photoID
        self.boundingBox = boundingBox
        self.confidence = min(
            1,
            max(0, confidence.isFinite ? confidence : 0)
        )
        self.captureQuality = captureQuality.map {
            min(1, max(0, $0.isFinite ? $0 : 0))
        }
        self.featurePrintData = featurePrintData
        self.personID = personID
        self.disposition = disposition
        self.analyzedAt = analyzedAt
    }
}

public struct CatalogPerson:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CatalogPeopleAnalysisCandidate:
    Sendable
{
    public var entry: CatalogEntry
    public var cachedFaces: [CatalogFace]?

    public init(
        entry: CatalogEntry,
        cachedFaces: [CatalogFace]?
    ) {
        self.entry = entry
        self.cachedFaces = cachedFaces
    }
}

public struct PeopleScanProgress:
    Equatable,
    Sendable
{
    public var completed: Int
    public var total: Int
    public var filename: String?
    public var analyzedCount: Int
    public var cachedCount: Int
    public var faceCount: Int
    public var unavailableCount: Int

    public init(
        completed: Int = 0,
        total: Int = 0,
        filename: String? = nil,
        analyzedCount: Int = 0,
        cachedCount: Int = 0,
        faceCount: Int = 0,
        unavailableCount: Int = 0
    ) {
        self.completed = max(0, completed)
        self.total = max(0, total)
        self.filename = filename
        self.analyzedCount = max(0, analyzedCount)
        self.cachedCount = max(0, cachedCount)
        self.faceCount = max(0, faceCount)
        self.unavailableCount = max(0, unavailableCount)
    }

    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }
}

public struct PeopleScanResult:
    Equatable,
    Sendable
{
    public var faces: [CatalogFace]
    public var candidateCount: Int
    public var analyzedCount: Int
    public var cachedCount: Int
    public var unavailablePaths: [String]

    public init(
        faces: [CatalogFace],
        candidateCount: Int,
        analyzedCount: Int,
        cachedCount: Int,
        unavailablePaths: [String]
    ) {
        self.faces = faces
        self.candidateCount = max(0, candidateCount)
        self.analyzedCount = max(0, analyzedCount)
        self.cachedCount = max(0, cachedCount)
        self.unavailablePaths = unavailablePaths
    }
}

public enum PeopleGroupKind:
    Equatable,
    Sendable
{
    case named(personID: UUID)
    case suggested
}

public struct PeopleGroup:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String
    public var name: String
    public var kind: PeopleGroupKind
    public var faces: [CatalogFace]

    public init(
        id: String,
        name: String,
        kind: PeopleGroupKind,
        faces: [CatalogFace]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.faces = faces
    }

    public var personID: UUID? {
        guard case let .named(personID) = kind else {
            return nil
        }
        return personID
    }

    public var isSuggested: Bool {
        if case .suggested = kind { return true }
        return false
    }

    public var representativeFace: CatalogFace? {
        faces.max {
            let lhs = $0.captureQuality ?? $0.confidence
            let rhs = $1.captureQuality ?? $1.confidence
            if lhs != rhs { return lhs < rhs }
            return $0.id > $1.id
        }
    }

    public var photoCount: Int {
        Set(faces.map(\.photoID)).count
    }
}

public struct PeopleSnapshot:
    Equatable,
    Sendable
{
    public var namedGroups: [PeopleGroup]
    public var suggestedGroups: [PeopleGroup]
    public var singleFaces: [CatalogFace]
    public var ignoredFaceCount: Int

    public init(
        namedGroups: [PeopleGroup] = [],
        suggestedGroups: [PeopleGroup] = [],
        singleFaces: [CatalogFace] = [],
        ignoredFaceCount: Int = 0
    ) {
        self.namedGroups = namedGroups
        self.suggestedGroups = suggestedGroups
        self.singleFaces = singleFaces
        self.ignoredFaceCount = max(0, ignoredFaceCount)
    }

    public var allGroups: [PeopleGroup] {
        namedGroups + suggestedGroups
    }
}
