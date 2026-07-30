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

        // Peak over the colour channels only. The buffer is interleaved RGBA,
        // and `inputScale: 1.0` makes each channel's bins sum to 1. In an
        // opaque photograph every pixel's alpha lands in the top bin, so that
        // one bin holds 1.0 — larger than any RGB bin can be. Taking
        // `pixels.max()` therefore normalised every curve against alpha and
        // drew the histogram at a few percent of its true height.
        //
        // One shared peak across R, G and B: normalising each channel
        // separately would equalise their heights and hide colour casts.
        var largest: Float = 0
        var scanIndex = 0
        while scanIndex < pixels.count {
            largest = max(largest, pixels[scanIndex])
            largest = max(largest, pixels[scanIndex + 1])
            largest = max(largest, pixels[scanIndex + 2])
            scanIndex += 4
        }
        guard largest > 0 else { return .empty }
        func channel(_ offset: Int) -> [CGFloat] {
            stride(from: offset, to: pixels.count, by: 4).map {
                // Square-root scaling keeps shadow/midtone detail readable even
                // when a narrow highlight spike dominates the histogram.
                CGFloat(sqrt(max(0, pixels[$0]) / largest))
            }
        }
        // Clipping is per-channel: a blown red channel is blown even when green
        // and blue are fine. Averaging the three channels divided a
        // single-channel clip by three and under-reported it.
        let last = (binCount - 1) * 4
        let shadow = max(pixels[0], pixels[1], pixels[2])
        let highlight = max(
            pixels[last],
            pixels[last + 1],
            pixels[last + 2]
        )
        return HistogramData(
            red: channel(0),
            green: channel(1),
            blue: channel(2),
            shadowClippingFraction: CGFloat(shadow),
            highlightClippingFraction: CGFloat(highlight)
        )
    }
}
