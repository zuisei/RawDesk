import Foundation

public enum DevelopmentPreset:
    String, CaseIterable, Codable, Identifiable, Sendable {
    case clean
    case vivid
    case portrait
    case dramatic
    case matte

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .clean: return "Clean"
        case .vivid: return "Vivid"
        case .portrait: return "Portrait"
        case .dramatic: return "Dramatic"
        case .matte: return "Matte"
        }
    }

    public var systemImage: String {
        switch self {
        case .clean: return "sparkles"
        case .vivid: return "paintpalette.fill"
        case .portrait: return "person.crop.rectangle"
        case .dramatic: return "circle.lefthalf.filled"
        case .matte: return "film"
        }
    }

    public var adjustments: PhotoAdjustments {
        switch self {
        case .clean:
            return PhotoAdjustments(
                contrast: 6,
                highlights: -18,
                shadows: 16,
                whites: 8,
                blacks: -6,
                vibrance: 8,
                clarity: 5,
                sharpening: 18,
                noiseReduction: 5
            )
        case .vivid:
            return PhotoAdjustments(
                contrast: 14,
                highlights: -12,
                shadows: 10,
                whites: 10,
                blacks: -12,
                vibrance: 28,
                saturation: 6,
                clarity: 12,
                dehaze: 6,
                sharpening: 22
            )
        case .portrait:
            return PhotoAdjustments(
                contrast: -4,
                highlights: -24,
                shadows: 20,
                whites: 4,
                blacks: 4,
                temperature: 5,
                vibrance: 10,
                clarity: -10,
                sharpening: 10,
                noiseReduction: 12
            )
        case .dramatic:
            return PhotoAdjustments(
                contrast: 30,
                highlights: -30,
                shadows: 18,
                whites: 18,
                blacks: -26,
                vibrance: 12,
                clarity: 28,
                dehaze: 18,
                vignette: -18,
                sharpening: 25
            )
        case .matte:
            return PhotoAdjustments(
                contrast: -8,
                highlights: -18,
                shadows: 24,
                whites: -10,
                blacks: 18,
                temperature: 3,
                vibrance: -8,
                saturation: -6,
                clarity: -4,
                vignette: -8,
                sharpening: 8
            )
        }
    }
}
