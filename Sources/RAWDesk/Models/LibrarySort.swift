import Foundation

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case captureDate
    case filename
    case rating
    case fileSize
    case format

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .captureDate: return "Date"
        case .filename: return "Filename"
        case .rating: return "Rating"
        case .fileSize: return "File Size"
        case .format: return "Format"
        }
    }

    public func sorted(_ assets: [PhotoAsset], ascending: Bool) -> [PhotoAsset] {
        assets.sorted { lhs, rhs in
            ascending ? isOrdered(lhs, before: rhs) : isOrdered(rhs, before: lhs)
        }
    }

    private func isOrdered(_ lhs: PhotoAsset, before rhs: PhotoAsset) -> Bool {
        switch self {
        case .captureDate:
            let left = lhs.metadata?.captureDate
                ?? lhs.creationDate
                ?? lhs.modificationDate
                ?? .distantPast
            let right = rhs.metadata?.captureDate
                ?? rhs.creationDate
                ?? rhs.modificationDate
                ?? .distantPast
            return left == right
                ? lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
                : left < right
        case .filename:
            return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
        case .rating:
            return lhs.userState.rating == rhs.userState.rating
                ? lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
                : lhs.userState.rating < rhs.userState.rating
        case .fileSize:
            return lhs.fileSize == rhs.fileSize
                ? lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
                : lhs.fileSize < rhs.fileSize
        case .format:
            return lhs.format.displayName == rhs.format.displayName
                ? lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
                : lhs.format.displayName.localizedStandardCompare(rhs.format.displayName)
                    == .orderedAscending
        }
    }
}
