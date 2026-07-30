import SwiftUI

struct ColorLabelSetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryViewModel

    @State private var selectedID: PhotoColorLabelSet.ID
    @State private var draft: PhotoColorLabelSet
    @State private var validationMessage: String?
    @State private var showingDeleteConfirmation = false

    init(library: LibraryViewModel) {
        self.library = library
        let active = library.activeColorLabelSet
        _selectedID = State(initialValue: active.id)
        _draft = State(initialValue: active)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                presetList
                Divider()
                editor
            }
            Divider()
            actions
        }
        .frame(width: 650, height: 470)
        .accessibilityIdentifier("Color Label Set editor")
        .confirmationDialog(
            "Delete “\(draft.name)”?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Preset", role: .destructive) {
                deleteSelectedPreset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Photos keep their assigned colors and metadata names. Only this reusable preset is removed."
            )
        }
    }

    private var header: some View {
        HStack(spacing: RAWDeskTokens.Spacing.medium) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.selection
                )
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Color Label Sets")
                    .font(RAWDeskTokens.Typography.modalTitle)
                Text(
                    "Name the five colors for your workflow and XMP metadata."
                )
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            Spacer()
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
    }

    private var presetList: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Text("PRESETS")
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .padding(.horizontal, RAWDeskTokens.Spacing.medium)
                .padding(.top, RAWDeskTokens.Spacing.medium)

            ScrollView {
                LazyVStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    ForEach(library.colorLabelSets) { set in
                        Button {
                            select(set)
                        } label: {
                            HStack(spacing: RAWDeskTokens.Spacing.small) {
                                Image(
                                    systemName:
                                        library.activeColorLabelSetID
                                            == set.id
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    library.activeColorLabelSetID == set.id
                                        ? RAWDeskTokens.ColorToken.selection
                                        : RAWDeskTokens.ColorToken.textSecondary
                                )
                                Text(set.name)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, RAWDeskTokens.Spacing.small)
                            .padding(.vertical, RAWDeskTokens.Spacing.small)
                            .background(
                                selectedID == set.id
                                    ? RAWDeskTokens.ColorToken.selection.opacity(0.13)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedID == set.id ? .isSelected : []
                        )
                    }
                }
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
            }

            HStack(spacing: RAWDeskTokens.Spacing.medium) {
                Menu {
                    Button("New Empty Preset") {
                        createPreset(copying: .standard)
                    }
                    Button("Duplicate Selected Preset") {
                        createPreset(copying: draft)
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .rawIconButtonTarget()
                .help("Create a color-label preset")
                .accessibilityLabel(
                    "Create a color-label preset"
                )

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .rawIconButtonTarget()
                .disabled(library.colorLabelSets.count <= 1)
                .help("Delete the selected preset")
                .accessibilityLabel(
                    "Delete the selected color-label preset"
                )

                Spacer()
            }
            .padding(.horizontal, RAWDeskTokens.Spacing.medium)
            .padding(.bottom, RAWDeskTokens.Spacing.medium)
        }
        .frame(width: 205)
        .background(RAWDeskTokens.ColorToken.panel)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text("Preset name")
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    TextField("Preset name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(
                            "Color label preset name"
                        )
                }

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
                    Text("Labels")
                        .font(RAWDeskTokens.Typography.workspaceHeader)
                    ForEach(
                        Array(PhotoColorLabel.allCases.dropFirst())
                    ) { label in
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            ColorLabelSwatch(
                                label: label,
                                size: 16
                            )
                            Text(label.name)
                                .font(RAWDeskTokens.Typography.control)
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                .frame(width: 54, alignment: .leading)
                            TextField(
                                "\(label.name) label",
                                text: Binding(
                                    get: { draft[label] },
                                    set: {
                                        draft[label] = $0
                                        validationMessage = nil
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(
                                "\(label.name) color label name"
                            )
                        }
                    }
                }

                Label(
                    "The chosen name is captured when you assign a color and is written to xmp:Label. Renaming a preset does not silently rewrite existing photos or sidecars.",
                    systemImage: "info.circle"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                if let validationMessage {
                    Label(
                        validationMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .destructive
                    )
                    .accessibilityIdentifier(
                        "Color label set validation error"
                    )
                }
            }
            .padding(RAWDeskTokens.Spacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack {
            Text(
                library.activeColorLabelSetID == selectedID
                    ? "Currently in use"
                    : "Preset is not active"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save Changes") {
                save(makeActive: false)
            }

            Button("Save & Use") {
                if save(makeActive: true) {
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .keyboardShortcut(.defaultAction)
        }
        .padding(RAWDeskTokens.Spacing.medium)
    }

    private func select(_ set: PhotoColorLabelSet) {
        selectedID = set.id
        draft = set
        validationMessage = nil
    }

    @discardableResult
    private func save(makeActive: Bool) -> Bool {
        draft = draft.normalized
        if let message = library.saveColorLabelSet(
            draft,
            makeActive: makeActive
        ) {
            validationMessage = message
            return false
        }
        selectedID = draft.id
        validationMessage = nil
        return true
    }

    private func createPreset(copying source: PhotoColorLabelSet) {
        var copy = source
        copy.id = UUID()
        copy.name = uniquePresetName(
            source.id == PhotoColorLabelSet.standardID
                ? "Custom"
                : "\(source.name) Copy"
        )
        if library.saveColorLabelSet(copy, makeActive: false) == nil {
            select(copy)
        }
    }

    private func deleteSelectedPreset() {
        guard library.deleteColorLabelSet(selectedID) == nil else {
            validationMessage = "The preset could not be deleted."
            return
        }
        select(library.activeColorLabelSet)
    }

    private func uniquePresetName(_ base: String) -> String {
        let existing = Set(
            library.colorLabelSets.map {
                PhotoColorLabelSet.comparisonKey($0.name)
            }
        )
        if !existing.contains(
            PhotoColorLabelSet.comparisonKey(base)
        ) {
            return base
        }
        for suffix in 2...999 {
            let candidate = "\(base) \(suffix)"
            if !existing.contains(
                PhotoColorLabelSet.comparisonKey(candidate)
            ) {
                return candidate
            }
        }
        return "\(base) \(UUID().uuidString.prefix(6))"
    }
}
