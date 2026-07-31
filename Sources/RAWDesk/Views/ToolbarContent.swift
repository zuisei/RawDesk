import SwiftUI

struct ActiveToolbarTaskProgress: Equatable {
    let title: String
    let status: String
    let fraction: Double
    let accessibilityLabel: String

    init(
        title: String,
        status: String,
        fraction: Double,
        accessibilityLabel: String
    ) {
        self.title = title
        self.status = status
        self.fraction = min(max(fraction, 0), 1)
        self.accessibilityLabel = accessibilityLabel
    }

    var percentage: Int {
        Int((fraction * 100).rounded())
    }

    var accessibilityValue: String {
        "\(percentage) percent"
    }

    var completionText: String {
        "\(percentage)% complete"
    }
}

private struct ToolbarTaskProgressView: View {
    let progress: ActiveToolbarTaskProgress

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ProgressView(value: progress.fraction)
                .frame(width: 56)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(
            minHeight:
                RAWDeskTokens.Size.iconTarget
        )
        .help("\(progress.title): \(progress.status)")
        .accessibilityLabel(progress.accessibilityLabel)
        .accessibilityValue(progress.accessibilityValue)
        .popover(isPresented: $isPresented) {
            VStack(
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.small
            ) {
                Label(
                    progress.title,
                    systemImage: "clock.arrow.circlepath"
                )
                .font(RAWDeskTokens.Typography.sectionHeader)
                Text(progress.status)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.textSecondary
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                ProgressView(value: progress.fraction)
                Text(progress.completionText)
                .font(RAWDeskTokens.Typography.numeric)
                .monospacedDigit()
            }
            .padding(RAWDeskTokens.Spacing.medium)
            .frame(width: 280)
        }
    }
}

/// Module picker in the Lightroom idiom: plain words, the current module
/// bright and the rest dim, separated by hairlines. No pill — a filled capsule
/// reads as a button you press rather than a place you are, and it was the one
/// remaining piece of chrome competing with the photograph.
struct RAWWorkspaceSwitcher: View {
    @Binding var destination: WorkspaceDestination

    var body: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(
                    WorkspaceDestination.allCases.enumerated()
                ),
                id: \.element
            ) { index, mode in
                if index > 0 {
                    Rectangle()
                        .fill(
                            RAWDeskTokens.ColorToken.divider
                        )
                        .frame(width: 1, height: 12)
                }
                moduleButton(for: mode)
            }
        }
        // Sized to its content. Forcing the full 48pt toolbar height made the
        // group taller than the toolbar's content area, so its rounded
        // background was clipped along the bottom edge.
        .frame(
            minHeight: RAWDeskTokens.Size.iconTarget
        )
        .help(
            "Switch between Library, Develop, and Map"
        )
        .accessibilityIdentifier(
            "Workspace picker"
        )
        .accessibilityElement(children: .contain)
    }

    private func moduleButton(
        for mode: WorkspaceDestination
    ) -> some View {
        let isCurrent = destination == mode
        return Button {
            destination = mode
        } label: {
            Text(mode.name)
                .font(
                    RAWDeskTokens.Typography.control
                )
                .fontWeight(
                    isCurrent ? .semibold : .regular
                )
                .foregroundStyle(
                    isCurrent
                        ? RAWDeskTokens.ColorToken
                            .textPrimary
                        : RAWDeskTokens.ColorToken
                            .textSecondary
                )
                .padding(
                    .horizontal,
                    RAWDeskTokens.Spacing.medium
                )
                .frame(
                    minHeight:
                        RAWDeskTokens.Size.iconTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.name)
        .accessibilityAddTraits(
            isCurrent
                ? [.isButton, .isSelected]
                : [.isButton]
        )
    }
}

struct MainToolbar: ToolbarContent {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var viewer: PhotoViewerViewModel
    @Binding var photoWorkspaceMode: PhotoWorkspaceMode
    @Binding var isSidebarVisible: Bool
    @Binding var isInspectorVisible: Bool
    @Binding var isFilmstripVisible: Bool
    @Binding var arePanelsTemporarilyHidden: Bool
    let onExport: () -> Void

    private var destination:
        Binding<WorkspaceDestination> {
        Binding(
            get: {
                switch library.workspaceMode {
                case .map:
                    return .map
                case .library:
                    return photoWorkspaceMode == .develop
                        ? .develop
                        : .library
                }
            },
            set: showDestination
        )
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                isSidebarVisible.toggle()
            } label: {
                Label(
                    isSidebarVisible
                        ? "Hide Sidebar"
                        : "Show Sidebar",
                    systemImage: "sidebar.left"
                )
                .labelStyle(.iconOnly)
            }
            .help(
                isSidebarVisible
                    ? "Hide Sidebar (⌥⌘S)"
                    : "Show Sidebar (⌥⌘S)"
            )
            .accessibilityLabel(
                isSidebarVisible
                    ? "Hide sidebar"
                    : "Show sidebar"
            )
            .frame(
                minWidth:
                    RAWDeskTokens.Size.iconTarget,
                minHeight:
                    RAWDeskTokens.Size.iconTarget
            )

            Button {
                library.openFolderPicker()
            } label: {
                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    Image(systemName: "folder")
                    Text("Open")
                }
            }
            .help("Open Photo Folder (⌘O)")
            .accessibilityLabel("Open photo folder")

            Button {
                library.presentImport()
            } label: {
                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Import")
                }
            }
            .help("Import Photos (⇧⌘I)")
            .accessibilityLabel("Import photos")
        }

        ToolbarItem(placement: .principal) {
            RAWWorkspaceSwitcher(
                destination: destination
            )
        }

        ToolbarItemGroup(placement: .automatic) {
            if let progress = activeTaskProgress {
                ToolbarTaskProgressView(progress: progress)
            }

            // Soft Proofing lives in one place: the Develop inspector, just
            // below the histogram, which is where a photographer expects it.
            // It used to appear here and on the image control bar as well. The
            // S shortcut still toggles it (KeyboardHandler), and the active
            // proof profile is still reported on the control bar.

            if library.selectionID != nil {
                Button(action: onExport) {
                    HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                }
                .help("Export Selected Photo (⌘E)")
                .accessibilityLabel("Export selected photo")
            }

            // Overflow only. Module switching is the principal control a few
            // centimetres to the left, and Sidebar and Inspector are the icon
            // buttons on either side of this menu; listing them again here
            // said the same thing twice on one toolbar.
            Menu {
                photoViewActions
                Divider()
                panelActions
            } label: {
                Label(
                    "Photo and Panel Actions",
                    systemImage: "ellipsis.circle"
                )
            }
            .help("Rotate, zoom, compare, and panel visibility")
            .accessibilityLabel("Photo and panel actions")
            .frame(
                minWidth:
                    RAWDeskTokens.Size.iconTarget,
                minHeight:
                    RAWDeskTokens.Size.iconTarget
            )

            Button {
                isInspectorVisible.toggle()
            } label: {
                Label(
                    isInspectorVisible
                        ? "Hide Inspector"
                        : "Show Inspector",
                    systemImage: "sidebar.right"
                )
                .labelStyle(.iconOnly)
            }
            .help(
                isInspectorVisible
                    ? "Hide Inspector (⌥⌘I)"
                    : "Show Inspector (⌥⌘I)"
            )
            .accessibilityLabel(
                isInspectorVisible
                    ? "Hide inspector"
                    : "Show inspector"
            )
            .frame(
                minWidth:
                    RAWDeskTokens.Size.iconTarget,
                minHeight:
                    RAWDeskTokens.Size.iconTarget
            )
        }
    }

    @ViewBuilder
    private var photoViewActions: some View {
        if destination.wrappedValue == .library {
            Button(
                library.compareState == nil
                    ? "Compare Photos"
                    : "Finish Comparing"
            ) {
                library.toggleCompare()
            }
            .disabled(
                library.compareState == nil
                    && !library.canStartCompare
            )
            Button(
                library.surveyState == nil
                    ? "Survey Photos"
                    : "Finish Surveying"
            ) {
                library.toggleSurvey()
            }
            .disabled(
                library.surveyState == nil
                    && !library.canStartSurvey
            )
            Button(
                library.referenceState == nil
                    ? "Open in Reference View"
                    : "Finish Reference View"
            ) {
                library.toggleReferenceView()
            }
            .disabled(
                library.referenceState == nil
                    && !library.canStartReference
            )
            Divider()
        }

        Button("Rotate Left") {
            guard let id = library.selectionID,
                  let adjustments =
                      library.rotateLeft(for: id) else {
                return
            }
            viewer.updateAdjustments(
                adjustments,
                for: id
            )
        }
        .disabled(library.selectionID == nil)

        Button("Rotate Right") {
            guard let id = library.selectionID,
                  let adjustments =
                      library.rotateRight(for: id) else {
                return
            }
            viewer.updateAdjustments(
                adjustments,
                for: id
            )
        }
        .disabled(library.selectionID == nil)

        Button("Zoom In") {
            viewer.transform.zoomIn()
        }
        .disabled(library.selectionID == nil)
        Button("Zoom Out") {
            viewer.transform.zoomOut()
        }
        .disabled(library.selectionID == nil)
        Button("Fit to Window") {
            viewer.transform.fit()
        }
        .disabled(library.selectionID == nil)
        Button("Actual Size") {
            viewer.transform.actualSize()
        }
        .disabled(library.selectionID == nil)
    }

    /// Sidebar and Inspector are omitted: both are permanent icon buttons on
    /// this same toolbar. Only the panels without a toolbar button are here.
    @ViewBuilder
    private var panelActions: some View {
        if destination.wrappedValue == .develop {
            Button(
                isFilmstripVisible
                    ? "Hide Filmstrip"
                    : "Show Filmstrip"
            ) {
                isFilmstripVisible.toggle()
            }
        }
        Button(
            arePanelsTemporarilyHidden
                ? "Restore All Panels"
                : "Hide All Panels"
        ) {
            arePanelsTemporarilyHidden.toggle()
        }
    }

    private func showDestination(
        _ destination: WorkspaceDestination
    ) {
        switch destination {
        case .library:
            library.workspaceMode = .library
            photoWorkspaceMode = .library
        case .develop:
            library.workspaceMode = .library
            photoWorkspaceMode = .develop
        case .map:
            library.workspaceMode = .map
        }
    }

    private var activeTaskProgress:
        ActiveToolbarTaskProgress? {
        if let progress = library.importProgress {
            return ActiveToolbarTaskProgress(
                title: "Import",
                status: progress.filename.map {
                    "\(progress.phase.name): \($0)"
                } ?? progress.phase.name,
                fraction: progress.fraction ?? 0,
                accessibilityLabel: "Import progress"
            )
        }
        if let progress =
            library.autoImportProgress {
            return ActiveToolbarTaskProgress(
                title: "Auto Import",
                status: progress.filename.map {
                    "Auto Import: \($0)"
                } ?? "Auto Import",
                fraction: progress.fraction ?? 0,
                accessibilityLabel: "Auto Import progress"
            )
        }
        if let progress =
            library.cullingScanProgress {
            return ActiveToolbarTaskProgress(
                title: "Assisted Culling",
                status: progress.filename.map {
                    "Assisted Culling: \($0)"
                } ?? "Assisted Culling",
                fraction: progress.fractionCompleted,
                accessibilityLabel: "Assisted Culling progress"
            )
        }
        if let progress =
            library.duplicateScanProgress {
            return ActiveToolbarTaskProgress(
                title: "Duplicate Analysis",
                status: progress.filename.map {
                    "Duplicate analysis: \($0)"
                } ?? "Duplicate analysis",
                fraction: progress.fractionCompleted,
                accessibilityLabel: "Duplicate analysis progress"
            )
        }
        return nil
    }
}
