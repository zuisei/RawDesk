import Foundation

/// Non-destructive, per-photo development settings.
///
/// Values intentionally mirror the ranges photographers already know from
/// desktop RAW editors. The original file is never changed; these settings are
/// applied to previews and full-resolution exports.
public struct PhotoAdjustments: Codable, Equatable, Hashable, Sendable {
    public var developmentProfile: DevelopmentProfileSettings
    public var exposure: Double
    public var contrast: Double
    public var highlights: Double
    public var shadows: Double
    public var whites: Double
    public var blacks: Double

    public var temperature: Double
    public var tint: Double
    public var vibrance: Double
    public var saturation: Double
    public var toneCurve: ToneCurve
    public var colorMixer: ColorMixer
    public var pointColors: [PointColorAdjustment]
    public var colorGrading: ColorGrading
    public var calibration: CalibrationAdjustments
    public var localMasks: [LocalAdjustmentMask]
    public var spotRemovals: [SpotRemoval]

    public var effectsEnabled: Bool
    public var texture: Double
    public var clarity: Double
    public var dehaze: Double
    public var vignette: Double
    public var grainAmount: Double
    public var grainSize: Double
    public var grainRoughness: Double

    public var sharpening: Double
    public var sharpeningRadius: Double
    public var sharpeningDetail: Double
    public var sharpeningMasking: Double
    public var noiseReduction: Double
    public var noiseReductionDetail: Double
    public var noiseReductionContrast: Double
    public var colorNoiseReduction: Double
    public var colorNoiseDetail: Double
    public var colorNoiseSmoothness: Double
    public var optics: OpticsAdjustments
    public var geometry: GeometryAdjustments
    public var rotationDegrees: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var straighten: Double
    public var crop: NormalizedCrop

    public init(
        developmentProfile: DevelopmentProfileSettings = .cameraDefault,
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        vibrance: Double = 0,
        saturation: Double = 0,
        toneCurve: ToneCurve = .neutral,
        colorMixer: ColorMixer = .neutral,
        pointColors: [PointColorAdjustment] = [],
        colorGrading: ColorGrading = .neutral,
        calibration: CalibrationAdjustments = .neutral,
        localMasks: [LocalAdjustmentMask] = [],
        spotRemovals: [SpotRemoval] = [],
        effectsEnabled: Bool = true,
        texture: Double = 0,
        clarity: Double = 0,
        dehaze: Double = 0,
        vignette: Double = 0,
        grainAmount: Double = 0,
        grainSize: Double = 25,
        grainRoughness: Double = 50,
        sharpening: Double = 0,
        sharpeningRadius: Double = 1,
        sharpeningDetail: Double = 25,
        sharpeningMasking: Double = 0,
        noiseReduction: Double = 0,
        noiseReductionDetail: Double = 50,
        noiseReductionContrast: Double = 0,
        colorNoiseReduction: Double = 0,
        colorNoiseDetail: Double = 50,
        colorNoiseSmoothness: Double = 50,
        optics: OpticsAdjustments = .neutral,
        geometry: GeometryAdjustments = .neutral,
        rotationDegrees: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        straighten: Double = 0,
        crop: NormalizedCrop = .fullFrame
    ) {
        self.developmentProfile = developmentProfile.normalized
        self.exposure = Self.clamp(exposure, to: -5...5)
        self.contrast = Self.clamp(contrast)
        self.highlights = Self.clamp(highlights)
        self.shadows = Self.clamp(shadows)
        self.whites = Self.clamp(whites)
        self.blacks = Self.clamp(blacks)
        self.temperature = Self.clamp(temperature)
        self.tint = Self.clamp(tint)
        self.vibrance = Self.clamp(vibrance)
        self.saturation = Self.clamp(saturation)
        self.toneCurve = toneCurve.normalized
        self.colorMixer = colorMixer.normalized
        self.pointColors = Array(pointColors.prefix(8)).map(\.normalized)
        self.colorGrading = colorGrading.normalized
        self.calibration = calibration.normalized
        self.localMasks = Array(localMasks.prefix(32)).map(\.normalized)
        self.spotRemovals = Array(spotRemovals.prefix(128)).map(\.normalized)
        self.effectsEnabled = effectsEnabled
        self.texture = Self.clamp(texture)
        self.clarity = Self.clamp(clarity)
        self.dehaze = Self.clamp(dehaze)
        self.vignette = Self.clamp(vignette)
        self.grainAmount = Self.clamp(grainAmount, to: 0...100)
        self.grainSize = Self.clamp(grainSize, to: 1...100)
        self.grainRoughness = Self.clamp(grainRoughness, to: 0...100)
        self.sharpening = Self.clamp(sharpening, to: 0...100)
        self.sharpeningRadius = Self.clamp(sharpeningRadius, to: 0.5...3)
        self.sharpeningDetail = Self.clamp(sharpeningDetail, to: 0...100)
        self.sharpeningMasking = Self.clamp(sharpeningMasking, to: 0...100)
        self.noiseReduction = Self.clamp(noiseReduction, to: 0...100)
        self.noiseReductionDetail = Self.clamp(noiseReductionDetail, to: 0...100)
        self.noiseReductionContrast = Self.clamp(noiseReductionContrast, to: 0...100)
        self.colorNoiseReduction = Self.clamp(colorNoiseReduction, to: 0...100)
        self.colorNoiseDetail = Self.clamp(colorNoiseDetail, to: 0...100)
        self.colorNoiseSmoothness = Self.clamp(colorNoiseSmoothness, to: 0...100)
        self.optics = optics.normalized
        self.geometry = geometry.normalized
        self.rotationDegrees = Self.normalizedRotation(rotationDegrees)
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.straighten = Self.clamp(straighten, to: -15...15)
        self.crop = crop.normalized
    }

    public static let neutral = PhotoAdjustments()

    public var isNeutral: Bool { editCount == 0 }

    public var editCount: Int {
        let scalarCount = [
            exposure, contrast, highlights, shadows, whites, blacks,
            temperature, tint, vibrance, saturation, texture, clarity, dehaze,
            vignette, grainAmount, sharpening, noiseReduction,
            colorNoiseReduction, straighten
        ].filter { abs($0) > 0.000_1 }.count
        return scalarCount
            + developmentProfile.editCount
            + toneCurve.editCount
            + colorMixer.editCount
            + pointColors.reduce(0) { $0 + $1.editCount }
            + colorGrading.editCount
            + calibration.editCount
            + localMasks.filter(\.isEffective).count
            + spotRemovals.count
            + optics.editCount
            + geometry.editCount
            + (rotationDegrees == 0 ? 0 : 1)
            + (flipHorizontal ? 1 : 0)
            + (flipVertical ? 1 : 0)
            + (effectsEnabled ? 0 : 1)
            + (crop.isFullFrame ? 0 : 1)
    }

    /// Sanitizes persisted values from older or manually edited state files.
    public var normalized: PhotoAdjustments {
        PhotoAdjustments(
            developmentProfile: developmentProfile,
            exposure: exposure,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            whites: whites,
            blacks: blacks,
            temperature: temperature,
            tint: tint,
            vibrance: vibrance,
            saturation: saturation,
            toneCurve: toneCurve,
            colorMixer: colorMixer,
            pointColors: pointColors,
            colorGrading: colorGrading,
            calibration: calibration,
            localMasks: localMasks,
            spotRemovals: spotRemovals,
            effectsEnabled: effectsEnabled,
            texture: texture,
            clarity: clarity,
            dehaze: dehaze,
            vignette: vignette,
            grainAmount: grainAmount,
            grainSize: grainSize,
            grainRoughness: grainRoughness,
            sharpening: sharpening,
            sharpeningRadius: sharpeningRadius,
            sharpeningDetail: sharpeningDetail,
            sharpeningMasking: sharpeningMasking,
            noiseReduction: noiseReduction,
            noiseReductionDetail: noiseReductionDetail,
            noiseReductionContrast: noiseReductionContrast,
            colorNoiseReduction: colorNoiseReduction,
            colorNoiseDetail: colorNoiseDetail,
            colorNoiseSmoothness: colorNoiseSmoothness,
            optics: optics,
            geometry: geometry,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical,
            straighten: straighten,
            crop: crop
        )
    }

    private enum CodingKeys: String, CodingKey {
        case developmentProfile
        case exposure, contrast, highlights, shadows, whites, blacks
        case temperature, tint, vibrance, saturation
        case toneCurve, colorMixer, pointColors, colorGrading, calibration
        case localMasks, spotRemovals
        case effectsEnabled
        case texture, clarity, dehaze, vignette
        case grainAmount, grainSize, grainRoughness
        case sharpening, sharpeningRadius, sharpeningDetail, sharpeningMasking
        case noiseReduction, noiseReductionDetail, noiseReductionContrast
        case colorNoiseReduction, colorNoiseDetail, colorNoiseSmoothness
        case optics, geometry
        case rotationDegrees, flipHorizontal, flipVertical
        case straighten, crop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            developmentProfile: try container.decodeIfPresent(
                DevelopmentProfileSettings.self,
                forKey: .developmentProfile
            ) ?? .cameraDefault,
            exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            whites: try container.decodeIfPresent(Double.self, forKey: .whites) ?? 0,
            blacks: try container.decodeIfPresent(Double.self, forKey: .blacks) ?? 0,
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            tint: try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            vibrance: try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            toneCurve: try container.decodeIfPresent(ToneCurve.self, forKey: .toneCurve) ?? .neutral,
            colorMixer: try container.decodeIfPresent(ColorMixer.self, forKey: .colorMixer) ?? .neutral,
            pointColors: try container.decodeIfPresent(
                [PointColorAdjustment].self,
                forKey: .pointColors
            ) ?? [],
            colorGrading: try container.decodeIfPresent(
                ColorGrading.self,
                forKey: .colorGrading
            ) ?? .neutral,
            calibration: try container.decodeIfPresent(
                CalibrationAdjustments.self,
                forKey: .calibration
            ) ?? .neutral,
            localMasks: try container.decodeIfPresent(
                [LocalAdjustmentMask].self,
                forKey: .localMasks
            ) ?? [],
            spotRemovals: try container.decodeIfPresent(
                [SpotRemoval].self,
                forKey: .spotRemovals
            ) ?? [],
            effectsEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .effectsEnabled
            ) ?? true,
            texture: try container.decodeIfPresent(Double.self, forKey: .texture) ?? 0,
            clarity: try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0,
            dehaze: try container.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0,
            vignette: try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
            grainAmount: try container.decodeIfPresent(Double.self, forKey: .grainAmount) ?? 0,
            grainSize: try container.decodeIfPresent(Double.self, forKey: .grainSize) ?? 25,
            grainRoughness: try container.decodeIfPresent(
                Double.self,
                forKey: .grainRoughness
            ) ?? 50,
            sharpening: try container.decodeIfPresent(Double.self, forKey: .sharpening) ?? 0,
            sharpeningRadius: try container.decodeIfPresent(
                Double.self,
                forKey: .sharpeningRadius
            ) ?? 1,
            sharpeningDetail: try container.decodeIfPresent(
                Double.self,
                forKey: .sharpeningDetail
            ) ?? 25,
            sharpeningMasking: try container.decodeIfPresent(
                Double.self,
                forKey: .sharpeningMasking
            ) ?? 0,
            noiseReduction: try container.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0,
            noiseReductionDetail: try container.decodeIfPresent(
                Double.self,
                forKey: .noiseReductionDetail
            ) ?? 50,
            noiseReductionContrast: try container.decodeIfPresent(
                Double.self,
                forKey: .noiseReductionContrast
            ) ?? 0,
            colorNoiseReduction: try container.decodeIfPresent(
                Double.self,
                forKey: .colorNoiseReduction
            ) ?? 0,
            colorNoiseDetail: try container.decodeIfPresent(
                Double.self,
                forKey: .colorNoiseDetail
            ) ?? 50,
            colorNoiseSmoothness: try container.decodeIfPresent(
                Double.self,
                forKey: .colorNoiseSmoothness
            ) ?? 50,
            optics: try container.decodeIfPresent(
                OpticsAdjustments.self,
                forKey: .optics
            ) ?? .neutral,
            geometry: try container.decodeIfPresent(
                GeometryAdjustments.self,
                forKey: .geometry
            ) ?? .neutral,
            rotationDegrees: try container.decodeIfPresent(Int.self, forKey: .rotationDegrees) ?? 0,
            flipHorizontal: try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false,
            flipVertical: try container.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false,
            straighten: try container.decodeIfPresent(Double.self, forKey: .straighten) ?? 0,
            crop: try container.decodeIfPresent(NormalizedCrop.self, forKey: .crop) ?? .fullFrame
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double> = -100...100) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 0))
    }

    private static func normalizedRotation(_ value: Int) -> Int {
        let snapped = Int((Double(value) / 90).rounded()) * 90
        return ((snapped % 360) + 360) % 360
    }
}
