import Foundation

/// A named mapping between RAWDesk's five stable label colors and the
/// human-readable values written to `xmp:Label`.
///
/// Keeping the color identity separate from its metadata name means a preset
/// can be renamed without making an already-organized catalog lose its color
/// filtering. The name captured when a label is assigned remains on that
/// photo until the user explicitly assigns or clears the label again.
public struct PhotoColorLabelSet:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public static let standardID = UUID(
        uuidString: "52415744-4553-4B4C-4142-454C53455431"
    )!

    public var id: UUID
    public var name: String
    public var red: String
    public var yellow: String
    public var green: String
    public var blue: String
    public var purple: String

    public init(
        id: UUID = UUID(),
        name: String,
        red: String = "Red",
        yellow: String = "Yellow",
        green: String = "Green",
        blue: String = "Blue",
        purple: String = "Purple"
    ) {
        self.id = id
        self.name = Self.normalizedText(name, maximumLength: 80)
        self.red = Self.normalizedText(red, maximumLength: 64)
        self.yellow = Self.normalizedText(yellow, maximumLength: 64)
        self.green = Self.normalizedText(green, maximumLength: 64)
        self.blue = Self.normalizedText(blue, maximumLength: 64)
        self.purple = Self.normalizedText(purple, maximumLength: 64)
    }

    public static let standard = PhotoColorLabelSet(
        id: standardID,
        name: "Color"
    )

    public var normalized: PhotoColorLabelSet {
        PhotoColorLabelSet(
            id: id,
            name: name,
            red: red,
            yellow: yellow,
            green: green,
            blue: blue,
            purple: purple
        )
    }

    public subscript(label: PhotoColorLabel) -> String {
        get {
            switch label {
            case .none: return "Unlabeled"
            case .red: return red
            case .yellow: return yellow
            case .green: return green
            case .blue: return blue
            case .purple: return purple
            }
        }
        set {
            // Preserve in-progress whitespace while a TextField is being
            // edited. The complete preset is normalized atomically on save.
            let edited = String(newValue.prefix(64))
            switch label {
            case .none: break
            case .red: red = edited
            case .yellow: yellow = edited
            case .green: green = edited
            case .blue: blue = edited
            case .purple: purple = edited
            }
        }
    }

    public var validationMessage: String? {
        let normalized = normalized
        if normalized.name.isEmpty {
            return "Enter a preset name."
        }
        let namedLabels = PhotoColorLabel.allCases.dropFirst().map {
            normalized[$0]
        }
        if namedLabels.contains(where: \.isEmpty) {
            return "Every color needs a label name."
        }
        let folded = namedLabels.map(Self.comparisonKey)
        if Set(folded).count != folded.count {
            return "Each color needs a unique label name."
        }
        return nil
    }

    public func color(
        matchingMetadataValue value: String
    ) -> PhotoColorLabel? {
        let comparison = Self.comparisonKey(value)
        guard !comparison.isEmpty else { return nil }
        return PhotoColorLabel.allCases.dropFirst().first {
            Self.comparisonKey(self[$0]) == comparison
        }
    }

    public static func normalizedMetadataValue(
        _ value: String?
    ) -> String? {
        guard let value else { return nil }
        let normalized = normalizedText(value, maximumLength: 64)
        return normalized.isEmpty ? nil : normalized
    }

    public static func comparisonKey(_ value: String) -> String {
        normalizedText(value, maximumLength: 64).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func normalizedText(
        _ value: String,
        maximumLength: Int
    ) -> String {
        String(
            value
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .precomposedStringWithCanonicalMapping
                .prefix(maximumLength)
        )
    }
}

public struct PhotoColorLabelSetLibrary:
    Codable,
    Equatable,
    Sendable
{
    public var activeSetID: PhotoColorLabelSet.ID
    public var sets: [PhotoColorLabelSet]

    public init(
        activeSetID: PhotoColorLabelSet.ID =
            PhotoColorLabelSet.standardID,
        sets: [PhotoColorLabelSet] = [.standard]
    ) {
        var seen: Set<PhotoColorLabelSet.ID> = []
        let unique = sets.filter { seen.insert($0.id).inserted }
        self.sets = unique.isEmpty ? [.standard] : unique
        self.activeSetID = self.sets.contains {
            $0.id == activeSetID
        } ? activeSetID : self.sets[0].id
    }

    public var activeSet: PhotoColorLabelSet {
        sets.first { $0.id == activeSetID }
            ?? sets.first
            ?? .standard
    }
}
