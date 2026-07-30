import Foundation

public enum FileFormat: String, Codable, Sendable, CaseIterable {
    case jpeg
    case png
    case heic
    case tiff
    case sonyARW
    case canonCR2
    case canonCR3
    case dng
    case nikonNEF
    case fujiRAF
    case panasonicRW2
    case olympusORF
    case unknownRaw
    case unsupported

    public var isRaw: Bool {
        switch self {
        case .sonyARW, .canonCR2, .canonCR3, .dng,
             .nikonNEF, .fujiRAF, .panasonicRW2, .olympusORF, .unknownRaw:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .sonyARW: return "Sony ARW"
        case .canonCR2: return "Canon CR2"
        case .canonCR3: return "Canon CR3"
        case .dng: return "DNG"
        case .nikonNEF: return "Nikon NEF"
        case .fujiRAF: return "Fuji RAF"
        case .panasonicRW2: return "Panasonic RW2"
        case .olympusORF: return "Olympus ORF"
        case .unknownRaw: return "RAW"
        case .unsupported: return "Unsupported"
        }
    }
}
