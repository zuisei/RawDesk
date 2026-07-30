import Foundation

/// A deterministic per-photo correction estimated from high-contrast radial
/// edges. The values use the same controls as the manual optics panel so the
/// result stays non-destructive and renders identically in preview and export.
public struct AutomaticChromaticAberrationCorrection:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public var redCyanShift: Double
    public var blueYellowShift: Double
    public var purpleDefringe: Double
    public var greenDefringe: Double
    public var confidence: Double
    public var sampledEdgeCount: Int
    public var algorithmVersion: Int

    public init(
        redCyanShift: Double = 0,
        blueYellowShift: Double = 0,
        purpleDefringe: Double = 0,
        greenDefringe: Double = 0,
        confidence: Double = 0,
        sampledEdgeCount: Int = 0,
        algorithmVersion: Int = 1
    ) {
        self.redCyanShift = Self.clampSigned(redCyanShift)
        self.blueYellowShift = Self.clampSigned(blueYellowShift)
        self.purpleDefringe = Self.clampUnsigned(purpleDefringe)
        self.greenDefringe = Self.clampUnsigned(greenDefringe)
        self.confidence = min(
            1,
            max(0, confidence.isFinite ? confidence : 0)
        )
        self.sampledEdgeCount = max(0, sampledEdgeCount)
        self.algorithmVersion = max(1, algorithmVersion)
    }

    public var normalized: AutomaticChromaticAberrationCorrection {
        AutomaticChromaticAberrationCorrection(
            redCyanShift: redCyanShift,
            blueYellowShift: blueYellowShift,
            purpleDefringe: purpleDefringe,
            greenDefringe: greenDefringe,
            confidence: confidence,
            sampledEdgeCount: sampledEdgeCount,
            algorithmVersion: algorithmVersion
        )
    }

    public var correctionCount: Int {
        [
            redCyanShift,
            blueYellowShift,
            purpleDefringe,
            greenDefringe
        ].filter { abs($0) > 0.000_1 }.count
    }

    public var confidenceName: String {
        switch confidence {
        case 0.66...: return "High confidence"
        case 0.33...: return "Medium confidence"
        default: return "Low confidence"
        }
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(100, max(-100, value.isFinite ? value : 0))
    }

    private static func clampUnsigned(_ value: Double) -> Double {
        min(100, max(0, value.isFinite ? value : 0))
    }
}

/// Manual optical corrections applied after local retouching and before crop.
///
/// RAWDesk also asks Apple's RAW decoder to apply an embedded or system lens
/// profile whenever one is available. These controls remain useful for lenses
/// without a profile and for fine tuning the automatic result.
public struct OpticsAdjustments: Codable, Equatable, Hashable, Sendable {
    /// Barrel/pincushion correction. Positive values pull bowed edges inward.
    public var distortion: Double
    /// Edge exposure correction in EV-like relative units.
    public var vignette: Double
    /// Radial red/cyan registration correction.
    public var redCyanShift: Double
    /// Radial blue/yellow registration correction.
    public var blueYellowShift: Double
    /// Suppresses purple/magenta fringes along detected edges.
    public var purpleDefringe: Double
    /// Suppresses green fringes along detected edges.
    public var greenDefringe: Double
    /// Optional photo-specific edge analysis applied before manual fine tuning.
    public var automaticChromaticAberration:
        AutomaticChromaticAberrationCorrection?

    public init(
        distortion: Double = 0,
        vignette: Double = 0,
        redCyanShift: Double = 0,
        blueYellowShift: Double = 0,
        purpleDefringe: Double = 0,
        greenDefringe: Double = 0,
        automaticChromaticAberration:
            AutomaticChromaticAberrationCorrection? = nil
    ) {
        self.distortion = Self.clampSigned(distortion)
        self.vignette = Self.clampSigned(vignette)
        self.redCyanShift = Self.clampSigned(redCyanShift)
        self.blueYellowShift = Self.clampSigned(blueYellowShift)
        self.purpleDefringe = Self.clampUnsigned(purpleDefringe)
        self.greenDefringe = Self.clampUnsigned(greenDefringe)
        self.automaticChromaticAberration =
            automaticChromaticAberration?.normalized
    }

    public static let neutral = OpticsAdjustments()

    public var isNeutral: Bool { editCount == 0 }

    public var editCount: Int {
        [
            distortion,
            vignette,
            redCyanShift,
            blueYellowShift,
            purpleDefringe,
            greenDefringe
        ].filter { abs($0) > 0.000_1 }.count
            + (automaticChromaticAberration == nil ? 0 : 1)
    }

    public var normalized: OpticsAdjustments {
        OpticsAdjustments(
            distortion: distortion,
            vignette: vignette,
            redCyanShift: redCyanShift,
            blueYellowShift: blueYellowShift,
            purpleDefringe: purpleDefringe,
            greenDefringe: greenDefringe,
            automaticChromaticAberration:
                automaticChromaticAberration
        )
    }

    /// Combines the analyzed correction with manual fine tuning without
    /// discarding either source. The returned value contains only renderable
    /// controls, preventing recursive application.
    public var renderingCorrection: OpticsAdjustments {
        guard let automaticChromaticAberration else {
            return normalized
        }
        return OpticsAdjustments(
            distortion: distortion,
            vignette: vignette,
            redCyanShift:
                redCyanShift
                + automaticChromaticAberration.redCyanShift,
            blueYellowShift:
                blueYellowShift
                + automaticChromaticAberration.blueYellowShift,
            purpleDefringe:
                purpleDefringe
                + automaticChromaticAberration.purpleDefringe,
            greenDefringe:
                greenDefringe
                + automaticChromaticAberration.greenDefringe
        )
    }

    private enum CodingKeys: String, CodingKey {
        case distortion, vignette, redCyanShift, blueYellowShift
        case purpleDefringe, greenDefringe
        case automaticChromaticAberration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            distortion: try container.decodeIfPresent(Double.self, forKey: .distortion) ?? 0,
            vignette: try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
            redCyanShift: try container.decodeIfPresent(Double.self, forKey: .redCyanShift) ?? 0,
            blueYellowShift: try container.decodeIfPresent(Double.self, forKey: .blueYellowShift) ?? 0,
            purpleDefringe: try container.decodeIfPresent(Double.self, forKey: .purpleDefringe) ?? 0,
            greenDefringe: try container.decodeIfPresent(Double.self, forKey: .greenDefringe) ?? 0,
            automaticChromaticAberration:
                try container.decodeIfPresent(
                    AutomaticChromaticAberrationCorrection.self,
                    forKey: .automaticChromaticAberration
                )
        )
    }

    private static func clampSigned(_ value: Double) -> Double {
        min(100, max(-100, value.isFinite ? value : 0))
    }

    private static func clampUnsigned(_ value: Double) -> Double {
        min(100, max(0, value.isFinite ? value : 0))
    }
}

public enum GuidedUprightOrientation:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case horizontal
    case vertical

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

/// A Lightroom-style perspective guide stored in normalized, top-left image
/// coordinates. Guides are metadata only; the solver writes the resulting
/// straighten and perspective values into the normal geometry controls.
public struct GuidedUprightGuide:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public var id: UUID
    public var orientation: GuidedUprightOrientation
    public var startX: Double
    public var startY: Double
    public var endX: Double
    public var endY: Double
    /// Pixel width divided by pixel height for the canvas where the guide was
    /// drawn. Coordinates stay normalized while angle math remains accurate.
    public var imageAspectRatio: Double

    public init(
        id: UUID = UUID(),
        orientation: GuidedUprightOrientation,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        imageAspectRatio: Double = 1
    ) {
        self.id = id
        self.orientation = orientation
        self.startX = Self.clamp(startX)
        self.startY = Self.clamp(startY)
        self.endX = Self.clamp(endX)
        self.endY = Self.clamp(endY)
        self.imageAspectRatio = Self.aspectRatio(
            imageAspectRatio
        )
    }

    public static func inferred(
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        imageAspectRatio: Double = 1
    ) -> GuidedUprightGuide {
        let aspect = Self.aspectRatio(imageAspectRatio)
        return GuidedUprightGuide(
            orientation:
                abs(endX - startX) * aspect
                    >= abs(endY - startY)
                    ? .horizontal
                    : .vertical,
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY,
            imageAspectRatio: imageAspectRatio
        )
    }

    public var normalized: GuidedUprightGuide {
        GuidedUprightGuide(
            id: id,
            orientation: orientation,
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY,
            imageAspectRatio: imageAspectRatio
        )
    }

    public var length: Double {
        hypot(
            (endX - startX) * imageAspectRatio,
            endY - startY
        )
    }

    public var isEffective: Bool {
        length >= 0.02
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }

    private static func aspectRatio(_ value: Double) -> Double {
        min(
            8,
            max(
                0.125,
                value.isFinite ? value : 1
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, orientation, startX, startY, endX, endY
        case imageAspectRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        self.init(
            id:
                try container.decodeIfPresent(
                    UUID.self,
                    forKey: .id
                ) ?? UUID(),
            orientation: try container.decode(
                GuidedUprightOrientation.self,
                forKey: .orientation
            ),
            startX: try container.decode(
                Double.self,
                forKey: .startX
            ),
            startY: try container.decode(
                Double.self,
                forKey: .startY
            ),
            endX: try container.decode(
                Double.self,
                forKey: .endX
            ),
            endY: try container.decode(
                Double.self,
                forKey: .endY
            ),
            imageAspectRatio:
                try container.decodeIfPresent(
                    Double.self,
                    forKey: .imageAspectRatio
                ) ?? 1
        )
    }
}

public struct GuidedUprightSolution:
    Equatable,
    Hashable,
    Sendable
{
    public var straighten: Double
    public var vertical: Double
    public var horizontal: Double
    public var horizontalGuideCount: Int
    public var verticalGuideCount: Int

    public var guideCount: Int {
        horizontalGuideCount + verticalGuideCount
    }

    public var hasPerspectiveCorrection: Bool {
        abs(vertical) > 0.000_1 || abs(horizontal) > 0.000_1
    }
}

/// Converts two to four user-drawn architectural guides into the existing
/// fixed-canvas geometry controls. The calculation is deterministic and local,
/// so the same guides render identically in previews, exports, versions, and
/// synchronized edits.
public enum GuidedUprightSolver {
    /// Stores the guides and applies their solution to the normal geometry
    /// controls. With fewer than two effective guides, Guided Upright has no
    /// active correction.
    public static func applying(
        _ guides: [GuidedUprightGuide],
        to adjustments: PhotoAdjustments
    ) -> PhotoAdjustments {
        var updated = adjustments
        updated.geometry.guidedUprightGuides = Array(
            guides
                .map(\.normalized)
                .filter(\.isEffective)
                .prefix(4)
        )
        if let solution = solve(updated.geometry.guidedUprightGuides) {
            updated.straighten = solution.straighten
            updated.geometry.vertical = solution.vertical
            updated.geometry.horizontal = solution.horizontal
        } else {
            updated.straighten = 0
            updated.geometry.vertical = 0
            updated.geometry.horizontal = 0
        }
        return updated.normalized
    }

    public static func solve(
        _ guides: [GuidedUprightGuide]
    ) -> GuidedUprightSolution? {
        let normalized = Array(
            guides
                .map(\.normalized)
                .filter(\.isEffective)
                .prefix(4)
        )
        guard normalized.count >= 2 else { return nil }

        let horizontalGuides = normalized.filter {
            $0.orientation == .horizontal
        }
        let verticalGuides = normalized.filter {
            $0.orientation == .vertical
        }

        // Horizontal guides are the strongest indication of level. Vertical
        // guides may intentionally converge because of perspective, so use
        // them for rotation only when no horizontal guide was drawn.
        let levelGuides =
            horizontalGuides.isEmpty
                ? verticalGuides
                : horizontalGuides
        var weightedCorrection = 0.0
        var totalWeight = 0.0
        for guide in levelGuides {
            let correction = rotationCorrection(for: guide)
            let weight = max(0.02, guide.length)
            weightedCorrection += correction * weight
            totalWeight += weight
        }
        let straighten = clamp(
            weightedCorrection / max(0.000_1, totalWeight),
            to: -15...15
        )

        let rotatedVertical = verticalGuides.map {
            rotated($0, byDegrees: straighten)
        }
        let rotatedHorizontal = horizontalGuides.map {
            rotated($0, byDegrees: straighten)
        }

        let vertical = perspectiveValue(
            for: rotatedVertical,
            sortingByHorizontalPosition: true
        )
        let horizontal = perspectiveValue(
            for: rotatedHorizontal,
            sortingByHorizontalPosition: false
        )

        return GuidedUprightSolution(
            straighten: straighten,
            vertical: vertical,
            horizontal: horizontal,
            horizontalGuideCount: horizontalGuides.count,
            verticalGuideCount: verticalGuides.count
        )
    }

    private struct RotatedGuide {
        var startX: Double
        var startY: Double
        var endX: Double
        var endY: Double
        var imageAspectRatio: Double

        var midX: Double { (startX + endX) / 2 }
        var midY: Double { (startY + endY) / 2 }

        var verticalSlope: Double {
            ((endX - startX) * imageAspectRatio)
                / signedMinimum(endY - startY)
        }

        var horizontalSlope: Double {
            (endY - startY)
                / signedMinimum(
                    (endX - startX) * imageAspectRatio
                )
        }

        private func signedMinimum(_ value: Double) -> Double {
            if abs(value) >= 0.000_1 { return value }
            return value < 0 ? -0.000_1 : 0.000_1
        }
    }

    private static func rotationCorrection(
        for guide: GuidedUprightGuide
    ) -> Double {
        var dx =
            (guide.endX - guide.startX)
            * guide.imageAspectRatio
        var dy = guide.endY - guide.startY
        switch guide.orientation {
        case .horizontal:
            if dx < 0 {
                dx = -dx
                dy = -dy
            }
            return -atan2(dy, dx) * 180 / .pi
        case .vertical:
            if dy < 0 {
                dx = -dx
                dy = -dy
            }
            return atan2(dx, dy) * 180 / .pi
        }
    }

    private static func rotated(
        _ guide: GuidedUprightGuide,
        byDegrees degrees: Double
    ) -> RotatedGuide {
        let radians = degrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)

        func point(_ x: Double, _ y: Double) -> (Double, Double) {
            let centeredX =
                (x - 0.5)
                * guide.imageAspectRatio
            let centeredY = y - 0.5
            return (
                (
                    centeredX * cosine
                    - centeredY * sine
                ) / guide.imageAspectRatio + 0.5,
                centeredX * sine + centeredY * cosine + 0.5
            )
        }

        let start = point(guide.startX, guide.startY)
        let end = point(guide.endX, guide.endY)
        return RotatedGuide(
            startX: start.0,
            startY: start.1,
            endX: end.0,
            endY: end.1,
            imageAspectRatio: guide.imageAspectRatio
        )
    }

    private static func perspectiveValue(
        for guides: [RotatedGuide],
        sortingByHorizontalPosition: Bool
    ) -> Double {
        guard guides.count >= 2 else { return 0 }
        let sorted = guides.sorted {
            sortingByHorizontalPosition
                ? $0.midX < $1.midX
                : $0.midY < $1.midY
        }
        guard let first = sorted.first,
              let last = sorted.last else {
            return 0
        }
        let slopeDifference: Double
        if sortingByHorizontalPosition {
            slopeDifference =
                last.verticalSlope
                - first.verticalSlope
        } else {
            slopeDifference =
                last.horizontalSlope
                - first.horizontalSlope
        }
        return clamp(
            slopeDifference * 140,
            to: -100...100
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>
    ) -> Double {
        min(
            range.upperBound,
            max(
                range.lowerBound,
                value.isFinite ? value : 0
            )
        )
    }
}

/// Manual perspective and framing controls that preserve a fixed output canvas.
public struct GeometryAdjustments: Codable, Equatable, Hashable, Sendable {
    public var vertical: Double
    public var horizontal: Double
    public var aspect: Double
    /// Percentage scale. 100 preserves the current size.
    public var scale: Double
    public var offsetX: Double
    public var offsetY: Double
    public var constrainCrop: Bool
    public var guidedUprightGuides: [GuidedUprightGuide]

    public init(
        vertical: Double = 0,
        horizontal: Double = 0,
        aspect: Double = 0,
        scale: Double = 100,
        offsetX: Double = 0,
        offsetY: Double = 0,
        constrainCrop: Bool = true,
        guidedUprightGuides: [GuidedUprightGuide] = []
    ) {
        self.vertical = Self.clampSigned(vertical)
        self.horizontal = Self.clampSigned(horizontal)
        self.aspect = Self.clampSigned(aspect)
        self.scale = Self.clamp(scale, to: 50...200, fallback: 100)
        self.offsetX = Self.clampSigned(offsetX)
        self.offsetY = Self.clampSigned(offsetY)
        self.constrainCrop = constrainCrop
        self.guidedUprightGuides = Array(
            guidedUprightGuides
                .map(\.normalized)
                .filter(\.isEffective)
                .prefix(4)
        )
    }

    public static let neutral = GeometryAdjustments()

    public var isNeutral: Bool { editCount == 0 }

    public var editCount: Int {
        [
            vertical,
            horizontal,
            aspect,
            offsetX,
            offsetY
        ].filter { abs($0) > 0.000_1 }.count
            + (abs(scale - 100) > 0.000_1 ? 1 : 0)
            + (!constrainCrop
                && (abs(vertical) > 0.000_1 || abs(horizontal) > 0.000_1)
                ? 1
                : 0)
            + (guidedUprightGuides.isEmpty ? 0 : 1)
    }

    public var normalized: GeometryAdjustments {
        GeometryAdjustments(
            vertical: vertical,
            horizontal: horizontal,
            aspect: aspect,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            constrainCrop: constrainCrop,
            guidedUprightGuides: guidedUprightGuides
        )
    }

    private enum CodingKeys: String, CodingKey {
        case vertical, horizontal, aspect, scale, offsetX, offsetY, constrainCrop
        case guidedUprightGuides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            vertical: try container.decodeIfPresent(Double.self, forKey: .vertical) ?? 0,
            horizontal: try container.decodeIfPresent(Double.self, forKey: .horizontal) ?? 0,
            aspect: try container.decodeIfPresent(Double.self, forKey: .aspect) ?? 0,
            scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? 100,
            offsetX: try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0,
            offsetY: try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0,
            constrainCrop: try container.decodeIfPresent(
                Bool.self,
                forKey: .constrainCrop
            ) ?? true,
            guidedUprightGuides: try container.decodeIfPresent(
                [GuidedUprightGuide].self,
                forKey: .guidedUprightGuides
            ) ?? []
        )
    }

    private static func clampSigned(_ value: Double) -> Double {
        clamp(value, to: -100...100, fallback: 0)
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
    }
}
