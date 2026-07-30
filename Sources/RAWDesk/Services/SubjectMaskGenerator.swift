import Foundation
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Produces a compact, reusable foreground mask with Apple's on-device Vision model.
public enum SubjectMaskGenerator {
    public enum GenerationError: Error, LocalizedError {
        case imageHasNoBitmap
        case noSubjectDetected
        case noObjectAtPoint
        case unsupportedInstanceMaskFormat
        case maskRenderingFailed

        public var errorDescription: String? {
            switch self {
            case .imageHasNoBitmap:
                return "The photo could not be prepared for subject selection."
            case .noSubjectDetected:
                return "No clear foreground subject was detected in this photo."
            case .noObjectAtPoint:
                return "No selectable object was found at that point. Click directly on a foreground object."
            case .unsupportedInstanceMaskFormat:
                return "The object-selection result uses an unsupported pixel format."
            case .maskRenderingFailed:
                return "The selected subject mask could not be rendered."
            }
        }
    }

    private static let analysisLimit: CGFloat = 1_024
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            ?? CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB(),
        .cacheIntermediates: false
    ])

    /// Generates an 8-bit grayscale PNG whose aspect ratio matches the source.
    /// The stored mask is intentionally limited to 1024 px on its longest edge;
    /// the non-destructive renderer scales it to preview or export resolution.
    public static func generateMaskPNG(from image: NSImage) throws -> Data {
        let (observation, handler) = try analyze(image)
        return try generateMaskPNG(
            observation: observation,
            handler: handler,
            instances: observation.allInstances
        )
    }

    /// Generates a mask for the single foreground instance under an on-photo click.
    ///
    /// Coordinates use the same top-left, normalized space as the SwiftUI preview.
    /// Vision's instance mask is a one-channel UInt8 label map where zero is the
    /// background and every non-zero byte identifies one detected object.
    public static func generateObjectMaskPNG(
        from image: NSImage,
        normalizedX: Double,
        normalizedY: Double
    ) throws -> Data {
        let (observation, handler) = try analyze(image)
        guard let instance = try instanceIndex(
            in: observation.instanceMask,
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            validInstances: observation.allInstances
        ) else {
            throw GenerationError.noObjectAtPoint
        }
        return try generateMaskPNG(
            observation: observation,
            handler: handler,
            instances: IndexSet(integer: instance)
        )
    }

    /// Reads an instance label from Vision's compact hit-test map.
    ///
    /// This is internal so deterministic pixel-buffer tests can guard coordinate
    /// orientation and row-padding behavior without invoking the Vision model.
    static func instanceIndex(
        in instanceMask: CVPixelBuffer,
        normalizedX: Double,
        normalizedY: Double,
        validInstances: IndexSet
    ) throws -> Int? {
        guard CVPixelBufferGetPixelFormatType(instanceMask)
                == kCVPixelFormatType_OneComponent8 else {
            throw GenerationError.unsupportedInstanceMaskFormat
        }

        let width = CVPixelBufferGetWidth(instanceMask)
        let height = CVPixelBufferGetHeight(instanceMask)
        guard width > 0, height > 0 else {
            throw GenerationError.maskRenderingFailed
        }

        let x = min(1, max(0, normalizedX.isFinite ? normalizedX : 0.5))
        let y = min(1, max(0, normalizedY.isFinite ? normalizedY : 0.5))
        let imagePoint = VNImagePointForNormalizedPoint(
            CGPoint(x: x, y: y),
            width,
            height
        )
        let pixelX = min(width - 1, max(0, Int(imagePoint.x)))
        let pixelY = min(height - 1, max(0, Int(imagePoint.y)))

        guard CVPixelBufferLockBaseAddress(instanceMask, .readOnly)
                == kCVReturnSuccess else {
            throw GenerationError.maskRenderingFailed
        }
        defer {
            CVPixelBufferUnlockBaseAddress(instanceMask, .readOnly)
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(instanceMask) else {
            throw GenerationError.maskRenderingFailed
        }

        let offset = pixelY * CVPixelBufferGetBytesPerRow(instanceMask) + pixelX
        let label = Int(
            baseAddress
                .advanced(by: offset)
                .assumingMemoryBound(to: UInt8.self)
                .pointee
        )
        guard label != 0, validInstances.contains(label) else { return nil }
        return label
    }

    private static func analyze(
        _ image: NSImage
    ) throws -> (VNInstanceMaskObservation, VNImageRequestHandler) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw GenerationError.imageHasNoBitmap
        }

        let source = CIImage(cgImage: cgImage)
        let normalized = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.minX,
                y: -source.extent.minY
            )
        )
        let longestEdge = max(normalized.extent.width, normalized.extent.height)
        let scale = min(1, analysisLimit / max(1, longestEdge))
        let analysisImage = normalized.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        guard let analysisCGImage = context.createCGImage(
            analysisImage,
            from: analysisImage.extent
        ) else {
            throw GenerationError.imageHasNoBitmap
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: analysisCGImage,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw GenerationError.noSubjectDetected
        }
        return (observation, handler)
    }

    private static func generateMaskPNG(
        observation: VNInstanceMaskObservation,
        handler: VNImageRequestHandler,
        instances: IndexSet
    ) throws -> Data {
        let pixelBuffer = try observation.generateScaledMaskForImage(
            forInstances: instances,
            from: handler
        )
        let mask = CIImage(cvPixelBuffer: pixelBuffer)
        let gray = CGColorSpaceCreateDeviceGray()
        guard let maskCGImage = context.createCGImage(
            mask,
            from: mask.extent,
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
        CGImageDestinationAddImage(destination, maskCGImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GenerationError.maskRenderingFailed
        }
        return data as Data
    }
}
