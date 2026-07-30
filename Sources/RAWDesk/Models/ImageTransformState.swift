import Foundation
import CoreGraphics

public struct ImageTransformState: Equatable, Sendable {
    public var rotationDegrees: Int      // 0, 90, 180, 270
    public var flipHorizontal: Bool
    public var flipVertical: Bool
    public var zoom: CGFloat              // 1.0 = fit to window
    public var fitToWindow: Bool

    public init(
        rotationDegrees: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        zoom: CGFloat = 1.0,
        fitToWindow: Bool = true
    ) {
        self.rotationDegrees = ((rotationDegrees % 360) + 360) % 360
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.zoom = zoom
        self.fitToWindow = fitToWindow
    }

    public mutating func rotateRight() {
        rotationDegrees = (rotationDegrees + 90) % 360
    }
    public mutating func rotateLeft() {
        rotationDegrees = (rotationDegrees + 270) % 360
    }
    public mutating func toggleFlipHorizontal() { flipHorizontal.toggle() }
    public mutating func toggleFlipVertical() { flipVertical.toggle() }
    public mutating func zoomIn()  { fitToWindow = false; zoom = min(zoom * 1.25, 16.0) }
    public mutating func zoomOut() { fitToWindow = false; zoom = max(zoom / 1.25, 0.05) }
    public mutating func actualSize() { fitToWindow = false; zoom = 1.0 }
    public mutating func fit() { fitToWindow = true; zoom = 1.0 }

    public static let identity = ImageTransformState()
}
