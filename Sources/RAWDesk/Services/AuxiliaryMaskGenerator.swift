import Foundation
import AppKit
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Builds reusable grayscale masks from auxiliary photo data or local analysis.
///
/// Image I/O exposes camera-provided sky mattes and depth/disparity maps without
/// uploading the photo. Sky selection prefers that authored data and falls back
/// to a conservative, top-connected color segmentation for RAW files that have
/// no semantic matte.
public enum AuxiliaryMaskGenerator {
    public enum SkySource: String, Sendable {
        case embeddedMatte
        case localEstimate
    }

    public struct SkyResult: Sendable {
        public let pngData: Data
        public let source: SkySource

        public init(pngData: Data, source: SkySource) {
            self.pngData = pngData
            self.source = source
        }
    }

    public enum GenerationError: Error, LocalizedError {
        case imageHasNoBitmap
        case noSkyDetected
        case noDepthData
        case depthDataUnreadable
        case maskRenderingFailed

        public var errorDescription: String? {
            switch self {
            case .imageHasNoBitmap:
                return "The photo could not be prepared for mask analysis."
            case .noSkyDetected:
                return "No clear sky connected to the photo edge was detected."
            case .noDepthData:
                return "This photo has no embedded depth or disparity map."
            case .depthDataUnreadable:
                return "The embedded depth map could not be read."
            case .maskRenderingFailed:
                return "The generated mask could not be rendered."
            }
        }
    }

    private static let analysisLimit: CGFloat = 1_024
    private static let outputColorSpace = CGColorSpace(
        name: CGColorSpace.sRGB
    ) ?? CGColorSpaceCreateDeviceRGB()
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(
            name: CGColorSpace.extendedLinearSRGB
        ) ?? CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: outputColorSpace,
        .cacheIntermediates: false
    ])

    public static func generateSkyMaskPNG(
        from orientedImage: NSImage,
        assetURL: URL?,
        rotationDegrees: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) throws -> SkyResult {
        if let assetURL {
            do {
                if let embedded = try embeddedSkyMattePNG(
                    from: assetURL,
                    rotationDegrees: rotationDegrees,
                    flipHorizontal: flipHorizontal,
                    flipVertical: flipVertical
                ) {
                    return SkyResult(
                        pngData: embedded,
                        source: .embeddedMatte
                    )
                }
            } catch {
                // A malformed authored matte should not prevent the local
                // on-device estimate from being used as a recovery path.
            }
        }

        let rgba = try topLeftRGBA(from: orientedImage)
        let foreground = estimatedForegroundBytes(
            from: orientedImage,
            width: rgba.width,
            height: rgba.height
        )
        let mask = estimatedSkyMaskBytes(
            rgba: rgba.bytes,
            width: rgba.width,
            height: rgba.height,
            foregroundMask: foreground
        )
        let selectedPixels = mask.reduce(into: 0) { count, value in
            if value > 32 { count += 1 }
        }
        guard selectedPixels >= max(16, mask.count / 200) else {
            throw GenerationError.noSkyDetected
        }
        return SkyResult(
            pngData: try grayPNG(
                bytes: mask,
                width: rgba.width,
                height: rgba.height
            ),
            source: .localEstimate
        )
    }

    public static func generateDepthMapPNG(
        from assetURL: URL,
        rotationDegrees: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(assetURL as CFURL, nil) else {
            throw GenerationError.noDepthData
        }

        let auxiliaryTypes = [
            kCGImageAuxiliaryDataTypeDepth,
            kCGImageAuxiliaryDataTypeDisparity
        ]
        var depthData: AVDepthData?
        for type in auxiliaryTypes {
            guard let dictionary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source,
                0,
                type
            ) as? [AnyHashable: Any] else {
                continue
            }
            depthData = try AVDepthData(
                fromDictionaryRepresentation: dictionary
            )
            break
        }
        guard let depthData else {
            throw GenerationError.noDepthData
        }

        let exifOrientation = imageOrientation(in: source)
        let oriented = depthData.applyingExifOrientation(exifOrientation)
        let converted = oriented.converting(
            toDepthDataType: kCVPixelFormatType_DepthFloat32
        )
        let map = converted.depthDataMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0,
              CVPixelBufferGetPixelFormatType(map)
                == kCVPixelFormatType_DepthFloat32 else {
            throw GenerationError.depthDataUnreadable
        }

        guard CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else {
            throw GenerationError.depthDataUnreadable
        }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(map) else {
            throw GenerationError.depthDataUnreadable
        }

        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var values = [Float](repeating: .nan, count: width * height)
        for y in 0..<height {
            let row = baseAddress
                .advanced(by: y * rowBytes)
                .assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                values[y * width + x] = row[x]
            }
        }
        let normalized = normalizedDepthBytes(values)
        let image = try grayCIImage(
            bytes: normalized,
            width: width,
            height: height
        )
        let transformed = applyingOrientation(
            to: image,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
        return try pngData(from: transformed)
    }

    /// Converts metric depth to a robust 0...255 near-to-far map.
    ///
    /// Invalid samples become 255 so the default near-half range does not
    /// accidentally include missing depth. Percentile clipping prevents one
    /// extreme sample from flattening the useful depth range.
    static func normalizedDepthBytes(_ values: [Float]) -> [UInt8] {
        var finite = values.filter { $0.isFinite && $0 > 0 }
        guard finite.count >= 2 else {
            return [UInt8](repeating: 255, count: values.count)
        }
        finite.sort()
        let last = finite.count - 1
        let lower = finite[Int((Double(last) * 0.02).rounded(.down))]
        let upper = finite[Int((Double(last) * 0.98).rounded(.down))]
        let span = max(Float.ulpOfOne, upper - lower)

        return values.map { value in
            guard value.isFinite, value > 0 else { return 255 }
            let unit = min(1, max(0, (value - lower) / span))
            return UInt8((unit * 255).rounded())
        }
    }

    /// Conservative sky segmentation used when a photo has no authored matte.
    ///
    /// The selection must be connected to the top or upper side edge, which
    /// prevents blue clothing and reflections in the middle of a photo from
    /// becoming sky. A foreground mask and color discontinuities stop the
    /// region at prominent subjects, trees, and architecture.
    static func estimatedSkyMaskBytes(
        rgba: [UInt8],
        width: Int,
        height: Int,
        foregroundMask: [UInt8]? = nil
    ) -> [UInt8] {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else {
            return []
        }
        let pixelCount = width * height
        let foreground = foregroundMask?.count == pixelCount
            ? foregroundMask
            : nil
        var score = [Float](repeating: 0, count: pixelCount)
        var candidate = [Bool](repeating: false, count: pixelCount)

        for y in 0..<height {
            let yUnit = height <= 1 ? 0 : Float(y) / Float(height - 1)
            let topPrior = 1 - yUnit
            for x in 0..<width {
                let index = y * width + x
                let byteIndex = index * 4
                let r = Float(rgba[byteIndex]) / 255
                let g = Float(rgba[byteIndex + 1]) / 255
                let b = Float(rgba[byteIndex + 2]) / 255
                let maximum = max(r, max(g, b))
                let minimum = min(r, min(g, b))
                let saturation = maximum <= 0.000_1
                    ? 0
                    : (maximum - minimum) / maximum
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

                let blueDominance = b - max(r, g)
                let blue = smoothStep(-0.035, 0.13, blueDominance)
                    * smoothStep(0.025, 0.28, saturation)
                    * smoothStep(0.12, 0.62, luminance)
                let blueGray = smoothStep(-0.02, 0.08, b - r)
                    * smoothStep(-0.025, 0.08, b - g)
                    * smoothStep(0.32, 0.82, luminance)
                let neutralCloud = smoothStep(0.5, 0.9, luminance)
                    * (1 - smoothStep(0.18, 0.52, saturation))

                let greenPenalty = smoothStep(0.025, 0.17, g - max(r, b))
                let warmPenalty = smoothStep(0.04, 0.22, r - b)
                let darkPenalty = 1 - smoothStep(0.1, 0.28, luminance)
                let foregroundValue = foreground.map {
                    Float($0[index]) / 255
                } ?? 0
                let raw = max(blue, max(blueGray * 0.82, neutralCloud * 0.78))
                    * (0.76 + 0.24 * topPrior)
                    * (1 - 0.92 * greenPenalty)
                    * (1 - 0.88 * warmPenalty)
                    * (1 - 0.9 * darkPenalty)
                    * (1 - 0.96 * foregroundValue)
                score[index] = raw
                candidate[index] = raw >= 0.26
                    && luminance >= 0.14
                    && foregroundValue < 0.58
            }
        }

        var selected = [Bool](repeating: false, count: pixelCount)
        var queue = [Int]()
        queue.reserveCapacity(pixelCount / 3)
        let seedRows = max(1, height / 24)
        let sideLimit = max(seedRows, Int(Double(height) * 0.62))

        func addSeed(_ index: Int) {
            guard candidate[index], score[index] >= 0.3, !selected[index] else {
                return
            }
            selected[index] = true
            queue.append(index)
        }

        for y in 0..<seedRows {
            for x in 0..<width {
                addSeed(y * width + x)
            }
        }
        if width > 1 {
            for y in 0..<sideLimit {
                addSeed(y * width)
                addSeed(y * width + width - 1)
            }
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            let neighbors = [
                x > 0 ? index - 1 : -1,
                x + 1 < width ? index + 1 : -1,
                y > 0 ? index - width : -1,
                y + 1 < height ? index + width : -1
            ]
            for neighbor in neighbors where neighbor >= 0 {
                guard !selected[neighbor], candidate[neighbor] else { continue }
                let distance = rgbDistance(
                    rgba: rgba,
                    first: index,
                    second: neighbor
                )
                if distance > 0.34, score[neighbor] < 0.62 {
                    continue
                }
                selected[neighbor] = true
                queue.append(neighbor)
            }
        }

        var binary = selected.map { $0 ? UInt8(255) : UInt8(0) }
        binary = closing(binary, width: width, height: height, radius: 1)
        let blurRadius = max(1, min(4, min(width, height) / 240))
        var softened = boxBlur(
            binary,
            width: width,
            height: height,
            radius: blurRadius
        )
        if let foreground {
            for index in 0..<pixelCount {
                let keep = 1 - Float(foreground[index]) / 255
                softened[index] = UInt8(
                    min(255, max(0, Float(softened[index]) * keep)).rounded()
                )
            }
        }
        return softened
    }

    private static func embeddedSkyMattePNG(
        from url: URL,
        rotationDegrees: Int,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) throws -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let dictionary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                  source,
                  0,
                  kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte
              ) as? [AnyHashable: Any] else {
            return nil
        }

        let matte = try AVSemanticSegmentationMatte(
            fromImageSourceAuxiliaryDataType:
                kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte,
            dictionaryRepresentation: dictionary
        )
        let oriented = matte.applyingExifOrientation(
            imageOrientation(in: source)
        )
        let image = CIImage(cvPixelBuffer: oriented.mattingImage)
        let transformed = applyingOrientation(
            to: image,
            rotationDegrees: rotationDegrees,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
        return try pngData(from: transformed)
    }

    private static func imageOrientation(
        in source: CGImageSource
    ) -> CGImagePropertyOrientation {
        let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?
            .uint32Value ?? 1
        return CGImagePropertyOrientation(rawValue: raw) ?? .up
    }

    private static func estimatedForegroundBytes(
        from image: NSImage,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        guard let data = try? SubjectMaskGenerator.generateMaskPNG(from: image),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let mask = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rgba = try? topLeftRGBA(
                  from: mask,
                  width: width,
                  height: height
              ) else {
            return nil
        }
        return stride(from: 0, to: rgba.count, by: 4).map { rgba[$0] }
    }

    static func topLeftRGBA(
        from image: NSImage
    ) throws -> (bytes: [UInt8], width: Int, height: Int) {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            throw GenerationError.imageHasNoBitmap
        }
        let longest = CGFloat(max(cgImage.width, cgImage.height))
        let scale = min(1, analysisLimit / max(1, longest))
        let width = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
        return (
            try topLeftRGBA(from: cgImage, width: width, height: height),
            width,
            height
        )
    }

    private static func topLeftRGBA(
        from image: CGImage,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let created = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: outputColorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard created else {
            throw GenerationError.maskRenderingFailed
        }
        let rowBytes = width * 4
        if height > 1 {
            for topRow in 0..<(height / 2) {
                let bottomRow = height - 1 - topRow
                let topOffset = topRow * rowBytes
                let bottomOffset = bottomRow * rowBytes
                for byte in 0..<rowBytes {
                    bytes.swapAt(topOffset + byte, bottomOffset + byte)
                }
            }
        }
        return bytes
    }

    private static func grayCIImage(
        bytes: [UInt8],
        width: Int,
        height: Int
    ) throws -> CIImage {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.none.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw GenerationError.maskRenderingFailed
        }
        return CIImage(cgImage: image)
    }

    private static func grayPNG(
        bytes: [UInt8],
        width: Int,
        height: Int
    ) throws -> Data {
        try pngData(from: grayCIImage(bytes: bytes, width: width, height: height))
    }

    private static func pngData(from source: CIImage) throws -> Data {
        let normalized = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.minX,
                y: -source.extent.minY
            )
        )
        let longest = max(normalized.extent.width, normalized.extent.height)
        let scale = min(1, analysisLimit / max(1, longest))
        let image = normalized.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let gray = CGColorSpaceCreateDeviceGray()
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent,
            format: .L8,
            colorSpace: gray
        ) else {
            throw GenerationError.maskRenderingFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw GenerationError.maskRenderingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GenerationError.maskRenderingFailed
        }
        return data as Data
    }

    private static func applyingOrientation(
        to image: CIImage,
        rotationDegrees: Int,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) -> CIImage {
        guard rotationDegrees != 0 || flipHorizontal || flipVertical else {
            return image
        }
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let radians = -CGFloat(rotationDegrees) * .pi / 180
        let transform = CGAffineTransform.identity
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: radians)
            .scaledBy(
                x: flipHorizontal ? -1 : 1,
                y: flipVertical ? -1 : 1
            )
            .translatedBy(x: -center.x, y: -center.y)
        let transformed = image.transformed(by: transform)
        return transformed.transformed(
            by: CGAffineTransform(
                translationX: -transformed.extent.minX,
                y: -transformed.extent.minY
            )
        )
    }

    private static func smoothStep(
        _ edge0: Float,
        _ edge1: Float,
        _ value: Float
    ) -> Float {
        guard edge1 > edge0 else { return value >= edge1 ? 1 : 0 }
        let unit = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return unit * unit * (3 - 2 * unit)
    }

    private static func rgbDistance(
        rgba: [UInt8],
        first: Int,
        second: Int
    ) -> Float {
        let firstByte = first * 4
        let secondByte = second * 4
        let red = abs(
            Float(rgba[firstByte]) - Float(rgba[secondByte])
        ) / 255
        let green = abs(
            Float(rgba[firstByte + 1]) - Float(rgba[secondByte + 1])
        ) / 255
        let blue = abs(
            Float(rgba[firstByte + 2]) - Float(rgba[secondByte + 2])
        ) / 255
        return red * 0.3 + green * 0.4 + blue * 0.3
    }

    private static func closing(
        _ input: [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) -> [UInt8] {
        guard radius > 0 else { return input }
        var dilated = [UInt8](repeating: 0, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                var maximum: UInt8 = 0
                for sampleY in max(0, y - radius)...min(height - 1, y + radius) {
                    for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                        maximum = max(maximum, input[sampleY * width + sampleX])
                    }
                }
                dilated[y * width + x] = maximum
            }
        }

        var eroded = [UInt8](repeating: 255, count: input.count)
        for y in 0..<height {
            for x in 0..<width {
                var minimum: UInt8 = 255
                for sampleY in max(0, y - radius)...min(height - 1, y + radius) {
                    for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                        minimum = min(minimum, dilated[sampleY * width + sampleX])
                    }
                }
                eroded[y * width + x] = minimum
            }
        }
        return eroded
    }

    private static func boxBlur(
        _ input: [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) -> [UInt8] {
        guard radius > 0 else { return input }
        var horizontal = [UInt16](repeating: 0, count: input.count)
        let diameter = radius * 2 + 1

        for y in 0..<height {
            var sum = 0
            for x in -radius...radius {
                let sampleX = min(width - 1, max(0, x))
                sum += Int(input[y * width + sampleX])
            }
            for x in 0..<width {
                horizontal[y * width + x] = UInt16(sum / diameter)
                let leaving = min(width - 1, max(0, x - radius))
                let entering = min(width - 1, max(0, x + radius + 1))
                sum -= Int(input[y * width + leaving])
                sum += Int(input[y * width + entering])
            }
        }

        var output = [UInt8](repeating: 0, count: input.count)
        for x in 0..<width {
            var sum = 0
            for y in -radius...radius {
                let sampleY = min(height - 1, max(0, y))
                sum += Int(horizontal[sampleY * width + x])
            }
            for y in 0..<height {
                output[y * width + x] = UInt8(sum / diameter)
                let leaving = min(height - 1, max(0, y - radius))
                let entering = min(height - 1, max(0, y + radius + 1))
                sum -= Int(horizontal[leaving * width + x])
                sum += Int(horizontal[entering * width + x])
            }
        }
        return output
    }
}
