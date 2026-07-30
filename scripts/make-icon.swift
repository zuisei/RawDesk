#!/usr/bin/env swift
// Generate AppIcon.icns into Resources/.
// Uses Core Graphics so the app icon can be rebuilt without extra design assets.

import Foundation
import AppKit
import CoreGraphics

func drawIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    func fillRounded(_ rect: CGRect, radius: CGFloat, color: CGColor) {
        ctx.setFillColor(color)
        ctx.addPath(roundedRect(rect, radius: radius))
        ctx.fillPath()
    }

    func strokeRounded(_ rect: CGRect, radius: CGFloat, color: CGColor, width: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.addPath(roundedRect(rect, radius: radius))
        ctx.strokePath()
    }

    // Deep desktop-style base.
    let bgColors = [
        CGColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1.0),
        CGColor(red: 0.13, green: 0.18, blue: 0.25, alpha: 1.0),
        CGColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 0.62, 1])!
    let cornerRadius = s * 0.22
    let bgPath = roundedRect(CGRect(x: 0, y: 0, width: s, height: s), radius: cornerRadius)
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0), options: [])

    // Soft top glow.
    let glowColors = [
        CGColor(red: 0.54, green: 0.82, blue: 1.00, alpha: 0.55),
        CGColor(red: 0.54, green: 0.82, blue: 1.00, alpha: 0.0)
    ] as CFArray
    let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0, 1])!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: s * 0.28, y: s * 0.18),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.28, y: s * 0.18),
        endRadius: s * 0.72,
        options: []
    )

    // Slightly tilted photo plate.
    ctx.saveGState()
    ctx.translateBy(x: s * 0.5, y: s * 0.52)
    ctx.rotate(by: -0.12)
    ctx.translateBy(x: -s * 0.5, y: -s * 0.52)

    let plate = CGRect(x: s * 0.17, y: s * 0.22, width: s * 0.66, height: s * 0.58)
    ctx.setShadow(offset: CGSize(width: 0, height: s * 0.035), blur: s * 0.055,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
    fillRounded(plate, radius: s * 0.06, color: CGColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1.0))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    strokeRounded(plate.insetBy(dx: s * 0.012, dy: s * 0.012), radius: s * 0.048,
                  color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.65), width: s * 0.012)

    // Photo preview area with a warm RAW-file accent.
    let imageRect = plate.insetBy(dx: s * 0.055, dy: s * 0.06)
    let imageGradientColors = [
        CGColor(red: 0.20, green: 0.34, blue: 0.45, alpha: 1.0),
        CGColor(red: 0.99, green: 0.62, blue: 0.22, alpha: 1.0)
    ] as CFArray
    let imageGradient = CGGradient(colorsSpace: cs, colors: imageGradientColors, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(roundedRect(imageRect, radius: s * 0.04))
    ctx.clip()
    ctx.drawLinearGradient(imageGradient, start: CGPoint(x: imageRect.minX, y: imageRect.minY),
                           end: CGPoint(x: imageRect.maxX, y: imageRect.maxY), options: [])

    ctx.setFillColor(CGColor(red: 0.05, green: 0.10, blue: 0.14, alpha: 0.42))
    let mountain = CGMutablePath()
    mountain.move(to: CGPoint(x: imageRect.minX, y: imageRect.maxY))
    mountain.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * 0.32, y: imageRect.minY + imageRect.height * 0.55))
    mountain.addLine(to: CGPoint(x: imageRect.minX + imageRect.width * 0.52, y: imageRect.minY + imageRect.height * 0.72))
    mountain.addLine(to: CGPoint(x: imageRect.maxX, y: imageRect.minY + imageRect.height * 0.38))
    mountain.addLine(to: CGPoint(x: imageRect.maxX, y: imageRect.maxY))
    mountain.closeSubpath()
    ctx.addPath(mountain)
    ctx.fillPath()

    ctx.setFillColor(CGColor(red: 1.0, green: 0.86, blue: 0.35, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: imageRect.maxX - s * 0.19, y: imageRect.minY + s * 0.06,
                               width: s * 0.09, height: s * 0.09))
    ctx.restoreGState()

    // RAW tab.
    let tab = CGRect(x: plate.maxX - s * 0.31, y: plate.minY - s * 0.03, width: s * 0.22, height: s * 0.12)
    fillRounded(tab, radius: s * 0.025, color: CGColor(red: 0.98, green: 0.40, blue: 0.16, alpha: 1.0))
    if size >= 128 {
        let text = "RAW" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: s * 0.045, weight: .heavy),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: CGPoint(x: tab.midX - textSize.width / 2, y: tab.midY - textSize.height / 2),
            withAttributes: attrs
        )
    }
    ctx.restoreGState()

    // Aperture/lens mark.
    ctx.saveGState()
    let center = CGPoint(x: s / 2, y: s / 2)
    let radius = s * 0.23
    ctx.setShadow(offset: CGSize(width: 0, height: s * 0.018), blur: s * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.36))
    ctx.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 0.92))
    ctx.fillEllipse(in: CGRect(x: center.x - radius * 1.13, y: center.y - radius * 1.13,
                               width: radius * 2.26, height: radius * 2.26))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let blades = 6
    for i in 0..<blades {
        let angle = (CGFloat(i) / CGFloat(blades)) * 2 * .pi
        let p1 = CGPoint(x: center.x + cos(angle) * radius,
                         y: center.y + sin(angle) * radius)
        let p2 = CGPoint(x: center.x + cos(angle + .pi / 3) * radius,
                         y: center.y + sin(angle + .pi / 3) * radius)
        let path = CGMutablePath()
        path.move(to: center)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        let color = NSColor(hue: 0.52 + CGFloat(i) * 0.018, saturation: 0.42,
                            brightness: 0.98, alpha: 0.94).cgColor
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }
    let lensRect = CGRect(x: center.x - radius * 0.45, y: center.y - radius * 0.45,
                          width: radius * 0.9, height: radius * 0.9)
    ctx.setFillColor(CGColor(red: 0.03, green: 0.05, blue: 0.08, alpha: 1.0))
    ctx.fillEllipse(in: lensRect)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
    ctx.setLineWidth(s * 0.012)
    ctx.strokeEllipse(in: lensRect)
    ctx.restoreGState()

    // Outer highlight.
    strokeRounded(CGRect(x: s * 0.018, y: s * 0.018, width: s * 0.964, height: s * 0.964),
                  radius: cornerRadius * 0.94,
                  color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
                  width: s * 0.012)

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-icon.swift <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
let iconset = outDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let pairs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in pairs {
    guard let img = drawIcon(size: size) else { continue }
    try writePNG(img, to: iconset.appendingPathComponent(name))
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("wrote \(icns.path)")
