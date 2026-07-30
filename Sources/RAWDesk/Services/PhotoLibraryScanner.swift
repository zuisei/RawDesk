import Foundation

public enum PhotoAssetInspectionError: LocalizedError, Equatable, Sendable {
    case unsupported
    case notRegularFile

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "The file is not a supported image."
        case .notRegularFile:
            return "The selected item is not a readable regular file."
        }
    }
}

public actor PhotoLibraryScanner {

    public struct ScanResult: Sendable {
        public var assets: [PhotoAsset]
        public var errors: [String]
        public var rootURL: URL
    }

    public struct AssetInspection: Sendable {
        public var asset: PhotoAsset
        public var warnings: [String]

        public init(asset: PhotoAsset, warnings: [String] = []) {
            self.asset = asset
            self.warnings = warnings
        }
    }

    public init() {}

    /// Scan a folder for supported images. Optionally recursive.
    /// Runs off the main thread (called via Task).
    public func scan(
        rootURL: URL,
        recursive: Bool,
        userStates: [String: PhotoUserState],
        colorLabelSet: PhotoColorLabelSet = .standard
    ) async -> ScanResult {
        var assets: [PhotoAsset] = []
        var errors: [String] = []

        let fm = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [
                .fileSizeKey, .creationDateKey,
                .contentModificationDateKey, .isRegularFileKey,
                .fileResourceIdentifierKey
            ],
            options: opts,
            errorHandler: { url, error in
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                return true
            }
        ) else {
            return ScanResult(assets: [], errors: ["Cannot enumerate \(rootURL.path)"], rootURL: rootURL)
        }

        while let next = enumerator.nextObject() {
            if Task.isCancelled { break }
            guard let url = next as? URL else { continue }
            guard FileTypeDetector.isSupported(url: url) else { continue }

            do {
                let inspection = try Self.inspectAsset(
                    at: url,
                    userStates: userStates,
                    colorLabelSet: colorLabelSet
                )
                assets.append(inspection.asset)
                errors.append(contentsOf: inspection.warnings)
            } catch {
                errors.append(
                    "\(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        assets.sort { lhs, rhs in
            let l = lhs.creationDate ?? lhs.modificationDate ?? .distantPast
            let r = rhs.creationDate ?? rhs.modificationDate ?? .distantPast
            if l == r { return lhs.filename < rhs.filename }
            return l > r
        }

        return ScanResult(assets: assets, errors: errors, rootURL: rootURL)
    }

    public static func inspectAsset(
        at sourceURL: URL,
        userStates: [String: PhotoUserState],
        colorLabelSet: PhotoColorLabelSet = .standard
    ) throws -> AssetInspection {
        let url = sourceURL.standardizedFileURL
        guard FileTypeDetector.isSupported(url: url) else {
            throw PhotoAssetInspectionError.unsupported
        }
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .fileResourceIdentifierKey,
        ])
        guard values.isRegularFile == true else {
            throw PhotoAssetInspectionError.notRegularFile
        }

        let size = Int64(values.fileSize ?? 0)
        let creation = values.creationDate
        let modification = values.contentModificationDate
        let ext = url.pathExtension
        let format = FileTypeDetector.format(forExtension: ext)
        let legacyID = legacyStableID(
            path: url.path,
            size: size,
            modification: modification
        )
        let id = stableID(
            path: url.path,
            size: size,
            modification: modification,
            resourceIdentifier: values.fileResourceIdentifier
        )
        // Image I/O reads container metadata without decoding the full image.
        // Keep it on the scanner actor so capture time, camera, and exposure
        // fields are cataloged during the initial folder scan instead of only
        // after a photo happens to be opened in the inspector. Features that
        // operate across the library (notably capture-time auto stacking) must
        // not depend on which thumbnails the user has already selected.
        let metadata = MetadataReader.read(url: url)
        // Path-based IDs from earlier releases migrate transparently.
        let storedState = userStates[id] ?? userStates[legacyID]
        let sidecarURL = XMPSidecarService.existingSidecarURL(for: url)
        var userState = storedState ?? .empty
        var importedFromXMP = false
        var warnings: [String] = []
        if storedState == nil, let sidecarURL {
            do {
                let result = try XMPSidecarService.read(
                    from: sidecarURL,
                    merging: .empty,
                    colorLabelSet: colorLabelSet
                )
                if result.importedFieldCount > 0 {
                    userState = result.state
                    importedFromXMP = true
                }
                warnings.append(contentsOf: result.warnings.map {
                    "\(sidecarURL.lastPathComponent): \($0)"
                })
            } catch {
                warnings.append(
                    "\(sidecarURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        return AssetInspection(
            asset: PhotoAsset(
                id: id,
                url: url,
                path: url.path,
                filename: url.lastPathComponent,
                fileExtension: ext,
                fileSize: size,
                creationDate: creation,
                modificationDate: modification,
                format: format,
                metadata: metadata,
                userState: userState,
                xmpSidecarURL: sidecarURL,
                xmpImportedOnScan: importedFromXMP
            ),
            warnings: warnings
        )
    }

    public static func stableID(
        path: String,
        size: Int64,
        modification: Date?,
        resourceIdentifier: Any? = nil
    ) -> String {
        if let resourceIdentifier,
           let stableResource = resourceIdentifierString(resourceIdentifier) {
            return "file-resource|\(stableResource)"
        }
        return legacyStableID(path: path, size: size, modification: modification)
    }

    public static func legacyStableID(path: String, size: Int64, modification: Date?) -> String {
        let mod = modification?.timeIntervalSinceReferenceDate ?? 0
        return "\(path)|\(size)|\(mod)"
    }

    private static func resourceIdentifierString(_ identifier: Any) -> String? {
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        if let number = identifier as? NSNumber {
            return number.stringValue
        }
        let description = String(describing: identifier)
        return description.isEmpty ? nil : description
    }
}
