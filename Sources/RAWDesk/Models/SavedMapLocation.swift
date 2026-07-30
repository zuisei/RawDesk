import Foundation
import CoreLocation

public struct SavedMapLocation:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    public var id: UUID
    public var name: String
    public var folder: String
    public var center: PhotoLocation
    public var radiusMeters: Double
    public var isPrivate: Bool
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        folder: String = "My Locations",
        center: PhotoLocation,
        radiusMeters: Double = 500,
        isPrivate: Bool = false,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.folder = Self.normalizedFolder(folder)
        self.center = center
        self.radiusMeters = max(
            10,
            min(2_000_000, radiusMeters)
        )
        self.isPrivate = isPrivate
        self.isVisible = isVisible
    }

    public var validationMessage: String? {
        if name.isEmpty {
            return "Enter a saved-location name."
        }
        if folder.isEmpty {
            return "Enter a folder name."
        }
        if !radiusMeters.isFinite
            || !(10...2_000_000).contains(radiusMeters) {
            return "Radius must be between 10 m and 2,000 km."
        }
        return nil
    }

    public func contains(_ location: PhotoLocation) -> Bool {
        let centerLocation = CLLocation(
            latitude: center.latitude,
            longitude: center.longitude
        )
        let candidate = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        )
        return centerLocation.distance(from: candidate)
            <= radiusMeters
    }

    public static func normalizedName(_ value: String) -> String {
        normalized(value, limit: 80)
    }

    public static func normalizedFolder(_ value: String) -> String {
        let normalized = normalized(value, limit: 80)
        return normalized.isEmpty ? "My Locations" : normalized
    }

    private static func normalized(
        _ value: String,
        limit: Int
    ) -> String {
        String(
            value
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .precomposedStringWithCanonicalMapping
                .prefix(limit)
        )
    }
}

public struct SavedMapLocationLibrary:
    Codable,
    Equatable,
    Sendable
{
    public var locations: [SavedMapLocation]

    public init(locations: [SavedMapLocation] = []) {
        var seen: Set<UUID> = []
        self.locations = locations
            .filter {
                seen.insert($0.id).inserted
                    && $0.validationMessage == nil
            }
            .sorted {
                if $0.folder != $1.folder {
                    return $0.folder.localizedStandardCompare(
                        $1.folder
                    ) == .orderedAscending
                }
                return $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
    }
}

public struct MapFocusRequest:
    Identifiable,
    Equatable,
    Sendable
{
    public let id: UUID
    public var locationID: SavedMapLocation.ID

    public init(locationID: SavedMapLocation.ID) {
        id = UUID()
        self.locationID = locationID
    }
}
