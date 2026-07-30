import Foundation

public enum GPXTracklogError:
    LocalizedError,
    Equatable
{
    case fileTooLarge
    case malformedXML
    case noTimedTrackPoints
    case tooManyTrackPoints

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The GPX file exceeds the 64 MB safety limit."
        case .malformedXML:
            return "The selected file is not valid GPX XML."
        case .noTimedTrackPoints:
            return "The GPX file contains no track points with valid timestamps."
        case .tooManyTrackPoints:
            return "The GPX file contains more than one million track points."
        }
    }
}

public enum GPXTracklogParser {
    private static let maximumBytes = 64 * 1_024 * 1_024

    public static func parse(url: URL) throws -> GPXTracklog {
        let values = try? url.resourceValues(
            forKeys: [.fileSizeKey]
        )
        if let size = values?.fileSize,
           size > maximumBytes {
            throw GPXTracklogError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else {
            throw GPXTracklogError.fileTooLarge
        }
        return try parse(
            data: data,
            name: url.deletingPathExtension()
                .lastPathComponent
        )
    }

    public static func parse(
        data: Data,
        name: String = "Tracklog"
    ) throws -> GPXTracklog {
        guard data.count <= maximumBytes else {
            throw GPXTracklogError.fileTooLarge
        }
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            if delegate.exceededPointLimit {
                throw GPXTracklogError.tooManyTrackPoints
            }
            throw GPXTracklogError.malformedXML
        }
        guard !delegate.points.isEmpty else {
            throw GPXTracklogError.noTimedTrackPoints
        }
        return GPXTracklog(name: name, points: delegate.points)
    }
}

private final class GPXParserDelegate:
    NSObject,
    XMLParserDelegate
{
    private struct PendingPoint {
        var latitude: Double
        var longitude: Double
        var altitude: Double?
        var timestamp: Date?
    }

    private(set) var points: [GPXTrackPoint] = []
    private(set) var exceededPointLimit = false
    private var pendingPoint: PendingPoint?
    private var text = ""
    private var activeElement = ""
    private let maximumPoints = 1_000_000

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        activeElement = elementName.lowercased()
        text = ""
        guard activeElement == "trkpt",
              let latitudeText = attributeDict["lat"],
              let longitudeText = attributeDict["lon"],
              let latitude = Double(latitudeText),
              let longitude = Double(longitudeText),
              PhotoLocation(
                  latitude: latitude,
                  longitude: longitude
              ) != nil else {
            return
        }
        pendingPoint = PendingPoint(
            latitude: latitude,
            longitude: longitude
        )
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if activeElement == "ele" || activeElement == "time" {
            text += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = elementName.lowercased()
        let value = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if element == "ele", pendingPoint != nil {
            pendingPoint?.altitude = Double(value)
        } else if element == "time", pendingPoint != nil {
            pendingPoint?.timestamp = Self.parseDate(value)
        } else if element == "trkpt" {
            if let pendingPoint,
               let timestamp = pendingPoint.timestamp,
               let location = PhotoLocation(
                   latitude: pendingPoint.latitude,
                   longitude: pendingPoint.longitude,
                   altitude: pendingPoint.altitude
               ) {
                points.append(
                    GPXTrackPoint(
                        timestamp: timestamp,
                        location: location
                    )
                )
                if points.count > maximumPoints {
                    exceededPointLimit = true
                    parser.abortParsing()
                }
            }
            self.pendingPoint = nil
        }
        activeElement = ""
        text = ""
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return standardFormatter.date(from: value)
    }

    private static let fractionalFormatter:
        ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            return formatter
        }()

    private static let standardFormatter:
        ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
}
