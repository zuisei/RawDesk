import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Fixture {
    var filename: String
    var captureTime: String?
    var topColor: NSColor
    var bottomColor: NSColor
}

private let fixtures = [
    Fixture(
        filename: "Burst-A.jpg",
        captureTime: "2026:07:25 12:00:00",
        topColor: .systemBlue,
        bottomColor: .systemTeal
    ),
    Fixture(
        filename: "Burst-B.jpg",
        captureTime: "2026:07:25 12:00:05",
        topColor: .systemIndigo,
        bottomColor: .systemBlue
    ),
    Fixture(
        filename: "Separate.jpg",
        captureTime: "2026:07:25 12:00:40",
        topColor: .systemOrange,
        bottomColor: .systemPink
    ),
    Fixture(
        filename: "No-Capture-Time.jpg",
        captureTime: nil,
        topColor: .darkGray,
        bottomColor: .lightGray
    ),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("Usage: make-auto-stack-qa-fixtures.swift OUTPUT_DIRECTORY\n".utf8)
    )
    exit(2)
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let width = 2_400
let height = 1_600
let colorSpace = CGColorSpaceCreateDeviceRGB()

for fixture in fixtures {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(
            domain: "RAWDeskQAFixtures",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not create a bitmap context.",
            ]
        )
    }

    context.setFillColor(fixture.bottomColor.cgColor)
    context.fill(
        CGRect(x: 0, y: 0, width: width, height: height)
    )
    context.setFillColor(fixture.topColor.cgColor)
    context.fill(
        CGRect(
            x: 0,
            y: height / 2,
            width: width,
            height: height / 2
        )
    )
    context.setFillColor(NSColor.white.withAlphaComponent(0.75).cgColor)
    context.fillEllipse(
        in: CGRect(
            x: width / 3,
            y: height / 3,
            width: width / 3,
            height: height / 3
        )
    )

    guard let image = context.makeImage() else {
        throw NSError(
            domain: "RAWDeskQAFixtures",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not create a CGImage.",
            ]
        )
    }

    var properties: [String: Any] = [
        kCGImagePropertyJFIFDictionary as String: [
            kCGImagePropertyJFIFIsProgressive as String: false,
        ],
        kCGImageDestinationLossyCompressionQuality as String: 0.9,
    ]
    if let captureTime = fixture.captureTime {
        properties[kCGImagePropertyExifDictionary as String] = [
            kCGImagePropertyExifDateTimeOriginal as String:
                captureTime,
            kCGImagePropertyExifDateTimeDigitized as String:
                captureTime,
        ]
        properties[kCGImagePropertyTIFFDictionary as String] = [
            kCGImagePropertyTIFFDateTime as String: captureTime,
            kCGImagePropertyTIFFMake as String: "RAWDesk QA",
            kCGImagePropertyTIFFModel as String: "Fixture Camera",
        ]
    }

    let destinationURL = outputDirectory.appendingPathComponent(
        fixture.filename
    )
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(
            domain: "RAWDeskQAFixtures",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not create \(fixture.filename).",
            ]
        )
    }
    CGImageDestinationAddImage(
        destination,
        image,
        properties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(
            domain: "RAWDeskQAFixtures",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not finalize \(fixture.filename).",
            ]
        )
    }

    guard let source = CGImageSourceCreateWithURL(
        destinationURL as CFURL,
        nil
    ),
    let storedProperties = CGImageSourceCopyPropertiesAtIndex(
        source,
        0,
        nil
    ) as? [String: Any] else {
        throw NSError(
            domain: "RAWDeskQAFixtures",
            code: 5,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not validate \(fixture.filename).",
            ]
        )
    }
    let storedEXIF = storedProperties[
        kCGImagePropertyExifDictionary as String
    ] as? [String: Any]
    let storedCaptureTime = storedEXIF?[
        kCGImagePropertyExifDateTimeOriginal as String
    ] as? String
    guard storedCaptureTime == fixture.captureTime else {
        throw NSError(
            domain: "RAWDeskQAFixtures",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Capture-time validation failed for \(fixture.filename).",
            ]
        )
    }
}

print(outputDirectory.path)
