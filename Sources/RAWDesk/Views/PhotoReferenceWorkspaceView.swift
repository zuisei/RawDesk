import SwiftUI
import AppKit

struct PhotoReferenceWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var referenceViewer: PhotoViewerViewModel
    @ObservedObject var activeViewer: PhotoViewerViewModel
    let onCropChange: (NormalizedCrop) -> Void
    let onGuidedUprightGuidesChange:
        ([GuidedUprightGuide]) -> Void
    let onSpotRemovalChange: (SpotRemoval) -> Void
    let onBrushStrokeCommit:
        (LocalAdjustmentMask.ID, BrushStroke) -> Void
    let onObjectMaskPoint: (Double, Double) -> Void
    let onPointColorSample: (PointColorSample) -> Void
    let onMaskColorRangeSample: (PointColorSample) -> Void

    @State private var referencePan: CGSize = .zero
    @State private var activePan: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            referenceToolbar
            Divider()
            pairedPhotos
        }
        .background(RAWDeskTokens.ColorToken.canvas)
        .onAppear {
            referenceViewer.display(library.referenceAsset)
            activeViewer.display(library.selectedAsset)
        }
        .onDisappear {
            referenceViewer.display(nil)
        }
        .onChange(
            of: library.referenceState?.referenceID
        ) { _, _ in
            referenceViewer.display(library.referenceAsset)
            referencePan = .zero
        }
        .onChange(
            of: library.referenceState?.activeID
        ) { _, _ in
            activeViewer.display(library.selectedAsset)
            activePan = .zero
        }
        .onChange(
            of: library.referenceAsset?
                .userState.adjustments
        ) { _, adjustments in
            guard let id = library.referenceState?.referenceID,
                  let adjustments else {
                return
            }
            referenceViewer.updateAdjustments(
                adjustments,
                for: id
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Photo reference workspace")
    }

    @ViewBuilder
    private var pairedPhotos: some View {
        if library.referenceState?.layout == .topBottom {
            VStack(spacing: 0) {
                referencePane
                Divider()
                activePane
            }
        } else {
            HStack(spacing: 0) {
                referencePane
                Divider()
                activePane
            }
        }
    }

    private var referencePane: some View {
        ReferencePhotoPane(
            role: .reference,
            asset: library.referenceAsset,
            viewer: referenceViewer,
            library: library,
            panOffset: $referencePan
        )
    }

    private var activePane: some View {
        ReferencePhotoPane(
            role: .active,
            asset: library.selectedAsset,
            viewer: activeViewer,
            library: library,
            panOffset: $activePan,
            onCropChange: onCropChange,
            onGuidedUprightGuidesChange:
                onGuidedUprightGuidesChange,
            onSpotRemovalChange: onSpotRemovalChange,
            onBrushStrokeCommit: onBrushStrokeCommit,
            onObjectMaskPoint: onObjectMaskPoint,
            onPointColorSample: onPointColorSample,
            onMaskColorRangeSample: onMaskColorRangeSample
        )
    }

    private var referenceToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Label(
                    "Reference",
                    systemImage: "photo.on.rectangle.angled"
                )
                .font(RAWDeskTokens.Typography.workspaceHeader)
                .fixedSize(horizontal: true, vertical: false)
            Text("Edits apply to Active only")
                .font(
                    RAWDeskTokens.Typography.metadata
                )
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )

            if let position = library.referenceActivePosition {
                Text(
                    "Active \(position.position) of \(position.total)"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .monospacedDigit()
            }

            ReferenceToneDeltaView(
                reference: referenceViewer.histogram,
                active: activeViewer.histogram
            )

            Spacer(minLength: 8)

            Button {
                library.moveReferenceActive(direction: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Previous Active Photo (←)")
            .accessibilityIdentifier(
                "Previous reference active photo"
            )

            Button {
                library.moveReferenceActive(direction: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Next Active Photo (→)")
            .accessibilityIdentifier(
                "Next reference active photo"
            )

            Divider().frame(height: 18)

            Menu {
                ForEach(library.filtered) { asset in
                    Button {
                        library.setReferencePhoto(asset.id)
                    } label: {
                        Label(
                            asset.filename,
                            systemImage:
                                asset.id
                                    == library.referenceState?
                                        .referenceID
                                ? "checkmark"
                                : "photo"
                        )
                    }
                    .disabled(
                        asset.id
                            == library.referenceState?.activeID
                    )
                }
                if library.referenceState?.referenceID != nil {
                    Divider()
                    Button(
                        "Clear Reference",
                        role: .destructive
                    ) {
                        library.clearReferencePhoto()
                    }
                }
            } label: {
                Label(
                    library.referenceAsset == nil
                        ? "Choose Reference"
                        : "Reference",
                    systemImage: "photo.badge.plus"
                )
            }
            .help("Choose the static Reference photo")
            .accessibilityIdentifier("Choose reference photo")

            Button {
                library.swapReferencePhotos()
            } label: {
                Label(
                    "Swap",
                    systemImage: "arrow.left.arrow.right"
                )
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Swap Reference and Active photos")
            .disabled(library.referenceAsset == nil)
            .accessibilityIdentifier("Swap reference photos")

            Menu {
                ForEach(PhotoReferenceLayout.allCases, id: \.self) {
                    layout in
                    Button {
                        library.setReferenceLayout(layout)
                    } label: {
                        Label(
                            layout.name,
                            systemImage:
                                layout
                                    == library.referenceState?.layout
                                ? "checkmark"
                                : layout.systemImage
                        )
                    }
                }
            } label: {
                Label(
                    "Layout",
                    systemImage:
                        library.referenceState?.layout
                            .systemImage
                            ?? PhotoReferenceLayout.sideBySide
                                .systemImage
                )
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help(
                "Reference layout: \(library.referenceState?.layout.name ?? PhotoReferenceLayout.sideBySide.name)"
            )
            .accessibilityIdentifier("Reference layout")

            Toggle(
                isOn: Binding(
                    get: {
                        library.referenceState?
                            .isReferenceLocked
                            ?? false
                    },
                    set: library.setReferenceLocked
                )
            ) {
                Label(
                    "Lock Reference",
                    systemImage:
                        library.referenceState?
                            .isReferenceLocked == true
                        ? "lock.fill"
                        : "lock.open"
                )
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help(
                library.referenceState?
                    .isReferenceLocked == true
                    ? "Keep this Reference when leaving the workspace"
                    : "Lock the Reference across workspaces"
            )
            .disabled(library.referenceAsset == nil)
            .accessibilityIdentifier("Lock reference photo")

            Button("Done") {
                library.endReferenceView()
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.small)
            .accessibilityIdentifier("Finish reference view")
            }

            compactReferenceToolbar
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

    private var compactReferenceToolbar: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(
                "Reference",
                systemImage: "photo.on.rectangle.angled"
            )
            .font(RAWDeskTokens.Typography.sectionHeader)
            .fixedSize(horizontal: true, vertical: false)

            if let position = library.referenceActivePosition {
                Text("\(position.position) / \(position.total)")
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .monospacedDigit()
            }

            ReferenceToneDeltaView(
                reference: referenceViewer.histogram,
                active: activeViewer.histogram
            )

            Spacer(minLength: 4)

            Button {
                library.moveReferenceActive(direction: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Previous Active Photo (←)")
            .accessibilityIdentifier(
                "Previous reference active photo"
            )

            Button {
                library.moveReferenceActive(direction: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Next Active Photo (→)")
            .accessibilityIdentifier(
                "Next reference active photo"
            )

            Menu {
                Menu("Choose Reference") {
                    ForEach(library.filtered) { asset in
                        Button {
                            library.setReferencePhoto(asset.id)
                        } label: {
                            Label(
                                asset.filename,
                                systemImage:
                                    asset.id
                                        == library.referenceState?
                                            .referenceID
                                    ? "checkmark"
                                    : "photo"
                            )
                        }
                        .disabled(
                            asset.id
                                == library.referenceState?.activeID
                        )
                    }
                    if library.referenceState?.referenceID != nil {
                        Divider()
                        Button(
                            "Clear Reference",
                            role: .destructive
                        ) {
                            library.clearReferencePhoto()
                        }
                    }
                }

                Button("Swap Reference and Active") {
                    library.swapReferencePhotos()
                }
                .disabled(library.referenceAsset == nil)

                Menu("Layout") {
                    ForEach(
                        PhotoReferenceLayout.allCases,
                        id: \.self
                    ) { layout in
                        Button {
                            library.setReferenceLayout(layout)
                        } label: {
                            Label(
                                layout.name,
                                systemImage:
                                    layout
                                        == library.referenceState?
                                            .layout
                                    ? "checkmark"
                                    : layout.systemImage
                            )
                        }
                    }
                }

                Toggle(
                    "Lock Reference",
                    isOn: Binding(
                        get: {
                            library.referenceState?
                                .isReferenceLocked
                                ?? false
                        },
                        set: library.setReferenceLocked
                    )
                )
                .disabled(library.referenceAsset == nil)
            } label: {
                Label(
                    "Reference Actions",
                    systemImage: "ellipsis.circle"
                )
                .labelStyle(.iconOnly)
            }
            .rawIconButtonTarget()
            .help("Choose, swap, arrange, and lock the Reference")

            Button("Done") {
                library.endReferenceView()
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.small)
            .accessibilityIdentifier("Finish reference view")
        }
    }
}

private enum ReferencePhotoRole {
    case reference
    case active

    var name: String {
        switch self {
        case .reference: return "Reference"
        case .active: return "Active"
        }
    }

    var systemImage: String {
        switch self {
        case .reference: return "pin.fill"
        case .active: return "slider.horizontal.3"
        }
    }

    var emphasisColor: Color {
        switch self {
        case .reference:
            return RAWDeskTokens.ColorToken.textSecondary
        case .active:
            return RAWDeskTokens.ColorToken.selection
        }
    }

    var badgeBackground: Color {
        switch self {
        case .reference:
            return RAWDeskTokens.ColorToken
                .controlElevated
        case .active:
            return RAWDeskTokens.ColorToken.selection.opacity(0.16)
        }
    }
}

private struct ReferencePhotoPane: View {
    let role: ReferencePhotoRole
    let asset: PhotoAsset?
    @ObservedObject var viewer: PhotoViewerViewModel
    @ObservedObject var library: LibraryViewModel
    @Binding var panOffset: CGSize
    var onCropChange: (NormalizedCrop) -> Void = { _ in }
    var onGuidedUprightGuidesChange:
        ([GuidedUprightGuide]) -> Void = { _ in }
    var onSpotRemovalChange: (SpotRemoval) -> Void = { _ in }
    var onBrushStrokeCommit:
        (LocalAdjustmentMask.ID, BrushStroke) -> Void = { _, _ in }
    var onObjectMaskPoint: (Double, Double) -> Void = { _, _ in }
    var onPointColorSample: (PointColorSample) -> Void = { _ in }
    var onMaskColorRangeSample: (PointColorSample) -> Void = { _ in }
    @State private var pixelSample: ImagePixelSample?

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            photoCanvas
                .overlay(alignment: .bottomLeading) {
                    if let pixelSample {
                        ReferencePixelReadoutView(
                            sample: pixelSample
                        )
                        .padding(RAWDeskTokens.Spacing.small)
                        .allowsHitTesting(false)
                    }
                }
            Divider()
            paneFooter
        }
        .overlay {
            Rectangle()
                .strokeBorder(
                    role.emphasisColor.opacity(0.72),
                    lineWidth: role == .active ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            role == .reference
                ? "Reference photo pane"
                : "Active reference photo pane"
        )
    }

    @ViewBuilder
    private var photoCanvas: some View {
        if role == .active {
            ImagePreviewView(
                viewer: viewer,
                asset: asset,
                onCropChange: onCropChange,
                onGuidedUprightGuidesChange:
                    onGuidedUprightGuidesChange,
                onSpotRemovalChange: onSpotRemovalChange,
                onBrushStrokeCommit: onBrushStrokeCommit,
                onObjectMaskPoint: onObjectMaskPoint,
                onPointColorSample: onPointColorSample,
                onMaskColorRangeSample: onMaskColorRangeSample,
                onPixelHover: {
                    pixelSample = $0
                }
            )
        } else {
            ReviewImageCanvas(
                viewer: viewer,
                asset: asset,
                panOffset: $panOffset,
                emptyMessage:
                    "Choose a Reference photo from the menu or filmstrip.",
                accessibilityText: "Reference photo preview",
                onPixelHover: {
                    pixelSample = $0
                }
            )
        }
    }

    private var paneHeader: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(
                role == .active && viewer.isShowingOriginal
                    ? "Active · Before"
                    : role.name,
                systemImage: role.systemImage
            )
            .font(RAWDeskTokens.Typography.sectionHeader)
            .foregroundStyle(role.emphasisColor)
            .padding(.horizontal, RAWDeskTokens.Spacing.small)
            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            .background(
                role.badgeBackground,
                in: Capsule()
            )
            Text(asset?.filename ?? "No Reference")
                .font(RAWDeskTokens.Typography.control)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if role == .reference,
               library.referenceState?
                .isReferenceLocked == true {
                Image(systemName: "lock.fill")
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .help("Reference is locked")
            }
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
            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                HStack(spacing: RAWDeskTokens.Spacing.small) {
                    VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                        Text(metadataSummary(asset))
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            .lineLimit(1)
                        if let captureDate =
                            asset.metadata?.captureDate
                            ?? asset.creationDate {
                            Text(
                                DisplayFormatters.date(
                                    captureDate
                                )
                            )
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if role == .active {
                        Text("Editable")
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(
                                role.emphasisColor
                            )
                        Button {
                            viewer.toggleOriginal()
                        } label: {
                            Label(
                                viewer.isShowingOriginal
                                    ? "Show Edited"
                                    : "Show Before",
                                systemImage:
                                    viewer.isShowingOriginal
                                    ? "eye.fill"
                                    : "eye"
                            )
                        }
                        .controlSize(.small)
                        .help("Toggle Active Before view (\\)")
                    } else {
                        Text("Static")
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(
                                role.emphasisColor
                            )
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    RAWReviewControls(
                        library: library,
                        asset: asset,
                        compact: true
                    )
                }
            }
            .padding(.horizontal, RAWDeskTokens.Spacing.small)
            .padding(.vertical, RAWDeskTokens.Spacing.small)
            .background(RAWDeskTokens.ColorToken.chrome)
        } else {
            HStack {
                Text(
                    "Choose a Reference while the Active photo remains editable."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                Spacer()
                Menu("Choose Reference") {
                    ForEach(library.filtered) { candidate in
                        Button(candidate.filename) {
                            library.setReferencePhoto(candidate.id)
                        }
                        .disabled(
                            candidate.id
                                == library.referenceState?.activeID
                        )
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, RAWDeskTokens.Spacing.small)
            .padding(.vertical, RAWDeskTokens.Spacing.small)
            .background(RAWDeskTokens.ColorToken.chrome)
        }
    }

    private func metadataSummary(
        _ asset: PhotoAsset
    ) -> String {
        let metadata = asset.metadata
        let values = [
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
        return values.isEmpty
            ? asset.format.displayName
            : values.joined(separator: " · ")
    }
}

private struct ReferencePixelReadoutView: View {
    let sample: ImagePixelSample

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                .fill(
                    RAWDeskTokens.ColorToken.imageSample(
                        red: sample.red,
                        green: sample.green,
                        blue: sample.blue
                    )
                )
                .frame(width: 20, height: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                        .strokeBorder(
                            RAWDeskTokens.ColorToken
                                .textPrimary.opacity(0.45),
                            lineWidth: 1
                        )
                }
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text(
                    "RGB \(rgb(sample.red)) \(rgb(sample.green)) \(rgb(sample.blue))"
                )
                let lab = sample.lab
                Text(
                    "Lab \(decimal(lab.lightness)) \(signed(lab.a)) \(signed(lab.b))"
                )
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            .font(RAWDeskTokens.Typography.numeric)
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .background(
            RAWDeskTokens.ColorToken.controlElevated,
            in: RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.control
            )
        )
        .shadow(
            color: .black.opacity(0.25),
            radius: 3,
            y: 1
        )
        .help(
            "Color-managed developed preview: sRGB 0–255 and CIE Lab D65"
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "Pixel color, red \(rgb(sample.red)), green \(rgb(sample.green)), blue \(rgb(sample.blue)), Lab lightness \(decimal(sample.lab.lightness)), a \(signed(sample.lab.a)), b \(signed(sample.lab.b))"
            )
        )
    }

    private func rgb(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }
}

struct ReferenceToneDelta: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static func calculate(
        reference: HistogramData,
        active: HistogramData
    ) -> ReferenceToneDelta? {
        guard let referenceRed = center(reference.red),
              let referenceGreen = center(reference.green),
              let referenceBlue = center(reference.blue),
              let activeRed = center(active.red),
              let activeGreen = center(active.green),
              let activeBlue = center(active.blue) else {
            return nil
        }
        return ReferenceToneDelta(
            red: (activeRed - referenceRed) * 100,
            green: (activeGreen - referenceGreen) * 100,
            blue: (activeBlue - referenceBlue) * 100
        )
    }

    private static func center(
        _ values: [CGFloat]
    ) -> Double? {
        guard values.count > 1 else { return nil }
        var weighted = 0.0
        var total = 0.0
        for (index, value) in values.enumerated() {
            let weight = Double(value * value)
            total += weight
            weighted +=
                (Double(index) / Double(values.count - 1))
                * weight
        }
        guard total > 0 else { return nil }
        return weighted / total
    }
}

private struct ReferenceToneDeltaView: View {
    let reference: HistogramData
    let active: HistogramData

    var body: some View {
        if let delta = ReferenceToneDelta.calculate(
            reference: reference,
            active: active
        ) {
            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Tone Δ")
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                deltaText("R", value: delta.red, color: .red)
                deltaText("G", value: delta.green, color: .green)
                deltaText("B", value: delta.blue, color: .blue)
            }
            .font(RAWDeskTokens.Typography.numeric)
            .help(
                "Whole-image Active minus Reference RGB histogram centers"
            )
            .accessibilityLabel(
                Text(
                    "Tone difference, red \(formatted(delta.red)), green \(formatted(delta.green)), blue \(formatted(delta.blue))"
                )
            )
        }
    }

    private func deltaText(
        _ channel: String,
        value: Double,
        color: Color
    ) -> some View {
        Text("\(channel) \(formatted(value))")
            .foregroundStyle(color)
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }
}

struct PhotoReferenceFilmstripView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let cellWidth: CGFloat = 112

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: RAWDeskTokens.Spacing.small) {
                    ForEach(library.filtered) { asset in
                        referenceCell(asset)
                            .id(asset.id)
                    }
                }
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            }
            .background(RAWDeskTokens.ColorToken.chrome)
            .onAppear {
                scrollToActive(
                    library.referenceState?.activeID,
                    proxy: proxy,
                    animated: false
                )
            }
            .onChange(
                of: library.referenceState?.activeID
            ) { _, id in
                scrollToActive(
                    id,
                    proxy: proxy,
                    animated: !reduceMotion
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Reference filmstrip")
    }

    private func referenceCell(
        _ asset: PhotoAsset
    ) -> some View {
        let isReference =
            asset.id == library.referenceState?.referenceID
        let isActive =
            asset.id == library.referenceState?.activeID
        return ThumbnailCellView(
            asset: asset,
            isSelected: isActive,
            isActive: isActive,
            compareRole: nil,
            surveyRole: nil,
            pixelSize: cellWidth * 2,
            duplicateGroupNumber:
                library.duplicateGroupNumber(for: asset.id),
            isDuplicateAnchor:
                library.isDuplicateAnchor(asset.id),
            isInQuickCollection:
                library.isInQuickCollection(asset.id),
            isInPhotoCollection:
                library.isInAnyPhotoCollection(asset.id),
            cullingEvaluation:
                library.cullingEvaluation(for: asset.id),
            cullingAnalysis:
                library.cullingAnalysis(for: asset.id),
            cullingStackNumber:
                library.cullingStackNumber(for: asset.id),
            stackMembership:
                library.catalogCollection == .exactDuplicates
                ? nil
                : library.photoStackMembership(for: asset.id),
            onStackToggle: {
                library.togglePhotoStack(containing: asset.id)
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
        .overlay {
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                .strokeBorder(
                    isReference
                        ? RAWDeskTokens.ColorToken
                            .textSecondary
                        : isActive
                            ? RAWDeskTokens.ColorToken.selection
                            : .clear,
                    lineWidth: isReference || isActive ? 3 : 0
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if isReference || isActive {
                Text(isReference ? "Reference" : "Active")
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
                    .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
                    .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                    .background(
                        isReference
                            ? RAWDeskTokens.ColorToken
                                .controlElevated
                            : RAWDeskTokens.ColorToken.selection,
                        in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                    )
                    .padding(RAWDeskTokens.Spacing.xSmall)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture {
            library.setReferenceActivePhoto(asset.id)
        }
        .contextMenu {
            Button("Make Active") {
                library.setReferenceActivePhoto(asset.id)
            }
            .disabled(isActive)
            Button("Set as Reference") {
                library.setReferencePhoto(asset.id)
            }
            .disabled(isActive)
        }
        .accessibilityLabel(
            Text(
                "\(asset.filename), \(isReference ? "Reference" : isActive ? "Active" : "filmstrip photo")"
            )
        )
    }

    private func scrollToActive(
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
