import Foundation
import AppKit
import ImageIO
import QuickLookThumbnailing

public enum ThumbnailGenerator {

    /// Quality hint controlling whether the loader is allowed to use embedded
    /// JPEG thumbnails (fast but small) or must always decode from the full
    /// image (sharp).
    public enum Quality {
        case grid       // small target, embedded thumb is acceptable
        case preview    // large target, must decode the full image
    }

    /// Synchronously generate a thumbnail. Caller is responsible for off-main dispatch.
    public static func generate(
        for asset: PhotoAsset,
        targetPixelSize: CGFloat,
        quality: Quality
    ) throws -> NSImage {
        if asset.format.isRaw {
            return try RAWImageLoader.load(
                url: asset.url,
                targetLongestEdge: targetPixelSize,
                preserveWideGamut: quality == .preview
            )
        }

        if let img = imageIOThumbnail(url: asset.url, target: targetPixelSize, quality: quality) {
            return img
        }
        if let img = quickLook(url: asset.url, target: targetPixelSize) {
            return img
        }
        throw RAWImageLoader.LoaderError.allStagesFailed(stages: ["ImageIO", "QuickLook"])
    }

    private static func imageIOThumbnail(url: URL, target: CGFloat, quality: Quality) -> NSImage? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else { return nil }

        // For previews we always force decoding from the full image so we never
        // up-scale a tiny embedded thumbnail. For the grid we allow the embedded
        // thumbnail when one is present *and large enough*; otherwise we fall
        // through to a full decode.
        let alwaysFromFull = (quality == .preview)
        let target = max(64, Int(target.rounded()))

        let primary: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: !alwaysFromFull,
            kCGImageSourceCreateThumbnailFromImageAlways: alwaysFromFull,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]

        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, primary as CFDictionary) {
            // Guard against tiny embedded thumbs being returned for the grid.
            // If the result is severely smaller than requested, redo from the full image.
            let longest = max(cg.width, cg.height)
            if alwaysFromFull || longest >= target / 2 {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }

        let force: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, force as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func quickLook(url: URL, target: CGFloat) -> NSImage? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: target, height: target),
            scale: 1.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            if let rep { result = rep.nsImage }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
}
