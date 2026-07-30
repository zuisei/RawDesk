import AppKit
import CoreGraphics

public struct SoftProofMonitorProfile:
    Equatable,
    Sendable
{
    public let name: String
    public let iccData: Data

    public init?(
        name: String,
        colorSpace: CGColorSpace
    ) {
        guard colorSpace.model == .rgb,
              colorSpace.supportsOutput,
              let data =
                colorSpace.copyICCData() as Data? else {
            return nil
        }
        self.name = name
        iccData = data
    }

    fileprivate var colorSpace: CGColorSpace? {
        CGColorSpace(
            iccData: iccData as CFData
        )
    }
}

public struct SoftProofResult {
    public var displayImage: NSImage
    public var proofImage: NSImage
    public var destinationGamutFraction: Double?
    public var monitorGamutFraction: Double?
    public var monitorName: String?

    public init(
        displayImage: NSImage,
        proofImage: NSImage,
        destinationGamutFraction: Double?,
        monitorGamutFraction: Double? = nil,
        monitorName: String? = nil
    ) {
        self.displayImage = displayImage
        self.proofImage = proofImage
        self.destinationGamutFraction =
            destinationGamutFraction
        self.monitorGamutFraction =
            monitorGamutFraction
        self.monitorName = monitorName
    }
}

public struct SoftProofRenderOutcome {
    public var result: SoftProofResult?
    public var errorMessage: String?

    public init(
        result: SoftProofResult? = nil,
        errorMessage: String? = nil
    ) {
        self.result = result
        self.errorMessage = errorMessage
    }
}

/// Builds a monitor-profile-ready round trip through an output profile.
///
/// The selected destination can be a built-in space or a validated installed
/// ICC profile. Clean proof pixels are tagged with the current display ICC
/// profile. Destination and monitor warning masks are calculated separately in
/// a Rec. 2020 comparison space, then painted red and blue only into the
/// display image. Pixels warned by both masks are magenta. The clean proof
/// remains available for histograms and cursor sampling.
public enum SoftProofProcessor {
    public enum ProcessingError:
        Error,
        LocalizedError
    {
        case imageHasNoBitmap
        case monitorColorSpaceUnavailable
        case renderingFailed

        public var errorDescription: String? {
            switch self {
            case .imageHasNoBitmap:
                return "The proof source has no renderable bitmap."
            case .monitorColorSpaceUnavailable:
                return "The current monitor profile is unavailable."
            case .renderingFailed:
                return "The soft-proof preview could not be rendered."
            }
        }
    }

    private static let sRGB =
        CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
    private static let fallbackMonitorRGB =
        CGColorSpace(name: CGColorSpace.displayP3)
            ?? sRGB
    private static let comparisonRGB =
        CGColorSpace(name: CGColorSpace.itur_2020)
            ?? fallbackMonitorRGB

    public static func apply(
        to image: NSImage,
        settings: SoftProofSettings,
        monitorProfile:
            SoftProofMonitorProfile? = nil
    ) throws -> SoftProofResult {
        let settings = settings.normalized
        guard settings.isEnabled else {
            return SoftProofResult(
                displayImage: image,
                proofImage: image,
                destinationGamutFraction: nil
            )
        }
        guard let source = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw ProcessingError.imageHasNoBitmap
        }
        let destination = try SoftProofProfileCatalog
            .colorSpace(for: settings.profile)
        let monitor = monitorProfile?.colorSpace
            ?? fallbackMonitorRGB
        guard monitor.model == .rgb,
              monitor.supportsOutput else {
            throw ProcessingError
                .monitorColorSpaceUnavailable
        }

        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else {
            throw ProcessingError.renderingFailed
        }

        let destinationImage = try convertedImage(
            source,
            width: width,
            height: height,
            colorSpace: destination,
            intent: settings.renderingIntent.cgIntent
        )
        let roundTripIntent:
            CGColorRenderingIntent =
                settings.simulatePaperAndInk
                ? .absoluteColorimetric
                : .relativeColorimetric
        let monitorImage = try convertedImage(
            destinationImage,
            width: width,
            height: height,
            colorSpace: monitor,
            intent: roundTripIntent
        )
        let proofBytes = try rgbaBytes(
            drawing: monitorImage,
            width: width,
            height: height,
            colorSpace: monitor,
            intent: .relativeColorimetric
        )
        let proofImage = try makeImage(
            fromRGBA: proofBytes,
            width: width,
            height: height,
            colorSpace: monitor
        )

        let needsDestinationWarning =
            settings
                .showDestinationGamutWarning
        let needsMonitorWarning =
            settings.showMonitorGamutWarning
        guard needsDestinationWarning
                || needsMonitorWarning else {
            return SoftProofResult(
                displayImage: proofImage,
                proofImage: proofImage,
                destinationGamutFraction: nil,
                monitorGamutFraction: nil,
                monitorName: monitorProfile?.name
                    ?? "Display P3"
            )
        }

        let intendedProofBytes = try rgbaBytes(
            drawing: destinationImage,
            width: width,
            height: height,
            colorSpace: comparisonRGB,
            intent: roundTripIntent
        )
        let destinationWarning:
            WarningMask?
        if needsDestinationWarning {
            let sourceBytes = try rgbaBytes(
                drawing: source,
                width: width,
                height: height,
                colorSpace: comparisonRGB,
                intent: .relativeColorimetric
            )
            destinationWarning = warningMask(
                source: sourceBytes,
                proof: intendedProofBytes
            )
        } else {
            destinationWarning = nil
        }

        let monitorWarning: WarningMask?
        if needsMonitorWarning {
            let monitorRoundTripBytes =
                try rgbaBytes(
                    drawing: monitorImage,
                    width: width,
                    height: height,
                    colorSpace: comparisonRGB,
                    intent:
                        .relativeColorimetric
                )
            monitorWarning = warningMask(
                source: intendedProofBytes,
                proof: monitorRoundTripBytes,
                maximumDeltaThreshold: 8,
                totalDeltaThreshold: 14
            )
        } else {
            monitorWarning = nil
        }

        let warnedBytes = overlayWarnings(
            on: proofBytes,
            destination:
                destinationWarning?.values,
            monitor: monitorWarning?.values
        )
        let displayImage = try makeImage(
            fromRGBA: warnedBytes,
            width: width,
            height: height,
            colorSpace: monitor
        )
        return SoftProofResult(
            displayImage: displayImage,
            proofImage: proofImage,
            destinationGamutFraction:
                destinationWarning?.fraction,
            monitorGamutFraction:
                monitorWarning?.fraction,
            monitorName: monitorProfile?.name
                ?? "Display P3"
        )
    }

    private static func convertedImage(
        _ source: CGImage,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        intent: CGColorRenderingIntent
    ) throws -> CGImage {
        let isRGB = colorSpace.model == .rgb
        let channels =
            isRGB
                ? 4
                : colorSpace.numberOfComponents
        guard channels > 0 else {
            throw ProcessingError.renderingFailed
        }
        var bytes = [UInt8](
            repeating: 0,
            count: width * height * channels
        )
        let bitmapInfo =
            isRGB
                ? CGImageAlphaInfo
                    .premultipliedLast.rawValue
                : CGImageAlphaInfo.none.rawValue
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * channels,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ProcessingError.renderingFailed
        }
        context.setRenderingIntent(intent)
        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        guard let image = context.makeImage() else {
            throw ProcessingError.renderingFailed
        }
        return image
    }

    private static func rgbaBytes(
        drawing source: CGImage,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        intent: CGColorRenderingIntent
    ) throws -> [UInt8] {
        var bytes = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo:
                CGImageAlphaInfo
                    .premultipliedLast.rawValue
        ) else {
            throw ProcessingError.renderingFailed
        }
        context.setRenderingIntent(intent)
        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        return bytes
    }

    private static func makeImage(
        fromRGBA bytes: [UInt8],
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) throws -> NSImage {
        guard let provider = CGDataProvider(
            data: Data(bytes) as CFData
        ), let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue:
                    CGImageAlphaInfo
                        .premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .relativeColorimetric
        ) else {
            throw ProcessingError.renderingFailed
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: width,
                height: height
            )
        )
    }

    private struct WarningMask {
        var values: [Bool]
        var fraction: Double
    }

    private static func warningMask(
        source: [UInt8],
        proof: [UInt8],
        maximumDeltaThreshold: Int = 18,
        totalDeltaThreshold: Int = 28
    ) -> WarningMask {
        guard source.count == proof.count else {
            return WarningMask(
                values: [],
                fraction: 0
            )
        }
        var values = [Bool](
            repeating: false,
            count: proof.count / 4
        )
        var considered = 0
        var warned = 0

        for offset in stride(
            from: 0,
            to: proof.count,
            by: 4
        ) {
            guard source[offset + 3] > 8 else {
                continue
            }
            considered += 1
            let redDelta = abs(
                Int(source[offset])
                    - Int(proof[offset])
            )
            let greenDelta = abs(
                Int(source[offset + 1])
                    - Int(proof[offset + 1])
            )
            let blueDelta = abs(
                Int(source[offset + 2])
                    - Int(proof[offset + 2])
            )
            let maximum =
                max(redDelta, greenDelta, blueDelta)
            let total =
                redDelta + greenDelta + blueDelta
            guard maximum
                    >= maximumDeltaThreshold,
                  total >= totalDeltaThreshold else {
                continue
            }
            warned += 1
            values[offset / 4] = true
        }
        return WarningMask(
            values: values,
            fraction:
                considered > 0
                ? Double(warned)
                    / Double(considered)
                : 0
        )
    }

    static func overlayWarnings(
        on proof: [UInt8],
        destination:
            [Bool]?,
        monitor: [Bool]?
    ) -> [UInt8] {
        var output = proof
        for pixel in 0..<(proof.count / 4) {
            let destinationWarned =
                destination?[safe: pixel] ?? false
            let monitorWarned =
                monitor?[safe: pixel] ?? false
            guard destinationWarned
                    || monitorWarned else {
                continue
            }
            let offset = pixel * 4
            if destinationWarned
                && monitorWarned {
                output[offset] = 230
                output[offset + 1] = 32
                output[offset + 2] = 220
            } else if destinationWarned {
                output[offset] = UInt8(
                    min(
                        255,
                        190
                            + Int(proof[offset])
                                / 4
                    )
                )
                output[offset + 1] =
                    proof[offset + 1] / 4
                output[offset + 2] =
                    proof[offset + 2] / 4
            } else {
                output[offset] =
                    proof[offset] / 4
                output[offset + 1] =
                    proof[offset + 1] / 4
                output[offset + 2] = UInt8(
                    min(
                        255,
                        190
                            + Int(
                                proof[offset + 2]
                            ) / 4
                    )
                )
            }
            output[offset + 3] = 255
        }
        return output
    }
}

private extension SoftProofRenderingIntent {
    var cgIntent: CGColorRenderingIntent {
        switch self {
        case .perceptual:
            return .perceptual
        case .relativeColorimetric:
            return .relativeColorimetric
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index)
            ? self[index]
            : nil
    }
}
