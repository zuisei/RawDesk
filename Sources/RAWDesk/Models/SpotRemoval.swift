import Foundation

public enum SpotRemovalKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case heal
    case clone

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .heal: return "Heal"
        case .clone: return "Clone"
        }
    }

    public var systemImage: String {
        switch self {
        case .heal: return "bandage"
        case .clone: return "circle.grid.cross"
        }
    }
}

/// A non-destructive circular repair. Coordinates are normalized from the
/// image's top-left after persisted orientation and before crop/straighten.
public struct SpotRemoval: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: SpotRemovalKind
    public var targetX: Double
    public var targetY: Double
    public var sourceX: Double
    public var sourceY: Double
    public var radius: Double
    public var feather: Double
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SpotRemovalKind = .heal,
        targetX: Double = 0.5,
        targetY: Double = 0.5,
        sourceX: Double = 0.36,
        sourceY: Double = 0.42,
        radius: Double = 0.06,
        feather: Double = 0.65,
        opacity: Double = 1
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.targetX = Self.clamp(targetX, to: 0...1)
        self.targetY = Self.clamp(targetY, to: 0...1)
        self.sourceX = Self.clamp(sourceX, to: 0...1)
        self.sourceY = Self.clamp(sourceY, to: 0...1)
        self.radius = Self.clamp(radius, to: 0.005...0.25)
        self.feather = Self.clamp(feather, to: 0...1)
        self.opacity = Self.clamp(opacity, to: 0...1)
    }

    public var normalized: SpotRemoval {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpotRemoval(
            id: id,
            name: trimmedName.isEmpty ? kind.name : trimmedName,
            kind: kind,
            targetX: targetX,
            targetY: targetY,
            sourceX: sourceX,
            sourceY: sourceY,
            radius: radius,
            feather: feather,
            opacity: opacity
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind
        case targetX, targetY, sourceX, sourceY
        case radius, feather, opacity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(SpotRemovalKind.self, forKey: .kind) ?? .heal
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? kind.name,
            kind: kind,
            targetX: try container.decodeIfPresent(Double.self, forKey: .targetX) ?? 0.5,
            targetY: try container.decodeIfPresent(Double.self, forKey: .targetY) ?? 0.5,
            sourceX: try container.decodeIfPresent(Double.self, forKey: .sourceX) ?? 0.36,
            sourceY: try container.decodeIfPresent(Double.self, forKey: .sourceY) ?? 0.42,
            radius: try container.decodeIfPresent(Double.self, forKey: .radius) ?? 0.06,
            feather: try container.decodeIfPresent(Double.self, forKey: .feather) ?? 0.65,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }
}
