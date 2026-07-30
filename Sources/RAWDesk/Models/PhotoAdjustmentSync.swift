import Foundation

public enum PhotoAdjustmentGroup:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case profile
    case light
    case color
    case toneCurve
    case colorMixer
    case pointColor
    case colorGrading
    case calibration
    case masks
    case healing
    case optics
    case geometry
    case effects
    case detail

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .profile: return "Profile"
        case .light: return "Light"
        case .color: return "Color"
        case .toneCurve: return "Tone Curve"
        case .colorMixer: return "Color Mixer"
        case .pointColor: return "Point Color"
        case .colorGrading: return "Color Grading"
        case .calibration: return "Calibration"
        case .masks: return "Masks"
        case .healing: return "Healing"
        case .optics: return "Optics"
        case .geometry: return "Crop & Geometry"
        case .effects: return "Effects"
        case .detail: return "Detail"
        }
    }

    public var systemImage: String {
        switch self {
        case .profile: return "camera.aperture"
        case .light: return "sun.max"
        case .color: return "thermometer.medium"
        case .toneCurve: return "point.topleft.down.to.point.bottomright.curvepath"
        case .colorMixer: return "slider.horizontal.3"
        case .pointColor: return "eyedropper"
        case .colorGrading: return "circle.hexagongrid"
        case .calibration: return "scope"
        case .masks: return "circle.lefthalf.filled"
        case .healing: return "bandage"
        case .optics: return "camera.filters"
        case .geometry: return "crop.rotate"
        case .effects: return "wand.and.stars"
        case .detail: return "viewfinder"
        }
    }

    public static let all = Set(allCases)
}

/// Determines whether a multi-photo control must present the neutral
/// “Mixed” state. Optional values let callers treat a control that is absent
/// from only some selected photos as mixed instead of silently substituting a
/// numeric default.
public enum PhotoAdjustmentMixedValuePlanner {
    public static func doublesAreMixed(
        _ values: [Double?],
        tolerance: Double = 0.000_001
    ) -> Bool {
        guard values.count > 1,
              let first = values.first else {
            return false
        }
        return values.dropFirst().contains { candidate in
            switch (first, candidate) {
            case let (.some(firstValue), .some(nextValue)):
                return abs(firstValue - nextValue) > tolerance
            case (.none, .none):
                return false
            default:
                return true
            }
        }
    }

    public static func valuesAreMixed<Value: Equatable>(
        _ values: [Value?]
    ) -> Bool {
        guard values.count > 1,
              let first = values.first else {
            return false
        }
        return values.dropFirst().contains {
            $0 != first
        }
    }
}

/// Selective batch synchronization and leaf-level Auto Sync planning.
///
/// Manual synchronization copies complete user-selected panels. Auto Sync
/// instead applies only values that changed on the active photo, preserving
/// unrelated settings already present on every other selected photo.
public enum PhotoAdjustmentSyncPlanner {
    public static func merging(
        source: PhotoAdjustments,
        into target: PhotoAdjustments,
        groups: Set<PhotoAdjustmentGroup>
    ) -> PhotoAdjustments {
        var result = target
        for group in PhotoAdjustmentGroup.allCases
            where groups.contains(group) {
            copy(
                group,
                from: source,
                to: &result
            )
        }
        return result.normalized
    }

    public static func modifiedGroups(
        in adjustments: PhotoAdjustments
    ) -> Set<PhotoAdjustmentGroup> {
        changedGroups(
            from: .neutral,
            to: adjustments
        )
    }

    public static func changedGroups(
        from before: PhotoAdjustments,
        to after: PhotoAdjustments
    ) -> Set<PhotoAdjustmentGroup> {
        Set(
            PhotoAdjustmentGroup.allCases.filter { group in
                merging(
                    source: after,
                    into: before,
                    groups: [group]
                ) != before.normalized
            }
        )
    }

    public static func applyingAutomaticChanges(
        from before: PhotoAdjustments,
        to after: PhotoAdjustments,
        onto target: PhotoAdjustments
    ) -> PhotoAdjustments {
        var result = target

        copyChanged(
            \.developmentProfile.profile,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.developmentProfile.amount,
            from: before,
            to: after,
            into: &result
        )

        [
            \PhotoAdjustments.exposure,
            \.contrast,
            \.highlights,
            \.shadows,
            \.whites,
            \.blacks,
            \.temperature,
            \.tint,
            \.vibrance,
            \.saturation,
            \.texture,
            \.clarity,
            \.dehaze,
            \.vignette,
            \.grainAmount,
            \.grainSize,
            \.grainRoughness,
            \.sharpening,
            \.sharpeningRadius,
            \.sharpeningDetail,
            \.sharpeningMasking,
            \.noiseReduction,
            \.noiseReductionDetail,
            \.noiseReductionContrast,
            \.colorNoiseReduction,
            \.colorNoiseDetail,
            \.colorNoiseSmoothness,
            \.straighten,
        ].forEach {
            copyChanged(
                $0,
                from: before,
                to: after,
                into: &result
            )
        }

        [
            \PhotoAdjustments.toneCurve.black,
            \.toneCurve.shadows,
            \.toneCurve.midtones,
            \.toneCurve.highlights,
            \.toneCurve.white,
        ].forEach {
            copyChanged(
                $0,
                from: before,
                to: after,
                into: &result
            )
        }

        copyColorMixerChanges(
            from: before,
            to: after,
            into: &result
        )

        copyChanged(
            \.pointColors,
            from: before,
            to: after,
            into: &result
        )
        copyColorGradingChanges(
            from: before,
            to: after,
            into: &result
        )

        [
            \PhotoAdjustments.calibration.shadowsTint,
            \.calibration.redPrimaryHue,
            \.calibration.redPrimarySaturation,
            \.calibration.greenPrimaryHue,
            \.calibration.greenPrimarySaturation,
            \.calibration.bluePrimaryHue,
            \.calibration.bluePrimarySaturation,
        ].forEach {
            copyChanged(
                $0,
                from: before,
                to: after,
                into: &result
            )
        }

        copyChanged(
            \.localMasks,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.spotRemovals,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.effectsEnabled,
            from: before,
            to: after,
            into: &result
        )

        [
            \PhotoAdjustments.optics.distortion,
            \.optics.vignette,
            \.optics.redCyanShift,
            \.optics.blueYellowShift,
            \.optics.purpleDefringe,
            \.optics.greenDefringe,
        ].forEach {
            copyChanged(
                $0,
                from: before,
                to: after,
                into: &result
            )
        }
        copyChanged(
            \.optics.automaticChromaticAberration,
            from: before,
            to: after,
            into: &result
        )

        [
            \PhotoAdjustments.geometry.vertical,
            \.geometry.horizontal,
            \.geometry.aspect,
            \.geometry.scale,
            \.geometry.offsetX,
            \.geometry.offsetY,
        ].forEach {
            copyChanged(
                $0,
                from: before,
                to: after,
                into: &result
            )
        }
        copyChanged(
            \.geometry.constrainCrop,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.geometry.guidedUprightGuides,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.rotationDegrees,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.flipHorizontal,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.flipVertical,
            from: before,
            to: after,
            into: &result
        )
        copyChanged(
            \.crop,
            from: before,
            to: after,
            into: &result
        )

        return result.normalized
    }

    private static func copy(
        _ group: PhotoAdjustmentGroup,
        from source: PhotoAdjustments,
        to target: inout PhotoAdjustments
    ) {
        switch group {
        case .profile:
            target.developmentProfile =
                source.developmentProfile
        case .light:
            target.exposure = source.exposure
            target.contrast = source.contrast
            target.highlights = source.highlights
            target.shadows = source.shadows
            target.whites = source.whites
            target.blacks = source.blacks
        case .color:
            target.temperature = source.temperature
            target.tint = source.tint
            target.vibrance = source.vibrance
            target.saturation = source.saturation
        case .toneCurve:
            target.toneCurve = source.toneCurve
        case .colorMixer:
            target.colorMixer = source.colorMixer
        case .pointColor:
            target.pointColors = source.pointColors
        case .colorGrading:
            target.colorGrading = source.colorGrading
        case .calibration:
            target.calibration = source.calibration
        case .masks:
            target.localMasks = source.localMasks
        case .healing:
            target.spotRemovals = source.spotRemovals
        case .optics:
            target.optics = source.optics
        case .geometry:
            target.geometry = source.geometry
            target.rotationDegrees = source.rotationDegrees
            target.flipHorizontal = source.flipHorizontal
            target.flipVertical = source.flipVertical
            target.straighten = source.straighten
            target.crop = source.crop
        case .effects:
            target.effectsEnabled = source.effectsEnabled
            target.texture = source.texture
            target.clarity = source.clarity
            target.dehaze = source.dehaze
            target.vignette = source.vignette
            target.grainAmount = source.grainAmount
            target.grainSize = source.grainSize
            target.grainRoughness = source.grainRoughness
        case .detail:
            target.sharpening = source.sharpening
            target.sharpeningRadius =
                source.sharpeningRadius
            target.sharpeningDetail =
                source.sharpeningDetail
            target.sharpeningMasking =
                source.sharpeningMasking
            target.noiseReduction =
                source.noiseReduction
            target.noiseReductionDetail =
                source.noiseReductionDetail
            target.noiseReductionContrast =
                source.noiseReductionContrast
            target.colorNoiseReduction =
                source.colorNoiseReduction
            target.colorNoiseDetail =
                source.colorNoiseDetail
            target.colorNoiseSmoothness =
                source.colorNoiseSmoothness
        }
    }

    private static func copyChanged<Value: Equatable>(
        _ keyPath: WritableKeyPath<
            PhotoAdjustments,
            Value
        >,
        from before: PhotoAdjustments,
        to after: PhotoAdjustments,
        into target: inout PhotoAdjustments
    ) {
        guard before[keyPath: keyPath]
                != after[keyPath: keyPath] else {
            return
        }
        target[keyPath: keyPath] =
            after[keyPath: keyPath]
    }

    private static func copyColorMixerChanges(
        from before: PhotoAdjustments,
        to after: PhotoAdjustments,
        into target: inout PhotoAdjustments
    ) {
        for channel in ColorMixerChannel.allCases {
            let previous = before.colorMixer[channel]
            let updated = after.colorMixer[channel]
            var destination = target.colorMixer[channel]
            if previous.hue != updated.hue {
                destination.hue = updated.hue
            }
            if previous.saturation != updated.saturation {
                destination.saturation = updated.saturation
            }
            if previous.luminance != updated.luminance {
                destination.luminance = updated.luminance
            }
            target.colorMixer[channel] =
                destination.normalized
        }
    }

    private static func copyColorGradingChanges(
        from before: PhotoAdjustments,
        to after: PhotoAdjustments,
        into target: inout PhotoAdjustments
    ) {
        for region in ColorGradingRegion.allCases {
            let previous = before.colorGrading[region]
            let updated = after.colorGrading[region]
            var destination = target.colorGrading[region]
            if previous.hue != updated.hue {
                destination.hue = updated.hue
            }
            if previous.saturation != updated.saturation {
                destination.saturation =
                    updated.saturation
            }
            if previous.luminance != updated.luminance {
                destination.luminance =
                    updated.luminance
            }
            target.colorGrading[region] =
                destination.normalized
        }
        if before.colorGrading.blending
            != after.colorGrading.blending {
            target.colorGrading.blending =
                after.colorGrading.blending
        }
        if before.colorGrading.balance
            != after.colorGrading.balance {
            target.colorGrading.balance =
                after.colorGrading.balance
        }
    }
}
