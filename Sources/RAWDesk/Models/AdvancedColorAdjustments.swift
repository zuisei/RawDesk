import Foundation

public enum ToneCurveRegion: Int, CaseIterable, Identifiable, Sendable {
    case black
    case shadows
    case midtones
    case highlights
    case white

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .black: return "Black"
        case .shadows: return "Shadows"
        case .midtones: return "Midtones"
        case .highlights: return "Highlights"
        case .white: return "White"
        }
    }

    public var inputLevel: Double {
        switch self {
        case .black: return 0
        case .shadows: return 0.25
        case .midtones: return 0.5
        case .highlights: return 0.75
        case .white: return 1
        }
    }

    public var neutralOutput: Double { inputLevel }
}

/// Five-point RGB tone curve compatible with Core Image's tone-curve filter.
public struct ToneCurve: Codable, Equatable, Hashable, Sendable {
    public var black: Double
    public var shadows: Double
    public var midtones: Double
    public var highlights: Double
    public var white: Double

    public init(
        black: Double = 0,
        shadows: Double = 0.25,
        midtones: Double = 0.5,
        highlights: Double = 0.75,
        white: Double = 1
    ) {
        self.black = Self.clamp(black)
        self.shadows = Self.clamp(shadows)
        self.midtones = Self.clamp(midtones)
        self.highlights = Self.clamp(highlights)
        self.white = Self.clamp(white)
    }

    public static let neutral = ToneCurve()

    public var isNeutral: Bool { self == .neutral }

    public var editCount: Int {
        ToneCurveRegion.allCases.filter {
            abs(self[$0] - $0.neutralOutput) > 0.000_1
        }.count
    }

    public subscript(region: ToneCurveRegion) -> Double {
        get {
            switch region {
            case .black: return black
            case .shadows: return shadows
            case .midtones: return midtones
            case .highlights: return highlights
            case .white: return white
            }
        }
        set {
            let value = Self.clamp(newValue)
            switch region {
            case .black: black = value
            case .shadows: shadows = value
            case .midtones: midtones = value
            case .highlights: highlights = value
            case .white: white = value
            }
        }
    }

    public var normalized: ToneCurve {
        ToneCurve(
            black: black,
            shadows: shadows,
            midtones: midtones,
            highlights: highlights,
            white: white
        )
    }

    private enum CodingKeys: String, CodingKey {
        case black, shadows, midtones, highlights, white
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            black: try container.decodeIfPresent(Double.self, forKey: .black) ?? 0,
            shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0.25,
            midtones: try container.decodeIfPresent(Double.self, forKey: .midtones) ?? 0.5,
            highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0.75,
            white: try container.decodeIfPresent(Double.self, forKey: .white) ?? 1
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

public enum ColorMixerChannel: String, CaseIterable, Codable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case aqua
    case blue
    case purple
    case magenta

    public var id: String { rawValue }

    public var name: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Center hue in the unit interval used to build a smooth color LUT.
    var centerHue: Double {
        switch self {
        case .red: return 0
        case .orange: return 30 / 360
        case .yellow: return 60 / 360
        case .green: return 120 / 360
        case .aqua: return 180 / 360
        case .blue: return 240 / 360
        case .purple: return 280 / 360
        case .magenta: return 320 / 360
        }
    }
}

public struct HSLChannelAdjustment: Codable, Equatable, Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var luminance: Double

    public init(
        hue: Double = 0,
        saturation: Double = 0,
        luminance: Double = 0
    ) {
        self.hue = Self.clamp(hue)
        self.saturation = Self.clamp(saturation)
        self.luminance = Self.clamp(luminance)
    }

    public static let neutral = HSLChannelAdjustment()

    public var isNeutral: Bool {
        abs(hue) <= 0.000_1
            && abs(saturation) <= 0.000_1
            && abs(luminance) <= 0.000_1
    }

    public var editCount: Int {
        [hue, saturation, luminance].filter { abs($0) > 0.000_1 }.count
    }

    public var normalized: HSLChannelAdjustment {
        HSLChannelAdjustment(
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
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            luminance: try container.decodeIfPresent(Double.self, forKey: .luminance) ?? 0
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(-100, value.isFinite ? value : 0))
    }
}

/// Lightroom-style eight-channel hue, saturation, and luminance mixer.
public struct ColorMixer: Codable, Equatable, Hashable, Sendable {
    public var red: HSLChannelAdjustment
    public var orange: HSLChannelAdjustment
    public var yellow: HSLChannelAdjustment
    public var green: HSLChannelAdjustment
    public var aqua: HSLChannelAdjustment
    public var blue: HSLChannelAdjustment
    public var purple: HSLChannelAdjustment
    public var magenta: HSLChannelAdjustment

    public init(
        red: HSLChannelAdjustment = .neutral,
        orange: HSLChannelAdjustment = .neutral,
        yellow: HSLChannelAdjustment = .neutral,
        green: HSLChannelAdjustment = .neutral,
        aqua: HSLChannelAdjustment = .neutral,
        blue: HSLChannelAdjustment = .neutral,
        purple: HSLChannelAdjustment = .neutral,
        magenta: HSLChannelAdjustment = .neutral
    ) {
        self.red = red.normalized
        self.orange = orange.normalized
        self.yellow = yellow.normalized
        self.green = green.normalized
        self.aqua = aqua.normalized
        self.blue = blue.normalized
        self.purple = purple.normalized
        self.magenta = magenta.normalized
    }

    public static let neutral = ColorMixer()

    public var isNeutral: Bool {
        ColorMixerChannel.allCases.allSatisfy { self[$0].isNeutral }
    }

    public var editCount: Int {
        ColorMixerChannel.allCases.reduce(0) { $0 + self[$1].editCount }
    }

    public subscript(channel: ColorMixerChannel) -> HSLChannelAdjustment {
        get {
            switch channel {
            case .red: return red
            case .orange: return orange
            case .yellow: return yellow
            case .green: return green
            case .aqua: return aqua
            case .blue: return blue
            case .purple: return purple
            case .magenta: return magenta
            }
        }
        set {
            let value = newValue.normalized
            switch channel {
            case .red: red = value
            case .orange: orange = value
            case .yellow: yellow = value
            case .green: green = value
            case .aqua: aqua = value
            case .blue: blue = value
            case .purple: purple = value
            case .magenta: magenta = value
            }
        }
    }

    public var normalized: ColorMixer {
        ColorMixer(
            red: red,
            orange: orange,
            yellow: yellow,
            green: green,
            aqua: aqua,
            blue: blue,
            purple: purple,
            magenta: magenta
        )
    }

    private enum CodingKeys: String, CodingKey {
        case red, orange, yellow, green, aqua, blue, purple, magenta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .red) ?? .neutral,
            orange: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .orange) ?? .neutral,
            yellow: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .yellow) ?? .neutral,
            green: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .green) ?? .neutral,
            aqua: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .aqua) ?? .neutral,
            blue: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .blue) ?? .neutral,
            purple: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .purple) ?? .neutral,
            magenta: try container.decodeIfPresent(HSLChannelAdjustment.self, forKey: .magenta) ?? .neutral
        )
    }
}

public enum ColorGradingRegion: String, CaseIterable, Codable, Identifiable, Sendable {
    case shadows
    case midtones
    case highlights
    case global

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .shadows: return "Shadows"
        case .midtones: return "Midtones"
        case .highlights: return "Highlights"
        case .global: return "Global"
        }
    }
}

public struct ColorGradingWheel: Codable, Equatable, Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var luminance: Double

    public init(
        hue: Double = 0,
        saturation: Double = 0,
        luminance: Double = 0
    ) {
        self.hue = Self.normalizedHue(hue)
        self.saturation = Self.clamp(saturation, to: 0...100)
        self.luminance = Self.clamp(luminance, to: -100...100)
    }

    public static let neutral = ColorGradingWheel()

    /// Hue has no visual effect until saturation is above zero.
    public var isNeutral: Bool {
        saturation <= 0.000_1 && abs(luminance) <= 0.000_1
    }

    public var editCount: Int {
        (saturation > 0.000_1 ? 1 : 0)
            + (abs(luminance) > 0.000_1 ? 1 : 0)
    }

    public var normalized: ColorGradingWheel {
        ColorGradingWheel(
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
            saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
            luminance: try container.decodeIfPresent(Double.self, forKey: .luminance) ?? 0
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

/// Three-way color grading plus a global wheel, blending, and tonal balance.
public struct ColorGrading: Codable, Equatable, Hashable, Sendable {
    public var shadows: ColorGradingWheel
    public var midtones: ColorGradingWheel
    public var highlights: ColorGradingWheel
    public var global: ColorGradingWheel
    public var blending: Double
    public var balance: Double

    public init(
        shadows: ColorGradingWheel = .neutral,
        midtones: ColorGradingWheel = .neutral,
        highlights: ColorGradingWheel = .neutral,
        global: ColorGradingWheel = .neutral,
        blending: Double = 50,
        balance: Double = 0
    ) {
        self.shadows = shadows.normalized
        self.midtones = midtones.normalized
        self.highlights = highlights.normalized
        self.global = global.normalized
        self.blending = Self.clamp(blending, to: 0...100, fallback: 50)
        self.balance = Self.clamp(balance, to: -100...100, fallback: 0)
    }

    public static let neutral = ColorGrading()

    public subscript(region: ColorGradingRegion) -> ColorGradingWheel {
        get {
            switch region {
            case .shadows: return shadows
            case .midtones: return midtones
            case .highlights: return highlights
            case .global: return global
            }
        }
        set {
            let value = newValue.normalized
            switch region {
            case .shadows: shadows = value
            case .midtones: midtones = value
            case .highlights: highlights = value
            case .global: global = value
            }
        }
    }

    public var isNeutral: Bool { editCount == 0 }

    public var editCount: Int {
        ColorGradingRegion.allCases.reduce(0) { $0 + self[$1].editCount }
            + (abs(blending - 50) > 0.000_1 ? 1 : 0)
            + (abs(balance) > 0.000_1 ? 1 : 0)
    }

    public var normalized: ColorGrading {
        ColorGrading(
            shadows: shadows,
            midtones: midtones,
            highlights: highlights,
            global: global,
            blending: blending,
            balance: balance
        )
    }

    private enum CodingKeys: String, CodingKey {
        case shadows, midtones, highlights, global, blending, balance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shadows: try container.decodeIfPresent(
                ColorGradingWheel.self,
                forKey: .shadows
            ) ?? .neutral,
            midtones: try container.decodeIfPresent(
                ColorGradingWheel.self,
                forKey: .midtones
            ) ?? .neutral,
            highlights: try container.decodeIfPresent(
                ColorGradingWheel.self,
                forKey: .highlights
            ) ?? .neutral,
            global: try container.decodeIfPresent(
                ColorGradingWheel.self,
                forKey: .global
            ) ?? .neutral,
            blending: try container.decodeIfPresent(Double.self, forKey: .blending) ?? 50,
            balance: try container.decodeIfPresent(Double.self, forKey: .balance) ?? 0
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }
}

/// Camera-calibration-style controls applied before the creative color tools.
///
/// Primary controls are deliberately broad: they tune the interpretation of
/// red, green, and blue color families rather than replacing the eight-channel
/// Color Mixer or Point Color tools.
public struct CalibrationAdjustments: Codable, Equatable, Hashable, Sendable {
    public var shadowsTint: Double
    public var redPrimaryHue: Double
    public var redPrimarySaturation: Double
    public var greenPrimaryHue: Double
    public var greenPrimarySaturation: Double
    public var bluePrimaryHue: Double
    public var bluePrimarySaturation: Double

    public init(
        shadowsTint: Double = 0,
        redPrimaryHue: Double = 0,
        redPrimarySaturation: Double = 0,
        greenPrimaryHue: Double = 0,
        greenPrimarySaturation: Double = 0,
        bluePrimaryHue: Double = 0,
        bluePrimarySaturation: Double = 0
    ) {
        self.shadowsTint = Self.clamp(shadowsTint)
        self.redPrimaryHue = Self.clamp(redPrimaryHue)
        self.redPrimarySaturation = Self.clamp(redPrimarySaturation)
        self.greenPrimaryHue = Self.clamp(greenPrimaryHue)
        self.greenPrimarySaturation = Self.clamp(greenPrimarySaturation)
        self.bluePrimaryHue = Self.clamp(bluePrimaryHue)
        self.bluePrimarySaturation = Self.clamp(bluePrimarySaturation)
    }

    public static let neutral = CalibrationAdjustments()

    public var isNeutral: Bool { editCount == 0 }

    public var editCount: Int {
        [
            shadowsTint,
            redPrimaryHue,
            redPrimarySaturation,
            greenPrimaryHue,
            greenPrimarySaturation,
            bluePrimaryHue,
            bluePrimarySaturation,
        ].filter { abs($0) > 0.000_1 }.count
    }

    public var normalized: CalibrationAdjustments {
        CalibrationAdjustments(
            shadowsTint: shadowsTint,
            redPrimaryHue: redPrimaryHue,
            redPrimarySaturation: redPrimarySaturation,
            greenPrimaryHue: greenPrimaryHue,
            greenPrimarySaturation: greenPrimarySaturation,
            bluePrimaryHue: bluePrimaryHue,
            bluePrimarySaturation: bluePrimarySaturation
        )
    }

    private enum CodingKeys: String, CodingKey {
        case shadowsTint
        case redPrimaryHue, redPrimarySaturation
        case greenPrimaryHue, greenPrimarySaturation
        case bluePrimaryHue, bluePrimarySaturation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shadowsTint: try container.decodeIfPresent(
                Double.self,
                forKey: .shadowsTint
            ) ?? 0,
            redPrimaryHue: try container.decodeIfPresent(
                Double.self,
                forKey: .redPrimaryHue
            ) ?? 0,
            redPrimarySaturation: try container.decodeIfPresent(
                Double.self,
                forKey: .redPrimarySaturation
            ) ?? 0,
            greenPrimaryHue: try container.decodeIfPresent(
                Double.self,
                forKey: .greenPrimaryHue
            ) ?? 0,
            greenPrimarySaturation: try container.decodeIfPresent(
                Double.self,
                forKey: .greenPrimarySaturation
            ) ?? 0,
            bluePrimaryHue: try container.decodeIfPresent(
                Double.self,
                forKey: .bluePrimaryHue
            ) ?? 0,
            bluePrimarySaturation: try container.decodeIfPresent(
                Double.self,
                forKey: .bluePrimarySaturation
            ) ?? 0
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(-100, value.isFinite ? value : 0))
    }
}
