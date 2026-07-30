import Foundation

/// A profile is a rendering foundation, not a preset.
///
/// Selecting one never rewrites the Light, Color, Curve, or other editing
/// controls. The profile is evaluated near the start of the development
/// pipeline so every later adjustment remains independently editable.
public enum DevelopmentProfileGroup: String, CaseIterable, Identifiable, Sendable {
    case foundation
    case creative
    case monochrome

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .foundation: return "Foundation"
        case .creative: return "Creative"
        case .monochrome: return "Black & White"
        }
    }
}

public enum DevelopmentProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case cameraDefault
    case rawDeskColor
    case neutral
    case vivid
    case landscape
    case portrait
    case modernCool
    case cinematicTeal
    case vintageWarm
    case monochrome
    case monochromePunch

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .cameraDefault: return "Camera Default"
        case .rawDeskColor: return "RAWDesk Color"
        case .neutral: return "RAWDesk Neutral"
        case .vivid: return "RAWDesk Vivid"
        case .landscape: return "RAWDesk Landscape"
        case .portrait: return "RAWDesk Portrait"
        case .modernCool: return "Modern Cool"
        case .cinematicTeal: return "Cinematic Teal"
        case .vintageWarm: return "Vintage Warm"
        case .monochrome: return "Monochrome"
        case .monochromePunch: return "Monochrome Punch"
        }
    }

    public var group: DevelopmentProfileGroup {
        switch self {
        case .cameraDefault, .rawDeskColor, .neutral, .vivid,
             .landscape, .portrait:
            return .foundation
        case .modernCool, .cinematicTeal, .vintageWarm:
            return .creative
        case .monochrome, .monochromePunch:
            return .monochrome
        }
    }

    public var systemImage: String {
        switch self {
        case .cameraDefault: return "camera.aperture"
        case .rawDeskColor: return "circle.hexagongrid.fill"
        case .neutral: return "circle.dashed"
        case .vivid: return "paintpalette.fill"
        case .landscape: return "mountain.2.fill"
        case .portrait: return "person.crop.rectangle"
        case .modernCool: return "snowflake"
        case .cinematicTeal: return "film.stack"
        case .vintageWarm: return "sun.haze.fill"
        case .monochrome: return "circle.lefthalf.filled"
        case .monochromePunch: return "circle.righthalf.filled"
        }
    }

    public var summary: String {
        switch self {
        case .cameraDefault:
            return "Preserves the color rendering supplied by the macOS camera decoder."
        case .rawDeskColor:
            return "Balanced color and gentle contrast for a natural starting point."
        case .neutral:
            return "Restrained contrast and saturation with extra editing latitude."
        case .vivid:
            return "Stronger color separation and contrast without shifting neutrals."
        case .landscape:
            return "Richer blue and green separation with protected highlights."
        case .portrait:
            return "Gentler contrast with protected skin hues and warm highlights."
        case .modernCool:
            return "Clean shadows, cool neutrals, and crisp restrained color."
        case .cinematicTeal:
            return "Cool shadows and warm highlights with a filmic contrast curve."
        case .vintageWarm:
            return "Warm highlights, softened blacks, and slightly muted color."
        case .monochrome:
            return "Balanced luminance-based black and white conversion."
        case .monochromePunch:
            return "High-contrast black and white with stronger red-channel weight."
        }
    }

    public var isMonochrome: Bool {
        group == .monochrome
    }
}

public struct DevelopmentProfileSettings: Codable, Equatable, Hashable, Sendable {
    public var profile: DevelopmentProfile
    public var amount: Double

    public init(
        profile: DevelopmentProfile = .cameraDefault,
        amount: Double = 100
    ) {
        self.profile = profile
        let finiteAmount = amount.isFinite ? amount : 100
        self.amount = min(200, max(0, finiteAmount))
        if profile == .cameraDefault {
            self.amount = 100
        }
    }

    public static let cameraDefault = DevelopmentProfileSettings()

    public var normalized: DevelopmentProfileSettings {
        DevelopmentProfileSettings(profile: profile, amount: amount)
    }

    /// Camera Default is the pre-existing decoder rendering and therefore does
    /// not count as an edit. A selected profile remains an intentional state
    /// even when Amount is zero.
    public var editCount: Int {
        profile == .cameraDefault ? 0 : 1
    }

    public var isDefault: Bool {
        profile == .cameraDefault
    }

    public var isEffective: Bool {
        profile != .cameraDefault && amount > 0.000_1
    }
}
