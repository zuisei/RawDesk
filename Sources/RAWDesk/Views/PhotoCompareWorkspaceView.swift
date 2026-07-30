import SwiftUI
import AppKit

struct PhotoCompareWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var selectViewer: PhotoViewerViewModel
    @ObservedObject var candidateViewer: PhotoViewerViewModel

    @AppStorage("rawdesk.compare.syncZoom")
    private var syncZoom = true
    @State private var selectPan: CGSize = .zero
    @State private var candidatePan: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            comparisonToolbar
            Divider()
            HStack(spacing: 0) {
                ComparePhotoPane(
                    role: .select,
                    asset: library.compareSelectAsset,
                    viewer: selectViewer,
                    library: library,
                    panOffset: $selectPan
                )
                Divider()
                ComparePhotoPane(
                    role: .candidate,
                    asset: library.selectedAsset,
                    viewer: candidateViewer,
                    library: library,
                    panOffset: $candidatePan
                )
            }
        }
        .background(RAWDeskTokens.ColorToken.canvas)
        .onAppear {
            selectViewer.display(library.compareSelectAsset)
            candidateViewer.display(library.selectedAsset)
            if syncZoom {
                copyZoom(
                    from: candidateViewer.transform,
                    to: selectViewer
                )
            }
        }
        .onDisappear {
            selectViewer.display(nil)
        }
        .onChange(of: library.compareState?.selectID) { _, _ in
            selectViewer.display(library.compareSelectAsset)
            selectPan = .zero
        }
        .onChange(of: library.compareState?.candidateID) { _, _ in
            candidateViewer.display(library.selectedAsset)
            if !syncZoom {
                candidatePan = .zero
            }
        }
        .onChange(of: candidateViewer.transform) { _, transform in
            guard syncZoom else { return }
            copyZoom(from: transform, to: selectViewer)
        }
        .onChange(of: selectViewer.transform) { _, transform in
            guard syncZoom else { return }
            copyZoom(from: transform, to: candidateViewer)
        }
        .onChange(of: candidatePan) { _, offset in
            if syncZoom, selectPan != offset {
                selectPan = offset
            }
        }
        .onChange(of: selectPan) { _, offset in
            if syncZoom, candidatePan != offset {
                candidatePan = offset
            }
        }
        .onChange(of: syncZoom) { _, enabled in
            guard enabled else { return }
            copyZoom(
                from: candidateViewer.transform,
                to: selectViewer
            )
            selectPan = candidatePan
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Photo compare workspace")
    }

    private var comparisonToolbar: some View {
        ViewThatFits(in: .horizontal) {
            fullComparisonToolbar
            compactComparisonToolbar
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.medium)
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .frame(
            minHeight:
                RAWDeskTokens.Size
                    .workspaceControlBar
        )
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    private var fullComparisonToolbar: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(
                "Compare — 2 photos",
                systemImage: "rectangle.split.2x1"
            )
            .font(RAWDeskTokens.Typography.workspaceHeader)
            .fixedSize(horizontal: true, vertical: false)
            if let position = library.compareCandidatePosition {
                Text(
                    "Candidate \(position.position) of \(position.total)"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }

            Spacer(minLength: 12)

            previousCandidateButton
            nextCandidateButton

            Divider().frame(height: 18)

            Button {
                library.swapComparePhotos()
            } label: {
                Label(
                    "Swap",
                    systemImage: "arrow.left.arrow.right"
                )
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Swap Select and Candidate")
            .accessibilityIdentifier("Swap compare photos")

            Button {
                library.promoteCompareCandidate()
            } label: {
                Label(
                    "Make Select",
                    systemImage: "checkmark.circle"
                )
            }
            .help("Make the Candidate the new Select")
            .accessibilityIdentifier("Make compare candidate select")

            Divider().frame(height: 18)

            Toggle(isOn: $syncZoom) {
                Label(
                    "Sync Zoom",
                    systemImage: "link"
                )
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help("Keep zoom and pan aligned")
            .accessibilityLabel(Text("Sync Zoom"))
            .accessibilityIdentifier("Sync compare zoom")

            Button {
                fitVisiblePhotos()
            } label: {
                Label(
                    "Fit",
                    systemImage:
                        "arrow.up.left.and.down.right.magnifyingglass"
                )
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Fit compared photos")

            Button {
                actualSizeVisiblePhotos()
            } label: {
                Text("1:1")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                    .monospacedDigit()
            }
            .help("View compared photos at actual size")

            Button("Done") {
                library.endCompare()
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.small)
            .accessibilityIdentifier("Finish photo compare")
        }
    }

    private var compactComparisonToolbar: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(
                "Compare",
                systemImage: "rectangle.split.2x1"
            )
            .font(RAWDeskTokens.Typography.sectionHeader)
            .fixedSize(horizontal: true, vertical: false)

            if let position = library.compareCandidatePosition {
                Text("\(position.position) / \(position.total)")
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            previousCandidateButton
            nextCandidateButton

            Menu {
                Button("Swap Select and Candidate") {
                    library.swapComparePhotos()
                }
                Button("Make Candidate Select") {
                    library.promoteCompareCandidate()
                }
                Divider()
                Toggle("Sync Zoom", isOn: $syncZoom)
                Button("Fit Compared Photos") {
                    fitVisiblePhotos()
                }
                Button("View at 1:1") {
                    actualSizeVisiblePhotos()
                }
            } label: {
                Label(
                    "Compare Actions",
                    systemImage: "ellipsis.circle"
                )
                .labelStyle(.iconOnly)
            }
            .rawIconButtonTarget()
            .help("Swap, promote, sync, and zoom actions")

            Button("Done") {
                library.endCompare()
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.small)
            .accessibilityIdentifier("Finish photo compare")
        }
    }

    private var previousCandidateButton: some View {
        Button {
            library.moveCompareCandidate(direction: -1)
        } label: {
            Label("Previous", systemImage: "chevron.left")
        }
        .labelStyle(.iconOnly)
        .rawIconButtonTarget()
        .help("Previous Candidate (←)")
        .accessibilityIdentifier("Previous compare candidate")
    }

    private var nextCandidateButton: some View {
        Button {
            library.moveCompareCandidate(direction: 1)
        } label: {
            Label("Next", systemImage: "chevron.right")
        }
        .labelStyle(.iconOnly)
        .rawIconButtonTarget()
        .help("Next Candidate (→)")
        .accessibilityIdentifier("Next compare candidate")
    }

    private func fitVisiblePhotos() {
        candidateViewer.transform.fit()
        candidatePan = .zero
        if syncZoom {
            selectViewer.transform.fit()
            selectPan = .zero
        }
    }

    private func actualSizeVisiblePhotos() {
        candidateViewer.transform.actualSize()
        candidatePan = .zero
        if syncZoom {
            selectViewer.transform.actualSize()
            selectPan = .zero
        }
    }

    private func copyZoom(
        from source: ImageTransformState,
        to viewer: PhotoViewerViewModel
    ) {
        guard viewer.transform.fitToWindow
                != source.fitToWindow
                || viewer.transform.zoom != source.zoom else {
            return
        }
        var target = viewer.transform
        target.fitToWindow = source.fitToWindow
        target.zoom = source.zoom
        viewer.transform = target
    }
}

private struct ComparePhotoPane: View {
    let role: PhotoCompareRole
    let asset: PhotoAsset?
    @ObservedObject var viewer: PhotoViewerViewModel
    @ObservedObject var library: LibraryViewModel
    @Binding var panOffset: CGSize

    private var roleColor: Color {
        role == .candidate
            ? RAWDeskTokens.ColorToken.selection
            : RAWDeskTokens.ColorToken.textSecondary
    }

    private var roleBackground: Color {
        role == .candidate
            ? RAWDeskTokens.ColorToken.selection.opacity(0.16)
            : RAWDeskTokens.ColorToken.controlElevated
    }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            ReviewImageCanvas(
                viewer: viewer,
                asset: asset,
                panOffset: $panOffset
            )
            Divider()
            paneFooter
        }
        .overlay {
            Rectangle()
                .strokeBorder(
                    roleColor.opacity(0.72),
                    lineWidth: role == .candidate ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            role == .select
                ? "Compare select photo"
                : "Compare candidate photo"
        )
    }

    private var paneHeader: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(role.name, systemImage: role.systemImage)
                .font(RAWDeskTokens.Typography.sectionHeader)
                .foregroundStyle(roleColor)
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                .background(
                    roleBackground,
                    in: Capsule()
                )
            Text(asset?.filename ?? "No Photo")
                .font(RAWDeskTokens.Typography.control)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let asset {
                Text(asset.format.displayName)
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    @ViewBuilder
    private var paneFooter: some View {
        if let asset {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(metadataSummary(asset))
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .lineLimit(1)
                    if let captureDate =
                        asset.metadata?.captureDate
                        ?? asset.creationDate {
                        Text(DisplayFormatters.date(captureDate))
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                RAWReviewControls(
                    library: library,
                    asset: asset,
                    compact: true
                )
            }
            .padding(.horizontal, RAWDeskTokens.Spacing.small)
            .padding(.vertical, RAWDeskTokens.Spacing.small)
            .background(RAWDeskTokens.ColorToken.chrome)
        } else {
            Text("Choose two visible photos to compare.")
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(RAWDeskTokens.Spacing.small)
                .background(RAWDeskTokens.ColorToken.chrome)
        }
    }

    private func metadataSummary(
        _ asset: PhotoAsset
    ) -> String {
        let metadata = asset.metadata
        return [
            DisplayFormatters.dimensions(
                metadata?.pixelWidth,
                metadata?.pixelHeight
            ),
            DisplayFormatters.aperture(metadata?.aperture),
            DisplayFormatters.shutter(metadata?.shutterSpeed),
            DisplayFormatters.iso(metadata?.iso),
            DisplayFormatters.focalLength(
                metadata?.focalLength
            ),
        ]
        .filter { $0 != "—" }
        .joined(separator: " · ")
    }
}

struct ReviewImageCanvas: View {
    @ObservedObject var viewer: PhotoViewerViewModel
    let asset: PhotoAsset?
    @Binding var panOffset: CGSize
    var emptyMessage = "Choose a photo to compare."
    var accessibilityText = "Compared photo preview"
    var onPixelHover:
        ((ImagePixelSample?) -> Void)? = nil
    @State private var dragOffset: CGSize = .zero
    @State private var pixelSampler: ImagePixelSampler?

    var body: some View {
        ZStack {
            if viewer.softProofSettings.isEnabled {
                Color.white
            } else {
                RAWDeskTokens.ColorToken.canvas
            }
            if asset == nil {
                ErrorPlaceholderView(
                    kind: .empty(emptyMessage)
                )
            } else {
                compareContent
            }
            if viewer.isDeveloping {
                VStack {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .padding(RAWDeskTokens.Spacing.small)
                            .background(
                                RAWDeskTokens.ColorToken
                                    .controlElevated,
                                in: Circle()
                            )
                    }
                    Spacer()
                }
                .padding(RAWDeskTokens.Spacing.small)
            }
        }
        .clipped()
        .onChange(of: viewer.transform.fitToWindow) { _, fit in
            if fit {
                panOffset = .zero
                dragOffset = .zero
            }
        }
        .onChange(of: viewer.currentAssetID) { _, _ in
            dragOffset = .zero
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
    private var compareContent: some View {
        switch viewer.loadState {
        case .idle:
            ErrorPlaceholderView(
                kind: .empty(emptyMessage)
            )
        case .loading:
            ProgressView("Loading…")
        case .failed(let reason):
            ErrorPlaceholderView(kind: .failed(reason))
        case .unsupported(let reason):
            ErrorPlaceholderView(kind: .unsupported(reason))
        case .loaded:
            if let image = viewer.image {
                compareImage(image)
            } else if viewer.isDeveloping {
                ProgressView("Rendering…")
            } else {
                ErrorPlaceholderView(
                    kind: .failed("Image data missing.")
                )
            }
        }
    }

    private func compareImage(
        _ image: NSImage
    ) -> some View {
        GeometryReader { proxy in
            let transform = viewer.transform
            let isQuarterTurn =
                transform.rotationDegrees == 90
                || transform.rotationDegrees == 270
            let imageSize = image.size
            let displaySize = isQuarterTurn
                ? CGSize(
                    width: imageSize.height,
                    height: imageSize.width
                )
                : imageSize
            let fitScale: CGFloat = {
                guard displaySize.width > 0,
                      displaySize.height > 0 else {
                    return 1
                }
                return min(
                    proxy.size.width / displaySize.width,
                    proxy.size.height / displaySize.height
                )
            }()
            let effectiveScale =
                transform.fitToWindow
                    ? fitScale
                    : transform.zoom
            let xScale: CGFloat =
                transform.flipHorizontal ? -1 : 1
            let yScale: CGFloat =
                transform.flipVertical ? -1 : 1

            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(
                        width: imageSize.width,
                        height: imageSize.height
                    )
                    .scaleEffect(
                        x: xScale * effectiveScale,
                        y: yScale * effectiveScale
                    )
                    .rotationEffect(
                        .degrees(
                            Double(transform.rotationDegrees)
                        )
                    )
                    .offset(
                        transform.fitToWindow
                            ? .zero
                            : CGSize(
                                width:
                                    panOffset.width
                                    + dragOffset.width,
                                height:
                                    panOffset.height
                                    + dragOffset.height
                            )
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard
                                    !transform.fitToWindow
                                else {
                                    return
                                }
                                dragOffset =
                                    value.translation
                            }
                            .onEnded { _ in
                                guard
                                    !transform.fitToWindow
                                else {
                                    return
                                }
                                panOffset.width
                                    += dragOffset.width
                                panOffset.height
                                    += dragOffset.height
                                dragOffset = .zero
                            }
                    )
                    .onTapGesture(count: 2) {
                        if viewer.transform.fitToWindow {
                            viewer.transform.actualSize()
                        } else {
                            viewer.transform.fit()
                            panOffset = .zero
                        }
                    }
                    .accessibilityLabel(
                        Text(accessibilityText)
                    )
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                handlePixelHover(
                    phase,
                    image: image,
                    containerSize: proxy.size,
                    panOffset: CGSize(
                        width:
                            panOffset.width
                            + dragOffset.width,
                        height:
                            panOffset.height
                            + dragOffset.height
                    )
                )
            }
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
}

struct PhotoCompareFilmstripView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let cellWidth: CGFloat = 112

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: RAWDeskTokens.Spacing.small) {
                    ForEach(library.filtered) { asset in
                        ThumbnailCellView(
                            asset: asset,
                            isSelected:
                                library.selectedIDs.contains(asset.id),
                            isActive:
                                library.selectionID == asset.id,
                            compareRole:
                                library.compareRole(for: asset.id),
                            surveyRole: nil,
                            pixelSize: cellWidth * 2,
                            duplicateGroupNumber:
                                library.duplicateGroupNumber(
                                    for: asset.id
                                ),
                            isDuplicateAnchor:
                                library.isDuplicateAnchor(asset.id),
                            isInQuickCollection:
                                library.isInQuickCollection(asset.id),
                            isInPhotoCollection:
                                library.isInAnyPhotoCollection(
                                    asset.id
                                ),
                            cullingEvaluation:
                                library.cullingEvaluation(for: asset.id),
                            cullingAnalysis:
                                library.cullingAnalysis(for: asset.id),
                            cullingStackNumber:
                                library.cullingStackNumber(
                                    for: asset.id
                                ),
                            stackMembership:
                                library.catalogCollection
                                    == .exactDuplicates
                                    ? nil
                                    : library.photoStackMembership(
                                        for: asset.id
                                    ),
                            onStackToggle: {
                                library.togglePhotoStack(
                                    containing: asset.id
                                )
                            },
                            onLoadStateChange: {
                                state,
                                rawDecodeSource in
                                library.updateLoadOutcome(
                                    state,
                                    rawDecodeSource:
                                        rawDecodeSource,
                                    for: asset.id
                                )
                            }
                        )
                        .frame(
                            width: cellWidth,
                            height: cellWidth + 22
                        )
                        .contentShape(Rectangle())
                        .id(asset.id)
                        .onTapGesture {
                            library.setCompareCandidate(asset.id)
                        }
                    }
                }
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            }
            .background(RAWDeskTokens.ColorToken.chrome)
            .onAppear {
                scrollToCandidate(
                    library.compareState?.candidateID,
                    proxy: proxy,
                    animated: false
                )
            }
            .onChange(
                of: library.compareState?.candidateID
            ) { _, id in
                scrollToCandidate(
                    id,
                    proxy: proxy,
                    animated: !reduceMotion
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Compare filmstrip")
    }

    private func scrollToCandidate(
        _ id: PhotoAsset.ID?,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let id else { return }
        if animated {
            withAnimation(.snappy(duration: 0.22)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
