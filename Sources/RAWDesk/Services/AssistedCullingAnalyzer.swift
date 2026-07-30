import AppKit
import CoreGraphics
import Foundation
import Vision

public enum AssistedCullingDecision:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case select
    case reject
    case review

    public var name: String {
        switch self {
        case .select: return "Select"
        case .reject: return "Reject"
        case .review: return "Review"
        }
    }
}

public enum AssistedCullingReviewFilter:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case all
    case selects
    case rejects
    case review

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .all: return "All"
        case .selects: return "Selects"
        case .rejects: return "Rejects"
        case .review: return "Review"
        }
    }

    public func contains(_ decision: AssistedCullingDecision) -> Bool {
        switch self {
        case .all:
            return true
        case .selects:
            return decision == .select
        case .rejects:
            return decision == .reject
        case .review:
            return decision == .review
        }
    }
}

public struct AssistedCullingCriteria:
    Codable,
    Equatable,
    Sendable
{
    public var useSubjectFocus: Bool
    public var subjectFocusThreshold: Double
    public var useEyeFocus: Bool
    public var eyeFocusThreshold: Double
    public var requireDetectedEyesForEyeFocus: Bool
    public var useEyesOpen: Bool
    public var requireDetectedEyesForEyesOpen: Bool
    public var includeUncertainEyes: Bool
    public var rejectExposureIssues: Bool
    public var exposureIssueThreshold: Double
    public var rejectMisfires: Bool
    public var misfireThreshold: Double
    public var rejectDocuments: Bool
    public var documentThreshold: Double
    public var suggestAutoStacks: Bool
    public var stackTimeWindow: TimeInterval
    public var stackSimilarityThreshold: Double

    public init(
        useSubjectFocus: Bool = true,
        subjectFocusThreshold: Double = 0.52,
        useEyeFocus: Bool = false,
        eyeFocusThreshold: Double = 0.52,
        requireDetectedEyesForEyeFocus: Bool = false,
        useEyesOpen: Bool = false,
        requireDetectedEyesForEyesOpen: Bool = false,
        includeUncertainEyes: Bool = true,
        rejectExposureIssues: Bool = true,
        exposureIssueThreshold: Double = 0.72,
        rejectMisfires: Bool = true,
        misfireThreshold: Double = 0.78,
        rejectDocuments: Bool = false,
        documentThreshold: Double = 0.72,
        suggestAutoStacks: Bool = true,
        stackTimeWindow: TimeInterval = 10,
        stackSimilarityThreshold: Double = 0.18
    ) {
        self.useSubjectFocus = useSubjectFocus
        self.subjectFocusThreshold = Self.unit(subjectFocusThreshold)
        self.useEyeFocus = useEyeFocus
        self.eyeFocusThreshold = Self.unit(eyeFocusThreshold)
        self.requireDetectedEyesForEyeFocus =
            requireDetectedEyesForEyeFocus
        self.useEyesOpen = useEyesOpen
        self.requireDetectedEyesForEyesOpen =
            requireDetectedEyesForEyesOpen
        self.includeUncertainEyes = includeUncertainEyes
        self.rejectExposureIssues = rejectExposureIssues
        self.exposureIssueThreshold = Self.unit(
            exposureIssueThreshold
        )
        self.rejectMisfires = rejectMisfires
        self.misfireThreshold = Self.unit(misfireThreshold)
        self.rejectDocuments = rejectDocuments
        self.documentThreshold = Self.unit(documentThreshold)
        self.suggestAutoStacks = suggestAutoStacks
        self.stackTimeWindow = min(
            120,
            max(0.5, stackTimeWindow.isFinite ? stackTimeWindow : 10)
        )
        self.stackSimilarityThreshold = Self.unit(
            stackSimilarityThreshold
        )
    }

    public static let `default` = AssistedCullingCriteria()

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public enum AssistedCullingEyeState:
    String,
    Codable,
    Sendable
{
    case open
    case closed
    case uncertain
    case notDetected

    public var name: String {
        switch self {
        case .open: return "Open"
        case .closed: return "Closed"
        case .uncertain: return "Can't Tell"
        case .notDetected: return "No Eyes"
        }
    }
}

public struct AssistedCullingFaceAnalysis:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public var id: Int
    public var boundingBox: CGRect
    public var eyeSharpness: Double?
    public var eyeOpenness: Double?
    public var eyeState: AssistedCullingEyeState

    public init(
        id: Int,
        boundingBox: CGRect,
        eyeSharpness: Double?,
        eyeOpenness: Double?,
        eyeState: AssistedCullingEyeState
    ) {
        self.id = id
        self.boundingBox = boundingBox
        self.eyeSharpness = eyeSharpness.map(Self.unit)
        self.eyeOpenness = eyeOpenness.map(Self.unit)
        self.eyeState = eyeState
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public struct AssistedCullingAnalysis:
    Codable,
    Equatable,
    Sendable
{
    public static let currentEngineVersion = 1

    public var engineVersion: Int
    public var analyzedAt: Date
    public var subjectDetected: Bool
    public var subjectSharpness: Double
    public var globalSharpness: Double
    public var eyeSharpness: Double?
    public var eyeOpenness: Double?
    public var eyeState: AssistedCullingEyeState
    public var faces: [AssistedCullingFaceAnalysis]
    public var meanLuminance: Double
    public var shadowClipping: Double
    public var highlightClipping: Double
    public var exposureIssueScore: Double
    public var misfireScore: Double
    public var documentScore: Double
    public var textObservationCount: Int
    public var largestRectangleCoverage: Double
    public var visualFingerprint: [Float]
    public var manualDecision: AssistedCullingDecision?

    public init(
        engineVersion: Int = currentEngineVersion,
        analyzedAt: Date = Date(),
        subjectDetected: Bool,
        subjectSharpness: Double,
        globalSharpness: Double,
        eyeSharpness: Double?,
        eyeOpenness: Double?,
        eyeState: AssistedCullingEyeState,
        faces: [AssistedCullingFaceAnalysis],
        meanLuminance: Double,
        shadowClipping: Double,
        highlightClipping: Double,
        exposureIssueScore: Double,
        misfireScore: Double,
        documentScore: Double,
        textObservationCount: Int,
        largestRectangleCoverage: Double,
        visualFingerprint: [Float],
        manualDecision: AssistedCullingDecision? = nil
    ) {
        self.engineVersion = engineVersion
        self.analyzedAt = analyzedAt
        self.subjectDetected = subjectDetected
        self.subjectSharpness = Self.unit(subjectSharpness)
        self.globalSharpness = Self.unit(globalSharpness)
        self.eyeSharpness = eyeSharpness.map(Self.unit)
        self.eyeOpenness = eyeOpenness.map(Self.unit)
        self.eyeState = eyeState
        self.faces = Array(faces.prefix(32))
        self.meanLuminance = Self.unit(meanLuminance)
        self.shadowClipping = Self.unit(shadowClipping)
        self.highlightClipping = Self.unit(highlightClipping)
        self.exposureIssueScore = Self.unit(exposureIssueScore)
        self.misfireScore = Self.unit(misfireScore)
        self.documentScore = Self.unit(documentScore)
        self.textObservationCount = max(0, textObservationCount)
        self.largestRectangleCoverage = Self.unit(
            largestRectangleCoverage
        )
        self.visualFingerprint = Array(
            visualFingerprint.prefix(64)
        ).map {
            Float(Self.unit(Double($0)))
        }
        self.manualDecision =
            manualDecision == .review ? nil : manualDecision
    }

    public var detectedEyeCount: Int {
        faces.reduce(0) {
            $0 + ($1.eyeState == .notDetected ? 0 : 2)
        }
    }

    public func evaluation(
        criteria: AssistedCullingCriteria
    ) -> AssistedCullingEvaluation {
        if let manualDecision, manualDecision != .review {
            return AssistedCullingEvaluation(
                decision: manualDecision,
                reasons: ["Manual \(manualDecision.name.lowercased())"]
            )
        }

        var rejectReasons: [String] = []
        if criteria.rejectExposureIssues,
           exposureIssueScore >= criteria.exposureIssueThreshold {
            rejectReasons.append(
                "Exposure issue \(Self.percent(exposureIssueScore))"
            )
        }
        if criteria.rejectMisfires,
           misfireScore >= criteria.misfireThreshold {
            rejectReasons.append(
                "Likely misfire \(Self.percent(misfireScore))"
            )
        }
        if criteria.rejectDocuments,
           documentScore >= criteria.documentThreshold {
            rejectReasons.append(
                "Document or receipt \(Self.percent(documentScore))"
            )
        }
        if !rejectReasons.isEmpty {
            return AssistedCullingEvaluation(
                decision: .reject,
                reasons: rejectReasons
            )
        }

        var selectedBy: [String] = []
        var failedSelection = false
        if criteria.useSubjectFocus {
            if subjectSharpness >= criteria.subjectFocusThreshold {
                selectedBy.append(
                    "Subject focus \(Self.percent(subjectSharpness))"
                )
            } else {
                failedSelection = true
            }
        }
        if criteria.useEyeFocus {
            if let eyeSharpness {
                if eyeSharpness >= criteria.eyeFocusThreshold {
                    selectedBy.append(
                        "Eye focus \(Self.percent(eyeSharpness))"
                    )
                } else {
                    failedSelection = true
                }
            } else if criteria.requireDetectedEyesForEyeFocus {
                failedSelection = true
            }
        }
        if criteria.useEyesOpen {
            switch eyeState {
            case .open:
                selectedBy.append("Eyes open")
            case .uncertain:
                if criteria.includeUncertainEyes {
                    selectedBy.append("Eyes open: can't tell")
                } else {
                    failedSelection = true
                }
            case .notDetected:
                if criteria.requireDetectedEyesForEyesOpen {
                    failedSelection = true
                }
            case .closed:
                failedSelection = true
            }
        }

        let hasSelectCriteria = criteria.useSubjectFocus
            || criteria.useEyeFocus
            || criteria.useEyesOpen
        if hasSelectCriteria, !failedSelection, !selectedBy.isEmpty {
            return AssistedCullingEvaluation(
                decision: .select,
                reasons: selectedBy
            )
        }
        return AssistedCullingEvaluation(
            decision: .review,
            reasons: ["No enabled Select or Reject rule matched"]
        )
    }

    public var scoreSummary: String {
        var values = [
            "Subject \(Self.percent(subjectSharpness))",
            "Exposure issue \(Self.percent(exposureIssueScore))",
            "Misfire \(Self.percent(misfireScore))",
            "Document \(Self.percent(documentScore))",
        ]
        if let eyeSharpness {
            values.insert(
                "Eye \(Self.percent(eyeSharpness))",
                at: 1
            )
        }
        if eyeState != .notDetected {
            values.append("Eyes \(eyeState.name)")
        }
        return values.joined(separator: " · ")
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((unit(value) * 100).rounded()))%"
    }
}

public struct AssistedCullingEvaluation: Equatable, Sendable {
    public var decision: AssistedCullingDecision
    public var reasons: [String]

    public init(
        decision: AssistedCullingDecision,
        reasons: [String]
    ) {
        self.decision = decision
        self.reasons = reasons
    }

    public var explanation: String {
        reasons.joined(separator: " · ")
    }
}

public struct AssistedCullingProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var filename: String?
    public var analyzedCount: Int
    public var cachedCount: Int
    public var unavailableCount: Int

    public init(
        completed: Int = 0,
        total: Int = 0,
        filename: String? = nil,
        analyzedCount: Int = 0,
        cachedCount: Int = 0,
        unavailableCount: Int = 0
    ) {
        self.completed = completed
        self.total = total
        self.filename = filename
        self.analyzedCount = analyzedCount
        self.cachedCount = cachedCount
        self.unavailableCount = unavailableCount
    }

    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public struct AssistedCullingScanResult: Equatable, Sendable {
    public var analysesByID: [String: AssistedCullingAnalysis]
    public var candidateCount: Int
    public var analyzedCount: Int
    public var cachedCount: Int
    public var unavailablePaths: [String]
    public var suggestedStacks: [[String]]

    public init(
        analysesByID: [String: AssistedCullingAnalysis],
        candidateCount: Int,
        analyzedCount: Int,
        cachedCount: Int,
        unavailablePaths: [String],
        suggestedStacks: [[String]]
    ) {
        self.analysesByID = analysesByID
        self.candidateCount = candidateCount
        self.analyzedCount = analyzedCount
        self.cachedCount = cachedCount
        self.unavailablePaths = unavailablePaths
        self.suggestedStacks = suggestedStacks
    }

    public func counts(
        criteria: AssistedCullingCriteria
    ) -> [AssistedCullingDecision: Int] {
        var result: [AssistedCullingDecision: Int] = [:]
        for analysis in analysesByID.values {
            result[analysis.evaluation(criteria: criteria).decision, default: 0]
                += 1
        }
        return result
    }
}

public struct CatalogCullingCandidate: Equatable, Sendable {
    public var entry: CatalogEntry
    public var cachedAnalysis: AssistedCullingAnalysis?
    public var manualDecision: AssistedCullingDecision?

    public init(
        entry: CatalogEntry,
        cachedAnalysis: AssistedCullingAnalysis?,
        manualDecision: AssistedCullingDecision?
    ) {
        self.entry = entry
        self.cachedAnalysis = cachedAnalysis
        self.manualDecision = manualDecision
    }
}

struct AssistedCullingVisualSignals: Equatable, Sendable {
    var subjectDetected: Bool
    var subjectSharpness: Double
    var globalSharpness: Double
    var faces: [AssistedCullingFaceAnalysis]
    var meanLuminance: Double
    var shadowClipping: Double
    var highlightClipping: Double
    var entropy: Double
    var textObservationCount: Int
    var largestRectangleCoverage: Double
    var visualFingerprint: [Float]
}

enum AssistedCullingSignalInterpreter {
    static func analysis(
        from signals: AssistedCullingVisualSignals,
        analyzedAt: Date = Date(),
        manualDecision: AssistedCullingDecision? = nil
    ) -> AssistedCullingAnalysis {
        let facesWithEyes = signals.faces.filter {
            $0.eyeState != .notDetected
        }
        let eyeSharpness = facesWithEyes
            .compactMap(\.eyeSharpness)
            .min()
        let eyeOpenness = facesWithEyes
            .compactMap(\.eyeOpenness)
            .min()
        let eyeState: AssistedCullingEyeState = {
            guard !facesWithEyes.isEmpty else { return .notDetected }
            if facesWithEyes.contains(where: { $0.eyeState == .closed }) {
                return .closed
            }
            if facesWithEyes.contains(where: {
                $0.eyeState == .uncertain
            }) {
                return .uncertain
            }
            return .open
        }()

        let mean = unit(signals.meanLuminance)
        let shadowClip = unit(signals.shadowClipping)
        let highlightClip = unit(signals.highlightClipping)
        let tonalIssue: Double
        if mean < 0.16 {
            tonalIssue = unit((0.16 - mean) / 0.16)
        } else if mean > 0.86 {
            tonalIssue = unit((mean - 0.86) / 0.14)
        } else {
            tonalIssue = 0
        }
        let clippingIssue = unit(
            (max(shadowClip, highlightClip) - 0.06) / 0.34
        )
        let exposureIssue = max(tonalIssue, clippingIssue)

        let sharpness = unit(signals.subjectSharpness)
        let flatness = unit((0.22 - unit(signals.entropy)) / 0.22)
        let noAnchor = signals.subjectDetected || !signals.faces.isEmpty
            ? 0.0
            : 0.18
        let blurAndFlatness = unit(
            (1 - sharpness) * 0.55 + flatness * 0.35 + noAnchor
        )
        let misfire = max(exposureIssue * 0.88, blurAndFlatness)

        let textScore = unit(Double(signals.textObservationCount) / 7)
        let rectangleScore = unit(
            (signals.largestRectangleCoverage - 0.12) / 0.7
        )
        let document = unit(textScore * 0.68 + rectangleScore * 0.5)

        return AssistedCullingAnalysis(
            analyzedAt: analyzedAt,
            subjectDetected: signals.subjectDetected,
            subjectSharpness: sharpness,
            globalSharpness: signals.globalSharpness,
            eyeSharpness: eyeSharpness,
            eyeOpenness: eyeOpenness,
            eyeState: eyeState,
            faces: signals.faces,
            meanLuminance: mean,
            shadowClipping: shadowClip,
            highlightClipping: highlightClip,
            exposureIssueScore: exposureIssue,
            misfireScore: misfire,
            documentScore: document,
            textObservationCount: signals.textObservationCount,
            largestRectangleCoverage:
                signals.largestRectangleCoverage,
            visualFingerprint: signals.visualFingerprint,
            manualDecision: manualDecision
        )
    }

    private static func unit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public actor AssistedCullingAnalyzer {
    public typealias ProgressHandler =
        @Sendable (AssistedCullingProgress) async -> Void
    public typealias AnalysisProvider =
        @Sendable (PhotoAsset) async throws -> AssistedCullingAnalysis

    private let catalogStore: CatalogStore
    private let analysisProvider: AnalysisProvider

    public init(
        catalogStore: CatalogStore = .shared,
        analysisProvider: AnalysisProvider? = nil
    ) {
        self.catalogStore = catalogStore
        self.analysisProvider = analysisProvider ?? { asset in
            try await Task.detached(priority: .utility) {
                try AssistedCullingImageAnalyzer.analyze(asset: asset)
            }.value
        }
    }

    public func scan(
        forceReanalysis: Bool = false,
        criteria: AssistedCullingCriteria = .default,
        progress: ProgressHandler? = nil
    ) async throws -> AssistedCullingScanResult {
        try catalogStore.refreshMissingStatus()
        let candidates = try catalogStore.cullingAnalysisCandidates(
            engineVersion:
                AssistedCullingAnalysis.currentEngineVersion
        )
        var analysesByID: [String: AssistedCullingAnalysis] = [:]
        var analyzedCount = 0
        var cachedCount = 0
        var unavailablePaths: [String] = []

        await progress?(AssistedCullingProgress(total: candidates.count))

        for (offset, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress?(AssistedCullingProgress(
                completed: offset,
                total: candidates.count,
                filename: candidate.entry.filename,
                analyzedCount: analyzedCount,
                cachedCount: cachedCount,
                unavailableCount: unavailablePaths.count
            ))

            let url = URL(fileURLWithPath: candidate.entry.path)
            guard let before = fileSnapshot(url),
                  before.fileSize == candidate.entry.fileSize,
                  datesMatch(
                      before.modificationDate,
                      candidate.entry.modificationDate
                  ) else {
                try? catalogStore.clearCullingComputedAnalysis(
                    id: candidate.entry.id
                )
                unavailablePaths.append(candidate.entry.path)
                continue
            }

            if var cached = candidate.cachedAnalysis,
               !forceReanalysis {
                cached.manualDecision = candidate.manualDecision
                analysesByID[candidate.entry.id] = cached
                cachedCount += 1
                continue
            }

            do {
                var analysis = try await analysisProvider(
                    candidate.entry.asset
                )
                try Task.checkCancellation()
                analysis.engineVersion =
                    AssistedCullingAnalysis.currentEngineVersion
                analysis.manualDecision = candidate.manualDecision
                guard let after = fileSnapshot(url),
                      after == before,
                      try catalogStore.recordCullingAnalysis(
                          analysis,
                          id: candidate.entry.id,
                          expectedFileSize: candidate.entry.fileSize,
                          expectedModificationDate:
                              candidate.entry.modificationDate
                      ) else {
                    try? catalogStore.clearCullingComputedAnalysis(
                        id: candidate.entry.id
                    )
                    unavailablePaths.append(candidate.entry.path)
                    continue
                }
                analysesByID[candidate.entry.id] = analysis
                analyzedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? catalogStore.clearCullingComputedAnalysis(
                    id: candidate.entry.id
                )
                unavailablePaths.append(candidate.entry.path)
            }
        }

        let stacks = criteria.suggestAutoStacks
            ? Self.suggestedStacks(
                candidates: candidates,
                analysesByID: analysesByID,
                criteria: criteria
            )
            : []
        await progress?(AssistedCullingProgress(
            completed: candidates.count,
            total: candidates.count,
            analyzedCount: analyzedCount,
            cachedCount: cachedCount,
            unavailableCount: unavailablePaths.count
        ))
        return AssistedCullingScanResult(
            analysesByID: analysesByID,
            candidateCount: candidates.count,
            analyzedCount: analyzedCount,
            cachedCount: cachedCount,
            unavailablePaths: unavailablePaths,
            suggestedStacks: stacks
        )
    }

    static func suggestedStacks(
        candidates: [CatalogCullingCandidate],
        analysesByID: [String: AssistedCullingAnalysis],
        criteria: AssistedCullingCriteria
    ) -> [[String]] {
        suggestedStacks(
            assets: candidates.map(\.entry.asset),
            analysesByID: analysesByID,
            criteria: criteria
        )
    }

    static func suggestedStacks(
        assets: [PhotoAsset],
        analysesByID: [String: AssistedCullingAnalysis],
        criteria: AssistedCullingCriteria
    ) -> [[String]] {
        guard criteria.suggestAutoStacks else { return [] }
        var groups: [[String]] = []
        let eligible = assets.filter {
            analysesByID[$0.id] != nil
        }
        let byFolder = Dictionary(grouping: eligible) {
            $0.url.deletingLastPathComponent()
                .standardizedFileURL.path
        }

        for folder in byFolder.keys.sorted() {
            let ordered = (byFolder[folder] ?? []).sorted {
                let lhs = $0.metadata?.captureDate
                    ?? $0.modificationDate
                    ?? .distantPast
                let rhs = $1.metadata?.captureDate
                    ?? $1.modificationDate
                    ?? .distantPast
                if lhs != rhs { return lhs < rhs }
                return $0.path.localizedStandardCompare(
                    $1.path
                ) == .orderedAscending
            }

            var current: [PhotoAsset] = []
            for asset in ordered {
                guard let previous = current.last else {
                    current = [asset]
                    continue
                }
                let previousDate = previous.metadata?.captureDate
                    ?? previous.modificationDate
                let currentDate = asset.metadata?.captureDate
                    ?? asset.modificationDate
                let timeDistance: TimeInterval
                if let previousDate, let currentDate {
                    timeDistance = abs(
                        currentDate.timeIntervalSince(previousDate)
                    )
                } else {
                    timeDistance = .infinity
                }
                let distance = fingerprintDistance(
                    analysesByID[previous.id]?.visualFingerprint ?? [],
                    analysesByID[asset.id]?.visualFingerprint ?? []
                )
                if timeDistance <= criteria.stackTimeWindow,
                   distance <= criteria.stackSimilarityThreshold {
                    current.append(asset)
                } else {
                    appendSuggestedStack(
                        current,
                        analysesByID: analysesByID,
                        criteria: criteria,
                        to: &groups
                    )
                    current = [asset]
                }
            }
            appendSuggestedStack(
                current,
                analysesByID: analysesByID,
                criteria: criteria,
                to: &groups
            )
        }
        return groups
    }

    private static func appendSuggestedStack(
        _ assets: [PhotoAsset],
        analysesByID: [String: AssistedCullingAnalysis],
        criteria: AssistedCullingCriteria,
        to groups: inout [[String]]
    ) {
        guard assets.count > 1 else { return }
        let ranked = assets.sorted { lhs, rhs in
            guard let lhsAnalysis = analysesByID[lhs.id],
                  let rhsAnalysis = analysesByID[rhs.id] else {
                return lhs.path.localizedStandardCompare(rhs.path)
                    == .orderedAscending
            }
            let lhsDecision = lhsAnalysis.evaluation(
                criteria: criteria
            ).decision
            let rhsDecision = rhsAnalysis.evaluation(
                criteria: criteria
            ).decision
            let lhsPriority = stackDecisionPriority(lhsDecision)
            let rhsPriority = stackDecisionPriority(rhsDecision)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            let lhsQuality = stackQuality(lhsAnalysis)
            let rhsQuality = stackQuality(rhsAnalysis)
            if lhsQuality != rhsQuality {
                return lhsQuality > rhsQuality
            }
            return lhs.path.localizedStandardCompare(rhs.path)
                == .orderedAscending
        }
        groups.append(ranked.map(\.id))
    }

    private static func stackDecisionPriority(
        _ decision: AssistedCullingDecision
    ) -> Int {
        switch decision {
        case .select: return 0
        case .review: return 1
        case .reject: return 2
        }
    }

    private static func stackQuality(
        _ analysis: AssistedCullingAnalysis
    ) -> Double {
        analysis.subjectSharpness
            + (analysis.eyeSharpness ?? analysis.globalSharpness) * 0.45
            + analysis.globalSharpness * 0.2
            - analysis.exposureIssueScore * 0.55
            - analysis.misfireScore * 0.7
            - analysis.documentScore * 0.2
    }

    static func fingerprintDistance(
        _ lhs: [Float],
        _ rhs: [Float]
    ) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else {
            return .infinity
        }
        let squared = zip(lhs, rhs).reduce(0.0) { partial, pair in
            let delta = Double(pair.0 - pair.1)
            return partial + delta * delta
        }
        return sqrt(squared / Double(lhs.count))
    }

    private struct FileSnapshot: Equatable {
        var fileSize: Int64
        var modificationDate: Date?
    }

    private func fileSnapshot(_ url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
        ]), values.isRegularFile == true else {
            return nil
        }
        return FileSnapshot(
            fileSize: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate
        )
    }

    private func datesMatch(_ lhs: Date?, _ rhs: Date?) -> Bool {
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

private enum AssistedCullingImageAnalyzer {
    private static let analysisLimit: CGFloat = 1_024

    static func analyze(asset: PhotoAsset) throws
        -> AssistedCullingAnalysis {
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
            throw SubjectMaskGenerator.GenerationError.imageHasNoBitmap
        }
        return try analyze(cgImage: cgImage)
    }

    static func analyze(cgImage: CGImage) throws
        -> AssistedCullingAnalysis {
        let gray = try GrayPlane(cgImage: cgImage)
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: .up,
            options: [:]
        )

        let faceRequest = VNDetectFaceLandmarksRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 8
        rectangleRequest.minimumConfidence = 0.55
        rectangleRequest.minimumSize = 0.18
        rectangleRequest.quadratureTolerance = 25
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.025
        try handler.perform([
            faceRequest,
            rectangleRequest,
            textRequest,
        ])

        var subjectMask: MaskPlane?
        let foregroundRequest = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([foregroundRequest])
            if let observation = foregroundRequest.results?.first,
               !observation.allInstances.isEmpty {
                let buffer = try observation.generateScaledMaskForImage(
                    forInstances: observation.allInstances,
                    from: handler
                )
                subjectMask = try? MaskPlane(pixelBuffer: buffer)
            }
        } catch {
            subjectMask = nil
        }

        let faces = faceAnalyses(
            observations: faceRequest.results ?? [],
            gray: gray
        )
        let globalSharpness = gray.sharpness()
        let subjectSharpness = subjectMask.map {
            gray.sharpness(mask: $0)
        } ?? globalSharpness
        let exposure = gray.exposureStatistics()
        let largestRectangleCoverage = (
            rectangleRequest.results ?? []
        ).map {
            Double($0.boundingBox.width * $0.boundingBox.height)
        }.max() ?? 0

        let signals = AssistedCullingVisualSignals(
            subjectDetected: subjectMask != nil,
            subjectSharpness: subjectSharpness,
            globalSharpness: globalSharpness,
            faces: faces,
            meanLuminance: exposure.mean,
            shadowClipping: exposure.shadowClipping,
            highlightClipping: exposure.highlightClipping,
            entropy: exposure.entropy,
            textObservationCount: textRequest.results?.count ?? 0,
            largestRectangleCoverage: largestRectangleCoverage,
            visualFingerprint: gray.fingerprint()
        )
        return AssistedCullingSignalInterpreter.analysis(from: signals)
    }

    private static func faceAnalyses(
        observations: [VNFaceObservation],
        gray: GrayPlane
    ) -> [AssistedCullingFaceAnalysis] {
        observations.prefix(32).enumerated().map { offset, face in
            let eyes = [
                face.landmarks?.leftEye,
                face.landmarks?.rightEye,
            ].compactMap { $0 }
            let eyeRects = eyes.compactMap {
                normalizedEyeRect(region: $0, face: face)
            }
            let sharpnessValues = eyeRects.map {
                gray.sharpness(normalizedVisionRect: $0)
            }
            let opennessValues = eyes.compactMap {
                eyeOpenness(region: $0)
            }
            let sharpness = sharpnessValues.isEmpty
                ? nil
                : sharpnessValues.min()
            let openness = opennessValues.isEmpty
                ? nil
                : opennessValues.min()
            let state: AssistedCullingEyeState
            if let openness {
                if openness >= 0.58 {
                    state = .open
                } else if openness <= 0.32 {
                    state = .closed
                } else {
                    state = .uncertain
                }
            } else {
                state = .notDetected
            }
            return AssistedCullingFaceAnalysis(
                id: offset + 1,
                boundingBox: face.boundingBox,
                eyeSharpness: sharpness,
                eyeOpenness: openness,
                eyeState: state
            )
        }
    }

    private static func normalizedEyeRect(
        region: VNFaceLandmarkRegion2D,
        face: VNFaceObservation
    ) -> CGRect? {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return nil }
        let global = points.map {
            CGPoint(
                x: face.boundingBox.minX
                    + CGFloat($0.x) * face.boundingBox.width,
                y: face.boundingBox.minY
                    + CGFloat($0.y) * face.boundingBox.height
            )
        }
        guard let minX = global.map(\.x).min(),
              let maxX = global.map(\.x).max(),
              let minY = global.map(\.y).min(),
              let maxY = global.map(\.y).max() else {
            return nil
        }
        let width = max(0.015, maxX - minX)
        let height = max(0.012, maxY - minY)
        let padX = width * 0.85
        let padY = max(height * 1.8, width * 0.45)
        return CGRect(
            x: max(0, minX - padX),
            y: max(0, minY - padY),
            width: min(1, maxX + padX) - max(0, minX - padX),
            height: min(1, maxY + padY) - max(0, minY - padY)
        )
    }

    private static func eyeOpenness(
        region: VNFaceLandmarkRegion2D
    ) -> Double? {
        let points = region.normalizedPoints
        guard points.count >= 4,
              let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else {
            return nil
        }
        let width = Double(maxX - minX)
        let height = Double(maxY - minY)
        guard width > 0.0001 else { return nil }
        let aspect = height / width
        return min(1, max(0, (aspect - 0.07) / 0.18))
    }
}

private struct GrayPlane {
    struct ExposureStatistics {
        var mean: Double
        var shadowClipping: Double
        var highlightClipping: Double
        var entropy: Double
    }

    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(cgImage: CGImage) throws {
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        guard imageWidth > 2, imageHeight > 2 else {
            throw SubjectMaskGenerator.GenerationError.imageHasNoBitmap
        }
        var storage = [UInt8](
            repeating: 0,
            count: imageWidth * imageHeight
        )
        let rendered = storage.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.translateBy(x: 0, y: CGFloat(imageHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                cgImage,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: imageWidth,
                    height: imageHeight
                )
            )
            return true
        }
        guard rendered else {
            throw SubjectMaskGenerator.GenerationError.imageHasNoBitmap
        }
        width = imageWidth
        height = imageHeight
        pixels = storage
    }

    func sharpness(
        mask: MaskPlane? = nil,
        normalizedVisionRect: CGRect? = nil
    ) -> Double {
        let rect = pixelRect(from: normalizedVisionRect)
        let step = max(1, max(width, height) / 640)
        var magnitude = 0.0
        var count = 0
        var y = max(1, rect.minY)
        while y < min(height - 1, rect.maxY) {
            var x = max(1, rect.minX)
            while x < min(width - 1, rect.maxX) {
                if mask?.contains(
                    x: x,
                    y: y,
                    sourceWidth: width,
                    sourceHeight: height
                ) ?? true {
                    let center = Int(pixels[y * width + x])
                    let value = abs(
                        center * 4
                            - Int(pixels[y * width + x - 1])
                            - Int(pixels[y * width + x + 1])
                            - Int(pixels[(y - 1) * width + x])
                            - Int(pixels[(y + 1) * width + x])
                    )
                    magnitude += Double(value)
                    count += 1
                }
                x += step
            }
            y += step
        }
        guard count > 0 else { return 0 }
        let mean = magnitude / Double(count)
        return min(1, max(0, log1p(mean) / log1p(28)))
    }

    func exposureStatistics() -> ExposureStatistics {
        let step = max(1, max(width, height) / 768)
        var histogram = [Int](repeating: 0, count: 256)
        var sum = 0.0
        var count = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let value = Int(pixels[y * width + x])
                histogram[value] += 1
                sum += Double(value)
                count += 1
                x += step
            }
            y += step
        }
        guard count > 0 else {
            return ExposureStatistics(
                mean: 0,
                shadowClipping: 0,
                highlightClipping: 0,
                entropy: 0
            )
        }
        var entropy = 0.0
        for bucket in histogram where bucket > 0 {
            let probability = Double(bucket) / Double(count)
            entropy -= probability * log2(probability)
        }
        return ExposureStatistics(
            mean: sum / Double(count) / 255,
            shadowClipping:
                Double(histogram[0...3].reduce(0, +)) / Double(count),
            highlightClipping:
                Double(histogram[252...255].reduce(0, +)) / Double(count),
            entropy: min(1, max(0, entropy / 8))
        )
    }

    func fingerprint() -> [Float] {
        let grid = 8
        var result: [Float] = []
        result.reserveCapacity(grid * grid)
        for row in 0..<grid {
            for column in 0..<grid {
                let minX = column * width / grid
                let maxX = max(minX + 1, (column + 1) * width / grid)
                let minY = row * height / grid
                let maxY = max(minY + 1, (row + 1) * height / grid)
                let step = max(
                    1,
                    max(maxX - minX, maxY - minY) / 24
                )
                var sum = 0
                var count = 0
                var y = minY
                while y < min(height, maxY) {
                    var x = minX
                    while x < min(width, maxX) {
                        sum += Int(pixels[y * width + x])
                        count += 1
                        x += step
                    }
                    y += step
                }
                result.append(
                    count > 0
                        ? Float(Double(sum) / Double(count) / 255)
                        : 0
                )
            }
        }
        return result
    }

    private func pixelRect(
        from normalizedVisionRect: CGRect?
    ) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        guard let rect = normalizedVisionRect else {
            return (0, width, 0, height)
        }
        let minX = Int((rect.minX * CGFloat(width)).rounded(.down))
        let maxX = Int((rect.maxX * CGFloat(width)).rounded(.up))
        let minY = Int(
            ((1 - rect.maxY) * CGFloat(height)).rounded(.down)
        )
        let maxY = Int(
            ((1 - rect.minY) * CGFloat(height)).rounded(.up)
        )
        return (
            min(width, max(0, minX)),
            min(width, max(0, maxX)),
            min(height, max(0, minY)),
            min(height, max(0, maxY))
        )
    }
}

private struct MaskPlane {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    init(pixelBuffer: CVPixelBuffer) throws {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer)
                == kCVPixelFormatType_OneComponent8,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                == kCVReturnSuccess else {
            throw SubjectMaskGenerator.GenerationError
                .unsupportedInstanceMaskFormat
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        width = CVPixelBufferGetWidth(pixelBuffer)
        height = CVPixelBufferGetHeight(pixelBuffer)
        bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              width > 0,
              height > 0 else {
            throw SubjectMaskGenerator.GenerationError.maskRenderingFailed
        }
        pixels = Array(
            UnsafeBufferPointer(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: bytesPerRow * height
            )
        )
    }

    func contains(
        x: Int,
        y: Int,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> Bool {
        let mappedX = min(
            width - 1,
            max(0, x * width / max(1, sourceWidth))
        )
        let mappedY = min(
            height - 1,
            max(0, y * height / max(1, sourceHeight))
        )
        return pixels[mappedY * bytesPerRow + mappedX] >= 128
    }
}
