import Foundation
import CoreLocation

public struct GPXTrackPoint:
    Codable,
    Equatable,
    Sendable
{
    public var timestamp: Date
    public var location: PhotoLocation

    public init(timestamp: Date, location: PhotoLocation) {
        self.timestamp = timestamp
        self.location = location
    }
}

public struct GPXTracklog:
    Equatable,
    Sendable
{
    public var name: String
    public var points: [GPXTrackPoint]

    public init(name: String, points: [GPXTrackPoint]) {
        self.name = name
        var latestByTimestamp: [Date: GPXTrackPoint] = [:]
        for point in points {
            latestByTimestamp[point.timestamp] = point
        }
        self.points = latestByTimestamp.values.sorted {
            $0.timestamp < $1.timestamp
        }
    }

    public var startDate: Date? { points.first?.timestamp }
    public var endDate: Date? { points.last?.timestamp }

    public var displayCoordinates: [CLLocationCoordinate2D] {
        guard points.count > 5_000 else {
            return points.map(\.location.coordinate)
        }
        let stride = max(1, points.count / 5_000)
        var result = Swift.stride(
            from: 0,
            to: points.count,
            by: stride
        ).map {
            points[$0].location.coordinate
        }
        if let last = points.last?.location.coordinate,
           result.last?.latitude != last.latitude
            || result.last?.longitude != last.longitude {
            result.append(last)
        }
        return result
    }

    public func location(
        atCameraTime cameraTime: Date,
        settings: GPXMatchSettings
    ) -> PhotoLocation? {
        guard !points.isEmpty else { return nil }
        let target = cameraTime.addingTimeInterval(
            -settings.tracklogOffset
        )
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].timestamp < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        if lower < points.count,
           points[lower].timestamp == target {
            return points[lower].location
        }
        if lower == 0 {
            let delta = abs(
                points[0].timestamp.timeIntervalSince(target)
            )
            return delta <= settings.maximumPointGap
                ? points[0].location
                : nil
        }
        if lower == points.count {
            guard let last = points.last else { return nil }
            let delta = abs(
                last.timestamp.timeIntervalSince(target)
            )
            return delta <= settings.maximumPointGap
                ? last.location
                : nil
        }

        let before = points[lower - 1]
        let after = points[lower]
        let segmentDuration =
            after.timestamp.timeIntervalSince(before.timestamp)
        guard segmentDuration > 0,
              segmentDuration <= settings.maximumPointGap else {
            let beforeDelta = abs(
                before.timestamp.timeIntervalSince(target)
            )
            let afterDelta = abs(
                after.timestamp.timeIntervalSince(target)
            )
            let nearest = beforeDelta <= afterDelta
                ? (beforeDelta, before.location)
                : (afterDelta, after.location)
            return nearest.0 <= settings.maximumPointGap
                ? nearest.1
                : nil
        }
        let fraction = target.timeIntervalSince(
            before.timestamp
        ) / segmentDuration
        return Self.interpolate(
            before.location,
            after.location,
            fraction: fraction
        )
    }

    private static func interpolate(
        _ start: PhotoLocation,
        _ end: PhotoLocation,
        fraction: Double
    ) -> PhotoLocation? {
        let fraction = max(0, min(1, fraction))
        let latitude = start.latitude
            + (end.latitude - start.latitude) * fraction
        var longitudeDelta = end.longitude - start.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        var longitude =
            start.longitude + longitudeDelta * fraction
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        let altitude: Double?
        if let startAltitude = start.altitude,
           let endAltitude = end.altitude {
            altitude = startAltitude
                + (endAltitude - startAltitude) * fraction
        } else {
            altitude = start.altitude ?? end.altitude
        }
        return PhotoLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude
        )
    }
}

public struct GPXMatchSettings:
    Codable,
    Equatable,
    Sendable
{
    /// Added to GPX timestamps to align them with camera capture times.
    public var tracklogOffset: TimeInterval
    public var maximumPointGap: TimeInterval
    public var overwriteExistingLocations: Bool
    public var photoScope: GPXPhotoScope

    public init(
        tracklogOffset: TimeInterval = 0,
        maximumPointGap: TimeInterval = 5 * 60,
        overwriteExistingLocations: Bool = false,
        photoScope: GPXPhotoScope = .selected
    ) {
        self.tracklogOffset = max(
            -24 * 60 * 60,
            min(24 * 60 * 60, tracklogOffset)
        )
        self.maximumPointGap = max(
            1,
            min(24 * 60 * 60, maximumPointGap)
        )
        self.overwriteExistingLocations =
            overwriteExistingLocations
        self.photoScope = photoScope
    }
}

public enum GPXPhotoScope:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case selected
    case visible

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .selected: return "Selected Photos"
        case .visible: return "All Visible Photos"
        }
    }
}

public struct GPXAutoTagPreview:
    Equatable,
    Sendable
{
    public var locationsByPhotoID:
        [PhotoAsset.ID: PhotoLocation]
    public var consideredCount: Int
    public var skippedExistingCount: Int
    public var missingCaptureDateCount: Int
    public var outsideTrackCount: Int

    public init(
        locationsByPhotoID:
            [PhotoAsset.ID: PhotoLocation] = [:],
        consideredCount: Int = 0,
        skippedExistingCount: Int = 0,
        missingCaptureDateCount: Int = 0,
        outsideTrackCount: Int = 0
    ) {
        self.locationsByPhotoID = locationsByPhotoID
        self.consideredCount = consideredCount
        self.skippedExistingCount = skippedExistingCount
        self.missingCaptureDateCount = missingCaptureDateCount
        self.outsideTrackCount = outsideTrackCount
    }

    public var matchedCount: Int {
        locationsByPhotoID.count
    }

    public static func make(
        tracklog: GPXTracklog,
        assets: [PhotoAsset],
        settings: GPXMatchSettings
    ) -> GPXAutoTagPreview {
        var result = GPXAutoTagPreview(
            consideredCount: assets.count
        )
        for asset in assets where !asset.catalogMissing {
            if asset.effectiveLocation != nil,
               !settings.overwriteExistingLocations {
                result.skippedExistingCount += 1
                continue
            }
            guard let captureDate =
                    asset.metadata?.captureDate else {
                result.missingCaptureDateCount += 1
                continue
            }
            guard let location = tracklog.location(
                atCameraTime: captureDate,
                settings: settings
            ) else {
                result.outsideTrackCount += 1
                continue
            }
            result.locationsByPhotoID[asset.id] = location
        }
        return result
    }
}
