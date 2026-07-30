import SwiftUI

struct PhotoInspectorView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var viewer: PhotoViewerViewModel
    let asset: PhotoAsset?

    @State private var mode: InspectorMode = .edit

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $mode) {
                ForEach(InspectorMode.allCases) { item in
                    Label(item.title, systemImage: item.icon).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, RAWDeskTokens.Spacing.medium)
            .padding(.vertical, RAWDeskTokens.Spacing.small)
            .disabled(asset == nil)

            if library.selectedIDs.count > 1 {
                Text("\(library.selectedIDs.count) photos selected")
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .padding(.bottom, RAWDeskTokens.Spacing.small)
            }

            Divider()

            switch mode {
            case .edit:
                EditingInspectorView(library: library, viewer: viewer, asset: asset)
            case .info:
                MetadataInspectorView(library: library, asset: asset)
            }
        }
    }
}

private enum InspectorMode: String, CaseIterable, Identifiable {
    case edit
    case info

    var id: String { rawValue }
    var title: String { self == .edit ? "Edit" : "Info" }
    var icon: String { self == .edit ? "slider.horizontal.3" : "info.circle" }
}

struct AssistedCullingInspectorView: View {
    @ObservedObject var library: LibraryViewModel
    let asset: PhotoAsset?

    private var analysis: AssistedCullingAnalysis? {
        asset.flatMap { library.cullingAnalysis(for: $0.id) }
    }

    private var evaluation: AssistedCullingEvaluation? {
        asset.flatMap { library.cullingEvaluation(for: $0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                Text("Culling Details")
                    .font(RAWDeskTokens.Typography.workspaceHeader)
                Spacer()
                if library.selectedIDs.count > 1 {
                    Text("\(library.selectedIDs.count) selected")
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
            }
            .padding(.horizontal, RAWDeskTokens.Spacing.medium)
            .padding(.vertical, RAWDeskTokens.Spacing.medium)

            Divider()

            if let asset, let analysis, let evaluation {
                ScrollView {
                    VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
                        selectedPhotoHeader(
                            asset: asset,
                            analysis: analysis,
                            evaluation: evaluation
                        )

                        evidenceSection("Focus") {
                            VStack(spacing: RAWDeskTokens.Spacing.small) {
                                metricRow(
                                    "Subject",
                                    value: analysis.subjectSharpness,
                                    tint: RAWDeskTokens.ColorToken.selection,
                                    detail: analysis.subjectDetected
                                        ? "Detected"
                                        : "No subject"
                                )
                                metricRow(
                                    "Whole frame",
                                    value: analysis.globalSharpness,
                                    tint: RAWDeskTokens.ColorToken.selection
                                )
                                if let eyeSharpness =
                                    analysis.eyeSharpness {
                                    metricRow(
                                        "Eyes",
                                        value: eyeSharpness,
                                        tint: RAWDeskTokens.ColorToken.selection,
                                        detail:
                                            "\(analysis.detectedEyeCount) detected"
                                    )
                                }
                            }
                        }

                        evidenceSection("Exposure") {
                            VStack(spacing: RAWDeskTokens.Spacing.small) {
                                metricRow(
                                    "Issue score",
                                    value: analysis.exposureIssueScore,
                                    tint: issueTint(
                                        analysis.exposureIssueScore
                                    )
                                )
                                metricRow(
                                    "Mean luminance",
                                    value: analysis.meanLuminance,
                                    tint: RAWDeskTokens.ColorToken.selection
                                )
                                metricRow(
                                    "Shadow clipping",
                                    value: analysis.shadowClipping,
                                    tint: issueTint(
                                        analysis.shadowClipping
                                    )
                                )
                                metricRow(
                                    "Highlight clipping",
                                    value: analysis.highlightClipping,
                                    tint: issueTint(
                                        analysis.highlightClipping
                                    )
                                )
                            }
                        }

                        evidenceSection("Other signals") {
                            VStack(spacing: RAWDeskTokens.Spacing.small) {
                                metricRow(
                                    "Likely misfire",
                                    value: analysis.misfireScore,
                                    tint: issueTint(
                                        analysis.misfireScore
                                    )
                                )
                                metricRow(
                                    "Document",
                                    value: analysis.documentScore,
                                    tint: issueTint(
                                        analysis.documentScore
                                    ),
                                    detail:
                                        "\(analysis.textObservationCount) text regions"
                                )
                                if let stack =
                                    library.cullingStackNumber(
                                        for: asset.id
                                    ) {
                                    LabeledContent(
                                        "Visual group",
                                        value: "Suggested Stack \(stack)"
                                    )
                                    .font(RAWDeskTokens.Typography.metadata)
                                }
                            }
                        }

                        if !analysis.faces.isEmpty {
                            evidenceSection(
                                "Faces (\(analysis.faces.count))"
                            ) {
                                VStack(spacing: RAWDeskTokens.Spacing.small) {
                                    ForEach(analysis.faces) { face in
                                        faceRow(face)
                                        if face.id
                                            != analysis.faces.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }

                        Text(
                            "Analyzed locally \(analysis.analyzedAt.formatted(date: .abbreviated, time: .shortened)). No photo is uploaded or changed."
                        )
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }
                    .padding(RAWDeskTokens.Spacing.medium)
                }
            } else {
                RAWEmptyState(
                    title: "No culling evidence",
                    systemImage: "photo.badge.magnifyingglass",
                    message:
                        library.cullingScanProgress == nil
                            ? "Select an analyzed photo to review its evidence."
                            : "Evidence will appear as the local analysis finishes."
                )
            }
        }
    }

    @ViewBuilder
    private func selectedPhotoHeader(
        asset: PhotoAsset,
        analysis: AssistedCullingAnalysis,
        evaluation: AssistedCullingEvaluation
    ) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Text(asset.filename)
                .font(RAWDeskTokens.Typography.sectionHeader)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Text(evaluation.decision.name.uppercased())
                    .font(RAWDeskTokens.Typography.badge)
                    .padding(.horizontal, RAWDeskTokens.Spacing.small)
                    .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                    .background(
                        decisionColor(evaluation.decision).opacity(0.9),
                        in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                    )
                    .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
                Text(evaluation.explanation)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Button("Select") {
                    library.setCullingManualDecision(
                        .select,
                        for: asset.id
                    )
                }
                .tint(RAWDeskTokens.ColorToken.selection)
                Button("Reject") {
                    library.setCullingManualDecision(
                        .reject,
                        for: asset.id
                    )
                }
                .tint(
                    RAWDeskTokens.ColorToken.destructive
                )
                Button("Calculated") {
                    library.setCullingManualDecision(
                        nil,
                        for: asset.id
                    )
                }
                .disabled(analysis.manualDecision == nil)
                .help("Remove the manual override")
            }
            .controlSize(.small)

            if analysis.manualDecision != nil {
                Label(
                    "Manual decision overrides the calculated result",
                    systemImage: "hand.raised.fill"
                )
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
    }

    private func evidenceSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Text(title)
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
            Divider()
            content()
        }
    }

    @ViewBuilder
    private func metricRow(
        _ title: String,
        value: Double,
        tint: Color,
        detail: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            HStack {
                Text(title)
                if let detail {
                    Text(detail)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
                Spacer()
                Text(percent(value))
                    .monospacedDigit()
            }
            .font(RAWDeskTokens.Typography.metadata)
            ProgressView(value: normalized(value))
                .progressViewStyle(.linear)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(percent(value))
        }
    }

    @ViewBuilder
    private func faceRow(
        _ face: AssistedCullingFaceAnalysis
    ) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            HStack {
                Text("Face \(face.id)")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                Spacer()
                Text(face.eyeState.name)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        face.eyeState == .closed
                            ? RAWDeskTokens.ColorToken
                                .warning
                            : RAWDeskTokens.ColorToken
                                .textSecondary
                    )
            }
            if let sharpness = face.eyeSharpness {
                metricRow(
                    "Eye focus",
                    value: sharpness,
                    tint: RAWDeskTokens.ColorToken.selection
                )
            }
            if let openness = face.eyeOpenness {
                metricRow(
                    "Eye openness",
                    value: openness,
                    tint: RAWDeskTokens.ColorToken.selection
                )
            }
            if face.eyeSharpness == nil, face.eyeOpenness == nil {
                Text("No reliable eye landmarks were available.")
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
    }

    private func normalized(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }

    private func percent(_ value: Double) -> String {
        "\(Int((normalized(value) * 100).rounded()))%"
    }

    private func issueTint(_ value: Double) -> Color {
        let normalizedValue = normalized(value)
        if normalizedValue >= 0.72 {
            return RAWDeskTokens.ColorToken.destructive
        }
        if normalizedValue >= 0.35 {
            return RAWDeskTokens.ColorToken.warning
        }
        return RAWDeskTokens.ColorToken.selection
    }

    private func decisionColor(
        _ decision: AssistedCullingDecision
    ) -> Color {
        switch decision {
        case .select:
            return RAWDeskTokens.ColorToken.success
        case .reject:
            return RAWDeskTokens.ColorToken.destructive
        case .review:
            return RAWDeskTokens.ColorToken.textSecondary
        }
    }
}
