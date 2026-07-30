import Foundation
import AppKit
import CoreImage

public struct HistogramData: Equatable, Sendable {
    public let red: [CGFloat]
    public let green: [CGFloat]
    public let blue: [CGFloat]
    public let shadowClippingFraction: CGFloat
    public let highlightClippingFraction: CGFloat

    public init(
        red: [CGFloat],
        green: [CGFloat],
        blue: [CGFloat],
        shadowClippingFraction: CGFloat = 0,
        highlightClippingFraction: CGFloat = 0
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.shadowClippingFraction = shadowClippingFraction
        self.highlightClippingFraction = highlightClippingFraction
    }

    public static let empty = HistogramData(red: [], green: [], blue: [])
}

public enum HistogramAnalyzer {
    private static let colorSpace =
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let context = CIContext(options: [.workingColorSpace: colorSpace])

    public static func analyze(_ image: NSImage, binCount: Int = 128) -> HistogramData? {
        guard binCount > 1,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIAreaHistogram") else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        filter.setValue(binCount, forKey: "inputCount")
        filter.setValue(1.0, forKey: "inputScale")
        guard let output = filter.outputImage else { return nil }

        var pixels = [Float](repeating: 0, count: binCount * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            context.render(
                output,
                toBitmap: address,
                rowBytes: binCount * MemoryLayout<Float>.size * 4,
                bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
                format: .RGBAf,
                colorSpace: colorSpace
            )
        }

        let largest = pixels.max() ?? 0
        guard largest > 0 else { return .empty }
        func channel(_ offset: Int) -> [CGFloat] {
            stride(from: offset, to: pixels.count, by: 4).map {
                // Square-root scaling keeps shadow/midtone detail readable even
                // when a narrow highlight spike dominates the histogram.
                CGFloat(sqrt(max(0, pixels[$0]) / largest))
            }
        }
        var colorTotal: Float = 0
        var pixelIndex = 0
        while pixelIndex < pixels.count {
            colorTotal += pixels[pixelIndex]
            colorTotal += pixels[pixelIndex + 1]
            colorTotal += pixels[pixelIndex + 2]
            pixelIndex += 4
        }
        let shadow = colorTotal > 0
            ? (pixels[0] + pixels[1] + pixels[2]) / colorTotal
            : 0
        let last = (binCount - 1) * 4
        let highlight = colorTotal > 0
            ? (pixels[last] + pixels[last + 1] + pixels[last + 2]) / colorTotal
            : 0
        return HistogramData(
            red: channel(0),
            green: channel(1),
            blue: channel(2),
            shadowClippingFraction: CGFloat(shadow),
            highlightClippingFraction: CGFloat(highlight)
        )
    }
}
