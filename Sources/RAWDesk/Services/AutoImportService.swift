import Foundation

public enum AutoImportServiceError:
    LocalizedError, Equatable, Sendable {
    case invalidSettings(message: String)
    case watchedFolderUnavailable

    public var errorDescription: String? {
        switch self {
        case let .invalidSettings(message):
            return message
        case .watchedFolderUnavailable:
            return "The watched folder is unavailable."
        }
    }
}

public actor AutoImportService {
    public typealias ProgressHandler =
        @Sendable (PhotoImportProgress) async -> Void

    private let photoImportService: PhotoImportService
    private let catalogStore: CatalogStore
    private let fileManager: FileManager

    public init(
        catalogStore: CatalogStore = .shared,
        photoImportService: PhotoImportService? = nil,
        fileManager: FileManager = .default
    ) {
        self.catalogStore = catalogStore
        self.photoImportService = photoImportService
            ?? PhotoImportService(
                catalogStore: catalogStore,
                fileManager: fileManager
            )
        self.fileManager = fileManager
    }

    /// Enumerates only direct children, matching Lightroom Classic's watched
    /// folder behavior. Hidden files, folders, and standalone XMP files do not
    /// become candidates.
    public func snapshots(
        in watchedFolderURL: URL
    ) throws -> [AutoImportFileSnapshot] {
        let watchedFolderURL =
            watchedFolderURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: watchedFolderURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw AutoImportServiceError.watchedFolderUnavailable
        }

        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isHiddenKey,
        ]
        let children = try fileManager.contentsOfDirectory(
            at: watchedFolderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        var result: [AutoImportFileSnapshot] = []
        for child in children {
            try Task.checkCancellation()
            let values = try child.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true,
                  values.isHidden != true,
                  child.pathExtension.lowercased() != "xmp",
                  FileTypeDetector.format(
                      forExtension: child.pathExtension
                  ) != .unsupported else {
                continue
            }
            let sidecar = XMPSidecarService.existingSidecarURL(
                for: child
            )
            let sidecarValues = try sidecar?.resourceValues(
                forKeys: resourceKeys
            )
            result.append(AutoImportFileSnapshot(
                url: child,
                fileSize: Int64(values.fileSize ?? 0),
                modificationDate:
                    values.contentModificationDate,
                sidecarURL: sidecar,
                sidecarFileSize: sidecarValues.map {
                    Int64($0.fileSize ?? 0)
                },
                sidecarModificationDate:
                    sidecarValues?.contentModificationDate
            ))
        }
        return result.sorted {
            $0.url.path.localizedStandardCompare($1.url.path)
                == .orderedAscending
        }
    }

    public func run(
        settings rawSettings: AutoImportSettings,
        sourceURLs: [URL],
        colorLabelSet: PhotoColorLabelSet = .standard,
        progress: ProgressHandler? = nil
    ) async throws -> AutoImportRunResult {
        let settings = rawSettings.normalized
        if let validation = settings.validationMessage(
            requiringComplete: true,
            fileManager: fileManager
        ) {
            throw AutoImportServiceError.invalidSettings(
                message: validation
            )
        }
        guard let watchedFolderURL =
                settings.watchedFolderURL,
              let destinationFolderURL =
                settings.destinationFolderURL else {
            throw AutoImportServiceError.invalidSettings(
                message: "Choose watched and destination folders."
            )
        }

        let watchedPath = watchedFolderURL.standardizedFileURL.path
        let safeSources = sourceURLs
            .map(\.standardizedFileURL)
            .filter {
                $0.deletingLastPathComponent().path == watchedPath
            }
        guard !safeSources.isEmpty else {
            return AutoImportRunResult()
        }

        let request = PhotoImportRequest(
            sourceURLs: safeSources,
            mode: .copyToFolder,
            destinationURL: destinationFolderURL,
            recursive: false,
            skipDuplicates: true,
            folderOrganization: settings.folderOrganization,
            fileNaming: settings.fileNaming,
            customFilenamePrefix:
                settings.customFilenamePrefix,
            sequenceStart: settings.sequenceStart,
            customFolderTemplate:
                settings.customFolderTemplate,
            customFilenameTemplate:
                settings.customFilenameTemplate
        )
        let preflight = try await photoImportService.preflight(
            request,
            progress: progress
        )
        var importResult = try await photoImportService.execute(
            preflight,
            colorLabelSet: colorLabelSet,
            progress: progress
        )
        let pathsBlockedByPersistence = applyInformation(
            settings: settings,
            to: &importResult
        )

        var handledPaths = Set<String>()
        for transfer in importResult.transfers {
            handledPaths.insert(
                transfer.sourceURL.standardizedFileURL.path
            )
        }

        var movedToTrashCount = 0
        if settings.sourceHandling == .moveSourceToTrash {
            if importResult.wasCancelled {
                let retained = importResult.transfers.filter {
                    fileManager.fileExists(
                        atPath: $0.sourceURL.path
                    )
                }
                importResult.retainedSourceCount +=
                    retained.count
                importResult.retainedSourceSidecarCount +=
                    retained.filter {
                        guard let sidecar = $0.sourceSidecarURL else {
                            return false
                        }
                        return fileManager.fileExists(
                            atPath: sidecar.path
                        )
                    }.count
                importResult.warnings.append(
                    "The import was interrupted before source cleanup. Original sources were retained."
                )
            } else {
                let blockedTransfers = importResult.transfers.filter {
                    pathsBlockedByPersistence.contains(
                        $0.catalogedURL.standardizedFileURL.path
                    )
                }
                importResult.retainedSourceCount +=
                    blockedTransfers.filter {
                        fileManager.fileExists(
                            atPath: $0.sourceURL.path
                        )
                    }.count
                importResult.retainedSourceSidecarCount +=
                    blockedTransfers.filter {
                        guard let sidecar = $0.sourceSidecarURL else {
                            return false
                        }
                        return fileManager.fileExists(
                            atPath: sidecar.path
                        )
                    }.count

                let eligibleTransfers =
                    importResult.transfers.filter {
                        !pathsBlockedByPersistence.contains(
                            $0.catalogedURL.standardizedFileURL.path
                        )
                    }
                let disposition =
                    await photoImportService
                        .moveVerifiedSourcesToTrash(
                            eligibleTransfers,
                            destinationURL:
                                destinationFolderURL,
                            requiredSourceDirectory:
                                watchedFolderURL,
                            progress: progress
                        )
                movedToTrashCount =
                    disposition.movedToTrashCount
                importResult.retainedSourceCount +=
                    disposition.retainedSourceCount
                importResult.retainedSourceSidecarCount +=
                    disposition.retainedSourceSidecarCount
                importResult.warnings.append(
                    contentsOf: disposition.warnings
                )
            }
        }

        var warnings = importResult.warnings
        let failures = importResult.failures

        let duplicateURLs = preflight.duplicateMatches.map(
            \.sourceURL
        )
        for url in duplicateURLs {
            handledPaths.insert(url.standardizedFileURL.path)
        }
        if !duplicateURLs.isEmpty {
            warnings.append(
                "\(duplicateURLs.count) exact duplicate(s) were retained in the watched folder for review."
            )
        }

        let retryURLs = safeSources.filter {
            !handledPaths.contains($0.path)
        }
        return AutoImportRunResult(
            importResult: importResult,
            removedSourceCount: movedToTrashCount,
            retainedDuplicateCount: duplicateURLs.count,
            handledURLs: safeSources.filter {
                handledPaths.contains($0.path)
            },
            retryURLs: retryURLs,
            warnings: warnings,
            failures: failures
        )
    }

    private func applyInformation(
        settings: AutoImportSettings,
        to result: inout PhotoImportResult
    ) -> Set<String> {
        guard !settings.keywords.isEmpty
                || settings.developmentPreset != nil else {
            return []
        }
        var pathsBlockedByPersistence = Set<String>()
        for index in result.importedAssets.indices {
            var asset = result.importedAssets[index]
            var state = asset.userState
            if !settings.keywords.isEmpty {
                state.keywords = PhotoUserState.normalizedKeywords(
                    state.keywords + settings.keywords
                )
            }
            if let developmentPreset =
                settings.developmentPreset {
                state.adjustments =
                    developmentPreset.adjustments.normalized
            }
            do {
                try catalogStore.updateUserState(
                    id: asset.id,
                    state: state
                )
                asset.userState = state
                result.importedAssets[index] = asset
            } catch {
                pathsBlockedByPersistence.insert(
                    asset.url.standardizedFileURL.path
                )
                result.warnings.append(
                    "\(asset.filename) was imported, but its requested Auto Import metadata could not be persisted. Its source will be retained: \(error.localizedDescription)"
                )
            }
        }
        return pathsBlockedByPersistence
    }
}
