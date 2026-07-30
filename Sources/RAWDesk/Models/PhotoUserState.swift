import Foundation

public enum PhotoPickStatus: Int, CaseIterable, Codable, Identifiable, Sendable {
    case rejected = -1
    case unflagged = 0
    case picked = 1

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .rejected: return "Rejected"
        case .unflagged: return "Unflagged"
        case .picked: return "Picked"
        }
    }
}

public enum PhotoColorLabel:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case none = ""
    case red
    case yellow
    case green
    case blue
    case purple

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .none: return "None"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }

    public var filterName: String {
        self == .none ? "Unlabeled" : name
    }

    public var xmpValue: String? {
        self == .none ? nil : name
    }

    public init?(xmpValue: String) {
        let normalized = xmpValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else {
            self = .none
            return
        }
        guard let match = Self.allCases.dropFirst().first(where: {
            $0.name.compare(
                normalized,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ) == .orderedSame
        }) else {
            return nil
        }
        self = match
    }
}

public struct PhotoUserState: Codable, Equatable, Sendable {
    public static let keywordPathSeparator = "|"

    public var rating: Int       // 0...5
    public var flagged: Bool
    public var rejected: Bool
    public var favorite: Bool
    public var colorLabel: PhotoColorLabel
    public var colorLabelMetadataValue: String?
    public var note: String
    public var keywords: [String]
    public var locationOverride: PhotoLocation?
    public var locationIsRemoved: Bool
    public var adjustments: PhotoAdjustments
    public var versions: [EditVersion]

    public init(
        rating: Int = 0,
        flagged: Bool = false,
        rejected: Bool = false,
        favorite: Bool = false,
        colorLabel: PhotoColorLabel = .none,
        colorLabelMetadataValue: String? = nil,
        note: String = "",
        keywords: [String] = [],
        locationOverride: PhotoLocation? = nil,
        locationIsRemoved: Bool = false,
        adjustments: PhotoAdjustments = .neutral,
        versions: [EditVersion] = []
    ) {
        self.rating = max(0, min(5, rating))
        self.flagged = rejected ? false : flagged
        self.rejected = rejected
        self.favorite = favorite
        self.colorLabel = colorLabel
        self.colorLabelMetadataValue =
            PhotoColorLabelSet.normalizedMetadataValue(
                colorLabelMetadataValue
            ) ?? (colorLabel == .none ? nil : colorLabel.name)
        self.note = note
        self.keywords = Self.normalizedKeywords(keywords)
        self.locationOverride =
            locationIsRemoved ? nil : locationOverride
        self.locationIsRemoved = locationIsRemoved
        self.adjustments = adjustments.normalized
        self.versions = Array(versions.suffix(50))
    }

    public static let empty = PhotoUserState()

    public func effectiveLocation(
        embedded: PhotoLocation?
    ) -> PhotoLocation? {
        guard !locationIsRemoved else { return nil }
        return locationOverride ?? embedded
    }

    public func locationSource(
        embedded: PhotoLocation?
    ) -> PhotoLocationSource {
        if locationIsRemoved { return .removed }
        if locationOverride != nil { return .manual }
        return embedded == nil ? .none : .embedded
    }

    public mutating func setLocation(
        _ location: PhotoLocation
    ) {
        locationOverride = location
        locationIsRemoved = false
    }

    public mutating func removeLocation() {
        locationOverride = nil
        locationIsRemoved = true
    }

    public mutating func useEmbeddedLocation() {
        locationOverride = nil
        locationIsRemoved = false
    }

    public mutating func assignColorLabel(
        _ label: PhotoColorLabel,
        metadataValue: String? = nil
    ) {
        colorLabel = label
        colorLabelMetadataValue = label == .none
            ? nil
            : PhotoColorLabelSet.normalizedMetadataValue(
                metadataValue
            ) ?? label.name
    }

    public var pickStatus: PhotoPickStatus {
        get {
            if rejected { return .rejected }
            return flagged ? .picked : .unflagged
        }
        set {
            flagged = newValue == .picked
            rejected = newValue == .rejected
        }
    }

    public static func normalizedKeywords(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let segments = keywordSegments(in: value)
            guard !segments.isEmpty else { continue }
            let keyword = segments.joined(separator: keywordPathSeparator)
            let comparisonKey = foldedKeyword(keyword)
            guard seen.insert(comparisonKey).inserted else { continue }
            result.append(keyword)
            if result.count == 200 { break }
        }
        return result
    }

    public static func keywordSegments(in value: String) -> [String] {
        value
            .replacingOccurrences(of: "›", with: keywordPathSeparator)
            .replacingOccurrences(of: ">", with: keywordPathSeparator)
            .replacingOccurrences(of: "＞", with: keywordPathSeparator)
            .components(separatedBy: keywordPathSeparator)
            .compactMap { rawSegment in
                let collapsed = rawSegment
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .precomposedStringWithCanonicalMapping
                guard !collapsed.isEmpty else { return nil }
                return String(collapsed.prefix(64))
            }
            .prefix(16)
            .map { $0 }
    }

    public static func keywordLeaf(_ keyword: String) -> String {
        keywordSegments(in: keyword).last ?? ""
    }

    public static func displayKeywordPath(_ keyword: String) -> String {
        keywordSegments(in: keyword).joined(separator: " › ")
    }

    public static func normalizedKeywordPath(_ value: String) -> String? {
        normalizedKeywords([value]).first
    }

    public static func keywordPath(
        _ candidate: String,
        isEqualToOrDescendantOf sourcePath: String
    ) -> Bool {
        guard let candidate = normalizedKeywordPath(candidate),
              let sourcePath = normalizedKeywordPath(sourcePath) else {
            return false
        }
        let candidateFolded = foldedKeyword(candidate)
        let sourceFolded = foldedKeyword(sourcePath)
        return candidateFolded == sourceFolded
            || candidateFolded.hasPrefix(
                sourceFolded + keywordPathSeparator
            )
    }

    public static func replacingKeywordBranch(
        in candidate: String,
        sourcePath: String,
        destinationPath: String?
    ) -> String? {
        guard keywordPath(
            candidate,
            isEqualToOrDescendantOf: sourcePath
        ) else {
            return normalizedKeywordPath(candidate)
        }
        guard let destinationPath,
              let normalizedDestination = normalizedKeywordPath(
                  destinationPath
              ) else {
            return nil
        }
        let sourceSegments = keywordSegments(in: sourcePath)
        let candidateSegments = keywordSegments(in: candidate)
        let destinationSegments = keywordSegments(
            in: normalizedDestination
        )
        return (destinationSegments + candidateSegments.dropFirst(
            sourceSegments.count
        )).joined(separator: keywordPathSeparator)
    }

    public static func flatKeywords(
        from keywords: [String]
    ) -> [String] {
        normalizedKeywords(keywords.map(keywordLeaf))
    }

    public static func normalizedKeywordSynonyms(
        _ values: [String]
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let segments = keywordSegments(in: value)
            guard segments.count == 1 else { continue }
            let synonym = segments[0]
            let comparisonKey = foldedKeyword(synonym)
            guard seen.insert(comparisonKey).inserted else { continue }
            result.append(synonym)
            if result.count == 50 { break }
        }
        return result
    }

    public static func mergedXMPKeywords(
        flat: [String],
        hierarchical: [String]
    ) -> [String] {
        let paths = normalizedKeywords(hierarchical)
        var representedLeaves = Set(
            paths.map { foldedKeyword(keywordLeaf($0)) }
        )
        var merged = paths
        for keyword in normalizedKeywords(flat) {
            let folded = foldedKeyword(keywordLeaf(keyword))
            guard representedLeaves.insert(folded).inserted else { continue }
            merged.append(keyword)
            if merged.count == 200 { break }
        }
        return normalizedKeywords(merged)
    }

    public static func keyword(
        _ candidate: String,
        matches filter: String
    ) -> Bool {
        guard let normalizedCandidate = normalizedKeywords([candidate]).first,
              let normalizedFilter = normalizedKeywords([filter]).first else {
            return false
        }
        let candidateFolded = foldedKeyword(normalizedCandidate)
        let filterFolded = foldedKeyword(normalizedFilter)
        if candidateFolded == filterFolded {
            return true
        }
        if candidateFolded.hasPrefix(
            filterFolded + keywordPathSeparator
        ) {
            return true
        }
        return foldedKeyword(keywordLeaf(normalizedCandidate))
            == filterFolded
    }

    public static func foldedKeyword(_ keyword: String) -> String {
        keyword.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private enum CodingKeys: String, CodingKey {
        case rating, flagged, rejected, favorite, colorLabel
        case colorLabelMetadataValue, note, keywords
        case locationOverride, locationIsRemoved
        case adjustments, versions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rating: try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0,
            flagged: try container.decodeIfPresent(Bool.self, forKey: .flagged) ?? false,
            rejected: try container.decodeIfPresent(Bool.self, forKey: .rejected) ?? false,
            favorite: try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false,
            colorLabel: try container.decodeIfPresent(
                PhotoColorLabel.self,
                forKey: .colorLabel
            ) ?? .none,
            colorLabelMetadataValue: try container.decodeIfPresent(
                String.self,
                forKey: .colorLabelMetadataValue
            ),
            note: try container.decodeIfPresent(String.self, forKey: .note) ?? "",
            keywords: try container.decodeIfPresent([String].self, forKey: .keywords) ?? [],
            locationOverride: try container.decodeIfPresent(
                PhotoLocation.self,
                forKey: .locationOverride
            ),
            locationIsRemoved: try container.decodeIfPresent(
                Bool.self,
                forKey: .locationIsRemoved
            ) ?? false,
            adjustments: try container.decodeIfPresent(PhotoAdjustments.self, forKey: .adjustments) ?? .neutral,
            versions: try container.decodeIfPresent([EditVersion].self, forKey: .versions) ?? []
        )
    }
}
