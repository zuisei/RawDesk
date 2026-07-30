import Foundation

public enum PhotoImportServiceError: LocalizedError, Equatable, Sendable {
    case noSources
    case destinationRequired
    case destinationUnavailable
    case destinationSubfolderUnavailable(name: String)
    case destinationNameExhausted
    case sourceChanged(filename: String)
    case copyVerificationFailed(filename: String)
    case invalidTemplate(reason: String)
    case moveDestinationConflictsWithSource
    case sourceRemovalFailed(filename: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .noSources:
            return "Choose at least one photo or folder."
        case .destinationRequired:
            return "Choose a destination folder for copied or moved photos."
        case .destinationUnavailable:
            return "The import destination is unavailable or is not a folder."
        case let .destinationSubfolderUnavailable(name):
            return "The import folder \(name) could not be created or is not a folder."
        case .destinationNameExhausted:
            return "RAWDesk could not find a safe unused destination name."
        case let .sourceChanged(filename):
            return "\(filename) changed after it was checked. Run the check again."
        case let .copyVerificationFailed(filename):
            return "The copied bytes for \(filename) did not match the source."
        case let .invalidTemplate(reason):
            return "Fix the import template before transferring files: \(reason)"
        case .moveDestinationConflictsWithSource:
            return "Choose a Copy + Trash destination outside the selected source folder and different from a selected photo's current folder."
        case let .sourceRemovalFailed(filename, reason):
            return "\(filename) was copied, verified, and cataloged, but its source could not be moved to the Trash and was retained: \(reason)"
        }
    }
}

public actor PhotoImportService {
    public typealias ProgressHandler =
        @Sendable (PhotoImportProgress) async -> Void
    public typealias SourceRemovalHandler =
        @Sendable (URL) throws -> Void
    public typealias AssetInspectionHandler =
        @Sendable (
            URL,
            [String: PhotoUserState],
            PhotoColorLabelSet
        ) throws -> PhotoLibraryScanner.AssetInspection

    private let catalogStore: CatalogStore
    private let fileManager: FileManager
    private let sourceRemovalHandler: SourceRemovalHandler
    private let assetInspectionHandler: AssetInspectionHandler

    public init(
        catalogStore: CatalogStore = .shared,
        fileManager: FileManager = .default,
        sourceRemovalHandler: @escaping SourceRemovalHandler = {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(
                at: $0,
                resultingItemURL: &resultingURL
            )
        },
        assetInspectionHandler: @escaping AssetInspectionHandler = {
            try PhotoLibraryScanner.inspectAsset(
                at: $0,
                userStates: $1,
                colorLabelSet: $2
            )
        }
    ) {
        self.catalogStore = catalogStore
        self.fileManager = fileManager
        self.sourceRemovalHandler = sourceRemovalHandler
        self.assetInspectionHandler = assetInspectionHandler
    }

    public func preflight(
        _ rawRequest: PhotoImportRequest,
        progress: ProgressHandler? = nil
    ) async throws -> PhotoImportPreflight {
        let request = normalized(rawRequest)
        guard !request.sourceURLs.isEmpty else {
            throw PhotoImportServiceError.noSources
        }

        await progress?(PhotoImportProgress(
            phase: .discovering,
            completed: 0,
            total: 0
        ))
        var warnings: [String] = []
        var items = discover(request: request, warnings: &warnings)
        let supportedCount = items.lazy.filter {
            $0.format != .unsupported
                && $0.status != .unsupported
        }.count
        var completed = 0
        var firstPathByHash: [String: String] = [:]
        var catalogCandidatesBySize: [Int64: [CatalogHashCandidate]] = [:]
        var resolvedCatalogHashes: [String: String] = [:]

        for index in items.indices {
            try Task.checkCancellation()
            guard items[index].status != .unsupported else { continue }
            guard case .ready = items[index].status else { continue }

            let sourceURL = items[index].sourceURL
            completed += 1
            await progress?(PhotoImportProgress(
                phase: .hashing,
                completed: completed - 1,
                total: supportedCount,
                filename: sourceURL.lastPathComponent
            ))

            do {
                let hash = try stableHash(
                    for: sourceURL,
                    expectedSize: items[index].fileSize,
                    expectedModificationDate:
                        items[index].modificationDate
                )
                items[index].contentHash = hash

                let candidates: [CatalogHashCandidate]
                if let cached = catalogCandidatesBySize[
                    items[index].fileSize
                ] {
                    candidates = cached
                } else {
                    let loaded = try catalogStore.duplicateCandidates(
                        fileSize: items[index].fileSize
                    )
                    catalogCandidatesBySize[
                        items[index].fileSize
                    ] = loaded
                    candidates = loaded
                }

                if let duplicate = try catalogDuplicate(
                    contentHash: hash,
                    sourceURL: sourceURL,
                    candidates: candidates,
                    resolvedHashes: &resolvedCatalogHashes
                ) {
                    items[index].status = .duplicate(
                        .catalog(path: duplicate.path)
                    )
                } else if let firstPath = firstPathByHash[hash] {
                    items[index].status = .duplicate(
                        .selection(path: firstPath)
                    )
                } else {
                    firstPathByHash[hash] = sourceURL.path
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                items[index].status = .unavailable(
                    reason: error.localizedDescription
                )
            }

            await progress?(PhotoImportProgress(
                phase: .hashing,
                completed: completed,
                total: supportedCount,
                filename: sourceURL.lastPathComponent
            ))
        }

        return PhotoImportPreflight(
            request: request,
            items: items,
            warnings: warnings
        )
    }

    public func execute(
        _ preflight: PhotoImportPreflight,
        colorLabelSet: PhotoColorLabelSet = .standard,
        progress: ProgressHandler? = nil
    ) async throws -> PhotoImportResult {
        let request = normalized(preflight.request)
        if let validation = request.templateValidationMessage {
            throw PhotoImportServiceError.invalidTemplate(
                reason: validation
            )
        }
        let destination: URL?
        if request.mode.requiresDestination {
            guard let requestedDestination = request.destinationURL else {
                throw PhotoImportServiceError.destinationRequired
            }
            destination = try validatedDestination(requestedDestination)
            if request.mode.removesVerifiedSources,
               let destination {
                try validateMoveDestination(
                    destination,
                    sources: request.sourceURLs
                )
            }
        } else {
            destination = nil
        }

        let eligible = preflight.items.filter {
            $0.isImportable(for: request)
        }
        let moveConflicts =
            request.mode.removesVerifiedSources
                ? preflight.items.filter { item in
                    guard case let .duplicate(duplicate) =
                        item.status else {
                        return false
                    }
                    return duplicate.matchesSource(item.sourceURL)
                }
                : []
        var result = PhotoImportResult(
            skippedDuplicateCount:
                request.skipDuplicates
                    ? preflight.duplicateCount
                    : moveConflicts.count,
            unsupportedCount: preflight.unsupportedCount,
            duplicateMatches: preflight.duplicateMatches,
            warnings: preflight.warnings,
            failures: preflight.items.compactMap { item in
                guard case let .unavailable(reason) = item.status else {
                    return nil
                }
                return "\(item.sourceURL.lastPathComponent): \(reason)"
            }
        )
        if !moveConflicts.isEmpty {
            result.warnings.append(
                "\(moveConflicts.count) source"
                    + "\(moveConflicts.count == 1 ? "" : "s")"
                    + " already cataloged at the selected path and "
                    + "\(moveConflicts.count == 1 ? "was" : "were")"
                    + " not moved. Relink an existing catalog photo instead."
            )
        }
        guard !eligible.isEmpty else { return result }

        let userStates = try catalogStore.userStates()
        var prepared: [PreparedImport] = []
        prepared.reserveCapacity(eligible.count)
        var preparedIDs: Set<PhotoAsset.ID> = []
        var createdImportDirectories: Set<String> = []
        var organizedDirectories: Set<String> = []

        do {
            for (offset, item) in eligible.enumerated() {
                try Task.checkCancellation()
                let phase: PhotoImportProgressPhase =
                    request.mode.requiresDestination
                        ? .copying
                        : .hashing
                await progress?(PhotoImportProgress(
                    phase: phase,
                    completed: offset,
                    total: eligible.count,
                    filename: item.sourceURL.lastPathComponent
                ))

                var uncommittedPhotoURL: URL?
                var uncommittedSidecarURL: URL?
                do {
                    guard let expectedHash = item.contentHash else {
                        throw PhotoImportServiceError.sourceChanged(
                            filename: item.sourceURL.lastPathComponent
                        )
                    }
                    let currentHash = try stableHash(
                        for: item.sourceURL,
                        expectedSize: item.fileSize,
                        expectedModificationDate: item.modificationDate
                    )
                    guard currentHash == expectedHash else {
                        throw PhotoImportServiceError.sourceChanged(
                            filename: item.sourceURL.lastPathComponent
                        )
                    }

                    let targetURL: URL
                    let rootURL: URL
                    var createdPhotoURL: URL?
                    var createdSidecarURL: URL?
                    var copied = false
                    var reusedDestination = false
                    var organizedDirectory: URL?

                    if let destination {
                        let renderContext =
                            templateContext(
                                for: item,
                                sequence:
                                    request.sequenceStart + offset
                            )
                        let targetDirectory =
                            try destinationDirectory(
                                base: destination,
                                request: request,
                                context: renderContext,
                                createdDirectories:
                                    &createdImportDirectories
                            )
                        let copy = try copyPhoto(
                            item,
                            to: targetDirectory,
                            reuseIdentical: request.skipDuplicates,
                            preferredBaseName: try preferredBaseName(
                                request: request,
                                context: renderContext
                            )
                        )
                        targetURL = copy.photoURL
                        rootURL = destination
                        if request.folderOrganization
                            != .singleFolder {
                            organizedDirectory = targetDirectory
                        }
                        createdPhotoURL = copy.createdPhotoURL
                        createdSidecarURL = copy.createdSidecarURL
                        uncommittedPhotoURL = copy.createdPhotoURL
                        uncommittedSidecarURL = copy.createdSidecarURL
                        copied = copy.createdPhotoURL != nil
                        reusedDestination = copy.reusedExistingPhoto
                    } else {
                        targetURL = item.sourceURL
                        rootURL = item.rootURL
                    }

                    let inspection = try assetInspectionHandler(
                        targetURL,
                        userStates,
                        colorLabelSet
                    )
                    result.warnings.append(
                        contentsOf: inspection.warnings
                    )
                    let preparedItem = PreparedImport(
                        sourceURL: item.sourceURL,
                        sourceSidecarURL: item.sidecarURL,
                        asset: inspection.asset,
                        rootURL: rootURL,
                        contentHash: expectedHash,
                        createdPhotoURL: createdPhotoURL,
                        createdSidecarURL: createdSidecarURL,
                        copied: copied,
                        reusedDestination: reusedDestination,
                        renamedByTemplate:
                            destination != nil
                                && request.fileNaming
                                    .renamesTransferredFiles,
                        organizedDirectory: organizedDirectory
                    )
                    if preparedIDs.insert(inspection.asset.id).inserted {
                        prepared.append(preparedItem)
                        uncommittedPhotoURL = nil
                        uncommittedSidecarURL = nil
                    } else {
                        rollback([preparedItem])
                        result.warnings.append(
                            "\(inspection.asset.filename) points to a file resource already included in this import and was cataloged once."
                        )
                    }
                } catch is CancellationError {
                    removeIfCreated(uncommittedSidecarURL)
                    removeIfCreated(uncommittedPhotoURL)
                    removeEmptyImportDirectories(
                        &createdImportDirectories
                    )
                    throw CancellationError()
                } catch {
                    removeIfCreated(uncommittedSidecarURL)
                    removeIfCreated(uncommittedPhotoURL)
                    removeEmptyImportDirectories(
                        &createdImportDirectories
                    )
                    result.failures.append(
                        "\(item.sourceURL.lastPathComponent): \(error.localizedDescription)"
                    )
                }

                await progress?(PhotoImportProgress(
                    phase: phase,
                    completed: offset + 1,
                    total: eligible.count,
                    filename: item.sourceURL.lastPathComponent
                ))
            }
        } catch {
            rollback(prepared)
            removeEmptyImportDirectories(&createdImportDirectories)
            throw error
        }

        let grouped = Dictionary(grouping: prepared) {
            $0.rootURL.standardizedFileURL.path
        }
        let orderedGroups = grouped.keys.sorted().compactMap {
            grouped[$0]
        }
        var cataloged = 0
        for (groupIndex, group) in
            orderedGroups.enumerated() {
            guard let first = group.first else {
                continue
            }
            if Task.isCancelled {
                return cancelledResult(
                    result,
                    request: request,
                    pending: orderedGroups[
                        groupIndex...
                    ].flatMap { $0 },
                    createdImportDirectories:
                        &createdImportDirectories,
                    organizedDirectories:
                        organizedDirectories
                )
            }
            await progress?(PhotoImportProgress(
                phase: .cataloging,
                completed: cataloged,
                total: prepared.count,
                filename: first.rootURL.lastPathComponent
            ))
            if Task.isCancelled {
                return cancelledResult(
                    result,
                    request: request,
                    pending: orderedGroups[
                        groupIndex...
                    ].flatMap { $0 },
                    createdImportDirectories:
                        &createdImportDirectories,
                    organizedDirectories:
                        organizedDirectories
                )
            }
            do {
                try catalogStore.upsert(
                    assets: group.map(\.asset),
                    rootURL: first.rootURL,
                    recursive: request.mode == .addInPlace
                        && request.recursive,
                    contentHashes: Dictionary(
                        uniqueKeysWithValues: group.map {
                            ($0.asset.id, $0.contentHash)
                        }
                    )
                )
                for item in group {
                    result.importedAssets.append(item.asset)
                    result.transfers.append(PhotoImportTransfer(
                        sourceURL: item.sourceURL,
                        sourceSidecarURL: item.sourceSidecarURL,
                        catalogedURL: item.asset.url,
                        contentHash: item.contentHash,
                        copied: item.copied,
                        reusedDestination:
                            item.reusedDestination
                    ))
                    if item.copied { result.copiedCount += 1 }
                    if item.reusedDestination {
                        result.reusedDestinationCount += 1
                    }
                    if item.renamedByTemplate {
                        result.renamedCount += 1
                    }
                    if let organizedDirectory =
                        item.organizedDirectory {
                        organizedDirectories.insert(
                            organizedDirectory.path
                        )
                    }
                }
            } catch {
                rollback(group)
                for item in group {
                    result.failures.append(
                        "\(item.asset.filename): catalog update failed — \(error.localizedDescription)"
                    )
                }
            }
            cataloged += group.count
        }
        await progress?(PhotoImportProgress(
            phase: .cataloging,
            completed: cataloged,
            total: prepared.count
        ))
        if Task.isCancelled {
            return cancelledResult(
                result,
                request: request,
                pending: [],
                createdImportDirectories:
                    &createdImportDirectories,
                organizedDirectories:
                    organizedDirectories
            )
        }

        if request.mode.removesVerifiedSources,
           let destination {
            let disposition =
                await moveVerifiedSourcesToTrash(
                    result.transfers,
                    destinationURL: destination,
                    progress: progress
                )
            result.movedCount += disposition.movedToTrashCount
            result.retainedSourceCount +=
                disposition.retainedSourceCount
            result.retainedSourceSidecarCount +=
                disposition.retainedSourceSidecarCount
            result.warnings.append(
                contentsOf: disposition.warnings
            )
            if disposition.wasCancelled {
                result.wasCancelled = true
            }
        }
        result.organizedFolderCount = organizedDirectories.count
        removeEmptyImportDirectories(&createdImportDirectories)
        return result
    }

    private func normalized(
        _ request: PhotoImportRequest
    ) -> PhotoImportRequest {
        var seen: Set<String> = []
        let sources = request.sourceURLs.compactMap { raw -> URL? in
            let url = raw.standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            return url
        }
        return PhotoImportRequest(
            sourceURLs: sources,
            mode: request.mode,
            destinationURL: request.destinationURL?.standardizedFileURL,
            recursive: request.recursive,
            skipDuplicates: request.skipDuplicates,
            folderOrganization: request.folderOrganization,
            fileNaming: request.fileNaming,
            customFilenamePrefix:
                PhotoImportRequest.normalizedFilenamePrefix(
                    request.customFilenamePrefix
                ),
            sequenceStart: request.sequenceStart,
            customFolderTemplate:
                request.customFolderTemplate,
            customFilenameTemplate:
                request.customFilenameTemplate
        )
    }

    private func discover(
        request: PhotoImportRequest,
        warnings: inout [String]
    ) -> [PhotoImportItem] {
        var items: [PhotoImportItem] = []
        var seenPaths: Set<String> = []

        func appendFile(_ rawURL: URL, rootURL: URL) {
            let url = rawURL.standardizedFileURL
            guard seenPaths.insert(url.path).inserted else { return }
            do {
                let values = try url.resourceValues(forKeys: [
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isRegularFileKey,
                ])
                guard values.isRegularFile == true else { return }
                if url.pathExtension.lowercased() == "xmp" {
                    return
                }
                let format = FileTypeDetector.format(
                    forExtension: url.pathExtension
                )
                items.append(PhotoImportItem(
                    sourceURL: url,
                    rootURL: rootURL,
                    fileSize: Int64(values.fileSize ?? 0),
                    creationDate: values.creationDate,
                    modificationDate: values.contentModificationDate,
                    format: format,
                    sidecarURL: format == .unsupported
                        ? nil
                        : XMPSidecarService.existingSidecarURL(for: url),
                    status: format == .unsupported
                        ? .unsupported
                        : .ready
                ))
            } catch {
                items.append(PhotoImportItem(
                    sourceURL: url,
                    rootURL: rootURL,
                    fileSize: 0,
                    format: FileTypeDetector.format(
                        forExtension: url.pathExtension
                    ),
                    status: .unavailable(
                        reason: error.localizedDescription
                    )
                ))
            }
        }

        for source in request.sourceURLs {
            do {
                let values = try source.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                ])
                if values.isDirectory == true {
                    let options: FileManager.DirectoryEnumerationOptions =
                        request.recursive
                            ? [.skipsHiddenFiles, .skipsPackageDescendants]
                            : [
                                .skipsHiddenFiles,
                                .skipsPackageDescendants,
                                .skipsSubdirectoryDescendants,
                            ]
                    var enumerationWarnings: [String] = []
                    guard let enumerator = fileManager.enumerator(
                        at: source,
                        includingPropertiesForKeys: [
                            .fileSizeKey,
                            .creationDateKey,
                            .contentModificationDateKey,
                            .isRegularFileKey,
                        ],
                        options: options,
                        errorHandler: { url, error in
                            enumerationWarnings.append(
                                "\(url.lastPathComponent): \(error.localizedDescription)"
                            )
                            return true
                        }
                    ) else {
                        warnings.append(
                            "Could not inspect \(source.path)."
                        )
                        continue
                    }
                    while let next = enumerator.nextObject() as? URL {
                        appendFile(next, rootURL: source)
                    }
                    warnings.append(contentsOf: enumerationWarnings)
                } else if values.isRegularFile == true {
                    appendFile(
                        source,
                        rootURL: source.deletingLastPathComponent()
                    )
                } else {
                    warnings.append(
                        "\(source.lastPathComponent) is not a regular file or folder."
                    )
                }
            } catch {
                items.append(PhotoImportItem(
                    sourceURL: source,
                    rootURL: source.deletingLastPathComponent(),
                    fileSize: 0,
                    format: FileTypeDetector.format(
                        forExtension: source.pathExtension
                    ),
                    status: .unavailable(
                        reason: error.localizedDescription
                    )
                ))
            }
        }
        return items.sorted {
            $0.sourceURL.path.localizedStandardCompare(
                $1.sourceURL.path
            ) == .orderedAscending
        }
    }

    private func catalogDuplicate(
        contentHash: String,
        sourceURL: URL,
        candidates: [CatalogHashCandidate],
        resolvedHashes: inout [String: String]
    ) throws -> CatalogHashCandidate? {
        for candidate in candidates {
            try Task.checkCancellation()
            let candidateURL = URL(fileURLWithPath: candidate.path)
            guard let snapshot = fileSnapshot(candidateURL),
                  snapshot.fileSize == candidate.fileSize,
                  datesMatch(
                      snapshot.modificationDate,
                      candidate.modificationDate
                  ) else {
                continue
            }

            let candidateHash: String
            if let resolved = resolvedHashes[candidate.id] {
                candidateHash = resolved
            } else if let cached = candidate.contentHash {
                candidateHash = cached
                resolvedHashes[candidate.id] = cached
            } else if candidateURL.standardizedFileURL.path
                        == sourceURL.standardizedFileURL.path {
                candidateHash = contentHash
                if try catalogStore.recordContentHash(
                    contentHash,
                    id: candidate.id,
                    expectedFileSize: candidate.fileSize,
                    expectedModificationDate: candidate.modificationDate
                ) {
                    resolvedHashes[candidate.id] = contentHash
                }
            } else {
                let calculated: String
                do {
                    calculated = try stableHash(
                        for: candidateURL,
                        expectedSize: candidate.fileSize,
                        expectedModificationDate:
                            candidate.modificationDate
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // An inaccessible stale catalog candidate must not
                    // prevent a readable source from being imported.
                    continue
                }
                guard try catalogStore.recordContentHash(
                    calculated,
                    id: candidate.id,
                    expectedFileSize: candidate.fileSize,
                    expectedModificationDate: candidate.modificationDate
                ) else {
                    continue
                }
                candidateHash = calculated
                resolvedHashes[candidate.id] = calculated
            }
            if candidateHash == contentHash {
                return candidate
            }
        }
        return nil
    }

    private func stableHash(
        for url: URL,
        expectedSize: Int64,
        expectedModificationDate: Date?
    ) throws -> String {
        guard let before = fileSnapshot(url),
              before.fileSize == expectedSize,
              datesMatch(
                  before.modificationDate,
                  expectedModificationDate
              ) else {
            throw PhotoImportServiceError.sourceChanged(
                filename: url.lastPathComponent
            )
        }
        let hash = try FileContentHasher.sha256(for: url)
        guard let after = fileSnapshot(url),
              before == after else {
            throw PhotoImportServiceError.sourceChanged(
                filename: url.lastPathComponent
            )
        }
        return hash
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

    private func validatedDestination(_ rawURL: URL) throws -> URL {
        let url = rawURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw PhotoImportServiceError.destinationUnavailable
        }
        return url
    }

    private func validateMoveDestination(
        _ destination: URL,
        sources: [URL]
    ) throws {
        let resolvedDestination =
            destination.resolvingSymlinksInPath().standardizedFileURL
        for rawSource in sources {
            let source =
                rawSource.resolvingSymlinksInPath().standardizedFileURL
            guard let values = try? source.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
            ]) else {
                continue
            }
            if values.isDirectory == true {
                if resolvedDestination.path == source.path
                    || isDescendant(
                        resolvedDestination,
                        of: source
                    ) {
                    throw PhotoImportServiceError
                        .moveDestinationConflictsWithSource
                }
            } else if values.isRegularFile == true,
                      resolvedDestination.path
                        == source.deletingLastPathComponent().path {
                throw PhotoImportServiceError
                    .moveDestinationConflictsWithSource
            }
        }
    }

    public func moveVerifiedSourcesToTrash(
        _ transfers: [PhotoImportTransfer],
        destinationURL: URL,
        requiredSourceDirectory: URL? = nil,
        progress: ProgressHandler? = nil
    ) async -> PhotoImportSourceDispositionResult {
        var result = PhotoImportSourceDispositionResult()
        guard !transfers.isEmpty else { return result }

        for (offset, transfer) in transfers.enumerated() {
            if Task.isCancelled {
                retainUndisposedSources(
                    in: transfers[offset...],
                    result: &result
                )
                result.wasCancelled = true
                result.warnings.append(
                    "The import completed, but source cleanup was canceled. Verified sources were retained."
                )
                break
            }

            await progress?(PhotoImportProgress(
                phase: .removingSources,
                completed: offset,
                total: transfers.count,
                filename: transfer.sourceURL.lastPathComponent
            ))
            if Task.isCancelled {
                retainUndisposedSources(
                    in: transfers[offset...],
                    result: &result
                )
                result.wasCancelled = true
                result.warnings.append(
                    "The import completed, but source cleanup was canceled. Verified sources were retained."
                )
                break
            }

            do {
                try moveVerifiedSourceToTrash(
                    transfer,
                    destination: destinationURL,
                    requiredSourceDirectory:
                        requiredSourceDirectory
                )
                result.movedToTrashCount += 1
            } catch {
                if fileManager.fileExists(
                    atPath: transfer.sourceURL.path
                ) {
                    result.retainedSourceCount += 1
                }
                if let sidecar = transfer.sourceSidecarURL,
                   fileManager.fileExists(atPath: sidecar.path) {
                    result.retainedSourceSidecarCount += 1
                }
                result.warnings.append(
                    "\(transfer.sourceURL.lastPathComponent) was imported and its destination was kept, but source cleanup did not complete. The source was not permanently deleted: \(error.localizedDescription)"
                )
            }
        }

        if !result.wasCancelled {
            await progress?(PhotoImportProgress(
                phase: .removingSources,
                completed: transfers.count,
                total: transfers.count
            ))
        }
        return result
    }

    private func moveVerifiedSourceToTrash(
        _ transfer: PhotoImportTransfer,
        destination: URL,
        requiredSourceDirectory: URL?
    ) throws {
        let source = transfer.sourceURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let target = transfer.catalogedURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedDestination = destination
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedRequiredSourceDirectory =
            requiredSourceDirectory?
                .resolvingSymlinksInPath()
                .standardizedFileURL

        guard source.path != target.path,
              isDescendant(target, of: resolvedDestination),
              resolvedRequiredSourceDirectory == nil
                || source.deletingLastPathComponent().path
                    == resolvedRequiredSourceDirectory?.path,
              fileManager.fileExists(atPath: source.path),
              fileManager.fileExists(atPath: target.path) else {
            throw PhotoImportServiceError.sourceRemovalFailed(
                filename: source.lastPathComponent,
                reason:
                    "the verified source and destination no longer match the Copy + Trash request."
            )
        }

        guard try FileContentHasher.sha256(for: source)
                == transfer.contentHash,
              try FileContentHasher.sha256(for: target)
                == transfer.contentHash else {
            throw PhotoImportServiceError.copyVerificationFailed(
                filename: source.lastPathComponent
            )
        }

        var verifiedSidecarPair: (source: URL, target: URL)?
        if let rawSourceSidecar = transfer.sourceSidecarURL {
            let sourceSidecar = rawSourceSidecar
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let targetSidecar =
                XMPSidecarService.canonicalSidecarURL(for: target)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            guard sourceSidecar.deletingLastPathComponent().path
                    == source.deletingLastPathComponent().path,
                  sourceSidecar.path != targetSidecar.path,
                  isDescendant(
                      targetSidecar,
                      of: resolvedDestination
                  ),
                  fileManager.fileExists(
                atPath: sourceSidecar.path
            ), fileManager.fileExists(
                atPath: targetSidecar.path
            ), try FileContentHasher.sha256(for: sourceSidecar)
                == FileContentHasher.sha256(for: targetSidecar) else {
                throw PhotoImportServiceError
                    .copyVerificationFailed(
                        filename: sourceSidecar.lastPathComponent
                    )
            }
            verifiedSidecarPair = (sourceSidecar, targetSidecar)
        }

        // Trash the sidecar first. If that step fails, the source photograph
        // has not moved. A later photo failure can therefore leave the
        // recoverable sidecar in Trash while retaining both photo copies.
        if let sidecarPair = verifiedSidecarPair {
            do {
                try sourceRemovalHandler(sidecarPair.source)
                guard !fileManager.fileExists(
                    atPath: sidecarPair.source.path
                ) else {
                    throw PhotoImportServiceError.sourceRemovalFailed(
                        filename: sidecarPair.source.lastPathComponent,
                        reason:
                            "the source sidecar still exists after the Trash operation."
                    )
                }
            } catch let error as PhotoImportServiceError {
                throw error
            } catch {
                throw PhotoImportServiceError.sourceRemovalFailed(
                    filename: sidecarPair.source.lastPathComponent,
                    reason: error.localizedDescription
                )
            }
        }

        do {
            try sourceRemovalHandler(source)
            guard !fileManager.fileExists(atPath: source.path) else {
                throw PhotoImportServiceError.sourceRemovalFailed(
                    filename: source.lastPathComponent,
                    reason:
                        "the source still exists after the Trash operation."
                )
            }
        } catch let error as PhotoImportServiceError {
            throw error
        } catch {
            throw PhotoImportServiceError.sourceRemovalFailed(
                filename: source.lastPathComponent,
                reason: error.localizedDescription
            )
        }
    }

    private func retainUndisposedSources(
        in transfers: ArraySlice<PhotoImportTransfer>,
        result: inout PhotoImportSourceDispositionResult
    ) {
        for transfer in transfers {
            if fileManager.fileExists(
                atPath: transfer.sourceURL.path
            ) {
                result.retainedSourceCount += 1
            }
            if let sidecar = transfer.sourceSidecarURL,
               fileManager.fileExists(atPath: sidecar.path) {
                result.retainedSourceSidecarCount += 1
            }
        }
    }

    private func isDescendant(
        _ candidate: URL,
        of directory: URL
    ) -> Bool {
        let directoryPath =
            directory.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath =
            candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = directoryPath.hasSuffix("/")
            ? directoryPath
            : directoryPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    private func copyPhoto(
        _ item: PhotoImportItem,
        to destination: URL,
        reuseIdentical: Bool,
        preferredBaseName: String?
    ) throws -> CopyOutcome {
        let selected = try collisionSafeDestination(
            for: item,
            in: destination,
            reuseIdentical: reuseIdentical,
            preferredBaseName: preferredBaseName
        )
        var createdPhotoURL: URL?
        var createdSidecarURL: URL?
        do {
            if !selected.reusesExistingPhoto {
                try verifiedCopy(
                    from: item.sourceURL,
                    to: selected.photoURL,
                    expectedHash: try requiredHash(item)
                )
                createdPhotoURL = selected.photoURL
            }
            if let sourceSidecar = item.sidecarURL {
                let destinationSidecar =
                    XMPSidecarService.canonicalSidecarURL(
                        for: selected.photoURL
                    )
                if sourceSidecar.standardizedFileURL.path
                    != destinationSidecar.standardizedFileURL.path,
                   !fileManager.fileExists(
                       atPath: destinationSidecar.path
                   ) {
                    try verifiedCopy(
                        from: sourceSidecar,
                        to: destinationSidecar,
                        expectedHash: try FileContentHasher.sha256(
                            for: sourceSidecar
                        )
                    )
                    createdSidecarURL = destinationSidecar
                }
            }
            return CopyOutcome(
                photoURL: selected.photoURL,
                createdPhotoURL: createdPhotoURL,
                createdSidecarURL: createdSidecarURL,
                reusedExistingPhoto: selected.reusesExistingPhoto
            )
        } catch {
            if let createdSidecarURL {
                try? fileManager.removeItem(at: createdSidecarURL)
            }
            if let createdPhotoURL {
                try? fileManager.removeItem(at: createdPhotoURL)
            }
            throw error
        }
    }

    private func collisionSafeDestination(
        for item: PhotoImportItem,
        in destination: URL,
        reuseIdentical: Bool,
        preferredBaseName: String?
    ) throws -> DestinationChoice {
        let filename = preferredBaseName
            ?? item.sourceURL.deletingPathExtension().lastPathComponent
        let ext = item.sourceURL.pathExtension
        let expectedHash = try requiredHash(item)

        for index in 1...10_000 {
            let suffix = index == 1 ? "" : " \(index)"
            let name = filename + suffix
            let candidate = ext.isEmpty
                ? destination.appendingPathComponent(name)
                : destination.appendingPathComponent(name)
                    .appendingPathExtension(ext)
            let sidecar = XMPSidecarService.canonicalSidecarURL(
                for: candidate
            )
            let photoExists = fileManager.fileExists(
                atPath: candidate.path
            )
            let sidecarExists = fileManager.fileExists(
                atPath: sidecar.path
            )
            if !photoExists && !sidecarExists {
                return DestinationChoice(
                    photoURL: candidate,
                    reusesExistingPhoto: false
                )
            }
            if photoExists, reuseIdentical,
               isDescendant(candidate, of: destination),
               let snapshot = fileSnapshot(candidate),
               snapshot.fileSize == item.fileSize,
               try FileContentHasher.sha256(for: candidate)
                    == expectedHash {
                return DestinationChoice(
                    photoURL: candidate,
                    reusesExistingPhoto: true
                )
            }
        }
        throw PhotoImportServiceError.destinationNameExhausted
    }

    private func verifiedCopy(
        from source: URL,
        to destination: URL,
        expectedHash: String
    ) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(
                ".rawdesk-import-\(UUID().uuidString).tmp"
            )
        defer {
            if fileManager.fileExists(atPath: temporary.path) {
                try? fileManager.removeItem(at: temporary)
            }
        }
        try fileManager.copyItem(at: source, to: temporary)
        let copiedHash = try FileContentHasher.sha256(for: temporary)
        guard copiedHash == expectedHash else {
            throw PhotoImportServiceError.copyVerificationFailed(
                filename: source.lastPathComponent
            )
        }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private func requiredHash(_ item: PhotoImportItem) throws -> String {
        guard let hash = item.contentHash else {
            throw PhotoImportServiceError.sourceChanged(
                filename: item.sourceURL.lastPathComponent
            )
        }
        return hash
    }

    private func templateContext(
        for item: PhotoImportItem,
        sequence: Int
    ) -> PhotoImportTemplateContext {
        let metadata = MetadataReader.read(
            url: item.sourceURL
        )
        return PhotoImportTemplateContext(
            sourceURL: item.sourceURL,
            captureDate: metadata.captureDate,
            fallbackDate:
                item.modificationDate ?? item.creationDate,
            cameraMake: metadata.cameraMake,
            cameraModel: metadata.cameraModel,
            sequence: sequence
        )
    }

    private func preferredBaseName(
        request: PhotoImportRequest,
        context: PhotoImportTemplateContext
    ) throws -> String? {
        switch request.fileNaming {
        case .originalFilename:
            return nil
        case .customSequence:
            let prefix =
                PhotoImportRequest.normalizedFilenamePrefix(
                    request.customFilenamePrefix
                )
            return "\(prefix)-\(String(format: "%04d", context.sequence))"
        case .tokenTemplate:
            return try PhotoImportTemplateRenderer
                .renderFilenameBase(
                    request.customFilenameTemplate,
                    context: context
                )
        }
    }

    private func destinationDirectory(
        base: URL,
        request: PhotoImportRequest,
        context: PhotoImportTemplateContext,
        createdDirectories: inout Set<String>
    ) throws -> URL {
        let components: [String]
        switch request.folderOrganization {
        case .singleFolder:
            return base
        case .customTemplate:
            components = try PhotoImportTemplateRenderer
                .renderFolderComponents(
                    request.customFolderTemplate,
                    context: context
                )
        case .captureDate:
            if let date = context.captureDate
                ?? context.fallbackDate {
                var calendar = Calendar(
                    identifier: .gregorian
                )
                calendar.timeZone =
                    TimeZone(secondsFromGMT: 0) ?? .current
                let values = calendar.dateComponents(
                    [.year, .month, .day],
                    from: date
                )
                if let year = values.year,
                   let month = values.month,
                   let day = values.day {
                    components = [
                        String(format: "%04d", year),
                        String(
                            format: "%04d-%02d-%02d",
                            year,
                            month,
                            day
                        ),
                    ]
                } else {
                    components = ["Unknown Date"]
                }
            } else {
                components = ["Unknown Date"]
            }
        }

        var directory = base
        for component in components {
            directory.appendPathComponent(
                component,
                isDirectory: true
            )
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: directory.path,
                isDirectory: &isDirectory
            ) {
                guard isDirectory.boolValue,
                      isDescendant(directory, of: base) else {
                    throw PhotoImportServiceError
                        .destinationSubfolderUnavailable(
                            name: component
                        )
                }
                continue
            }
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false
                )
                guard isDescendant(directory, of: base) else {
                    try? fileManager.removeItem(at: directory)
                    throw PhotoImportServiceError
                        .destinationSubfolderUnavailable(
                            name: component
                        )
                }
                createdDirectories.insert(directory.path)
            } catch {
                throw PhotoImportServiceError
                    .destinationSubfolderUnavailable(name: component)
            }
        }
        return directory
    }

    private func removeEmptyImportDirectories(
        _ directories: inout Set<String>
    ) {
        for path in directories.sorted(by: {
            ($0 as NSString).pathComponents.count
                > ($1 as NSString).pathComponents.count
        }) {
            guard let contents = try? fileManager
                .contentsOfDirectory(atPath: path),
                  contents.isEmpty else {
                continue
            }
            try? fileManager.removeItem(atPath: path)
            directories.remove(path)
        }
    }

    private func cancelledResult(
        _ partialResult: PhotoImportResult,
        request: PhotoImportRequest,
        pending: [PreparedImport],
        createdImportDirectories:
            inout Set<String>,
        organizedDirectories: Set<String>
    ) -> PhotoImportResult {
        rollback(pending)
        var result = partialResult
        result.wasCancelled = true
        if request.mode.removesVerifiedSources {
            result.retainedSourceCount +=
                result.transfers.filter {
                    fileManager.fileExists(
                        atPath: $0.sourceURL.path
                    )
                }.count
        }
        result.organizedFolderCount =
            organizedDirectories.count
        removeEmptyImportDirectories(
            &createdImportDirectories
        )
        return result
    }

    private func rollback(_ items: [PreparedImport]) {
        for item in items.reversed() {
            if let sidecar = item.createdSidecarURL {
                try? fileManager.removeItem(at: sidecar)
            }
            if let photo = item.createdPhotoURL {
                try? fileManager.removeItem(at: photo)
            }
        }
    }

    private func removeIfCreated(_ url: URL?) {
        guard let url else { return }
        try? fileManager.removeItem(at: url)
    }
}

private struct FileSnapshot: Equatable {
    var fileSize: Int64
    var modificationDate: Date?
}

private struct DestinationChoice {
    var photoURL: URL
    var reusesExistingPhoto: Bool
}

private struct CopyOutcome {
    var photoURL: URL
    var createdPhotoURL: URL?
    var createdSidecarURL: URL?
    var reusedExistingPhoto: Bool
}

private struct PreparedImport {
    var sourceURL: URL
    var sourceSidecarURL: URL?
    var asset: PhotoAsset
    var rootURL: URL
    var contentHash: String
    var createdPhotoURL: URL?
    var createdSidecarURL: URL?
    var copied: Bool
    var reusedDestination: Bool
    var renamedByTemplate: Bool
    var organizedDirectory: URL?
}
