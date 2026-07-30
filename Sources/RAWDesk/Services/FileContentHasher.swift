import CryptoKit
import Foundation
import ImageIO

public enum FileContentHasher {
    private static let chunkSize = 1_024 * 1_024

    public static func sha256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: chunkSize),
                  !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }
}

public enum ImageContentHasherError: LocalizedError, Equatable {
    case unreadableImage
    case unreadablePixels
    case invalidPixelLayout

    public var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The file does not contain decodable image data."
        case .unreadablePixels:
            return "The decoded image pixels are unavailable."
        case .invalidPixelLayout:
            return "The decoded image has an invalid pixel layout."
        }
    }
}

/// Calculates a metadata-insensitive SHA-256 over decoded source image data.
///
/// File names, EXIF/IPTC/XMP blocks, color-profile metadata, and catalog edits
/// are deliberately excluded. The digest includes the decoded raster geometry
/// and component layout, then every meaningful row byte without row padding.
/// This makes metadata-only container copies match without treating a visually
/// similar re-encoding as an exact duplicate.
public enum ImageContentHasher {
    private static let version = "rawdesk-image-data-v1"

    public static func sha256(for url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary
        ),
        let image = CGImageSourceCreateImageAtIndex(
            source,
            0,
            [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        ) else {
            throw ImageContentHasherError.unreadableImage
        }
        return try sha256(for: image)
    }

    public static func sha256(for image: CGImage) throws -> String {
        guard let provider = image.dataProvider,
              let providerData = provider.data else {
            throw ImageContentHasherError.unreadablePixels
        }
        let (bitCount, bitCountOverflow) =
            image.width.multipliedReportingOverflow(
                by: image.bitsPerPixel
            )
        guard !bitCountOverflow else {
            throw ImageContentHasherError.invalidPixelLayout
        }
        let meaningfulRowBytes = (bitCount + 7) / 8
        let (requiredBytes, requiredBytesOverflow) =
            image.bytesPerRow.multipliedReportingOverflow(
                by: image.height
            )
        let data = providerData as Data
        guard !requiredBytesOverflow,
              image.width > 0,
              image.height > 0,
              image.bitsPerComponent > 0,
              image.bitsPerPixel > 0,
              meaningfulRowBytes > 0,
              image.bytesPerRow >= meaningfulRowBytes,
              requiredBytes <= data.count else {
            throw ImageContentHasherError.invalidPixelLayout
        }

        var hasher = SHA256()
        hasher.update(data: Data(
            """
            \(version)
            \(image.width)x\(image.height)
            \(image.bitsPerComponent):\(image.bitsPerPixel):\(image.bitmapInfo.rawValue)

            """.utf8
        ))
        for row in 0..<image.height {
            try Task.checkCancellation()
            let start = row * image.bytesPerRow
            let end = start + meaningfulRowBytes
            hasher.update(data: data[start..<end])
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }
}

/// Performs a catalog-wide duplicate pass with guarded cached signatures.
///
/// Decodable photos use their exact decoded image-data SHA-256, so filename or
/// metadata-only differences do not hide duplicates. Files that ImageIO cannot
/// decode retain the complete-file SHA-256 fallback when another file has the
/// same byte size. Recorded file facts are checked before cached signatures
/// are trusted and both before and after a new signature is calculated.
public actor CatalogDuplicateScanner {
    public typealias ProgressHandler =
        @Sendable (CatalogDuplicateScanProgress) async -> Void

    private let catalogStore: CatalogStore

    public init(catalogStore: CatalogStore = .shared) {
        self.catalogStore = catalogStore
    }

    public func scan(
        forceRehash: Bool = false,
        progress: ProgressHandler? = nil
    ) async throws -> CatalogDuplicateScanResult {
        try catalogStore.refreshMissingStatus()
        let candidates = try catalogStore.duplicateScanCandidates()
        let repeatedFileSizes = Set(
            Dictionary(grouping: candidates, by: \.fileSize)
                .compactMap {
                    $0.value.count > 1 ? $0.key : nil
                }
        )
        var newlyHashedCount = 0
        var cachedHashCount = 0
        var unavailablePaths: [String] = []

        await progress?(CatalogDuplicateScanProgress(
            total: candidates.count
        ))

        for (offset, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress?(CatalogDuplicateScanProgress(
                completed: offset,
                total: candidates.count,
                filename: URL(fileURLWithPath: candidate.path)
                    .lastPathComponent,
                newlyHashedCount: newlyHashedCount,
                cachedHashCount: cachedHashCount,
                unavailableCount: unavailablePaths.count
            ))

            let url = URL(fileURLWithPath: candidate.path)
            guard let before = fileSnapshot(url),
                  before.fileSize == candidate.fileSize,
                  datesMatch(
                      before.modificationDate,
                      candidate.modificationDate
                  ) else {
                try? catalogStore.clearDuplicateSignatures(
                    id: candidate.id
                )
                unavailablePaths.append(candidate.path)
                continue
            }

            if candidate.imageContentHash != nil, !forceRehash {
                cachedHashCount += 1
                continue
            }

            do {
                let imageContentHash =
                    try ImageContentHasher.sha256(for: url)
                guard let after = fileSnapshot(url),
                      after == before,
                      try catalogStore.recordImageContentHash(
                          imageContentHash,
                          id: candidate.id,
                          expectedFileSize: candidate.fileSize,
                          expectedModificationDate:
                              candidate.modificationDate
                      ) else {
                    try? catalogStore.clearDuplicateSignatures(
                        id: candidate.id
                    )
                    unavailablePaths.append(candidate.path)
                    continue
                }
                newlyHashedCount += 1
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? catalogStore.clearImageContentHash(
                    id: candidate.id
                )
            }

            guard repeatedFileSizes.contains(candidate.fileSize) else {
                unavailablePaths.append(candidate.path)
                continue
            }
            if candidate.contentHash != nil, !forceRehash {
                cachedHashCount += 1
                continue
            }

            do {
                let contentHash = try FileContentHasher.sha256(for: url)
                guard let after = fileSnapshot(url),
                      after == before,
                      try catalogStore.recordContentHash(
                          contentHash,
                          id: candidate.id,
                          expectedFileSize: candidate.fileSize,
                          expectedModificationDate:
                              candidate.modificationDate
                      ) else {
                    try? catalogStore.clearDuplicateSignatures(
                        id: candidate.id
                    )
                    unavailablePaths.append(candidate.path)
                    continue
                }
                newlyHashedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? catalogStore.clearDuplicateSignatures(
                    id: candidate.id
                )
                unavailablePaths.append(candidate.path)
            }
        }

        let groups = try catalogStore.exactDuplicateGroups()
        await progress?(CatalogDuplicateScanProgress(
            completed: candidates.count,
            total: candidates.count,
            newlyHashedCount: newlyHashedCount,
            cachedHashCount: cachedHashCount,
            unavailableCount: unavailablePaths.count
        ))
        return CatalogDuplicateScanResult(
            groups: groups,
            candidateCount: candidates.count,
            newlyHashedCount: newlyHashedCount,
            cachedHashCount: cachedHashCount,
            unavailablePaths: unavailablePaths
        )
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
