import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageExporter {

    public enum ExportFormat {
        case jpeg(quality: CGFloat)
        case png

        public var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            }
        }

        public var defaultExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            }
        }
    }

    public enum ExportError: Error, LocalizedError {
        case noCGImage
        case destinationCreationFailed
        case finalizeFailed
        public var errorDescription: String? {
            switch self {
            case .noCGImage: return "Could not derive a bitmap from the image."
            case .destinationCreationFailed: return "Could not create export destination."
            case .finalizeFailed: return "Could not write export file."
            }
        }
    }

    /// Export an NSImage with display-only transforms applied, to a destination URL.
    public static func export(
        image: NSImage,
        transform: ImageTransformState,
        to url: URL,
        format: ExportFormat,
        sourceURL: URL? = nil,
        keywords: [String] = [],
        location: PhotoLocation? = nil,
        replaceLocation: Bool = false,
        suppressLocationMetadata: Bool = false
    ) throws {
        let transformed = applyTransform(image: image, transform: transform)
        guard let cg = transformed.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else {
            throw ExportError.noCGImage
        }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil
        ) else {
            throw ExportError.destinationCreationFailed
        }

        var properties = exportMetadata(
            from: sourceURL,
            width: cg.width,
            height: cg.height,
            keywords: keywords,
            location: location,
            replaceLocation: replaceLocation,
            suppressLocationMetadata:
                suppressLocationMetadata
        )
        if case let .jpeg(quality) = format {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(dest, cg, properties as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            throw ExportError.finalizeFailed
        }
    }

    /// Develops the original source at its maximum available resolution, then
    /// applies display transforms and writes the result off the main thread.
    public static func export(
        asset: PhotoAsset,
        adjustments: PhotoAdjustments,
        transform: ImageTransformState,
        to url: URL,
        format: ExportFormat,
        keywords: [String]? = nil,
        suppressLocation: Bool = false
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let developed = try PhotoProcessor.renderFullResolution(
                asset: asset,
                adjustments: adjustments
            )
            try export(
                image: developed,
                transform: transform,
                to: url,
                format: format,
                sourceURL: asset.url,
                keywords: keywords ?? asset.userState.keywords,
                location:
                    suppressLocation
                    ? nil
                    : asset.effectiveLocation,
                replaceLocation:
                    suppressLocation
                        || asset.userState.locationOverride != nil
                        || asset.userState.locationIsRemoved,
                suppressLocationMetadata: suppressLocation
            )
        }.value
    }

    private static func exportMetadata(
        from sourceURL: URL?,
        width: Int,
        height: Int,
        keywords: [String],
        location: PhotoLocation?,
        replaceLocation: Bool,
        suppressLocationMetadata: Bool
    ) -> [CFString: Any] {
        var result: [CFString: Any] = [
            kCGImagePropertyPixelWidth: width,
            kCGImagePropertyPixelHeight: height,
            kCGImagePropertyOrientation: 1,
            kCGImagePropertyProfileName: "sRGB IEC61966-2.1"
        ]
        if let sourceURL,
           let source = CGImageSourceCreateWithURL(
               sourceURL as CFURL,
               nil
           ),
           let sourceProperties = CGImageSourceCopyPropertiesAtIndex(
               source,
               0,
               nil
           ) as? [CFString: Any] {
            for key in [
                kCGImagePropertyExifDictionary,
                kCGImagePropertyIPTCDictionary,
            ] {
                if let dictionary = sourceProperties[key] {
                    result[key] = dictionary
                }
            }
            if !replaceLocation,
               let gps = sourceProperties[
                   kCGImagePropertyGPSDictionary
               ] {
                result[kCGImagePropertyGPSDictionary] = gps
            }

            if var tiff = sourceProperties[
                kCGImagePropertyTIFFDictionary
            ] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                result[kCGImagePropertyTIFFDictionary] = tiff
            }
            if let dpiWidth =
                sourceProperties[kCGImagePropertyDPIWidth] {
                result[kCGImagePropertyDPIWidth] = dpiWidth
            }
            if let dpiHeight =
                sourceProperties[kCGImagePropertyDPIHeight] {
                result[kCGImagePropertyDPIHeight] = dpiHeight
            }
        }
        let exportedKeywords = PhotoUserState.flatKeywords(
            from: keywords
        )
        if !exportedKeywords.isEmpty {
            var iptc = result[kCGImagePropertyIPTCDictionary]
                as? [CFString: Any] ?? [:]
            iptc[kCGImagePropertyIPTCKeywords] = exportedKeywords
            result[kCGImagePropertyIPTCDictionary] = iptc
        }
        if suppressLocationMetadata,
           var iptc = result[kCGImagePropertyIPTCDictionary]
                as? [CFString: Any] {
            for key in [
                kCGImagePropertyIPTCSubLocation,
                kCGImagePropertyIPTCCity,
                kCGImagePropertyIPTCProvinceState,
                kCGImagePropertyIPTCCountryPrimaryLocationCode,
                kCGImagePropertyIPTCCountryPrimaryLocationName,
            ] {
                iptc.removeValue(forKey: key)
            }
            result[kCGImagePropertyIPTCDictionary] = iptc
        }
        if replaceLocation, let location {
            result[kCGImagePropertyGPSDictionary] =
                gpsDictionary(for: location)
        }
        return result
    }

    private static func gpsDictionary(
        for location: PhotoLocation
    ) -> [CFString: Any] {
        var gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude:
                abs(location.latitude),
            kCGImagePropertyGPSLatitudeRef:
                location.latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude:
                abs(location.longitude),
            kCGImagePropertyGPSLongitudeRef:
                location.longitude < 0 ? "W" : "E",
        ]
        if let altitude = location.altitude {
            gps[kCGImagePropertyGPSAltitude] = abs(altitude)
            gps[kCGImagePropertyGPSAltitudeRef] =
                altitude < 0 ? 1 : 0
        }
        return gps
    }

    private static func applyTransform(image: NSImage, transform: ImageTransformState) -> NSImage {
        if transform.rotationDegrees == 0 && !transform.flipHorizontal && !transform.flipVertical {
            return image
        }
        guard let source = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return image
        }

        let baseWidth = source.width
        let baseHeight = source.height
        let isQuarter = transform.rotationDegrees == 90 || transform.rotationDegrees == 270
        let outputWidth = isQuarter ? baseHeight : baseWidth
        let outputHeight = isQuarter ? baseWidth : baseHeight
        let colorSpace = source.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(outputWidth) / 2, y: CGFloat(outputHeight) / 2)
        context.rotate(by: CGFloat(transform.rotationDegrees) * .pi / 180)
        context.scaleBy(
            x: transform.flipHorizontal ? -1 : 1,
            y: transform.flipVertical ? -1 : 1
        )
        context.translateBy(x: -CGFloat(baseWidth) / 2, y: -CGFloat(baseHeight) / 2)
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: baseWidth, height: baseHeight)
        )

        guard let transformed = context.makeImage() else { return image }
        return NSImage(
            cgImage: transformed,
            size: NSSize(width: transformed.width, height: transformed.height)
        )
    }
}
