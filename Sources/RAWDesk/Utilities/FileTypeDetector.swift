import Foundation

public enum FileTypeDetector {

    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "tif", "tiff",
        "arw", "cr2", "dng", "cr3", "nef", "raf", "rw2", "orf"
    ]

    public static func format(forExtension ext: String) -> FileFormat {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "tif", "tiff": return .tiff
        case "arw": return .sonyARW
        case "cr2": return .canonCR2
        case "cr3": return .canonCR3
        case "dng": return .dng
        case "nef": return .nikonNEF
        case "raf": return .fujiRAF
        case "rw2": return .panasonicRW2
        case "orf": return .olympusORF
        default: return .unsupported
        }
    }

    public static func isSupported(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
