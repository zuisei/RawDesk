import Foundation

public enum LibraryFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case all
    case rawOnly
    case sonyARWOnly
    case canonCR2Only
    case favoritesOnly
    case flaggedOnly
    case rejectedOnly
    case errorsOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "All"
        case .rawOnly: return "RAW Only"
        case .sonyARWOnly: return "Sony ARW Only"
        case .canonCR2Only: return "Canon CR2 Only"
        case .favoritesOnly: return "Favorites"
        // "Picked" everywhere: the pick status, the sidebar collection, the
        // cell badge and the inspector all call this state Picked, so the
        // filter must not introduce a second name for it.
        case .flaggedOnly: return "Picked"
        case .rejectedOnly: return "Rejected"
        case .errorsOnly: return "Loading Errors"
        }
    }
}

public struct FilterState: Codable, Equatable, Sendable {
    public var searchText: String
    public var primary: LibraryFilter
    public var minimumRating: Int          // 0 = no rating filter
    public var keyword: String?
    public var colorLabels: Set<PhotoColorLabel>

    public init(
        searchText: String = "",
        primary: LibraryFilter = .all,
        minimumRating: Int = 0,
        keyword: String? = nil,
        colorLabels: Set<PhotoColorLabel> = []
    ) {
        self.searchText = searchText
        self.primary = primary
        self.minimumRating = max(0, min(5, minimumRating))
        let trimmedKeyword = keyword?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.keyword = trimmedKeyword?.isEmpty == false
            ? trimmedKeyword
            : nil
        self.colorLabels = colorLabels
    }

    public var isActive: Bool {
        !searchText.isEmpty
            || primary != .all
            || minimumRating > 0
            || keyword != nil
            || !colorLabels.isEmpty
    }

    public var hasFacetFilters: Bool {
        primary != .all
            || minimumRating > 0
            || keyword != nil
            || !colorLabels.isEmpty
    }

    public var activeFacetCount: Int {
        var count = 0
        if primary != .all { count += 1 }
        if minimumRating > 0 { count += 1 }
        if keyword != nil { count += 1 }
        if !colorLabels.isEmpty { count += 1 }
        return count
    }

    public mutating func clearFacetFilters() {
        primary = .all
        minimumRating = 0
        keyword = nil
        colorLabels = []
    }

    public func matches(_ asset: PhotoAsset) -> Bool {
        if !searchText.isEmpty {
            let searchable = [
                asset.filename,
                asset.userState.note,
                asset.userState.keywords.flatMap {
                    PhotoUserState.keywordSegments(in: $0)
                }.joined(separator: " "),
                asset.metadata?.cameraMake ?? "",
                asset.metadata?.cameraModel ?? "",
                asset.metadata?.lensModel ?? "",
            ].joined(separator: " ")
            if !searchable.localizedCaseInsensitiveContains(searchText) {
                return false
            }
        }
        if let keyword,
           !asset.userState.keywords.contains(where: {
               PhotoUserState.keyword($0, matches: keyword)
           }) {
            return false
        }
        if !colorLabels.isEmpty,
           !colorLabels.contains(asset.userState.colorLabel) {
            return false
        }
        switch primary {
        case .all: break
        case .rawOnly: if !asset.isRaw { return false }
        case .sonyARWOnly: if !asset.isSonyARW { return false }
        case .canonCR2Only: if !asset.isCanonCR2 { return false }
        case .favoritesOnly: if !asset.userState.favorite { return false }
        case .flaggedOnly: if !asset.userState.flagged { return false }
        case .rejectedOnly: if !asset.userState.rejected { return false }
        case .errorsOnly:
            switch asset.loadState {
            case .failed, .unsupported: break
            default: return false
            }
        }
        if minimumRating > 0, asset.userState.rating < minimumRating { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case searchText, primary, minimumRating, keyword, colorLabels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            searchText: try container.decodeIfPresent(
                String.self,
                forKey: .searchText
            ) ?? "",
            primary: try container.decodeIfPresent(
                LibraryFilter.self,
                forKey: .primary
            ) ?? .all,
            minimumRating: try container.decodeIfPresent(
                Int.self,
                forKey: .minimumRating
            ) ?? 0,
            keyword: try container.decodeIfPresent(
                String.self,
                forKey: .keyword
            ),
            colorLabels: try container.decodeIfPresent(
                Set<PhotoColorLabel>.self,
                forKey: .colorLabels
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchText, forKey: .searchText)
        try container.encode(primary, forKey: .primary)
        try container.encode(minimumRating, forKey: .minimumRating)
        try container.encodeIfPresent(keyword, forKey: .keyword)
        try container.encode(colorLabels, forKey: .colorLabels)
    }
}
