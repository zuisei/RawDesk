import Foundation
import AppKit
import CoreImage
import ImageIO

/// Color-managed, non-destructive development pipeline shared by preview and export.
public enum PhotoProcessor {
    public enum ProcessingError: Error, LocalizedError {
        case imageHasNoBitmap
        case sourceCannotBeOpened
        case renderingFailed

        public var errorDescription: String? {
            switch self {
            case .imageHasNoBitmap: return "The image has no renderable bitmap."
            case .sourceCannotBeOpened: return "The original image could not be opened."
            case .renderingFailed: return "The developed image could not be rendered."
            }
        }
    }

    private static let workingColorSpace =
        CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let outputColorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let context = CIContext(options: [
        .workingColorSpace: workingColorSpace,
        .outputColorSpace: outputColorSpace,
        .cacheIntermediates: true
    ])
    private static let softProofContext = CIContext(options: [
        .workingColorSpace: workingColorSpace,
        .outputColorSpace: workingColorSpace,
        .cacheIntermediates: true
    ])
    private static let colorCubeDimension = 32
    private static let colorCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 32
        return cache
    }()
    private static let pointColorCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 32
        return cache
    }()
    private static let maskRangeCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 48
        return cache
    }()
    private static let colorGradingCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 24
        return cache
    }()
    private static let calibrationCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 24
        return cache
    }()
    private static let developmentProfileCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 24
        return cache
    }()
    private static let defringeCubeCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 16
        return cache
    }()
    private static let brushMaskCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()
    private static let rasterMaskCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private static let grainTile: CIImage = {
        let width = 512
        let height = 512
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var state: UInt32 = 0x6D2B_79F5
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            state = state &* 1_664_525 &+ 1_013_904_223
            let value = UInt8(truncatingIfNeeded: state >> 24)
            bytes[offset] = value
            bytes[offset + 1] = value
            bytes[offset + 2] = value
            bytes[offset + 3] = 255
        }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        }
        return CIImage(cgImage: image)
    }()

    /// Applies development settings to an already decoded image.
    public static func apply(
        to image: NSImage,
        adjustments: PhotoAdjustments,
        visualizePointColorID: PointColorAdjustment.ID? = nil,
        visualizeLocalMaskID: LocalAdjustmentMask.ID? = nil
    ) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ProcessingError.imageHasNoBitmap
        }
        let developed = develop(
            CIImage(cgImage: cgImage),
            adjustments: adjustments.normalized,
            visualizePointColorID: visualizePointColorID,
            visualizeLocalMaskID: visualizeLocalMaskID
        )
        return try rasterize(developed)
    }

    /// Develops and soft-proofs without first narrowing the working image to
    /// an 8-bit sRGB preview. The half-float extended-linear handoff preserves
    /// negative and above-one working values until the destination-profile
    /// conversion, which is essential for meaningful gamut simulation.
    public static func applySoftProof(
        to image: NSImage,
        adjustments: PhotoAdjustments,
        settings: SoftProofSettings,
        monitorProfile:
            SoftProofMonitorProfile? = nil,
        visualizePointColorID: PointColorAdjustment.ID? = nil,
        visualizeLocalMaskID: LocalAdjustmentMask.ID? = nil
    ) throws -> SoftProofResult {
        guard settings.normalized.isEnabled else {
            let developed = try apply(
                to: image,
                adjustments: adjustments,
                visualizePointColorID: visualizePointColorID,
                visualizeLocalMaskID: visualizeLocalMaskID
            )
            return SoftProofResult(
                displayImage: developed,
                proofImage: developed,
                destinationGamutFraction: nil
            )
        }
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw ProcessingError.imageHasNoBitmap
        }
        let developed = develop(
            CIImage(cgImage: cgImage),
            adjustments: adjustments.normalized,
            visualizePointColorID: visualizePointColorID,
            visualizeLocalMaskID: visualizeLocalMaskID
        )
        let proofSource = try rasterizeForSoftProof(developed)
        return try SoftProofProcessor.apply(
            to: proofSource,
            settings: settings,
            monitorProfile: monitorProfile
        )
    }

    /// Loads the original at its maximum available resolution and develops it.
    /// RAW files use Core Image's RAW decoder first and the embedded preview only
    /// as a compatibility fallback.
    public static func renderFullResolution(
        asset: PhotoAsset,
        adjustments: PhotoAdjustments
    ) throws -> NSImage {
        let source: NSImage
        if asset.isRaw {
            source = try RAWImageLoader.load(url: asset.url, targetLongestEdge: nil)
        } else {
            source = try loadFullResolutionImage(url: asset.url)
        }
        return try apply(to: source, adjustments: adjustments)
    }

    private static func loadFullResolutionImage(url: URL) throws -> NSImage {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              let cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw ProcessingError.sourceCannotBeOpened
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        let oriented = CIImage(cgImage: cgImage).oriented(forExifOrientation: orientation)
        return try rasterize(oriented)
    }

    private static func develop(
        _ source: CIImage,
        adjustments a: PhotoAdjustments,
        visualizePointColorID: PointColorAdjustment.ID?,
        visualizeLocalMaskID: LocalAdjustmentMask.ID?
    ) -> CIImage {
        let visualizedPoint = visualizePointColorID.flatMap { id in
            a.pointColors.first { $0.id == id }
        }
        let visualizedMask = visualizeLocalMaskID.flatMap { id in
            a.localMasks.first { $0.id == id }
        }
        guard !a.isNeutral || visualizedPoint != nil || visualizedMask != nil else {
            return source
        }
        var image = source

        if a.rotationDegrees != 0 || a.flipHorizontal || a.flipVertical {
            image = applyingOrientation(
                to: image,
                rotationDegrees: a.rotationDegrees,
                flipHorizontal: a.flipHorizontal,
                flipVertical: a.flipVertical
            )
        }
        let originalExtent = image.extent

        // White balance is deliberately relative. Zero preserves the camera/RAW
        // decoder's neutral rendering rather than imposing a hard-coded profile.
        if a.temperature != 0 || a.tint != 0 {
            image = applying(
                "CITemperatureAndTint",
                to: image,
                values: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 + a.temperature * 25,
                        y: a.tint * 1.5
                    )
                ]
            )
        }

        // Profiles establish the color and tonal foundation without changing
        // any of the independently editable controls that follow.
        if a.developmentProfile.isEffective {
            image = applyingDevelopmentProfile(
                a.developmentProfile,
                to: image
            )
        }

        if !a.calibration.isNeutral {
            image = applyingCalibration(a.calibration, to: image)
        }

        if a.exposure != 0 {
            image = applying(
                "CIExposureAdjust",
                to: image,
                values: [kCIInputEVKey: a.exposure]
            )
        }

        if a.highlights < 0 || a.shadows != 0 {
            image = applying(
                "CIHighlightShadowAdjust",
                to: image,
                values: [
                    "inputHighlightAmount": 1 + min(0, a.highlights) / 100,
                    "inputShadowAmount": a.shadows / 100
                ]
            )
        }

        if a.highlights > 0 {
            let lift = a.highlights / 100 * 0.16
            image = applying(
                "CIToneCurve",
                to: image,
                values: [
                    "inputPoint0": CIVector(x: 0, y: 0),
                    "inputPoint1": CIVector(x: 0.25, y: 0.25),
                    "inputPoint2": CIVector(x: 0.5, y: 0.5),
                    "inputPoint3": CIVector(x: 0.75, y: min(0.96, 0.75 + lift)),
                    "inputPoint4": CIVector(x: 1, y: 1)
                ]
            )
        }

        if a.whites != 0 || a.blacks != 0 {
            let whiteGain = 1 + a.whites / 100 * 0.18
            let blackBias = a.blacks / 100 * 0.08
            let gain = max(0.72, whiteGain - abs(blackBias) * 0.35)
            image = applying(
                "CIColorMatrix",
                to: image,
                values: [
                    "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: blackBias, y: blackBias, z: blackBias, w: 0)
                ]
            )
        }

        if !a.toneCurve.isNeutral {
            let curve = a.toneCurve
            image = applying(
                "CIToneCurve",
                to: image,
                values: [
                    "inputPoint0": CIVector(x: 0, y: curve.black),
                    "inputPoint1": CIVector(x: 0.25, y: curve.shadows),
                    "inputPoint2": CIVector(x: 0.5, y: curve.midtones),
                    "inputPoint3": CIVector(x: 0.75, y: curve.highlights),
                    "inputPoint4": CIVector(x: 1, y: curve.white)
                ]
            )
        }

        if a.contrast != 0 || a.saturation != 0 {
            image = applying(
                "CIColorControls",
                to: image,
                values: [
                    kCIInputContrastKey: 1 + a.contrast / 100 * 0.5,
                    kCIInputSaturationKey: 1 + a.saturation / 100
                ]
            )
        }

        if a.vibrance != 0 {
            image = applying(
                "CIVibrance",
                to: image,
                values: ["inputAmount": a.vibrance / 100]
            )
        }

        if !a.colorMixer.isNeutral {
            image = applyingColorMixer(a.colorMixer, to: image)
        }

        let effectivePointColors = a.pointColors.filter(\.isEffective)
        // Range visualization shows the sampled input range itself. Point
        // shifts are intentionally bypassed while it is active so a large hue
        // shift cannot move selected pixels out of their own visualization.
        if visualizedPoint == nil, !effectivePointColors.isEmpty {
            image = applyingPointColors(effectivePointColors, to: image)
        }

        if !a.colorGrading.isNeutral {
            image = applyingColorGrading(a.colorGrading, to: image)
        }

        var localMaskOverlay: CIImage?
        for mask in a.localMasks {
            if mask.id == visualizedMask?.id {
                localMaskOverlay = combinedLocalMaskImage(
                    mask,
                    source: image,
                    extent: originalExtent
                )
            }
            guard mask.isEffective else { continue }
            image = applyingLocalMask(mask, to: image, extent: originalExtent)
        }
        if let localMaskOverlay {
            image = applyingLocalMaskOverlay(
                localMaskOverlay,
                to: image,
                extent: originalExtent
            )
        }

        for spot in a.spotRemovals {
            image = applyingSpotRemoval(spot, to: image, extent: originalExtent)
        }

        if a.effectsEnabled {
            if a.texture > 0 {
                image = applying(
                    "CIUnsharpMask",
                    to: image,
                    values: [
                        kCIInputRadiusKey: 0.7 + a.texture / 100 * 1.4,
                        kCIInputIntensityKey: a.texture / 100 * 0.72
                    ]
                ).cropped(to: originalExtent)
            } else if a.texture < 0 {
                let smoothed = applying(
                    "CINoiseReduction",
                    to: image,
                    values: [
                        "inputNoiseLevel": abs(a.texture) / 100 * 0.075,
                        "inputSharpness": 0.35
                    ]
                ).cropped(to: originalExtent)
                image = applying(
                    "CIDissolveTransition",
                    to: image,
                    values: [
                        "inputTargetImage": smoothed,
                        "inputTime": abs(a.texture) / 100 * 0.8
                    ]
                ).cropped(to: originalExtent)
            }

            if a.clarity > 0 {
                image = applying(
                    "CIUnsharpMask",
                    to: image,
                    values: [
                        kCIInputRadiusKey: 2.5 + a.clarity / 100 * 2.5,
                        kCIInputIntensityKey: a.clarity / 100 * 0.8
                    ]
                ).cropped(to: originalExtent)
            } else if a.clarity < 0 {
                image = applying(
                    "CINoiseReduction",
                    to: image,
                    values: [
                        "inputNoiseLevel": abs(a.clarity) / 100 * 0.035,
                        "inputSharpness": 0.15
                    ]
                ).cropped(to: originalExtent)
            }

            if a.dehaze != 0 {
                let amount = a.dehaze / 100
                image = applying(
                    "CIColorControls",
                    to: image,
                    values: [
                        kCIInputContrastKey: 1 + amount * 0.28,
                        kCIInputSaturationKey: 1 + amount * 0.16,
                        kCIInputBrightnessKey: -amount * 0.025
                    ]
                )
            }
        }

        if a.noiseReduction > 0 {
            let detailedSource = image
            var denoised = applying(
                "CINoiseReduction",
                to: image,
                values: [
                    "inputNoiseLevel": a.noiseReduction / 100 * 0.095,
                    "inputSharpness": 0.2 + a.noiseReductionDetail / 100 * 0.45
                ]
            ).cropped(to: originalExtent)

            let retainedDetail = a.noiseReductionDetail / 100 * 0.45
            if retainedDetail > 0 {
                denoised = applying(
                    "CIDissolveTransition",
                    to: denoised,
                    values: [
                        "inputTargetImage": detailedSource,
                        "inputTime": retainedDetail
                    ]
                ).cropped(to: originalExtent)
            }
            if a.noiseReductionContrast > 0 {
                denoised = applying(
                    "CIUnsharpMask",
                    to: denoised,
                    values: [
                        kCIInputRadiusKey: 1.5 + a.noiseReductionContrast / 35,
                        kCIInputIntensityKey: a.noiseReductionContrast / 100 * 0.35
                    ]
                ).cropped(to: originalExtent)
            }
            image = denoised
        }

        if a.colorNoiseReduction > 0 {
            let luminanceSource = image
            let radius = 0.6
                + a.colorNoiseReduction / 100 * 2.8
                + a.colorNoiseSmoothness / 100 * 1.2
                - a.colorNoiseDetail / 100 * 1.4
            let smoothedColor = applying(
                "CIGaussianBlur",
                to: image,
                values: [kCIInputRadiusKey: max(0.25, radius)]
            ).cropped(to: originalExtent)
            let chromaDenoised = applying(
                "CIColorBlendMode",
                to: smoothedColor,
                values: [kCIInputBackgroundImageKey: luminanceSource]
            ).cropped(to: originalExtent)
            image = applying(
                "CIDissolveTransition",
                to: luminanceSource,
                values: [
                    "inputTargetImage": chromaDenoised,
                    "inputTime": a.colorNoiseReduction / 100
                ]
            ).cropped(to: originalExtent)
        }

        if a.sharpening > 0 {
            let unsharpened = image
            let detailGain = 0.65 + a.sharpeningDetail / 100 * 0.85
            let sharpened = applying(
                "CISharpenLuminance",
                to: image,
                values: [
                    kCIInputSharpnessKey: a.sharpening / 100 * 1.45 * detailGain,
                    kCIInputRadiusKey: a.sharpeningRadius
                ]
            ).cropped(to: originalExtent)

            if a.sharpeningMasking > 0 {
                var edgeMask = applying(
                    "CIEdges",
                    to: unsharpened,
                    values: [
                        kCIInputIntensityKey: 1 + a.sharpeningMasking / 100 * 7
                    ]
                ).cropped(to: originalExtent)
                edgeMask = applying(
                    "CIColorControls",
                    to: edgeMask,
                    values: [
                        kCIInputContrastKey: 1 + a.sharpeningMasking / 100 * 4,
                        kCIInputBrightnessKey: -a.sharpeningMasking / 100 * 0.16
                    ]
                ).cropped(to: originalExtent)
                image = applying(
                    "CIBlendWithMask",
                    to: sharpened,
                    values: [
                        kCIInputBackgroundImageKey: unsharpened,
                        kCIInputMaskImageKey: edgeMask
                    ]
                ).cropped(to: originalExtent)
            } else {
                image = sharpened
            }
        }

        if !a.optics.isNeutral {
            image = applyingOptics(
                a.optics.renderingCorrection,
                to: image,
                extent: originalExtent
            )
        }

        if a.straighten != 0 || !a.geometry.isNeutral {
            image = applyingGeometry(
                a.geometry,
                straighten: a.straighten,
                to: image,
                extent: originalExtent
            )
        }

        if !a.crop.isFullFrame {
            let crop = a.crop.normalized
            let cropRect = CGRect(
                x: originalExtent.minX + crop.x * originalExtent.width,
                y: originalExtent.minY + (1 - crop.y - crop.height) * originalExtent.height,
                width: crop.width * originalExtent.width,
                height: crop.height * originalExtent.height
            ).integral.intersection(originalExtent)
            if !cropRect.isEmpty {
                image = image
                    .cropped(to: cropRect)
                    .transformed(by: CGAffineTransform(
                        translationX: -cropRect.minX,
                        y: -cropRect.minY
                    ))
            }
        }

        let developedExtent = image.extent
        if a.effectsEnabled, a.vignette != 0 {
            image = applying(
                "CIVignette",
                to: image,
                values: [
                    kCIInputIntensityKey: -a.vignette / 100 * 1.6,
                    kCIInputRadiusKey: min(developedExtent.width, developedExtent.height) * 0.48
                ]
            ).cropped(to: developedExtent)
        }

        if a.effectsEnabled, a.grainAmount > 0 {
            image = applyingGrain(
                amount: a.grainAmount,
                size: a.grainSize,
                roughness: a.grainRoughness,
                to: image,
                extent: developedExtent
            )
        }

        if let visualizedPoint {
            image = applyingPointColorVisualization(visualizedPoint, to: image)
        }

        return image.cropped(to: developedExtent)
    }

    private static func applyingGrain(
        amount: Double,
        size: Double,
        roughness: Double,
        to source: CIImage,
        extent: CGRect
    ) -> CIImage {
        let grainScale = CGFloat(0.38 + size / 100 * 2.15)
        var noise = grainTile.transformed(
            by: CGAffineTransform(scaleX: grainScale, y: grainScale)
        )
        noise = applying(
            "CIAffineTile",
            to: noise,
            values: [:]
        ).cropped(to: extent)
        noise = applying(
            "CIColorControls",
            to: noise,
            values: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 0.65 + roughness / 100 * 1.6,
                kCIInputBrightnessKey: 0
            ]
        ).cropped(to: extent)
        let textured = applying(
            "CIOverlayBlendMode",
            to: noise,
            values: [kCIInputBackgroundImageKey: source]
        ).cropped(to: extent)
        return applying(
            "CIDissolveTransition",
            to: source,
            values: [
                "inputTargetImage": textured,
                "inputTime": amount / 100 * 0.62
            ]
        ).cropped(to: extent)
    }

    private static func applyingOptics(
        _ optics: OpticsAdjustments,
        to source: CIImage,
        extent: CGRect
    ) -> CIImage {
        var image = source

        if optics.distortion != 0 {
            image = applying(
                "CIBumpDistortion",
                to: image,
                values: [
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                    kCIInputRadiusKey: hypot(extent.width, extent.height) * 0.56,
                    kCIInputScaleKey: optics.distortion / 100 * 0.42
                ]
            ).cropped(to: extent)
        }

        if optics.redCyanShift != 0 || optics.blueYellowShift != 0 {
            let center = CIVector(x: extent.midX, y: extent.midY)
            let radius = hypot(extent.width, extent.height) * 0.56
            let red = optics.redCyanShift == 0
                ? image
                : applying(
                    "CIBumpDistortion",
                    to: image,
                    values: [
                        kCIInputCenterKey: center,
                        kCIInputRadiusKey: radius,
                        kCIInputScaleKey: optics.redCyanShift / 100 * 0.024
                    ]
                ).cropped(to: extent)
            let blue = optics.blueYellowShift == 0
                ? image
                : applying(
                    "CIBumpDistortion",
                    to: image,
                    values: [
                        kCIInputCenterKey: center,
                        kCIInputRadiusKey: radius,
                        kCIInputScaleKey: optics.blueYellowShift / 100 * 0.024
                    ]
                ).cropped(to: extent)
            let redOnly = isolatingColorChannel(.red, in: red)
            let greenOnly = isolatingColorChannel(.green, in: image)
            let blueOnly = isolatingColorChannel(.blue, in: blue)
            let redGreen = applying(
                "CIMaximumCompositing",
                to: redOnly,
                values: [kCIInputBackgroundImageKey: greenOnly]
            )
            image = applying(
                "CIMaximumCompositing",
                to: redGreen,
                values: [kCIInputBackgroundImageKey: blueOnly]
            ).cropped(to: extent)
        }

        if optics.purpleDefringe > 0 || optics.greenDefringe > 0 {
            let defringed = applying(
                "CIColorCubeWithColorSpace",
                to: image,
                values: [
                    "inputCubeDimension": colorCubeDimension,
                    "inputCubeData": defringeCubeData(for: optics),
                    "inputColorSpace": outputColorSpace
                ]
            ).cropped(to: extent)
            var edgeMask = applying(
                "CIEdges",
                to: image,
                values: [kCIInputIntensityKey: 3.5]
            ).cropped(to: extent)
            edgeMask = applying(
                "CIColorControls",
                to: edgeMask,
                values: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 2.8,
                    kCIInputBrightnessKey: -0.08
                ]
            ).cropped(to: extent)
            image = applying(
                "CIBlendWithMask",
                to: defringed,
                values: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: edgeMask
                ]
            ).cropped(to: extent)
        }

        if optics.vignette != 0 {
            let adjusted = applying(
                "CIExposureAdjust",
                to: image,
                values: [kCIInputEVKey: optics.vignette / 100 * 1.35]
            ).cropped(to: extent)
            let edgeMask = applyingGenerator(
                "CIRadialGradient",
                values: [
                    "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                    "inputRadius0": min(extent.width, extent.height) * 0.18,
                    "inputRadius1": hypot(extent.width, extent.height) * 0.5,
                    "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                    "inputColor1": CIColor(red: 1, green: 1, blue: 1)
                ]
            ).cropped(to: extent)
            image = applying(
                "CIBlendWithMask",
                to: adjusted,
                values: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: edgeMask
                ]
            ).cropped(to: extent)
        }

        return image.cropped(to: extent)
    }

    private enum ColorChannel {
        case red
        case green
        case blue
    }

    private static func isolatingColorChannel(
        _ channel: ColorChannel,
        in image: CIImage
    ) -> CIImage {
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let red: CIVector
        let green: CIVector
        let blue: CIVector
        switch channel {
        case .red:
            red = CIVector(x: 1, y: 0, z: 0, w: 0)
            green = zero
            blue = zero
        case .green:
            red = zero
            green = CIVector(x: 0, y: 1, z: 0, w: 0)
            blue = zero
        case .blue:
            red = zero
            green = zero
            blue = CIVector(x: 0, y: 0, z: 1, w: 0)
        }
        return applying(
            "CIColorMatrix",
            to: image,
            values: [
                "inputRVector": red,
                "inputGVector": green,
                "inputBVector": blue,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": zero
            ]
        )
    }

    private static func applyingGeometry(
        _ geometry: GeometryAdjustments,
        straighten: Double,
        to source: CIImage,
        extent: CGRect
    ) -> CIImage {
        var image = source

        if geometry.vertical != 0 || geometry.horizontal != 0 {
            let verticalDelta = extent.width * geometry.vertical / 100 * 0.18
            let horizontalDelta = extent.height * geometry.horizontal / 100 * 0.18
            image = applying(
                "CIPerspectiveTransform",
                to: image,
                values: [
                    "inputTopLeft": CIVector(
                        x: extent.minX - verticalDelta,
                        y: extent.maxY + horizontalDelta
                    ),
                    "inputTopRight": CIVector(
                        x: extent.maxX + verticalDelta,
                        y: extent.maxY - horizontalDelta
                    ),
                    "inputBottomRight": CIVector(
                        x: extent.maxX - verticalDelta,
                        y: extent.minY + horizontalDelta
                    ),
                    "inputBottomLeft": CIVector(
                        x: extent.minX + verticalDelta,
                        y: extent.minY - horizontalDelta
                    )
                ]
            ).cropped(to: extent)
        }

        if straighten != 0
            || geometry.aspect != 0
            || geometry.scale != 100
            || geometry.offsetX != 0
            || geometry.offsetY != 0
            || (geometry.constrainCrop
                && (geometry.vertical != 0 || geometry.horizontal != 0)) {
            let radians = CGFloat(straighten) * .pi / 180
            let straightenScale = 1 + abs(sin(radians)) * 1.15
            let userScale = CGFloat(geometry.scale / 100)
            let aspectScale = CGFloat(1 + geometry.aspect / 100 * 0.3)
            let constrainedXScale = geometry.constrainCrop
                ? CGFloat(1 / max(0.55, 1 - abs(geometry.vertical) / 100 * 0.36))
                : 1
            let constrainedYScale = geometry.constrainCrop
                ? CGFloat(1 / max(0.55, 1 - abs(geometry.horizontal) / 100 * 0.36))
                : 1
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let offset = CGPoint(
                x: extent.width * geometry.offsetX / 100 * 0.45,
                y: extent.height * geometry.offsetY / 100 * 0.45
            )
            let transform = CGAffineTransform.identity
                .translatedBy(x: center.x + offset.x, y: center.y + offset.y)
                .rotated(by: radians)
                .scaledBy(
                    x: userScale * aspectScale * straightenScale * constrainedXScale,
                    y: userScale * straightenScale * constrainedYScale
                )
                .translatedBy(x: -center.x, y: -center.y)
            image = image.transformed(by: transform).cropped(to: extent)
        }

        return image.cropped(to: extent)
    }

    private static func applyingCalibration(
        _ calibration: CalibrationAdjustments,
        to image: CIImage
    ) -> CIImage {
        applying(
            "CIColorCubeWithColorSpace",
            to: image,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": calibrationCubeData(for: calibration),
                "inputColorSpace": outputColorSpace
            ]
        )
    }

    private static func applyingColorMixer(
        _ mixer: ColorMixer,
        to image: CIImage
    ) -> CIImage {
        applying(
            "CIColorCubeWithColorSpace",
            to: image,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": colorCubeData(for: mixer),
                "inputColorSpace": outputColorSpace
            ]
        )
    }

    private static func applyingColorGrading(
        _ grading: ColorGrading,
        to image: CIImage
    ) -> CIImage {
        applying(
            "CIColorCubeWithColorSpace",
            to: image,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": colorGradingCubeData(for: grading),
                "inputColorSpace": outputColorSpace
            ]
        )
    }

    private static func applyingPointColors(
        _ points: [PointColorAdjustment],
        to image: CIImage
    ) -> CIImage {
        applying(
            "CIColorCubeWithColorSpace",
            to: image,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": pointColorCubeData(for: points),
                "inputColorSpace": outputColorSpace
            ]
        )
    }

    private static func applyingPointColorVisualization(
        _ point: PointColorAdjustment,
        to image: CIImage
    ) -> CIImage {
        applying(
            "CIColorCubeWithColorSpace",
            to: image,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": pointColorVisualizationCubeData(for: point),
                "inputColorSpace": outputColorSpace
            ]
        )
    }

    private static func applyingLocalMask(
        _ mask: LocalAdjustmentMask,
        to image: CIImage,
        extent: CGRect
    ) -> CIImage {
        var adjusted = applyingLocalTone(mask.adjustments, to: image, extent: extent)
        let effectivePointColors = mask.pointColors.filter(\.isEffective)
        if !effectivePointColors.isEmpty {
            adjusted = applyingPointColors(effectivePointColors, to: adjusted)
                .cropped(to: extent)
        }
        let maskImage = combinedLocalMaskImage(mask, source: image, extent: extent)
        return applying(
            "CIBlendWithMask",
            to: adjusted,
            values: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: maskImage
            ]
        ).cropped(to: extent)
    }

    private static func applyingLocalMaskOverlay(
        _ maskImage: CIImage,
        to image: CIImage,
        extent: CGRect
    ) -> CIImage {
        let tint = CIImage(
            color: CIColor(red: 1, green: 0.08, blue: 0.12, alpha: 0.52)
        ).cropped(to: extent)
        let tinted = tint.composited(over: image).cropped(to: extent)
        return applying(
            "CIBlendWithMask",
            to: tinted,
            values: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: maskImage
            ]
        ).cropped(to: extent)
    }

    private static func applyingLocalTone(
        _ adjustment: LocalToneAdjustments,
        to source: CIImage,
        extent: CGRect
    ) -> CIImage {
        var image = source

        if adjustment.temperature != 0 || adjustment.tint != 0 {
            image = applying(
                "CITemperatureAndTint",
                to: image,
                values: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 + adjustment.temperature * 25,
                        y: adjustment.tint * 1.5
                    )
                ]
            )
        }
        if adjustment.exposure != 0 {
            image = applying(
                "CIExposureAdjust",
                to: image,
                values: [kCIInputEVKey: adjustment.exposure]
            )
        }
        if adjustment.highlights < 0 || adjustment.shadows != 0 {
            image = applying(
                "CIHighlightShadowAdjust",
                to: image,
                values: [
                    "inputHighlightAmount": 1 + min(0, adjustment.highlights) / 100,
                    "inputShadowAmount": adjustment.shadows / 100
                ]
            )
        }
        if adjustment.highlights > 0 {
            let lift = adjustment.highlights / 100 * 0.16
            image = applying(
                "CIToneCurve",
                to: image,
                values: [
                    "inputPoint0": CIVector(x: 0, y: 0),
                    "inputPoint1": CIVector(x: 0.25, y: 0.25),
                    "inputPoint2": CIVector(x: 0.5, y: 0.5),
                    "inputPoint3": CIVector(
                        x: 0.75,
                        y: min(0.96, 0.75 + lift)
                    ),
                    "inputPoint4": CIVector(x: 1, y: 1)
                ]
            )
        }
        if adjustment.whites != 0 || adjustment.blacks != 0 {
            let whiteGain = 1 + adjustment.whites / 100 * 0.18
            let blackBias = adjustment.blacks / 100 * 0.08
            let gain = max(0.72, whiteGain - abs(blackBias) * 0.35)
            image = applying(
                "CIColorMatrix",
                to: image,
                values: [
                    "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(
                        x: blackBias,
                        y: blackBias,
                        z: blackBias,
                        w: 0
                    )
                ]
            )
        }
        if adjustment.contrast != 0 || adjustment.saturation != 0 {
            image = applying(
                "CIColorControls",
                to: image,
                values: [
                    kCIInputContrastKey: 1 + adjustment.contrast / 100 * 0.5,
                    kCIInputSaturationKey: 1 + adjustment.saturation / 100
                ]
            )
        }
        if adjustment.hue != 0 {
            image = applying(
                "CIHueAdjust",
                to: image,
                values: [
                    kCIInputAngleKey: adjustment.hue * .pi / 180
                ]
            )
        }
        if adjustment.texture > 0 {
            image = applying(
                "CIUnsharpMask",
                to: image,
                values: [
                    kCIInputRadiusKey: 0.7 + adjustment.texture / 100 * 1.4,
                    kCIInputIntensityKey: adjustment.texture / 100 * 0.72
                ]
            ).cropped(to: extent)
        } else if adjustment.texture < 0 {
            let smoothed = applying(
                "CINoiseReduction",
                to: image,
                values: [
                    "inputNoiseLevel": abs(adjustment.texture) / 100 * 0.075,
                    "inputSharpness": 0.35
                ]
            ).cropped(to: extent)
            image = applying(
                "CIDissolveTransition",
                to: image,
                values: [
                    "inputTargetImage": smoothed,
                    "inputTime": abs(adjustment.texture) / 100 * 0.8
                ]
            ).cropped(to: extent)
        }
        if adjustment.clarity > 0 {
            image = applying(
                "CIUnsharpMask",
                to: image,
                values: [
                    kCIInputRadiusKey: 2.5 + adjustment.clarity / 100 * 2.5,
                    kCIInputIntensityKey: adjustment.clarity / 100 * 0.8
                ]
            ).cropped(to: extent)
        } else if adjustment.clarity < 0 {
            image = applying(
                "CINoiseReduction",
                to: image,
                values: [
                    "inputNoiseLevel": abs(adjustment.clarity) / 100 * 0.035,
                    "inputSharpness": 0.15
                ]
            ).cropped(to: extent)
        }
        if adjustment.dehaze != 0 {
            let amount = adjustment.dehaze / 100
            image = applying(
                "CIColorControls",
                to: image,
                values: [
                    kCIInputContrastKey: 1 + amount * 0.28,
                    kCIInputSaturationKey: 1 + amount * 0.16,
                    kCIInputBrightnessKey: -amount * 0.025
                ]
            )
        }
        if adjustment.noiseReduction > 0 {
            image = applying(
                "CINoiseReduction",
                to: image,
                values: [
                    "inputNoiseLevel": adjustment.noiseReduction / 100 * 0.095,
                    "inputSharpness": 0.35
                ]
            ).cropped(to: extent)
        }
        if adjustment.sharpness > 0 {
            image = applying(
                "CISharpenLuminance",
                to: image,
                values: [
                    kCIInputSharpnessKey: adjustment.sharpness / 100 * 1.45,
                    kCIInputRadiusKey: 1
                ]
            ).cropped(to: extent)
        } else if adjustment.sharpness < 0 {
            let blurred = applying(
                "CIGaussianBlur",
                to: image,
                values: [
                    kCIInputRadiusKey: abs(adjustment.sharpness) / 100 * 3
                ]
            ).cropped(to: extent)
            image = applying(
                "CIDissolveTransition",
                to: image,
                values: [
                    "inputTargetImage": blurred,
                    "inputTime": abs(adjustment.sharpness) / 100 * 0.8
                ]
            ).cropped(to: extent)
        }
        return image.cropped(to: extent)
    }

    private static func combinedLocalMaskImage(
        _ mask: LocalAdjustmentMask,
        source: CIImage,
        extent: CGRect
    ) -> CIImage {
        var output = primaryLocalMaskImage(mask, extent: extent)
        if mask.inverted {
            output = applying("CIColorInvert", to: output, values: [:])
                .cropped(to: extent)
        }

        for operation in mask.primaryOperations where operation.isEnabled {
            var operationMask = primaryLocalMaskImage(operation, extent: extent)
            if operation.inverted {
                operationMask = applying(
                    "CIColorInvert",
                    to: operationMask,
                    values: [:]
                ).cropped(to: extent)
            }

            switch operation.combination {
            case .add:
                output = applying(
                    "CIMaximumCompositing",
                    to: operationMask,
                    values: [kCIInputBackgroundImageKey: output]
                ).cropped(to: extent)
            case .subtract:
                let inverseOperation = applying(
                    "CIColorInvert",
                    to: operationMask,
                    values: [:]
                ).cropped(to: extent)
                output = applying(
                    "CIMultiplyCompositing",
                    to: output,
                    values: [kCIInputBackgroundImageKey: inverseOperation]
                ).cropped(to: extent)
            case .intersect:
                output = applying(
                    "CIMultiplyCompositing",
                    to: output,
                    values: [kCIInputBackgroundImageKey: operationMask]
                ).cropped(to: extent)
            }
        }

        for operation in mask.rangeOperations where operation.isEnabled {
            var rangeMask = rangeMaskImage(
                operation,
                source: source,
                extent: extent
            )
            if operation.inverted {
                rangeMask = applying("CIColorInvert", to: rangeMask, values: [:])
                    .cropped(to: extent)
            }

            switch operation.combination {
            case .add:
                output = applying(
                    "CIMaximumCompositing",
                    to: rangeMask,
                    values: [kCIInputBackgroundImageKey: output]
                ).cropped(to: extent)
            case .subtract:
                let inverseRange = applying(
                    "CIColorInvert",
                    to: rangeMask,
                    values: [:]
                ).cropped(to: extent)
                output = applying(
                    "CIMultiplyCompositing",
                    to: output,
                    values: [kCIInputBackgroundImageKey: inverseRange]
                ).cropped(to: extent)
            case .intersect:
                output = applying(
                    "CIMultiplyCompositing",
                    to: output,
                    values: [kCIInputBackgroundImageKey: rangeMask]
                ).cropped(to: extent)
            }
        }
        return output.cropped(to: extent)
    }

    private static func primaryLocalMaskImage(
        _ operation: MaskPrimaryOperation,
        extent: CGRect
    ) -> CIImage {
        let center = CIVector(
            x: extent.minX + operation.centerX * extent.width,
            y: extent.minY + (1 - operation.centerY) * extent.height
        )
        let black = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let output: CIImage

        switch operation.kind {
        case .subject, .object, .sky:
            output = rasterMaskImage(operation, extent: extent)
        case .radial:
            let outerRadius = min(extent.width, extent.height) * operation.size * 0.5
            let transition = max(0.01, operation.feather)
            let innerRadius = outerRadius * (1 - transition)
            output = applyingGenerator(
                "CIRadialGradient",
                values: [
                    "inputCenter": center,
                    "inputRadius0": innerRadius,
                    "inputRadius1": outerRadius,
                    "inputColor0": white,
                    "inputColor1": black
                ]
            )
        case .linear:
            let radians = operation.angle * .pi / 180
            let length = min(extent.width, extent.height)
                * operation.size
                * max(0.05, operation.feather)
            let dx = cos(radians) * length / 2
            let dy = sin(radians) * length / 2
            output = applyingGenerator(
                "CILinearGradient",
                values: [
                    "inputPoint0": CIVector(x: center.x - dx, y: center.y - dy),
                    "inputPoint1": CIVector(x: center.x + dx, y: center.y + dy),
                    "inputColor0": black,
                    "inputColor1": white
                ]
            )
        case .brush:
            output = brushMaskImage(operation, extent: extent)
        }
        return output.cropped(to: extent)
    }

    private static func primaryLocalMaskImage(
        _ mask: LocalAdjustmentMask,
        extent: CGRect
    ) -> CIImage {
        let center = CIVector(
            x: extent.minX + mask.centerX * extent.width,
            y: extent.minY + (1 - mask.centerY) * extent.height
        )
        let black = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        let white = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let output: CIImage

        switch mask.kind {
        case .subject, .object, .sky:
            output = rasterMaskImage(mask, extent: extent)
        case .radial:
            let outerRadius = min(extent.width, extent.height) * mask.size * 0.5
            let transition = max(0.01, mask.feather)
            let innerRadius = outerRadius * (1 - transition)
            output = applyingGenerator(
                "CIRadialGradient",
                values: [
                    "inputCenter": center,
                    "inputRadius0": innerRadius,
                    "inputRadius1": outerRadius,
                    "inputColor0": white,
                    "inputColor1": black
                ]
            )
        case .linear:
            let radians = mask.angle * .pi / 180
            let length = min(extent.width, extent.height)
                * mask.size
                * max(0.05, mask.feather)
            let dx = cos(radians) * length / 2
            let dy = sin(radians) * length / 2
            output = applyingGenerator(
                "CILinearGradient",
                values: [
                    "inputPoint0": CIVector(x: center.x - dx, y: center.y - dy),
                    "inputPoint1": CIVector(x: center.x + dx, y: center.y + dy),
                    "inputColor0": black,
                    "inputColor1": white
                ]
            )
        case .brush:
            output = brushMaskImage(mask, extent: extent)
        }
        return output.cropped(to: extent)
    }

    private static func rangeMaskImage(
        _ operation: MaskRangeOperation,
        source: CIImage,
        extent: CGRect
    ) -> CIImage {
        let rangeSource: CIImage
        switch operation.kind {
        case .color, .luminance:
            rangeSource = source
        case .depth:
            rangeSource = rasterMaskImage(
                data: operation.rasterMaskData,
                cacheKey: operation.id.uuidString,
                extent: extent
            )
        }
        return applying(
            "CIColorCubeWithColorSpace",
            to: rangeSource,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": maskRangeCubeData(for: operation),
                "inputColorSpace": outputColorSpace
            ]
        ).cropped(to: extent)
    }

    private static func rasterMaskImage(
        _ mask: LocalAdjustmentMask,
        extent: CGRect
    ) -> CIImage {
        rasterMaskImage(
            data: mask.rasterMaskData,
            cacheKey: mask.id.uuidString,
            extent: extent
        )
    }

    private static func rasterMaskImage(
        _ operation: MaskPrimaryOperation,
        extent: CGRect
    ) -> CIImage {
        rasterMaskImage(
            data: operation.rasterMaskData,
            cacheKey: operation.id.uuidString,
            extent: extent
        )
    }

    private static func rasterMaskImage(
        data: Data?,
        cacheKey: String,
        extent: CGRect
    ) -> CIImage {
        guard let data, !data.isEmpty else {
            return CIImage(color: .black).cropped(to: extent)
        }

        let key = "\(cacheKey)|\(data.hashValue)" as NSString
        let cgImage: CGImage
        if let cached = rasterMaskCache.object(forKey: key) {
            cgImage = cached
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return CIImage(color: .black).cropped(to: extent)
            }
            rasterMaskCache.setObject(
                decoded,
                forKey: key,
                cost: decoded.bytesPerRow * decoded.height
            )
            cgImage = decoded
        }

        let source = CIImage(cgImage: cgImage)
        guard source.extent.width > 0, source.extent.height > 0 else {
            return CIImage(color: .black).cropped(to: extent)
        }
        let normalized = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.minX,
                y: -source.extent.minY
            )
        )
        let scaled = normalized.transformed(
            by: CGAffineTransform(
                scaleX: extent.width / normalized.extent.width,
                y: extent.height / normalized.extent.height
            )
        )
        return scaled.transformed(
            by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
        )
    }

    private static func brushMaskImage(
        _ mask: LocalAdjustmentMask,
        extent: CGRect
    ) -> CIImage {
        brushMaskImage(
            cacheKey: mask.hashValue,
            size: mask.size,
            feather: mask.feather,
            flow: mask.flow,
            strokes: mask.strokes,
            extent: extent
        )
    }

    private static func brushMaskImage(
        _ operation: MaskPrimaryOperation,
        extent: CGRect
    ) -> CIImage {
        brushMaskImage(
            cacheKey: operation.hashValue,
            size: operation.size,
            feather: operation.feather,
            flow: operation.flow,
            strokes: operation.strokes,
            extent: extent
        )
    }

    private static func brushMaskImage(
        cacheKey: Int,
        size: Double,
        feather: Double,
        flow: Double,
        strokes: [BrushStroke],
        extent: CGRect
    ) -> CIImage {
        let width = max(1, Int(extent.width.rounded(.up)))
        let height = max(1, Int(extent.height.rounded(.up)))
        let key = "\(cacheKey)|\(width)x\(height)" as NSString
        if let cached = brushMaskCache.object(forKey: key) {
            return CIImage(cgImage: cached).transformed(
                by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
            )
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return CIImage(color: .black).cropped(to: extent)
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.lighten)

        let radius = max(1, min(CGFloat(width), CGFloat(height)) * size)
        let innerRadius = radius * (1 - feather)
        let featherSteps = max(4, Int((feather * 14).rounded(.up)))

        for step in 0...featherSteps {
            let t = CGFloat(step) / CGFloat(featherSteps)
            let eased = t * t * (3 - 2 * t)
            let currentRadius = radius - (radius - innerRadius) * t
            let level = CGFloat(flow) * eased
            context.setStrokeColor(gray: level, alpha: 1)
            context.setFillColor(gray: level, alpha: 1)
            context.setLineWidth(max(1, currentRadius * 2))

            for stroke in strokes where !stroke.points.isEmpty {
                let points = stroke.points.map { point in
                    CGPoint(
                        x: point.x * Double(width),
                        y: (1 - point.y) * Double(height)
                    )
                }
                if points.count == 1, let point = points.first {
                    context.fillEllipse(
                        in: CGRect(
                            x: point.x - currentRadius,
                            y: point.y - currentRadius,
                            width: currentRadius * 2,
                            height: currentRadius * 2
                        )
                    )
                } else if let first = points.first {
                    context.beginPath()
                    context.move(to: first)
                    for point in points.dropFirst() {
                        context.addLine(to: point)
                    }
                    context.strokePath()
                }
            }
        }

        guard let image = context.makeImage() else {
            return CIImage(color: .black).cropped(to: extent)
        }
        brushMaskCache.setObject(image, forKey: key, cost: width * height)
        return CIImage(cgImage: image).transformed(
            by: CGAffineTransform(translationX: extent.minX, y: extent.minY)
        )
    }

    private static func applyingSpotRemoval(
        _ spot: SpotRemoval,
        to image: CIImage,
        extent: CGRect
    ) -> CIImage {
        let target = CGPoint(
            x: extent.minX + spot.targetX * extent.width,
            y: extent.minY + (1 - spot.targetY) * extent.height
        )
        let source = CGPoint(
            x: extent.minX + spot.sourceX * extent.width,
            y: extent.minY + (1 - spot.sourceY) * extent.height
        )
        let translation = CGAffineTransform(
            translationX: target.x - source.x,
            y: target.y - source.y
        )
        let sampled = image
            .clampedToExtent()
            .transformed(by: translation)
            .cropped(to: extent)

        let replacement: CIImage
        switch spot.kind {
        case .clone:
            replacement = sampled
        case .heal:
            // Source luminance carries texture while the destination keeps its
            // hue and saturation. Soft edge blending supplies the low-frequency
            // transition expected from a healing tool.
            replacement = applying(
                "CILuminosityBlendMode",
                to: sampled,
                values: [kCIInputBackgroundImageKey: image]
            ).cropped(to: extent)
        }

        let outerRadius = max(1, min(extent.width, extent.height) * spot.radius)
        let innerRadius = outerRadius * (1 - max(0.01, spot.feather))
        var mask = applyingGenerator(
            "CIRadialGradient",
            values: [
                "inputCenter": CIVector(x: target.x, y: target.y),
                "inputRadius0": innerRadius,
                "inputRadius1": outerRadius,
                "inputColor0": CIColor(red: spot.opacity, green: spot.opacity, blue: spot.opacity),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0)
            ]
        ).cropped(to: extent)
        if spot.opacity <= 0 {
            mask = CIImage(color: .black).cropped(to: extent)
        }

        return applying(
            "CIBlendWithMask",
            to: replacement,
            values: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ]
        ).cropped(to: extent)
    }

    private static func applyingGenerator(
        _ filterName: String,
        values: [String: Any]
    ) -> CIImage {
        guard let filter = CIFilter(name: filterName) else {
            return CIImage(color: .black)
        }
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? CIImage(color: .black)
    }

    private static func applyingOrientation(
        to image: CIImage,
        rotationDegrees: Int,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) -> CIImage {
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        // Core Image uses a bottom-left coordinate system; negate the angle so
        // a positive quarter turn matches the UI's visual "Rotate Right".
        let radians = -CGFloat(rotationDegrees) * .pi / 180
        let transform = CGAffineTransform.identity
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: radians)
            .scaledBy(
                x: flipHorizontal ? -1 : 1,
                y: flipVertical ? -1 : 1
            )
            .translatedBy(x: -center.x, y: -center.y)
        let transformed = image.transformed(by: transform)
        return transformed.transformed(
            by: CGAffineTransform(
                translationX: -transformed.extent.minX,
                y: -transformed.extent.minY
            )
        )
    }

    private static func applyingDevelopmentProfile(
        _ settings: DevelopmentProfileSettings,
        to image: CIImage
    ) -> CIImage {
        applying(
            "CIColorCubeWithColorSpace",
            to: image,
            values: [
                "inputCubeDimension": colorCubeDimension,
                "inputCubeData": developmentProfileCubeData(for: settings),
                "inputColorSpace": outputColorSpace
            ]
        )
    }

    /// Builds the foundation lookup table once per profile and Amount value.
    ///
    /// The transforms are deliberately bounded and keep neutral RGB inputs
    /// neutral in the Foundation profiles. Creative profiles may introduce
    /// intentional split toning, while monochrome profiles use explicit
    /// luminance channel weights.
    private static func developmentProfileCubeData(
        for rawSettings: DevelopmentProfileSettings
    ) -> Data {
        let settings = rawSettings.normalized
        let key = [
            settings.profile.rawValue,
            String(settings.amount.bitPattern, radix: 16)
        ].joined(separator: "|") as NSString
        if let cached = developmentProfileCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        let strength = settings.amount / 100
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    let target = developmentProfileTarget(
                        settings.profile,
                        red: red,
                        green: green,
                        blue: blue
                    )
                    cube.append(Float(clampUnit(
                        red + (target.red - red) * strength
                    )))
                    cube.append(Float(clampUnit(
                        green + (target.green - green) * strength
                    )))
                    cube.append(Float(clampUnit(
                        blue + (target.blue - blue) * strength
                    )))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        developmentProfileCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func developmentProfileTarget(
        _ profile: DevelopmentProfile,
        red: Double,
        green: Double,
        blue: Double
    ) -> (red: Double, green: Double, blue: Double) {
        guard profile != .cameraDefault else {
            return (red, green, blue)
        }

        let perceptualLuminance = 0.2126 * red + 0.7152 * green
            + 0.0722 * blue
        if profile == .monochrome || profile == .monochromePunch {
            let base: Double
            if profile == .monochromePunch {
                base = 0.34 * red + 0.50 * green + 0.16 * blue
            } else {
                base = perceptualLuminance
            }
            let contrast = profile == .monochromePunch ? 0.24 : 0.07
            let gray = profileTone(base, contrast: contrast)
            return (gray, gray, gray)
        }

        var hsl = rgbToHSL(red: red, green: green, blue: blue)
        switch profile {
        case .cameraDefault:
            break
        case .rawDeskColor:
            hsl.saturation = shiftedUnitValue(hsl.saturation, by: 0.07)
            hsl.luminance = profileTone(hsl.luminance, contrast: 0.08)
        case .neutral:
            hsl.saturation *= 0.90
            hsl.luminance = 0.015 + profileTone(
                hsl.luminance,
                contrast: -0.08
            ) * 0.97
        case .vivid:
            hsl.saturation = shiftedUnitValue(hsl.saturation, by: 0.20)
            hsl.luminance = profileTone(hsl.luminance, contrast: 0.18)
        case .landscape:
            let greenWeight = hueWeight(
                hue: hsl.hue,
                center: 125.0 / 360,
                radius: 82.0 / 360
            )
            let blueWeight = hueWeight(
                hue: hsl.hue,
                center: 220.0 / 360,
                radius: 78.0 / 360
            )
            hsl.saturation = shiftedUnitValue(
                hsl.saturation,
                by: 0.07 + max(greenWeight, blueWeight) * 0.16
            )
            hsl.luminance = profileTone(hsl.luminance, contrast: 0.13)
            if hsl.luminance > 0.74 {
                hsl.luminance -= (hsl.luminance - 0.74) * 0.10
            }
        case .portrait:
            let skinWeight = hueWeight(
                hue: hsl.hue,
                center: 30.0 / 360,
                radius: 58.0 / 360
            ) * min(1, hsl.saturation * 2)
            hsl.saturation = clampUnit(
                hsl.saturation * (0.95 + skinWeight * 0.10)
            )
            hsl.luminance = clampUnit(
                0.008 + profileTone(hsl.luminance, contrast: -0.045) * 0.984
            )
        case .modernCool:
            hsl.saturation *= 0.91
            hsl.luminance = profileTone(hsl.luminance, contrast: 0.09)
        case .cinematicTeal:
            hsl.saturation *= 0.90
            hsl.luminance = profileTone(hsl.luminance, contrast: 0.16)
        case .vintageWarm:
            hsl.saturation *= 0.82
            hsl.luminance = clampUnit(
                0.035 + profileTone(hsl.luminance, contrast: -0.055) * 0.92
            )
        case .monochrome, .monochromePunch:
            break
        }

        var output = hslToRGB(
            hue: hsl.hue,
            saturation: clampUnit(hsl.saturation),
            luminance: clampUnit(hsl.luminance)
        )
        switch profile {
        case .portrait:
            let highlight = pow(perceptualLuminance, 1.8) * 0.018
            output.red += highlight
            output.blue -= highlight * 0.45
        case .modernCool:
            let shadow = pow(1 - perceptualLuminance, 1.6)
            output.red -= shadow * 0.018
            output.green += shadow * 0.008
            output.blue += shadow * 0.035
        case .cinematicTeal:
            let shadow = pow(1 - perceptualLuminance, 1.7)
            let highlight = pow(perceptualLuminance, 1.8)
            output.red += highlight * 0.045 - shadow * 0.030
            output.green += shadow * 0.028 + highlight * 0.008
            output.blue += shadow * 0.042 - highlight * 0.026
        case .vintageWarm:
            let highlight = pow(perceptualLuminance, 1.5)
            output.red += highlight * 0.045
            output.green += highlight * 0.018
            output.blue -= highlight * 0.028
        default:
            break
        }
        return (
            clampUnit(output.red),
            clampUnit(output.green),
            clampUnit(output.blue)
        )
    }

    private static func profileTone(
        _ value: Double,
        contrast: Double
    ) -> Double {
        let bounded = clampUnit(value)
        let shaped = bounded + contrast * (bounded - 0.5)
            * 4 * bounded * (1 - bounded)
        return clampUnit(shaped)
    }

    private static func clampUnit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }

    /// Builds an eight-channel HSL lookup table. Core Image interpolates
    /// between its vertices on the GPU, so the same path works for previews,
    /// thumbnails, and full-resolution export.
    private static func calibrationCubeData(
        for calibration: CalibrationAdjustments
    ) -> Data {
        let key = [
            String(calibration.shadowsTint.bitPattern, radix: 16),
            String(calibration.redPrimaryHue.bitPattern, radix: 16),
            String(calibration.redPrimarySaturation.bitPattern, radix: 16),
            String(calibration.greenPrimaryHue.bitPattern, radix: 16),
            String(calibration.greenPrimarySaturation.bitPattern, radix: 16),
            String(calibration.bluePrimaryHue.bitPattern, radix: 16),
            String(calibration.bluePrimarySaturation.bitPattern, radix: 16),
        ].joined(separator: "|") as NSString
        if let cached = calibrationCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    var hsl = rgbToHSL(red: red, green: green, blue: blue)

                    if hsl.saturation > 0.000_1 {
                        let radius = 100.0 / 360
                        let redWeight = hueWeight(
                            hue: hsl.hue,
                            center: 0,
                            radius: radius
                        )
                        let greenWeight = hueWeight(
                            hue: hsl.hue,
                            center: 120.0 / 360,
                            radius: radius
                        )
                        let blueWeight = hueWeight(
                            hue: hsl.hue,
                            center: 240.0 / 360,
                            radius: radius
                        )
                        let divisor = max(1, redWeight + greenWeight + blueWeight)
                        let hueAmount = (
                            redWeight * calibration.redPrimaryHue
                                + greenWeight * calibration.greenPrimaryHue
                                + blueWeight * calibration.bluePrimaryHue
                        ) / divisor
                        let saturationAmount = (
                            redWeight * calibration.redPrimarySaturation
                                + greenWeight * calibration.greenPrimarySaturation
                                + blueWeight * calibration.bluePrimarySaturation
                        ) / divisor
                        hsl.hue = wrappedUnit(
                            hsl.hue + hueAmount / 100 * (30.0 / 360)
                        )
                        hsl.saturation = shiftedUnitValue(
                            hsl.saturation,
                            by: saturationAmount / 100
                        )
                    }

                    var output = hslToRGB(
                        hue: hsl.hue,
                        saturation: hsl.saturation,
                        luminance: hsl.luminance
                    )
                    let shadowAmount = calibration.shadowsTint / 100
                        * pow(1 - hsl.luminance, 2)
                        * 0.18
                    if abs(shadowAmount) > 0.000_1 {
                        output.red = shiftedUnitValue(output.red, by: shadowAmount)
                        output.green = shiftedUnitValue(output.green, by: -shadowAmount)
                        output.blue = shiftedUnitValue(output.blue, by: shadowAmount)
                    }

                    cube.append(Float(output.red))
                    cube.append(Float(output.green))
                    cube.append(Float(output.blue))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        calibrationCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func colorCubeData(for mixer: ColorMixer) -> Data {
        let key = ColorMixerChannel.allCases.flatMap { channel -> [String] in
            let value = mixer[channel]
            return [
                String(value.hue.bitPattern, radix: 16),
                String(value.saturation.bitPattern, radix: 16),
                String(value.luminance.bitPattern, radix: 16)
            ]
        }.joined(separator: "|") as NSString

        if let cached = colorCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    var (hue, saturation, luminance) = rgbToHSL(
                        red: red,
                        green: green,
                        blue: blue
                    )

                    var hueAmount = 0.0
                    var saturationAmount = 0.0
                    var luminanceAmount = 0.0

                    if saturation > 0.000_1 {
                        for channel in ColorMixerChannel.allCases {
                            let adjustment = mixer[channel]
                            guard !adjustment.isNeutral else { continue }
                            let weight = colorWeight(hue: hue, center: channel.centerHue)
                            hueAmount += weight * adjustment.hue / 100
                            saturationAmount += weight * adjustment.saturation / 100
                            luminanceAmount += weight * adjustment.luminance / 100
                        }
                    }

                    hue = wrappedUnit(hue + min(1, max(-1, hueAmount)) * (30 / 360))
                    saturation = shiftedUnitValue(
                        saturation,
                        by: min(1, max(-1, saturationAmount))
                    )
                    luminance = shiftedUnitValue(
                        luminance,
                        by: min(1, max(-1, luminanceAmount))
                    )

                    let output = hslToRGB(
                        hue: hue,
                        saturation: saturation,
                        luminance: luminance
                    )
                    cube.append(Float(output.red))
                    cube.append(Float(output.green))
                    cube.append(Float(output.blue))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        colorCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func pointColorCubeData(
        for points: [PointColorAdjustment]
    ) -> Data {
        let keyParts = points.flatMap { point -> [String] in
            [
                point.id.uuidString,
                String(point.sample.hue.bitPattern, radix: 16),
                String(point.sample.saturation.bitPattern, radix: 16),
                String(point.sample.luminance.bitPattern, radix: 16),
                String(point.hueShift.bitPattern, radix: 16),
                String(point.saturationShift.bitPattern, radix: 16),
                String(point.luminanceShift.bitPattern, radix: 16),
                String(point.variance.bitPattern, radix: 16),
                String(point.hueRange.bitPattern, radix: 16),
                String(point.saturationRange.bitPattern, radix: 16),
                String(point.luminanceRange.bitPattern, radix: 16)
            ]
        }
        let key = ("adjust|" + keyParts.joined(separator: "|")) as NSString
        if let cached = pointColorCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    var hsl = rgbToHSL(red: red, green: green, blue: blue)

                    for point in points {
                        let weight = pointColorWeight(
                            hue: hsl.hue,
                            saturation: hsl.saturation,
                            luminance: hsl.luminance,
                            point: point
                        )
                        guard weight > 0.000_1 else { continue }

                        if point.variance != 0 {
                            let scale = max(
                                0.05,
                                1 + point.variance / 100 * weight * 0.78
                            )
                            let sampleHue = point.sample.hue / 360
                            let hueDelta = shortestHueDelta(
                                from: sampleHue,
                                to: hsl.hue
                            )
                            hsl.hue = wrappedUnit(sampleHue + hueDelta * scale)
                            let sampleSaturation = point.sample.saturation / 100
                            let sampleLuminance = point.sample.luminance / 100
                            hsl.saturation = min(
                                1,
                                max(
                                    0,
                                    sampleSaturation
                                        + (hsl.saturation - sampleSaturation) * scale
                                )
                            )
                            hsl.luminance = min(
                                1,
                                max(
                                    0,
                                    sampleLuminance
                                        + (hsl.luminance - sampleLuminance) * scale
                                )
                            )
                        }

                        hsl.hue = wrappedUnit(
                            hsl.hue
                                + point.hueShift / 100 * (60 / 360) * weight
                        )
                        hsl.saturation = shiftedUnitValue(
                            hsl.saturation,
                            by: point.saturationShift / 100 * weight
                        )
                        hsl.luminance = shiftedUnitValue(
                            hsl.luminance,
                            by: point.luminanceShift / 100 * weight
                        )
                    }

                    let output = hslToRGB(
                        hue: hsl.hue,
                        saturation: hsl.saturation,
                        luminance: hsl.luminance
                    )
                    cube.append(Float(output.red))
                    cube.append(Float(output.green))
                    cube.append(Float(output.blue))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        pointColorCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func pointColorVisualizationCubeData(
        for point: PointColorAdjustment
    ) -> Data {
        let key = [
            "visualize",
            point.id.uuidString,
            String(point.sample.hue.bitPattern, radix: 16),
            String(point.sample.saturation.bitPattern, radix: 16),
            String(point.sample.luminance.bitPattern, radix: 16),
            String(point.hueRange.bitPattern, radix: 16),
            String(point.saturationRange.bitPattern, radix: 16),
            String(point.luminanceRange.bitPattern, radix: 16)
        ].joined(separator: "|") as NSString
        if let cached = pointColorCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    let hsl = rgbToHSL(red: red, green: green, blue: blue)
                    let weight = pointColorWeight(
                        hue: hsl.hue,
                        saturation: hsl.saturation,
                        luminance: hsl.luminance,
                        point: point
                    )
                    let visibleWeight = smoothStep(
                        edge0: 0.035,
                        edge1: 0.32,
                        value: weight
                    )
                    let background = 0.035 + hsl.luminance * 0.18
                    cube.append(Float(background + (red - background) * visibleWeight))
                    cube.append(Float(background + (green - background) * visibleWeight))
                    cube.append(Float(background + (blue - background) * visibleWeight))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        pointColorCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func maskRangeCubeData(
        for operation: MaskRangeOperation
    ) -> Data {
        let key = [
            operation.kind.rawValue,
            String(operation.colorSample.hue.bitPattern, radix: 16),
            String(operation.colorSample.saturation.bitPattern, radix: 16),
            String(operation.colorSample.luminance.bitPattern, radix: 16),
            String(operation.hueRange.bitPattern, radix: 16),
            String(operation.saturationRange.bitPattern, radix: 16),
            String(operation.colorLuminanceRange.bitPattern, radix: 16),
            String(operation.luminanceMinimum.bitPattern, radix: 16),
            String(operation.luminanceMaximum.bitPattern, radix: 16),
            String(operation.luminanceFeather.bitPattern, radix: 16),
            String(operation.depthMinimum.bitPattern, radix: 16),
            String(operation.depthMaximum.bitPattern, radix: 16),
            String(operation.depthFeather.bitPattern, radix: 16)
        ].joined(separator: "|") as NSString
        if let cached = maskRangeCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    let hsl = rgbToHSL(red: red, green: green, blue: blue)
                    let weight = maskRangeWeight(hsl: hsl, operation: operation)
                    cube.append(Float(weight))
                    cube.append(Float(weight))
                    cube.append(Float(weight))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        maskRangeCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func defringeCubeData(for optics: OpticsAdjustments) -> Data {
        let key = [
            String(optics.purpleDefringe.bitPattern, radix: 16),
            String(optics.greenDefringe.bitPattern, radix: 16)
        ].joined(separator: "|") as NSString
        if let cached = defringeCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    let hsl = rgbToHSL(red: red, green: green, blue: blue)
                    let purpleWeight = hueWeight(
                        hue: hsl.hue,
                        center: 292 / 360,
                        radius: 47 / 360
                    ) * optics.purpleDefringe / 100
                    let greenWeight = hueWeight(
                        hue: hsl.hue,
                        center: 128 / 360,
                        radius: 42 / 360
                    ) * optics.greenDefringe / 100
                    let suppression = min(0.96, max(purpleWeight, greenWeight) * 0.96)
                    let output = hslToRGB(
                        hue: hsl.hue,
                        saturation: hsl.saturation * (1 - suppression),
                        luminance: hsl.luminance
                    )
                    cube.append(Float(output.red))
                    cube.append(Float(output.green))
                    cube.append(Float(output.blue))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        defringeCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func colorGradingCubeData(for grading: ColorGrading) -> Data {
        let keyParts = ColorGradingRegion.allCases.flatMap { region -> [String] in
            let wheel = grading[region]
            return [
                String(wheel.hue.bitPattern, radix: 16),
                String(wheel.saturation.bitPattern, radix: 16),
                String(wheel.luminance.bitPattern, radix: 16)
            ]
        } + [
            String(grading.blending.bitPattern, radix: 16),
            String(grading.balance.bitPattern, radix: 16)
        ]
        let key = keyParts.joined(separator: "|") as NSString
        if let cached = colorGradingCubeCache.object(forKey: key) {
            return cached as Data
        }

        let dimension = colorCubeDimension
        let denominator = Double(dimension - 1)
        var cube = [Float]()
        cube.reserveCapacity(dimension * dimension * dimension * 4)

        for blueIndex in 0..<dimension {
            let blue = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let green = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let red = Double(redIndex) / denominator
                    let hsl = rgbToHSL(red: red, green: green, blue: blue)
                    let balancedLuminance = min(
                        1,
                        max(0, hsl.luminance + grading.balance / 100 * 0.22)
                    )
                    let overlap = 0.06 + grading.blending / 100 * 0.18
                    var shadowWeight = 1 - smoothStep(
                        edge0: 0.08,
                        edge1: 0.46 + overlap,
                        value: balancedLuminance
                    )
                    var highlightWeight = smoothStep(
                        edge0: 0.54 - overlap,
                        edge1: 0.92,
                        value: balancedLuminance
                    )
                    var midtoneWeight = smoothStep(
                        edge0: 0.02,
                        edge1: 0.48,
                        value: balancedLuminance
                    ) * (1 - smoothStep(
                        edge0: 0.52,
                        edge1: 0.98,
                        value: balancedLuminance
                    ))
                    let weightTotal = max(
                        0.000_1,
                        shadowWeight + midtoneWeight + highlightWeight
                    )
                    shadowWeight /= weightTotal
                    midtoneWeight /= weightTotal
                    highlightWeight /= weightTotal

                    var output = (red: red, green: green, blue: blue)
                    output = applyingGrade(
                        grading.shadows,
                        weight: shadowWeight,
                        to: output
                    )
                    output = applyingGrade(
                        grading.midtones,
                        weight: midtoneWeight,
                        to: output
                    )
                    output = applyingGrade(
                        grading.highlights,
                        weight: highlightWeight,
                        to: output
                    )
                    output = applyingGrade(grading.global, weight: 1, to: output)

                    cube.append(Float(output.red))
                    cube.append(Float(output.green))
                    cube.append(Float(output.blue))
                    cube.append(1)
                }
            }
        }

        let data = cube.withUnsafeBufferPointer { buffer in
            Data(
                bytes: buffer.baseAddress!,
                count: buffer.count * MemoryLayout<Float>.stride
            )
        }
        colorGradingCubeCache.setObject(data as NSData, forKey: key)
        return data
    }

    private static func applyingGrade(
        _ wheel: ColorGradingWheel,
        weight: Double,
        to input: (red: Double, green: Double, blue: Double)
    ) -> (red: Double, green: Double, blue: Double) {
        guard weight > 0.000_1, !wheel.isNeutral else { return input }
        var output = input

        if wheel.saturation > 0 {
            let currentHSL = rgbToHSL(
                red: output.red,
                green: output.green,
                blue: output.blue
            )
            let tint = hslToRGB(
                hue: wheel.hue / 360,
                saturation: max(0.72, currentHSL.saturation),
                luminance: currentHSL.luminance
            )
            let amount = min(0.86, wheel.saturation / 100 * weight * 0.86)
            output = (
                red: output.red + (tint.red - output.red) * amount,
                green: output.green + (tint.green - output.green) * amount,
                blue: output.blue + (tint.blue - output.blue) * amount
            )
        }

        if wheel.luminance != 0 {
            let currentHSL = rgbToHSL(
                red: output.red,
                green: output.green,
                blue: output.blue
            )
            let shifted = shiftedUnitValue(
                currentHSL.luminance,
                by: wheel.luminance / 100 * weight * 0.65
            )
            output = hslToRGB(
                hue: currentHSL.hue,
                saturation: currentHSL.saturation,
                luminance: shifted
            )
        }

        return (
            red: min(1, max(0, output.red)),
            green: min(1, max(0, output.green)),
            blue: min(1, max(0, output.blue))
        )
    }

    private static func smoothStep(
        edge0: Double,
        edge1: Double,
        value: Double
    ) -> Double {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func colorWeight(hue: Double, center: Double) -> Double {
        hueWeight(hue: hue, center: center, radius: 38.0 / 360)
    }

    private static func pointColorWeight(
        hue: Double,
        saturation: Double,
        luminance: Double,
        point: PointColorAdjustment
    ) -> Double {
        let sampleHue = point.sample.hue / 360
        let sampleSaturation = point.sample.saturation / 100
        let sampleLuminance = point.sample.luminance / 100
        let hueSelection = point.sample.saturation < 2
            ? 1
            : hueWeight(
                hue: hue,
                center: sampleHue,
                radius: point.hueRange / 360
            )
        let saturationSelection = axisWeight(
            value: saturation,
            center: sampleSaturation,
            radius: point.saturationRange / 100
        )
        let luminanceSelection = axisWeight(
            value: luminance,
            center: sampleLuminance,
            radius: point.luminanceRange / 100
        )
        return hueSelection * saturationSelection * luminanceSelection
    }

    private static func maskRangeWeight(
        hsl: (hue: Double, saturation: Double, luminance: Double),
        operation: MaskRangeOperation
    ) -> Double {
        switch operation.kind {
        case .color:
            let sampleHue = operation.colorSample.hue / 360
            let sampleSaturation = operation.colorSample.saturation / 100
            let sampleLuminance = operation.colorSample.luminance / 100
            let hueSelection = operation.colorSample.saturation < 2
                ? 1
                : hueWeight(
                    hue: hsl.hue,
                    center: sampleHue,
                    radius: operation.hueRange / 360
                )
            let saturationSelection = axisWeight(
                value: hsl.saturation,
                center: sampleSaturation,
                radius: operation.saturationRange / 100
            )
            let luminanceSelection = axisWeight(
                value: hsl.luminance,
                center: sampleLuminance,
                radius: operation.colorLuminanceRange / 100
            )
            return hueSelection * saturationSelection * luminanceSelection

        case .luminance, .depth:
            let lower = (
                operation.kind == .depth
                    ? operation.depthMinimum
                    : operation.luminanceMinimum
            ) / 100
            let upper = (
                operation.kind == .depth
                    ? operation.depthMaximum
                    : operation.luminanceMaximum
            ) / 100
            let feather = (
                operation.kind == .depth
                    ? operation.depthFeather
                    : operation.luminanceFeather
            ) / 100
            let lowerWeight = lower <= 0
                ? 1.0
                : feather <= 0
                ? (hsl.luminance >= lower ? 1.0 : 0.0)
                : smoothStep(
                    edge0: max(0, lower - feather),
                    edge1: lower,
                    value: hsl.luminance
                )
            let upperWeight = upper >= 1
                ? 1.0
                : feather <= 0
                ? (hsl.luminance <= upper ? 1.0 : 0.0)
                : 1 - smoothStep(
                    edge0: upper,
                    edge1: min(1, upper + feather),
                    value: hsl.luminance
                )
            return min(lowerWeight, upperWeight)
        }
    }

    private static func axisWeight(
        value: Double,
        center: Double,
        radius: Double
    ) -> Double {
        let t = min(1, max(0, 1 - abs(value - center) / max(0.000_1, radius)))
        return t * t * (3 - 2 * t)
    }

    private static func hueWeight(
        hue: Double,
        center: Double,
        radius: Double
    ) -> Double {
        let rawDistance = abs(hue - center)
        let circularDistance = min(rawDistance, 1 - rawDistance)
        let t = min(1, max(0, 1 - circularDistance / radius))
        return t * t * (3 - 2 * t)
    }

    private static func shortestHueDelta(
        from start: Double,
        to end: Double
    ) -> Double {
        var delta = wrappedUnit(end) - wrappedUnit(start)
        if delta > 0.5 {
            delta -= 1
        } else if delta < -0.5 {
            delta += 1
        }
        return delta
    }

    private static func shiftedUnitValue(_ value: Double, by amount: Double) -> Double {
        if amount < 0 {
            return min(1, max(0, value * (1 + amount)))
        }
        return min(1, max(0, value + (1 - value) * amount))
    }

    private static func rgbToHSL(
        red: Double,
        green: Double,
        blue: Double
    ) -> (hue: Double, saturation: Double, luminance: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let luminance = (maximum + minimum) / 2

        guard delta > 0.000_001 else {
            return (0, 0, luminance)
        }

        let saturation = delta / (1 - abs(2 * luminance - 1))
        let rawHue: Double
        if maximum == red {
            rawHue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            rawHue = (blue - red) / delta + 2
        } else {
            rawHue = (red - green) / delta + 4
        }

        return (wrappedUnit(rawHue / 6), saturation, luminance)
    }

    private static func hslToRGB(
        hue: Double,
        saturation: Double,
        luminance: Double
    ) -> (red: Double, green: Double, blue: Double) {
        guard saturation > 0.000_001 else {
            return (luminance, luminance, luminance)
        }

        let q = luminance < 0.5
            ? luminance * (1 + saturation)
            : luminance + saturation - luminance * saturation
        let p = 2 * luminance - q
        return (
            hueComponent(p: p, q: q, t: hue + 1.0 / 3),
            hueComponent(p: p, q: q, t: hue),
            hueComponent(p: p, q: q, t: hue - 1.0 / 3)
        )
    }

    private static func hueComponent(p: Double, q: Double, t: Double) -> Double {
        let value = wrappedUnit(t)
        if value < 1.0 / 6 {
            return p + (q - p) * 6 * value
        }
        if value < 1.0 / 2 {
            return q
        }
        if value < 2.0 / 3 {
            return p + (q - p) * (2.0 / 3 - value) * 6
        }
        return p
    }

    private static func wrappedUnit(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 1)
        return result < 0 ? result + 1 : result
    }

    private static func applying(
        _ filterName: String,
        to image: CIImage,
        values: [String: Any]
    ) -> CIImage {
        guard let filter = CIFilter(name: filterName) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? image
    }

    private static func rasterize(_ image: CIImage) throws -> NSImage {
        let extent = image.extent.integral
        guard !extent.isEmpty,
              extent.width.isFinite,
              extent.height.isFinite,
              let cgImage = context.createCGImage(
                image,
                from: extent,
                format: .RGBA8,
                colorSpace: outputColorSpace
              ) else {
            throw ProcessingError.renderingFailed
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private static func rasterizeForSoftProof(
        _ image: CIImage
    ) throws -> NSImage {
        let extent = image.extent.integral
        guard !extent.isEmpty,
              extent.width.isFinite,
              extent.height.isFinite,
              let cgImage = softProofContext.createCGImage(
                image,
                from: extent,
                format: .RGBAh,
                colorSpace: workingColorSpace
              ) else {
            throw ProcessingError.renderingFailed
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            )
        )
    }
}

/// Compact, color-managed RGBA input for deterministic off-main-thread lens
/// analysis. Keeping AppKit out of the worker task avoids sharing NSImage
/// instances across executors.
public struct ChromaticAberrationRaster: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init?(
        width: Int,
        height: Int,
        rgba: [UInt8]
    ) {
        guard width >= 8,
              height >= 8,
              rgba.count == width * height * 4 else {
            return nil
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// Estimates lateral red/blue registration and purple/green edge fringing
/// from the decoded photo. Analysis is local, deterministic, and records only
/// bounded correction values in the non-destructive edit state.
public enum AutomaticChromaticAberrationAnalyzer {
    private struct EdgeSample {
        var x: Double
        var y: Double
        var radialX: Double
        var radialY: Double
        var radiusFraction: Double
        var gradientX: Double
        var gradientY: Double
        var weight: Double
    }

    private struct Alignment {
        var shift: Double
        var improvement: Double
    }

    /// Creates a bounded analysis bitmap while still on the UI actor.
    @MainActor
    public static func raster(
        from image: NSImage,
        maximumDimension: Int = 640
    ) -> ChromaticAberrationRaster? {
        var proposed = CGRect(
            origin: .zero,
            size: image.size
        )
        guard let source = image.cgImage(
            forProposedRect: &proposed,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        let sourceWidth = max(1, source.width)
        let sourceHeight = max(1, source.height)
        let limit = max(64, min(1_024, maximumDimension))
        let scale = min(
            1,
            Double(limit)
                / Double(max(sourceWidth, sourceHeight))
        )
        let width = max(8, Int(
            (Double(sourceWidth) * scale).rounded()
        ))
        let height = max(8, Int(
            (Double(sourceHeight) * scale).rounded()
        ))
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
            space: CGColorSpace(
                name: CGColorSpace.sRGB
            ) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:
                CGImageAlphaInfo
                    .premultipliedLast.rawValue
        ) else {
            return nil
        }
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
        return ChromaticAberrationRaster(
            width: width,
            height: height,
            rgba: bytes
        )
    }

    public static func analyze(
        _ raster: ChromaticAberrationRaster
    ) -> AutomaticChromaticAberrationCorrection? {
        let samples = edgeSamples(in: raster)
        guard samples.count >= 24 else {
            return nil
        }

        let red = bestAlignment(
            channel: 0,
            samples: samples,
            raster: raster
        )
        let blue = bestAlignment(
            channel: 2,
            samples: samples,
            raster: raster
        )
        let maximumRadius = hypot(
            Double(raster.width) / 2,
            Double(raster.height) / 2
        )
        // CIBumpDistortion's small dimensionless scale is proportional to
        // radius. A negative sign converts the source-sampling offset found by
        // the analyzer into the rendered channel displacement.
        let controlPerPixel =
            100 / max(1, maximumRadius) / 0.024
        let fringe = fringeAmounts(
            samples: samples,
            raster: raster
        )
        let sampleConfidence = min(
            1,
            Double(samples.count) / 600
        )
        let signalConfidence = min(
            1,
            (red.improvement + blue.improvement) * 2.4
                + (fringe.purple + fringe.green) / 280
        )

        return AutomaticChromaticAberrationCorrection(
            redCyanShift:
                -red.shift * controlPerPixel,
            blueYellowShift:
                -blue.shift * controlPerPixel,
            purpleDefringe: fringe.purple,
            greenDefringe: fringe.green,
            confidence:
                sampleConfidence
                * max(0.08, signalConfidence),
            sampledEdgeCount: samples.count
        )
    }

    private static func edgeSamples(
        in raster: ChromaticAberrationRaster
    ) -> [EdgeSample] {
        let centerX = Double(raster.width - 1) / 2
        let centerY = Double(raster.height - 1) / 2
        let maximumRadius = hypot(centerX, centerY)
        var samples: [EdgeSample] = []
        samples.reserveCapacity(
            min(4_000, raster.width * raster.height / 16)
        )

        for y in stride(
            from: 2,
            to: raster.height - 2,
            by: 2
        ) {
            for x in stride(
                from: 2,
                to: raster.width - 2,
                by: 2
            ) {
                let dx = Double(x) - centerX
                let dy = Double(y) - centerY
                let radius = hypot(dx, dy)
                let radiusFraction =
                    radius / max(1, maximumRadius)
                guard radiusFraction >= 0.18,
                      radiusFraction <= 0.98 else {
                    continue
                }
                let gradientX =
                    (component(
                        1,
                        x: x + 1,
                        y: y,
                        in: raster
                    )
                    - component(
                        1,
                        x: x - 1,
                        y: y,
                        in: raster
                    )) / 2
                let gradientY =
                    (component(
                        1,
                        x: x,
                        y: y + 1,
                        in: raster
                    )
                    - component(
                        1,
                        x: x,
                        y: y - 1,
                        in: raster
                    )) / 2
                let magnitude = hypot(
                    gradientX,
                    gradientY
                )
                guard magnitude >= 0.035 else {
                    continue
                }
                let radialX = dx / max(0.000_1, radius)
                let radialY = dy / max(0.000_1, radius)
                let radialAlignment = abs(
                    gradientX * radialX
                        + gradientY * radialY
                ) / magnitude
                guard radialAlignment >= 0.42 else {
                    continue
                }
                samples.append(
                    EdgeSample(
                        x: Double(x),
                        y: Double(y),
                        radialX: radialX,
                        radialY: radialY,
                        radiusFraction: radiusFraction,
                        gradientX:
                            gradientX / magnitude,
                        gradientY:
                            gradientY / magnitude,
                        weight:
                            min(1, magnitude * 5)
                            * (0.4 + radiusFraction * 0.6)
                    )
                )
            }
        }
        if samples.count > 4_000 {
            let strideSize = max(
                1,
                samples.count / 4_000
            )
            return Array(
                samples.enumerated().compactMap {
                    $0.offset % strideSize == 0
                        ? $0.element
                        : nil
                }.prefix(4_000)
            )
        }
        return samples
    }

    private static func bestAlignment(
        channel: Int,
        samples: [EdgeSample],
        raster: ChromaticAberrationRaster
    ) -> Alignment {
        let candidates = stride(
            from: -3.0,
            through: 3.0,
            by: 0.25
        )
        var bestShift = 0.0
        var bestScore = Double.greatestFiniteMagnitude
        var zeroScore = Double.greatestFiniteMagnitude

        for shift in candidates {
            var score = 0.0
            var totalWeight = 0.0
            for sample in samples {
                let offset =
                    shift * sample.radiusFraction
                let x =
                    sample.x
                    + sample.radialX * offset
                let y =
                    sample.y
                    + sample.radialY * offset
                let channelBefore = bilinearComponent(
                    channel,
                    x: x - sample.gradientX,
                    y: y - sample.gradientY,
                    in: raster
                )
                let channelAfter = bilinearComponent(
                    channel,
                    x: x + sample.gradientX,
                    y: y + sample.gradientY,
                    in: raster
                )
                let greenBefore = bilinearComponent(
                    1,
                    x: sample.x - sample.gradientX,
                    y: sample.y - sample.gradientY,
                    in: raster
                )
                let greenAfter = bilinearComponent(
                    1,
                    x: sample.x + sample.gradientX,
                    y: sample.y + sample.gradientY,
                    in: raster
                )
                let derivativeError = abs(
                    (channelAfter - channelBefore)
                        - (greenAfter - greenBefore)
                )
                let centerError = abs(
                    bilinearComponent(
                        channel,
                        x: x,
                        y: y,
                        in: raster
                    )
                    - bilinearComponent(
                        1,
                        x: sample.x,
                        y: sample.y,
                        in: raster
                    )
                )
                score +=
                    (derivativeError
                        + centerError * 0.18)
                    * sample.weight
                totalWeight += sample.weight
            }
            score /= max(0.000_1, totalWeight)
            if abs(shift) < 0.001 {
                zeroScore = score
            }
            if score < bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        let improvement = max(
            0,
            (zeroScore - bestScore)
                / max(0.000_1, zeroScore)
        )
        if improvement < 0.012 {
            bestShift = 0
        }
        return Alignment(
            shift: bestShift,
            improvement: improvement
        )
    }

    private static func fringeAmounts(
        samples: [EdgeSample],
        raster: ChromaticAberrationRaster
    ) -> (purple: Double, green: Double) {
        var purple: [Double] = []
        var green: [Double] = []
        purple.reserveCapacity(samples.count)
        green.reserveCapacity(samples.count)
        for sample in samples {
            let red = bilinearComponent(
                0,
                x: sample.x,
                y: sample.y,
                in: raster
            )
            let greenValue = bilinearComponent(
                1,
                x: sample.x,
                y: sample.y,
                in: raster
            )
            let blue = bilinearComponent(
                2,
                x: sample.x,
                y: sample.y,
                in: raster
            )
            let redBlue = (red + blue) / 2
            purple.append(
                max(
                    0,
                    redBlue - greenValue
                        - abs(red - blue) * 0.12
                )
            )
            green.append(
                max(
                    0,
                    greenValue - redBlue
                        - abs(red - blue) * 0.12
                )
            )
        }
        return (
            fringeAmount(from: purple),
            fringeAmount(from: green)
        )
    }

    private static func fringeAmount(
        from values: [Double]
    ) -> Double {
        let significant = values
            .filter { $0 >= 0.018 }
            .sorted(by: >)
        guard !significant.isEmpty else {
            return 0
        }
        let count = max(
            1,
            min(
                significant.count,
                max(4, values.count / 5)
            )
        )
        let mean = significant
            .prefix(count)
            .reduce(0, +) / Double(count)
        let coverage = min(
            1,
            Double(significant.count)
                / Double(max(1, values.count)) * 4
        )
        let amount = min(
            100,
            max(0, (mean - 0.012) * 260 * coverage)
        )
        return amount >= 0.5 ? amount : 0
    }

    private static func component(
        _ channel: Int,
        x: Int,
        y: Int,
        in raster: ChromaticAberrationRaster
    ) -> Double {
        let clampedX = min(
            raster.width - 1,
            max(0, x)
        )
        let clampedY = min(
            raster.height - 1,
            max(0, y)
        )
        let offset =
            (clampedY * raster.width + clampedX) * 4
                + channel
        return Double(raster.rgba[offset]) / 255
    }

    private static func bilinearComponent(
        _ channel: Int,
        x: Double,
        y: Double,
        in raster: ChromaticAberrationRaster
    ) -> Double {
        let clampedX = min(
            Double(raster.width - 1),
            max(0, x)
        )
        let clampedY = min(
            Double(raster.height - 1),
            max(0, y)
        )
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(raster.width - 1, x0 + 1)
        let y1 = min(raster.height - 1, y0 + 1)
        let tx = clampedX - Double(x0)
        let ty = clampedY - Double(y0)
        let top =
            component(
                channel,
                x: x0,
                y: y0,
                in: raster
            ) * (1 - tx)
            + component(
                channel,
                x: x1,
                y: y0,
                in: raster
            ) * tx
        let bottom =
            component(
                channel,
                x: x0,
                y: y1,
                in: raster
            ) * (1 - tx)
            + component(
                channel,
                x: x1,
                y: y1,
                in: raster
            ) * tx
        return top * (1 - ty) + bottom * ty
    }
}

/// Serializes interactive development work so rapid slider movement cannot
/// accumulate many expensive, already-obsolete Core Image renders.
public actor PhotoRenderQueue {
    public static let preview = PhotoRenderQueue()
    public static let thumbnails = PhotoRenderQueue()

    public init() {}

    public func render(
        image: NSImage,
        adjustments: PhotoAdjustments,
        visualizePointColorID: PointColorAdjustment.ID? = nil,
        visualizeLocalMaskID: LocalAdjustmentMask.ID? = nil
    ) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        return try? PhotoProcessor.apply(
            to: image,
            adjustments: adjustments,
            visualizePointColorID: visualizePointColorID,
            visualizeLocalMaskID: visualizeLocalMaskID
        )
    }

    public func renderSoftProof(
        image: NSImage,
        adjustments: PhotoAdjustments,
        settings: SoftProofSettings,
        monitorProfile:
            SoftProofMonitorProfile? = nil,
        visualizePointColorID: PointColorAdjustment.ID? = nil,
        visualizeLocalMaskID: LocalAdjustmentMask.ID? = nil
    ) -> SoftProofRenderOutcome {
        guard !Task.isCancelled else {
            return SoftProofRenderOutcome()
        }
        do {
            return SoftProofRenderOutcome(
                result:
                    try PhotoProcessor
                        .applySoftProof(
                            to: image,
                            adjustments: adjustments,
                            settings: settings,
                            monitorProfile:
                                monitorProfile,
                            visualizePointColorID:
                                visualizePointColorID,
                            visualizeLocalMaskID:
                                visualizeLocalMaskID
                        )
            )
        } catch {
            return SoftProofRenderOutcome(
                errorMessage:
                    error.localizedDescription
            )
        }
    }
}
