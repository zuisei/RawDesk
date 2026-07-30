import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Fixture {
    var filename: String
    var captureTime: String
    var topColor: NSColor
    var bottomColor: NSColor
    var rating: Int
    var keyword: String
}

private let fixtures = [
    Fixture(
        filename: "Tethered-A.jpg",
        captureTime: "2026:07:26 09:15:00",
        topColor: .systemMint,
        bottomColor: .systemBlue,
        rating: 4,
        keyword: "Capture Source"
    ),
    Fixture(
        filename: "Tethered-B.jpg",
        captureTime: "2026:07:26 09:15:03",
        topColor: .systemOrange,
        bottomColor: .systemPurple,
        rating: 3,
        keyword: "Capture Source"
    ),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data(
        "Usage: make-auto-import-qa-fixtures.swift OUTPUT_DIRECTORY\n"
            .utf8
    ))
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

let width = 2_000
let height = 1_250
let colorSpace = CGColorSpaceCreateDeviceRGB()

for fixture in fixtures {
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
        throw NSError(
            domain: "RAWDeskAutoImportQA",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not create a bitmap context.",
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
    context.setFillColor(
        NSColor.white.withAlphaComponent(0.8).cgColor
    )
    context.fillEllipse(
        in: CGRect(
            x: width * 3 / 8,
            y: height * 3 / 10,
            width: width / 4,
            height: height * 2 / 5
        )
    )
    guard let image = context.makeImage() else {
        throw NSError(
            domain: "RAWDeskAutoImportQA",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not create \(fixture.filename).",
            ]
        )
    }

    let photoURL = outputDirectory.appendingPathComponent(
        fixture.filename
    )
    guard let destination = CGImageDestinationCreateWithURL(
        photoURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(
            domain: "RAWDeskAutoImportQA",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not open \(fixture.filename).",
            ]
        )
    }
    let properties: [String: Any] = [
        kCGImageDestinationLossyCompressionQuality as String: 0.9,
        kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifDateTimeOriginal as String:
                fixture.captureTime,
            kCGImagePropertyExifDateTimeDigitized as String:
                fixture.captureTime,
        ],
        kCGImagePropertyTIFFDictionary as String: [
            kCGImagePropertyTIFFDateTime as String:
                fixture.captureTime,
            kCGImagePropertyTIFFMake as String: "RAWDesk QA",
            kCGImagePropertyTIFFModel as String:
                "Auto Import Fixture",
        ],
    ]
    CGImageDestinationAddImage(
        destination,
        image,
        properties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(
            domain: "RAWDeskAutoImportQA",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not finalize \(fixture.filename).",
            ]
        )
    }

    let sidecarURL = photoURL
        .deletingPathExtension()
        .appendingPathExtension("xmp")
    let xmp = """
    <?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about=""
          xmlns:xmp="http://ns.adobe.com/xap/1.0/"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmp:Rating="\(fixture.rating)">
          <dc:subject>
            <rdf:Bag>
              <rdf:li>\(fixture.keyword)</rdf:li>
            </rdf:Bag>
          </dc:subject>
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end="w"?>
    """
    try Data(xmp.utf8).write(
        to: sidecarURL,
        options: [.atomic]
    )
}

let original = outputDirectory.appendingPathComponent(
    "Tethered-A.jpg"
)
let duplicate = outputDirectory.appendingPathComponent(
    "Tethered-A-Duplicate.jpg"
)
try? FileManager.default.removeItem(at: duplicate)
try FileManager.default.copyItem(
    at: original,
    to: duplicate
)

print(outputDirectory.path)
