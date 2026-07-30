import Foundation
import AppKit
import CryptoKit

/// Bounded memory caches plus a persistent thumbnail cache.
public final class ImageCache: @unchecked Sendable {

    public static let shared = ImageCache()

    private let thumbnailCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 4096
        c.totalCostLimit = 256 * 1024 * 1024 // ~256MB approx
        return c
    }()
    private let thumbnailDecodeSourceCache:
        NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 4096
        return cache
    }()

    private let previewCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 32
        c.totalCostLimit = 512 * 1024 * 1024
        return c
    }()

    private let diskDirectory: URL
    private let diskQueue = DispatchQueue(label: "rawdesk.thumbnail.disk-cache")
    private let maximumDiskBytes: Int64 = 1_024 * 1_024 * 1_024

    public init(directory: URL? = nil) {
        if let directory {
            diskDirectory = directory
        } else {
            let base = (try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            diskDirectory = base
                .appendingPathComponent("RAWDesk", isDirectory: true)
                .appendingPathComponent("Thumbnails", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: diskDirectory,
            withIntermediateDirectories: true
        )
        diskQueue.async { [weak self] in
            self?.pruneDiskCacheIfNeeded()
        }
    }

    public static func key(for asset: PhotoAsset, target: CGFloat, scale: CGFloat) -> String {
        let mod = asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(asset.path)|\(asset.fileSize)|\(mod)|\(Int(target))|\(Int(scale))"
    }

    public func thumbnail(for key: String) -> NSImage? {
        if let memory = thumbnailCache.object(forKey: key as NSString) {
            return memory
        }
        let diskImage: NSImage? = diskQueue.sync {
            let url = diskURL(for: key)
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { return nil }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
            return image
        }
        if let diskImage {
            storeThumbnailInMemory(diskImage, for: key)
        }
        return diskImage
    }

    public func thumbnailDecodeSource(
        for key: String
    ) -> RAWImageLoader.DecodeSource? {
        if let cached = thumbnailDecodeSourceCache.object(
            forKey: key as NSString
        ) {
            return RAWImageLoader.DecodeSource(
                rawValue: cached as String
            )
        }
        let rawValue: String? = diskQueue.sync {
            guard let data = try? Data(
                contentsOf: decodeSourceURL(for: key)
            ) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
        guard let rawValue,
              let source = RAWImageLoader.DecodeSource(
                rawValue: rawValue
              ) else {
            return nil
        }
        thumbnailDecodeSourceCache.setObject(
            rawValue as NSString,
            forKey: key as NSString
        )
        return source
    }

    public func storeThumbnail(
        _ image: NSImage,
        for key: String,
        rawDecodeSource:
            RAWImageLoader.DecodeSource? = nil
    ) {
        storeThumbnailInMemory(image, for: key)
        if let rawDecodeSource {
            thumbnailDecodeSourceCache.setObject(
                rawDecodeSource.rawValue as NSString,
                forKey: key as NSString
            )
        }
        guard let data = jpegData(for: image) else { return }
        diskQueue.async { [weak self] in
            guard let self else { return }
            let url = self.diskURL(for: key)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url, options: [.atomic])
            }
            if let rawDecodeSource {
                try? Data(
                    rawDecodeSource.rawValue.utf8
                ).write(
                    to: self.decodeSourceURL(for: key),
                    options: [.atomic]
                )
            }
        }
    }

    public func preview(for key: String) -> NSImage? {
        previewCache.object(forKey: key as NSString)
    }
    public func storePreview(_ image: NSImage, for key: String) {
        let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        )
        let bytesPerPixel = max(
            1,
            (cgImage?.bitsPerPixel ?? 32) / 8
        )
        let cost =
            (cgImage?.width ?? Int(image.size.width))
            * (cgImage?.height ?? Int(image.size.height))
            * bytesPerPixel
        previewCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    public func clear() {
        thumbnailCache.removeAllObjects()
        thumbnailDecodeSourceCache.removeAllObjects()
        previewCache.removeAllObjects()
        diskQueue.sync {
            try? FileManager.default.removeItem(at: diskDirectory)
            try? FileManager.default.createDirectory(
                at: diskDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    /// Waits for queued thumbnail writes. Primarily used by deterministic tests.
    public func flushDiskWrites() {
        diskQueue.sync {}
    }

    private func storeThumbnailInMemory(_ image: NSImage, for key: String) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let cost = (cg?.width ?? Int(image.size.width))
            * (cg?.height ?? Int(image.size.height))
            * 4
        thumbnailCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func jpegData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.88]
        )
    }

    private func diskURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
        return diskDirectory.appendingPathComponent(filename)
    }

    private func decodeSourceURL(
        for key: String
    ) -> URL {
        diskURL(for: key)
            .deletingPathExtension()
            .appendingPathExtension("raw-source")
    }

    private func pruneDiskCacheIfNeeded() {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for url in files {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            entries.append((
                url: url,
                size: size,
                date: values.contentModificationDate ?? .distantPast
            ))
            total += size
        }
        guard total > maximumDiskBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            if total <= maximumDiskBytes { break }
        }
    }
}
