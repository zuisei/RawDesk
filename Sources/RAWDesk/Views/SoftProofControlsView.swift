import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SoftProofControlsView: View {
    @ObservedObject var viewer:
        PhotoViewerViewModel
    let onSaveProofVersion: () -> Void

    @State private var isShowingProfiles =
        false

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Label(
                    "Soft Proofing",
                    systemImage: "printer"
                )
                .font(RAWDeskTokens.Typography.sectionHeader)
                Spacer()
                Toggle(
                    isOn: Binding(
                        get: {
                            viewer.softProofSettings
                                .isEnabled
                        },
                        set:
                            viewer
                                .setSoftProofEnabled
                    )
                ) {
                    Text("Soft Proofing")
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityIdentifier(
                    "Toggle soft proofing"
                )
            }

            if viewer.softProofSettings.isEnabled {
                Divider()

                LabeledContent("Profile") {
                    Button {
                        isShowingProfiles = true
                    } label: {
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Image(
                                systemName:
                                    viewer
                                        .softProofSettings
                                        .profile
                                        .systemImage
                            )
                            Text(
                                viewer
                                    .softProofSettings
                                    .profile.name
                            )
                            .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(
                                systemName:
                                    "chevron.up.chevron.down"
                            )
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }
                        .frame(
                            maxWidth: 205,
                            alignment: .leading
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(
                        isPresented:
                            $isShowingProfiles,
                        arrowEdge: .trailing
                    ) {
                        SoftProofProfileBrowser(
                            selected:
                                viewer
                                    .softProofSettings
                                    .profile,
                            onSelect:
                                viewer
                                    .setSoftProofProfile
                        )
                    }
                    .accessibilityLabel(
                        Text("Browse proof profiles")
                    )
                    .accessibilityValue(
                        Text(
                            viewer
                                .softProofSettings
                                .profile.name
                        )
                    )
                }

                Text(
                    viewer.softProofSettings
                        .profile.summary
                )
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )

                Picker(
                    "Rendering intent",
                    selection: Binding(
                        get: {
                            viewer.softProofSettings
                                .renderingIntent
                        },
                        set:
                            viewer
                                .setSoftProofRenderingIntent
                    )
                ) {
                    ForEach(
                        SoftProofRenderingIntent.allCases
                    ) { intent in
                        Text(intent.name)
                            .tag(intent)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(
                    "Perceptual preserves color relationships; Relative preserves more in-gamut colors"
                )

                if let monitorName =
                    viewer.softProofMonitorName {
                    Label(
                        "Monitor: \(monitorName)",
                        systemImage: "display"
                    )
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .lineLimit(1)
                }

                Toggle(
                    isOn: Binding(
                        get: {
                            viewer.softProofSettings
                                .showDestinationGamutWarning
                        },
                        set:
                            viewer
                                .setSoftProofGamutWarning
                    )
                ) {
                    Label(
                        "Destination Gamut Warning",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                if viewer.softProofSettings
                    .showDestinationGamutWarning {
                    warningStatus(
                        color: .red,
                        fraction:
                            viewer
                                .softProofDestinationGamutFraction,
                        emptyText:
                            "No destination warning result"
                    )
                }

                Toggle(
                    isOn: Binding(
                        get: {
                            viewer.softProofSettings
                                .showMonitorGamutWarning
                        },
                        set:
                            viewer
                                .setSoftProofMonitorGamutWarning
                    )
                ) {
                    Label(
                        "Monitor Gamut Warning",
                        systemImage: "display.trianglebadge.exclamationmark"
                    )
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                if viewer.softProofSettings
                    .showMonitorGamutWarning {
                    warningStatus(
                        color: .blue,
                        fraction:
                            viewer
                                .softProofMonitorGamutFraction,
                        emptyText:
                            "No monitor warning result"
                    )
                }

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text("Gamut Warning Legend")
                        .font(
                            RAWDeskTokens.Typography
                                .sectionHeader
                        )
                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                        warningLegend(
                            color: .red,
                            text: "Red · Output"
                        )
                        warningLegend(
                            color: .blue,
                            text: "Blue · Monitor"
                        )
                        warningLegend(
                            color: .purple,
                            text: "Purple · Both"
                        )
                    }
                    Text(
                        "Warning overlays are preview-only and are never included in export."
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .metadata
                    )
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Toggle(
                    isOn: Binding(
                        get: {
                            viewer.softProofSettings
                                .simulatePaperAndInk
                        },
                        set:
                            viewer
                                .setSoftProofPaperAndInk
                    )
                ) {
                    Label(
                        "Simulate Paper & Ink",
                        systemImage: "doc.text"
                    )
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(
                    !viewer.softProofSettings
                        .profile.supportsPaperAndInk
                )
                .help(
                    viewer.softProofSettings
                        .profile.supportsPaperAndInk
                        ? "Use the profile media white and black behavior"
                        : "Available for output profiles"
                )

                if let error =
                    viewer.softProofErrorMessage {
                    Label(
                        error,
                        systemImage:
                            "exclamationmark.octagon.fill"
                    )
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .destructive
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .accessibilityIdentifier(
                        "Soft proofing error"
                    )
                }

                Button {
                    onSaveProofVersion()
                } label: {
                    Label(
                        "Create Proof Version",
                        systemImage:
                            "plus.square.on.square"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
                .controlSize(.small)
                .disabled(
                    viewer.softProofErrorMessage != nil
                )
                .help(
                    "Save adjustments, ICC profile, intent, and warning settings as a named proof version"
                )
            }
        }
        .padding(RAWDeskTokens.Spacing.small)
        .background(
            viewer.softProofSettings.isEnabled
                ? RAWDeskTokens.ColorToken.selection.opacity(0.10)
                : RAWDeskTokens.ColorToken.textSecondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
                .strokeBorder(
                    viewer.softProofSettings.isEnabled
                        ? RAWDeskTokens.ColorToken.selection
                            .opacity(0.30)
                        : Color.clear,
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "Soft proofing controls"
        )
    }

    @ViewBuilder
    private func warningStatus(
        color: Color,
        fraction: Double?,
        emptyText: String
    ) -> some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            if viewer.isSoftProofRendering {
                Text("Calculating affected colors…")
            } else if let fraction {
                Text(
                    "\(percentage(fraction)) of preview pixels exceed the proof tolerance"
                )
            } else {
                Text(emptyText)
            }
        }
        .font(RAWDeskTokens.Typography.badge)
        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
    }

    @ViewBuilder
    private func warningLegend(
        color: Color,
        text: String
    ) -> some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
        }
    }

    private func percentage(
        _ fraction: Double
    ) -> String {
        String(
            format: fraction < 0.001
                ? "%.2f%%"
                : "%.1f%%",
            fraction * 100
        )
    }
}

private struct SoftProofProfileBrowser: View {
    let selected: SoftProofProfile
    let onSelect: (SoftProofProfile) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State private var search = ""
    @State private var installed:
        [SoftProofProfile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filteredInstalled:
        [SoftProofProfile]
    {
        let builtInNames = Set(
            SoftProofProfile.builtIns.map {
                $0.name.lowercased()
            }
        )
        return installed.filter { profile in
            !builtInNames.contains(
                profile.name.lowercased()
            )
            && (
                search.isEmpty
                || profile.name.localizedCaseInsensitiveContains(
                    search
                )
                || profile.summary.localizedCaseInsensitiveContains(
                    search
                )
            )
        }
    }

    private var installedRGB:
        [SoftProofProfile]
    {
        filteredInstalled.filter {
            $0.colorModel == .rgb
        }
    }

    private var installedCMYK:
        [SoftProofProfile]
    {
        filteredInstalled.filter {
            $0.colorModel == .cmyk
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text("Proof Profiles")
                        .font(
                            RAWDeskTokens.Typography
                                .workspaceHeader
                        )
                    Text(
                        "\(installed.count) installed ICC profiles"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(
                        systemName:
                            "xmark.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .rawIconButtonTarget()
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .help("Close profile browser")
                .accessibilityLabel(
                    Text("Close profile browser")
                )
            }
            .padding(RAWDeskTokens.Spacing.medium)

            TextField(
                "Search profiles",
                text: $search
            )
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, RAWDeskTokens.Spacing.medium)
            .padding(.bottom, RAWDeskTokens.Spacing.small)
            .accessibilityIdentifier(
                "Search proof profiles"
            )

            Divider()

            List {
                Section("Built-In") {
                    ForEach(
                        SoftProofProfile.builtIns
                    ) { profile in
                        profileButton(profile)
                    }
                }

                if isLoading {
                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            "Reading ColorSync profiles…"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }
                } else {
                    if !installedCMYK.isEmpty {
                        Section("Output / CMYK") {
                            ForEach(
                                installedCMYK
                            ) { profile in
                                profileButton(profile)
                            }
                        }
                    }
                    if !installedRGB.isEmpty {
                        Section("RGB") {
                            ForEach(
                                installedRGB
                            ) { profile in
                                profileButton(profile)
                            }
                        }
                    }
                    if filteredInstalled.isEmpty,
                       !search.isEmpty {
                        RAWEmptyState(
                            title: "No Matching Profiles",
                            systemImage:
                                "magnifyingglass",
                            message:
                                "Try another profile name or color model.",
                            layout: .compact
                        )
                    }
                }
            }
            .listStyle(.inset)
            .rawPanelScrollBackground()

            Divider()

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                if let errorMessage {
                    Label(
                        errorMessage,
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .destructive
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Button {
                    chooseICCProfile()
                } label: {
                    Label(
                        "Add ICC Profile…",
                        systemImage: "plus"
                    )
                }
                .disabled(isLoading)
                .accessibilityIdentifier(
                    "Add ICC profile"
                )
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(RAWDeskTokens.Spacing.medium)
        }
        .frame(width: 430, height: 500)
        .task {
            let profiles = await Task.detached(
                priority: .utility
            ) {
                SoftProofProfileCatalog
                    .installedProfiles()
            }.value
            installed = profiles
            isLoading = false
        }
    }

    @ViewBuilder
    private func profileButton(
        _ profile: SoftProofProfile
    ) -> some View {
        Button {
            selectProfile(profile)
        } label: {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Image(
                    systemName:
                        profile.systemImage
                )
                .frame(width: 16)
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(profile.name)
                        .lineLimit(1)
                    Text(profile.summary)
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
                Spacer()
                if selected.id == profile.id {
                    Image(
                        systemName:
                            "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.selection
                    )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            selected.id == profile.id
                ? Text("Selected")
                : Text("")
        )
        .accessibilityHint(
            Text(
                "Use \(profile.name) for soft proofing"
            )
        )
        .accessibilityRepresentation {
            Button {
                selectProfile(profile)
            } label: {
                Label(
                    profile.name,
                    systemImage:
                        profile.systemImage
                )
            }
            .accessibilityValue(
                selected.id == profile.id
                    ? Text(
                        "\(profile.summary), selected"
                    )
                    : Text(profile.summary)
            )
            .accessibilityHint(
                Text(
                    "Use \(profile.name) for soft proofing"
                )
            )
            .accessibilityIdentifier(
                "Select proof profile \(profile.id)"
            )
        }
    }

    private func selectProfile(
        _ profile: SoftProofProfile
    ) {
        onSelect(profile)
        dismiss()
    }

    private func chooseICCProfile() {
        let panel = NSOpenPanel()
        panel.title = "Add Proof Profile"
        panel.message =
            "Choose an RGB or CMYK ICC profile. RAWDesk keeps a private copy for named Proof Versions."
        panel.prompt = "Add Profile"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(
                filenameExtension: "icc"
            ),
            UTType(
                filenameExtension: "icm"
            ),
        ].compactMap { $0 }
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url else {
                return
            }
            Task {
                do {
                    let profile =
                        try await Task.detached(
                            priority: .userInitiated
                        ) {
                            try SoftProofProfileCatalog
                                .importProfile(
                                    at: url
                                )
                        }.value
                    if !installed.contains(
                        where: {
                            $0.id == profile.id
                        }
                    ) {
                        installed.append(profile)
                        installed.sort {
                            $0.name
                                .localizedStandardCompare(
                                    $1.name
                                ) == .orderedAscending
                        }
                    }
                    errorMessage = nil
                    onSelect(profile)
                    dismiss()
                } catch {
                    errorMessage =
                        error.localizedDescription
                }
            }
        }
    }
}
