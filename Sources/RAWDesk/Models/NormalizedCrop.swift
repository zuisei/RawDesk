import Foundation

public enum CropHandle: String, CaseIterable, Identifiable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var id: String { rawValue }
}

/// A crop rectangle expressed in normalized image coordinates.
/// The origin is top-left to match what users see in the preview.
public struct NormalizedCrop: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        let safeWidth = Self.clamp(width, 0.02...1)
        let safeHeight = Self.clamp(height, 0.02...1)
        self.width = safeWidth
        self.height = safeHeight
        self.x = Self.clamp(x, 0...(1 - safeWidth))
        self.y = Self.clamp(y, 0...(1 - safeHeight))
    }

    public static let fullFrame = NormalizedCrop()

    public var isFullFrame: Bool {
        abs(x) < 0.000_1
            && abs(y) < 0.000_1
            && abs(width - 1) < 0.000_1
            && abs(height - 1) < 0.000_1
    }

    public var normalized: NormalizedCrop {
        NormalizedCrop(x: x, y: y, width: width, height: height)
    }

    public func positioned(horizontal: Double? = nil, vertical: Double? = nil) -> NormalizedCrop {
        let availableX = max(0, 1 - width)
        let availableY = max(0, 1 - height)
        return NormalizedCrop(
            x: horizontal.map { Self.clamp($0, 0...1) * availableX } ?? x,
            y: vertical.map { Self.clamp($0, 0...1) * availableY } ?? y,
            width: width,
            height: height
        )
    }

    public func translated(deltaX: Double, deltaY: Double) -> NormalizedCrop {
        NormalizedCrop(
            x: x + deltaX,
            y: y + deltaY,
            width: width,
            height: height
        )
    }

    public func resized(
        from handle: CropHandle,
        deltaX: Double,
        deltaY: Double,
        minimumSize: Double = 0.02
    ) -> NormalizedCrop {
        let minimum = Self.clamp(minimumSize, 0.02...1)
        var left = x
        var top = y
        var right = x + width
        var bottom = y + height

        switch handle {
        case .topLeft:
            left = min(right - minimum, max(0, left + deltaX))
            top = min(bottom - minimum, max(0, top + deltaY))
        case .topRight:
            right = max(left + minimum, min(1, right + deltaX))
            top = min(bottom - minimum, max(0, top + deltaY))
        case .bottomLeft:
            left = min(right - minimum, max(0, left + deltaX))
            bottom = max(top + minimum, min(1, bottom + deltaY))
        case .bottomRight:
            right = max(left + minimum, min(1, right + deltaX))
            bottom = max(top + minimum, min(1, bottom + deltaY))
        }

        return NormalizedCrop(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }

    public var horizontalPosition: Double {
        let available = 1 - width
        return available > 0.000_1 ? x / available : 0.5
    }

    public var verticalPosition: Double {
        let available = 1 - height
        return available > 0.000_1 ? y / available : 0.5
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }
}

public enum CropAspectPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .original: return "Original"
        case .square: return "1 × 1"
        case .fourThree: return "4 × 3"
        case .threeTwo: return "3 × 2"
        case .sixteenNine: return "16 × 9"
        }
    }

    public func crop(forSourceAspect sourceAspect: Double) -> NormalizedCrop {
        guard self != .original, sourceAspect > 0 else { return .fullFrame }
        let landscapeRatio: Double
        switch self {
        case .original: return .fullFrame
        case .square: landscapeRatio = 1
        case .fourThree: landscapeRatio = 4.0 / 3.0
        case .threeTwo: landscapeRatio = 3.0 / 2.0
        case .sixteenNine: landscapeRatio = 16.0 / 9.0
        }
        let targetAspect = sourceAspect >= 1 ? landscapeRatio : 1 / landscapeRatio

        if targetAspect < sourceAspect {
            let width = targetAspect / sourceAspect
            return NormalizedCrop(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else {
            let height = sourceAspect / targetAspect
            return NormalizedCrop(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
    }
}
