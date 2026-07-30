import SwiftUI

struct EditingInspectorView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var viewer: PhotoViewerViewModel
    let asset: PhotoAsset?
    var onActivateTool:
        (DevelopCanvasTool) -> Void = { _ in }

    @AppStorage("rawdesk.develop.section.light")
    private var lightExpanded = true
    @AppStorage("rawdesk.develop.section.color")
    private var colorExpanded = true
    @AppStorage("rawdesk.develop.section.toneCurve")
    private var toneCurveExpanded = false
    @AppStorage("rawdesk.develop.section.colorMixer")
    private var colorMixerExpanded = false
    @State private var selectedMixerChannel: ColorMixerChannel = .red
    @AppStorage("rawdesk.develop.section.pointColor")
    private var pointColorExpanded = false
    @State private var pointColorRangeExpanded = false
    @AppStorage("rawdesk.develop.section.colorGrading")
    private var colorGradingExpanded = false
    @State private var selectedGradingRegion: ColorGradingRegion = .shadows
    @AppStorage("rawdesk.develop.section.calibration")
    private var calibrationExpanded = false
    @AppStorage("rawdesk.develop.section.masks")
    private var masksExpanded = false
    @State private var selectedMaskID: LocalAdjustmentMask.ID?
    @State private var selectedMaskPrimaryOperationID: MaskPrimaryOperation.ID?
    @State private var selectedMaskPointColorID: PointColorAdjustment.ID?
    @State private var maskPointColorRangeExpanded = false
    @State private var isGeneratingSubjectMask = false
    @State private var subjectMaskMessage: String?
    @State private var isGeneratingSkyMask = false
    @State private var skyMaskMessage: String?
    @State private var isGeneratingDepthRange = false
    @State private var depthRangeMessage: String?
    @State private var depthRangeTargetMaskID: LocalAdjustmentMask.ID?
    @AppStorage("rawdesk.develop.section.remove")
    private var removalExpanded = false
    @AppStorage("rawdesk.develop.section.optics")
    private var opticsExpanded = false
    @State private var isAnalyzingChromaticAberration = false
    @State private var chromaticAberrationMessage: String?
    @AppStorage("rawdesk.develop.section.geometry")
    private var geometryExpanded = false
    @AppStorage("rawdesk.develop.section.effects")
    private var effectsExpanded = false
    @AppStorage("rawdesk.develop.section.detail")
    private var detailExpanded = false
    @AppStorage("rawdesk.develop.section.versions")
    private var versionsExpanded = false
    @State private var showingSoftProofSettings = false

    var body: some View {
        if let asset {
            VStack(spacing: 0) {
                fixedInspectorHeader(for: asset)

                ScrollView {
                    VStack(spacing: 0) {
                        if library
                            .canSynchronizeSelectedAdjustments {
                            autoSyncBanner
                                .padding(
                                    RAWDeskTokens.Spacing.medium
                                )
                        }

                        adjustmentGroup("Light", isExpanded: $lightExpanded) {
                        AdjustmentSlider(
                            title: "Exposure",
                            value: binding(\.exposure, for: asset),
                            range: -5...5,
                            step: 0.05,
                            format: { String(format: "%+.2f", $0) }
                        )
                        AdjustmentSlider(title: "Contrast", value: binding(\.contrast, for: asset))
                        AdjustmentSlider(title: "Highlights", value: binding(\.highlights, for: asset))
                        AdjustmentSlider(title: "Shadows", value: binding(\.shadows, for: asset))
                        AdjustmentSlider(title: "Whites", value: binding(\.whites, for: asset))
                        AdjustmentSlider(title: "Blacks", value: binding(\.blacks, for: asset))
                    }

                    adjustmentGroup("Color", isExpanded: $colorExpanded) {
                        AdjustmentSlider(title: "Temperature", value: binding(\.temperature, for: asset))
                        AdjustmentSlider(title: "Tint", value: binding(\.tint, for: asset))
                        AdjustmentSlider(title: "Vibrance", value: binding(\.vibrance, for: asset))
                        AdjustmentSlider(title: "Saturation", value: binding(\.saturation, for: asset))
                    }

                    adjustmentGroup("Tone Curve", isExpanded: $toneCurveExpanded) {
                        ToneCurveEditor(
                            curve: toneCurveBinding(for: asset),
                            isMixed: adjustmentValuesAreMixed {
                                $0.toneCurve
                            }
                        )
                    }

                    adjustmentGroup("Color Mixer", isExpanded: $colorMixerExpanded) {
                        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                            ForEach(ColorMixerChannel.allCases) { channel in
                                Button {
                                    selectedMixerChannel = channel
                                } label: {
                                    Circle()
                                        .fill(mixerColor(channel))
                                        .frame(width: 18, height: 18)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(
                                                    selectedMixerChannel == channel
                                                        ? RAWDeskTokens.ColorToken.textPrimary
                                                        : Color.clear,
                                                    lineWidth: 2
                                                )
                                                .padding(-RAWDeskTokens.Spacing.xSmall)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(channel.name))
                                .help(channel.name)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Text(selectedMixerChannel.name)
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .foregroundStyle(mixerColor(selectedMixerChannel))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        AdjustmentSlider(
                            title: "Hue",
                            value: colorMixerBinding(
                                channel: selectedMixerChannel,
                                component: .hue,
                                for: asset
                            )
                        )
                        AdjustmentSlider(
                            title: "Saturation",
                            value: colorMixerBinding(
                                channel: selectedMixerChannel,
                                component: .saturation,
                                for: asset
                            )
                        )
                        AdjustmentSlider(
                            title: "Luminance",
                            value: colorMixerBinding(
                                channel: selectedMixerChannel,
                                component: .luminance,
                                for: asset
                            )
                        )

                        HStack {
                            Button("Reset \(selectedMixerChannel.name)") {
                                resetColorMixerChannel(selectedMixerChannel, for: asset)
                            }
                            .disabled(
                                asset.userState.adjustments.colorMixer[selectedMixerChannel].isNeutral
                            )

                            Spacer()

                            Button("Reset All") {
                                resetColorMixer(for: asset)
                            }
                            .disabled(asset.userState.adjustments.colorMixer.isNeutral)
                        }
                        .buttonStyle(.link)
                        .font(RAWDeskTokens.Typography.metadata)
                    }

                    adjustmentGroup("Point Color", isExpanded: $pointColorExpanded) {
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Button {
                                viewer.setPointColorPicking(
                                    !viewer.isPointColorPicking
                                )
                            } label: {
                                Label(
                                    viewer.isPointColorPicking
                                        ? "Cancel Picker"
                                        : "Sample from Photo",
                                    systemImage: viewer.isPointColorPicking
                                        ? "xmark"
                                        : "eyedropper"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(
                                asset.userState.adjustments.pointColors.count >= 8
                                    && !viewer.isPointColorPicking
                            )

                            Text("\(asset.userState.adjustments.pointColors.count)/8")
                                .font(RAWDeskTokens.Typography.numeric)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }

                        if viewer.isPointColorPicking {
                            Text("Click a color in the photo to create a precise swatch.")
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        let pointColors = asset.userState.adjustments.pointColors
                        if pointColors.isEmpty {
                            Text("Sample a color from the photo, then refine only similar colors.")
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: RAWDeskTokens.Spacing.small) {
                                ForEach(pointColors) { point in
                                    Button {
                                        viewer.selectPointColor(point.id)
                                    } label: {
                                        Circle()
                                            .fill(pointColorColor(point))
                                            .frame(width: 22, height: 22)
                                            .overlay {
                                                Circle()
                                                    .strokeBorder(
                                                        selectedPointColor(
                                                            in: pointColors
                                                        )?.id == point.id
                                                            ? RAWDeskTokens.ColorToken.textPrimary
                                                            : RAWDeskTokens.ColorToken.textSecondary.opacity(0.45),
                                                        lineWidth: selectedPointColor(
                                                            in: pointColors
                                                        )?.id == point.id ? 2 : 1
                                                    )
                                                    .padding(-RAWDeskTokens.Spacing.xSmall)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(point.hueFamilyName))
                                    .help(
                                        "\(point.hueFamilyName), hue "
                                            + "\(Int(point.sample.hue.rounded())) degrees"
                                    )
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)

                            if let point = selectedPointColor(in: pointColors) {
                                HStack(spacing: RAWDeskTokens.Spacing.small) {
                                    RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                                        .fill(pointColorColor(point))
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                                                .strokeBorder(
                                                    RAWDeskTokens.ColorToken.textPrimary.opacity(0.25),
                                                    lineWidth: 1
                                                )
                                        }

                                    VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                                        Text(point.hueFamilyName)
                                            .font(RAWDeskTokens.Typography.sectionHeader)
                                        Text(
                                            "H \(Int(point.sample.hue.rounded()))°  "
                                                + "S \(Int(point.sample.saturation.rounded()))  "
                                                + "L \(Int(point.sample.luminance.rounded()))"
                                        )
                                        .font(RAWDeskTokens.Typography.numeric)
                                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    }
                                    Spacer()
                                }

                                AdjustmentSlider(
                                    title: "Hue Shift",
                                    value: pointColorBinding(
                                        pointID: point.id,
                                        keyPath: \.hueShift,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Saturation Shift",
                                    value: pointColorBinding(
                                        pointID: point.id,
                                        keyPath: \.saturationShift,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Luminance Shift",
                                    value: pointColorBinding(
                                        pointID: point.id,
                                        keyPath: \.luminanceShift,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Variance",
                                    value: pointColorBinding(
                                        pointID: point.id,
                                        keyPath: \.variance,
                                        for: asset
                                    )
                                )

                                DisclosureGroup(
                                    "Range",
                                    isExpanded: $pointColorRangeExpanded
                                ) {
                                    VStack(spacing: RAWDeskTokens.Spacing.small) {
                                        AdjustmentSlider(
                                            title: "Hue Range",
                                            value: pointColorBinding(
                                                pointID: point.id,
                                                keyPath: \.hueRange,
                                                for: asset
                                            ),
                                            range: 1...180,
                                            step: 1,
                                            resetValue: 30,
                                            format: { "\(Int($0.rounded()))°" }
                                        )
                                        AdjustmentSlider(
                                            title: "Saturation Range",
                                            value: pointColorBinding(
                                                pointID: point.id,
                                                keyPath: \.saturationRange,
                                                for: asset
                                            ),
                                            range: 1...100,
                                            resetValue: 35
                                        )
                                        AdjustmentSlider(
                                            title: "Luminance Range",
                                            value: pointColorBinding(
                                                pointID: point.id,
                                                keyPath: \.luminanceRange,
                                                for: asset
                                            ),
                                            range: 1...100,
                                            resetValue: 35
                                        )
                                    }
                                    .padding(.top, RAWDeskTokens.Spacing.small)
                                }
                                .font(RAWDeskTokens.Typography.sectionHeader)

                                Toggle(
                                    "Visualize Range",
                                    isOn: pointColorVisualizationBinding(
                                        point.id
                                    )
                                )
                                .toggleStyle(.switch)
                                .controlSize(.small)

                                HStack {
                                    Button("Reset Point") {
                                        resetPointColor(point.id, for: asset)
                                    }
                                    .disabled(pointColorIsDefault(point))

                                    Spacer()

                                    Button("Delete", role: .destructive) {
                                        deletePointColor(point.id, from: asset)
                                    }
                                }
                                .buttonStyle(.link)
                                .font(RAWDeskTokens.Typography.metadata)

                                Button("Remove All Swatches", role: .destructive) {
                                    resetPointColors(for: asset)
                                }
                                .buttonStyle(.link)
                                .font(RAWDeskTokens.Typography.metadata)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }

                    adjustmentGroup("Color Grading", isExpanded: $colorGradingExpanded) {
                        Picker("Tonal range", selection: $selectedGradingRegion) {
                            ForEach(ColorGradingRegion.allCases) { region in
                                Text(gradingShortName(region))
                                    .tag(region)
                                    .help(region.name)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Circle()
                                .fill(gradingColor(for: asset))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle()
                                        .strokeBorder(RAWDeskTokens.ColorToken.textPrimary.opacity(0.3), lineWidth: 1)
                                }
                            Text(selectedGradingRegion.name)
                                .font(RAWDeskTokens.Typography.sectionHeader)
                            Spacer()
                        }

                        AdjustmentSlider(
                            title: "Hue",
                            value: colorGradingBinding(
                                region: selectedGradingRegion,
                                component: .hue,
                                for: asset
                            ),
                            range: 0...360,
                            step: 1,
                            format: { "\(Int($0.rounded()))°" }
                        )
                        AdjustmentSlider(
                            title: "Saturation",
                            value: colorGradingBinding(
                                region: selectedGradingRegion,
                                component: .saturation,
                                for: asset
                            ),
                            range: 0...100
                        )
                        AdjustmentSlider(
                            title: "Luminance",
                            value: colorGradingBinding(
                                region: selectedGradingRegion,
                                component: .luminance,
                                for: asset
                            )
                        )

                        Divider()

                        AdjustmentSlider(
                            title: "Blending",
                            value: colorGradingGlobalBinding(\.blending, for: asset),
                            range: 0...100,
                            resetValue: 50
                        )
                        AdjustmentSlider(
                            title: "Balance",
                            value: colorGradingGlobalBinding(\.balance, for: asset)
                        )

                        HStack {
                            Button("Reset \(selectedGradingRegion.name)") {
                                resetColorGradingRegion(selectedGradingRegion, for: asset)
                            }
                            .disabled(
                                asset.userState.adjustments.colorGrading[
                                    selectedGradingRegion
                                ].isNeutral
                            )

                            Spacer()

                            Button("Reset All") {
                                resetColorGrading(for: asset)
                            }
                            .disabled(asset.userState.adjustments.colorGrading.isNeutral)
                        }
                        .buttonStyle(.link)
                        .font(RAWDeskTokens.Typography.metadata)
                    }

                    adjustmentGroup("Calibration", isExpanded: $calibrationExpanded) {
                        Label(
                            "Tune the camera color interpretation before creative color edits.",
                            systemImage: "camera.aperture"
                        )
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        AdjustmentSlider(
                            title: "Shadows Tint",
                            value: calibrationBinding(\.shadowsTint, for: asset)
                        )

                        Divider()

                        Text("Red Primary")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Hue",
                            value: calibrationBinding(\.redPrimaryHue, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Saturation",
                            value: calibrationBinding(
                                \.redPrimarySaturation,
                                for: asset
                            )
                        )

                        Text("Green Primary")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .foregroundStyle(Color.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Hue",
                            value: calibrationBinding(\.greenPrimaryHue, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Saturation",
                            value: calibrationBinding(
                                \.greenPrimarySaturation,
                                for: asset
                            )
                        )

                        Text("Blue Primary")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .foregroundStyle(Color.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Hue",
                            value: calibrationBinding(\.bluePrimaryHue, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Saturation",
                            value: calibrationBinding(
                                \.bluePrimarySaturation,
                                for: asset
                            )
                        )

                        Button("Reset Calibration") {
                            resetCalibration(for: asset)
                        }
                        .buttonStyle(.link)
                        .font(RAWDeskTokens.Typography.metadata)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .disabled(asset.userState.adjustments.calibration.isNeutral)
                    }

                    adjustmentGroup("Masks", isExpanded: $masksExpanded) {
                        Menu {
                            ForEach(LocalMaskKind.allCases) { kind in
                                Button {
                                    addMask(kind, for: asset)
                                } label: {
                                    Label(kind.name, systemImage: kind.systemImage)
                                }
                            }
                        } label: {
                            Label("Add Mask", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(
                            asset.userState.adjustments.localMasks.count >= 32
                                || isGeneratingSubjectMask
                                || isGeneratingSkyMask
                                || viewer.isGeneratingObjectMask
                        )

                        if isGeneratingSubjectMask {
                            ProgressView("Selecting subject on this Mac…")
                                .controlSize(.small)
                                .font(RAWDeskTokens.Typography.metadata)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let subjectMaskMessage {
                            Text(subjectMaskMessage)
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isGeneratingSkyMask {
                            ProgressView("Selecting sky on this Mac…")
                                .controlSize(.small)
                                .font(RAWDeskTokens.Typography.metadata)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let skyMaskMessage {
                            Text(skyMaskMessage)
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if viewer.isGeneratingObjectMask {
                            ProgressView("Selecting object on this Mac…")
                                .controlSize(.small)
                                .font(RAWDeskTokens.Typography.metadata)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if viewer.isObjectMaskPicking {
                            Label(
                                "Click the object in the photo. Esc or Done cancels.",
                                systemImage: "viewfinder.circle"
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let objectMaskMessage = viewer.objectMaskMessage {
                            Text(objectMaskMessage)
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        let masks = asset.userState.adjustments.localMasks
                        if masks.isEmpty {
                            Text(
                                "Select a subject, sky, object, paint, or add "
                                    + "a gradient to adjust one area."
                            )
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                                ForEach(masks) { mask in
                                    Button {
                                        selectedMaskID = mask.id
                                        if viewer.isObjectMaskPicking {
                                            viewer.setObjectMaskPicking(false)
                                        }
                                        if viewer.isMaskColorRangePicking,
                                           viewer.maskColorRangeTargetID != mask.id {
                                            viewer.setMaskColorRangePicking(false)
                                        }
                                        viewer.selectMaskRangeOperation(
                                            mask.rangeOperations.first?.id
                                        )
                                        selectedMaskPrimaryOperationID =
                                            mask.primaryOperations.first?.id
                                        selectedMaskPointColorID =
                                            mask.pointColors.first?.id
                                        if viewer.visualizedLocalMaskID != nil {
                                            viewer.setLocalMaskVisualization(mask.id)
                                        }
                                        if mask.kind == .brush {
                                            viewer.selectLocalMask(mask.id)
                                        } else if viewer.isBrushEditing {
                                            viewer.setBrushEditing(false)
                                            viewer.selectLocalMask(mask.id)
                                        } else {
                                            viewer.selectLocalMask(mask.id)
                                        }
                                    } label: {
                                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                                            Image(systemName: mask.kind.systemImage)
                                                .frame(width: 16)
                                            Text(mask.name)
                                                .lineLimit(1)
                                            Spacer()
                                            if mask.inverted {
                                                Image(systemName: "circle.lefthalf.filled")
                                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                            }
                                        }
                                        .padding(.horizontal, RAWDeskTokens.Spacing.small)
                                        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                                        .background(
                                            selectedMaskID == mask.id
                                                || (selectedMaskID == nil && mask.id == masks.first?.id)
                                                ? RAWDeskTokens.ColorToken.selection.opacity(0.18)
                                                : RAWDeskTokens.ColorToken.textSecondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(mask.name))
                                    .accessibilityValue(Text(mask.kind.name))
                                }
                            }

                            let selectedMask = masks.first { $0.id == selectedMaskID }
                                ?? masks.first
                            if let selectedMask {
                                Divider()

                                HStack {
                                    Label(
                                        selectedMask.kind.name,
                                        systemImage: selectedMask.kind.systemImage
                                    )
                                    .font(RAWDeskTokens.Typography.sectionHeader)

                                    Spacer()

                                    Toggle(
                                        "Invert",
                                        isOn: maskInversionBinding(
                                            maskID: selectedMask.id,
                                            for: asset
                                        )
                                    )
                                    .toggleStyle(.checkbox)
                                    .font(RAWDeskTokens.Typography.metadata)
                                }

                                Toggle(
                                    "Show Mask Overlay",
                                    isOn: maskOverlayBinding(maskID: selectedMask.id)
                                )
                                .toggleStyle(.checkbox)
                                .font(RAWDeskTokens.Typography.metadata)

                                if selectedMask.kind == .brush {
                                    Button {
                                        viewer.setBrushEditing(
                                            !viewer.isBrushEditing,
                                            selectedMaskID: selectedMask.id
                                        )
                                    } label: {
                                        Label(
                                            viewer.isBrushEditing
                                                ? "Done Painting Mask"
                                                : "Paint Mask on Photo",
                                            systemImage: viewer.isBrushEditing
                                                ? "checkmark"
                                                : "paintbrush.pointed"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(
                                        viewer.isBrushEditing
                                            ? RAWDeskTokens.ColorToken.selection
                                            : RAWDeskTokens.ColorToken.textSecondary
                                    )
                                    .controlSize(.small)

                                    MaskValueSlider(
                                        title: "Brush Size",
                                        value: maskGeometryBinding(
                                            maskID: selectedMask.id,
                                            keyPath: \.size,
                                            for: asset
                                        ),
                                        range: 0.005...0.25,
                                        step: 0.005,
                                        resetValue: 0.04,
                                        format: percentFormat
                                    )
                                    MaskValueSlider(
                                        title: "Feather",
                                        value: maskGeometryBinding(
                                            maskID: selectedMask.id,
                                            keyPath: \.feather,
                                            for: asset
                                        ),
                                        range: 0...1,
                                        step: 0.01,
                                        resetValue: 0.65,
                                        format: percentFormat
                                    )
                                    MaskValueSlider(
                                        title: "Flow",
                                        value: maskGeometryBinding(
                                            maskID: selectedMask.id,
                                            keyPath: \.flow,
                                            for: asset
                                        ),
                                        range: 0...1,
                                        step: 0.01,
                                        resetValue: 1,
                                        format: percentFormat
                                    )

                                    HStack {
                                        Button("Undo Stroke") {
                                            undoLastBrushStroke(selectedMask.id, for: asset)
                                        }
                                        .disabled(selectedMask.strokes.isEmpty)

                                        Spacer()

                                        Button("Clear") {
                                            clearBrushStrokes(selectedMask.id, for: asset)
                                        }
                                        .disabled(selectedMask.strokes.isEmpty)
                                    }
                                    .buttonStyle(.link)
                                    .font(RAWDeskTokens.Typography.metadata)
                                } else if selectedMask.kind != .subject
                                            && selectedMask.kind != .object
                                            && selectedMask.kind != .sky {
                                    Group {
                                        MaskValueSlider(
                                            title: "Horizontal",
                                            value: maskGeometryBinding(
                                                maskID: selectedMask.id,
                                                keyPath: \.centerX,
                                                for: asset
                                            ),
                                            range: 0...1,
                                            step: 0.01,
                                            resetValue: 0.5,
                                            format: percentFormat
                                        )
                                        MaskValueSlider(
                                            title: "Vertical",
                                            value: maskGeometryBinding(
                                                maskID: selectedMask.id,
                                                keyPath: \.centerY,
                                                for: asset
                                            ),
                                            range: 0...1,
                                            step: 0.01,
                                            resetValue: 0.5,
                                            format: percentFormat
                                        )
                                        MaskValueSlider(
                                            title: "Size",
                                            value: maskGeometryBinding(
                                                maskID: selectedMask.id,
                                                keyPath: \.size,
                                                for: asset
                                            ),
                                            range: 0.02...1.5,
                                            step: 0.01,
                                            resetValue: 0.55,
                                            format: percentFormat
                                        )
                                        MaskValueSlider(
                                            title: "Feather",
                                            value: maskGeometryBinding(
                                                maskID: selectedMask.id,
                                                keyPath: \.feather,
                                                for: asset
                                            ),
                                            range: 0...1,
                                            step: 0.01,
                                            resetValue: 0.5,
                                            format: percentFormat
                                        )
                                        if selectedMask.kind == .linear {
                                            MaskValueSlider(
                                                title: "Angle",
                                                value: maskGeometryBinding(
                                                    maskID: selectedMask.id,
                                                    keyPath: \.angle,
                                                    for: asset
                                                ),
                                                range: -180...180,
                                                step: 1,
                                                resetValue: 0,
                                                format: { String(format: "%+.0f°", $0) }
                                            )
                                        }
                                    }
                                } else {
                                    Label(
                                        selectedMask.kind == .object
                                            ? "Object selected locally with Apple Vision. No upload required."
                                            : selectedMask.kind == .sky
                                            ? "Sky selected locally. Embedded camera mattes are preferred when available."
                                            : "Subject selected locally with Apple Vision. No upload required.",
                                        systemImage: "lock.shield"
                                    )
                                    .font(RAWDeskTokens.Typography.metadata)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                maskPrimaryOperationsSection(selectedMask, for: asset)

                                maskRangeSection(selectedMask, for: asset)

                                Divider()

                                Text("Light")
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                AdjustmentSlider(
                                    title: "Exposure",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.exposure,
                                        for: asset
                                    ),
                                    range: -5...5,
                                    step: 0.05,
                                    format: { String(format: "%+.2f", $0) }
                                )
                                AdjustmentSlider(
                                    title: "Contrast",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.contrast,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Highlights",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.highlights,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Shadows",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.shadows,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Whites",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.whites,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Blacks",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.blacks,
                                        for: asset
                                    )
                                )

                                Divider()

                                Text("Color")
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                AdjustmentSlider(
                                    title: "Temperature",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.temperature,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Tint",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.tint,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Hue",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.hue,
                                        for: asset
                                    ),
                                    range: -180...180,
                                    step: 1,
                                    format: { String(format: "%+.0f°", $0) }
                                )
                                AdjustmentSlider(
                                    title: "Saturation",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.saturation,
                                        for: asset
                                    )
                                )

                                maskPointColorSection(selectedMask, for: asset)

                                Divider()

                                Text("Effects")
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                AdjustmentSlider(
                                    title: "Texture",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.texture,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Clarity",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.clarity,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Dehaze",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.dehaze,
                                        for: asset
                                    )
                                )

                                Divider()

                                Text("Detail")
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                AdjustmentSlider(
                                    title: "Sharpness",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.sharpness,
                                        for: asset
                                    )
                                )
                                AdjustmentSlider(
                                    title: "Noise Reduction",
                                    value: localAdjustmentBinding(
                                        maskID: selectedMask.id,
                                        keyPath: \.noiseReduction,
                                        for: asset
                                    ),
                                    range: 0...100
                                )

                                HStack {
                                    Button("Reset Mask") {
                                        resetMask(selectedMask.id, for: asset)
                                    }
                                    .disabled(
                                        selectedMask.adjustments.isNeutral
                                            && !selectedMask.pointColors.contains(
                                                where: \.isEffective
                                            )
                                    )

                                    Spacer()

                                    Button(role: .destructive) {
                                        deleteMask(selectedMask.id, from: asset)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .buttonStyle(.link)
                                .font(RAWDeskTokens.Typography.metadata)
                            }
                        }
                    }

                    adjustmentGroup("Remove", isExpanded: $removalExpanded) {
                        Menu {
                            ForEach(SpotRemovalKind.allCases) { kind in
                                Button {
                                    addSpotRemoval(kind, for: asset)
                                } label: {
                                    Label(kind.name, systemImage: kind.systemImage)
                                }
                            }
                        } label: {
                            Label("Add Repair", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(asset.userState.adjustments.spotRemovals.count >= 128)

                        let spots = asset.userState.adjustments.spotRemovals
                        if spots.isEmpty {
                            Text("Heal or clone a source area over an unwanted spot.")
                                .font(RAWDeskTokens.Typography.metadata)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Button {
                                let selectedID = viewer.selectedSpotRemovalID
                                    ?? spots.first?.id
                                viewer.setRemovalEditing(
                                    true,
                                    selectedSpotID: selectedID
                                )
                            } label: {
                                Label(
                                    viewer.isRemovalEditing
                                        ? "Repair Tool Active"
                                        : "Edit Repairs on Photo",
                                    systemImage: viewer.isRemovalEditing
                                        ? "checkmark"
                                        : "bandage"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(viewer.isRemovalEditing ? RAWDeskTokens.ColorToken.selection : RAWDeskTokens.ColorToken.textSecondary)
                            .controlSize(.small)
                            .disabled(viewer.isRemovalEditing)

                            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                                ForEach(spots) { spot in
                                    Button {
                                        viewer.selectSpotRemoval(spot.id)
                                    } label: {
                                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                                            Image(systemName: spot.kind.systemImage)
                                                .frame(width: 16)
                                            Text(spot.name)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.horizontal, RAWDeskTokens.Spacing.small)
                                        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                                        .background(
                                            viewer.selectedSpotRemovalID == spot.id
                                                || (viewer.selectedSpotRemovalID == nil
                                                    && spot.id == spots.first?.id)
                                                ? RAWDeskTokens.ColorToken.selection.opacity(0.18)
                                                : RAWDeskTokens.ColorToken.textSecondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(spot.name))
                                    .accessibilityValue(Text(spot.kind.name))
                                }
                            }

                            let selectedSpot = spots.first {
                                $0.id == viewer.selectedSpotRemovalID
                            } ?? spots.first
                            if let selectedSpot {
                                Divider()

                                Picker(
                                    "Mode",
                                    selection: spotKindBinding(
                                        spotID: selectedSpot.id,
                                        for: asset
                                    )
                                ) {
                                    ForEach(SpotRemovalKind.allCases) { kind in
                                        Label(kind.name, systemImage: kind.systemImage)
                                            .tag(kind)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)

                                Text("Target")
                                    .font(RAWDeskTokens.Typography.sectionHeader)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                MaskValueSlider(
                                    title: "Horizontal",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.targetX,
                                        for: asset
                                    ),
                                    range: 0...1,
                                    step: 0.01,
                                    resetValue: 0.5,
                                    format: percentFormat
                                )
                                MaskValueSlider(
                                    title: "Vertical",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.targetY,
                                        for: asset
                                    ),
                                    range: 0...1,
                                    step: 0.01,
                                    resetValue: 0.5,
                                    format: percentFormat
                                )

                                Text("Source")
                                    .font(RAWDeskTokens.Typography.sectionHeader)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                MaskValueSlider(
                                    title: "Horizontal",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.sourceX,
                                        for: asset
                                    ),
                                    range: 0...1,
                                    step: 0.01,
                                    resetValue: 0.36,
                                    format: percentFormat
                                )
                                MaskValueSlider(
                                    title: "Vertical",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.sourceY,
                                        for: asset
                                    ),
                                    range: 0...1,
                                    step: 0.01,
                                    resetValue: 0.42,
                                    format: percentFormat
                                )

                                MaskValueSlider(
                                    title: "Size",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.radius,
                                        for: asset
                                    ),
                                    range: 0.005...0.25,
                                    step: 0.005,
                                    resetValue: 0.06,
                                    format: percentFormat
                                )
                                MaskValueSlider(
                                    title: "Feather",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.feather,
                                        for: asset
                                    ),
                                    range: 0...1,
                                    step: 0.01,
                                    resetValue: 0.65,
                                    format: percentFormat
                                )
                                MaskValueSlider(
                                    title: "Opacity",
                                    value: spotGeometryBinding(
                                        spotID: selectedSpot.id,
                                        keyPath: \.opacity,
                                        for: asset
                                    ),
                                    range: 0...1,
                                    step: 0.01,
                                    resetValue: 1,
                                    format: percentFormat
                                )

                                Button(role: .destructive) {
                                    deleteSpotRemoval(selectedSpot.id, from: asset)
                                } label: {
                                    Label("Delete Repair", systemImage: "trash")
                                }
                                .buttonStyle(.link)
                                .font(RAWDeskTokens.Typography.metadata)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }

                    adjustmentGroup("Optics", isExpanded: $opticsExpanded) {
                        if asset.isRaw {
                            Label {
                                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                                    Text("Built-in RAW lens correction")
                                    Text("Applied automatically when the camera profile supports it.")
                                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                }
                            } icon: {
                                Image(systemName: "checkmark.seal")
                                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            }
                            .font(RAWDeskTokens.Typography.metadata)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("Manual Correction")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Distortion",
                            value: opticsBinding(\.distortion, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Lens Vignette",
                            value: opticsBinding(\.vignette, for: asset)
                        )

                        Divider()

                        Text("Chromatic Aberration")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                            HStack(spacing: RAWDeskTokens.Spacing.small) {
                                Image(
                                    systemName:
                                        asset.userState.adjustments
                                            .optics
                                            .automaticChromaticAberration
                                            == nil
                                            ? "scope"
                                            : "checkmark.circle.fill"
                                )
                                .foregroundStyle(
                                    asset.userState.adjustments
                                        .optics
                                        .automaticChromaticAberration
                                        == nil
                                        ? RAWDeskTokens.ColorToken.textSecondary
                                        : RAWDeskTokens.ColorToken.selection
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: RAWDeskTokens.Spacing.xSmall
                                ) {
                                    Text("Auto CA Analysis")
                                        .font(
                                            RAWDeskTokens.Typography
                                                .sectionHeader
                                        )
                                    Text(
                                        "Aligns color channels from high-contrast radial edges. Manual controls remain available for fine tuning."
                                    )
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                }
                            }

                            if isAnalyzingChromaticAberration,
                               asset.userState.adjustments
                                .optics
                                .automaticChromaticAberration
                                != nil {
                                HStack(spacing: RAWDeskTokens.Spacing.small) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Reanalyzing edges…")
                                }
                                .font(RAWDeskTokens.Typography.badge)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }

                            if let correction =
                                asset.userState.adjustments
                                    .optics
                                    .automaticChromaticAberration {
                                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                                    Text(
                                        correction.confidenceName
                                    )
                                    Text("•")
                                    Text(
                                        "\(correction.sampledEdgeCount) edges"
                                    )
                                    Text("•")
                                    Text(
                                        "\(correction.correctionCount) \(correction.correctionCount == 1 ? "correction" : "corrections")"
                                    )
                                }
                                .font(RAWDeskTokens.Typography.numeric)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .accessibilityElement(
                                    children: .combine
                                )

                                HStack(spacing: RAWDeskTokens.Spacing.small) {
                                    Button {
                                        analyzeChromaticAberration(
                                            for: asset
                                        )
                                    } label: {
                                        Label(
                                            "Analyze Again",
                                            systemImage:
                                                "arrow.clockwise"
                                        )
                                    }
                                    .disabled(
                                        isAnalyzingChromaticAberration
                                            || viewer.baseImage == nil
                                    )

                                    Button(role: .destructive) {
                                        removeAutomaticChromaticAberration(
                                            from: asset
                                        )
                                    } label: {
                                        Label(
                                            "Remove Auto",
                                            systemImage: "xmark"
                                        )
                                    }
                                    .disabled(
                                        isAnalyzingChromaticAberration
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button {
                                    analyzeChromaticAberration(
                                        for: asset
                                    )
                                } label: {
                                    if isAnalyzingChromaticAberration {
                                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Analyzing Edges…")
                                        }
                                        .frame(
                                            maxWidth: .infinity
                                        )
                                    } else {
                                        Label(
                                            "Analyze Photo",
                                            systemImage:
                                                "scope"
                                        )
                                        .frame(
                                            maxWidth: .infinity
                                        )
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .rawPrimaryButtonHeight()
                                .controlSize(.small)
                                .disabled(
                                    isAnalyzingChromaticAberration
                                        || viewer.baseImage == nil
                                )
                                .accessibilityIdentifier(
                                    "Analyze chromatic aberration"
                                )
                            }

                            if let chromaticAberrationMessage {
                                Text(chromaticAberrationMessage)
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                                    .accessibilityIdentifier(
                                        "Chromatic aberration analysis result"
                                    )
                            }
                        }
                        .padding(RAWDeskTokens.Spacing.small)
                        .background(
                            RAWDeskTokens.ColorToken.textSecondary.opacity(0.08),
                            in: RoundedRectangle(
                                cornerRadius: RAWDeskTokens.Radius.group,
                                style: .continuous
                            )
                        )

                        AdjustmentSlider(
                            title: "Red / Cyan Shift",
                            value: opticsBinding(\.redCyanShift, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Blue / Yellow Shift",
                            value: opticsBinding(\.blueYellowShift, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Purple Defringe",
                            value: opticsBinding(\.purpleDefringe, for: asset),
                            range: 0...100
                        )
                        AdjustmentSlider(
                            title: "Green Defringe",
                            value: opticsBinding(\.greenDefringe, for: asset),
                            range: 0...100
                        )

                        Button {
                            var updated = asset.userState.adjustments
                            updated.optics = .neutral
                            library.setAdjustments(
                                updated,
                                for: asset.id,
                                coalescingHistory: false
                            )
                            viewer.updateAdjustments(updated, for: asset.id)
                        } label: {
                            Label("Reset Optics", systemImage: "camera.aperture")
                        }
                        .buttonStyle(.link)
                        .font(RAWDeskTokens.Typography.metadata)
                        .disabled(asset.userState.adjustments.optics.isNeutral)
                    }

                    adjustmentGroup("Crop & Geometry", isExpanded: $geometryExpanded) {
                        Button {
                            viewer.setCropEditing(true)
                        } label: {
                            Label(
                                viewer.isCropEditing ? "Crop Tool Active" : "Edit Crop on Photo",
                                systemImage: viewer.isCropEditing ? "checkmark" : "crop"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewer.isCropEditing ? RAWDeskTokens.ColorToken.selection : RAWDeskTokens.ColorToken.textSecondary)
                        .controlSize(.small)
                        .disabled(viewer.isCropEditing)

                        let guides =
                            asset.userState.adjustments.geometry
                                .guidedUprightGuides
                        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                            HStack {
                                Label(
                                    "Guided Upright",
                                    systemImage: "ruler"
                                )
                                .font(RAWDeskTokens.Typography.sectionHeader)
                                Spacer()
                                Text("\(guides.count) / 4")
                                    .font(RAWDeskTokens.Typography.numeric)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }

                            Text(
                                "Draw 2–4 lines on the stable full-frame preview. RAWDesk classifies level/vertical edges, then applies perspective and restores the crop when you finish."
                            )
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )

                            Button {
                                viewer.setGuidedUprightEditing(
                                    !viewer.isGuidedUprightEditing
                                )
                            } label: {
                                Label(
                                    viewer.isGuidedUprightEditing
                                        ? "Done Drawing Guides"
                                        : "Draw Guides on Photo",
                                    systemImage:
                                        viewer.isGuidedUprightEditing
                                            ? "checkmark"
                                            : "pencil.and.ruler"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(
                                viewer.isGuidedUprightEditing
                                    ? RAWDeskTokens.ColorToken.selection
                                    : RAWDeskTokens.ColorToken.textSecondary
                            )
                            .controlSize(.small)

                            if !guides.isEmpty {
                                ForEach(
                                    Array(guides.enumerated()),
                                    id: \.element.id
                                ) { index, guide in
                                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                                        Text("\(index + 1)")
                                            .font(
                                                RAWDeskTokens.Typography
                                                    .numeric
                                            )
                                            .frame(width: 18, height: 18)
                                            .background(
                                                guide.orientation == .horizontal
                                                    ? Color.yellow.opacity(0.75)
                                                    : Color.cyan.opacity(0.75),
                                                in: Circle()
                                            )
                                            .foregroundStyle(.black)

                                        Picker(
                                            "Guide \(index + 1)",
                                            selection:
                                                guidedUprightOrientationBinding(
                                                    guideID: guide.id,
                                                    for: asset
                                                )
                                        ) {
                                            ForEach(
                                                GuidedUprightOrientation
                                                    .allCases
                                            ) { orientation in
                                                Text(orientation.name)
                                                    .tag(orientation)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.segmented)

                                        Button {
                                            updateGuidedUprightGuides(
                                                guides.filter {
                                                    $0.id != guide.id
                                                },
                                                for: asset
                                            )
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                        .rawIconButtonTarget()
                                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                        .help("Delete guide \(index + 1)")
                                        .accessibilityLabel(
                                            "Delete guide \(index + 1)"
                                        )
                                    }
                                }

                                if let solution =
                                    GuidedUprightSolver.solve(guides) {
                                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                                        Label(
                                            String(
                                                format: "%+.1f°",
                                                solution.straighten
                                            ),
                                            systemImage: "level"
                                        )
                                        Text(
                                            "V \(Int(solution.vertical.rounded()))"
                                        )
                                        Text(
                                            "H \(Int(solution.horizontal.rounded()))"
                                        )
                                    }
                                    .font(RAWDeskTokens.Typography.numeric)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .accessibilityElement(
                                        children: .ignore
                                    )
                                    .accessibilityLabel(
                                        "Guided solution: level \(solution.straighten), vertical \(solution.vertical), horizontal \(solution.horizontal)"
                                    )
                                } else {
                                    Text("Draw one more guide to solve.")
                                        .font(RAWDeskTokens.Typography.badge)
                                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                }

                                Button("Clear Guides") {
                                    updateGuidedUprightGuides(
                                        [],
                                        for: asset
                                    )
                                }
                                .buttonStyle(.link)
                                .font(RAWDeskTokens.Typography.metadata)
                            }
                        }
                        .padding(RAWDeskTokens.Spacing.small)
                        .background(
                            RAWDeskTokens.ColorToken
                                .controlElevated,
                            in: RoundedRectangle(
                                cornerRadius: RAWDeskTokens.Radius.group,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: RAWDeskTokens.Radius.group,
                                style: .continuous
                            )
                            .strokeBorder(
                                viewer.isGuidedUprightEditing
                                    ? RAWDeskTokens.ColorToken.selection.opacity(0.55)
                                    : RAWDeskTokens.ColorToken.textSecondary.opacity(0.16)
                            )
                        }

                        HStack {
                            Text("Orientation")
                                .font(RAWDeskTokens.Typography.metadata)
                            Spacer()
                            Text("\(asset.userState.adjustments.rotationDegrees)°")
                                .font(RAWDeskTokens.Typography.numeric)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }

                        ControlGroup {
                            Button {
                                applyOrientationChange(
                                    library.rotateLeft(for: asset.id),
                                    to: asset.id
                                )
                            } label: {
                                Label("Rotate Left", systemImage: "rotate.left")
                            }
                            .rawIconButtonTarget()
                            .help("Rotate left")
                            Button {
                                applyOrientationChange(
                                    library.rotateRight(for: asset.id),
                                    to: asset.id
                                )
                            } label: {
                                Label("Rotate Right", systemImage: "rotate.right")
                            }
                            .rawIconButtonTarget()
                            .help("Rotate right")
                            Button {
                                applyOrientationChange(
                                    library.flipHorizontal(for: asset.id),
                                    to: asset.id
                                )
                            } label: {
                                Label(
                                    "Flip Horizontal",
                                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
                                )
                            }
                            .rawIconButtonTarget()
                            .help("Flip horizontally")
                            Button {
                                applyOrientationChange(
                                    library.flipVertical(for: asset.id),
                                    to: asset.id
                                )
                            } label: {
                                Label(
                                    "Flip Vertical",
                                    systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down"
                                )
                            }
                            .rawIconButtonTarget()
                            .help("Flip vertically")
                        }
                        .labelStyle(.iconOnly)
                        .controlSize(.small)

                        HStack {
                            Text("Aspect")
                                .font(RAWDeskTokens.Typography.metadata)
                            Spacer()
                            Menu {
                                ForEach(CropAspectPreset.allCases) { preset in
                                    Button(preset.name) {
                                        applyCropPreset(preset, to: asset)
                                    }
                                }
                            } label: {
                                Text(asset.userState.adjustments.crop.isFullFrame
                                     ? "Full Frame"
                                     : "Cropped")
                                    .frame(minWidth: 72, alignment: .trailing)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        let crop = asset.userState.adjustments.crop
                        if !crop.isFullFrame {
                            CropPositionSlider(
                                title: "Horizontal",
                                value: cropPositionBinding(horizontal: true, for: asset),
                                isEnabled: crop.width < 0.999
                            )
                            CropPositionSlider(
                                title: "Vertical",
                                value: cropPositionBinding(horizontal: false, for: asset),
                                isEnabled: crop.height < 0.999
                            )
                        }

                        AdjustmentSlider(
                            title: "Straighten",
                            value: straightenBinding(for: asset),
                            range: -15...15,
                            step: 0.1,
                            format: { String(format: "%+.1f°", $0) }
                        )

                        Text("Perspective")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Vertical",
                            value: geometryBinding(
                                \.vertical,
                                for: asset,
                                clearsGuidedUpright: true
                            )
                        )
                        AdjustmentSlider(
                            title: "Horizontal",
                            value: geometryBinding(
                                \.horizontal,
                                for: asset,
                                clearsGuidedUpright: true
                            )
                        )
                        AdjustmentSlider(
                            title: "Aspect",
                            value: geometryBinding(\.aspect, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Scale",
                            value: geometryBinding(\.scale, for: asset),
                            range: 50...200,
                            resetValue: 100,
                            format: { "\(Int($0.rounded()))%" }
                        )
                        AdjustmentSlider(
                            title: "X Offset",
                            value: geometryBinding(\.offsetX, for: asset)
                        )
                        AdjustmentSlider(
                            title: "Y Offset",
                            value: geometryBinding(\.offsetY, for: asset)
                        )
                        Toggle(
                            "Constrain Crop",
                            isOn: geometryBoolBinding(\.constrainCrop, for: asset)
                        )
                        .font(RAWDeskTokens.Typography.metadata)

                        Button {
                            var updated = asset.userState.adjustments
                            updated.crop = .fullFrame
                            updated.straighten = 0
                            updated.geometry = .neutral
                            library.setAdjustments(
                                updated,
                                for: asset.id,
                                coalescingHistory: false
                            )
                            viewer.updateAdjustments(updated, for: asset.id)
                        } label: {
                            Label("Reset Crop & Geometry", systemImage: "crop.rotate")
                        }
                        .buttonStyle(.link)
                        .font(RAWDeskTokens.Typography.metadata)
                        .disabled(
                            crop.isFullFrame
                                && asset.userState.adjustments.straighten == 0
                                && asset.userState.adjustments.geometry.isNeutral
                        )
                    }

                    adjustmentGroup(
                        "Effects",
                        isExpanded: $effectsExpanded,
                        sectionEnabled:
                            effectsEnabledBinding(for: asset)
                    ) {
                        AdjustmentSlider(title: "Texture", value: binding(\.texture, for: asset))
                        AdjustmentSlider(title: "Clarity", value: binding(\.clarity, for: asset))
                        AdjustmentSlider(title: "Dehaze", value: binding(\.dehaze, for: asset))
                        AdjustmentSlider(title: "Vignette", value: binding(\.vignette, for: asset))

                        Divider()

                        Text("Grain")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Amount",
                            value: binding(\.grainAmount, for: asset),
                            range: 0...100
                        )
                        Group {
                            AdjustmentSlider(
                                title: "Size",
                                value: binding(\.grainSize, for: asset),
                                range: 1...100,
                                resetValue: 25
                            )
                            AdjustmentSlider(
                                title: "Roughness",
                                value: binding(\.grainRoughness, for: asset),
                                range: 0...100,
                                resetValue: 50
                            )
                        }
                        .disabled(asset.userState.adjustments.grainAmount == 0)
                    }

                    adjustmentGroup("Detail", isExpanded: $detailExpanded) {
                        Text("Sharpening")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Amount",
                            value: binding(\.sharpening, for: asset),
                            range: 0...100
                        )
                        Group {
                            AdjustmentSlider(
                                title: "Radius",
                                value: binding(\.sharpeningRadius, for: asset),
                                range: 0.5...3,
                                step: 0.1,
                                resetValue: 1,
                                format: { String(format: "%.1f", $0) }
                            )
                            AdjustmentSlider(
                                title: "Detail",
                                value: binding(\.sharpeningDetail, for: asset),
                                range: 0...100,
                                resetValue: 25,
                                format: { String(format: "%.0f", $0) }
                            )
                            AdjustmentSlider(
                                title: "Masking",
                                value: binding(\.sharpeningMasking, for: asset),
                                range: 0...100,
                                format: { String(format: "%.0f", $0) }
                            )
                        }
                        .disabled(asset.userState.adjustments.sharpening == 0)

                        Divider()

                        Text("Noise Reduction")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AdjustmentSlider(
                            title: "Luminance",
                            value: binding(\.noiseReduction, for: asset),
                            range: 0...100
                        )
                        Group {
                            AdjustmentSlider(
                                title: "Luminance Detail",
                                value: binding(\.noiseReductionDetail, for: asset),
                                range: 0...100,
                                resetValue: 50,
                                format: { String(format: "%.0f", $0) }
                            )
                            AdjustmentSlider(
                                title: "Luminance Contrast",
                                value: binding(\.noiseReductionContrast, for: asset),
                                range: 0...100,
                                format: { String(format: "%.0f", $0) }
                            )
                        }
                        .disabled(asset.userState.adjustments.noiseReduction == 0)

                        AdjustmentSlider(
                            title: "Color",
                            value: binding(\.colorNoiseReduction, for: asset),
                            range: 0...100
                        )
                        Group {
                            AdjustmentSlider(
                                title: "Color Detail",
                                value: binding(\.colorNoiseDetail, for: asset),
                                range: 0...100,
                                resetValue: 50,
                                format: { String(format: "%.0f", $0) }
                            )
                            AdjustmentSlider(
                                title: "Color Smoothness",
                                value: binding(\.colorNoiseSmoothness, for: asset),
                                range: 0...100,
                                resetValue: 50,
                                format: { String(format: "%.0f", $0) }
                            )
                        }
                        .disabled(asset.userState.adjustments.colorNoiseReduction == 0)
                    }

                    adjustmentGroup(
                        "Versions",
                        isExpanded: $versionsExpanded
                    ) {
                        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                            if !asset.userState.versions.isEmpty {
                                Text(
                                    "\(asset.userState.versions.count) saved"
                                )
                                .font(
                                    RAWDeskTokens.Typography
                                        .metadata
                                )
                                .foregroundStyle(
                                    RAWDeskTokens.ColorToken
                                        .textSecondary
                                )
                            }
                            Button {
                                library.createVersion(for: asset.id)
                            } label: {
                                Label("Save Current Version", systemImage: "plus.circle")
                            }
                            .buttonStyle(.link)
                            .font(RAWDeskTokens.Typography.metadata)

                            if asset.userState.versions.isEmpty {
                                Text("No saved versions")
                                    .font(RAWDeskTokens.Typography.metadata)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            } else {
                                ForEach(asset.userState.versions.reversed()) { version in
                                    HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                                        Button {
                                            library.applyVersion(version.id, to: asset.id)
                                            syncViewer(for: asset.id)
                                            if let proof =
                                                version
                                                    .softProofSettings {
                                                viewer
                                                    .restoreSoftProofSettings(
                                                        proof
                                                    )
                                            }
                                        } label: {
                                            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                                                Text(version.name)
                                                    .lineLimit(1)
                                                Text(version.createdAt.formatted(
                                                    date: .abbreviated,
                                                    time: .shortened
                                                ))
                                                .font(RAWDeskTokens.Typography.badge)
                                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                                if let proof =
                                                    version
                                                        .softProofSettings {
                                                    Label(
                                                        "\(proof.profile.shortName) · \(proof.renderingIntent.name)",
                                                        systemImage:
                                                            "printer"
                                                    )
                                                    .font(RAWDeskTokens.Typography.badge)
                                                    .foregroundStyle(
                                                        RAWDeskTokens
                                                            .ColorToken
                                                            .textSecondary
                                                    )
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            library.deleteVersion(version.id, from: asset.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                        .rawIconButtonTarget()
                                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                        .help("Delete \(version.name)")
                                        .accessibilityLabel(
                                            "Delete version \(version.name)"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: viewer.selectedLocalMaskID) { _, id in
                if let id {
                    selectedMaskID = id
                }
            }
            .onChange(of: asset.id) { _, _ in
                isAnalyzingChromaticAberration = false
                chromaticAberrationMessage = nil
            }
            .onChange(
                of:
                    asset.userState.adjustments
                        .optics
                        .automaticChromaticAberration
            ) { _, correction in
                if correction == nil {
                    chromaticAberrationMessage = nil
                }
            }
            }
        } else {
            RAWEmptyState(
                title: "No Photo Selected",
                systemImage: "slider.horizontal.3",
                message:
                    "Open a folder and select a photo to start editing."
            )
        }
    }

    private func fixedInspectorHeader(
        for asset: PhotoAsset
    ) -> some View {
        VStack(spacing: 0) {
            HistogramView(data: viewer.histogram)
                .frame(height: 94)
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
                .padding(.top, RAWDeskTokens.Spacing.small)
                .accessibilityLabel("RGB histogram")

            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Toggle(
                    "Soft Proof",
                    isOn: Binding(
                        get: {
                            viewer.softProofSettings
                                .isEnabled
                        },
                        set:
                            viewer
                                .setSoftProofEnabled
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
                .help("Preview the selected output profile")

                Button {
                    showingSoftProofSettings = true
                } label: {
                    Label(
                        "Proof Settings",
                        systemImage: "slider.horizontal.3"
                    )
                }
                .labelStyle(.iconOnly)
                .rawIconButtonTarget()
                .help(
                    "Soft Proof profile, intent, paper simulation, and gamut warnings"
                )
                .accessibilityLabel(
                    "Soft Proof settings"
                )
                .popover(
                    isPresented:
                        $showingSoftProofSettings
                ) {
                    SoftProofControlsView(
                        viewer: viewer,
                        onSaveProofVersion: {
                            library.createVersion(
                                for: asset.id,
                                name:
                                    "Proof – \(viewer.softProofSettings.profile.shortName)",
                                softProofSettings:
                                    viewer
                                        .softProofSettings
                            )
                        }
                    )
                    .padding(RAWDeskTokens.Spacing.medium)
                    .frame(width: 330)
                }

                Spacer(minLength: 4)

                Button("Reset All") {
                    resetAllAdjustments(for: asset)
                }
                .buttonStyle(.plain)
                .font(
                    RAWDeskTokens.Typography.metadata
                )
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                .disabled(
                    asset.userState.adjustments.isNeutral
                )
                .help("Reset all adjustments")
            }
            .padding(.horizontal, RAWDeskTokens.Spacing.small)
            .padding(.vertical, RAWDeskTokens.Spacing.small)

            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)

            toolRow

            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)

            fixedProfileSection(for: asset)
        }
        .background(RAWDeskTokens.ColorToken.panel)
    }

    /// Tools sit under the histogram, labelled, instead of on an unlabelled
    /// vertical rail beside the image. Selecting a tool and then adjusting it
    /// no longer means crossing the whole window, and the image well gains the
    /// rail's width back.
    private var toolRow: some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            ForEach(DevelopCanvasTool.allCases) { tool in
                RAWToolRailButton(
                    title: tool.name,
                    systemImage: tool.systemImage,
                    isSelected: activeTool == tool,
                    isEnabled: asset != nil,
                    caption: tool.shortName
                ) {
                    onActivateTool(tool)
                }
            }
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .accessibilityElement(children: .contain)
    }

    /// Mirrors the canvas's own notion of which tool is live, so the row
    /// reflects tools entered by keyboard or by the canvas itself.
    private var activeTool: DevelopCanvasTool? {
        if viewer.isCropEditing { return .crop }
        if viewer.isRemovalEditing { return .remove }
        if viewer.isBrushEditing
            || viewer.isObjectMaskPicking
            || viewer.isMaskColorRangePicking {
            return .mask
        }
        if viewer.isGuidedUprightEditing {
            return .guidedUpright
        }
        if viewer.isPointColorPicking {
            return .pointColor
        }
        return nil
    }

    private func fixedProfileSection(
        for asset: PhotoAsset
    ) -> some View {
        let settings =
            selectedDevelopmentProfile(for: asset)
        return VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            HStack {
                Text("Profile")
                    .font(
                        RAWDeskTokens.Typography
                            .sectionHeader
                    )
                Spacer()
                Button("Reset") {
                    resetDevelopmentProfile(for: asset)
                }
                .buttonStyle(.plain)
                .font(
                    RAWDeskTokens.Typography.metadata
                )
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                .disabled(settings.isDefault)
                .help("Reset Profile")
            }

            Menu {
                ForEach(
                    DevelopmentProfileGroup.allCases
                ) { group in
                    Section(group.name) {
                        ForEach(
                            DevelopmentProfile.allCases
                                .filter {
                                    $0.group == group
                                }
                        ) { profile in
                            Button {
                                selectDevelopmentProfile(
                                    profile,
                                    for: asset
                                )
                            } label: {
                                Label(
                                    profile.name,
                                    systemImage:
                                        settings.profile
                                            == profile
                                        ? "checkmark.circle.fill"
                                        : profile.systemImage
                                )
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Label(
                        settings.profile.name,
                        systemImage:
                            settings.profile.systemImage
                    )
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Browse Profiles")

            if settings.profile != .cameraDefault {
                AdjustmentSlider(
                    title: "Amount",
                    value:
                        developmentProfileAmountBinding(
                            for: asset
                        ),
                    range: 0...200,
                    step: 1,
                    resetValue: 100,
                    format: {
                        "\(Int($0.rounded()))%"
                    }
                )
            }
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
    }

    private var autoSyncBanner: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            HStack(alignment: .center, spacing: RAWDeskTokens.Spacing.small) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)

                Text(
                    library.isAutoSyncEnabled
                        ? "Auto Sync · \(library.selectedIDs.count) photos"
                        : "\(library.selectedIDs.count) photos selected"
                )
                .font(
                    RAWDeskTokens.Typography.sectionHeader
                )
                .lineLimit(1)

                Spacer(minLength: 4)

                Toggle(
                    "Auto Sync",
                    isOn: Binding(
                        get: {
                            library.isAutoSyncEnabled
                        },
                        set:
                            library.setAutoSyncEnabled
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("Auto Sync")
            }

            HStack(alignment: .center, spacing: RAWDeskTokens.Spacing.small) {
                Text(
                    library.isAutoSyncEnabled
                        ? "Only changed controls are synchronized."
                        : "Choose settings or enable Auto Sync."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

                Button("Sync…") {
                    library.presentSyncSettings()
                }
                .controlSize(.small)
            }
        }
        .padding(RAWDeskTokens.Spacing.small)
        .background(
            RAWDeskTokens.ColorToken.selection.opacity(
                library.isAutoSyncEnabled
                    ? 0.16
                    : 0.08
            ),
            in: RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.group
            )
        )
        .accessibilityElement(children: .contain)
    }

    private func resetAllAdjustments(
        for asset: PhotoAsset
    ) {
        library.resetAdjustments(for: asset.id)
        viewer.finishInteractiveTools()
        viewer.setObjectMaskGeneration(false)
        viewer.setLocalMaskVisualization(nil)
        viewer.selectMaskRangeOperation(nil)
        viewer.setPointColorVisualization(nil)
        viewer.updateAdjustments(
            .neutral,
            for: asset.id
        )
    }

    private func binding(
        _ keyPath: WritableKeyPath<PhotoAdjustments, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0[keyPath: keyPath]
            },
            set: {
                $0[keyPath: keyPath] = $1
            }
        )
    }

    private func effectsEnabledBinding(
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                library.selectedAsset?
                    .userState.adjustments
                    .effectsEnabled
                    ?? asset.userState.adjustments
                        .effectsEnabled
            },
            set: { isEnabled in
                var updated =
                    library.selectedAsset?
                        .userState.adjustments
                    ?? asset.userState.adjustments
                updated.effectsEnabled = isEnabled
                library.setAdjustments(
                    updated,
                    for: asset.id
                )
                viewer.updateAdjustments(
                    updated,
                    for: asset.id
                )
            }
        )
    }

    private func mixedDoubleBinding(
        for asset: PhotoAsset,
        value:
            @escaping (PhotoAdjustments) -> Double?,
        set:
            @escaping (
                inout PhotoAdjustments,
                Double
            ) -> Void
    ) -> MixedAdjustmentValue {
        let selectedValues = library.assets
            .filter {
                library.selectedIDs.contains($0.id)
            }
            .map {
                value($0.userState.adjustments)
            }
        let isMixed =
            PhotoAdjustmentMixedValuePlanner
                .doublesAreMixed(selectedValues)
        return MixedAdjustmentValue(
            binding: Binding(
                get: {
                    let adjustments =
                        library.selectedAsset?
                            .userState.adjustments
                        ?? asset.userState.adjustments
                    return value(adjustments) ?? 0
                },
                set: { newValue in
                    var updated =
                        library.selectedAsset?
                            .userState.adjustments
                        ?? asset.userState.adjustments
                    set(&updated, newValue)
                    updated = updated.normalized
                    library.setAdjustments(
                        updated,
                        for: asset.id
                    )
                    viewer.updateAdjustments(
                        updated,
                        for: asset.id
                    )
                }
            ),
            isMixed: isMixed
        )
    }

    private func adjustmentValuesAreMixed<
        Value: Equatable
    >(
        _ value:
            (PhotoAdjustments) -> Value
    ) -> Bool {
        let selectedValues = library.assets
            .filter {
                library.selectedIDs.contains($0.id)
            }
            .map {
                Optional(
                    value($0.userState.adjustments)
                )
            }
        return PhotoAdjustmentMixedValuePlanner
            .valuesAreMixed(selectedValues)
    }

    private func opticsBinding(
        _ keyPath: WritableKeyPath<OpticsAdjustments, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0.optics[keyPath: keyPath]
            },
            set: {
                $0.optics[keyPath: keyPath] = $1
            }
        )
    }

    private func analyzeChromaticAberration(
        for asset: PhotoAsset
    ) {
        guard let image = viewer.baseImage,
              let raster =
                AutomaticChromaticAberrationAnalyzer
                    .raster(from: image) else {
            chromaticAberrationMessage =
                "The current preview could not be analyzed."
            return
        }
        isAnalyzingChromaticAberration = true
        chromaticAberrationMessage = nil
        let assetID = asset.id
        Task { @MainActor in
            let correction = await Task.detached(
                priority: .userInitiated
            ) {
                AutomaticChromaticAberrationAnalyzer
                    .analyze(raster)
            }.value
            guard library.selectedAsset?.id == assetID else {
                isAnalyzingChromaticAberration = false
                return
            }
            guard let correction else {
                isAnalyzingChromaticAberration = false
                chromaticAberrationMessage =
                    "Not enough high-contrast radial edges were found. No correction was applied."
                return
            }
            var updated =
                library.selectedAsset?
                    .userState.adjustments
                ?? asset.userState.adjustments
            updated.optics
                .automaticChromaticAberration =
                    correction
            updated = updated.normalized
            library.setAdjustments(
                updated,
                for: assetID,
                coalescingHistory: false
            )
            viewer.updateAdjustments(
                updated,
                for: assetID
            )
            isAnalyzingChromaticAberration = false
            chromaticAberrationMessage =
                correction.correctionCount == 0
                ? "Analysis found no significant color displacement. The result is stored and can be reanalyzed."
                : "Applied \(correction.correctionCount) automatic \(correction.correctionCount == 1 ? "correction" : "corrections") from \(correction.sampledEdgeCount) sampled edges."
        }
    }

    private func removeAutomaticChromaticAberration(
        from asset: PhotoAsset
    ) {
        var updated =
            library.selectedAsset?
                .userState.adjustments
            ?? asset.userState.adjustments
        updated.optics
            .automaticChromaticAberration = nil
        updated = updated.normalized
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(
            updated,
            for: asset.id
        )
        chromaticAberrationMessage =
            "Automatic correction removed. Manual fine tuning was preserved."
    }

    private func straightenBinding(
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0.straighten
            },
            set: {
                $0.straighten = $1
                $0.geometry.guidedUprightGuides = []
            }
        )
    }

    private func geometryBinding(
        _ keyPath: WritableKeyPath<GeometryAdjustments, Double>,
        for asset: PhotoAsset,
        clearsGuidedUpright: Bool = false
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0.geometry[keyPath: keyPath]
            },
            set: {
                $0.geometry[keyPath: keyPath] = $1
                if clearsGuidedUpright {
                    $0.geometry.guidedUprightGuides = []
                }
            }
        )
    }

    private func guidedUprightOrientationBinding(
        guideID: GuidedUprightGuide.ID,
        for asset: PhotoAsset
    ) -> Binding<GuidedUprightOrientation> {
        Binding(
            get: {
                let guides =
                    library.selectedAsset?.userState.adjustments
                        .geometry.guidedUprightGuides
                    ?? asset.userState.adjustments.geometry
                        .guidedUprightGuides
                return guides.first {
                    $0.id == guideID
                }?.orientation ?? .horizontal
            },
            set: { orientation in
                var guides =
                    library.selectedAsset?.userState.adjustments
                        .geometry.guidedUprightGuides
                    ?? asset.userState.adjustments.geometry
                        .guidedUprightGuides
                guard let index = guides.firstIndex(
                    where: { $0.id == guideID }
                ) else {
                    return
                }
                guides[index].orientation = orientation
                updateGuidedUprightGuides(
                    guides,
                    for: asset
                )
            }
        )
    }

    private func updateGuidedUprightGuides(
        _ guides: [GuidedUprightGuide],
        for asset: PhotoAsset
    ) {
        let current =
            library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        let updated = GuidedUprightSolver.applying(
            guides,
            to: current
        )
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func geometryBoolBinding(
        _ keyPath: WritableKeyPath<GeometryAdjustments, Bool>,
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                let geometry = library.selectedAsset?.userState.adjustments.geometry
                    ?? asset.userState.adjustments.geometry
                return geometry[keyPath: keyPath]
            },
            set: { newValue in
                var updated = library.selectedAsset?.userState.adjustments
                    ?? asset.userState.adjustments
                updated.geometry[keyPath: keyPath] = newValue
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: asset.id,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: asset.id)
            }
        )
    }

    private func toneCurveBinding(for asset: PhotoAsset) -> Binding<ToneCurve> {
        Binding(
            get: {
                library.selectedAsset?.userState.adjustments.toneCurve
                    ?? asset.userState.adjustments.toneCurve
            },
            set: { curve in
                var updated = library.selectedAsset?.userState.adjustments
                    ?? asset.userState.adjustments
                updated.toneCurve = curve.normalized
                library.setAdjustments(updated, for: asset.id)
                viewer.updateAdjustments(updated, for: asset.id)
            }
        )
    }

    private enum MixerComponent {
        case hue
        case saturation
        case luminance
    }

    private func colorMixerBinding(
        channel: ColorMixerChannel,
        component: MixerComponent,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                let value =
                    adjustments.colorMixer[channel]
                switch component {
                case .hue: return value.hue
                case .saturation: return value.saturation
                case .luminance: return value.luminance
                }
            },
            set: { adjustments, newValue in
                var channelValue =
                    adjustments.colorMixer[channel]
                switch component {
                case .hue: channelValue.hue = newValue
                case .saturation: channelValue.saturation = newValue
                case .luminance: channelValue.luminance = newValue
                }
                adjustments.colorMixer[channel] =
                    channelValue
            }
        )
    }

    private func resetColorMixerChannel(
        _ channel: ColorMixerChannel,
        for asset: PhotoAsset
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.colorMixer[channel] = .neutral
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func resetColorMixer(for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.colorMixer = .neutral
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func mixerColor(_ channel: ColorMixerChannel) -> Color {
        switch channel {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .aqua: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .magenta: return .pink
        }
    }

    private func selectedPointColor(
        in points: [PointColorAdjustment]
    ) -> PointColorAdjustment? {
        points.first { $0.id == viewer.selectedPointColorID } ?? points.first
    }

    private func pointColorBinding(
        pointID: PointColorAdjustment.ID,
        keyPath: WritableKeyPath<PointColorAdjustment, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.pointColors
                    .first {
                        $0.id == pointID
                    }?[keyPath: keyPath]
            },
            set: { adjustments, newValue in
                guard let index =
                    adjustments.pointColors.firstIndex(
                    where: { $0.id == pointID }
                ) else {
                    return
                }
                adjustments.pointColors[index][
                    keyPath: keyPath
                ] = newValue
            }
        )
    }

    private func pointColorVisualizationBinding(
        _ pointID: PointColorAdjustment.ID
    ) -> Binding<Bool> {
        Binding(
            get: {
                viewer.visualizedPointColorID == pointID
            },
            set: { enabled in
                viewer.setPointColorVisualization(enabled ? pointID : nil)
            }
        )
    }

    private func resetPointColor(
        _ pointID: PointColorAdjustment.ID,
        for asset: PhotoAsset
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.pointColors.firstIndex(
            where: { $0.id == pointID }
        ) else {
            return
        }
        let existing = updated.pointColors[index]
        updated.pointColors[index] = PointColorAdjustment(
            id: existing.id,
            sample: existing.sample
        )
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func deletePointColor(
        _ pointID: PointColorAdjustment.ID,
        from asset: PhotoAsset
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.pointColors.firstIndex(
            where: { $0.id == pointID }
        ) else {
            return
        }
        updated.pointColors.remove(at: index)
        let nextID = updated.pointColors.indices.contains(index)
            ? updated.pointColors[index].id
            : updated.pointColors.last?.id
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(updated, for: asset.id)
        viewer.selectPointColor(nextID)
    }

    private func resetPointColors(for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.pointColors = []
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(updated, for: asset.id)
        viewer.selectPointColor(nil)
        viewer.setPointColorPicking(false)
        viewer.setPointColorVisualization(nil)
    }

    private func pointColorIsDefault(_ point: PointColorAdjustment) -> Bool {
        point == PointColorAdjustment(id: point.id, sample: point.sample)
    }

    private func pointColorColor(_ point: PointColorAdjustment) -> Color {
        let saturation = point.sample.saturation / 100
        let luminance = point.sample.luminance / 100
        let brightness = luminance + saturation * min(luminance, 1 - luminance)
        let hsvSaturation = brightness <= 0.000_1
            ? 0
            : 2 * (1 - luminance / brightness)
        return Color(
            hue: point.sample.hue / 360,
            saturation: min(1, max(0, hsvSaturation)),
            brightness: min(1, max(0, brightness))
        )
    }

    private enum ColorGradingComponent {
        case hue
        case saturation
        case luminance
    }

    private func colorGradingBinding(
        region: ColorGradingRegion,
        component: ColorGradingComponent,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                let wheel =
                    adjustments.colorGrading[region]
                switch component {
                case .hue: return wheel.hue
                case .saturation: return wheel.saturation
                case .luminance: return wheel.luminance
                }
            },
            set: { adjustments, newValue in
                var wheel =
                    adjustments.colorGrading[region]
                switch component {
                case .hue: wheel.hue = newValue
                case .saturation: wheel.saturation = newValue
                case .luminance: wheel.luminance = newValue
                }
                adjustments.colorGrading[region] =
                    wheel
            }
        )
    }

    private func colorGradingGlobalBinding(
        _ keyPath: WritableKeyPath<ColorGrading, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0.colorGrading[keyPath: keyPath]
            },
            set: {
                $0.colorGrading[keyPath: keyPath] = $1
            }
        )
    }

    private func resetColorGradingRegion(
        _ region: ColorGradingRegion,
        for asset: PhotoAsset
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.colorGrading[region] = .neutral
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func resetColorGrading(for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.colorGrading = .neutral
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func calibrationBinding(
        _ keyPath: WritableKeyPath<CalibrationAdjustments, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0.calibration[keyPath: keyPath]
            },
            set: {
                $0.calibration[keyPath: keyPath] = $1
            }
        )
    }

    private func resetCalibration(for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.calibration = .neutral
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func selectedDevelopmentProfile(
        for asset: PhotoAsset
    ) -> DevelopmentProfileSettings {
        library.selectedAsset?.userState.adjustments.developmentProfile
            ?? asset.userState.adjustments.developmentProfile
    }

    private func selectDevelopmentProfile(
        _ profile: DevelopmentProfile,
        for asset: PhotoAsset
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        let currentAmount = updated.developmentProfile.amount
        updated.developmentProfile = DevelopmentProfileSettings(
            profile: profile,
            amount: profile == .cameraDefault ? 100 : currentAmount
        )
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func developmentProfileAmountBinding(
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: {
                $0.developmentProfile.amount
            },
            set: { adjustments, amount in
                adjustments.developmentProfile =
                    DevelopmentProfileSettings(
                    profile:
                        adjustments
                            .developmentProfile
                            .profile,
                    amount: amount
                )
            }
        )
    }

    private func resetDevelopmentProfile(for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        updated.developmentProfile = .cameraDefault
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func profileCameraDescription(for asset: PhotoAsset) -> String? {
        let make = asset.metadata?.cameraMake?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = asset.metadata?.cameraModel?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !model.isEmpty {
            if !make.isEmpty,
               !model.localizedCaseInsensitiveContains(make) {
                return "\(make) \(model)"
            }
            return model
        }
        return make.isEmpty ? nil : make
    }

    private func gradingColor(for asset: PhotoAsset) -> Color {
        let grading = library.selectedAsset?.userState.adjustments.colorGrading
            ?? asset.userState.adjustments.colorGrading
        let wheel = grading[selectedGradingRegion]
        return Color(
            hue: wheel.hue / 360,
            saturation: wheel.saturation / 100,
            brightness: min(1, max(0.2, 0.68 + wheel.luminance / 100 * 0.28))
        )
    }

    private func gradingShortName(_ region: ColorGradingRegion) -> String {
        switch region {
        case .shadows: return "Shadows"
        case .midtones: return "Mids"
        case .highlights: return "Lights"
        case .global: return "Global"
        }
    }

    @ViewBuilder
    private func maskPrimaryOperationsSection(
        _ mask: LocalAdjustmentMask,
        for asset: PhotoAsset
    ) -> some View {
        Divider()

        HStack {
            Text("Primary Tool Operations")
                .font(RAWDeskTokens.Typography.sectionHeader)

            Spacer()

            Menu {
                ForEach(MaskCombinationMode.allCases) { combination in
                    Menu {
                        ForEach(LocalMaskKind.allCases) { kind in
                            Button {
                                addMaskPrimaryOperation(
                                    kind,
                                    combination: combination,
                                    to: mask.id,
                                    for: asset
                                )
                            } label: {
                                Label(kind.name, systemImage: kind.systemImage)
                            }
                        }
                    } label: {
                        Label(combination.name, systemImage: combination.systemImage)
                    }
                }
            } label: {
                Label("Add Tool", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .disabled(
                mask.primaryOperations.count >= 16
                    || isGeneratingSubjectMask
                    || isGeneratingSkyMask
                    || viewer.isGeneratingObjectMask
            )
        }

        Text(
            "Combine Subject, Object, Sky, Brush, and gradients in order "
                + "inside this one mask."
        )
        .font(RAWDeskTokens.Typography.badge)
        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

        if viewer.isObjectMaskPicking, viewer.objectMaskTargetID == mask.id {
            Label(
                "Click the object to \(viewer.pendingMaskPrimaryCombination.name.lowercased()) it.",
                systemImage: "viewfinder.circle"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if mask.primaryOperations.isEmpty {
            Text("No additional primary tools.")
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                ForEach(mask.primaryOperations) { operation in
                    Button {
                        selectedMaskPrimaryOperationID = operation.id
                        selectedMaskID = mask.id
                        viewer.selectLocalMask(mask.id)
                    } label: {
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Image(systemName: operation.combination.systemImage)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(width: 14)
                            Image(systemName: operation.kind.systemImage)
                                .frame(width: 14)
                            Text("\(operation.combination.name) \(operation.name)")
                                .lineLimit(1)
                            Spacer()
                            if !operation.isEnabled {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }
                            if operation.inverted {
                                Image(systemName: "circle.lefthalf.filled")
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }
                        }
                        .padding(.horizontal, RAWDeskTokens.Spacing.small)
                        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                        .background(
                            selectedMaskPrimaryOperation(mask)?.id == operation.id
                                ? RAWDeskTokens.ColorToken.selection.opacity(0.16)
                                : RAWDeskTokens.ColorToken.textSecondary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("\(operation.combination.name) \(operation.name)")
                    )
                }
            }

            if let operation = selectedMaskPrimaryOperation(mask) {
                maskPrimaryOperationEditor(operation, in: mask, for: asset)
            }
        }
    }

    @ViewBuilder
    private func maskPrimaryOperationEditor(
        _ operation: MaskPrimaryOperation,
        in mask: LocalAdjustmentMask,
        for asset: PhotoAsset
    ) -> some View {
        VStack(spacing: RAWDeskTokens.Spacing.small) {
            HStack {
                Toggle(
                    "Enabled",
                    isOn: maskPrimaryOperationEnabledBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        for: asset
                    )
                )
                .toggleStyle(.checkbox)

                Spacer()

                Toggle(
                    "Invert",
                    isOn: maskPrimaryOperationInversionBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        for: asset
                    )
                )
                .toggleStyle(.checkbox)
            }
            .font(RAWDeskTokens.Typography.metadata)

            Picker(
                "Combination",
                selection: maskPrimaryOperationCombinationBinding(
                    maskID: mask.id,
                    operationID: operation.id,
                    for: asset
                )
            ) {
                ForEach(MaskCombinationMode.allCases) { combination in
                    Text(combination.name).tag(combination)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            if operation.kind == .brush {
                let isPainting = viewer.isBrushEditing
                    && viewer.selectedLocalMaskID == mask.id
                    && viewer.selectedBrushPrimaryOperationID == operation.id
                Button {
                    viewer.setBrushEditing(
                        !isPainting,
                        selectedMaskID: mask.id,
                        primaryOperationID: operation.id
                    )
                } label: {
                    Label(
                        isPainting ? "Done Painting Component" : "Paint Component on Photo",
                        systemImage: isPainting ? "checkmark" : "paintbrush.pointed"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(isPainting ? RAWDeskTokens.ColorToken.selection : RAWDeskTokens.ColorToken.textSecondary)
                .controlSize(.small)

                MaskValueSlider(
                    title: "Brush Size",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.size,
                        for: asset
                    ),
                    range: 0.005...0.25,
                    step: 0.005,
                    resetValue: 0.04,
                    format: percentFormat
                )
                MaskValueSlider(
                    title: "Feather",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.feather,
                        for: asset
                    ),
                    range: 0...1,
                    step: 0.01,
                    resetValue: 0.65,
                    format: percentFormat
                )
                MaskValueSlider(
                    title: "Flow",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.flow,
                        for: asset
                    ),
                    range: 0...1,
                    step: 0.01,
                    resetValue: 1,
                    format: percentFormat
                )

                HStack {
                    Button("Undo Stroke") {
                        undoLastPrimaryBrushStroke(
                            operation.id,
                            in: mask.id,
                            for: asset
                        )
                    }
                    .disabled(operation.strokes.isEmpty)

                    Spacer()

                    Button("Clear") {
                        clearPrimaryBrushStrokes(
                            operation.id,
                            in: mask.id,
                            for: asset
                        )
                    }
                    .disabled(operation.strokes.isEmpty)
                }
                .buttonStyle(.link)
                .font(RAWDeskTokens.Typography.metadata)
            } else if operation.kind == .radial || operation.kind == .linear {
                MaskValueSlider(
                    title: "Horizontal",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.centerX,
                        for: asset
                    ),
                    range: 0...1,
                    step: 0.01,
                    resetValue: 0.5,
                    format: percentFormat
                )
                MaskValueSlider(
                    title: "Vertical",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.centerY,
                        for: asset
                    ),
                    range: 0...1,
                    step: 0.01,
                    resetValue: 0.5,
                    format: percentFormat
                )
                MaskValueSlider(
                    title: "Size",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.size,
                        for: asset
                    ),
                    range: 0.02...1.5,
                    step: 0.01,
                    resetValue: 0.55,
                    format: percentFormat
                )
                MaskValueSlider(
                    title: "Feather",
                    value: maskPrimaryOperationValueBinding(
                        maskID: mask.id,
                        operationID: operation.id,
                        keyPath: \.feather,
                        for: asset
                    ),
                    range: 0...1,
                    step: 0.01,
                    resetValue: 0.5,
                    format: percentFormat
                )
                if operation.kind == .linear {
                    MaskValueSlider(
                        title: "Angle",
                        value: maskPrimaryOperationValueBinding(
                            maskID: mask.id,
                            operationID: operation.id,
                            keyPath: \.angle,
                            for: asset
                        ),
                        range: -180...180,
                        step: 1,
                        resetValue: 0,
                        format: { String(format: "%+.0f°", $0) }
                    )
                }
            } else {
                Label(
                    "Selection data is stored locally with this operation.",
                    systemImage: "lock.shield"
                )
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                let operationIndex = mask.primaryOperations.firstIndex(
                    where: { $0.id == operation.id }
                ) ?? 0
                Button {
                    moveMaskPrimaryOperation(
                        operation.id,
                        in: mask.id,
                        offset: -1,
                        for: asset
                    )
                } label: {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .rawIconButtonTarget()
                .help("Move primary operation up")
                .disabled(operationIndex == 0)

                Button {
                    moveMaskPrimaryOperation(
                        operation.id,
                        in: mask.id,
                        offset: 1,
                        for: asset
                    )
                } label: {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .rawIconButtonTarget()
                .help("Move primary operation down")
                .disabled(operationIndex >= mask.primaryOperations.count - 1)

                Spacer()

                Button("Delete", role: .destructive) {
                    deleteMaskPrimaryOperation(
                        operation.id,
                        from: mask.id,
                        for: asset
                    )
                }
                .buttonStyle(.link)
                .font(RAWDeskTokens.Typography.metadata)
            }
        }
        .padding(RAWDeskTokens.Spacing.small)
        .background(
            RAWDeskTokens.ColorToken.textSecondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
        )
    }

    @ViewBuilder
    private func maskPointColorSection(
        _ mask: LocalAdjustmentMask,
        for asset: PhotoAsset
    ) -> some View {
        Divider()

        HStack {
            Text("Point Color")
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

            Spacer()

            Text("\(mask.pointColors.count)/8")
                .font(RAWDeskTokens.Typography.numeric)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }

        let isPickingThisMask = viewer.isPointColorPicking
            && viewer.pointColorMaskTargetID == mask.id
        Button {
            viewer.setPointColorPicking(
                !isPickingThisMask,
                selectedMaskID: mask.id
            )
        } label: {
            Label(
                isPickingThisMask ? "Cancel Local Picker" : "Sample Color for Mask",
                systemImage: isPickingThisMask ? "xmark" : "eyedropper"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(mask.pointColors.count >= 8 && !isPickingThisMask)

        if isPickingThisMask {
            Text("Click a color in the photo; its adjustment stays inside this mask.")
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if mask.pointColors.isEmpty {
            Text("No local Point Color samples.")
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                ForEach(mask.pointColors) { point in
                    Button {
                        selectedMaskPointColorID = point.id
                    } label: {
                        Circle()
                            .fill(pointColorColor(point))
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        selectedMaskPointColor(mask)?.id == point.id
                                            ? RAWDeskTokens.ColorToken.textPrimary
                                            : RAWDeskTokens.ColorToken.textSecondary.opacity(0.45),
                                        lineWidth: selectedMaskPointColor(mask)?.id == point.id
                                            ? 2
                                            : 1
                                    )
                                    .padding(-RAWDeskTokens.Spacing.xSmall)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Local \(point.hueFamilyName) point color"))
                }
                Spacer(minLength: 0)
            }

            if let point = selectedMaskPointColor(mask) {
                HStack(spacing: RAWDeskTokens.Spacing.small) {
                    RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                        .fill(pointColorColor(point))
                        .frame(width: 24, height: 24)
                    Text(point.hueFamilyName)
                        .font(RAWDeskTokens.Typography.sectionHeader)
                    Spacer()
                }

                AdjustmentSlider(
                    title: "Hue Shift",
                    value: maskPointColorBinding(
                        maskID: mask.id,
                        pointID: point.id,
                        keyPath: \.hueShift,
                        for: asset
                    )
                )
                AdjustmentSlider(
                    title: "Saturation Shift",
                    value: maskPointColorBinding(
                        maskID: mask.id,
                        pointID: point.id,
                        keyPath: \.saturationShift,
                        for: asset
                    )
                )
                AdjustmentSlider(
                    title: "Luminance Shift",
                    value: maskPointColorBinding(
                        maskID: mask.id,
                        pointID: point.id,
                        keyPath: \.luminanceShift,
                        for: asset
                    )
                )
                AdjustmentSlider(
                    title: "Variance",
                    value: maskPointColorBinding(
                        maskID: mask.id,
                        pointID: point.id,
                        keyPath: \.variance,
                        for: asset
                    )
                )

                DisclosureGroup("Range", isExpanded: $maskPointColorRangeExpanded) {
                    VStack(spacing: RAWDeskTokens.Spacing.small) {
                        AdjustmentSlider(
                            title: "Hue Range",
                            value: maskPointColorBinding(
                                maskID: mask.id,
                                pointID: point.id,
                                keyPath: \.hueRange,
                                for: asset
                            ),
                            range: 1...180,
                            step: 1,
                            resetValue: 30,
                            format: { "\(Int($0.rounded()))°" }
                        )
                        AdjustmentSlider(
                            title: "Saturation Range",
                            value: maskPointColorBinding(
                                maskID: mask.id,
                                pointID: point.id,
                                keyPath: \.saturationRange,
                                for: asset
                            ),
                            range: 1...100,
                            resetValue: 35
                        )
                        AdjustmentSlider(
                            title: "Luminance Range",
                            value: maskPointColorBinding(
                                maskID: mask.id,
                                pointID: point.id,
                                keyPath: \.luminanceRange,
                                for: asset
                            ),
                            range: 1...100,
                            resetValue: 35
                        )
                    }
                    .padding(.top, RAWDeskTokens.Spacing.small)
                }
                .font(RAWDeskTokens.Typography.sectionHeader)

                HStack {
                    Button("Reset Point") {
                        resetMaskPointColor(point.id, in: mask.id, for: asset)
                    }
                    .disabled(pointColorIsDefault(point))

                    Spacer()

                    Button("Delete", role: .destructive) {
                        deleteMaskPointColor(point.id, from: mask.id, for: asset)
                    }
                }
                .buttonStyle(.link)
                .font(RAWDeskTokens.Typography.metadata)
            }
        }
    }

    @ViewBuilder
    private func maskRangeSection(
        _ mask: LocalAdjustmentMask,
        for asset: PhotoAsset
    ) -> some View {
        Divider()

        HStack {
            Text("Range Operations")
                .font(RAWDeskTokens.Typography.sectionHeader)

            Spacer()

            Menu {
                ForEach(MaskCombinationMode.allCases) { combination in
                    Menu {
                        Button {
                            viewer.setMaskColorRangePicking(
                                true,
                                selectedMaskID: mask.id,
                                combination: combination
                            )
                        } label: {
                            Label(
                                "Color Range…",
                                systemImage: MaskRangeKind.color.systemImage
                            )
                        }

                        Button {
                            addLuminanceRange(
                                to: mask.id,
                                combination: combination,
                                for: asset
                            )
                        } label: {
                            Label(
                                "Luminance Range",
                                systemImage: MaskRangeKind.luminance.systemImage
                            )
                        }

                        Button {
                            addDepthRange(
                                to: mask.id,
                                combination: combination,
                                for: asset
                            )
                        } label: {
                            Label(
                                "Depth Range…",
                                systemImage: MaskRangeKind.depth.systemImage
                            )
                        }
                        .disabled(isGeneratingDepthRange)
                    } label: {
                        Label(combination.name, systemImage: combination.systemImage)
                    }
                }
            } label: {
                Label("Add Operation", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .disabled(
                mask.rangeOperations.count >= 16
                    || (
                        isGeneratingDepthRange
                            && depthRangeTargetMaskID == mask.id
                    )
            )
        }

        if viewer.isMaskColorRangePicking,
           viewer.maskColorRangeTargetID == mask.id {
            Label(
                "Click a color in the photo. Esc or Done cancels.",
                systemImage: "eyedropper"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if isGeneratingDepthRange,
           depthRangeTargetMaskID == mask.id {
            ProgressView("Reading embedded depth data…")
                .controlSize(.small)
                .font(RAWDeskTokens.Typography.metadata)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if depthRangeTargetMaskID == mask.id,
                  let depthRangeMessage {
            Text(depthRangeMessage)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if mask.rangeOperations.isEmpty {
            Text(
                "Limit this mask by color, brightness, or embedded depth, "
                    + "then combine selections in order."
            )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let selectedOperation = mask.rangeOperations.first {
                $0.id == viewer.selectedMaskRangeOperationID
            } ?? mask.rangeOperations.first

            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                ForEach(mask.rangeOperations) { operation in
                    Button {
                        viewer.selectMaskRangeOperation(operation.id)
                    } label: {
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Image(systemName: operation.kind.systemImage)
                                .frame(width: 15)
                            Text(operation.name)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: operation.combination.systemImage)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            if !operation.isEnabled {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }
                        }
                        .padding(.horizontal, RAWDeskTokens.Spacing.small)
                        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                        .background(
                            selectedOperation?.id == operation.id
                                ? RAWDeskTokens.ColorToken.selection.opacity(0.16)
                                : RAWDeskTokens.ColorToken.textSecondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(operation.name))
                    .accessibilityValue(
                        Text("\(operation.combination.name) \(operation.kind.name)")
                    )
                }
            }

            if let selectedOperation {
                Divider()

                HStack {
                    Label(
                        selectedOperation.kind.name,
                        systemImage: selectedOperation.kind.systemImage
                    )
                    .font(RAWDeskTokens.Typography.sectionHeader)

                    Spacer()

                    Toggle(
                        "On",
                        isOn: maskRangeEnabledBinding(
                            maskID: mask.id,
                            operationID: selectedOperation.id,
                            for: asset
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(RAWDeskTokens.Typography.metadata)

                    Toggle(
                        "Invert",
                        isOn: maskRangeInversionBinding(
                            maskID: mask.id,
                            operationID: selectedOperation.id,
                            for: asset
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(RAWDeskTokens.Typography.metadata)
                }

                Picker(
                    "Combine",
                    selection: maskRangeCombinationBinding(
                        maskID: mask.id,
                        operationID: selectedOperation.id,
                        for: asset
                    )
                ) {
                    ForEach(MaskCombinationMode.allCases) { combination in
                        Text(combination.name).tag(combination)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                Group {
                    switch selectedOperation.kind {
                    case .color:
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Circle()
                                .fill(maskRangeColor(selectedOperation.colorSample))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1)
                                }

                            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                                Text(
                                    "H\(Int(selectedOperation.colorSample.hue.rounded())) "
                                        + "S\(Int(selectedOperation.colorSample.saturation.rounded())) "
                                        + "L\(Int(selectedOperation.colorSample.luminance.rounded()))"
                                )
                                .font(RAWDeskTokens.Typography.numeric)
                                Text("Sampled from the developed photo")
                                    .font(RAWDeskTokens.Typography.badge)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }

                            Spacer()
                        }

                        Button {
                            viewer.setMaskColorRangePicking(
                                true,
                                selectedMaskID: mask.id,
                                operationID: selectedOperation.id,
                                combination: selectedOperation.combination
                            )
                        } label: {
                            Label("Resample from Photo", systemImage: "eyedropper")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        MaskValueSlider(
                            title: "Hue Range",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.hueRange,
                                for: asset
                            ),
                            range: 1...180,
                            step: 1,
                            resetValue: 30,
                            format: { "\(Int($0.rounded()))°" }
                        )
                        MaskValueSlider(
                            title: "Saturation Range",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.saturationRange,
                                for: asset
                            ),
                            range: 1...100,
                            step: 1,
                            resetValue: 35,
                            format: { "\(Int($0.rounded()))%" }
                        )
                        MaskValueSlider(
                            title: "Luminance Range",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.colorLuminanceRange,
                                for: asset
                            ),
                            range: 1...100,
                            step: 1,
                            resetValue: 35,
                            format: { "\(Int($0.rounded()))%" }
                        )

                    case .luminance:
                        MaskValueSlider(
                            title: "Minimum",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.luminanceMinimum,
                                for: asset
                            ),
                            range: 0...100,
                            step: 1,
                            resetValue: 20,
                            format: { "\(Int($0.rounded()))%" }
                        )
                        MaskValueSlider(
                            title: "Maximum",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.luminanceMaximum,
                                for: asset
                            ),
                            range: 0...100,
                            step: 1,
                            resetValue: 80,
                            format: { "\(Int($0.rounded()))%" }
                        )
                        MaskValueSlider(
                            title: "Feather",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.luminanceFeather,
                                for: asset
                            ),
                            range: 0...50,
                            step: 1,
                            resetValue: 15,
                            format: { "\(Int($0.rounded()))%" }
                        )

                    case .depth:
                        Label(
                            "0% is nearest and 100% is farthest in the "
                                + "embedded camera depth map.",
                            systemImage: "camera.metering.matrix"
                        )
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        MaskValueSlider(
                            title: "Near",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.depthMinimum,
                                for: asset
                            ),
                            range: 0...100,
                            step: 1,
                            resetValue: 0,
                            format: { "\(Int($0.rounded()))%" }
                        )
                        MaskValueSlider(
                            title: "Far",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.depthMaximum,
                                for: asset
                            ),
                            range: 0...100,
                            step: 1,
                            resetValue: 50,
                            format: { "\(Int($0.rounded()))%" }
                        )
                        MaskValueSlider(
                            title: "Feather",
                            value: maskRangeValueBinding(
                                maskID: mask.id,
                                operationID: selectedOperation.id,
                                keyPath: \.depthFeather,
                                for: asset
                            ),
                            range: 0...50,
                            step: 1,
                            resetValue: 10,
                            format: { "\(Int($0.rounded()))%" }
                        )
                    }
                }
                .disabled(!selectedOperation.isEnabled)

                HStack {
                    Text("Applied after the mask above, in list order.")
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

                    Spacer()

                    let operationIndex = mask.rangeOperations.firstIndex(
                        where: { $0.id == selectedOperation.id }
                    ) ?? 0
                    Button {
                        moveMaskRangeOperation(
                            selectedOperation.id,
                            in: mask.id,
                            offset: -1,
                            for: asset
                        )
                    } label: {
                        Label("Move Up", systemImage: "chevron.up")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .rawIconButtonTarget()
                    .help("Move operation up")
                    .disabled(operationIndex == 0)

                    Button {
                        moveMaskRangeOperation(
                            selectedOperation.id,
                            in: mask.id,
                            offset: 1,
                            for: asset
                        )
                    } label: {
                        Label("Move Down", systemImage: "chevron.down")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .rawIconButtonTarget()
                    .help("Move operation down")
                    .disabled(operationIndex >= mask.rangeOperations.count - 1)

                    Button(role: .destructive) {
                        deleteMaskRangeOperation(
                            selectedOperation.id,
                            from: mask.id,
                            for: asset
                        )
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.link)
                    .font(RAWDeskTokens.Typography.metadata)
                }
            }
        }
    }

    private var percentFormat: (Double) -> String {
        { "\(Int(($0 * 100).rounded()))%" }
    }

    private func selectedMaskPrimaryOperation(
        _ mask: LocalAdjustmentMask
    ) -> MaskPrimaryOperation? {
        mask.primaryOperations.first {
            $0.id == selectedMaskPrimaryOperationID
        } ?? mask.primaryOperations.first
    }

    private func addMaskPrimaryOperation(
        _ kind: LocalMaskKind,
        combination: MaskCombinationMode,
        to maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        switch kind {
        case .subject:
            viewer.setObjectMaskPicking(false)
            addSubjectPrimaryOperation(
                combination: combination,
                to: maskID,
                for: asset
            )
        case .object:
            guard viewer.baseImage != nil else {
                viewer.setObjectMaskGeneration(
                    false,
                    message: "Wait for the photo to finish loading, then try again."
                )
                return
            }
            viewer.setObjectMaskGeneration(false)
            viewer.setObjectMaskPicking(
                true,
                targetMaskID: maskID,
                combination: combination
            )
        case .sky:
            viewer.setObjectMaskPicking(false)
            addSkyPrimaryOperation(
                combination: combination,
                to: maskID,
                for: asset
            )
        case .brush, .radial, .linear:
            let masks = library.selectedAsset?.userState.adjustments.localMasks
                ?? asset.userState.adjustments.localMasks
            guard let mask = masks.first(where: { $0.id == maskID }),
                  mask.primaryOperations.count < 16 else {
                return
            }
            let count = mask.primaryOperations.filter { $0.kind == kind }.count + 1
            let shortName: String
            switch kind {
            case .brush: shortName = "Brush"
            case .radial: shortName = "Radial"
            case .linear: shortName = "Linear"
            default: shortName = kind.name
            }
            let operation = MaskPrimaryOperation(
                name: "\(shortName) \(count)",
                kind: kind,
                combination: combination,
                size: kind == .brush ? 0.04 : 0.55,
                feather: kind == .brush ? 0.65 : 0.5
            )
            updateMask(maskID, for: asset, coalescingHistory: false) { mask in
                mask.primaryOperations.append(operation)
            }
            selectedMaskID = maskID
            selectedMaskPrimaryOperationID = operation.id
            viewer.selectLocalMask(maskID)
            if kind == .brush {
                viewer.setBrushEditing(
                    true,
                    selectedMaskID: maskID,
                    primaryOperationID: operation.id
                )
            }
        }
    }

    private func addSubjectPrimaryOperation(
        combination: MaskCombinationMode,
        to maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        guard !isGeneratingSubjectMask else { return }
        guard let image = viewer.baseImage else {
            subjectMaskMessage = "Wait for the photo to finish loading, then try again."
            return
        }

        let assetID = asset.id
        let sourceAdjustments = asset.userState.adjustments
        let orientationAdjustments = PhotoAdjustments(
            rotationDegrees: sourceAdjustments.rotationDegrees,
            flipHorizontal: sourceAdjustments.flipHorizontal,
            flipVertical: sourceAdjustments.flipVertical
        )
        isGeneratingSubjectMask = true
        subjectMaskMessage = nil

        Task { @MainActor in
            let result: Result<Data, Error> = await Task.detached(
                priority: .userInitiated
            ) {
                Result {
                    let orientedImage = try PhotoProcessor.apply(
                        to: image,
                        adjustments: orientationAdjustments
                    )
                    return try SubjectMaskGenerator.generateMaskPNG(
                        from: orientedImage
                    )
                }
            }.value

            isGeneratingSubjectMask = false
            switch result {
            case let .success(maskData):
                guard let currentAsset = library.assets.first(
                    where: { $0.id == assetID }
                ) else {
                    subjectMaskMessage = "The photo is no longer in the open library."
                    return
                }
                var updated = currentAsset.userState.adjustments
                guard let maskIndex = updated.localMasks.firstIndex(
                    where: { $0.id == maskID }
                ), updated.localMasks[maskIndex].primaryOperations.count < 16 else {
                    subjectMaskMessage = "The target mask is no longer available."
                    return
                }
                let count = updated.localMasks[maskIndex].primaryOperations
                    .filter { $0.kind == .subject }
                    .count + 1
                let operation = MaskPrimaryOperation(
                    name: "Subject \(count)",
                    kind: .subject,
                    combination: combination,
                    rasterMaskData: maskData
                )
                updated.localMasks[maskIndex].primaryOperations.append(operation)
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: assetID,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: assetID)
                selectedMaskID = maskID
                selectedMaskPrimaryOperationID = operation.id
                viewer.selectLocalMask(maskID)
                subjectMaskMessage =
                    "Subject added to the mask as \(combination.name)."

            case let .failure(error):
                subjectMaskMessage = error.localizedDescription
            }
        }
    }

    private func addSkyPrimaryOperation(
        combination: MaskCombinationMode,
        to maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        guard !isGeneratingSkyMask else { return }
        guard let image = viewer.baseImage else {
            skyMaskMessage = "Wait for the photo to finish loading, then try again."
            return
        }

        let assetID = asset.id
        let sourceAdjustments = asset.userState.adjustments
        let orientationAdjustments = PhotoAdjustments(
            rotationDegrees: sourceAdjustments.rotationDegrees,
            flipHorizontal: sourceAdjustments.flipHorizontal,
            flipVertical: sourceAdjustments.flipVertical
        )
        isGeneratingSkyMask = true
        skyMaskMessage = nil

        Task { @MainActor in
            let result: Result<AuxiliaryMaskGenerator.SkyResult, Error> =
                await Task.detached(priority: .userInitiated) {
                    Result {
                        let orientedImage = try PhotoProcessor.apply(
                            to: image,
                            adjustments: orientationAdjustments
                        )
                        return try AuxiliaryMaskGenerator.generateSkyMaskPNG(
                            from: orientedImage,
                            assetURL: asset.url,
                            rotationDegrees: sourceAdjustments.rotationDegrees,
                            flipHorizontal: sourceAdjustments.flipHorizontal,
                            flipVertical: sourceAdjustments.flipVertical
                        )
                    }
                }.value

            isGeneratingSkyMask = false
            switch result {
            case let .success(skyResult):
                guard let currentAsset = library.assets.first(
                    where: { $0.id == assetID }
                ) else {
                    skyMaskMessage = "The photo is no longer in the open library."
                    return
                }
                var updated = currentAsset.userState.adjustments
                guard let maskIndex = updated.localMasks.firstIndex(
                    where: { $0.id == maskID }
                ), updated.localMasks[maskIndex].primaryOperations.count < 16 else {
                    skyMaskMessage = "The target mask is no longer available."
                    return
                }
                let count = updated.localMasks[maskIndex].primaryOperations
                    .filter { $0.kind == .sky }
                    .count + 1
                let operation = MaskPrimaryOperation(
                    name: "Sky \(count)",
                    kind: .sky,
                    combination: combination,
                    rasterMaskData: skyResult.pngData
                )
                updated.localMasks[maskIndex].primaryOperations.append(operation)
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: assetID,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: assetID)
                selectedMaskID = maskID
                selectedMaskPrimaryOperationID = operation.id
                viewer.selectLocalMask(maskID)
                let sourceName = skyResult.source == .embeddedMatte
                    ? "camera matte"
                    : "local estimate"
                skyMaskMessage =
                    "Sky \(sourceName) added to the mask as \(combination.name)."

            case let .failure(error):
                skyMaskMessage = error.localizedDescription
            }
        }
    }

    private func maskPrimaryOperation(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskPrimaryOperation.ID,
        for asset: PhotoAsset
    ) -> MaskPrimaryOperation? {
        let masks = library.selectedAsset?.userState.adjustments.localMasks
            ?? asset.userState.adjustments.localMasks
        return masks.first(where: { $0.id == maskID })?
            .primaryOperations.first(where: { $0.id == operationID })
    }

    private func updateMaskPrimaryOperation(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskPrimaryOperation.ID,
        for asset: PhotoAsset,
        coalescingHistory: Bool = true,
        mutation: (inout MaskPrimaryOperation) -> Void
    ) {
        updateMask(
            maskID,
            for: asset,
            coalescingHistory: coalescingHistory
        ) { mask in
            guard let index = mask.primaryOperations.firstIndex(
                where: { $0.id == operationID }
            ) else {
                return
            }
            mutation(&mask.primaryOperations[index])
        }
    }

    private func maskPrimaryOperationEnabledBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskPrimaryOperation.ID,
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                maskPrimaryOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                )?.isEnabled ?? false
            },
            set: { enabled in
                updateMaskPrimaryOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                ) { operation in
                    operation.isEnabled = enabled
                }
            }
        )
    }

    private func maskPrimaryOperationInversionBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskPrimaryOperation.ID,
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                maskPrimaryOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                )?.inverted ?? false
            },
            set: { inverted in
                updateMaskPrimaryOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                ) { operation in
                    operation.inverted = inverted
                }
            }
        )
    }

    private func maskPrimaryOperationCombinationBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskPrimaryOperation.ID,
        for asset: PhotoAsset
    ) -> Binding<MaskCombinationMode> {
        Binding(
            get: {
                maskPrimaryOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                )?.combination ?? .add
            },
            set: { combination in
                updateMaskPrimaryOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                ) { operation in
                    operation.combination = combination
                }
            }
        )
    }

    private func maskPrimaryOperationValueBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskPrimaryOperation.ID,
        keyPath: WritableKeyPath<MaskPrimaryOperation, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.localMasks
                    .first {
                        $0.id == maskID
                    }?
                    .primaryOperations
                    .first {
                        $0.id == operationID
                    }?[keyPath: keyPath]
            },
            set: { adjustments, value in
                guard let maskIndex =
                    adjustments.localMasks.firstIndex(
                        where: {
                            $0.id == maskID
                        }
                    ),
                      let operationIndex =
                        adjustments.localMasks[
                            maskIndex
                        ].primaryOperations.firstIndex(
                            where: {
                                $0.id == operationID
                            }
                        ) else {
                    return
                }
                adjustments.localMasks[maskIndex]
                    .primaryOperations[operationIndex][
                        keyPath: keyPath
                    ] = value
            }
        )
    }

    private func moveMaskPrimaryOperation(
        _ operationID: MaskPrimaryOperation.ID,
        in maskID: LocalAdjustmentMask.ID,
        offset: Int,
        for asset: PhotoAsset
    ) {
        guard offset != 0 else { return }
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard let sourceIndex = mask.primaryOperations.firstIndex(
                where: { $0.id == operationID }
            ) else {
                return
            }
            let destinationIndex = min(
                mask.primaryOperations.count - 1,
                max(0, sourceIndex + offset)
            )
            guard destinationIndex != sourceIndex else { return }
            let operation = mask.primaryOperations.remove(at: sourceIndex)
            mask.primaryOperations.insert(operation, at: destinationIndex)
        }
        selectedMaskPrimaryOperationID = operationID
    }

    private func deleteMaskPrimaryOperation(
        _ operationID: MaskPrimaryOperation.ID,
        from maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        var nextID: MaskPrimaryOperation.ID?
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard let index = mask.primaryOperations.firstIndex(
                where: { $0.id == operationID }
            ) else {
                return
            }
            mask.primaryOperations.remove(at: index)
            nextID = mask.primaryOperations.indices.contains(index)
                ? mask.primaryOperations[index].id
                : mask.primaryOperations.last?.id
        }
        selectedMaskPrimaryOperationID = nextID
        if viewer.selectedBrushPrimaryOperationID == operationID {
            viewer.setBrushEditing(false)
            viewer.selectLocalMask(maskID)
        }
    }

    private func undoLastPrimaryBrushStroke(
        _ operationID: MaskPrimaryOperation.ID,
        in maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        updateMaskPrimaryOperation(
            maskID: maskID,
            operationID: operationID,
            for: asset,
            coalescingHistory: false
        ) { operation in
            guard !operation.strokes.isEmpty else { return }
            operation.strokes.removeLast()
        }
    }

    private func clearPrimaryBrushStrokes(
        _ operationID: MaskPrimaryOperation.ID,
        in maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        updateMaskPrimaryOperation(
            maskID: maskID,
            operationID: operationID,
            for: asset,
            coalescingHistory: false
        ) { operation in
            operation.strokes.removeAll()
        }
    }

    private func selectedMaskPointColor(
        _ mask: LocalAdjustmentMask
    ) -> PointColorAdjustment? {
        mask.pointColors.first { $0.id == selectedMaskPointColorID }
            ?? mask.pointColors.last
    }

    private func maskPointColorBinding(
        maskID: LocalAdjustmentMask.ID,
        pointID: PointColorAdjustment.ID,
        keyPath: WritableKeyPath<PointColorAdjustment, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.localMasks
                    .first {
                        $0.id == maskID
                    }?
                    .pointColors
                    .first {
                        $0.id == pointID
                    }?[keyPath: keyPath]
            },
            set: { adjustments, value in
                guard let maskIndex =
                    adjustments.localMasks.firstIndex(
                        where: {
                            $0.id == maskID
                        }
                    ),
                      let pointIndex =
                        adjustments.localMasks[
                            maskIndex
                        ].pointColors.firstIndex(
                            where: {
                                $0.id == pointID
                            }
                        ) else {
                    return
                }
                adjustments.localMasks[maskIndex]
                    .pointColors[pointIndex][
                        keyPath: keyPath
                    ] = value
            }
        )
    }

    private func resetMaskPointColor(
        _ pointID: PointColorAdjustment.ID,
        in maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard let index = mask.pointColors.firstIndex(
                where: { $0.id == pointID }
            ) else {
                return
            }
            let existing = mask.pointColors[index]
            mask.pointColors[index] = PointColorAdjustment(
                id: existing.id,
                sample: existing.sample
            )
        }
    }

    private func deleteMaskPointColor(
        _ pointID: PointColorAdjustment.ID,
        from maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        var nextID: PointColorAdjustment.ID?
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard let index = mask.pointColors.firstIndex(
                where: { $0.id == pointID }
            ) else {
                return
            }
            mask.pointColors.remove(at: index)
            nextID = mask.pointColors.indices.contains(index)
                ? mask.pointColors[index].id
                : mask.pointColors.last?.id
        }
        selectedMaskPointColorID = nextID
    }

    private func maskOverlayBinding(
        maskID: LocalAdjustmentMask.ID
    ) -> Binding<Bool> {
        Binding(
            get: { viewer.visualizedLocalMaskID == maskID },
            set: { show in
                viewer.setLocalMaskVisualization(show ? maskID : nil)
            }
        )
    }

    private func addLuminanceRange(
        to maskID: LocalAdjustmentMask.ID,
        combination: MaskCombinationMode,
        for asset: PhotoAsset
    ) {
        let masks = library.selectedAsset?.userState.adjustments.localMasks
            ?? asset.userState.adjustments.localMasks
        guard let mask = masks.first(where: { $0.id == maskID }),
              mask.rangeOperations.count < 16 else {
            return
        }
        let count = mask.rangeOperations.filter { $0.kind == .luminance }.count + 1
        let operation = MaskRangeOperation(
            name: "Luminance Range \(count)",
            kind: .luminance,
            combination: combination
        )
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            mask.rangeOperations.append(operation)
        }
        selectedMaskID = maskID
        viewer.selectLocalMask(maskID)
        viewer.selectMaskRangeOperation(operation.id)
    }

    private func addDepthRange(
        to maskID: LocalAdjustmentMask.ID,
        combination: MaskCombinationMode,
        for asset: PhotoAsset
    ) {
        guard !isGeneratingDepthRange else { return }
        let masks = library.selectedAsset?.userState.adjustments.localMasks
            ?? asset.userState.adjustments.localMasks
        guard let mask = masks.first(where: { $0.id == maskID }),
              mask.rangeOperations.count < 16 else {
            return
        }

        let assetID = asset.id
        let rotationDegrees = asset.userState.adjustments.rotationDegrees
        let flipHorizontal = asset.userState.adjustments.flipHorizontal
        let flipVertical = asset.userState.adjustments.flipVertical
        isGeneratingDepthRange = true
        depthRangeMessage = nil
        depthRangeTargetMaskID = maskID

        Task { @MainActor in
            let result: Result<Data, Error> = await Task.detached(
                priority: .userInitiated
            ) {
                Result {
                    try AuxiliaryMaskGenerator.generateDepthMapPNG(
                        from: asset.url,
                        rotationDegrees: rotationDegrees,
                        flipHorizontal: flipHorizontal,
                        flipVertical: flipVertical
                    )
                }
            }.value

            isGeneratingDepthRange = false
            guard let currentAsset = library.assets.first(
                where: { $0.id == assetID }
            ) else {
                depthRangeMessage = "The photo is no longer in the open library."
                return
            }

            switch result {
            case let .success(depthMapData):
                var updated = currentAsset.userState.adjustments
                guard let maskIndex = updated.localMasks.firstIndex(
                    where: { $0.id == maskID }
                ), updated.localMasks[maskIndex].rangeOperations.count < 16 else {
                    depthRangeMessage = "The target mask is no longer available."
                    return
                }
                let count = updated.localMasks[maskIndex].rangeOperations
                    .filter { $0.kind == .depth }
                    .count + 1
                let operation = MaskRangeOperation(
                    name: "Depth Range \(count)",
                    kind: .depth,
                    combination: combination,
                    rasterMaskData: depthMapData
                )
                updated.localMasks[maskIndex].rangeOperations.append(operation)
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: assetID,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: assetID)
                selectedMaskID = maskID
                viewer.selectLocalMask(maskID)
                viewer.selectMaskRangeOperation(operation.id)
                depthRangeMessage = "Embedded camera depth loaded locally."

            case let .failure(error):
                depthRangeMessage = error.localizedDescription
            }
        }
    }

    private func deleteMaskRangeOperation(
        _ operationID: MaskRangeOperation.ID,
        from maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        var nextID: MaskRangeOperation.ID?
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard let index = mask.rangeOperations.firstIndex(
                where: { $0.id == operationID }
            ) else {
                return
            }
            mask.rangeOperations.remove(at: index)
            nextID = mask.rangeOperations.indices.contains(index)
                ? mask.rangeOperations[index].id
                : mask.rangeOperations.last?.id
        }
        if viewer.maskColorRangeOperationTargetID == operationID {
            viewer.setMaskColorRangePicking(false)
        }
        viewer.selectMaskRangeOperation(nextID)
    }

    private func moveMaskRangeOperation(
        _ operationID: MaskRangeOperation.ID,
        in maskID: LocalAdjustmentMask.ID,
        offset: Int,
        for asset: PhotoAsset
    ) {
        guard offset != 0 else { return }
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard let sourceIndex = mask.rangeOperations.firstIndex(
                where: { $0.id == operationID }
            ) else {
                return
            }
            let destinationIndex = min(
                mask.rangeOperations.count - 1,
                max(0, sourceIndex + offset)
            )
            guard destinationIndex != sourceIndex else { return }
            let operation = mask.rangeOperations.remove(at: sourceIndex)
            mask.rangeOperations.insert(operation, at: destinationIndex)
        }
        viewer.selectMaskRangeOperation(operationID)
    }

    private func maskRangeEnabledBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskRangeOperation.ID,
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                maskRangeOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                )?.isEnabled ?? false
            },
            set: { enabled in
                updateMaskRangeOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                ) { operation in
                    operation.isEnabled = enabled
                }
            }
        )
    }

    private func maskRangeInversionBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskRangeOperation.ID,
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                maskRangeOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                )?.inverted ?? false
            },
            set: { inverted in
                updateMaskRangeOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                ) { operation in
                    operation.inverted = inverted
                }
            }
        )
    }

    private func maskRangeCombinationBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskRangeOperation.ID,
        for asset: PhotoAsset
    ) -> Binding<MaskCombinationMode> {
        Binding(
            get: {
                maskRangeOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                )?.combination ?? .intersect
            },
            set: { combination in
                updateMaskRangeOperation(
                    maskID: maskID,
                    operationID: operationID,
                    for: asset
                ) { operation in
                    operation.combination = combination
                }
            }
        )
    }

    private func maskRangeValueBinding(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskRangeOperation.ID,
        keyPath: WritableKeyPath<MaskRangeOperation, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.localMasks
                    .first {
                        $0.id == maskID
                    }?
                    .rangeOperations
                    .first {
                        $0.id == operationID
                    }?[keyPath: keyPath]
            },
            set: { adjustments, value in
                guard let maskIndex =
                    adjustments.localMasks.firstIndex(
                        where: {
                            $0.id == maskID
                        }
                    ),
                      let operationIndex =
                        adjustments.localMasks[
                            maskIndex
                        ].rangeOperations.firstIndex(
                            where: {
                                $0.id == operationID
                            }
                        ) else {
                    return
                }
                adjustments.localMasks[maskIndex]
                    .rangeOperations[operationIndex][
                        keyPath: keyPath
                    ] = value
            }
        )
    }

    private func maskRangeOperation(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskRangeOperation.ID,
        for asset: PhotoAsset
    ) -> MaskRangeOperation? {
        let masks = library.selectedAsset?.userState.adjustments.localMasks
            ?? asset.userState.adjustments.localMasks
        return masks.first(where: { $0.id == maskID })?
            .rangeOperations.first(where: { $0.id == operationID })
    }

    private func updateMaskRangeOperation(
        maskID: LocalAdjustmentMask.ID,
        operationID: MaskRangeOperation.ID,
        for asset: PhotoAsset,
        mutation: (inout MaskRangeOperation) -> Void
    ) {
        updateMask(maskID, for: asset) { mask in
            guard let index = mask.rangeOperations.firstIndex(
                where: { $0.id == operationID }
            ) else {
                return
            }
            mutation(&mask.rangeOperations[index])
        }
    }

    private func maskRangeColor(_ sample: PointColorSample) -> Color {
        let saturation = sample.saturation / 100
        let luminance = sample.luminance / 100
        let brightness = luminance + saturation * min(luminance, 1 - luminance)
        let hsvSaturation = brightness <= 0.000_1
            ? 0
            : 2 * (1 - luminance / brightness)
        return Color(
            hue: sample.hue / 360,
            saturation: min(1, max(0, hsvSaturation)),
            brightness: min(1, max(0, brightness))
        )
    }

    private func addMask(_ kind: LocalMaskKind, for asset: PhotoAsset) {
        if kind == .subject {
            viewer.setObjectMaskPicking(false)
            addSubjectMask(for: asset)
            return
        }
        if kind == .object {
            guard viewer.baseImage != nil else {
                viewer.setObjectMaskGeneration(
                    false,
                    message: "Wait for the photo to finish loading, then try again."
                )
                return
            }
            viewer.setObjectMaskGeneration(false)
            viewer.setObjectMaskPicking(true)
            return
        }
        if kind == .sky {
            viewer.setObjectMaskPicking(false)
            addSkyMask(for: asset)
            return
        }

        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard updated.localMasks.count < 32 else { return }

        let count = updated.localMasks.filter { $0.kind == kind }.count + 1
        let shortName: String
        switch kind {
        case .subject: shortName = "Subject"
        case .object: shortName = "Object"
        case .sky: shortName = "Sky"
        case .brush: shortName = "Brush"
        case .radial: shortName = "Radial"
        case .linear: shortName = "Linear"
        }
        let mask = LocalAdjustmentMask(
            name: "\(shortName) \(count)",
            kind: kind,
            size: kind == .brush ? 0.04 : 0.55,
            feather: kind == .brush ? 0.65 : 0.5
        )
        updated.localMasks.append(mask)
        updated = updated.normalized
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
        selectedMaskID = mask.id
        viewer.selectLocalMask(mask.id)
        if kind == .brush {
            viewer.setBrushEditing(true, selectedMaskID: mask.id)
        }
    }

    private func addSubjectMask(for asset: PhotoAsset) {
        guard !isGeneratingSubjectMask else { return }
        guard let image = viewer.baseImage else {
            subjectMaskMessage = "Wait for the photo to finish loading, then try again."
            return
        }

        let assetID = asset.id
        let sourceAdjustments = asset.userState.adjustments
        let orientationAdjustments = PhotoAdjustments(
            rotationDegrees: sourceAdjustments.rotationDegrees,
            flipHorizontal: sourceAdjustments.flipHorizontal,
            flipVertical: sourceAdjustments.flipVertical
        )
        isGeneratingSubjectMask = true
        subjectMaskMessage = nil

        Task { @MainActor in
            let result: Result<Data, Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    let orientedImage = try PhotoProcessor.apply(
                        to: image,
                        adjustments: orientationAdjustments
                    )
                    return try SubjectMaskGenerator.generateMaskPNG(
                        from: orientedImage
                    )
                }
            }.value

            isGeneratingSubjectMask = false
            switch result {
            case let .success(maskData):
                guard let currentAsset = library.assets.first(where: { $0.id == assetID }) else {
                    subjectMaskMessage = "The photo is no longer in the open library."
                    return
                }
                var updated = currentAsset.userState.adjustments
                guard updated.localMasks.count < 32 else {
                    subjectMaskMessage = "This photo already has the maximum number of masks."
                    return
                }
                let count = updated.localMasks.filter { $0.kind == .subject }.count + 1
                let mask = LocalAdjustmentMask(
                    name: "Subject \(count)",
                    kind: .subject,
                    rasterMaskData: maskData
                )
                updated.localMasks.append(mask)
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: assetID,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: assetID)
                selectedMaskID = mask.id
                viewer.selectLocalMask(mask.id)
                subjectMaskMessage = "Subject selected on this Mac."

            case let .failure(error):
                subjectMaskMessage = error.localizedDescription
            }
        }
    }

    private func addSkyMask(for asset: PhotoAsset) {
        guard !isGeneratingSkyMask else { return }
        guard let image = viewer.baseImage else {
            skyMaskMessage = "Wait for the photo to finish loading, then try again."
            return
        }

        let assetID = asset.id
        let sourceAdjustments = asset.userState.adjustments
        let orientationAdjustments = PhotoAdjustments(
            rotationDegrees: sourceAdjustments.rotationDegrees,
            flipHorizontal: sourceAdjustments.flipHorizontal,
            flipVertical: sourceAdjustments.flipVertical
        )
        isGeneratingSkyMask = true
        skyMaskMessage = nil

        Task { @MainActor in
            let result: Result<AuxiliaryMaskGenerator.SkyResult, Error> =
                await Task.detached(priority: .userInitiated) {
                    Result {
                        let orientedImage = try PhotoProcessor.apply(
                            to: image,
                            adjustments: orientationAdjustments
                        )
                        return try AuxiliaryMaskGenerator.generateSkyMaskPNG(
                            from: orientedImage,
                            assetURL: asset.url,
                            rotationDegrees: sourceAdjustments.rotationDegrees,
                            flipHorizontal: sourceAdjustments.flipHorizontal,
                            flipVertical: sourceAdjustments.flipVertical
                        )
                    }
                }.value

            isGeneratingSkyMask = false
            switch result {
            case let .success(skyResult):
                guard let currentAsset = library.assets.first(
                    where: { $0.id == assetID }
                ) else {
                    skyMaskMessage = "The photo is no longer in the open library."
                    return
                }
                var updated = currentAsset.userState.adjustments
                guard updated.localMasks.count < 32 else {
                    skyMaskMessage = "This photo already has the maximum number of masks."
                    return
                }
                let count = updated.localMasks.filter { $0.kind == .sky }.count + 1
                let mask = LocalAdjustmentMask(
                    name: "Sky \(count)",
                    kind: .sky,
                    rasterMaskData: skyResult.pngData
                )
                updated.localMasks.append(mask)
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: assetID,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: assetID)
                selectedMaskID = mask.id
                viewer.selectLocalMask(mask.id)
                skyMaskMessage = skyResult.source == .embeddedMatte
                    ? "Camera-provided sky matte loaded locally."
                    : "Sky estimated locally from this photo."

            case let .failure(error):
                skyMaskMessage = error.localizedDescription
            }
        }
    }

    private func deleteMask(_ maskID: LocalAdjustmentMask.ID, from asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.localMasks.firstIndex(where: { $0.id == maskID }) else {
            return
        }
        updated.localMasks.remove(at: index)
        let nextID = updated.localMasks.indices.contains(index)
            ? updated.localMasks[index].id
            : updated.localMasks.last?.id
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
        selectedMaskID = nextID
        selectedMaskPrimaryOperationID = nextID.flatMap { id in
            updated.localMasks.first(where: { $0.id == id })?
                .primaryOperations.first?.id
        }
        selectedMaskPointColorID = nextID.flatMap { id in
            updated.localMasks.first(where: { $0.id == id })?
                .pointColors.first?.id
        }
        if viewer.visualizedLocalMaskID == maskID {
            viewer.setLocalMaskVisualization(nil)
        }
        if viewer.maskColorRangeTargetID == maskID {
            viewer.setMaskColorRangePicking(false)
        }
        viewer.selectMaskRangeOperation(nil)
        if viewer.selectedLocalMaskID == maskID {
            if let nextBrushID = updated.localMasks.first(where: { $0.kind == .brush })?.id {
                viewer.selectLocalMask(nextBrushID)
            } else {
                viewer.setBrushEditing(false)
            }
        }
    }

    private func resetMask(_ maskID: LocalAdjustmentMask.ID, for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.localMasks.firstIndex(where: { $0.id == maskID }) else {
            return
        }
        updated.localMasks[index].adjustments = .neutral
        updated.localMasks[index].pointColors = updated.localMasks[index]
            .pointColors.map {
                PointColorAdjustment(id: $0.id, sample: $0.sample)
            }
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func undoLastBrushStroke(
        _ maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            guard !mask.strokes.isEmpty else { return }
            mask.strokes.removeLast()
        }
    }

    private func clearBrushStrokes(
        _ maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) {
        updateMask(maskID, for: asset, coalescingHistory: false) { mask in
            mask.strokes.removeAll()
        }
    }

    private func maskInversionBinding(
        maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset
    ) -> Binding<Bool> {
        Binding(
            get: {
                let masks = library.selectedAsset?.userState.adjustments.localMasks
                    ?? asset.userState.adjustments.localMasks
                return masks.first(where: { $0.id == maskID })?.inverted ?? false
            },
            set: { inverted in
                updateMask(maskID, for: asset) { mask in
                    mask.inverted = inverted
                }
            }
        )
    }

    private func maskGeometryBinding(
        maskID: LocalAdjustmentMask.ID,
        keyPath: WritableKeyPath<LocalAdjustmentMask, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.localMasks
                    .first {
                        $0.id == maskID
                    }?[keyPath: keyPath]
            },
            set: { adjustments, value in
                guard let index =
                    adjustments.localMasks.firstIndex(
                        where: {
                            $0.id == maskID
                        }
                    ) else {
                    return
                }
                adjustments.localMasks[index][
                    keyPath: keyPath
                ] = value
            }
        )
    }

    private func localAdjustmentBinding(
        maskID: LocalAdjustmentMask.ID,
        keyPath: WritableKeyPath<LocalToneAdjustments, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.localMasks
                    .first {
                        $0.id == maskID
                    }?
                    .adjustments[keyPath: keyPath]
            },
            set: { adjustments, value in
                guard let index =
                    adjustments.localMasks.firstIndex(
                        where: {
                            $0.id == maskID
                        }
                    ) else {
                    return
                }
                adjustments.localMasks[index]
                    .adjustments[keyPath: keyPath] =
                        value
            }
        )
    }

    private func updateMask(
        _ maskID: LocalAdjustmentMask.ID,
        for asset: PhotoAsset,
        coalescingHistory: Bool = true,
        mutation: (inout LocalAdjustmentMask) -> Void
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.localMasks.firstIndex(where: { $0.id == maskID }) else {
            return
        }
        mutation(&updated.localMasks[index])
        updated = updated.normalized
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: coalescingHistory
        )
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func addSpotRemoval(_ kind: SpotRemovalKind, for asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard updated.spotRemovals.count < 128 else { return }

        let count = updated.spotRemovals.filter { $0.kind == kind }.count + 1
        let stagger = Double(updated.spotRemovals.count % 5) * 0.025
        let spot = SpotRemoval(
            name: "\(kind.name) \(count)",
            kind: kind,
            targetX: 0.5 + stagger,
            targetY: 0.5 + stagger,
            sourceX: 0.36 + stagger,
            sourceY: 0.42 + stagger
        )
        updated.spotRemovals.append(spot)
        updated = updated.normalized
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
        viewer.setRemovalEditing(true, selectedSpotID: spot.id)
    }

    private func deleteSpotRemoval(_ spotID: SpotRemoval.ID, from asset: PhotoAsset) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.spotRemovals.firstIndex(where: { $0.id == spotID }) else {
            return
        }
        updated.spotRemovals.remove(at: index)
        let nextID = updated.spotRemovals.indices.contains(index)
            ? updated.spotRemovals[index].id
            : updated.spotRemovals.last?.id
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
        if let nextID {
            viewer.selectSpotRemoval(nextID)
        } else {
            viewer.setRemovalEditing(false)
        }
    }

    private func spotKindBinding(
        spotID: SpotRemoval.ID,
        for asset: PhotoAsset
    ) -> Binding<SpotRemovalKind> {
        Binding(
            get: {
                let spots = library.selectedAsset?.userState.adjustments.spotRemovals
                    ?? asset.userState.adjustments.spotRemovals
                return spots.first(where: { $0.id == spotID })?.kind ?? .heal
            },
            set: { kind in
                updateSpotRemoval(spotID, for: asset) { spot in
                    spot.kind = kind
                }
            }
        )
    }

    private func spotGeometryBinding(
        spotID: SpotRemoval.ID,
        keyPath: WritableKeyPath<SpotRemoval, Double>,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                adjustments.spotRemovals
                    .first {
                        $0.id == spotID
                    }?[keyPath: keyPath]
            },
            set: { adjustments, value in
                guard let index =
                    adjustments.spotRemovals.firstIndex(
                        where: {
                            $0.id == spotID
                        }
                    ) else {
                    return
                }
                adjustments.spotRemovals[index][
                    keyPath: keyPath
                ] = value
            }
        )
    }

    private func updateSpotRemoval(
        _ spotID: SpotRemoval.ID,
        for asset: PhotoAsset,
        mutation: (inout SpotRemoval) -> Void
    ) {
        var updated = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        guard let index = updated.spotRemovals.firstIndex(where: { $0.id == spotID }) else {
            return
        }
        mutation(&updated.spotRemovals[index])
        updated = updated.normalized
        library.setAdjustments(updated, for: asset.id)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func applyOrientationChange(
        _ adjustments: PhotoAdjustments?,
        to assetID: PhotoAsset.ID
    ) {
        guard let adjustments else { return }
        viewer.updateAdjustments(adjustments, for: assetID)
    }

    private func syncViewer(for assetID: PhotoAsset.ID) {
        guard let adjustments = library.selectedAsset?.userState.adjustments else { return }
        viewer.updateAdjustments(adjustments, for: assetID)
    }

    private func applyCropPreset(_ preset: CropAspectPreset, to asset: PhotoAsset) {
        var size = viewer.baseImage?.size ?? viewer.image?.size ?? .zero
        let adjustments = library.selectedAsset?.userState.adjustments
            ?? asset.userState.adjustments
        if adjustments.rotationDegrees == 90 || adjustments.rotationDegrees == 270 {
            size = CGSize(width: size.height, height: size.width)
        }
        guard size.width > 0, size.height > 0 else { return }
        var updated = adjustments
        updated.crop = preset.crop(
            forSourceAspect: Double(size.width / size.height)
        )
        library.setAdjustments(updated, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(updated, for: asset.id)
    }

    private func cropPositionBinding(
        horizontal: Bool,
        for asset: PhotoAsset
    ) -> MixedAdjustmentValue {
        mixedDoubleBinding(
            for: asset,
            value: { adjustments in
                horizontal
                    ? adjustments.crop
                        .horizontalPosition
                    : adjustments.crop
                        .verticalPosition
            },
            set: { adjustments, newValue in
                adjustments.crop =
                    horizontal
                    ? adjustments.crop.positioned(
                        horizontal: newValue
                    )
                    : adjustments.crop.positioned(
                        vertical: newValue
                    )
            }
        )
    }

    private func adjustmentGroup<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        sectionEnabled: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let group = adjustmentGroup(for: title)
        return RAWInspectorSection(
            title: title,
            isExpanded: isExpanded,
            isResetDisabled:
                group.map(sectionIsNeutral) ?? true,
            onReset:
                group.map { group in
                    {
                        resetAdjustmentGroup(group)
                    }
                },
            onSolo: {
                collapseAllAdjustmentSections()
                isExpanded.wrappedValue = true
            },
            onActivate:
                interactiveTool(for: title).map {
                    tool in
                    {
                        onActivateTool(tool)
                    }
                },
            sectionEnabled: sectionEnabled
        ) {
            VStack(
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.small
            ) {
                content()
            }
        }
    }

    private func adjustmentGroup(
        for title: String
    ) -> PhotoAdjustmentGroup? {
        switch title {
        case "Light": return .light
        case "Color": return .color
        case "Tone Curve": return .toneCurve
        case "Color Mixer": return .colorMixer
        case "Point Color": return .pointColor
        case "Color Grading": return .colorGrading
        case "Calibration": return .calibration
        case "Masks": return .masks
        case "Remove": return .healing
        case "Optics": return .optics
        case "Crop & Geometry": return .geometry
        case "Effects": return .effects
        case "Detail": return .detail
        default: return nil
        }
    }

    private func interactiveTool(
        for title: String
    ) -> DevelopCanvasTool? {
        switch title {
        case "Masks": return .mask
        case "Remove": return .remove
        case "Crop & Geometry":
            return .crop
        case "Point Color":
            return .pointColor
        default:
            return nil
        }
    }

    private func sectionIsNeutral(
        _ group: PhotoAdjustmentGroup
    ) -> Bool {
        guard let current =
            library.selectedAsset?.userState
                .adjustments else {
            return true
        }
        return PhotoAdjustmentSyncPlanner.merging(
            source: .neutral,
            into: current,
            groups: [group]
        ) == current
    }

    private func resetAdjustmentGroup(
        _ group: PhotoAdjustmentGroup
    ) {
        guard let asset = library.selectedAsset else {
            return
        }
        let updated =
            PhotoAdjustmentSyncPlanner.merging(
                source: .neutral,
                into: asset.userState.adjustments,
                groups: [group]
            )
        library.setAdjustments(
            updated,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(
            updated,
            for: asset.id
        )
        if group == .masks
            || group == .healing
            || group == .geometry {
            viewer.finishInteractiveTools()
        }
    }

    private func collapseAllAdjustmentSections() {
        lightExpanded = false
        colorExpanded = false
        toneCurveExpanded = false
        colorMixerExpanded = false
        pointColorExpanded = false
        colorGradingExpanded = false
        calibrationExpanded = false
        masksExpanded = false
        removalExpanded = false
        opticsExpanded = false
        geometryExpanded = false
        effectsExpanded = false
        detailExpanded = false
        versionsExpanded = false
    }
}

private struct ToneCurveEditor: View {
    @Binding var curve: ToneCurve
    let isMixed: Bool
    @State private var selectedRegion: ToneCurveRegion = .midtones
    @FocusState private var valueFieldFocused: Bool

    var body: some View {
        let sliderPresentation =
            RAWSliderPresentation(
                value: curve[selectedRegion],
                isMixed: isMixed,
                format: curveOutputFormat
            )
        let fieldPresentation =
            RAWSliderPresentation(
                value: curve[selectedRegion],
                isMixed: isMixed,
                isFieldFocused:
                    valueFieldFocused,
                format: curveOutputFormat
            )
        VStack(spacing: RAWDeskTokens.Spacing.small) {
            GeometryReader { proxy in
                Canvas { context, size in
                    let gridColor =
                        RAWDeskTokens.ColorToken.divider
                    for index in 1..<4 {
                        let fraction = CGFloat(index) / 4
                        var vertical = Path()
                        vertical.move(to: CGPoint(x: size.width * fraction, y: 0))
                        vertical.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                        context.stroke(vertical, with: .color(gridColor), lineWidth: 0.5)

                        var horizontal = Path()
                        horizontal.move(to: CGPoint(x: 0, y: size.height * fraction))
                        horizontal.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                        context.stroke(horizontal, with: .color(gridColor), lineWidth: 0.5)
                    }

                    var line = Path()
                    for (index, region) in ToneCurveRegion.allCases.enumerated() {
                        let point = point(for: region, in: size)
                        if index == 0 {
                            line.move(to: point)
                        } else {
                            line.addLine(to: point)
                        }
                    }
                    context.stroke(line, with: .color(.white), lineWidth: 2)

                    for region in ToneCurveRegion.allCases {
                        let point = point(for: region, in: size)
                        let radius: CGFloat = selectedRegion == region ? 5 : 3.5
                        let marker = Path(
                            ellipseIn: CGRect(
                                x: point.x - radius,
                                y: point.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                        )
                        context.fill(
                            marker,
                            with: .color(selectedRegion == region ? RAWDeskTokens.ColorToken.selection : .white)
                        )
                    }
                }
                .background(
                    LinearGradient(
                        colors: [.black, Color(white: 0.22)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                        .strokeBorder(RAWDeskTokens.ColorToken.textSecondary.opacity(0.4), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateCurve(at: value.location, size: proxy.size)
                        }
                )
                .accessibilityLabel(Text("Tone curve graph"))
                .accessibilityValue(
                    Text(
                        isMixed
                            ? "Mixed values"
                            : "\(selectedRegion.name), \(Int((curve[selectedRegion] * 100).rounded())) percent"
                    )
                )
            }
            .frame(height: 150)

            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                ForEach(ToneCurveRegion.allCases) { region in
                    Button {
                        selectedRegion = region
                    } label: {
                        Text(shortLabel(for: region))
                            .font(RAWDeskTokens.Typography.numeric)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                            .background(
                                selectedRegion == region
                                    ? RAWDeskTokens.ColorToken.selection.opacity(0.2)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(region.name))
                }
            }

            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                HStack {
                    Text(selectedRegion.name)
                        .font(RAWDeskTokens.Typography.metadata)
                    Spacer()
                    TextField(
                        "",
                        value: Binding(
                            get: { curve[selectedRegion] },
                            set: {
                                curve[selectedRegion] =
                                    min(1, max(0, $0))
                            }
                        ),
                        format: .percent.precision(
                            .fractionLength(0)
                        )
                    )
                    .rawNumericField(width: 58)
                    .focused($valueFieldFocused)
                    .opacity(
                        fieldPresentation
                            .showsMixedMarker
                            ? 0
                            : 1
                    )
                    .overlay {
                        if fieldPresentation
                            .showsMixedMarker {
                            Text("—")
                                .font(
                                    RAWDeskTokens.Typography
                                        .numeric
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .trailing
                                )
                                .padding(.trailing, RAWDeskTokens.Spacing.small)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(
                        Text(
                            "\(selectedRegion.name) curve output"
                        )
                    )
                    .accessibilityValue(
                        Text(
                            fieldPresentation
                                .accessibilityValue
                        )
                    )
                }

                Slider(
                    value: Binding(
                        get: { curve[selectedRegion] },
                        set: { curve[selectedRegion] = $0 }
                    ),
                    in: 0...1,
                    step: 0.01
                )
                .rawKeyboardAdjustableSlider(
                    value: Binding(
                        get: { curve[selectedRegion] },
                        set: { curve[selectedRegion] = $0 }
                    ),
                    in: 0...1,
                    step: 0.01
                )
                .rawSliderTarget()
                .controlSize(.small)
                .tint(
                    sliderPresentation
                        .usesNeutralTint
                        ? RAWDeskTokens.ColorToken
                            .textSecondary
                        : RAWDeskTokens.ColorToken.selection
                )
                .accessibilityLabel(Text("\(selectedRegion.name) curve output"))
                .accessibilityValue(
                    Text(
                        sliderPresentation
                            .accessibilityValue
                    )
                )
            }

            Button {
                curve = .neutral
            } label: {
                Label("Reset Tone Curve", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.link)
            .font(RAWDeskTokens.Typography.metadata)
            .disabled(curve.isNeutral && !isMixed)
        }
    }

    private func point(for region: ToneCurveRegion, in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(region.inputLevel) * size.width,
            y: (1 - CGFloat(curve[region])) * size.height
        )
    }

    private func updateCurve(at location: CGPoint, size: CGSize) {
        // The five curve inputs stay fixed. Horizontal position selects the
        // nearest point; vertical movement sets its output.
        let nearestIndex = Int(
            (min(1, max(0, location.x / max(1, size.width))) * 4).rounded()
        )
        guard let region = ToneCurveRegion(rawValue: nearestIndex) else { return }
        selectedRegion = region

        curve[region] = Double(
            1 - min(1, max(0, location.y / max(1, size.height)))
        )
    }

    private func shortLabel(for region: ToneCurveRegion) -> String {
        switch region {
        case .black: return "B"
        case .shadows: return "S"
        case .midtones: return "M"
        case .highlights: return "H"
        case .white: return "W"
        }
    }

    private func curveOutputFormat(
        _ value: Double
    ) -> String {
        "\(Int((value * 100).rounded())) percent"
    }
}

private struct CropPositionSlider: View {
    let title: String
    let value: MixedAdjustmentValue
    let isEnabled: Bool

    var body: some View {
        RAWSliderRow(
            title: title,
            value: value.binding,
            range: 0...1,
            step: 0.01,
            resetValue: 0.5,
            isMixed: value.isMixed,
            format: {
                "\(Int(($0 * 100).rounded()))%"
            }
        )
        .disabled(!isEnabled)
        .accessibilityLabel(
            "\(title) crop position"
        )
    }
}

private struct MixedAdjustmentValue {
    let binding: Binding<Double>
    let isMixed: Bool
}

private struct AdjustmentSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let resetValue: Double
    let isMixed: Bool
    let format: (Double) -> String

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = -100...100,
        step: Double = 1,
        resetValue: Double = 0,
        isMixed: Bool = false,
        format: @escaping (Double) -> String = {
            String(format: "%+.0f", $0)
        }
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.resetValue = resetValue
        self.isMixed = isMixed
        self.format = format
    }

    init(
        title: String,
        value: MixedAdjustmentValue,
        range: ClosedRange<Double> = -100...100,
        step: Double = 1,
        resetValue: Double = 0,
        format: @escaping (Double) -> String = {
            String(format: "%+.0f", $0)
        }
    ) {
        self.init(
            title: title,
            value: value.binding,
            range: range,
            step: step,
            resetValue: resetValue,
            isMixed: value.isMixed,
            format: format
        )
    }

    var body: some View {
        RAWSliderRow(
            title: title,
            value: value,
            range: range,
            step: step,
            resetValue: resetValue,
            isMixed: isMixed,
            format: format
        )
    }
}

private struct MaskValueSlider: View {
    let title: String
    let value: MixedAdjustmentValue
    let range: ClosedRange<Double>
    let step: Double
    let resetValue: Double
    let format: (Double) -> String

    var body: some View {
        RAWSliderRow(
            title: title,
            value: value.binding,
            range: range,
            step: step,
            resetValue: resetValue,
            isMixed: value.isMixed,
            format: format
        )
        .accessibilityLabel(
            "\(title) mask geometry"
        )
    }
}
