import SwiftUI
import AppKit

struct PhotoSyncSettingsView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: RAWDeskTokens.Spacing.medium),
        GridItem(.flexible(), spacing: RAWDeskTokens.Spacing.medium),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            selectionPresets
            settingsGrid
            Divider()
            actions
        }
        .frame(width: 520, height: 500)
        .background(RAWDeskTokens.ColorToken.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Sync edit settings")
    }

    private var header: some View {
        HStack(spacing: RAWDeskTokens.Spacing.medium) {
            Image(systemName: "slider.horizontal.2.square")
                .font(RAWDeskTokens.Typography.modalTitle)
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                .frame(width: 34, height: 34)
                .background(
                    RAWDeskTokens.ColorToken.selection.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
                )
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Synchronize Edit Settings")
                    .font(RAWDeskTokens.Typography.workspaceHeader)
                Text(
                    "\(library.selectedAsset?.filename ?? "Active photo") → \(targetDescription)"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(RAWDeskTokens.Spacing.large)
    }

    private var selectionPresets: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Text("Copy")
                .font(RAWDeskTokens.Typography.sectionHeader)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            Button("All") {
                library.selectAllSyncAdjustmentGroups()
            }
            Button("Modified") {
                library.selectModifiedSyncAdjustmentGroups()
            }
            Button("None") {
                library.selectedSyncAdjustmentGroups = []
            }
            Spacer()
            Text(
                "\(library.selectedSyncAdjustmentGroups.count) of \(PhotoAdjustmentGroup.allCases.count)"
            )
            .font(RAWDeskTokens.Typography.numeric)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
        .controlSize(.small)
        .padding(.horizontal, RAWDeskTokens.Spacing.large)
        .padding(.vertical, RAWDeskTokens.Spacing.medium)
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    private var settingsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.small
            ) {
                ForEach(PhotoAdjustmentGroup.allCases) {
                    group in
                    Toggle(
                        isOn: groupBinding(group)
                    ) {
                        Label(
                            group.name,
                            systemImage: group.systemImage
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, RAWDeskTokens.Spacing.small)
                    .padding(.vertical, RAWDeskTokens.Spacing.small)
                    .background(
                        library.selectedSyncAdjustmentGroups
                            .contains(group)
                            ? RAWDeskTokens.ColorToken.selection.opacity(0.08)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                    )
                    .accessibilityIdentifier(
                        "Sync \(group.name)"
                    )
                }
            }
            .padding(RAWDeskTokens.Spacing.large)
        }
    }

    private var actions: some View {
        HStack {
            Text(
                "Existing settings outside the checked sections are preserved."
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            .lineLimit(2)
            Spacer(minLength: 16)
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Synchronize") {
                _ = library.synchronizeSelectedAdjustments()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .keyboardShortcut(.defaultAction)
            .disabled(
                library.selectedSyncAdjustmentGroups.isEmpty
                    || !library
                        .canSynchronizeSelectedAdjustments
            )
            .accessibilityIdentifier(
                "Confirm edit synchronization"
            )
        }
        .padding(RAWDeskTokens.Spacing.large)
    }

    private var targetDescription: String {
        let count = library.adjustmentSyncTargetCount
        return "\(count) other \(count == 1 ? "photo" : "photos")"
    }

    private func groupBinding(
        _ group: PhotoAdjustmentGroup
    ) -> Binding<Bool> {
        Binding(
            get: {
                library.selectedSyncAdjustmentGroups
                    .contains(group)
            },
            set: { selected in
                var groups =
                    library.selectedSyncAdjustmentGroups
                if selected {
                    groups.insert(group)
                } else {
                    groups.remove(group)
                }
                library.selectedSyncAdjustmentGroups =
                    groups
            }
        )
    }
}
