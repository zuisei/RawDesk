import Foundation

/// A color sampled from the developed preview, represented in HSL.
public struct PointColorSample: Codable, Equatable, Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var luminance: Double

    public init(
        hue: Double,
        saturation: Double,
        luminance: Double
    ) {
        self.hue = Self.normalizedHue(hue)
        self.saturation = Self.clamp(saturation, to: 0...100)
        self.luminance = Self.clamp(luminance, to: 0...100)
    }

    public init(red: Double, green: Double, blue: Double) {
        let red = Self.clamp(red, to: 0...1)
        let green = Self.clamp(green, to: 0...1)
        let blue = Self.clamp(blue, to: 0...1)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let luminance = (maximum + minimum) / 2

        guard delta > 0.000_001 else {
            self.init(hue: 0, saturation: 0, luminance: luminance * 100)
            return
        }

        let saturation = delta / max(0.000_001, 1 - abs(2 * luminance - 1))
        let rawHue: Double
        if maximum == red {
            rawHue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            rawHue = (blue - red) / delta + 2
        } else {
            rawHue = (red - green) / delta + 4
        }
        self.init(
            hue: rawHue / 6 * 360,
            saturation: saturation * 100,
            luminance: luminance * 100
        )
    }

    public var normalized: PointColorSample {
        PointColorSample(
            hue: hue,
            saturation: saturation,
            luminance: luminance
        )
    }

    private enum CodingKeys: String, CodingKey {
        case hue, saturation, luminance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hue: try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0,
            saturation: try container.decodeIfPresent(
                Double.self,
                forKey: .saturation
            ) ?? 0,
            luminance: try container.decodeIfPresent(
                Double.self,
                forKey: .luminance
            ) ?? 50
        )
    }

    private static func normalizedHue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped >= 0 ? wrapped : wrapped + 360
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 0))
    }
}

/// A Lightroom-style Point Color swatch.
///
/// The sampled color and its ranges define selection only. The adjustment is
/// neutral until at least one shift or Variance is changed.
public struct PointColorAdjustment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var sample: PointColorSample
    public var hueShift: Double
    public var saturationShift: Double
    public var luminanceShift: Double
    public var variance: Double
    public var hueRange: Double
    public var saturationRange: Double
    public var luminanceRange: Double

    public init(
        id: UUID = UUID(),
        sample: PointColorSample,
        hueShift: Double = 0,
        saturationShift: Double = 0,
        luminanceShift: Double = 0,
        variance: Double = 0,
        hueRange: Double = 30,
        saturationRange: Double = 35,
        luminanceRange: Double = 35
    ) {
        self.id = id
        self.sample = sample.normalized
        self.hueShift = Self.clamp(hueShift, to: -100...100)
        self.saturationShift = Self.clamp(saturationShift, to: -100...100)
        self.luminanceShift = Self.clamp(luminanceShift, to: -100...100)
        self.variance = Self.clamp(variance, to: -100...100)
        self.hueRange = Self.clamp(hueRange, to: 1...180)
        self.saturationRange = Self.clamp(saturationRange, to: 1...100)
        self.luminanceRange = Self.clamp(luminanceRange, to: 1...100)
    }

    public var isEffective: Bool {
        abs(hueShift) > 0.000_1
            || abs(saturationShift) > 0.000_1
            || abs(luminanceShift) > 0.000_1
            || abs(variance) > 0.000_1
    }

    public var editCount: Int {
        [hueShift, saturationShift, luminanceShift, variance]
            .filter { abs($0) > 0.000_1 }
            .count
    }

    public var normalized: PointColorAdjustment {
        PointColorAdjustment(
            id: id,
            sample: sample,
            hueShift: hueShift,
            saturationShift: saturationShift,
            luminanceShift: luminanceShift,
            variance: variance,
            hueRange: hueRange,
            saturationRange: saturationRange,
            luminanceRange: luminanceRange
        )
    }

    public var hueFamilyName: String {
        let hue = sample.hue
        switch hue {
        case 15..<45: return "Orange"
        case 45..<75: return "Yellow"
        case 75..<165: return "Green"
        case 165..<205: return "Aqua"
        case 205..<265: return "Blue"
        case 265..<300: return "Purple"
        case 300..<345: return "Magenta"
        default: return sample.saturation < 5 ? "Neutral" : "Red"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, sample
        case hueShift, saturationShift, luminanceShift, variance
        case hueRange, saturationRange, luminanceRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            sample: try container.decodeIfPresent(
                PointColorSample.self,
                forKey: .sample
            ) ?? PointColorSample(hue: 0, saturation: 0, luminance: 50),
            hueShift: try container.decodeIfPresent(
                Double.self,
                forKey: .hueShift
            ) ?? 0,
            saturationShift: try container.decodeIfPresent(
                Double.self,
                forKey: .saturationShift
            ) ?? 0,
            luminanceShift: try container.decodeIfPresent(
                Double.self,
                forKey: .luminanceShift
            ) ?? 0,
            variance: try container.decodeIfPresent(Double.self, forKey: .variance) ?? 0,
            hueRange: try container.decodeIfPresent(Double.self, forKey: .hueRange) ?? 30,
            saturationRange: try container.decodeIfPresent(
                Double.self,
                forKey: .saturationRange
            ) ?? 35,
            luminanceRange: try container.decodeIfPresent(
                Double.self,
                forKey: .luminanceRange
            ) ?? 35
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 0))
    }
}
