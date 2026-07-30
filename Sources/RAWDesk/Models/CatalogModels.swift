import Foundation

public enum CatalogSmartCollection: String, CaseIterable, Codable, Identifiable, Sendable {
    case allPhotos
    case recentlyAdded
    case quickCollection
    case edited
    case fiveStars
    case picked
    case rejected
    case withKeywords
    case withLocation
    case withoutLocation
    case assistedCulling
    case exactDuplicates
    case missingFiles

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .allPhotos: return "All Photographs"
        case .recentlyAdded: return "Recently Added"
        case .quickCollection: return "Quick Collection"
        case .edited: return "Edited"
        case .fiveStars: return "Five Stars"
        case .picked: return "Picked"
        case .rejected: return "Rejected"
        case .withKeywords: return "With Keywords"
        case .withLocation: return "With Location"
        case .withoutLocation: return "Without Location"
        case .assistedCulling: return "Assisted Culling"
        case .exactDuplicates: return "Duplicates"
        case .missingFiles: return "Missing Files"
        }
    }

    public var systemImage: String {
        switch self {
        case .allPhotos: return "rectangle.stack"
        case .recentlyAdded: return "clock"
        case .quickCollection: return "bolt.circle"
        case .edited: return "slider.horizontal.3"
        case .fiveStars: return "star.fill"
        case .picked: return "flag.fill"
        case .rejected: return "xmark.circle"
        case .withKeywords: return "tag"
        case .withLocation: return "mappin.and.ellipse"
        case .withoutLocation: return "mappin.slash"
        case .assistedCulling: return "checkmark.seal"
        case .exactDuplicates: return "square.on.square"
        case .missingFiles: return "questionmark.folder"
        }
    }

    public func contains(_ asset: PhotoAsset) -> Bool {
        switch self {
        case .allPhotos, .recentlyAdded:
            return !asset.catalogMissing
        case .quickCollection:
            // Membership depends on the catalog relation rather than
            // an individual photo field and is resolved by CatalogStore.
            return true
        case .missingFiles:
            return asset.catalogMissing
        case .edited:
            return !asset.catalogMissing
                && !asset.userState.adjustments.isNeutral
        case .fiveStars:
            return !asset.catalogMissing && asset.userState.rating >= 5
        case .picked:
            return !asset.catalogMissing
                && asset.userState.pickStatus == .picked
        case .rejected:
            return !asset.catalogMissing
                && asset.userState.pickStatus == .rejected
        case .withKeywords:
            return !asset.catalogMissing
                && !asset.userState.keywords.isEmpty
        case .withLocation:
            return !asset.catalogMissing
                && asset.effectiveLocation != nil
        case .withoutLocation:
            return !asset.catalogMissing
                && asset.effectiveLocation == nil
        case .assistedCulling:
            return !asset.catalogMissing
        case .exactDuplicates:
            // Duplicate membership depends on other catalog rows and is
            // therefore determined by CatalogStore's grouped query.
            return !asset.catalogMissing
        }
    }
}

public struct CatalogSummary: Equatable, Sendable {
    public var counts: [CatalogSmartCollection: Int]
    public var keywordCounts: [String: Int]
    public var colorLabelCounts: [PhotoColorLabel: Int]
    public var rootCount: Int
    public var databaseBytes: Int64
    public var exactDuplicateGroupCount: Int
    public var duplicateReclaimableBytes: Int64
    public var hashedPhotoCount: Int
    public var photoStackCount: Int
    public var stackedPhotoCount: Int
    public var peopleCount: Int
    public var faceCount: Int
    public var unconfirmedFaceCount: Int

    public init(
        counts: [CatalogSmartCollection: Int] = [:],
        keywordCounts: [String: Int] = [:],
        colorLabelCounts: [PhotoColorLabel: Int] = [:],
        rootCount: Int = 0,
        databaseBytes: Int64 = 0,
        exactDuplicateGroupCount: Int = 0,
        duplicateReclaimableBytes: Int64 = 0,
        hashedPhotoCount: Int = 0,
        photoStackCount: Int = 0,
        stackedPhotoCount: Int = 0,
        peopleCount: Int = 0,
        faceCount: Int = 0,
        unconfirmedFaceCount: Int = 0
    ) {
        self.counts = counts
        self.keywordCounts = keywordCounts
        self.colorLabelCounts = colorLabelCounts
        self.rootCount = rootCount
        self.databaseBytes = databaseBytes
        self.exactDuplicateGroupCount = exactDuplicateGroupCount
        self.duplicateReclaimableBytes = duplicateReclaimableBytes
        self.hashedPhotoCount = hashedPhotoCount
        self.photoStackCount = photoStackCount
        self.stackedPhotoCount = stackedPhotoCount
        self.peopleCount = peopleCount
        self.faceCount = faceCount
        self.unconfirmedFaceCount = unconfirmedFaceCount
    }

    public subscript(_ collection: CatalogSmartCollection) -> Int {
        counts[collection] ?? 0
    }

    public var keywordTree: [KeywordSummaryNode] {
        KeywordSummaryNode.makeTree(from: keywordCounts)
    }
}

public struct CatalogExactDuplicateMember:
    Equatable, Identifiable, Sendable
{
    public var id: String
    public var path: String
    public var filename: String
    public var fileSize: Int64
    public var indexedAt: Date

    public init(
        id: String,
        path: String,
        filename: String,
        fileSize: Int64,
        indexedAt: Date
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.fileSize = fileSize
        self.indexedAt = indexedAt
    }
}

public enum CatalogDuplicateMatchBasis:
    String, Equatable, Sendable
{
    case imageData
    case wholeFile

    public var name: String {
        switch self {
        case .imageData:
            return "Image data"
        case .wholeFile:
            return "Whole file fallback"
        }
    }
}

public struct CatalogExactDuplicateGroup:
    Equatable, Identifiable, Sendable
{
    public var contentHash: String
    public var matchBasis: CatalogDuplicateMatchBasis
    public var members: [CatalogExactDuplicateMember]

    public var id: String {
        "\(matchBasis.rawValue):\(contentHash)"
    }
    public var anchorID: String? { members.first?.id }
    public var fileSize: Int64 { members.first?.fileSize ?? 0 }
    public var duplicateCopyCount: Int { max(0, members.count - 1) }
    public var reclaimableBytes: Int64 {
        members.dropFirst().reduce(0) {
            $0 + max(0, $1.fileSize)
        }
    }

    public init(
        contentHash: String,
        matchBasis: CatalogDuplicateMatchBasis = .wholeFile,
        members: [CatalogExactDuplicateMember]
    ) {
        self.contentHash = contentHash
        self.matchBasis = matchBasis
        self.members = members.sorted {
            if $0.indexedAt != $1.indexedAt {
                return $0.indexedAt < $1.indexedAt
            }
            return $0.path.localizedStandardCompare($1.path)
                == .orderedAscending
        }
    }
}

public struct CatalogPhotoStack:
    Equatable, Identifiable, Sendable
{
    public var id: UUID
    public var scopePath: String
    public var memberIDs: [PhotoAsset.ID]
    public var isCollapsed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public var topPhotoID: PhotoAsset.ID? {
        memberIDs.first
    }

    public var photoCount: Int {
        memberIDs.count
    }

    public init(
        id: UUID = UUID(),
        scopePath: String,
        memberIDs: [PhotoAsset.ID],
        isCollapsed: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.scopePath = URL(
            fileURLWithPath: scopePath,
            isDirectory: true
        ).standardizedFileURL.path
        var seen: Set<PhotoAsset.ID> = []
        self.memberIDs = memberIDs.filter {
            seen.insert($0).inserted
        }
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func membership(
        for photoID: PhotoAsset.ID
    ) -> CatalogPhotoStackMembership? {
        guard let index = memberIDs.firstIndex(of: photoID) else {
            return nil
        }
        return CatalogPhotoStackMembership(
            stackID: id,
            position: index + 1,
            photoCount: memberIDs.count,
            isTop: index == 0,
            isCollapsed: isCollapsed
        )
    }
}

public struct CatalogPhotoStackMembership:
    Equatable, Sendable
{
    public var stackID: UUID
    public var position: Int
    public var photoCount: Int
    public var isTop: Bool
    public var isCollapsed: Bool

    public init(
        stackID: UUID,
        position: Int,
        photoCount: Int,
        isTop: Bool,
        isCollapsed: Bool
    ) {
        self.stackID = stackID
        self.position = position
        self.photoCount = photoCount
        self.isTop = isTop
        self.isCollapsed = isCollapsed
    }
}

public enum CatalogPhotoStackMove: Sendable {
    case top
    case up
    case down
}

public struct CatalogDuplicateScanProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var filename: String?
    public var newlyHashedCount: Int
    public var cachedHashCount: Int
    public var unavailableCount: Int

    public init(
        completed: Int = 0,
        total: Int = 0,
        filename: String? = nil,
        newlyHashedCount: Int = 0,
        cachedHashCount: Int = 0,
        unavailableCount: Int = 0
    ) {
        self.completed = completed
        self.total = total
        self.filename = filename
        self.newlyHashedCount = newlyHashedCount
        self.cachedHashCount = cachedHashCount
        self.unavailableCount = unavailableCount
    }

    public var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public struct CatalogDuplicateScanResult: Equatable, Sendable {
    public var groups: [CatalogExactDuplicateGroup]
    public var candidateCount: Int
    public var newlyHashedCount: Int
    public var cachedHashCount: Int
    public var unavailablePaths: [String]

    public init(
        groups: [CatalogExactDuplicateGroup],
        candidateCount: Int,
        newlyHashedCount: Int,
        cachedHashCount: Int,
        unavailablePaths: [String]
    ) {
        self.groups = groups
        self.candidateCount = candidateCount
        self.newlyHashedCount = newlyHashedCount
        self.cachedHashCount = cachedHashCount
        self.unavailablePaths = unavailablePaths
    }

    public var groupedPhotoCount: Int {
        groups.reduce(0) { $0 + $1.members.count }
    }

    public var duplicateCopyCount: Int {
        groups.reduce(0) { $0 + $1.duplicateCopyCount }
    }

    public var reclaimableBytes: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var imageDataGroupCount: Int {
        groups.count {
            $0.matchBasis == .imageData
        }
    }

    public var wholeFileFallbackGroupCount: Int {
        groups.count {
            $0.matchBasis == .wholeFile
        }
    }
}

public struct KeywordSummaryNode: Equatable, Identifiable, Sendable {
    public var path: String
    public var name: String
    public var directCount: Int
    public var count: Int
    public var children: [KeywordSummaryNode]

    public var id: String { path }

    public var outlineChildren: [KeywordSummaryNode]? {
        children.isEmpty ? nil : children
    }

    public static func makeTree(
        from keywordCounts: [String: Int]
    ) -> [KeywordSummaryNode] {
        let root = MutableKeywordNode(name: "", path: "")
        for (keyword, count) in keywordCounts {
            let segments = PhotoUserState.keywordSegments(in: keyword)
            guard !segments.isEmpty else { continue }
            var current = root
            var pathSegments: [String] = []
            for segment in segments {
                pathSegments.append(segment)
                let path = pathSegments.joined(
                    separator: PhotoUserState.keywordPathSeparator
                )
                let folded = segment.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                if let existing = current.children[folded] {
                    current = existing
                } else {
                    let child = MutableKeywordNode(
                        name: segment,
                        path: path
                    )
                    current.children[folded] = child
                    current = child
                }
            }
            current.directCount += count
        }
        return root.children.values
            .map(\.immutable)
            .sorted(by: sortNodes)
    }

    private static func sortNodes(
        _ lhs: KeywordSummaryNode,
        _ rhs: KeywordSummaryNode
    ) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            == .orderedAscending
    }
}

public enum CatalogKeywordChange: Equatable, Sendable {
    case rename(sourcePath: String, newName: String)
    case moveOrMerge(sourcePath: String, destinationPath: String)
    case delete(sourcePath: String)

    public var sourcePath: String {
        switch self {
        case let .rename(sourcePath, _),
             let .moveOrMerge(sourcePath, _),
             let .delete(sourcePath):
            return sourcePath
        }
    }

    public var actionName: String {
        switch self {
        case .rename:
            return "renamed"
        case .moveOrMerge:
            return "moved or merged"
        case .delete:
            return "removed"
        }
    }
}

public struct CatalogKeywordChangePreview: Equatable, Sendable {
    public var sourcePath: String
    public var destinationPath: String?
    public var affectedPhotoCount: Int
    public var affectedKeywordAssignmentCount: Int
    public var affectedKeywordPathCount: Int
    public var missingPhotoCount: Int
    public var mergedAssignmentCount: Int
    public var affectedSmartCollectionCount: Int
    public var affectedDefinitionCount: Int

    public init(
        sourcePath: String,
        destinationPath: String?,
        affectedPhotoCount: Int,
        affectedKeywordAssignmentCount: Int,
        affectedKeywordPathCount: Int,
        missingPhotoCount: Int,
        mergedAssignmentCount: Int,
        affectedSmartCollectionCount: Int,
        affectedDefinitionCount: Int
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.affectedPhotoCount = affectedPhotoCount
        self.affectedKeywordAssignmentCount =
            affectedKeywordAssignmentCount
        self.affectedKeywordPathCount = affectedKeywordPathCount
        self.missingPhotoCount = missingPhotoCount
        self.mergedAssignmentCount = mergedAssignmentCount
        self.affectedSmartCollectionCount =
            affectedSmartCollectionCount
        self.affectedDefinitionCount = affectedDefinitionCount
    }
}

public struct CatalogKeywordDefinition: Equatable, Sendable {
    public var path: String
    public var synonyms: [String]
    public var includeOnExport: Bool
    public var exportSynonyms: Bool
    public var exportContainingKeywords: Bool

    public init(
        path: String,
        synonyms: [String] = [],
        includeOnExport: Bool = true,
        exportSynonyms: Bool = true,
        exportContainingKeywords: Bool = false
    ) {
        let normalizedPath =
            PhotoUserState.normalizedKeywordPath(path) ?? ""
        let leafFolded = PhotoUserState.foldedKeyword(
            PhotoUserState.keywordLeaf(normalizedPath)
        )
        self.path = normalizedPath
        self.synonyms = PhotoUserState.normalizedKeywordSynonyms(
            synonyms
        ).filter {
            PhotoUserState.foldedKeyword($0) != leafFolded
        }
        self.includeOnExport = includeOnExport
        self.exportSynonyms = exportSynonyms
        self.exportContainingKeywords = exportContainingKeywords
    }
}

public struct CatalogKeywordChangeResult: Equatable, Sendable {
    public var preview: CatalogKeywordChangePreview
    public var updatedStates: [String: PhotoUserState]
    public var savedSmartCollections: [SavedSmartCollection]

    public init(
        preview: CatalogKeywordChangePreview,
        updatedStates: [String: PhotoUserState],
        savedSmartCollections: [SavedSmartCollection]
    ) {
        self.preview = preview
        self.updatedStates = updatedStates
        self.savedSmartCollections = savedSmartCollections
    }
}

private final class MutableKeywordNode {
    var name: String
    var path: String
    var directCount = 0
    var children: [String: MutableKeywordNode] = [:]

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    var immutable: KeywordSummaryNode {
        let immutableChildren = children.values
            .map(\.immutable)
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
        return KeywordSummaryNode(
            path: path,
            name: name,
            directCount: directCount,
            count: directCount + immutableChildren.reduce(0) {
                $0 + $1.count
            },
            children: immutableChildren
        )
    }
}

public struct SavedSmartCollection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var filter: FilterState
    public var createdAt: Date
    public var parentSetID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        filter: FilterState,
        createdAt: Date = Date(),
        parentSetID: UUID? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = String(
            (trimmed.isEmpty ? "Smart Collection" : trimmed).prefix(80)
        )
        self.filter = filter
        let milliseconds = (
            createdAt.timeIntervalSince1970 * 1_000
        ).rounded()
        self.createdAt = Date(
            timeIntervalSince1970: milliseconds / 1_000
        )
        self.parentSetID = parentSetID
    }
}

public struct CatalogCollectionSet:
    Codable, Equatable, Identifiable, Sendable
{
    public var id: UUID
    public var name: String
    public var parentSetID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        parentSetID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.id = id
        self.name = String(
            (trimmed.isEmpty ? "Collection Set" : trimmed).prefix(80)
        )
        self.parentSetID = parentSetID
        let milliseconds = (
            createdAt.timeIntervalSince1970 * 1_000
        ).rounded()
        self.createdAt = Date(
            timeIntervalSince1970: milliseconds / 1_000
        )
    }
}

public struct CatalogPhotoCollection:
    Codable, Equatable, Identifiable, Sendable
{
    public var id: UUID
    public var name: String
    public var parentSetID: UUID?
    public var createdAt: Date
    public var isTarget: Bool
    public var photoCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        parentSetID: UUID? = nil,
        createdAt: Date = Date(),
        isTarget: Bool = false,
        photoCount: Int = 0
    ) {
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.id = id
        self.name = String(
            (trimmed.isEmpty ? "Collection" : trimmed).prefix(80)
        )
        self.parentSetID = parentSetID
        let milliseconds = (
            createdAt.timeIntervalSince1970 * 1_000
        ).rounded()
        self.createdAt = Date(
            timeIntervalSince1970: milliseconds / 1_000
        )
        self.isTarget = isTarget
        self.photoCount = max(0, photoCount)
    }
}

public enum CatalogCollectionMemberMove: Sendable {
    case beginning
    case up
    case down
    case end
}

public struct CatalogRelinkResult: Equatable, Sendable {
    public var previousID: String
    public var entry: CatalogEntry

    public init(previousID: String, entry: CatalogEntry) {
        self.previousID = previousID
        self.entry = entry
    }
}

public struct CatalogEntry: Equatable, Sendable {
    public var id: String
    public var path: String
    public var rootPath: String
    public var filename: String
    public var fileExtension: String
    public var fileSize: Int64
    public var creationDate: Date?
    public var modificationDate: Date?
    public var format: FileFormat
    public var metadata: PhotoMetadata?
    public var userState: PhotoUserState
    public var indexedAt: Date
    public var lastSeen: Date
    public var isMissing: Bool

    public init(
        id: String,
        path: String,
        rootPath: String,
        filename: String,
        fileExtension: String,
        fileSize: Int64,
        creationDate: Date?,
        modificationDate: Date?,
        format: FileFormat,
        metadata: PhotoMetadata?,
        userState: PhotoUserState,
        indexedAt: Date,
        lastSeen: Date,
        isMissing: Bool
    ) {
        self.id = id
        self.path = path
        self.rootPath = rootPath
        self.filename = filename
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.format = format
        self.metadata = metadata
        self.userState = userState
        self.indexedAt = indexedAt
        self.lastSeen = lastSeen
        self.isMissing = isMissing
    }

    public var asset: PhotoAsset {
        let url = URL(fileURLWithPath: path)
        return PhotoAsset(
            id: id,
            url: url,
            path: path,
            filename: filename,
            fileExtension: fileExtension,
            fileSize: fileSize,
            creationDate: creationDate,
            modificationDate: modificationDate,
            format: format,
            catalogMissing: isMissing,
            loadState: isMissing
                ? .failed(
                    reason: "The source file is missing from its recorded location."
                )
                : .idle,
            metadata: metadata,
            userState: userState,
            xmpSidecarURL: isMissing
                ? nil
                : XMPSidecarService.existingSidecarURL(for: url)
        )
    }
}
