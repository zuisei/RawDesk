import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FixtureError: Error {
    case imageCreation
    case destinationCreation
    case destinationFinalize
}

func makeImage(
    width: Int,
    height: Int,
    color: NSColor
) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo:
            CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FixtureError.imageCreation
    }
    context.setFillColor(
        (color.usingColorSpace(.sRGB) ?? color).cgColor
    )
    context.fill(
        CGRect(x: 0, y: 0, width: width, height: height)
    )
    guard let image = context.makeImage() else {
        throw FixtureError.imageCreation
    }
    return image
}

func writeJPEG(
    named name: String,
    color: NSColor,
    captureDate: String,
    location: (
        latitude: Double,
        longitude: Double,
        altitude: Double
    )? = nil,
    to directory: URL
) throws {
    let url = directory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw FixtureError.destinationCreation
    }
    var properties: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFMake: "RAWDesk QA",
            kCGImagePropertyTIFFModel: "Map Fixture",
            kCGImagePropertyTIFFDateTime: captureDate,
        ] as [CFString: Any],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: captureDate,
            kCGImagePropertyExifDateTimeDigitized: captureDate,
            kCGImagePropertyExifISOSpeedRatings: [200],
            kCGImagePropertyExifFNumber: 4.0,
            kCGImagePropertyExifExposureTime: 0.01,
            kCGImagePropertyExifFocalLength: 35.0,
        ] as [CFString: Any],
        kCGImagePropertyIPTCDictionary: [
            kCGImagePropertyIPTCKeywords: ["Map QA"],
            kCGImagePropertyIPTCCaptionAbstract:
                "RAWDesk map Release QA fixture",
            kCGImagePropertyIPTCCity: "Fixture City",
            kCGImagePropertyIPTCProvinceState: "Fixture State",
            kCGImagePropertyIPTCCountryPrimaryLocationCode:
                "QAT",
            kCGImagePropertyIPTCCountryPrimaryLocationName:
                "QA Territory",
        ] as [CFString: Any],
    ]
    if let location {
        properties[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude:
                abs(location.latitude),
            kCGImagePropertyGPSLatitudeRef:
                location.latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude:
                abs(location.longitude),
            kCGImagePropertyGPSLongitudeRef:
                location.longitude < 0 ? "W" : "E",
            kCGImagePropertyGPSAltitude:
                abs(location.altitude),
            kCGImagePropertyGPSAltitudeRef:
                location.altitude < 0 ? 1 : 0,
        ] as [CFString: Any]
    }
    CGImageDestinationAddImage(
        destination,
        try makeImage(
            width: 1_200,
            height: 800,
            color: color
        ),
        properties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw FixtureError.destinationFinalize
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs(
        "usage: swift make-map-qa-fixtures.swift OUTPUT_DIRECTORY\n",
        stderr
    )
    exit(2)
}

let output = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)
try FileManager.default.createDirectory(
    at: output,
    withIntermediateDirectories: true
)

try writeJPEG(
    named: "01-Tokyo-Embedded.jpg",
    color: .systemRed,
    captureDate: "2026:07:26 00:00:00",
    location: (
        latitude: 35.681236,
        longitude: 139.767125,
        altitude: 12
    ),
    to: output
)
try writeJPEG(
    named: "02-GPX-Match.jpg",
    color: .systemBlue,
    captureDate: "2026:07:26 00:01:00",
    to: output
)
try writeJPEG(
    named: "03-GPX-Match.jpg",
    color: .systemGreen,
    captureDate: "2026:07:26 00:02:00",
    to: output
)
try writeJPEG(
    named: "04-Untagged.jpg",
    color: .systemOrange,
    captureDate: "2026:07:26 03:00:00",
    to: output
)

let gpx = """
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="RAWDesk Release QA"
     xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Tokyo QA Route</name></metadata>
  <trk><name>Tokyo QA Route</name><trkseg>
    <trkpt lat="35.681236" lon="139.767125">
      <ele>12</ele><time>2026-07-26T00:00:00Z</time>
    </trkpt>
    <trkpt lat="35.689500" lon="139.691710">
      <ele>40</ele><time>2026-07-26T00:01:00Z</time>
    </trkpt>
    <trkpt lat="35.658581" lon="139.745433">
      <ele>25</ele><time>2026-07-26T00:02:00Z</time>
    </trkpt>
  </trkseg></trk>
</gpx>
"""
try Data(gpx.utf8).write(
    to: output.appendingPathComponent("Tokyo-QA-Route.gpx"),
    options: [.atomic]
)

print(output.path)
