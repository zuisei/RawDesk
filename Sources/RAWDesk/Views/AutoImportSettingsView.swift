import AppKit
import SwiftUI

struct AutoImportSettingsView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AutoImportSettings
    @State private var keywordsText: String
    @State private var saveError: String?

    init(library: LibraryViewModel) {
        self.library = library
        let settings = library.autoImportSettings
        _draft = State(initialValue: settings)
        _keywordsText = State(
            initialValue: settings.keywords.joined(
                separator: ", "
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: RAWDeskTokens.Spacing.large) {
                    folderSection
                    handlingSection
                    informationSection
                    safetySection
                }
                .padding(RAWDeskTokens.Spacing.xLarge)
            }
            Divider()
            footer
        }
        .frame(
            minWidth: 680,
            idealWidth: 720,
            minHeight: 600,
            idealHeight: 660
        )
        .onExitCommand {
            dismiss()
        }
    }

    private var header: some View {
        HStack(spacing: RAWDeskTokens.Spacing.medium) {
            Image(systemName: "folder.badge.gearshape")
                .font(RAWDeskTokens.Typography.modalTitle)
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                .frame(width: 32, height: 32)
                .background(
                    RAWDeskTokens.ColorToken.selection.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
                )
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Auto Import")
                    .font(RAWDeskTokens.Typography.modalTitle)
                Text(
                    "Copy completed camera downloads into the catalog without opening Import."
                )
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $draft.enabled)
                .toggleStyle(.switch)
                .accessibilityIdentifier(
                    "Enable Auto Import"
                )
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
    }

    private var folderSection: some View {
        AutoImportPanelSection(
            title: "Folders",
            systemImage: "folder"
        ) {
            VStack(spacing: RAWDeskTokens.Spacing.medium) {
                folderRow(
                    title: "Watched folder",
                    detail:
                        "RAWDesk watches supported photos directly inside this folder. Subfolders are ignored.",
                    url: draft.watchedFolderURL,
                    buttonTitle: "Choose Watched Folder…",
                    accessibilityIdentifier:
                        "Choose Auto Import watched folder"
                ) {
                    chooseFolder(
                        title: "Choose Watched Folder",
                        prompt: "Watch Folder"
                    ) {
                        draft.watchedFolderURL = $0
                    }
                }

                Divider()

                folderRow(
                    title: "Copy to",
                    detail:
                        "RAWDesk verifies and catalogs the destination copy here. Source handling is chosen separately below.",
                    url: draft.destinationFolderURL,
                    buttonTitle: "Choose Destination…",
                    accessibilityIdentifier:
                        "Choose Auto Import destination"
                ) {
                    chooseFolder(
                        title: "Choose Auto Import Destination",
                        prompt: "Choose"
                    ) {
                        draft.destinationFolderURL = $0
                    }
                }
            }
        }
    }

    private var handlingSection: some View {
        AutoImportPanelSection(
            title: "File Handling",
            systemImage: "arrow.right.doc.on.clipboard"
        ) {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
                HStack {
                    Text("Source handling")
                    Spacer()
                    Picker(
                        "Source handling",
                        selection: $draft.sourceHandling
                    ) {
                        ForEach(
                            AutoImportSourceHandling.allCases
                        ) {
                            Text($0.name).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                    .accessibilityIdentifier(
                        "Auto Import source handling"
                    )
                }
                Text(draft.sourceHandling.detail)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.textSecondary
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Divider()

                HStack {
                    Text("Organize")
                    Spacer()
                    Picker(
                        "Folder organization",
                        selection: $draft.folderOrganization
                    ) {
                        ForEach(
                            PhotoImportFolderOrganization.allCases
                        ) {
                            Text($0.name).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityIdentifier(
                        "Auto Import organization"
                    )
                }
                Text(draft.folderOrganization.detail)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

                if draft.folderOrganization
                    == .customTemplate {
                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                        TextField(
                            "Folder template",
                            text: $draft.customFolderTemplate
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(
                            "Auto Import folder template"
                        )
                        Menu("Insert Token") {
                            ForEach(
                                PhotoImportTemplateRenderer
                                    .folderTokenExamples,
                                id: \.self
                            ) { token in
                                Button(token) {
                                    draft.customFolderTemplate
                                        .append(token)
                                }
                            }
                        }
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

                Divider()

                HStack {
                    Text("File naming")
                    Spacer()
                    Picker(
                        "File naming",
                        selection: $draft.fileNaming
                    ) {
                        ForEach(PhotoImportFileNaming.allCases) {
                            Text($0.name).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityIdentifier(
                        "Auto Import file naming"
                    )
                }

                if draft.fileNaming == .customSequence {
                    TextField(
                        "Filename prefix",
                        text: $draft.customFilenamePrefix
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(
                        "Auto Import filename prefix"
                    )
                    Text(filenameExample)
                        .font(RAWDeskTokens.Typography.numeric)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }

                if draft.fileNaming == .tokenTemplate {
                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                        TextField(
                            "Filename template",
                            text: $draft.customFilenameTemplate
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(
                            "Auto Import filename template"
                        )
                        Menu("Insert Token") {
                            ForEach(
                                PhotoImportTemplateRenderer
                                    .filenameTokenExamples,
                                id: \.self
                            ) { token in
                                Button(token) {
                                    draft.customFilenameTemplate
                                        .append(token)
                                }
                            }
                        }
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

                if draft.usesSequence {
                    HStack {
                        Text("Sequence starts at")
                        Spacer()
                        Stepper(
                            "\(draft.sequenceStart)",
                            value: $draft.sequenceStart,
                            in: 1...999_999
                        )
                        .frame(width: 124)
                        .accessibilityIdentifier(
                            "Auto Import sequence start"
                        )
                    }
                }

                if let templateValidation {
                    Label(
                        templateValidation,
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                    .accessibilityIdentifier(
                        "Auto Import template error"
                    )
                }

                Divider()

                HStack {
                    Text("Wait for completed writes")
                    Spacer()
                    Stepper(
                        "\(draft.settleInterval, specifier: "%.1f") s",
                        value: $draft.settleInterval,
                        in: 0.5...30,
                        step: 0.5
                    )
                    .frame(width: 130)
                    .accessibilityIdentifier(
                        "Auto Import settling time"
                    )
                }
                Text(
                    "The photo and sibling XMP must remain unchanged for this long before hashing begins."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
    }

    private var informationSection: some View {
        AutoImportPanelSection(
            title: "Apply During Import",
            systemImage: "tag"
        ) {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
                HStack {
                    Text("Develop preset")
                    Spacer()
                    Picker(
                        "Develop preset",
                        selection: $draft.developmentPreset
                    ) {
                        Text("None")
                            .tag(nil as DevelopmentPreset?)
                        ForEach(DevelopmentPreset.allCases) {
                            Text($0.name)
                                .tag($0 as DevelopmentPreset?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityIdentifier(
                        "Auto Import develop preset"
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text("Keywords")
                    TextField(
                        "Studio, Tethered, Client > Project",
                        text: $keywordsText
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(
                        "Auto Import keywords"
                    )
                    Text(
                        "Separate keywords with commas. Hierarchies can use > or |."
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
            }
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Label(
                draft.sourceHandling == .keepSource
                    ? "Verified copy — source retained"
                    : "Verified copy, register, then Trash",
                systemImage:
                    draft.sourceHandling == .keepSource
                        ? "doc.on.doc.fill"
                        : "trash.slash.fill"
            )
            .font(RAWDeskTokens.Typography.sectionHeader)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.success
            )
            Text(
                draft.sourceHandling == .keepSource
                    ? "RAWDesk waits for stable bytes, calculates the complete SHA-256, copies the photo and XMP, verifies the destination, and commits the catalog record. The watched-folder source remains in place."
                    : "RAWDesk waits for stable bytes, calculates the complete SHA-256, copies the photo and XMP, verifies the destination, commits the catalog record, and only then moves the verified source to the macOS Trash. Trash failures retain the source and destination and appear as a warning."
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RAWDeskTokens.Spacing.medium)
        .background(
            RAWDeskTokens.ColorToken.success
                .opacity(0.08),
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
        )
    }

    private var footer: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            if let message = displayedValidation {
                Label(
                    message,
                    systemImage: "exclamationmark.triangle"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                .lineLimit(2)
            } else {
                Label(
                    draft.enabled
                        ? "Ready to watch"
                        : "Settings can be saved while off",
                    systemImage:
                        draft.enabled
                            ? "checkmark.circle"
                            : "pause.circle"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(draft.enabled ? "Save & Enable" : "Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                templateValidation != nil
                    || (
                        draft.enabled
                            && readinessValidation != nil
                    )
            )
            .accessibilityIdentifier(
                draft.enabled
                    ? "Save and enable Auto Import"
                    : "Save Auto Import settings"
            )
        }
        .padding(RAWDeskTokens.Spacing.large)
    }

    @ViewBuilder
    private func folderRow(
        title: String,
        detail: String,
        url: URL?,
        buttonTitle: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: RAWDeskTokens.Spacing.medium) {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text(title)
                    .font(RAWDeskTokens.Typography.control)
                Text(url?.path ?? "Not selected")
                    .font(RAWDeskTokens.Typography.control)
                    .foregroundStyle(
                        url == nil
                            ? RAWDeskTokens.ColorToken
                                .textSecondary
                            : RAWDeskTokens.ColorToken
                                .textPrimary
                    )
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(detail)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
            Spacer()
            Button(buttonTitle, action: action)
                .accessibilityIdentifier(
                    accessibilityIdentifier
                )
        }
    }

    private var readinessValidation: String? {
        var settings = draft
        settings.keywords = parsedKeywords
        return settings.normalized.validationMessage(
            requiringComplete: true
        )
    }

    private var displayedValidation: String? {
        saveError
            ?? templateValidation
            ?? (draft.enabled ? readinessValidation : nil)
    }

    private var templateValidation: String? {
        draft.templateValidationMessage
    }

    private var parsedKeywords: [String] {
        keywordsText
            .split(separator: ",", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private var filenameExample: String {
        let prefix =
            PhotoImportRequest.normalizedFilenamePrefix(
                draft.customFilenamePrefix
            )
        return "\(prefix)-\(String(format: "%04d", draft.sequenceStart)).ext"
    }

    private var templateExampleContext:
        PhotoImportTemplateContext {
        PhotoImportTemplateContext(
            sourceURL: URL(
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
            sequence: draft.sequenceStart
        )
    }

    private var customFolderTemplateExample: String? {
        try? PhotoImportTemplateRenderer
            .renderFolderComponents(
                draft.customFolderTemplate,
                context: templateExampleContext
            )
            .joined(separator: "/")
    }

    private var customFilenameTemplateExample: String? {
        guard let base = try?
                PhotoImportTemplateRenderer
                    .renderFilenameBase(
                        draft.customFilenameTemplate,
                        context: templateExampleContext
                    ) else {
            return nil
        }
        return "\(base).ext"
    }

    private func save() {
        var settings = draft
        settings.keywords = parsedKeywords
        if let error = library.saveAutoImportSettings(settings) {
            saveError = error
            return
        }
        dismiss()
    }

    private func chooseFolder(
        title: String,
        prompt: String,
        assignment: (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            assignment(url.standardizedFileURL)
            saveError = nil
        }
    }
}

private struct AutoImportPanelSection<Content: View>:
    View {
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
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
            Label(title, systemImage: systemImage)
                .font(RAWDeskTokens.Typography.workspaceHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RAWDeskTokens.Spacing.large)
        .background(
            RAWDeskTokens.ColorToken.panel,
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.modal)
        )
    }
}
