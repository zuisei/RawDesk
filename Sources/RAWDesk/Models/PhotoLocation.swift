import Foundation
import CoreLocation

public struct PhotoLocation:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?

    public init?(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil
    ) {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              altitude?.isFinite != false else {
            return nil
        }
        self.latitude = latitude == -0 ? 0 : latitude
        self.longitude = longitude == -0 ? 0 : longitude
        self.altitude = altitude
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    public var coordinateText: String {
        String(
            format: "%.6f, %.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            latitude,
            longitude
        )
    }

    public var altitudeText: String? {
        altitude.map {
            String(
                format: "%.1f m",
                locale: Locale(identifier: "en_US_POSIX"),
                $0
            )
        }
    }
}

public enum PhotoLocationSource:
    String,
    Codable,
    Equatable,
    Sendable
{
    case none
    case embedded
    case manual
    case removed

    public var name: String {
        switch self {
        case .none: return "No location"
        case .embedded: return "Camera GPS"
        case .manual: return "Set in RAWDesk"
        case .removed: return "Removed in RAWDesk"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "mappin.slash"
        case .embedded: return "camera.metering.center.weighted"
        case .manual: return "mappin.and.ellipse"
        case .removed: return "location.slash"
        }
    }
}

public struct LocationMetadataRefreshProgress:
    Equatable,
    Sendable
{
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 1 }
        return Double(completed) / Double(total)
    }
}
