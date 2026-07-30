import Foundation
import ImageIO
import CoreGraphics

public enum MetadataReader {
    public static let currentReaderVersion = 2

    public static func read(url: URL) -> PhotoMetadata {
        let opts: [String: Any] = [kCGImageSourceShouldCache as String: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts as CFDictionary) else {
            return PhotoMetadata(
                readerVersion: currentReaderVersion,
                error: "Cannot open image source"
            )
        }
        guard let raw = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] else {
            return PhotoMetadata(
                readerVersion: currentReaderVersion,
                error: "Cannot read image properties"
            )
        }

        let exif = raw[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = raw[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exifAux = raw[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
        let gps = raw[kCGImagePropertyGPSDictionary as String]
            as? [String: Any] ?? [:]

        let pixelWidth = (raw[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue
        let pixelHeight = (raw[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
        let colorProfile = (raw[kCGImagePropertyProfileName as String] as? String)
            ?? (raw[kCGImagePropertyColorModel as String] as? String)

        let cameraMake = tiff[kCGImagePropertyTIFFMake as String] as? String
        let cameraModel = tiff[kCGImagePropertyTIFFModel as String] as? String

        let lensModel = (exif[kCGImagePropertyExifLensModel as String] as? String)
            ?? (exifAux[kCGImagePropertyExifAuxLensModel as String] as? String)

        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber]
        let iso = isoArray?.first?.intValue
            ?? (exif["PhotographicSensitivity"] as? NSNumber)?.intValue

        let shutter = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        let aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
        let focalLength = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue
        let exposureBias = (exif[kCGImagePropertyExifExposureBiasValue as String] as? NSNumber)?.doubleValue

        let captureDate: Date? = {
            if let s = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
               let d = parseExifDate(s) { return d }
            if let s = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String,
               let d = parseExifDate(s) { return d }
            if let s = tiff[kCGImagePropertyTIFFDateTime as String] as? String,
               let d = parseExifDate(s) { return d }
            return nil
        }()
        let location = readLocation(from: gps)

        return PhotoMetadata(
            readerVersion: currentReaderVersion,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lensModel,
            iso: iso,
            shutterSpeed: shutter,
            aperture: aperture,
            focalLength: focalLength,
            captureDate: captureDate,
            exposureBias: exposureBias,
            colorProfile: colorProfile,
            location: location
        )
    }

    private static func readLocation(
        from gps: [String: Any]
    ) -> PhotoLocation? {
        guard let latitude = number(
            gps[kCGImagePropertyGPSLatitude as String]
        ),
        let longitude = number(
            gps[kCGImagePropertyGPSLongitude as String]
        ) else {
            return nil
        }

        let latitudeRef = (
            gps[kCGImagePropertyGPSLatitudeRef as String] as? String
        )?.uppercased()
        let longitudeRef = (
            gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        )?.uppercased()
        let signedLatitude: Double
        switch latitudeRef {
        case "S": signedLatitude = -abs(latitude)
        case "N": signedLatitude = abs(latitude)
        default: signedLatitude = latitude
        }
        let signedLongitude: Double
        switch longitudeRef {
        case "W": signedLongitude = -abs(longitude)
        case "E": signedLongitude = abs(longitude)
        default: signedLongitude = longitude
        }

        var altitude = number(
            gps[kCGImagePropertyGPSAltitude as String]
        )
        if let value = altitude,
           number(
               gps[kCGImagePropertyGPSAltitudeRef as String]
           ) == 1 {
            altitude = -abs(value)
        }
        return PhotoLocation(
            latitude: signedLatitude,
            longitude: signedLongitude,
            altitude: altitude
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static func parseExifDate(_ s: String) -> Date? {
        exifDateFormatter.date(from: s)
    }
}
