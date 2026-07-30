import AppKit

public struct CIELABSample: Equatable, Sendable {
    public var lightness: Double
    public var a: Double
    public var b: Double

    public init(
        lightness: Double,
        a: Double,
        b: Double
    ) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }
}

public struct ImagePixelSample: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(
        red: Double,
        green: Double,
        blue: Double
    ) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    public var lab: CIELABSample {
        let linearRed = Self.linearized(red)
        let linearGreen = Self.linearized(green)
        let linearBlue = Self.linearized(blue)

        let x =
            0.412_456_4 * linearRed
            + 0.357_576_1 * linearGreen
            + 0.180_437_5 * linearBlue
        let y =
            0.212_672_9 * linearRed
            + 0.715_152_2 * linearGreen
            + 0.072_175_0 * linearBlue
        let z =
            0.019_333_9 * linearRed
            + 0.119_192_0 * linearGreen
            + 0.950_304_1 * linearBlue

        let fx = Self.labCurve(x / 0.950_47)
        let fy = Self.labCurve(y)
        let fz = Self.labCurve(z / 1.088_83)
        return CIELABSample(
            lightness: 116 * fy - 16,
            a: 500 * (fx - fy),
            b: 200 * (fy - fz)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }

    private static func linearized(_ value: Double) -> Double {
        value <= 0.040_45
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func labCurve(_ value: Double) -> Double {
        let delta = 6.0 / 29.0
        let threshold = delta * delta * delta
        return value > threshold
            ? pow(value, 1.0 / 3.0)
            : value / (3 * delta * delta) + 4.0 / 29.0
    }
}

/// Reuses one bitmap representation while the pointer moves over a preview.
public final class ImagePixelSampler {
    private let bitmap: NSBitmapImageRep

    public init?(image: NSImage) {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            return nil
        }
        self.bitmap = bitmap
    }

    public func sample(
        normalizedX: Double,
        normalizedY: Double,
        radius: Int = 2
    ) -> ImagePixelSample? {
        let x = min(
            1,
            max(
                0,
                normalizedX.isFinite
                    ? normalizedX
                    : 0.5
            )
        )
        let y = min(
            1,
            max(
                0,
                normalizedY.isFinite
                    ? normalizedY
                    : 0.5
            )
        )
        let centerX = Int(
            (
                x * Double(bitmap.pixelsWide - 1)
            ).rounded()
        )
        // NSBitmapImageRep exposes CGImage rows in the same
        // top-to-bottom order used by the SwiftUI preview.
        let centerY = Int(
            (
                y * Double(bitmap.pixelsHigh - 1)
            ).rounded()
        )
        let sampleRadius = min(8, max(0, radius))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var weight = 0.0

        for pixelY in max(
            0,
            centerY - sampleRadius
        )...min(
            bitmap.pixelsHigh - 1,
            centerY + sampleRadius
        ) {
            for pixelX in max(
                0,
                centerX - sampleRadius
            )...min(
                bitmap.pixelsWide - 1,
                centerX + sampleRadius
            ) {
                guard let color =
                    bitmap.colorAt(
                        x: pixelX,
                        y: pixelY
                    )?.usingColorSpace(.sRGB) else {
                    continue
                }
                let alpha = Double(color.alphaComponent)
                guard alpha > 0.001 else { continue }
                red += Double(color.redComponent) * alpha
                green += Double(color.greenComponent) * alpha
                blue += Double(color.blueComponent) * alpha
                weight += alpha
            }
        }

        guard weight > 0 else { return nil }
        return ImagePixelSample(
            red: red / weight,
            green: green / weight,
            blue: blue / weight
        )
    }
}

/// Samples a small color-managed neighborhood from the displayed preview.
public enum ImageColorSampler {
    public static func sample(
        image: NSImage,
        normalizedX: Double,
        normalizedY: Double,
        radius: Int = 2
    ) -> PointColorSample? {
        guard let rgb = sampleRGB(
            image: image,
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            radius: radius
        ) else {
            return nil
        }
        return PointColorSample(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )
    }

    public static func sampleRGB(
        image: NSImage,
        normalizedX: Double,
        normalizedY: Double,
        radius: Int = 2
    ) -> ImagePixelSample? {
        ImagePixelSampler(image: image)?.sample(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            radius: radius
        )
    }
}
