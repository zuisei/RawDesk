import SwiftUI
import AppKit

struct ThumbnailGridView: View {
    @ObservedObject var library: LibraryViewModel
    @Binding private var scrollPositionID: PhotoAsset.ID?
    private let onOpenLoupe: (PhotoAsset.ID) -> Void
    @AppStorage("rawdesk.culling.criteriaExpanded")
    private var isCullingCriteriaExpanded = false

    private var cellSize: CGFloat { library.thumbnailPixelSize / 1.6 }

    init(
        library: LibraryViewModel,
        scrollPositionID: Binding<PhotoAsset.ID?> = .constant(nil),
        onOpenLoupe: @escaping (PhotoAsset.ID) -> Void = { _ in }
    ) {
        _library = ObservedObject(wrappedValue: library)
        _scrollPositionID = scrollPositionID
        self.onOpenLoupe = onOpenLoupe
    }

    var body: some View {
        let visible = library.filtered

        VStack(spacing: 0) {
            if library.catalogCollection == .assistedCulling {
                assistedCullingHeader
            }
            if library.catalogCollection == .exactDuplicates {
                exactDuplicateHeader
            }

            if visible.isEmpty {
                ErrorPlaceholderView(kind: .empty(emptyMessage))
            } else {
                GeometryReader { geo in
                    ScrollView {
                        let columns = max(
                            1,
                            Int(geo.size.width / (cellSize + 12))
                        )
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(
                                    .flexible(),
                                    spacing: RAWDeskTokens.Spacing.xSmall
                                ),
                                count: columns
                            ),
                            spacing: RAWDeskTokens.Spacing.xSmall
                        ) {
                            ForEach(visible) { asset in
                                thumbnailCell(for: asset)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(RAWDeskTokens.Spacing.small)
                    }
                    .scrollPosition(
                        id: $scrollPositionID,
                        anchor: .top
                    )
                }
                .overlay(alignment: .topTrailing) {
                    if library.selectedIDs.count > 1 {
                        Text("\(library.selectedIDs.count) selected")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .padding(.horizontal, RAWDeskTokens.Spacing.small)
                            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                            .background(
                                RAWDeskTokens.ColorToken
                                    .controlElevated,
                                in: Capsule()
                            )
                            .padding(RAWDeskTokens.Spacing.small)
                    }
                }
            }
        }
    }

    private func thumbnailCell(
        for asset: PhotoAsset
    ) -> some View {
        let stackMembership =
            library.catalogCollection == .exactDuplicates
                ? nil
                : library.photoStackMembership(for: asset.id)
        return ThumbnailCellView(
            asset: asset,
            isSelected: library.selectedIDs.contains(asset.id),
            isActive: library.selectionID == asset.id,
            compareRole: library.compareRole(for: asset.id),
            surveyRole: library.surveyRole(for: asset.id),
            pixelSize: library.thumbnailPixelSize,
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
            stackMembership: stackMembership,
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
            },
            onQuickPick: {
                library.setPickStatus(
                    .picked,
                    for: asset.id
                )
            },
            onQuickReject: {
                library.setPickStatus(
                    .rejected,
                    for: asset.id
                )
            },
            onQuickRating: { rating in
                library.setRating(
                    rating,
                    for: asset.id
                )
            }
        )
        .frame(height: cellSize + 22)
        .contentShape(Rectangle())
        // Two independent recognizers, not an ExclusiveGesture. In an exclusive
        // pair the single tap is only evaluated once the double tap *fails*,
        // and a two-count tap cannot fail until the system double-click
        // interval elapses — so selecting a photo took half a second or more,
        // while the filmstrip (a plain tap gesture) responded immediately.
        .onTapGesture(count: 2) {
            // Plain select: the single-tap handler may already have run for
            // this click, and re-applying a modifier-aware selection would
            // toggle the photo back out of the selection on a shift- or
            // command-double-click.
            library.select(asset.id)
            onOpenLoupe(asset.id)
        }
        .onTapGesture {
            selectThumbnail(asset.id)
        }
        .contextMenu {
            thumbnailContextMenu(for: asset)
        }
        .draggable("rawdesk-photo:\(asset.id)")
        .dropDestination(for: String.self) { values, _ in
            guard library.activePhotoCollection != nil,
                  let value = values.first,
                  value.hasPrefix("rawdesk-photo:") else {
                return false
            }
            let draggedID = String(
                value.dropFirst("rawdesk-photo:".count)
            )
            return library.movePhotoInActiveCollection(
                draggedID,
                before: asset.id
            )
        }
    }

    private func selectThumbnail(_ id: PhotoAsset.ID) {
        let modifiers = NSEvent.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        library.select(
            id,
            extending: modifiers.contains(.command),
            range: modifiers.contains(.shift)
        )
    }

    @ViewBuilder
    private func thumbnailContextMenu(
        for asset: PhotoAsset
    ) -> some View {
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(
                [asset.url]
            )
        }
        duplicateDigestContextButton(for: asset)
        quickCollectionContextButton(for: asset)
        photoCollectionContextMenu(for: asset)
        if library.catalogCollection == .assistedCulling,
           let analysis = library.cullingAnalysis(for: asset.id) {
            Divider()
            Button("Mark as Select") {
                library.setCullingManualDecision(
                    .select,
                    for: asset.id
                )
            }
            Button("Mark as Reject") {
                library.setCullingManualDecision(
                    .reject,
                    for: asset.id
                )
            }
            Button("Use Calculated Result") {
                library.setCullingManualDecision(
                    nil,
                    for: asset.id
                )
            }
            .disabled(analysis.manualDecision == nil)
        }
        Divider()
        Menu("Set Color Label") {
            PhotoColorLabelMenuItems(
                current: asset.userState.colorLabel,
                labelSet: library.activeColorLabelSet,
                editAction: {
                    library.isColorLabelSetEditorPresented = true
                }
            ) { label in
                library.setColorLabel(label, for: asset.id)
            }
        }
        stackingContextMenu(for: asset)
    }

    @ViewBuilder
    private func duplicateDigestContextButton(
        for asset: PhotoAsset
    ) -> some View {
        if let hash = library.duplicateContentHash(for: asset.id),
           let basis = library.duplicateMatchBasis(for: asset.id) {
            Button(
                basis == .imageData
                    ? "Copy Image Data SHA-256"
                    : "Copy Full File SHA-256"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    hash,
                    forType: .string
                )
            }
        }
    }

    private func stackingContextMenu(
        for asset: PhotoAsset
    ) -> some View {
        Menu("Stacking") {
            if let stack = library.photoStack(for: asset.id) {
                Button(
                    stack.isCollapsed
                        ? "Expand Stack"
                        : "Collapse Stack"
                ) {
                    library.togglePhotoStack(
                        containing: asset.id
                    )
                }
                Divider()
                Button("Move to Top") {
                    library.movePhotoInStack(asset.id, .top)
                }
                .disabled(stack.topPhotoID == asset.id)
                Button("Move Up") {
                    library.movePhotoInStack(asset.id, .up)
                }
                .disabled(stack.memberIDs.first == asset.id)
                Button("Move Down") {
                    library.movePhotoInStack(asset.id, .down)
                }
                .disabled(stack.memberIDs.last == asset.id)
                Divider()
                Button("Split Stack") {
                    _ = library.splitSelectedPhotoStack()
                }
                .disabled(!library.canSplitSelectedPhotoStack)
                Button("Remove from Stack") {
                    library.removePhotoFromStack(asset.id)
                }
                Button("Unstack") {
                    library.unstackPhoto(containing: asset.id)
                }
            } else {
                Button("Group into Stack") {
                    _ = library.stackSelectedPhotos(
                        topPhotoID: asset.id
                    )
                }
                .disabled(
                    !library.canStackSelectedPhotos
                        || !library.selectedIDs.contains(asset.id)
                )
            }
            Divider()
            Button("Expand All Stacks") {
                library.setAllPhotoStacksCollapsed(false)
            }
            Button("Collapse All Stacks") {
                library.setAllPhotoStacksCollapsed(true)
            }
            .disabled(library.photoStacks.isEmpty)
        }
    }

    @ViewBuilder
    private var assistedCullingHeader: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                Text("On-device Assisted Culling")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                Spacer()
                Button {
                    _ = library.createSuggestedCullingStacks()
                } label: {
                    Label(
                        "Create Stacks",
                        systemImage: "rectangle.stack.badge.plus"
                    )
                }
                .controlSize(.small)
                .disabled(
                    library.cullingScanResult?
                        .suggestedStacks.isEmpty != false
                        || library.cullingScanProgress != nil
                )
                .help(
                    "Create persistent stacks from the reviewed suggestions"
                )
                Menu("Apply Results") {
                    let selectLabelName =
                        library.colorLabelName(for: .green)
                    let rejectLabelName =
                        library.colorLabelName(for: .red)
                    Button("Select → Pick · Reject → Rejected") {
                        library.applyCullingFlags()
                    }
                    Divider()
                    Button(
                        "Select → \(selectLabelName) · Reject → \(rejectLabelName)"
                    ) {
                        library.applyCullingColorLabels()
                    }
                    Divider()
                    Button("Select 5★ · Reject 1★") {
                        library.applyCullingRatings(
                            selectRating: 5,
                            rejectRating: 1
                        )
                    }
                    Button("Select 4★ · Reject 0★") {
                        library.applyCullingRatings(
                            selectRating: 4,
                            rejectRating: 0
                        )
                    }
                }
                .controlSize(.small)
                .disabled(
                    library.cullingScanResult == nil
                        || library.cullingScanProgress != nil
                )
                if library.cullingScanProgress != nil {
                    Button("Cancel") {
                        library.cancelAssistedCullingScan()
                    }
                    .controlSize(.small)
                } else {
                    Button("Analyze Again") {
                        library.verifyAssistedCullingAgain()
                    }
                    .controlSize(.small)
                }
            }

            Picker(
                "Review",
                selection: $library.cullingReviewFilter
            ) {
                ForEach(AssistedCullingReviewFilter.allCases) {
                    filter in
                    Text(filter.name).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            assistedCullingStatus

            DisclosureGroup(
                isExpanded: $isCullingCriteriaExpanded
            ) {
                assistedCullingCriteriaControls
                    .padding(.top, RAWDeskTokens.Spacing.xSmall)
            } label: {
                HStack(spacing: RAWDeskTokens.Spacing.small) {
                    Label("Criteria", systemImage: "slider.horizontal.3")
                        .font(RAWDeskTokens.Typography.sectionHeader)
                    Spacer()
                    Text(cullingCriteriaSummary)
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .lineLimit(1)
                    }
            }
            Text(
                "Select a photo for complete evidence in Culling Details. Suggested stacks stay provisional until you choose Create Stacks; RAWDesk never auto-deletes a photo."
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var assistedCullingStatus: some View {
        if let progress = library.cullingScanProgress {
            ProgressView(value: progress.fractionCompleted)
            HStack {
                Text(
                    progress.filename.map {
                        "Analyzing \($0)"
                    } ?? "Preparing catalog analysis…"
                )
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer()
                Text("\(progress.completed) / \(progress.total)")
                    .monospacedDigit()
            }
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        } else if let result = library.cullingScanResult {
            let counts = result.counts(
                criteria: library.cullingCriteria
            )
            Text(
                "\(counts[.select, default: 0]) Selects · "
                    + "\(counts[.reject, default: 0]) Rejects · "
                    + "\(counts[.review, default: 0]) Review · "
                    + "\(result.suggestedStacks.count) suggested stacks"
            )
            .font(RAWDeskTokens.Typography.badge)
            if !result.unavailablePaths.isEmpty {
                Text(
                    "\(result.unavailablePaths.count) unavailable or changed files were excluded."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.warning)
            }
        }
    }

    @ViewBuilder
    private var assistedCullingCriteriaControls: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Grid(
                alignment: .leading,
                horizontalSpacing:
                    RAWDeskTokens.Spacing.small,
                verticalSpacing:
                    RAWDeskTokens.Spacing.xSmall
            ) {
                GridRow {
                    Toggle(
                        "Subject Focus",
                        isOn:
                            $library.cullingCriteria.useSubjectFocus
                    )
                    Slider(
                        value:
                            $library.cullingCriteria
                                .subjectFocusThreshold,
                        in: 0...1
                    )
                    .rawKeyboardAdjustableSlider(
                        value:
                            $library.cullingCriteria
                                .subjectFocusThreshold,
                        in: 0...1,
                        step: 0.01
                    )
                    .rawSliderTarget()
                    .frame(minWidth: 120)
                    .accessibilityLabel("Subject focus threshold")
                    .accessibilityValue(
                        percent(
                            library.cullingCriteria
                                .subjectFocusThreshold
                        )
                    )
                    TextField(
                        "Subject focus threshold",
                        value: rawClampedBinding(
                            $library.cullingCriteria
                                .subjectFocusThreshold,
                            in: 0...1
                        ),
                        format: .percent.precision(
                            .fractionLength(0)
                        )
                    )
                    .rawNumericField(width: 58)
                }
                GridRow {
                    Toggle(
                        "Eye Focus",
                        isOn: $library.cullingCriteria.useEyeFocus
                    )
                    Slider(
                        value:
                            $library.cullingCriteria
                                .eyeFocusThreshold,
                        in: 0...1
                    )
                    .rawKeyboardAdjustableSlider(
                        value:
                            $library.cullingCriteria
                                .eyeFocusThreshold,
                        in: 0...1,
                        step: 0.01
                    )
                    .rawSliderTarget()
                    .frame(minWidth: 120)
                    .disabled(!library.cullingCriteria.useEyeFocus)
                    .accessibilityLabel("Eye focus threshold")
                    .accessibilityValue(
                        percent(
                            library.cullingCriteria
                                .eyeFocusThreshold
                        )
                    )
                    TextField(
                        "Eye focus threshold",
                        value: rawClampedBinding(
                            $library.cullingCriteria
                                .eyeFocusThreshold,
                            in: 0...1
                        ),
                        format: .percent.precision(
                            .fractionLength(0)
                        )
                    )
                    .rawNumericField(width: 58)
                    .disabled(
                        !library.cullingCriteria.useEyeFocus
                    )
                }
            }
            .font(RAWDeskTokens.Typography.metadata)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 140),
                        spacing: RAWDeskTokens.Spacing.small,
                        alignment: .leading
                    ),
                ],
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.xSmall
            ) {
                Toggle(
                    "Eyes Open",
                    isOn: $library.cullingCriteria.useEyesOpen
                )
                Toggle(
                    "Exposure Issues",
                    isOn:
                        $library.cullingCriteria
                            .rejectExposureIssues
                )
                Toggle(
                    "Misfires",
                    isOn: $library.cullingCriteria.rejectMisfires
                )
                Toggle(
                    "Documents",
                    isOn:
                        $library.cullingCriteria.rejectDocuments
                )
                Toggle(
                    "Auto Stack",
                    isOn:
                        $library.cullingCriteria.suggestAutoStacks
                )
            }
            .font(RAWDeskTokens.Typography.metadata)
            .toggleStyle(.checkbox)

            if library.cullingCriteria.useEyeFocus
                || library.cullingCriteria.useEyesOpen {
                Divider()
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 190),
                            spacing: RAWDeskTokens.Spacing.small,
                            alignment: .leading
                        ),
                    ],
                    alignment: .leading,
                    spacing: RAWDeskTokens.Spacing.xSmall
                ) {
                    if library.cullingCriteria.useEyeFocus {
                        Toggle(
                            "Eye Focus requires detected eyes",
                            isOn:
                                $library.cullingCriteria
                                    .requireDetectedEyesForEyeFocus
                        )
                    }
                    if library.cullingCriteria.useEyesOpen {
                        Toggle(
                            "Eyes Open requires detected eyes",
                            isOn:
                                $library.cullingCriteria
                                    .requireDetectedEyesForEyesOpen
                        )
                        Toggle(
                            "Include Can't Tell eyes",
                            isOn:
                                $library.cullingCriteria
                                    .includeUncertainEyes
                        )
                    }
                }
                .font(RAWDeskTokens.Typography.metadata)
                .toggleStyle(.checkbox)
            }

            if library.cullingCriteria.suggestAutoStacks {
                Divider()
                Grid(
                    alignment: .leading,
                    horizontalSpacing:
                        RAWDeskTokens.Spacing.small,
                    verticalSpacing:
                        RAWDeskTokens.Spacing.xSmall
                ) {
                    GridRow {
                        Text("Stack interval")
                        Slider(
                            value:
                                $library.cullingCriteria
                                    .stackTimeWindow,
                            in: 0.5...120,
                            step: 0.5
                        )
                        .rawKeyboardAdjustableSlider(
                            value:
                                $library.cullingCriteria
                                    .stackTimeWindow,
                            in: 0.5...120,
                            step: 0.5
                        )
                        .rawSliderTarget()
                        .frame(minWidth: 120)
                        .accessibilityLabel(
                            "Maximum time between stacked photos"
                        )
                        .accessibilityValue(
                            stackTimeLabel(
                                library.cullingCriteria
                                    .stackTimeWindow
                            )
                        )
                        TextField(
                            "Stack interval in seconds",
                            value: rawClampedBinding(
                                $library.cullingCriteria
                                    .stackTimeWindow,
                                in: 0.5...120
                            ),
                            format: .number.precision(
                                .fractionLength(1)
                            )
                        )
                        .rawNumericField(width: 62)
                    }
                    GridRow {
                        Text("Visual similarity")
                        Slider(
                            value:
                                $library.cullingCriteria
                                    .stackSimilarityThreshold,
                            in: 0...1
                        )
                        .rawKeyboardAdjustableSlider(
                            value:
                                $library.cullingCriteria
                                    .stackSimilarityThreshold,
                            in: 0...1,
                            step: 0.01
                        )
                        .rawSliderTarget()
                        .frame(minWidth: 120)
                        .accessibilityLabel(
                            "Maximum visual distance for a stack"
                        )
                        .accessibilityValue(
                            percent(
                                library.cullingCriteria
                                    .stackSimilarityThreshold
                            )
                        )
                        TextField(
                            "Visual similarity threshold",
                            value: rawClampedBinding(
                                $library.cullingCriteria
                                    .stackSimilarityThreshold,
                                in: 0...1
                            ),
                            format: .percent.precision(
                                .fractionLength(0)
                            )
                        )
                        .rawNumericField(width: 58)
                    }
                }
                .font(RAWDeskTokens.Typography.metadata)
                Text(
                    "Smaller similarity values require closer-looking photos."
                )
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
    }

    private var cullingCriteriaSummary: String {
        var parts: [String] = []
        let criteria = library.cullingCriteria
        if criteria.useSubjectFocus {
            parts.append(
                "Subject \(percent(criteria.subjectFocusThreshold))"
            )
        }
        if criteria.useEyeFocus {
            parts.append("Eye \(percent(criteria.eyeFocusThreshold))")
        }
        if criteria.useEyesOpen {
            parts.append("Eyes Open")
        }
        if criteria.rejectExposureIssues {
            parts.append("Exposure")
        }
        if criteria.rejectMisfires {
            parts.append("Misfires")
        }
        if criteria.rejectDocuments {
            parts.append("Documents")
        }
        if criteria.suggestAutoStacks {
            parts.append("Stacks")
        }
        return parts.isEmpty
            ? "No active rules"
            : parts.joined(separator: " · ")
    }

    private func stackTimeLabel(_ seconds: TimeInterval) -> String {
        if seconds < 10 {
            return String(format: "%.1f s", seconds)
        }
        return "\(Int(seconds.rounded())) s"
    }

    @ViewBuilder
    private var exactDuplicateHeader: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Image(systemName: "photo.stack")
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                Text("Exact image-data duplicate verification")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                Spacer()
                if library.duplicateScanProgress != nil {
                    Button("Cancel") {
                        library.cancelExactDuplicateScan()
                    }
                    .controlSize(.small)
                } else {
                    Button("Analyze Again") {
                        library.verifyExactDuplicatesAgain()
                    }
                    .controlSize(.small)
                }
            }

            if let progress = library.duplicateScanProgress {
                ProgressView(value: progress.fractionCompleted)
                HStack {
                    Text(
                        progress.filename.map {
                            "Analyzing image data in \($0)"
                        } ?? "Preparing image-data analysis…"
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Spacer()
                    Text("\(progress.completed) / \(progress.total)")
                        .monospacedDigit()
                }
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            } else if let result = library.duplicateScanResult {
                Text(
                    "\(result.groups.count) groups · "
                        + "\(result.groupedPhotoCount) files · "
                        + "\(result.duplicateCopyCount) additional copies · "
                        + "\(formattedBytes(result.reclaimableBytes)) reviewable"
                )
                .font(RAWDeskTokens.Typography.badge)
                if result.unavailablePaths.isEmpty {
                    Text(
                        "\(result.imageDataGroupCount) groups matched decoded image data independent of filename and metadata. \(result.wholeFileFallbackGroupCount) groups used the guarded whole-file fallback. “Original” is only the earliest catalog entry, never an automatic deletion recommendation."
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                } else {
                    Text(
                        "\(result.unavailablePaths.count) changed or unavailable files were excluded. Rescan their folders before relying on those records."
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                }
            } else {
                Text(
                    "RAWDesk compares decoded source image data and ignores filename, EXIF, IPTC, XMP, color-profile metadata, and catalog edits. Undecodable equal-size files use a complete-file SHA-256 fallback. Nothing is deleted automatically."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var emptyMessage: String {
        if library.catalogCollection == .assistedCulling {
            return library.isScanning
                ? "Analyzing focus, eyes, exposure, and visual groups…"
                : "No photos match this culling review."
        }
        if library.catalogCollection == .exactDuplicates {
            return library.isScanning
                ? "Analyzing exact image data…"
                : "No duplicate image groups were found."
        }
        if library.isScanning {
            return "Loading…"
        }
        if let collection = library.activePhotoCollection {
            return "No photos are currently in \(collection.name)."
        }
        if let collection = library.activeSavedCollection {
            return "No photos currently match \(collection.name)."
        }
        if let collection = library.catalogCollection {
            return library.filter.isActive
                ? "No photos match the current filter."
                : "No photos are currently in \(collection.name)."
        }
        return library.rootURL == nil
            ? "Open a folder to begin."
            : "No photos match the current filter."
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: value,
            countStyle: .file
        )
    }

    private func quickCollectionContextButton(
        for asset: PhotoAsset
    ) -> some View {
        let willAdd = library.willAddToQuickCollection(
            for: asset.id
        )
        return Button(
            willAdd
                ? "Add to Quick Collection"
                : "Remove from Quick Collection"
        ) {
            _ = library.toggleQuickCollection(for: asset.id)
        }
    }

    @ViewBuilder
    private func photoCollectionContextMenu(
        for asset: PhotoAsset
    ) -> some View {
        if !library.photoCollections.isEmpty {
            Menu("Collections") {
                ForEach(library.photoCollections) { collection in
                    let included = library.isInPhotoCollection(
                        asset.id,
                        collectionID: collection.id
                    )
                    Button {
                        _ = library.setPhotoCollectionMembership(
                            collection,
                            for: asset.id,
                            included: !included
                        )
                    } label: {
                        Label(
                            collection.name,
                            systemImage:
                                included
                                ? "checkmark"
                                : "rectangle.stack"
                        )
                    }
                }
            }
        }

        if let activeCollection =
            library.activePhotoCollection {
            Divider()
            Button(
                "Remove from \(activeCollection.name)",
                role: .destructive
            ) {
                _ = library.setPhotoCollectionMembership(
                    activeCollection,
                    for: asset.id,
                    included: false
                )
            }
            Menu("Collection Order") {
                Button("Move to Beginning") {
                    _ = library.movePhotoInActiveCollection(
                        asset.id,
                        .beginning
                    )
                }
                Button("Move Up") {
                    _ = library.movePhotoInActiveCollection(
                        asset.id,
                        .up
                    )
                }
                Button("Move Down") {
                    _ = library.movePhotoInActiveCollection(
                        asset.id,
                        .down
                    )
                }
                Button("Move to End") {
                    _ = library.movePhotoInActiveCollection(
                        asset.id,
                        .end
                    )
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }
}
