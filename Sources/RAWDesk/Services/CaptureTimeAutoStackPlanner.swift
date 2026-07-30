import Foundation

public struct CaptureTimeAutoStackGroup:
    Equatable, Sendable
{
    public var scopePath: String
    public var memberIDs: [PhotoAsset.ID]
    public var firstCaptureDate: Date
    public var lastCaptureDate: Date

    public var photoCount: Int {
        memberIDs.count
    }

    public init(
        scopePath: String,
        memberIDs: [PhotoAsset.ID],
        firstCaptureDate: Date,
        lastCaptureDate: Date
    ) {
        self.scopePath = URL(
            fileURLWithPath: scopePath,
            isDirectory: true
        ).standardizedFileURL.path
        self.memberIDs = memberIDs
        self.firstCaptureDate = firstCaptureDate
        self.lastCaptureDate = lastCaptureDate
    }
}

public struct CaptureTimeAutoStackPreview:
    Equatable, Sendable
{
    public var maximumGap: TimeInterval
    public var scopePhotoCount: Int
    public var eligiblePhotoCount: Int
    public var alreadyStackedPhotoCount: Int
    public var missingCaptureTimePhotoCount: Int
    public var unavailablePhotoCount: Int
    public var groups: [CaptureTimeAutoStackGroup]

    public var stackCount: Int {
        groups.count
    }

    public var groupedPhotoCount: Int {
        groups.reduce(0) { $0 + $1.photoCount }
    }

    public var ungroupedEligiblePhotoCount: Int {
        max(0, eligiblePhotoCount - groupedPhotoCount)
    }

    public var photoIDGroups: [[PhotoAsset.ID]] {
        groups.map(\.memberIDs)
    }

    public init(
        maximumGap: TimeInterval,
        scopePhotoCount: Int,
        eligiblePhotoCount: Int,
        alreadyStackedPhotoCount: Int,
        missingCaptureTimePhotoCount: Int,
        unavailablePhotoCount: Int,
        groups: [CaptureTimeAutoStackGroup]
    ) {
        self.maximumGap = CaptureTimeAutoStackPlanner.normalizedGap(
            maximumGap
        )
        self.scopePhotoCount = scopePhotoCount
        self.eligiblePhotoCount = eligiblePhotoCount
        self.alreadyStackedPhotoCount = alreadyStackedPhotoCount
        self.missingCaptureTimePhotoCount =
            missingCaptureTimePhotoCount
        self.unavailablePhotoCount = unavailablePhotoCount
        self.groups = groups
    }
}

public enum CaptureTimeAutoStackPlanner {
    public static let maximumSupportedGap: TimeInterval = 60 * 60

    public static func normalizedGap(
        _ gap: TimeInterval
    ) -> TimeInterval {
        guard gap.isFinite else { return 0 }
        return min(maximumSupportedGap, max(0, gap))
    }

    /// Produces a Lightroom-style contiguous capture-time preview.
    ///
    /// Photos are ordered by capture time within their actual parent folder.
    /// A photo joins the current group when its capture time is no more than
    /// `maximumGap` after the previous photo. Existing stacks are deliberately
    /// excluded so a preview can never imply that user-authored organization
    /// will be replaced.
    public static func preview(
        assets: [PhotoAsset],
        existingStacks: [CatalogPhotoStack],
        maximumGap: TimeInterval
    ) -> CaptureTimeAutoStackPreview {
        let gap = normalizedGap(maximumGap)
        let stackedIDs = Set(existingStacks.flatMap(\.memberIDs))
        var candidatesByFolder:
            [String: [(asset: PhotoAsset, captureDate: Date)]] = [:]
        var alreadyStackedPhotoCount = 0
        var missingCaptureTimePhotoCount = 0
        var unavailablePhotoCount = 0

        for asset in assets {
            guard !asset.catalogMissing else {
                unavailablePhotoCount += 1
                continue
            }
            guard !stackedIDs.contains(asset.id) else {
                alreadyStackedPhotoCount += 1
                continue
            }
            guard let captureDate = asset.metadata?.captureDate else {
                missingCaptureTimePhotoCount += 1
                continue
            }
            let scopePath = asset.url
                .deletingLastPathComponent()
                .standardizedFileURL.path
            candidatesByFolder[scopePath, default: []].append(
                (asset, captureDate)
            )
        }

        let eligiblePhotoCount = candidatesByFolder.values.reduce(0) {
            $0 + $1.count
        }
        var groups: [CaptureTimeAutoStackGroup] = []

        for scopePath in candidatesByFolder.keys.sorted(
            by: {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        ) {
            guard let folderCandidates =
                    candidatesByFolder[scopePath] else {
                continue
            }
            let ordered = folderCandidates.sorted { lhs, rhs in
                if lhs.captureDate != rhs.captureDate {
                    return lhs.captureDate < rhs.captureDate
                }
                let pathOrder = lhs.asset.path.localizedStandardCompare(
                    rhs.asset.path
                )
                if pathOrder != .orderedSame {
                    return pathOrder == .orderedAscending
                }
                return lhs.asset.id < rhs.asset.id
            }
            guard let first = ordered.first else { continue }

            var run = [first]
            var previousDate = first.captureDate

            func appendRunIfNeeded() {
                guard run.count >= 2,
                      let runFirst = run.first,
                      let runLast = run.last else {
                    return
                }
                groups.append(
                    CaptureTimeAutoStackGroup(
                        scopePath: scopePath,
                        memberIDs: run.map { $0.asset.id },
                        firstCaptureDate: runFirst.captureDate,
                        lastCaptureDate: runLast.captureDate
                    )
                )
            }

            for candidate in ordered.dropFirst() {
                let interval = candidate.captureDate
                    .timeIntervalSince(previousDate)
                if interval <= gap {
                    run.append(candidate)
                } else {
                    appendRunIfNeeded()
                    run = [candidate]
                }
                previousDate = candidate.captureDate
            }
            appendRunIfNeeded()
        }

        return CaptureTimeAutoStackPreview(
            maximumGap: gap,
            scopePhotoCount: assets.count,
            eligiblePhotoCount: eligiblePhotoCount,
            alreadyStackedPhotoCount: alreadyStackedPhotoCount,
            missingCaptureTimePhotoCount:
                missingCaptureTimePhotoCount,
            unavailablePhotoCount: unavailablePhotoCount,
            groups: groups
        )
    }
}
