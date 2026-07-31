import AppKit
import SwiftUI

struct PhotoImportView: View {
    @ObservedObject var library: LibraryViewModel
    let onDismiss: () -> Void

    @State private var sourceURLs: [URL] = []
    @State private var mode: PhotoImportMode = .addInPlace
    @State private var destinationURL: URL?
    @State private var recursive = true
    @State private var skipDuplicates = true
    @State private var folderOrganization:
        PhotoImportFolderOrganization = .singleFolder
    @State private var fileNaming:
        PhotoImportFileNaming = .originalFilename
    @State private var customFilenamePrefix = "Photo"
    @State private var sequenceStart = 1
    @State private var customFolderTemplate =
        PhotoImportTemplateRenderer.defaultFolderTemplate
    @State private var customFilenameTemplate =
        PhotoImportTemplateRenderer.defaultFilenameTemplate
    @State private var preflight: PhotoImportPreflight?
    @State private var result: PhotoImportResult?
    @State private var errorMessage: String?
    @State private var cancellationMessage: String?
    @State private var isBusy = false
    @State private var workflowTask: Task<Void, Never>?
    @State private var isPreflightSummaryPresented = false
    @State private var isProblemsPresented = false

    init(
        library: LibraryViewModel,
        initialSourceURLs: [URL] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.library = library
        self.onDismiss = onDismiss
        _sourceURLs = State(
            initialValue: initialSourceURLs
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ScrollView {
                        sourceSection
                            .padding(
                                RAWDeskTokens.Spacing.large
                            )
                    }
                    .frame(
                        width: max(
                            220,
                            min(270, proxy.size.width * 0.23)
                        )
                    )

                    Divider()

                    reviewColumn
                        .frame(maxWidth: .infinity)

                    Divider()

                    ScrollView {
                        methodSection
                            .padding(
                                RAWDeskTokens.Spacing.large
                            )
                    }
                    .frame(
                        width: max(
                            310,
                            min(390, proxy.size.width * 0.34)
                        )
                    )
                }
            }
            Divider()
            footer
        }
        .frame(
            minWidth: 900,
            idealWidth: 1120,
            minHeight: 560
        )
        .background(
            RAWDeskTokens.ColorToken.panel
        )
        .onChange(of: mode) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: destinationURL) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: skipDuplicates) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: folderOrganization) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: fileNaming) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: customFilenamePrefix) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: sequenceStart) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: customFolderTemplate) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: customFilenameTemplate) { _, _ in
            updatePreflightRequest()
        }
        .onChange(of: recursive) { _, _ in
            guard !sourceURLs.isEmpty else { return }
            runPreflight()
        }
        .onAppear {
            guard !sourceURLs.isEmpty,
                  preflight == nil,
                  !isBusy else {
                return
            }
            runPreflight()
        }
        .onDisappear {
            workflowTask?.cancel()
        }
        .onExitCommand {
            guard !isBusy else { return }
            onDismiss()
        }
        .sheet(isPresented: $isProblemsPresented) {
            if let result {
                ImportProblemsView(result: result)
            }
        }
    }

    private var header: some View {
        HStack(spacing: RAWDeskTokens.Spacing.medium) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(RAWDeskTokens.Typography.modalTitle)
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Import Photos")
                    .font(RAWDeskTokens.Typography.modalTitle)
                Text("Preview new, duplicate, and unsupported files before anything changes.")
                    .font(RAWDeskTokens.Typography.control)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            Spacer()
            Button("Close") {
                onDismiss()
            }
            .disabled(isBusy)
            .help(
                isBusy
                    ? "Stop the current operation before closing."
                    : "Close Import"
            )
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.large)
        .frame(minHeight: 64)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
            importColumnTitle(
                "Source",
                systemImage: "externaldrive"
            )

            Button {
                chooseSources()
            } label: {
                Label(
                    "Choose Photos or Folders…",
                    systemImage: "plus"
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight:
                        RAWDeskTokens.Size
                            .primaryButtonHeight
                )
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .accessibilityIdentifier(
                "Choose photos or folders"
            )
            .disabled(isBusy)

            Toggle("Include subfolders", isOn: $recursive)
                .disabled(isBusy)

            Divider()

            Text(sourceSummary)
                .font(
                    RAWDeskTokens.Typography.control
                        .weight(.semibold)
                )

            if sourceURLs.isEmpty {
                Text(
                    "Choose individual photos, one folder, or several folders."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
            } else {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                    ForEach(
                        Array(sourceURLs.prefix(8)),
                        id: \.standardizedFileURL.path
                    ) { url in
                        Label {
                            Text(url.path)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        } icon: {
                            Image(
                                systemName:
                                    url.hasDirectoryPath
                                    ? "folder"
                                    : "photo"
                            )
                        }
                        .font(
                            RAWDeskTokens.Typography
                                .metadata
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                    }
                    if sourceURLs.count > 8 {
                        Text(
                            "\(sourceURLs.count - 8) more selected"
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
                }
            }
        }
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
            importColumnTitle(
                "File Handling",
                systemImage: "arrow.right.doc.on.clipboard"
            )

            VStack(spacing: RAWDeskTokens.Spacing.small) {
                ForEach(PhotoImportMode.allCases) { method in
                    importMethodCard(method)
                }
            }
            .accessibilityIdentifier("Import method")

            if mode.removesVerifiedSources {
                moveSafetyExplanation
            }

            if mode.requiresDestination {
                    VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
                        HStack {
                            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                                Text("Destination")
                                    .font(RAWDeskTokens.Typography.metadata)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                Text(
                                    destinationURL?.path
                                        ?? "No destination selected"
                                )
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            }
                            Spacer()
                            Button("Choose Destination…") {
                                chooseDestination()
                            }
                            .accessibilityIdentifier(
                                "Choose import destination"
                            )
                            .disabled(isBusy)
                        }

                        Divider()

                        HStack {
                            Text("Organize")
                            Spacer()
                            Picker(
                                "Organize transferred photos",
                                selection: $folderOrganization
                            ) {
                                ForEach(
                                    PhotoImportFolderOrganization
                                        .allCases
                                ) { organization in
                                    Text(organization.name)
                                        .tag(organization)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190)
                            .disabled(isBusy)
                        }
                        Text(folderOrganization.detail)
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

                        if folderOrganization
                            == .customTemplate {
                            HStack(spacing: RAWDeskTokens.Spacing.small) {
                                TextField(
                                    "Folder template",
                                    text: $customFolderTemplate
                                )
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier(
                                    "Import folder template"
                                )
                                .disabled(isBusy)
                                Menu("Insert Token") {
                                    ForEach(
                                        PhotoImportTemplateRenderer
                                            .folderTokenExamples,
                                        id: \.self
                                    ) { token in
                                        Button(token) {
                                            customFolderTemplate
                                                .append(token)
                                        }
                                    }
                                }
                                .disabled(isBusy)
                            }
                            Text(
                                "Use / between folder levels. Braces can be written literally as {{ or }}."
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            if let example =
                                customFolderTemplateExample {
                                Text("Example: \(example)")
                                    .font(RAWDeskTokens.Typography.numeric)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }
                        }

                        HStack {
                            Text("File naming")
                            Spacer()
                            Picker(
                                "Transferred file naming",
                                selection: $fileNaming
                            ) {
                                ForEach(
                                    PhotoImportFileNaming.allCases
                                ) { naming in
                                    Text(naming.name).tag(naming)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190)
                            .disabled(isBusy)
                        }

                        if fileNaming == .customSequence {
                            TextField(
                                "Filename prefix",
                                text: $customFilenamePrefix
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBusy)
                            Text(customFilenameExample)
                                .font(RAWDeskTokens.Typography.numeric)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }

                        if fileNaming == .tokenTemplate {
                            HStack(spacing: RAWDeskTokens.Spacing.small) {
                                TextField(
                                    "Filename template",
                                    text: $customFilenameTemplate
                                )
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier(
                                    "Import filename template"
                                )
                                .disabled(isBusy)
                                Menu("Insert Token") {
                                    ForEach(
                                        PhotoImportTemplateRenderer
                                            .filenameTokenExamples,
                                        id: \.self
                                    ) { token in
                                        Button(token) {
                                            customFilenameTemplate
                                                .append(token)
                                        }
                                    }
                                }
                                .disabled(isBusy)
                            }
                            Text(
                                "The original extension is preserved automatically."
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            if let example =
                                customFilenameTemplateExample {
                                Text("Example: \(example)")
                                    .font(RAWDeskTokens.Typography.numeric)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            }
                        }

                        if currentRequest.usesSequence {
                            HStack {
                                Text("Sequence starts at")
                                Spacer()
                                Stepper(
                                    "\(sequenceStart)",
                                    value: $sequenceStart,
                                    in: 1...999_999
                                )
                                .frame(width: 118)
                                .disabled(isBusy)
                                .accessibilityIdentifier(
                                    "Import sequence start"
                                )
                            }
                        }

                        if let validation =
                            currentRequest
                                .templateValidationMessage {
                            Label(
                                validation,
                                systemImage:
                                    "exclamationmark.triangle.fill"
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                            .accessibilityIdentifier(
                                "Import template error"
                            )
                        }

                    }
                }

                Toggle(
                    "Skip exact duplicates",
                    isOn: $skipDuplicates
                )
                .help(
                    "Uses the complete file contents, not the filename, to detect duplicates."
                )
                .disabled(isBusy)
            }
        }

    private var moveSafetyExplanation: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Label(
                "Copy + Trash changes the original location",
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(
                RAWDeskTokens.Typography.sectionHeader
            )
            .foregroundStyle(
                RAWDeskTokens.ColorToken.warning
            )

            Text(
                "From: \(sourceURLs.isEmpty ? "No source selected" : sourceSummary)"
            )
            Text(
                "To: \(destinationURL?.path ?? "No destination selected")"
            )
            Text(
                "Sources move to the macOS Trash only after SHA-256 verification, catalog registration, and a final source check all succeed."
            )
            Text(
                "Already-cataloged files in the same location are never moved. Any failed check keeps the source and destination; RAWDesk never falls back to permanent deletion."
            )
        }
        .font(RAWDeskTokens.Typography.metadata)
        .foregroundStyle(
            RAWDeskTokens.ColorToken.textSecondary
        )
        .padding(RAWDeskTokens.Spacing.small)
        .background(
            RAWDeskTokens.ColorToken.warning
                .opacity(0.08),
            in: RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.group
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.group
            )
            .stroke(
                RAWDeskTokens.ColorToken.warning
                    .opacity(0.45),
                lineWidth: 1
            )
        }
        .accessibilityIdentifier(
            "Copy and Trash source safety explanation"
        )
    }

    private var reviewColumn: some View {
        VStack(spacing: 0) {
            HStack {
                importColumnTitle(
                    result == nil ? "Review" : "Result",
                    systemImage:
                        result == nil
                        ? "checklist"
                        : "checkmark.circle"
                )
                Spacer()
                if let preflight, result == nil {
                    Text(
                        "\(preflight.items.count) item\(preflight.items.count == 1 ? "" : "s")"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                }
            }
            .padding(
                RAWDeskTokens.Spacing.large
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
                    if let progress = library.importProgress {
                        progressSection(progress)
                    }
                    if let errorMessage {
                        RAWInlineMessage(
                            title: "Import could not continue",
                            message: errorMessage,
                            systemImage:
                                "exclamationmark.triangle.fill",
                            tone: .destructive
                        )
                        .accessibilityIdentifier(
                            "Import error"
                        )
                    }
                    if let cancellationMessage {
                        RAWInlineMessage(
                            title: "Import stopped safely",
                            message: cancellationMessage,
                            systemImage: "stop.circle",
                            tone: .neutral
                        )
                        .accessibilityIdentifier(
                            "Import cancellation result"
                        )
                    }

                    if let result {
                        resultSection(result)
                    } else if let preflight {
                        preflightSection(preflight)
                    } else {
                        reviewEmptyState
                    }
                }
                .padding(
                    RAWDeskTokens.Spacing.large
                )
            }
        }
    }

    private var reviewEmptyState: some View {
        RAWEmptyState(
            title: "Choose photos to review",
            systemImage: "photo.on.rectangle.angled",
            message:
                "RAWDesk will show New, Duplicate, Unsupported, and Unavailable status before anything changes.",
            layout: .compact
        ) {
            Button {
                chooseSources()
            } label: {
                Label(
                    "Choose Photos or Folders…",
                    systemImage: "arrow.left"
                )
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 260
        )
    }

    private func importColumnTitle(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(
                RAWDeskTokens.Typography
                    .workspaceHeader
            )
    }

    private func importMethodCard(
        _ method: PhotoImportMode
    ) -> some View {
        Button {
            mode = method
        } label: {
            HStack(alignment: .top, spacing: RAWDeskTokens.Spacing.small) {
                Image(
                    systemName:
                        mode == method
                        ? "largecircle.fill.circle"
                        : "circle"
                )
                .foregroundStyle(
                    mode == method
                        ? RAWDeskTokens.ColorToken.selection
                        : RAWDeskTokens.ColorToken
                            .textSecondary
                )
                .frame(width: 18, height: 20)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                        Text(method.name)
                            .font(
                                RAWDeskTokens.Typography
                                    .control
                                    .weight(.semibold)
                            )
                        Spacer(minLength: 4)
                        RAWStateBadge(
                            text:
                                method.removesVerifiedSources
                                ? "Originals affected"
                                : "Safe",
                            systemImage:
                                method.removesVerifiedSources
                                ? "exclamationmark.triangle"
                                : "checkmark.shield",
                            tone:
                                method.removesVerifiedSources
                                ? .warning
                                : .neutral
                        )
                        .accessibilityHidden(true)
                    }
                    Text(importMethodExplanation(method))
                        .font(
                            RAWDeskTokens.Typography
                                .metadata
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }
            .padding(RAWDeskTokens.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                mode == method
                    ? RAWDeskTokens.ColorToken.selection.opacity(0.12)
                    : RAWDeskTokens.ColorToken
                        .controlElevated.opacity(0.55),
                in: RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.group
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.group
                )
                .stroke(
                    mode == method
                        ? RAWDeskTokens.ColorToken.selection
                        : RAWDeskTokens.ColorToken.divider,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(method.name)
        .accessibilityValue(
            (mode == method ? "Selected. " : "Not selected. ")
            + importMethodExplanation(method)
        )
        .accessibilityAddTraits(
            mode == method ? .isSelected : []
        )
        .accessibilityRemoveTraits(
            mode == method ? [] : .isSelected
        )
    }

    private func importMethodExplanation(
        _ method: PhotoImportMode
    ) -> String {
        switch method {
        case .addInPlace:
            return "Reference the current location. Nothing is copied or deleted."
        case .copyToFolder:
            return "Create and verify copies. The source files remain where they are."
        case .moveToFolder:
            return "Copy and verify each source, register the destination, then move the source to the macOS Trash."
        }
    }

    @ViewBuilder
    private func progressSection(
        _ progress: PhotoImportProgress
    ) -> some View {
        ImportPanelSection(
            title: progress.phase.name,
            systemImage: "clock.arrow.circlepath"
        ) {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                HStack {
                    Text(progress.filename ?? "Preparing…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if progress.total > 0 {
                        Text("\(progress.completed) of \(progress.total)")
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            .monospacedDigit()
                    }
                }
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
        }
        .accessibilityIdentifier("Import progress")
    }

    private func preflightSection(
        _ preview: PhotoImportPreflight
    ) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: RAWDeskTokens.Spacing.small),
                    count: 4
                ),
                spacing: RAWDeskTokens.Spacing.small
            ) {
                ImportStatView(
                    title: "New",
                    value: preview.readyCount,
                    color:
                        RAWDeskTokens.ColorToken.success
                )
                ImportStatView(
                    title: "Duplicates",
                    value: preview.duplicateCount,
                    color:
                        RAWDeskTokens.ColorToken.warning
                )
                ImportStatView(
                    title: "Unsupported",
                    value: preview.unsupportedCount,
                    color:
                        RAWDeskTokens.ColorToken
                            .textSecondary
                )
                ImportStatView(
                    title: "Unavailable",
                    value: preview.unavailableCount,
                    color:
                        RAWDeskTokens.ColorToken
                            .destructive
                )
            }

            HStack {
                Text(
                    "\(preview.importableCount) photo\(preview.importableCount == 1 ? "" : "s") ready · \(formattedBytes(preview.importableByteCount))"
                )
                .font(RAWDeskTokens.Typography.control)
                Spacer()
                Text("SHA-256 exact-content check")
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }

            ImportPanelSection(
                title: "Preflight Results",
                systemImage: "checklist"
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(preview.items.prefix(250))) { item in
                        ImportItemRow(item: item)
                        if item.id != preview.items.prefix(250).last?.id {
                            Divider()
                        }
                    }
                    if preview.items.count > 250 {
                        Text(
                            "\(preview.items.count - 250) more items are included in the counts above."
                        )
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .padding(RAWDeskTokens.Spacing.small)
                    }
                }
            }

            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    ForEach(preview.warnings, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle")
                    }
                }
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.warning)
            }
        }
        .accessibilityIdentifier("Import preflight results")
    }

    private func resultSection(
        _ completed: PhotoImportResult
    ) -> some View {
        let presentation =
            PhotoImportResultPresentation(
                result: completed
            )
        return ImportPanelSection(
            title: presentation.title,
            systemImage:
                presentation.requiresAttention
                ? "exclamationmark.circle.fill"
                : "checkmark.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Label(
                    presentation.headline,
                    systemImage:
                        presentation.requiresAttention
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill"
                )
                .font(RAWDeskTokens.Typography.workspaceHeader)
                .foregroundStyle(
                    presentation.requiresAttention
                        ? RAWDeskTokens.ColorToken.warning
                        : RAWDeskTokens.ColorToken.success
                )

                if let cancellationDetail =
                    presentation
                        .cancellationDetail {
                    Text(
                        cancellationDetail
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 180),
                            alignment: .leading
                        ),
                    ],
                    alignment: .leading,
                    spacing: RAWDeskTokens.Spacing.small
                ) {
                    if completed.copiedCount > 0 {
                        Label(
                            "\(completed.copiedCount) copied and verified",
                            systemImage: "doc.on.doc"
                        )
                    }
                    if completed.movedCount > 0 {
                        Label(
                            "\(completed.movedCount) original"
                                + "\(completed.movedCount == 1 ? "" : "s") moved to Trash",
                            systemImage: "trash"
                        )
                    }
                    if completed.retainedSourceCount > 0 {
                        Label(
                            "\(completed.retainedSourceCount) original"
                                + "\(completed.retainedSourceCount == 1 ? "" : "s") retained for safety",
                            systemImage: "shield.lefthalf.filled"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                    }
                    if completed.retainedSourceSidecarCount > 0 {
                        Label(
                            "\(completed.retainedSourceSidecarCount) source sidecar"
                                + "\(completed.retainedSourceSidecarCount == 1 ? "" : "s") retained",
                            systemImage: "doc.badge.exclamationmark"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                    }
                    if completed.reusedDestinationCount > 0 {
                        Label(
                            "\(completed.reusedDestinationCount) already at destination",
                            systemImage: "equal.circle"
                        )
                    }
                    if completed.renamedCount > 0 {
                        Label(
                            "\(completed.renamedCount) named by template",
                            systemImage: "textformat.123"
                        )
                    }
                    if completed.organizedFolderCount > 0 {
                        Label(
                            "\(completed.organizedFolderCount) organized folder"
                                + "\(completed.organizedFolderCount == 1 ? "" : "s")",
                            systemImage: "calendar.badge.checkmark"
                        )
                    }
                    if completed.skippedDuplicateCount > 0 {
                        Label(
                            "\(completed.skippedDuplicateCount) duplicates skipped",
                            systemImage: "rectangle.on.rectangle.slash"
                        )
                    }
                }
                .font(RAWDeskTokens.Typography.control)

                if !completed.duplicateGroups.isEmpty {
                    Divider()
                    DisclosureGroup(
                        "Review Exact Duplicate Groups (\(completed.duplicateGroups.count))"
                    ) {
                        LazyVStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                            ForEach(completed.duplicateGroups) { group in
                                ImportDuplicateGroupView(group: group)
                            }
                        }
                        .padding(.top, RAWDeskTokens.Spacing.small)
                    }
                    .accessibilityIdentifier(
                        "Review exact duplicate groups"
                    )
                }

                if !completed.failures.isEmpty {
                    Divider()
                    Text("Could not import")
                        .font(RAWDeskTokens.Typography.workspaceHeader)
                    ForEach(completed.failures, id: \.self) {
                        Text("• \($0)")
                            .font(RAWDeskTokens.Typography.control)
                            .foregroundStyle(
                                RAWDeskTokens.ColorToken
                                    .destructive
                            )
                            .textSelection(.enabled)
                    }
                }
                if !completed.warnings.isEmpty {
                    Divider()
                    Text("Warnings")
                        .font(RAWDeskTokens.Typography.workspaceHeader)
                    ForEach(completed.warnings, id: \.self) {
                        Text("• \($0)")
                            .font(RAWDeskTokens.Typography.control)
                            .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .accessibilityIdentifier("Import result")
    }

    @ViewBuilder
    private var footer: some View {
        if isBusy {
            RAWProgressBanner(
                title: importProgressSummary,
                fraction:
                    library.importProgress?
                        .fraction,
                accessibilityLabel:
                    "Import progress: \(importProgressSummary)"
            ) {
                if library.importProgress?.phase
                    == .removingSources {
                    Label(
                        "Finishing verified Trash disposition…",
                        systemImage:
                            "checkmark.shield"
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                } else {
                    Button("Cancel") {
                        workflowTask?.cancel()
                    }
                    .help(
                        "Stop safely. Uncommitted copies are removed and Copy + Trash originals remain in place."
                    )
                }
            }
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.large
            )
            .frame(minHeight: 68)
        } else {
            RAWPrimaryFooterBar {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                if let result {
                    Text(
                        "\(result.importedCount) imported · \(result.skippedDuplicateCount) skipped · \(result.failures.count) failed"
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .control
                    )
                    .monospacedDigit()
                } else {
                    RAWPreflightSummary(
                        summary:
                            preflightPresentation?
                                .footerSummary
                                ?? "0 total · 0 new · 0 duplicates · 0 unsupported",
                        isAvailable:
                            preflight != nil,
                        isPresented:
                            $isPreflightSummaryPresented
                    ) {
                        if let preflight {
                            preflightSummaryDetails(
                                preflight
                            )
                        } else {
                            EmptyView()
                        }
                    }

                    if let reason = importDisabledReason {
                        Label(
                            reason,
                            systemImage: "info.circle"
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
                }
            }
            } actions: {
                if let result {
                let presentation =
                    PhotoImportResultPresentation(
                        result: result
                    )
                if presentation.showsRevealProblems {
                    Button("Reveal Problems") {
                        isProblemsPresented = true
                    }
                }
                if presentation.showsLastImport {
                    Button("Show Last Import") {
                        onDismiss()
                    }
                }
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
                .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        onDismiss()
                    }

                    Button(
                        preflight == nil
                            ? "Analyze"
                            : "Analyze Again"
                    ) {
                        runPreflight()
                    }
                    .disabled(sourceURLs.isEmpty)

                    Button(importButtonTitle) {
                        runImport()
                    }
                    .buttonStyle(.borderedProminent)
                    .rawPrimaryButtonHeight()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
                    .accessibilityIdentifier(
                        "Import checked photos"
                    )
                }
            }
        }
    }

    private var preflightPresentation:
        PhotoImportPreflightPresentation? {
        preflight.map {
            PhotoImportPreflightPresentation(
                preflight: $0,
                request: currentRequest
            )
        }
    }

    private var importProgressSummary: String {
        guard let progress = library.importProgress else {
            return "Analyzing sources…"
        }
        if progress.total > 0 {
            return "\(progress.phase.name) \(progress.completed)/\(progress.total) · \(progress.filename ?? "Preparing…")"
        }
        return "\(progress.phase.name) · \(progress.filename ?? "Preparing…")"
    }

    private func preflightSummaryDetails(
        _ preview: PhotoImportPreflight
    ) -> some View {
        let presentation =
            PhotoImportPreflightPresentation(
                preflight: preview,
                request: currentRequest
            )
        return VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Text("Preflight Details")
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
            LabeledContent("Unavailable") {
                Text("\(presentation.unavailableCount)")
                    .monospacedDigit()
            }
            LabeledContent("Estimated copy size") {
                Text(presentation.estimatedCopySize)
            }
            LabeledContent("XMP companions") {
                Text("\(presentation.xmpCompanionCount)")
                    .monospacedDigit()
            }
            LabeledContent("Naming conflicts") {
                Text(presentation.namingConflictDetail)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
            LabeledContent("Warnings") {
                Text("\(presentation.warningCount)")
                    .monospacedDigit()
            }
            if !presentation.warnings.isEmpty {
                Divider()
                ForEach(
                    Array(presentation.warnings.prefix(6)),
                    id: \.self
                ) { warning in
                    Label(
                        warning,
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .metadata
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }
            }
        }
        .padding(RAWDeskTokens.Spacing.medium)
        .frame(width: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preflight Details")
        .accessibilityValue(
            presentation.accessibilityDetailSummary
        )
    }

    private var importDisabledReason: String? {
        if sourceURLs.isEmpty {
            return "Choose photos or folders to continue."
        }
        guard let preflight else {
            return "Analyze the selected source to continue."
        }
        if preflight.importableCount == 0 {
            return "There are no photos ready to import."
        }
        if mode.requiresDestination,
           destinationURL == nil {
            return "Choose a destination folder."
        }
        if let validation =
            currentRequest.templateValidationMessage {
            return validation
        }
        return nil
    }

    private var sourceSummary: String {
        switch sourceURLs.count {
        case 0:
            return "No source selected"
        case 1:
            return sourceURLs[0].lastPathComponent
        default:
            return "\(sourceURLs.count) items selected"
        }
    }

    private var importButtonTitle: String {
        guard let count = preflight?.importableCount else {
            return mode.removesVerifiedSources
                ? "Copy, Import & Trash"
                : "Import"
        }
        let verb =
            mode.removesVerifiedSources
            ? "Copy, Import & Trash"
            : "Import"
        return count == 1
            ? "\(verb) 1 Photo"
            : "\(verb) \(count) Photos"
    }

    private var canImport: Bool {
        guard !isBusy,
              let preflight,
              preflight.importableCount > 0 else {
            return false
        }
        return (
            !mode.requiresDestination || destinationURL != nil
        ) && currentRequest.templateValidationMessage == nil
    }

    private func chooseSources() {
        let panel = NSOpenPanel()
        panel.title = "Choose Photos or Folders"
        panel.message =
            "Select supported image files or folders. RAWDesk will check them before importing."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        if panel.runModal() == .OK {
            sourceURLs = panel.urls
            result = nil
            runPreflight()
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = mode.removesVerifiedSources
            ? "Choose Copy + Trash Destination"
            : "Choose Import Destination"
        panel.message = mode.removesVerifiedSources
            ? "RAWDesk first copies and verifies every photo and XMP, updates the catalog, and only then moves each verified source to the macOS Trash."
            : "RAWDesk will copy and verify photos in this folder without changing the sources."
        panel.prompt = "Choose Destination"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            destinationURL = panel.url
        }
    }

    private func runPreflight() {
        guard !sourceURLs.isEmpty else { return }
        workflowTask?.cancel()
        preflight = nil
        result = nil
        errorMessage = nil
        cancellationMessage = nil
        isBusy = true
        let request = currentRequest
        workflowTask = Task {
            defer { isBusy = false }
            do {
                preflight = try await library.preflightImport(request)
            } catch is CancellationError {
                cancellationMessage =
                    "Analysis was canceled. No photo, sidecar, catalog record, or original file was changed."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runImport() {
        guard var checked = preflight else { return }
        checked.request = currentRequest
        workflowTask?.cancel()
        errorMessage = nil
        cancellationMessage = nil
        isBusy = true
        let wasMove =
            checked.request.mode.removesVerifiedSources
        workflowTask = Task {
            defer { isBusy = false }
            do {
                result = try await library.executeImport(
                    checked
                )
            } catch is CancellationError {
                cancellationMessage =
                    wasMove
                    ? "0 photos completed. Uncommitted copies were removed, and no original was moved to Trash."
                    : "0 photos completed. Uncommitted copies were removed, and no original file was changed."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var currentRequest: PhotoImportRequest {
        PhotoImportRequest(
            sourceURLs: sourceURLs,
            mode: mode,
            destinationURL: destinationURL,
            recursive: recursive,
            skipDuplicates: skipDuplicates,
            folderOrganization: folderOrganization,
            fileNaming: fileNaming,
            customFilenamePrefix: customFilenamePrefix,
            sequenceStart: sequenceStart,
            customFolderTemplate: customFolderTemplate,
            customFilenameTemplate: customFilenameTemplate
        )
    }

    private func updatePreflightRequest() {
        guard var checked = preflight else { return }
        checked.request = currentRequest
        preflight = checked
    }

    private func formattedBytes(_ count: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: count,
            countStyle: .file
        )
    }

    private var customFilenameExample: String {
        let prefix = PhotoImportRequest.normalizedFilenamePrefix(
            customFilenamePrefix
        )
        return "Example: \(prefix)-\(String(format: "%04d", sequenceStart)).jpg"
    }

    private var templateExampleContext:
        PhotoImportTemplateContext {
        PhotoImportTemplateContext(
            sourceURL:
                preflight?.items.first?.sourceURL
                    ?? URL(
                        fileURLWithPath:
                            "/Pictures/Studio/IMG_0001.CR2"
                    ),
            captureDate: Date(
                timeIntervalSince1970: 1_767_268_800
            ),
            fallbackDate: Date(
                timeIntervalSince1970: 1_767_268_800
            ),
            cameraMake: "Canon",
            cameraModel: "EOS R5",
            sequence: sequenceStart
        )
    }

    private var customFolderTemplateExample: String? {
        try? PhotoImportTemplateRenderer
            .renderFolderComponents(
                customFolderTemplate,
                context: templateExampleContext
            )
            .joined(separator: "/")
    }

    private var customFilenameTemplateExample: String? {
        guard let base = try?
                PhotoImportTemplateRenderer
                    .renderFilenameBase(
                        customFilenameTemplate,
                        context: templateExampleContext
                    ) else {
            return nil
        }
        let ext =
            templateExampleContext.sourceURL.pathExtension
                .isEmpty
                ? "ext"
                : templateExampleContext.sourceURL.pathExtension
        return "\(base).\(ext)"
    }
}

private struct ImportProblemsView: View {
    let result: PhotoImportResult

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    "Import Problems",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(
                    RAWDeskTokens.Typography
                        .modalTitle
                )
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(RAWDeskTokens.Spacing.large)

            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: RAWDeskTokens.Spacing.medium
                ) {
                    if result.retainedSourceCount > 0 {
                        RAWInlineMessage(
                            title: "Originals retained",
                            message:
                                "\(result.retainedSourceCount) original file"
                                + (
                                    result.retainedSourceCount == 1
                                        ? " was"
                                        : "s were"
                                )
                                + " retained because a Copy + Trash safety check did not complete.",
                            systemImage: "checkmark.shield",
                            tone: .warning
                        )
                    }
                    if result.retainedSourceSidecarCount > 0 {
                        RAWInlineMessage(
                            title: "Sidecars retained",
                            message:
                                "\(result.retainedSourceSidecarCount) source XMP sidecar"
                                + (
                                    result.retainedSourceSidecarCount == 1
                                        ? " was"
                                        : "s were"
                                )
                                + " retained for safety.",
                            systemImage:
                                "doc.badge.exclamationmark",
                            tone: .warning
                        )
                    }
                    if !result.failures.isEmpty {
                        problemSection(
                            title: "Failed",
                            systemImage: "xmark.octagon",
                            values: result.failures,
                            tone: .destructive
                        )
                    }
                    if !result.warnings.isEmpty {
                        problemSection(
                            title: "Warnings",
                            systemImage:
                                "exclamationmark.triangle",
                            values: result.warnings,
                            tone: .warning
                        )
                    }
                }
                .padding(RAWDeskTokens.Spacing.large)
            }
        }
        .frame(
            minWidth: 540,
            idealWidth: 640,
            minHeight: 360,
            idealHeight: 480
        )
        .background(RAWDeskTokens.ColorToken.panel)
    }

    private func problemSection(
        title: String,
        systemImage: String,
        values: [String],
        tone: RAWBadgeTone
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Label(title, systemImage: systemImage)
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
                .foregroundStyle(tone.background)
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(
                        RAWDeskTokens.Typography
                            .control
                    )
                    .textSelection(.enabled)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImportDuplicateGroupView: View {
    var group: PhotoImportDuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            HStack {
                Label(
                    "\(group.matches.count) exact match"
                        + "\(group.matches.count == 1 ? "" : "es")",
                    systemImage: "equal.square"
                )
                .font(RAWDeskTokens.Typography.sectionHeader)
                Spacer()
                Text(
                    ByteCountFormatter.string(
                        fromByteCount: group.fileSize,
                        countStyle: .file
                    )
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }

            Text("SHA-256 \(group.contentHash)")
                .font(RAWDeskTokens.Typography.numeric)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            ForEach(group.matches) { match in
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(match.sourceURL.lastPathComponent)
                            .font(RAWDeskTokens.Typography.control)
                        Text("→ \(match.matchKindName)")
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                        Spacer()
                        Button {
                            NSWorkspace.shared
                                .activateFileViewerSelecting([
                                    match.sourceURL,
                                ])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .rawIconButtonTarget()
                        .help("Show selected source in Finder")
                        .accessibilityLabel(
                            "Show selected source in Finder"
                        )

                        Button {
                            NSWorkspace.shared
                                .activateFileViewerSelecting([
                                    URL(
                                        fileURLWithPath:
                                            match.matchingPath
                                    ),
                                ])
                        } label: {
                            Image(systemName: "folder.badge.checkmark")
                        }
                        .buttonStyle(.borderless)
                        .rawIconButtonTarget()
                        .help("Show exact match in Finder")
                        .accessibilityLabel(
                            "Show exact match in Finder"
                        )
                        .disabled(
                            !FileManager.default.fileExists(
                                atPath: match.matchingPath
                            )
                        )
                    }
                    Text(match.sourceURL.path)
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(match.matchingPath)
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .padding(.top, RAWDeskTokens.Spacing.xSmall)
            }
        }
        .padding(RAWDeskTokens.Spacing.small)
        .background(
            RAWDeskTokens.ColorToken.warning.opacity(0.07),
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
                .stroke(RAWDeskTokens.ColorToken.warning.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct ImportStatView: View {
    var title: String
    var value: Int
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            Text("\(value)")
                .font(RAWDeskTokens.Typography.modalTitle)
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RAWDeskTokens.Spacing.medium)
        .background(
            color.opacity(0.08),
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
        )
    }
}

private struct ImportPanelSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Label(title, systemImage: systemImage)
                .font(RAWDeskTokens.Typography.workspaceHeader)
            Divider()
            content
        }
        .padding(RAWDeskTokens.Spacing.medium)
        .background(
            RAWDeskTokens.ColorToken.textPrimary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
                .stroke(RAWDeskTokens.ColorToken.textPrimary.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct ImportItemRow: View {
    var item: PhotoImportItem

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text(item.sourceURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = statusDetail {
                    Text(detail)
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if item.sidecarURL != nil {
                RAWStateBadge(
                    text: "XMP",
                    tone: .accent,
                    prominence: .soft
                )
            }
            Text(statusName)
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(statusColor)
            Text(
                ByteCountFormatter.string(
                    fromByteCount: item.fileSize,
                    countStyle: .file
                )
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
    }

    private var statusName: String {
        switch item.status {
        case .ready: return "New"
        case .duplicate: return "Duplicate"
        case .unsupported: return "Unsupported"
        case .unavailable: return "Unavailable"
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .ready: return "checkmark.circle.fill"
        case .duplicate: return "rectangle.on.rectangle.slash"
        case .unsupported: return "nosign"
        case .unavailable: return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .ready:
            return RAWDeskTokens.ColorToken.success
        case .duplicate:
            return RAWDeskTokens.ColorToken.warning
        case .unsupported:
            return RAWDeskTokens.ColorToken
                .textSecondary
        case .unavailable:
            return RAWDeskTokens.ColorToken.destructive
        }
    }

    private var statusDetail: String? {
        switch item.status {
        case .ready:
            return item.sourceURL.deletingLastPathComponent().path
        case let .duplicate(duplicate):
            return duplicate.detail
        case .unsupported:
            return item.sourceURL.pathExtension.isEmpty
                ? "Unsupported file type"
                : "\(item.sourceURL.pathExtension.uppercased()) is not supported"
        case let .unavailable(reason):
            return reason
        }
    }
}
