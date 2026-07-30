import Foundation

public enum LocalMaskKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case subject
    case object
    case sky
    case brush
    case radial
    case linear

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .subject: return "Select Subject"
        case .object: return "Select Object"
        case .sky: return "Select Sky"
        case .brush: return "Brush"
        case .radial: return "Radial Gradient"
        case .linear: return "Linear Gradient"
        }
    }

    public var systemImage: String {
        switch self {
        case .subject: return "person.crop.circle"
        case .object: return "viewfinder.circle"
        case .sky: return "cloud.sun"
        case .brush: return "paintbrush.pointed"
        case .radial: return "circle.dotted"
        case .linear: return "rectangle.split.3x1"
        }
    }
}

/// How a range selection changes the mask produced by the primary tool.
public enum MaskCombinationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case add
    case subtract
    case intersect

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .intersect: return "Intersect"
        }
    }

    public var systemImage: String {
        switch self {
        case .add: return "plus.circle"
        case .subtract: return "minus.circle"
        case .intersect: return "circle.grid.cross"
        }
    }
}

public enum MaskRangeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case color
    case luminance
    case depth

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .color: return "Color Range"
        case .luminance: return "Luminance Range"
        case .depth: return "Depth Range"
        }
    }

    public var systemImage: String {
        switch self {
        case .color: return "eyedropper"
        case .luminance: return "circle.lefthalf.filled"
        case .depth: return "square.3.layers.3d"
        }
    }
}

/// A source-image-dependent selection that is combined with a primary mask.
///
/// Operations are evaluated in array order. This keeps the model compact while
/// still allowing Lightroom-style Add, Subtract, and Intersect refinements.
public struct MaskRangeOperation: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: MaskRangeKind
    public var combination: MaskCombinationMode
    public var isEnabled: Bool
    public var inverted: Bool
    public var colorSample: PointColorSample
    public var hueRange: Double
    public var saturationRange: Double
    public var colorLuminanceRange: Double
    public var luminanceMinimum: Double
    public var luminanceMaximum: Double
    public var luminanceFeather: Double
    public var rasterMaskData: Data?
    public var depthMinimum: Double
    public var depthMaximum: Double
    public var depthFeather: Double

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        kind: MaskRangeKind,
        combination: MaskCombinationMode = .intersect,
        isEnabled: Bool = true,
        inverted: Bool = false,
        colorSample: PointColorSample = PointColorSample(
            hue: 0,
            saturation: 0,
            luminance: 50
        ),
        hueRange: Double = 30,
        saturationRange: Double = 35,
        colorLuminanceRange: Double = 35,
        luminanceMinimum: Double = 20,
        luminanceMaximum: Double = 80,
        luminanceFeather: Double = 15,
        rasterMaskData: Data? = nil,
        depthMinimum: Double = 0,
        depthMaximum: Double = 50,
        depthFeather: Double = 10
    ) {
        self.id = id
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmedName.isEmpty ? kind.name : trimmedName
        self.kind = kind
        self.combination = combination
        self.isEnabled = isEnabled
        self.inverted = inverted
        self.colorSample = colorSample.normalized
        self.hueRange = Self.clamp(hueRange, to: 1...180)
        self.saturationRange = Self.clamp(saturationRange, to: 1...100)
        self.colorLuminanceRange = Self.clamp(colorLuminanceRange, to: 1...100)
        let lower = Self.clamp(luminanceMinimum, to: 0...100)
        let upper = Self.clamp(luminanceMaximum, to: 0...100)
        self.luminanceMinimum = min(lower, upper)
        self.luminanceMaximum = max(lower, upper)
        self.luminanceFeather = Self.clamp(luminanceFeather, to: 0...50)
        self.rasterMaskData = rasterMaskData.map {
            Data($0.prefix(2_000_000))
        }
        let near = Self.clamp(depthMinimum, to: 0...100)
        let far = Self.clamp(depthMaximum, to: 0...100)
        self.depthMinimum = min(near, far)
        self.depthMaximum = max(near, far)
        self.depthFeather = Self.clamp(depthFeather, to: 0...50)
    }

    public var normalized: MaskRangeOperation {
        MaskRangeOperation(
            id: id,
            name: name,
            kind: kind,
            combination: combination,
            isEnabled: isEnabled,
            inverted: inverted,
            colorSample: colorSample,
            hueRange: hueRange,
            saturationRange: saturationRange,
            colorLuminanceRange: colorLuminanceRange,
            luminanceMinimum: luminanceMinimum,
            luminanceMaximum: luminanceMaximum,
            luminanceFeather: luminanceFeather,
            rasterMaskData: rasterMaskData,
            depthMinimum: depthMinimum,
            depthMaximum: depthMaximum,
            depthFeather: depthFeather
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, combination, isEnabled, inverted, colorSample
        case hueRange, saturationRange, colorLuminanceRange
        case luminanceMinimum, luminanceMaximum, luminanceFeather
        case rasterMaskData, depthMinimum, depthMaximum, depthFeather
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(MaskRangeKind.self, forKey: .kind)
            ?? .luminance
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name),
            kind: kind,
            combination: try container.decodeIfPresent(
                MaskCombinationMode.self,
                forKey: .combination
            ) ?? .intersect,
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            inverted: try container.decodeIfPresent(Bool.self, forKey: .inverted) ?? false,
            colorSample: try container.decodeIfPresent(
                PointColorSample.self,
                forKey: .colorSample
            ) ?? PointColorSample(hue: 0, saturation: 0, luminance: 50),
            hueRange: try container.decodeIfPresent(Double.self, forKey: .hueRange) ?? 30,
            saturationRange: try container.decodeIfPresent(
                Double.self,
                forKey: .saturationRange
            ) ?? 35,
            colorLuminanceRange: try container.decodeIfPresent(
                Double.self,
                forKey: .colorLuminanceRange
            ) ?? 35,
            luminanceMinimum: try container.decodeIfPresent(
                Double.self,
                forKey: .luminanceMinimum
            ) ?? 20,
            luminanceMaximum: try container.decodeIfPresent(
                Double.self,
                forKey: .luminanceMaximum
            ) ?? 80,
            luminanceFeather: try container.decodeIfPresent(
                Double.self,
                forKey: .luminanceFeather
            ) ?? 15,
            rasterMaskData: try container.decodeIfPresent(
                Data.self,
                forKey: .rasterMaskData
            ),
            depthMinimum: try container.decodeIfPresent(
                Double.self,
                forKey: .depthMinimum
            ) ?? 0,
            depthMaximum: try container.decodeIfPresent(
                Double.self,
                forKey: .depthMaximum
            ) ?? 50,
            depthFeather: try container.decodeIfPresent(
                Double.self,
                forKey: .depthFeather
            ) ?? 10
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }
}

public struct BrushPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    public var normalized: BrushPoint {
        BrushPoint(x: x, y: y)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public struct BrushStroke: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var points: [BrushPoint]

    public init(id: UUID = UUID(), points: [BrushPoint]) {
        self.id = id
        self.points = Array(points.prefix(2_048)).map(\.normalized)
    }

    public var normalized: BrushStroke {
        BrushStroke(id: id, points: points)
    }
}

/// An additional primary selection tool inside a local mask.
///
/// The root selection remains on `LocalAdjustmentMask` for backward
/// compatibility. These operations are evaluated in array order and allow
/// subject, object, sky, brush, radial, and linear tools to be added,
/// subtracted, or intersected inside the same mask.
public struct MaskPrimaryOperation: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: LocalMaskKind
    public var combination: MaskCombinationMode
    public var isEnabled: Bool
    public var inverted: Bool
    public var centerX: Double
    public var centerY: Double
    public var size: Double
    public var feather: Double
    public var angle: Double
    public var flow: Double
    public var strokes: [BrushStroke]
    public var rasterMaskData: Data?

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        kind: LocalMaskKind,
        combination: MaskCombinationMode = .add,
        isEnabled: Bool = true,
        inverted: Bool = false,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        size: Double = 0.55,
        feather: Double = 0.5,
        angle: Double = 0,
        flow: Double = 1,
        strokes: [BrushStroke] = [],
        rasterMaskData: Data? = nil
    ) {
        self.id = id
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmedName.isEmpty ? kind.name : trimmedName
        self.kind = kind
        self.combination = combination
        self.isEnabled = isEnabled
        self.inverted = inverted
        self.centerX = Self.clamp(centerX, to: 0...1)
        self.centerY = Self.clamp(centerY, to: 0...1)
        self.size = Self.clamp(size, to: 0.005...1.5)
        self.feather = Self.clamp(feather, to: 0...1)
        self.angle = Self.normalizedAngle(angle)
        self.flow = Self.clamp(flow, to: 0...1)
        self.strokes = Array(strokes.prefix(256))
            .map(\.normalized)
            .filter { !$0.points.isEmpty }
        self.rasterMaskData = rasterMaskData.map {
            Data($0.prefix(2_000_000))
        }
    }

    public var hasCoverage: Bool {
        switch kind {
        case .brush:
            return !strokes.isEmpty && flow > 0.000_1
        case .subject, .object, .sky:
            return !(rasterMaskData?.isEmpty ?? true)
        case .radial, .linear:
            return true
        }
    }

    public var normalized: MaskPrimaryOperation {
        MaskPrimaryOperation(
            id: id,
            name: name,
            kind: kind,
            combination: combination,
            isEnabled: isEnabled,
            inverted: inverted,
            centerX: centerX,
            centerY: centerY,
            size: size,
            feather: feather,
            angle: angle,
            flow: flow,
            strokes: strokes,
            rasterMaskData: rasterMaskData
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, combination, isEnabled, inverted
        case centerX, centerY, size, feather, angle, flow
        case strokes, rasterMaskData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(LocalMaskKind.self, forKey: .kind)
            ?? .radial
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name),
            kind: kind,
            combination: try container.decodeIfPresent(
                MaskCombinationMode.self,
                forKey: .combination
            ) ?? .add,
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            inverted: try container.decodeIfPresent(Bool.self, forKey: .inverted) ?? false,
            centerX: try container.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5,
            centerY: try container.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5,
            size: try container.decodeIfPresent(Double.self, forKey: .size)
                ?? (kind == .brush ? 0.04 : 0.55),
            feather: try container.decodeIfPresent(Double.self, forKey: .feather)
                ?? (kind == .brush ? 0.65 : 0.5),
            angle: try container.decodeIfPresent(Double.self, forKey: .angle) ?? 0,
            flow: try container.decodeIfPresent(Double.self, forKey: .flow) ?? 1,
            strokes: try container.decodeIfPresent(
                [BrushStroke].self,
                forKey: .strokes
            ) ?? [],
            rasterMaskData: try container.decodeIfPresent(
                Data.self,
                forKey: .rasterMaskData
            )
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : (wrapped < -180 ? wrapped + 360 : wrapped)
    }
}

public struct LocalToneAdjustments: Codable, Equatable, Hashable, Sendable {
    public var exposure: Double
    public var contrast: Double
    public var highlights: Double
    public var shadows: Double
    public var whites: Double
    public var blacks: Double
    public var temperature: Double
    public var tint: Double
    public var hue: Double
    public var saturation: Double
    public var texture: Double
    public var clarity: Double
    public var dehaze: Double
    public var sharpness: Double
    public var noiseReduction: Double

    public init(
        exposure: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        hue: Double = 0,
        saturation: Double = 0,
        texture: Double = 0,
        clarity: Double = 0,
        dehaze: Double = 0,
        sharpness: Double = 0,
        noiseReduction: Double = 0
    ) {
        self.exposure = Self.clamp(exposure, to: -5...5)
        self.contrast = Self.clamp(contrast)
        self.highlights = Self.clamp(highlights)
        self.shadows = Self.clamp(shadows)
        self.whites = Self.clamp(whites)
        self.blacks = Self.clamp(blacks)
        self.temperature = Self.clamp(temperature)
        self.tint = Self.clamp(tint)
        self.hue = Self.clamp(hue, to: -180...180)
        self.saturation = Self.clamp(saturation)
        self.texture = Self.clamp(texture)
        self.clarity = Self.clamp(clarity)
        self.dehaze = Self.clamp(dehaze)
        self.sharpness = Self.clamp(sharpness)
        self.noiseReduction = Self.clamp(noiseReduction, to: 0...100)
    }

    public static let neutral = LocalToneAdjustments()

    public var isNeutral: Bool { self == .neutral }

    public var normalized: LocalToneAdjustments {
        LocalToneAdjustments(
            exposure: exposure,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            whites: whites,
            blacks: blacks,
            temperature: temperature,
            tint: tint,
            hue: hue,
            saturation: saturation,
            texture: texture,
            clarity: clarity,
            dehaze: dehaze,
            sharpness: sharpness,
            noiseReduction: noiseReduction
        )
    }

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks
        case temperature, tint, hue, saturation
        case texture, clarity, dehaze, sharpness, noiseReduction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
            contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
            shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
            whites: try container.decodeIfPresent(Double.self, forKey: .whites) ?? 0,
            blacks: try container.decodeIfPresent(Double.self, forKey: .blacks) ?? 0,
            temperature: try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
            tint: try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
            hue: try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0,
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            texture: try container.decodeIfPresent(Double.self, forKey: .texture) ?? 0,
            clarity: try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0,
            dehaze: try container.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0,
            sharpness: try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0,
            noiseReduction: try container.decodeIfPresent(
                Double.self,
                forKey: .noiseReduction
            ) ?? 0
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double> = -100...100
    ) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 0))
    }
}

public struct LocalAdjustmentMask: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: LocalMaskKind
    public var centerX: Double
    public var centerY: Double
    public var size: Double
    public var feather: Double
    public var angle: Double
    public var inverted: Bool
    public var flow: Double
    public var strokes: [BrushStroke]
    public var rasterMaskData: Data?
    public var primaryOperations: [MaskPrimaryOperation]
    public var rangeOperations: [MaskRangeOperation]
    public var pointColors: [PointColorAdjustment]
    public var adjustments: LocalToneAdjustments

    public init(
        id: UUID = UUID(),
        name: String,
        kind: LocalMaskKind,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        size: Double = 0.55,
        feather: Double = 0.5,
        angle: Double = 0,
        inverted: Bool = false,
        flow: Double = 1,
        strokes: [BrushStroke] = [],
        rasterMaskData: Data? = nil,
        primaryOperations: [MaskPrimaryOperation] = [],
        rangeOperations: [MaskRangeOperation] = [],
        pointColors: [PointColorAdjustment] = [],
        adjustments: LocalToneAdjustments = LocalToneAdjustments(exposure: 0.5)
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.centerX = Self.clamp(centerX, to: 0...1)
        self.centerY = Self.clamp(centerY, to: 0...1)
        self.size = Self.clamp(size, to: 0.005...1.5)
        self.feather = Self.clamp(feather, to: 0...1)
        self.angle = Self.normalizedAngle(angle)
        self.inverted = inverted
        self.flow = Self.clamp(flow, to: 0...1)
        self.strokes = Array(strokes.prefix(256))
            .map(\.normalized)
            .filter { !$0.points.isEmpty }
        self.rasterMaskData = rasterMaskData.map {
            Data($0.prefix(2_000_000))
        }
        self.primaryOperations = Array(primaryOperations.prefix(16)).map(\.normalized)
        self.rangeOperations = Array(rangeOperations.prefix(16)).map(\.normalized)
        self.pointColors = Array(pointColors.prefix(8)).map(\.normalized)
        self.adjustments = adjustments.normalized
    }

    public var isEffective: Bool {
        guard !adjustments.isNeutral || pointColors.contains(where: \.isEffective) else {
            return false
        }
        let primaryHasCoverage: Bool
        switch kind {
        case .brush:
            primaryHasCoverage = !strokes.isEmpty && flow > 0.000_1
        case .subject, .object, .sky:
            primaryHasCoverage = !(rasterMaskData?.isEmpty ?? true)
        case .radial, .linear:
            primaryHasCoverage = true
        }
        return primaryHasCoverage
            || inverted
            || primaryOperations.contains {
                $0.isEnabled && $0.combination == .add && ($0.hasCoverage || $0.inverted)
            }
            || rangeOperations.contains {
                $0.isEnabled && $0.combination == .add
            }
    }

    public var normalized: LocalAdjustmentMask {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalAdjustmentMask(
            id: id,
            name: trimmedName.isEmpty ? kind.name : trimmedName,
            kind: kind,
            centerX: centerX,
            centerY: centerY,
            size: size,
            feather: feather,
            angle: angle,
            inverted: inverted,
            flow: flow,
            strokes: strokes,
            rasterMaskData: rasterMaskData,
            primaryOperations: primaryOperations,
            rangeOperations: rangeOperations,
            pointColors: pointColors,
            adjustments: adjustments
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, centerX, centerY, size, feather, angle, inverted
        case flow, strokes, rasterMaskData, primaryOperations, rangeOperations
        case pointColors, adjustments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(LocalMaskKind.self, forKey: .kind) ?? .radial
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? kind.name,
            kind: kind,
            centerX: try container.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5,
            centerY: try container.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 0.55,
            feather: try container.decodeIfPresent(Double.self, forKey: .feather) ?? 0.5,
            angle: try container.decodeIfPresent(Double.self, forKey: .angle) ?? 0,
            inverted: try container.decodeIfPresent(Bool.self, forKey: .inverted) ?? false,
            flow: try container.decodeIfPresent(Double.self, forKey: .flow) ?? 1,
            strokes: try container.decodeIfPresent(
                [BrushStroke].self,
                forKey: .strokes
            ) ?? [],
            rasterMaskData: try container.decodeIfPresent(
                Data.self,
                forKey: .rasterMaskData
            ),
            primaryOperations: try container.decodeIfPresent(
                [MaskPrimaryOperation].self,
                forKey: .primaryOperations
            ) ?? [],
            rangeOperations: try container.decodeIfPresent(
                [MaskRangeOperation].self,
                forKey: .rangeOperations
            ) ?? [],
            pointColors: try container.decodeIfPresent(
                [PointColorAdjustment].self,
                forKey: .pointColors
            ) ?? [],
            adjustments: try container.decodeIfPresent(
                LocalToneAdjustments.self,
                forKey: .adjustments
            ) ?? LocalToneAdjustments(exposure: 0.5)
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped > 180 ? wrapped - 360 : (wrapped < -180 ? wrapped + 360 : wrapped)
    }
}
