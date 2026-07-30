import Foundation

public enum AutoImportSourceHandling:
    String, CaseIterable, Codable, Identifiable, Sendable {
    case keepSource
    case moveSourceToTrash

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .keepSource:
            return "Copy and Keep Source"
        case .moveSourceToTrash:
            return "Copy, Verify, then Trash Source"
        }
    }

    public var detail: String {
        switch self {
        case .keepSource:
            return "Copy and register the photo while retaining the watched-folder source."
        case .moveSourceToTrash:
            return "After the copy, hash verification, and catalog registration succeed, move the source photo and verified XMP to the macOS Trash."
        }
    }
}

public struct AutoImportSettings: Codable, Equatable, Sendable {
    public static let defaultSettleInterval: TimeInterval = 2

    public var enabled: Bool
    public var watchedFolderURL: URL?
    public var destinationFolderURL: URL?
    public var sourceHandling: AutoImportSourceHandling
    public var folderOrganization: PhotoImportFolderOrganization
    public var fileNaming: PhotoImportFileNaming
    public var customFilenamePrefix: String
    public var sequenceStart: Int
    public var customFolderTemplate: String
    public var customFilenameTemplate: String
    public var keywords: [String]
    public var developmentPreset: DevelopmentPreset?
    public var settleInterval: TimeInterval

    public init(
        enabled: Bool = false,
        watchedFolderURL: URL? = nil,
        destinationFolderURL: URL? = nil,
        sourceHandling: AutoImportSourceHandling = .keepSource,
        folderOrganization: PhotoImportFolderOrganization =
            .singleFolder,
        fileNaming: PhotoImportFileNaming = .originalFilename,
        customFilenamePrefix: String = "Photo",
        sequenceStart: Int = 1,
        customFolderTemplate: String =
            PhotoImportTemplateRenderer.defaultFolderTemplate,
        customFilenameTemplate: String =
            PhotoImportTemplateRenderer.defaultFilenameTemplate,
        keywords: [String] = [],
        developmentPreset: DevelopmentPreset? = nil,
        settleInterval: TimeInterval = Self.defaultSettleInterval
    ) {
        self.enabled = enabled
        self.watchedFolderURL = watchedFolderURL
        self.destinationFolderURL = destinationFolderURL
        self.sourceHandling = sourceHandling
        self.folderOrganization = folderOrganization
        self.fileNaming = fileNaming
        self.customFilenamePrefix = customFilenamePrefix
        self.sequenceStart = sequenceStart
        self.customFolderTemplate = customFolderTemplate
        self.customFilenameTemplate = customFilenameTemplate
        self.keywords = keywords
        self.developmentPreset = developmentPreset
        self.settleInterval = settleInterval
        self = normalized
    }

    public var normalized: Self {
        var result = self
        result.watchedFolderURL =
            watchedFolderURL?.standardizedFileURL
        result.destinationFolderURL =
            destinationFolderURL?.standardizedFileURL
        result.customFilenamePrefix =
            PhotoImportRequest.normalizedFilenamePrefix(
                customFilenamePrefix
            )
        result.sequenceStart = max(
            1,
            min(999_999, sequenceStart)
        )
        result.keywords = PhotoUserState.normalizedKeywords(keywords)
        result.settleInterval = max(
            0.5,
            min(30, settleInterval)
        )
        return result
    }

    public var usesSequence: Bool {
        if fileNaming == .customSequence {
            return true
        }
        if fileNaming == .tokenTemplate,
           customFilenameTemplate.contains("{sequence") {
            return true
        }
        return folderOrganization == .customTemplate
            && customFolderTemplate.contains("{sequence")
    }

    public var templateValidationMessage: String? {
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

    public func validationMessage(
        requiringComplete: Bool? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let requiringComplete = requiringComplete ?? enabled
        if let templateValidationMessage {
            return templateValidationMessage
        }
        guard let watchedFolderURL else {
            return requiringComplete
                ? "Choose a watched folder."
                : nil
        }
        guard let destinationFolderURL else {
            return requiringComplete
                ? "Choose a destination folder."
                : nil
        }
        guard Self.isDirectory(
            watchedFolderURL,
            fileManager: fileManager
        ) else {
            return "The watched folder is unavailable."
        }
        guard Self.isDirectory(
            destinationFolderURL,
            fileManager: fileManager
        ) else {
            return "The destination folder is unavailable."
        }
        guard !Self.pathsOverlap(
            watchedFolderURL,
            destinationFolderURL
        ) else {
            return "Choose separate, non-nested watched and destination folders."
        }
        if sourceHandling == .moveSourceToTrash,
           !fileManager.isWritableFile(
               atPath: watchedFolderURL.path
           ) {
            return "RAWDesk needs write access to move verified sources to the Trash."
        }
        guard fileManager.isWritableFile(
            atPath: destinationFolderURL.path
        ) else {
            return "RAWDesk needs write access to the destination folder."
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case watchedFolderURL
        case destinationFolderURL
        case sourceHandling
        case folderOrganization
        case fileNaming
        case customFilenamePrefix
        case sequenceStart
        case customFolderTemplate
        case customFilenameTemplate
        case keywords
        case developmentPreset
        case settleInterval
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        self.init(
            enabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .enabled
            ) ?? false,
            watchedFolderURL: try container.decodeIfPresent(
                URL.self,
                forKey: .watchedFolderURL
            ),
            destinationFolderURL: try container.decodeIfPresent(
                URL.self,
                forKey: .destinationFolderURL
            ),
            sourceHandling: try container.decodeIfPresent(
                AutoImportSourceHandling.self,
                forKey: .sourceHandling
            ) ?? .keepSource,
            folderOrganization: try container.decodeIfPresent(
                PhotoImportFolderOrganization.self,
                forKey: .folderOrganization
            ) ?? .singleFolder,
            fileNaming: try container.decodeIfPresent(
                PhotoImportFileNaming.self,
                forKey: .fileNaming
            ) ?? .originalFilename,
            customFilenamePrefix: try container.decodeIfPresent(
                String.self,
                forKey: .customFilenamePrefix
            ) ?? "Photo",
            sequenceStart: try container.decodeIfPresent(
                Int.self,
                forKey: .sequenceStart
            ) ?? 1,
            customFolderTemplate: try container.decodeIfPresent(
                String.self,
                forKey: .customFolderTemplate
            ) ?? PhotoImportTemplateRenderer.defaultFolderTemplate,
            customFilenameTemplate: try container.decodeIfPresent(
                String.self,
                forKey: .customFilenameTemplate
            ) ?? PhotoImportTemplateRenderer.defaultFilenameTemplate,
            keywords: try container.decodeIfPresent(
                [String].self,
                forKey: .keywords
            ) ?? [],
            developmentPreset: try container.decodeIfPresent(
                DevelopmentPreset.self,
                forKey: .developmentPreset
            ),
            settleInterval: try container.decodeIfPresent(
                TimeInterval.self,
                forKey: .settleInterval
            ) ?? Self.defaultSettleInterval
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(
            watchedFolderURL,
            forKey: .watchedFolderURL
        )
        try container.encodeIfPresent(
            destinationFolderURL,
            forKey: .destinationFolderURL
        )
        try container.encode(
            sourceHandling,
            forKey: .sourceHandling
        )
        try container.encode(
            folderOrganization,
            forKey: .folderOrganization
        )
        try container.encode(fileNaming, forKey: .fileNaming)
        try container.encode(
            customFilenamePrefix,
            forKey: .customFilenamePrefix
        )
        try container.encode(sequenceStart, forKey: .sequenceStart)
        try container.encode(
            customFolderTemplate,
            forKey: .customFolderTemplate
        )
        try container.encode(
            customFilenameTemplate,
            forKey: .customFilenameTemplate
        )
        try container.encode(keywords, forKey: .keywords)
        try container.encodeIfPresent(
            developmentPreset,
            forKey: .developmentPreset
        )
        try container.encode(
            settleInterval,
            forKey: .settleInterval
        )
    }

    public static func pathsOverlap(
        _ lhs: URL,
        _ rhs: URL
    ) -> Bool {
        let lhsPath = lhs.standardizedFileURL
            .resolvingSymlinksInPath().path
        let rhsPath = rhs.standardizedFileURL
            .resolvingSymlinksInPath().path
        if lhsPath == rhsPath { return true }
        let lhsPrefix = lhsPath.hasSuffix("/")
            ? lhsPath
            : lhsPath + "/"
        let rhsPrefix = rhsPath.hasSuffix("/")
            ? rhsPath
            : rhsPath + "/"
        return rhsPath.hasPrefix(lhsPrefix)
            || lhsPath.hasPrefix(rhsPrefix)
    }

    private static func isDirectory(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

public struct AutoImportFileSnapshot: Equatable, Sendable {
    public var url: URL
    public var fileSize: Int64
    public var modificationDate: Date?
    public var sidecarURL: URL?
    public var sidecarFileSize: Int64?
    public var sidecarModificationDate: Date?

    public init(
        url: URL,
        fileSize: Int64,
        modificationDate: Date?,
        sidecarURL: URL? = nil,
        sidecarFileSize: Int64? = nil,
        sidecarModificationDate: Date? = nil
    ) {
        self.url = url.standardizedFileURL
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.sidecarURL = sidecarURL?.standardizedFileURL
        self.sidecarFileSize = sidecarFileSize
        self.sidecarModificationDate = sidecarModificationDate
    }
}

/// Holds a file until both its bytes and any sibling XMP have remained
/// unchanged across the configured settling window.
public struct AutoImportStabilityTracker: Sendable {
    private struct Signature: Equatable, Sendable {
        var fileSize: Int64
        var modificationDate: Date?
        var sidecarPath: String?
        var sidecarFileSize: Int64?
        var sidecarModificationDate: Date?
    }

    private struct Observation: Sendable {
        var signature: Signature
        var stableSince: Date
        var dispatched: Bool
    }

    public var settleInterval: TimeInterval {
        didSet {
            settleInterval = max(0.5, min(30, settleInterval))
        }
    }

    private var observations: [String: Observation] = [:]

    public init(
        settleInterval: TimeInterval =
            AutoImportSettings.defaultSettleInterval
    ) {
        self.settleInterval = max(
            0.5,
            min(30, settleInterval)
        )
    }

    public var observedCount: Int { observations.count }

    public var waitingCount: Int {
        observations.values.lazy.filter { !$0.dispatched }.count
    }

    public mutating func reset(
        settleInterval: TimeInterval? = nil
    ) {
        observations.removeAll()
        if let settleInterval {
            self.settleInterval = settleInterval
        }
    }

    public mutating func readyCandidates(
        from snapshots: [AutoImportFileSnapshot],
        now: Date = Date()
    ) -> [URL] {
        let ordered = snapshots.sorted {
            $0.url.path.localizedStandardCompare($1.url.path)
                == .orderedAscending
        }
        let currentPaths = Set(ordered.map {
            $0.url.standardizedFileURL.path
        })
        observations = observations.filter {
            currentPaths.contains($0.key)
        }

        var ready: [URL] = []
        for snapshot in ordered {
            let path = snapshot.url.standardizedFileURL.path
            let signature = Signature(
                fileSize: snapshot.fileSize,
                modificationDate: snapshot.modificationDate,
                sidecarPath:
                    snapshot.sidecarURL?.standardizedFileURL.path,
                sidecarFileSize: snapshot.sidecarFileSize,
                sidecarModificationDate:
                    snapshot.sidecarModificationDate
            )
            guard var observation = observations[path] else {
                observations[path] = Observation(
                    signature: signature,
                    stableSince: now,
                    dispatched: false
                )
                continue
            }
            guard observation.signature == signature else {
                observations[path] = Observation(
                    signature: signature,
                    stableSince: now,
                    dispatched: false
                )
                continue
            }
            guard !observation.dispatched,
                  now.timeIntervalSince(observation.stableSince)
                    >= settleInterval,
                  Self.isOldEnough(
                      snapshot.modificationDate,
                      now: now,
                      interval: settleInterval
                  ),
                  Self.isOldEnough(
                      snapshot.sidecarModificationDate,
                      now: now,
                      interval: settleInterval
                  ) else {
                continue
            }
            observation.dispatched = true
            observations[path] = observation
            ready.append(snapshot.url)
        }
        return ready
    }

    /// Makes transient failures eligible again after another quiet window.
    public mutating func retry(
        _ urls: [URL],
        now: Date = Date()
    ) {
        for url in urls {
            let path = url.standardizedFileURL.path
            guard var observation = observations[path] else {
                continue
            }
            observation.dispatched = false
            observation.stableSince = now
            observations[path] = observation
        }
    }

    private static func isOldEnough(
        _ date: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) >= interval
    }
}

public enum AutoImportActivityPhase:
    String, Equatable, Sendable {
    case off
    case watching
    case settling
    case checking
    case importing
    case attention

    public var name: String {
        switch self {
        case .off: return "Off"
        case .watching: return "Watching"
        case .settling: return "Waiting for files"
        case .checking: return "Checking files"
        case .importing: return "Importing"
        case .attention: return "Needs attention"
        }
    }

    public var systemImage: String {
        switch self {
        case .off: return "pause.circle"
        case .watching: return "eye"
        case .settling: return "clock"
        case .checking: return "checkmark.shield"
        case .importing: return "arrow.down.doc"
        case .attention: return "exclamationmark.triangle"
        }
    }
}

public struct AutoImportStatus: Equatable, Sendable {
    public var phase: AutoImportActivityPhase
    public var message: String
    public var pendingCount: Int
    public var lastRunDate: Date?
    public var lastImportedCount: Int

    public init(
        phase: AutoImportActivityPhase = .off,
        message: String = "Auto Import is off.",
        pendingCount: Int = 0,
        lastRunDate: Date? = nil,
        lastImportedCount: Int = 0
    ) {
        self.phase = phase
        self.message = message
        self.pendingCount = pendingCount
        self.lastRunDate = lastRunDate
        self.lastImportedCount = lastImportedCount
    }
}

public struct AutoImportRunResult: Equatable, Sendable {
    public var importResult: PhotoImportResult
    public var removedSourceCount: Int
    public var retainedDuplicateCount: Int
    public var handledURLs: [URL]
    public var retryURLs: [URL]
    public var warnings: [String]
    public var failures: [String]

    public init(
        importResult: PhotoImportResult = PhotoImportResult(),
        removedSourceCount: Int = 0,
        retainedDuplicateCount: Int = 0,
        handledURLs: [URL] = [],
        retryURLs: [URL] = [],
        warnings: [String] = [],
        failures: [String] = []
    ) {
        self.importResult = importResult
        self.removedSourceCount = removedSourceCount
        self.retainedDuplicateCount = retainedDuplicateCount
        self.handledURLs = handledURLs
        self.retryURLs = retryURLs
        self.warnings = warnings
        self.failures = failures
    }
}
