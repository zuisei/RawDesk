import Foundation
import AppKit
import CoreImage
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Layered RAW loader. Tries CIRAWFilter, then CIImage, then Image I/O embedded preview,
/// then Quick Look. Returns NSImage on success, throws on total failure.
public enum RAWImageLoader {

    public enum DecodeSource:
        String,
        Equatable,
        Sendable
    {
        case ciRAWFilter
        case coreImage
        case embeddedPreview
        case quickLook

        public var displayName: String {
            switch self {
            case .ciRAWFilter:
                return "CIRAWFilter"
            case .coreImage:
                return "Core Image"
            case .embeddedPreview:
                return "Embedded preview"
            case .quickLook:
                return "Quick Look preview"
            }
        }
    }

    public struct LoadResult {
        public let image: NSImage
        public let source: DecodeSource
    }

    public enum LoaderError: Error, LocalizedError {
        case allStagesFailed(stages: [String])
        public var errorDescription: String? {
            switch self {
            case .allStagesFailed(let stages):
                return "Could not decode RAW file. Tried: \(stages.joined(separator: ", "))"
            }
        }
    }

    private static let displayContext = CIContext(
        options: [.useSoftwareRenderer: false]
    )
    private static let wideColorSpace =
        CGColorSpace(
            name: CGColorSpace.extendedLinearSRGB
        ) ?? CGColorSpaceCreateDeviceRGB()
    private static let wideContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: wideColorSpace,
        .outputColorSpace: wideColorSpace,
    ])

    /// Load a RAW file at a target longest-edge size (in pixels). Pass nil for full size.
    public static func load(
        url: URL,
        targetLongestEdge: CGFloat?,
        preserveWideGamut: Bool = false
    ) throws -> NSImage {
        try loadResult(
            url: url,
            targetLongestEdge: targetLongestEdge,
            preserveWideGamut: preserveWideGamut
        ).image
    }

    public static func loadResult(
        url: URL,
        targetLongestEdge: CGFloat?,
        preserveWideGamut: Bool = false
    ) throws -> LoadResult {
        var failures: [String] = []

        if let img = tryCIRAW(
            url: url,
            targetLongestEdge: targetLongestEdge,
            preserveWideGamut: preserveWideGamut
        ) {
            return LoadResult(
                image: img,
                source: .ciRAWFilter
            )
        } else {
            failures.append("CIRAWFilter")
        }

        if let img = tryCIImage(
            url: url,
            targetLongestEdge: targetLongestEdge,
            preserveWideGamut: preserveWideGamut
        ) {
            return LoadResult(
                image: img,
                source: .coreImage
            )
        } else {
            failures.append("CIImage")
        }

        if let img = tryImageIOEmbedded(url: url, targetLongestEdge: targetLongestEdge) {
            return LoadResult(
                image: img,
                source: .embeddedPreview
            )
        } else {
            failures.append("ImageIO embedded preview")
        }

        if let target = targetLongestEdge,
           let img = tryQuickLook(url: url, target: target) {
            return LoadResult(
                image: img,
                source: .quickLook
            )
        } else {
            failures.append("QuickLook")
        }

        throw LoaderError.allStagesFailed(stages: failures)
    }

    /// Returns a display-sized embedded thumbnail without running the full
    /// RAW pipeline. Grid cells use this fast path; Loupe and Develop still
    /// call `loadResult` so edit and export decisions are based on RAW data.
    public static func loadGridThumbnail(
        url: URL,
        targetLongestEdge: CGFloat
    ) -> NSImage? {
        tryImageIOEmbeddedOnly(
            url: url,
            targetLongestEdge: targetLongestEdge
        )
    }

    // MARK: - Stages

    private static func tryImageIOEmbeddedOnly(
        url: URL,
        targetLongestEdge: CGFloat
    ) -> NSImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        // Both generation flags are false on purpose: return an embedded
        // camera preview when present, but never decode the RAW mosaic merely
        // to populate a scrolling grid.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize:
                max(64, Int(targetLongestEdge.rounded()))
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(
                width: image.width,
                height: image.height
            )
        )
    }

    private static func tryCIRAW(
        url: URL,
        targetLongestEdge: CGFloat?,
        preserveWideGamut: Bool
    ) -> NSImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.isDraftModeEnabled = false
        filter.isGamutMappingEnabled =
            !preserveWideGamut
        if filter.isLensCorrectionSupported {
            filter.isLensCorrectionEnabled = true
        }
        if #available(macOS 16.0, *), filter.isHighlightRecoverySupported {
            filter.isHighlightRecoveryEnabled = true
        }
        if let target = targetLongestEdge {
            let nativeW = filter.nativeSize.width
            let nativeH = filter.nativeSize.height
            let longest = max(nativeW, nativeH)
            if longest > 0 {
                filter.scaleFactor = Float(min(CGFloat(1.0), target / longest))
            }
        }
        guard let outputImage = filter.outputImage else { return nil }
        return rasterize(
            ciImage: outputImage,
            preserveWideGamut: preserveWideGamut
        )
    }

    private static func tryCIImage(
        url: URL,
        targetLongestEdge: CGFloat?,
        preserveWideGamut: Bool
    ) -> NSImage? {
        guard let ci = CIImage(contentsOf: url) else { return nil }
        var scaled = ci
        if let target = targetLongestEdge {
            let extent = ci.extent
            let longest = max(extent.width, extent.height)
            if longest > target, longest > 0 {
                let factor = target / longest
                scaled = ci.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            }
        }
        return rasterize(
            ciImage: scaled,
            preserveWideGamut: preserveWideGamut
        )
    }

    private static func tryImageIOEmbedded(url: URL, targetLongestEdge: CGFloat?) -> NSImage? {
        let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else { return nil }

        let maxPixel = targetLongestEdge.map { Int($0.rounded()) } ?? 4096
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func tryQuickLook(url: URL, target: CGFloat) -> NSImage? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: target, height: target),
            scale: 1.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            if let rep {
                result = rep.nsImage
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }

    private static func rasterize(
        ciImage: CIImage,
        preserveWideGamut: Bool
    ) -> NSImage? {
        let extent = ciImage.extent
        guard !extent.isEmpty, extent.width.isFinite, extent.height.isFinite else { return nil }
        let cg: CGImage?
        if preserveWideGamut {
            cg = wideContext.createCGImage(
                ciImage,
                from: extent,
                format: .RGBAh,
                colorSpace: wideColorSpace
            )
        } else {
            cg = displayContext.createCGImage(
                ciImage,
                from: extent
            )
        }
        guard let cg else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
