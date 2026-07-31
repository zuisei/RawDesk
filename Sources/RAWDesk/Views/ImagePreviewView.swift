import SwiftUI
import AppKit

struct ImageViewportMapper {
    static func normalizedPoint(
        location: CGPoint,
        containerSize: CGSize,
        imageSize: CGSize,
        transform: ImageTransformState,
        panOffset: CGSize = .zero
    ) -> CGPoint? {
        guard containerSize.width > 0,
              containerSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }

        let isQuarterTurn =
            transform.rotationDegrees == 90
            || transform.rotationDegrees == 270
        let displaySize = isQuarterTurn
            ? CGSize(
                width: imageSize.height,
                height: imageSize.width
            )
            : imageSize
        let fitScale = min(
            containerSize.width / displaySize.width,
            containerSize.height / displaySize.height
        )
        let scale =
            transform.fitToWindow
            ? fitScale
            : transform.zoom
        guard scale > 0 else { return nil }

        let appliedPan =
            transform.fitToWindow
            ? CGSize.zero
            : panOffset
        let centeredX =
            location.x
            - containerSize.width / 2
            - appliedPan.width
        let centeredY =
            location.y
            - containerSize.height / 2
            - appliedPan.height
        let angle =
            CGFloat(transform.rotationDegrees)
            * .pi / 180
        let cosine = cos(angle)
        let sine = sin(angle)
        let unrotatedX =
            cosine * centeredX
            + sine * centeredY
        let unrotatedY =
            -sine * centeredX
            + cosine * centeredY
        let horizontalScale =
            scale * (transform.flipHorizontal ? -1 : 1)
        let verticalScale =
            scale * (transform.flipVertical ? -1 : 1)
        let imageX =
            unrotatedX / horizontalScale
            + imageSize.width / 2
        let imageY =
            unrotatedY / verticalScale
            + imageSize.height / 2
        let edgeTolerance =
            max(imageSize.width, imageSize.height)
            * 0.000_000_1
        guard imageX >= -edgeTolerance,
              imageX <= imageSize.width + edgeTolerance,
              imageY >= -edgeTolerance,
              imageY <= imageSize.height + edgeTolerance else {
            return nil
        }
        return CGPoint(
            x: min(
                1,
                max(0, imageX / imageSize.width)
            ),
            y: min(
                1,
                max(0, imageY / imageSize.height)
            )
        )
    }
}

struct ImagePreviewView: View {
    @ObservedObject var viewer: PhotoViewerViewModel
    let asset: PhotoAsset?
    let onCropChange: (NormalizedCrop) -> Void
    let onGuidedUprightGuidesChange:
        ([GuidedUprightGuide]) -> Void
    let onSpotRemovalChange: (SpotRemoval) -> Void
    let onBrushStrokeCommit: (LocalAdjustmentMask.ID, BrushStroke) -> Void
    let onObjectMaskPoint: (Double, Double) -> Void
    let onPointColorSample: (PointColorSample) -> Void
    let onMaskColorRangeSample: (PointColorSample) -> Void
    var onPixelHover: ((ImagePixelSample?) -> Void)? = nil
    var showsInlineToolCompletion = true
    var onCancelActiveTool: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var anchorOffset: CGSize = .zero
    @State private var pixelSampler: ImagePixelSampler?

    var body: some View {
        ZStack {
            if viewer.softProofSettings.isEnabled {
                Color.white
            } else {
                RAWDeskTokens.ColorToken.canvas
            }

            if asset == nil {
                ErrorPlaceholderView(kind: .empty("Select a photo from the grid."))
            } else {
                content
            }

            VStack {
                HStack {
                    if viewer.isGuidedUprightEditing {
                        previewBadge(
                            "GUIDED UPRIGHT",
                            systemImage: "ruler"
                        )
                    } else if viewer.isCropEditing {
                        previewBadge("CROP", systemImage: "crop")
                    } else if viewer.isRemovalEditing {
                        previewBadge("REMOVE", systemImage: "bandage")
                    } else if viewer.isBrushEditing {
                        previewBadge("BRUSH", systemImage: "paintbrush.pointed")
                    } else if viewer.isObjectMaskPicking {
                        previewBadge("SELECT OBJECT", systemImage: "viewfinder.circle")
                    } else if viewer.isMaskColorRangePicking {
                        previewBadge("MASK COLOR RANGE", systemImage: "eyedropper")
                    } else if viewer.isPointColorPicking {
                        previewBadge("POINT COLOR", systemImage: "eyedropper")
                    } else if viewer.isShowingOriginal {
                        previewBadge("ORIGINAL", systemImage: "eye")
                    } else if asset?.userState.adjustments.isNeutral == false {
                        previewBadge("EDITED", systemImage: "slider.horizontal.3")
                    }
                    Spacer()
                    if viewer.softProofSettings.isEnabled {
                        previewBadge(
                            "PROOF · \(viewer.softProofSettings.profile.shortName.uppercased())",
                            systemImage: "printer"
                        )
                        .help(
                            "Soft proofing \(viewer.softProofSettings.profile.name)"
                        )
                    }
                    if showsInlineToolCompletion,
                       viewer.isGuidedUprightEditing
                        || viewer.isCropEditing
                        || viewer.isRemovalEditing
                        || viewer.isBrushEditing
                        || viewer.isObjectMaskPicking
                        || viewer.isMaskColorRangePicking
                        || viewer.isPointColorPicking {
                        Button("Done") {
                            finishActiveTool()
                        }
                        .buttonStyle(.borderedProminent)
                        .rawPrimaryButtonHeight()
                        .controlSize(.small)
                    }
                    if viewer.isDeveloping {
                        ProgressView()
                            .controlSize(.small)
                            .padding(RAWDeskTokens.Spacing.small)
                            .background(
                                RAWDeskTokens.ColorToken
                                    .controlElevated,
                                in: Circle()
                            )
                    }
                    if viewer.isSoftProofRendering {
                        ProgressView()
                            .controlSize(.small)
                            .padding(RAWDeskTokens.Spacing.small)
                            .background(
                                RAWDeskTokens.ColorToken
                                    .controlElevated,
                                in: Circle()
                            )
                            .help("Updating soft proof")
                    }
                }
                Spacer()
            }
            .padding(RAWDeskTokens.Spacing.medium)
        }
        .accessibilityElement(children: .contain)
        .onExitCommand {
            if let onCancelActiveTool {
                onCancelActiveTool()
            } else {
                finishActiveTool()
            }
        }
        .onAppear {
            refreshPixelSampler(
                for:
                    viewer.colorSamplingImage
                    ?? viewer.image
            )
        }
        .onChange(of: viewer.image) { _, image in
            refreshPixelSampler(
                for:
                    viewer.colorSamplingImage
                    ?? image
            )
        }
        .onChange(
            of: viewer.colorSamplingImage
        ) { _, image in
            refreshPixelSampler(
                for: image ?? viewer.image
            )
        }
        .onDisappear {
            onPixelHover?(nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewer.loadState {
        case .idle:
            ErrorPlaceholderView(kind: .empty("Select a photo to preview."))
        case .loading:
            ProgressView("Loading…").controlSize(.regular)
        case .failed(let reason):
            ErrorPlaceholderView(kind: .failed(reason))
        case .unsupported(let reason):
            ErrorPlaceholderView(kind: .unsupported(reason))
        case .loaded:
            if let img = viewer.image {
                imageView(img)
            } else if viewer.isDeveloping {
                ProgressView("Rendering…")
                    .controlSize(.regular)
            } else {
                ErrorPlaceholderView(kind: .failed("Image data missing."))
            }
        }
    }

    private func imageView(_ image: NSImage) -> some View {
        GeometryReader { geo in
            let t = viewer.transform
            let isQuarter = t.rotationDegrees == 90 || t.rotationDegrees == 270
            let imgSize = image.size
            let displayBase = isQuarter
                ? CGSize(width: imgSize.height, height: imgSize.width)
                : imgSize
            let fitScale: CGFloat = {
                guard displayBase.width > 0, displayBase.height > 0 else { return 1 }
                let sx = geo.size.width / displayBase.width
                let sy = geo.size.height / displayBase.height
                return min(sx, sy)
            }()
            let effectiveScale = t.fitToWindow ? fitScale : t.zoom

            let sx: CGFloat = t.flipHorizontal ? -1 : 1
            let sy: CGFloat = t.flipVertical ? -1 : 1

            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .accessibilityLabel(Text("Photo preview"))
                    .frame(width: imgSize.width, height: imgSize.height)
                    .scaleEffect(x: sx * effectiveScale, y: sy * effectiveScale)
                    .rotationEffect(.degrees(Double(t.rotationDegrees)))
                    .offset(t.fitToWindow ? .zero : CGSize(
                        width: anchorOffset.width + dragOffset.width,
                        height: anchorOffset.height + dragOffset.height
                    ))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard !t.fitToWindow,
                                      !viewer.isGuidedUprightEditing,
                                      !viewer.isCropEditing,
                                      !viewer.isRemovalEditing,
                                      !viewer.isBrushEditing,
                                      !viewer.isObjectMaskPicking,
                                      !viewer.isMaskColorRangePicking,
                                      !viewer.isPointColorPicking else { return }
                                dragOffset = value.translation
                            }
                            .onEnded { _ in
                                guard !viewer.isGuidedUprightEditing,
                                      !viewer.isCropEditing,
                                      !viewer.isRemovalEditing,
                                      !viewer.isBrushEditing,
                                      !viewer.isObjectMaskPicking,
                                      !viewer.isMaskColorRangePicking,
                                      !viewer.isPointColorPicking else { return }
                                anchorOffset.width += dragOffset.width
                                anchorOffset.height += dragOffset.height
                                dragOffset = .zero
                            }
                    )

                if viewer.isCropEditing, let asset {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    CropOverlayView(
                        crop: asset.userState.adjustments.crop,
                        imageRect: imageRect,
                        onChange: onCropChange
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                if viewer.isGuidedUprightEditing, let asset {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    GuidedUprightOverlayView(
                        guides:
                            asset.userState.adjustments.geometry
                                .guidedUprightGuides,
                        imageRect: imageRect,
                        onChange: onGuidedUprightGuidesChange
                    )
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height
                    )
                }

                if viewer.isRemovalEditing,
                   let asset,
                   let spot = selectedSpot(in: asset.userState.adjustments.spotRemovals) {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    SpotRemovalOverlayView(
                        spot: spot,
                        imageRect: imageRect,
                        onChange: onSpotRemovalChange
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                if viewer.isBrushEditing,
                   let asset,
                   let brush = selectedBrush(in: asset.userState.adjustments.localMasks) {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    BrushPaintOverlayView(
                        size: brush.size,
                        flow: brush.flow,
                        strokes: brush.strokes,
                        imageRect: imageRect,
                        onCommit: { stroke in
                            onBrushStrokeCommit(brush.maskID, stroke)
                        }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                if viewer.isObjectMaskPicking {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    PhotoPointPickerOverlayView(
                        imageRect: imageRect,
                        accessibilityLabel: "Object mask picker",
                        accessibilityHint: "Click a foreground object to select it",
                        onPoint: onObjectMaskPoint
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(
                        !viewer.isDeveloping && !viewer.isGeneratingObjectMask
                    )
                }

                if viewer.isPointColorPicking {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    PhotoColorPickerOverlayView(
                        image: image,
                        imageRect: imageRect,
                        accessibilityLabel: "Point Color picker",
                        accessibilityHint: "Click a color in the photo to create a swatch",
                        onSample: onPointColorSample
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(!viewer.isDeveloping)
                }

                if viewer.isMaskColorRangePicking {
                    let imageRect = CGRect(
                        x: (geo.size.width - imgSize.width * fitScale) / 2,
                        y: (geo.size.height - imgSize.height * fitScale) / 2,
                        width: imgSize.width * fitScale,
                        height: imgSize.height * fitScale
                    )
                    PhotoColorPickerOverlayView(
                        image: image,
                        imageRect: imageRect,
                        accessibilityLabel: "Mask Color Range picker",
                        accessibilityHint: "Click a color in the photo to refine the selected mask",
                        onSample: onMaskColorRangeSample
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(!viewer.isDeveloping)
                }
            }
            .frame(
                width: geo.size.width,
                height: geo.size.height
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                handlePixelHover(
                    phase,
                    image: image,
                    containerSize: geo.size,
                    panOffset: CGSize(
                        width:
                            anchorOffset.width
                            + dragOffset.width,
                        height:
                            anchorOffset.height
                            + dragOffset.height
                    )
                )
            }
        }
        .clipped()
        .onChange(of: viewer.transform.fitToWindow) { _, fit in
            if fit {
                anchorOffset = .zero
                dragOffset = .zero
            }
        }
        .onChange(of: viewer.currentAssetID) { _, _ in
            anchorOffset = .zero
            dragOffset = .zero
        }
    }

    private func refreshPixelSampler(
        for image: NSImage?
    ) {
        guard onPixelHover != nil,
              let image else {
            pixelSampler = nil
            onPixelHover?(nil)
            return
        }
        pixelSampler = ImagePixelSampler(image: image)
    }

    private func handlePixelHover(
        _ phase: HoverPhase,
        image: NSImage,
        containerSize: CGSize,
        panOffset: CGSize
    ) {
        guard let onPixelHover else { return }
        switch phase {
        case .active(let location):
            guard let point =
                ImageViewportMapper.normalizedPoint(
                    location: location,
                    containerSize: containerSize,
                    imageSize: image.size,
                    transform: viewer.transform,
                    panOffset: panOffset
                ) else {
                onPixelHover(nil)
                return
            }
            onPixelHover(
                pixelSampler?.sample(
                    normalizedX: Double(point.x),
                    normalizedY: Double(point.y)
                )
            )
        case .ended:
            onPixelHover(nil)
        }
    }

    private func previewBadge(_ text: String, systemImage: String) -> some View {
        RAWStateBadge(
            text: text,
            systemImage: systemImage,
            tone: .neutral
        )
    }

    private func finishActiveTool() {
        if viewer.isGuidedUprightEditing {
            viewer.setGuidedUprightEditing(false)
        } else if viewer.isCropEditing {
            viewer.setCropEditing(false)
        } else if viewer.isObjectMaskPicking {
            viewer.setObjectMaskPicking(false)
        } else if viewer.isMaskColorRangePicking {
            viewer.setMaskColorRangePicking(false)
        } else if viewer.isPointColorPicking {
            viewer.setPointColorPicking(false)
        } else if viewer.isRemovalEditing {
            viewer.setRemovalEditing(false)
        } else if viewer.isBrushEditing {
            viewer.setBrushEditing(false)
        }
    }

    private func selectedSpot(in spots: [SpotRemoval]) -> SpotRemoval? {
        spots.first { $0.id == viewer.selectedSpotRemovalID } ?? spots.first
    }

    private func selectedBrush(in masks: [LocalAdjustmentMask]) -> BrushPaintTarget? {
        guard let selectedMask = masks.first(
            where: { $0.id == viewer.selectedLocalMaskID }
        ) else {
            return masks.first(where: { $0.kind == .brush }).map {
                BrushPaintTarget(
                    maskID: $0.id,
                    size: $0.size,
                    flow: $0.flow,
                    strokes: $0.strokes
                )
            }
        }
        if let operationID = viewer.selectedBrushPrimaryOperationID,
           let operation = selectedMask.primaryOperations.first(
               where: { $0.id == operationID && $0.kind == .brush }
           ) {
            return BrushPaintTarget(
                maskID: selectedMask.id,
                size: operation.size,
                flow: operation.flow,
                strokes: operation.strokes
            )
        }
        guard selectedMask.kind == .brush else { return nil }
        return BrushPaintTarget(
            maskID: selectedMask.id,
            size: selectedMask.size,
            flow: selectedMask.flow,
            strokes: selectedMask.strokes
        )
    }
}

private struct BrushPaintTarget {
    let maskID: LocalAdjustmentMask.ID
    let size: Double
    let flow: Double
    let strokes: [BrushStroke]
}

private struct PhotoPointPickerOverlayView: View {
    let imageRect: CGRect
    let accessibilityLabel: String
    let accessibilityHint: String
    let onPoint: (Double, Double) -> Void

    @State private var hoverPoint: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let hoverPoint, imageRect.contains(hoverPoint) {
                Circle()
                    .strokeBorder(.white, lineWidth: 1.5)
                    .background(Circle().fill(Color.black.opacity(0.2)))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
                    }
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .position(hoverPoint)
                    .allowsHitTesting(false)
            }

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverPoint = location
                    case .ended:
                        hoverPoint = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            select(at: value.location)
                        }
                )
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityHint(Text(accessibilityHint))
        }
    }

    private func select(at location: CGPoint) {
        guard imageRect.contains(location),
              imageRect.width > 0,
              imageRect.height > 0 else {
            return
        }
        onPoint(
            Double((location.x - imageRect.minX) / imageRect.width),
            Double((location.y - imageRect.minY) / imageRect.height)
        )
    }
}

private struct PhotoColorPickerOverlayView: View {
    let image: NSImage
    let imageRect: CGRect
    let accessibilityLabel: String
    let accessibilityHint: String
    let onSample: (PointColorSample) -> Void

    @State private var hoverPoint: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let hoverPoint, imageRect.contains(hoverPoint) {
                Circle()
                    .strokeBorder(.white, lineWidth: 1.5)
                    .background(Circle().fill(Color.black.opacity(0.18)))
                    .frame(width: 18, height: 18)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
                    }
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .position(hoverPoint)
                    .allowsHitTesting(false)
            }

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverPoint = location
                    case .ended:
                        hoverPoint = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            sample(at: value.location)
                        }
                )
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityHint(Text(accessibilityHint))
        }
    }

    private func sample(at location: CGPoint) {
        guard imageRect.contains(location),
              imageRect.width > 0,
              imageRect.height > 0 else {
            return
        }
        let normalizedX = Double(
            (location.x - imageRect.minX) / imageRect.width
        )
        let normalizedY = Double(
            (location.y - imageRect.minY) / imageRect.height
        )
        guard let sample = ImageColorSampler.sample(
            image: image,
            normalizedX: normalizedX,
            normalizedY: normalizedY
        ) else {
            return
        }
        onSample(sample)
    }
}

private struct BrushPaintOverlayView: View {
    let size: Double
    let flow: Double
    let strokes: [BrushStroke]
    let imageRect: CGRect
    let onCommit: (BrushStroke) -> Void

    @State private var activePoints: [BrushPoint] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for stroke in strokes {
                    draw(stroke.points, in: &context, opacity: 0.65)
                }
                draw(activePoints, in: &context, opacity: 0.9)
            }
            .allowsHitTesting(false)

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(paintGesture)
                .accessibilityLabel(Text("Brush canvas"))
                .accessibilityHint(Text("Drag on the photo to paint the selected mask"))
        }
        .clipped()
    }

    private var brushWidth: CGFloat {
        max(3, CGFloat(size) * min(imageRect.width, imageRect.height) * 2)
    }

    private var paintGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard imageRect.contains(value.location) else { return }
                let point = BrushPoint(
                    x: Double((value.location.x - imageRect.minX) / max(1, imageRect.width)),
                    y: Double((value.location.y - imageRect.minY) / max(1, imageRect.height))
                )
                if let last = activePoints.last {
                    let dx = point.x - last.x
                    let dy = point.y - last.y
                    let minimumDistance = max(0.0015, size * 0.05)
                    guard dx * dx + dy * dy >= minimumDistance * minimumDistance else {
                        return
                    }
                }
                activePoints.append(point)
            }
            .onEnded { _ in
                guard !activePoints.isEmpty else { return }
                onCommit(BrushStroke(points: activePoints))
                activePoints = []
            }
    }

    private func draw(
        _ points: [BrushPoint],
        in context: inout GraphicsContext,
        opacity: Double
    ) {
        guard let first = points.first else { return }
        let color = RAWDeskTokens.ColorToken.selection.opacity(opacity * max(0.2, flow))
        if points.count == 1 {
            let point = displayPoint(first)
            let radius = brushWidth / 2
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: brushWidth,
                        height: brushWidth
                    )
                ),
                with: .color(color)
            )
            return
        }

        var path = Path()
        path.move(to: displayPoint(first))
        for point in points.dropFirst() {
            path.addLine(to: displayPoint(point))
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: brushWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func displayPoint(_ point: BrushPoint) -> CGPoint {
        CGPoint(
            x: imageRect.minX + CGFloat(point.x) * imageRect.width,
            y: imageRect.minY + CGFloat(point.y) * imageRect.height
        )
    }
}

private struct SpotRemovalOverlayView: View {
    let spot: SpotRemoval
    let imageRect: CGRect
    let onChange: (SpotRemoval) -> Void

    @State private var targetGestureStart: SpotRemoval?
    @State private var sourceGestureStart: SpotRemoval?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var connector = Path()
                connector.move(to: sourcePoint)
                connector.addLine(to: targetPoint)
                context.stroke(
                    connector,
                    with: .color(.white.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                let radiusRect = CGRect(
                    x: targetPoint.x - displayRadius,
                    y: targetPoint.y - displayRadius,
                    width: displayRadius * 2,
                    height: displayRadius * 2
                )
                context.stroke(
                    Path(ellipseIn: radiusRect),
                    with: .color(RAWDeskTokens.ColorToken.selection.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )
            }
            .allowsHitTesting(false)

            spotHandle(
                at: sourcePoint,
                fill: .white.opacity(0.2),
                stroke: .white,
                label: "Repair source",
                hint: "Drag to select the source texture"
            )
            .gesture(sourceGesture)

            spotHandle(
                at: targetPoint,
                fill: RAWDeskTokens.ColorToken.selection.opacity(0.65),
                stroke: .white,
                label: "Repair target",
                hint: "Drag over the object to remove"
            )
            .gesture(targetGesture)
        }
        .accessibilityElement(children: .contain)
    }

    private var targetPoint: CGPoint {
        point(x: spot.targetX, y: spot.targetY)
    }

    private var sourcePoint: CGPoint {
        point(x: spot.sourceX, y: spot.sourceY)
    }

    private var displayRadius: CGFloat {
        max(4, CGFloat(spot.radius) * min(imageRect.width, imageRect.height))
    }

    private func point(x: Double, y: Double) -> CGPoint {
        CGPoint(
            x: imageRect.minX + CGFloat(x) * imageRect.width,
            y: imageRect.minY + CGFloat(y) * imageRect.height
        )
    }

    private func spotHandle(
        at point: CGPoint,
        fill: Color,
        stroke: Color,
        label: String,
        hint: String
    ) -> some View {
        RAWCanvasHandle(fill: fill, stroke: stroke)
            .position(point)
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text(hint))
    }

    private var targetGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = targetGestureStart ?? spot
                if targetGestureStart == nil { targetGestureStart = start }
                var updated = start
                updated.targetX += Double(value.translation.width / max(1, imageRect.width))
                updated.targetY += Double(value.translation.height / max(1, imageRect.height))
                onChange(updated.normalized)
            }
            .onEnded { _ in
                targetGestureStart = nil
            }
    }

    private var sourceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = sourceGestureStart ?? spot
                if sourceGestureStart == nil { sourceGestureStart = start }
                var updated = start
                updated.sourceX += Double(value.translation.width / max(1, imageRect.width))
                updated.sourceY += Double(value.translation.height / max(1, imageRect.height))
                onChange(updated.normalized)
            }
            .onEnded { _ in
                sourceGestureStart = nil
            }
    }
}

private struct GuidedUprightOverlayView: View {
    let guides: [GuidedUprightGuide]
    let imageRect: CGRect
    let onChange: ([GuidedUprightGuide]) -> Void

    @State private var draftStart: CGPoint?
    @State private var draftEnd: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(
                    width: imageRect.width,
                    height: imageRect.height
                )
                .position(
                    x: imageRect.midX,
                    y: imageRect.midY
                )
                .gesture(drawingGesture)
                .accessibilityLabel(
                    Text("Guided Upright drawing area")
                )
                .accessibilityHint(
                    Text(
                        guides.count < 4
                            ? "Draw a line along a horizontal or vertical architectural edge"
                            : "Four guides are already drawn"
                    )
                )

            Canvas { context, _ in
                for guide in guides {
                    stroke(
                        guide: guide,
                        in: &context
                    )
                }
                if let start = draftStart,
                   let end = draftEnd {
                    let draft = GuidedUprightGuide.inferred(
                        startX: Double(start.x),
                        startY: Double(start.y),
                        endX: Double(end.x),
                        endY: Double(end.y),
                        imageAspectRatio:
                            Double(
                                imageRect.width
                                    / max(1, imageRect.height)
                            )
                    )
                    stroke(
                        guide: draft,
                        in: &context,
                        opacity: 0.72
                    )
                }
            }
            .allowsHitTesting(false)

            ForEach(
                Array(guides.enumerated()),
                id: \.element.id
            ) { index, guide in
                let start = displayPoint(
                    x: guide.startX,
                    y: guide.startY
                )
                let end = displayPoint(
                    x: guide.endX,
                    y: guide.endY
                )
                let midpoint = CGPoint(
                    x: (start.x + end.x) / 2,
                    y: (start.y + end.y) / 2
                )

                Text(
                    "\(guide.orientation == .horizontal ? "H" : "V")\(index + 1)"
                )
                .font(RAWDeskTokens.Typography.numeric)
                .foregroundStyle(.black)
                .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                .background(
                    guideColor(guide.orientation),
                    in: Capsule()
                )
                .position(midpoint)
                .allowsHitTesting(false)

                endpointHandle(
                    guide: guide,
                    isStart: true,
                    at: start,
                    number: index + 1
                )
                endpointHandle(
                    guide: guide,
                    isStart: false,
                    at: end,
                    number: index + 1
                )
            }
        }
        .clipped()
        .coordinateSpace(name: "guidedUprightOverlay")
    }

    private var drawingGesture: some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(
                "guidedUprightOverlay"
            )
        )
            .onChanged { value in
                guard guides.count < 4 else { return }
                draftStart =
                    normalizedPoint(value.startLocation)
                draftEnd = normalizedPoint(value.location)
            }
            .onEnded { value in
                defer {
                    draftStart = nil
                    draftEnd = nil
                }
                guard guides.count < 4 else { return }
                let start = normalizedPoint(value.startLocation)
                let end = normalizedPoint(value.location)
                let guide = GuidedUprightGuide.inferred(
                    startX: Double(start.x),
                    startY: Double(start.y),
                    endX: Double(end.x),
                    endY: Double(end.y),
                    imageAspectRatio:
                        Double(
                            imageRect.width
                                / max(1, imageRect.height)
                        )
                )
                guard guide.isEffective else { return }
                onChange(guides + [guide])
            }
    }

    private func endpointHandle(
        guide: GuidedUprightGuide,
        isStart: Bool,
        at point: CGPoint,
        number: Int
    ) -> some View {
        RAWCanvasHandle(
            fill: guideColor(guide.orientation),
            stroke: .black.opacity(0.82)
        )
        .position(point)
        .gesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(
                    "guidedUprightOverlay"
                )
            )
                .onChanged { value in
                    updateEndpoint(
                        of: guide,
                        isStart: isStart,
                        to: value.location
                    )
                }
        )
        .accessibilityLabel(
            Text(
                "Guide \(number) \(isStart ? "start" : "end") point"
            )
        )
        .accessibilityHint(
            Text("Drag to align the guide with the photo")
        )
    }

    private func updateEndpoint(
        of guide: GuidedUprightGuide,
        isStart: Bool,
        to location: CGPoint
    ) {
        guard let index = guides.firstIndex(
            where: { $0.id == guide.id }
        ) else {
            return
        }
        let point = normalizedPoint(location)
        var updated = guide
        if isStart {
            updated.startX = Double(point.x)
            updated.startY = Double(point.y)
        } else {
            updated.endX = Double(point.x)
            updated.endY = Double(point.y)
        }
        var allGuides = guides
        allGuides[index] = updated.normalized
        onChange(allGuides)
    }

    private func stroke(
        guide: GuidedUprightGuide,
        in context: inout GraphicsContext,
        opacity: Double = 1
    ) {
        var shadow = Path()
        shadow.move(
            to: displayPoint(
                x: guide.startX,
                y: guide.startY
            )
        )
        shadow.addLine(
            to: displayPoint(
                x: guide.endX,
                y: guide.endY
            )
        )
        context.stroke(
            shadow,
            with: .color(.black.opacity(0.86 * opacity)),
            lineWidth: 5
        )
        context.stroke(
            shadow,
            with: .color(
                guideColor(guide.orientation)
                    .opacity(opacity)
            ),
            style: StrokeStyle(
                lineWidth: 2.25,
                dash: [8, 4]
            )
        )
    }

    private func displayPoint(
        x: Double,
        y: Double
    ) -> CGPoint {
        CGPoint(
            x: imageRect.minX + CGFloat(x) * imageRect.width,
            y: imageRect.minY + CGFloat(y) * imageRect.height
        )
    }

    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(
                1,
                max(
                    0,
                    (point.x - imageRect.minX)
                        / max(1, imageRect.width)
                )
            ),
            y: min(
                1,
                max(
                    0,
                    (point.y - imageRect.minY)
                        / max(1, imageRect.height)
                )
            )
        )
    }

    private func guideColor(
        _ orientation: GuidedUprightOrientation
    ) -> Color {
        orientation == .horizontal
            ? .yellow
            : .cyan
    }
}

private struct CropOverlayView: View {
    let crop: NormalizedCrop
    let imageRect: CGRect
    let onChange: (NormalizedCrop) -> Void

    @State private var gestureStart: NormalizedCrop?

    var body: some View {
        let rect = cropRect
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var shade = Path()
                shade.addRect(imageRect)
                shade.addRect(rect)
                context.fill(
                    shade,
                    with: .color(.black.opacity(0.58)),
                    style: FillStyle(eoFill: true)
                )

                var grid = Path()
                for fraction in [1.0 / 3, 2.0 / 3] {
                    let x = rect.minX + rect.width * fraction
                    grid.move(to: CGPoint(x: x, y: rect.minY))
                    grid.addLine(to: CGPoint(x: x, y: rect.maxY))
                    let y = rect.minY + rect.height * fraction
                    grid.move(to: CGPoint(x: rect.minX, y: y))
                    grid.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                context.stroke(
                    grid,
                    with: .color(.white.opacity(0.55)),
                    lineWidth: 0.75
                )
            }
            .allowsHitTesting(false)

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .overlay {
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .shadow(color: .black.opacity(0.7), radius: 1)
                        .allowsHitTesting(false)
                }
                .gesture(moveGesture)
                .accessibilityLabel(Text("Crop area"))
                .accessibilityHint(Text("Drag to reposition the crop"))

            ForEach(CropHandle.allCases) { handle in
                handleView(handle, at: point(for: handle, rect: rect))
            }
        }
    }

    private var cropRect: CGRect {
        CGRect(
            x: imageRect.minX + CGFloat(crop.x) * imageRect.width,
            y: imageRect.minY + CGFloat(crop.y) * imageRect.height,
            width: CGFloat(crop.width) * imageRect.width,
            height: CGFloat(crop.height) * imageRect.height
        )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = gestureStart ?? crop
                if gestureStart == nil { gestureStart = start }
                let dx = Double(value.translation.width / max(1, imageRect.width))
                let dy = Double(value.translation.height / max(1, imageRect.height))
                onChange(start.translated(deltaX: dx, deltaY: dy))
            }
            .onEnded { _ in
                gestureStart = nil
            }
    }

    private func handleView(_ handle: CropHandle, at point: CGPoint) -> some View {
        RAWCanvasHandle()
            .position(point)
            .gesture(resizeGesture(handle))
            .accessibilityLabel(Text("\(handleName(handle)) crop handle"))
    }

    private func resizeGesture(_ handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = gestureStart ?? crop
                if gestureStart == nil { gestureStart = start }
                let dx = Double(value.translation.width / max(1, imageRect.width))
                let dy = Double(value.translation.height / max(1, imageRect.height))
                onChange(
                    start.resized(
                        from: handle,
                        deltaX: dx,
                        deltaY: dy
                    )
                )
            }
            .onEnded { _ in
                gestureStart = nil
            }
    }

    private func point(for handle: CropHandle, rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func handleName(_ handle: CropHandle) -> String {
        switch handle {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}
