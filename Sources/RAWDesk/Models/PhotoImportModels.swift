import Foundation

public enum PhotoImportMode: String, CaseIterable, Identifiable, Sendable {
    case addInPlace
    case copyToFolder
    case moveToFolder

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .addInPlace:
            return "Add"
        case .copyToFolder:
            return "Copy"
        case .moveToFolder:
            return "Copy + Trash"
        }
    }

    public var detail: String {
        switch self {
        case .addInPlace:
            return "Reference photos where they are. No source files are copied."
        case .copyToFolder:
            return "Copy verified originals and sibling XMP files into one folder."
        case .moveToFolder:
            return "Copy and verify first, update the catalog, then move the verified sources to the macOS Trash."
        }
    }

    public var requiresDestination: Bool {
        self != .addInPlace
    }

    public var removesVerifiedSources: Bool {
        self == .moveToFolder
    }
}

public enum PhotoImportFolderOrganization:
    String, CaseIterable, Codable, Identifiable, Sendable {
    case singleFolder
    case captureDate
    case customTemplate

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .singleFolder:
            return "One Folder"
        case .captureDate:
            return "By Capture Date"
        case .customTemplate:
            return "Custom Template"
        }
    }

    public var detail: String {
        switch self {
        case .singleFolder:
            return "Place every transferred photo directly in the destination."
        case .captureDate:
            return "Create YYYY/YYYY-MM-DD folders using capture date, then file date."
        case .customTemplate:
            return "Build safe nested folders from date, camera, source-folder, and sequence tokens."
        }
    }
}

public enum PhotoImportFileNaming:
    String, CaseIterable, Codable, Identifiable, Sendable {
    case originalFilename
    case customSequence
    case tokenTemplate

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .originalFilename:
            return "Original Filename"
        case .customSequence:
            return "Custom Name + Sequence"
        case .tokenTemplate:
            return "Token Template"
        }
    }

    public var renamesTransferredFiles: Bool {
        self != .originalFilename
    }
}

public struct PhotoImportRequest: Equatable, Sendable {
    public var sourceURLs: [URL]
    public var mode: PhotoImportMode
    public var destinationURL: URL?
    public var recursive: Bool
    public var skipDuplicates: Bool
    public var folderOrganization: PhotoImportFolderOrganization
    public var fileNaming: PhotoImportFileNaming
    public var customFilenamePrefix: String
    public var sequenceStart: Int
    public var customFolderTemplate: String
    public var customFilenameTemplate: String

    public init(
        sourceURLs: [URL],
        mode: PhotoImportMode = .addInPlace,
        destinationURL: URL? = nil,
        recursive: Bool = true,
        skipDuplicates: Bool = true,
        folderOrganization: PhotoImportFolderOrganization =
            .singleFolder,
        fileNaming: PhotoImportFileNaming = .originalFilename,
        customFilenamePrefix: String = "Photo",
        sequenceStart: Int = 1,
        customFolderTemplate: String =
            PhotoImportTemplateRenderer.defaultFolderTemplate,
        customFilenameTemplate: String =
            PhotoImportTemplateRenderer.defaultFilenameTemplate
    ) {
        self.sourceURLs = sourceURLs
        self.mode = mode
        self.destinationURL = destinationURL
        self.recursive = recursive
        self.skipDuplicates = skipDuplicates
        self.folderOrganization = folderOrganization
        self.fileNaming = fileNaming
        self.customFilenamePrefix = customFilenamePrefix
        self.sequenceStart = max(1, min(999_999, sequenceStart))
        self.customFolderTemplate = customFolderTemplate
        self.customFilenameTemplate = customFilenameTemplate
    }

    public var templateValidationMessage: String? {
        guard mode.requiresDestination else { return nil }
        do {
            if folderOrganization == .customTemplate {
                try PhotoImportTemplateRenderer.validate(
                    customFolderTemplate,
                    kind: .folder
                )
            }
            if fileNaming == .tokenTemplate {
                try PhotoImportTemplateRenderer.validate(
                    customFilenameTemplate,
                    kind: .filename
                )
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public var usesSequence: Bool {
        switch fileNaming {
        case .originalFilename:
            return folderOrganization == .customTemplate
                && customFolderTemplate.contains("{sequence")
        case .customSequence:
            return true
        case .tokenTemplate:
            return customFilenameTemplate.contains("{sequence")
                || (
                    folderOrganization == .customTemplate
                        && customFolderTemplate.contains("{sequence")
                )
        }
    }

    public static func normalizedFilenamePrefix(
        _ rawValue: String
    ) -> String {
        let replaced = String(rawValue.map { character in
            switch character {
            case "/", ":", "\\":
                return "-"
            default:
                return character
            }
        })
        let collapsed = replaced
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(
                in: CharacterSet(charactersIn: ". ")
            )
        let source = collapsed.isEmpty ? "Photo" : collapsed
        var result = ""
        var byteCount = 0
        for character in source {
            let bytes = String(character).utf8.count
            guard byteCount + bytes <= 120 else { break }
            result.append(character)
            byteCount += bytes
        }
        return result.isEmpty ? "Photo" : result
    }
}

public enum PhotoImportDuplicate: Equatable, Sendable {
    case catalog(path: String)
    case selection(path: String)

    public var detail: String {
        switch self {
        case let .catalog(path):
            return "Already in catalog: \(path)"
        case let .selection(path):
            return "Same content as selected file: \(path)"
        }
    }

    public func matchesSource(_ sourceURL: URL) -> Bool {
        guard case let .catalog(path) = self else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path
            == sourceURL.standardizedFileURL.path
    }
}

public enum PhotoImportItemStatus: Equatable, Sendable {
    case ready
    case duplicate(PhotoImportDuplicate)
    case unsupported
    case unavailable(reason: String)

    public var isImportable: Bool {
        switch self {
        case .ready, .duplicate:
            return true
        case .unsupported, .unavailable:
            return false
        }
    }
}

public struct PhotoImportItem: Identifiable, Equatable, Sendable {
    public var sourceURL: URL
    public var rootURL: URL
    public var fileSize: Int64
    public var creationDate: Date?
    public var modificationDate: Date?
    public var format: FileFormat
    public var contentHash: String?
    public var sidecarURL: URL?
    public var status: PhotoImportItemStatus

    public var id: String { sourceURL.standardizedFileURL.path }

    public init(
        sourceURL: URL,
        rootURL: URL,
        fileSize: Int64,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        format: FileFormat,
        contentHash: String? = nil,
        sidecarURL: URL? = nil,
        status: PhotoImportItemStatus
    ) {
        self.sourceURL = sourceURL
        self.rootURL = rootURL
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.format = format
        self.contentHash = contentHash
        self.sidecarURL = sidecarURL
        self.status = status
    }

    public func isImportable(for request: PhotoImportRequest) -> Bool {
        switch status {
        case .ready:
            return true
        case let .duplicate(duplicate):
            if request.mode.removesVerifiedSources,
               duplicate.matchesSource(sourceURL) {
                return false
            }
            return !request.skipDuplicates
        case .unsupported, .unavailable:
            return false
        }
    }
}

public struct PhotoImportPreflight: Equatable, Sendable {
    public var request: PhotoImportRequest
    public var items: [PhotoImportItem]
    public var warnings: [String]

    public init(
        request: PhotoImportRequest,
        items: [PhotoImportItem],
        warnings: [String] = []
    ) {
        self.request = request
        self.items = items
        self.warnings = warnings
    }

    public var readyCount: Int {
        items.lazy.filter { $0.status == .ready }.count
    }

    public var duplicateCount: Int {
        items.lazy.filter {
            if case .duplicate = $0.status { return true }
            return false
        }.count
    }

    public var unsupportedCount: Int {
        items.lazy.filter { $0.status == .unsupported }.count
    }

    public var unavailableCount: Int {
        items.lazy.filter {
            if case .unavailable = $0.status { return true }
            return false
        }.count
    }

    public var importableCount: Int {
        items.lazy.filter { $0.isImportable(for: request) }.count
    }

    public var importableByteCount: Int64 {
        items.lazy.filter {
            $0.isImportable(for: request)
        }.reduce(0) { $0 + $1.fileSize }
    }

    public var catalogedSourceMoveConflictCount: Int {
        guard request.mode.removesVerifiedSources else { return 0 }
        return items.lazy.filter { item in
            guard case let .duplicate(duplicate) = item.status else {
                return false
            }
            return duplicate.matchesSource(item.sourceURL)
        }.count
    }

    public var duplicateMatches: [PhotoImportDuplicateMatch] {
        items.compactMap { item in
            guard case let .duplicate(duplicate) = item.status,
                  let contentHash = item.contentHash else {
                return nil
            }
            return PhotoImportDuplicateMatch(
                sourceURL: item.sourceURL,
                duplicate: duplicate,
                fileSize: item.fileSize,
                contentHash: contentHash
            )
        }
    }
}

struct PhotoImportPreflightPresentation:
    Equatable, Sendable {
    let footerSummary: String
    let unavailableCount: Int
    let estimatedCopySize: String
    let xmpCompanionCount: Int
    let namingConflictDetail: String
    let warningCount: Int
    let warnings: [String]

    var accessibilityDetailSummary: String {
        var details = [
            "Unavailable \(unavailableCount)",
            "Estimated copy size \(estimatedCopySize)",
            "XMP companions \(xmpCompanionCount)",
            "Naming conflicts \(namingConflictDetail)",
            "Warnings \(warningCount)",
        ]
        details.append(contentsOf: warnings)
        return details
            .map {
                $0.trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: ". "
                    )
                )
            }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
            + "."
    }

    init(
        preflight: PhotoImportPreflight,
        request: PhotoImportRequest? = nil
    ) {
        let currentRequest = request ?? preflight.request
        footerSummary =
            "\(preflight.items.count) total · "
            + "\(preflight.readyCount) new · "
            + "\(preflight.duplicateCount) duplicates · "
            + "\(preflight.unsupportedCount) unsupported"
        unavailableCount = preflight.unavailableCount
        estimatedCopySize =
            currentRequest.mode.requiresDestination
                ? ByteCountFormatter.string(
                    fromByteCount:
                        preflight.importableByteCount,
                    countStyle: .file
                )
                : "No copy"
        xmpCompanionCount =
            preflight.items.lazy.filter {
                $0.sidecarURL != nil
            }.count
        if let validation =
            currentRequest.templateValidationMessage {
            namingConflictDetail =
                "Template needs attention: \(validation)"
        } else if currentRequest.mode.requiresDestination {
            namingConflictDetail =
                "Checked during transfer; conflicts use a safe numbered suffix and never overwrite."
        } else {
            namingConflictDetail =
                "No destination naming for Add."
        }
        warningCount = preflight.warnings.count
        warnings = preflight.warnings
    }
}

public enum PhotoImportProgressPhase: String, Equatable, Sendable {
    case discovering
    case hashing
    case copying
    case cataloging
    case removingSources

    public var name: String {
        switch self {
        case .discovering: return "Finding photos"
        case .hashing: return "Checking duplicates"
        case .copying: return "Copying and verifying"
        case .cataloging: return "Updating catalog"
        case .removingSources: return "Moving verified sources to Trash"
        }
    }
}

public struct PhotoImportProgress: Equatable, Sendable {
    public var phase: PhotoImportProgressPhase
    public var completed: Int
    public var total: Int
    public var filename: String?

    public init(
        phase: PhotoImportProgressPhase,
        completed: Int,
        total: Int,
        filename: String? = nil
    ) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.filename = filename
    }

    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

public struct PhotoImportResult: Equatable, Sendable {
    public var importedAssets: [PhotoAsset]
    public var transfers: [PhotoImportTransfer]
    public var copiedCount: Int
    public var movedCount: Int
    public var retainedSourceCount: Int
    public var retainedSourceSidecarCount: Int
    public var reusedDestinationCount: Int
    public var renamedCount: Int
    public var organizedFolderCount: Int
    public var skippedDuplicateCount: Int
    public var unsupportedCount: Int
    public var duplicateMatches: [PhotoImportDuplicateMatch]
    public var warnings: [String]
    public var failures: [String]
    public var wasCancelled: Bool

    public init(
        importedAssets: [PhotoAsset] = [],
        transfers: [PhotoImportTransfer] = [],
        copiedCount: Int = 0,
        movedCount: Int = 0,
        retainedSourceCount: Int = 0,
        retainedSourceSidecarCount: Int = 0,
        reusedDestinationCount: Int = 0,
        renamedCount: Int = 0,
        organizedFolderCount: Int = 0,
        skippedDuplicateCount: Int = 0,
        unsupportedCount: Int = 0,
        duplicateMatches: [PhotoImportDuplicateMatch] = [],
        warnings: [String] = [],
        failures: [String] = [],
        wasCancelled: Bool = false
    ) {
        self.importedAssets = importedAssets
        self.transfers = transfers
        self.copiedCount = copiedCount
        self.movedCount = movedCount
        self.retainedSourceCount = retainedSourceCount
        self.retainedSourceSidecarCount =
            retainedSourceSidecarCount
        self.reusedDestinationCount = reusedDestinationCount
        self.renamedCount = renamedCount
        self.organizedFolderCount = organizedFolderCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.unsupportedCount = unsupportedCount
        self.duplicateMatches = duplicateMatches
        self.warnings = warnings
        self.failures = failures
        self.wasCancelled = wasCancelled
    }

    public var importedCount: Int { importedAssets.count }

    public var duplicateGroups: [PhotoImportDuplicateGroup] {
        Dictionary(grouping: duplicateMatches, by: \.contentHash)
            .map { contentHash, matches in
                PhotoImportDuplicateGroup(
                    contentHash: contentHash,
                    fileSize: matches.first?.fileSize ?? 0,
                    matches: matches.sorted {
                        $0.sourceURL.path.localizedStandardCompare(
                            $1.sourceURL.path
                        ) == .orderedAscending
                    }
                )
            }
            .sorted { $0.contentHash < $1.contentHash }
    }
}

public struct PhotoImportSourceDispositionResult:
    Equatable, Sendable {
    public var movedToTrashCount: Int
    public var retainedSourceCount: Int
    public var retainedSourceSidecarCount: Int
    public var warnings: [String]
    public var wasCancelled: Bool

    public init(
        movedToTrashCount: Int = 0,
        retainedSourceCount: Int = 0,
        retainedSourceSidecarCount: Int = 0,
        warnings: [String] = [],
        wasCancelled: Bool = false
    ) {
        self.movedToTrashCount = movedToTrashCount
        self.retainedSourceCount = retainedSourceCount
        self.retainedSourceSidecarCount =
            retainedSourceSidecarCount
        self.warnings = warnings
        self.wasCancelled = wasCancelled
    }
}

struct PhotoImportResultPresentation:
    Equatable, Sendable {
    let title: String
    let headline: String
    let cancellationDetail: String?
    let requiresAttention: Bool
    let showsRevealProblems: Bool
    let showsLastImport: Bool

    init(result: PhotoImportResult) {
        let photoLabel =
            "photo"
                + (
                    result.importedCount == 1
                        ? ""
                        : "s"
                )
        title =
            result.wasCancelled
                ? "Import Canceled"
                : "Import Complete"
        headline =
            result.wasCancelled
                ? "\(result.importedCount) \(photoLabel) completed before cancel"
                : "\(result.importedCount) \(photoLabel) imported"
        if result.wasCancelled {
            cancellationDetail =
                result.movedCount > 0
                    ? "Completed photos remain imported. \(result.movedCount) verified original(s) were moved to Trash before cancellation; remaining originals were retained."
                    : "Completed photos remain imported. Uncommitted copies were removed, and original files were not changed."
        } else {
            cancellationDetail = nil
        }
        requiresAttention =
            result.wasCancelled
                || !result.failures.isEmpty
                || !result.warnings.isEmpty
                || result.retainedSourceCount > 0
                || result.retainedSourceSidecarCount
                    > 0
        showsRevealProblems =
            !result.failures.isEmpty
                || !result.warnings.isEmpty
                || result.retainedSourceCount > 0
                || result.retainedSourceSidecarCount
                    > 0
        showsLastImport =
            result.importedCount > 0
    }
}

/// A source-to-catalog handoff that completed successfully.
///
/// Add and Copy leave the source untouched. Manual Copy + Trash and optional
/// Auto Import source cleanup use this receipt only after the verified copy and
/// catalog transaction have both succeeded.
public struct PhotoImportTransfer:
    Identifiable, Equatable, Sendable {
    public var sourceURL: URL
    public var sourceSidecarURL: URL?
    public var catalogedURL: URL
    public var contentHash: String
    public var copied: Bool
    public var reusedDestination: Bool

    public var id: String {
        sourceURL.standardizedFileURL.path
    }

    public init(
        sourceURL: URL,
        sourceSidecarURL: URL? = nil,
        catalogedURL: URL,
        contentHash: String,
        copied: Bool,
        reusedDestination: Bool
    ) {
        self.sourceURL = sourceURL
        self.sourceSidecarURL = sourceSidecarURL
        self.catalogedURL = catalogedURL
        self.contentHash = contentHash
        self.copied = copied
        self.reusedDestination = reusedDestination
    }
}

public struct PhotoImportDuplicateMatch:
    Identifiable, Equatable, Sendable {
    public var sourceURL: URL
    public var duplicate: PhotoImportDuplicate
    public var fileSize: Int64
    public var contentHash: String

    public var id: String { sourceURL.standardizedFileURL.path }

    public var matchingPath: String {
        switch duplicate {
        case let .catalog(path), let .selection(path):
            return path
        }
    }

    public var matchKindName: String {
        switch duplicate {
        case .catalog:
            return "Catalog match"
        case .selection:
            return "Selection match"
        }
    }

    public init(
        sourceURL: URL,
        duplicate: PhotoImportDuplicate,
        fileSize: Int64,
        contentHash: String
    ) {
        self.sourceURL = sourceURL
        self.duplicate = duplicate
        self.fileSize = fileSize
        self.contentHash = contentHash
    }
}

public struct PhotoImportDuplicateGroup:
    Identifiable, Equatable, Sendable {
    public var contentHash: String
    public var fileSize: Int64
    public var matches: [PhotoImportDuplicateMatch]

    public var id: String { contentHash }

    public init(
        contentHash: String,
        fileSize: Int64,
        matches: [PhotoImportDuplicateMatch]
    ) {
        self.contentHash = contentHash
        self.fileSize = fileSize
        self.matches = matches
    }
}

public struct CatalogHashCandidate: Equatable, Sendable {
    public var id: String
    public var path: String
    public var fileSize: Int64
    public var modificationDate: Date?
    public var contentHash: String?
    public var imageContentHash: String?

    public init(
        id: String,
        path: String,
        fileSize: Int64,
        modificationDate: Date?,
        contentHash: String?,
        imageContentHash: String? = nil
    ) {
        self.id = id
        self.path = path
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.contentHash = contentHash
        self.imageContentHash = imageContentHash
    }
}
