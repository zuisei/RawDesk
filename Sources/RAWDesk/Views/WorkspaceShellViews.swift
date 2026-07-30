import SwiftUI
import AppKit

enum WelcomeDropPlan: Equatable {
    case openFolder(URL)
    case presentImport([URL])
}

enum WelcomeDropActionPlanner {
    static func plan(
        urls: [URL],
        optionHeld: Bool,
        isDirectory: (URL) -> Bool = {
            let values = try? $0.resourceValues(
                forKeys: [.isDirectoryKey]
            )
            return values?.isDirectory
                ?? $0.hasDirectoryPath
        }
    ) -> WelcomeDropPlan? {
        guard let first = urls.first else { return nil }
        if optionHeld {
            return .presentImport(urls)
        }
        return .openFolder(
            isDirectory(first)
                ? first
                : first.deletingLastPathComponent()
        )
    }
}

struct RAWWelcomeWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel

    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: RAWDeskTokens.Spacing.xLarge) {
                    Spacer(minLength: max(32, proxy.size.height * 0.08))

                    VStack(spacing: RAWDeskTokens.Spacing.small) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityHidden(true)
                        Text("RAWDesk")
                            .font(
                                RAWDeskTokens.Typography.modalTitle
                            )
                        Text(
                            "Organize and develop photos on this Mac — locally and non-destructively."
                        )
                        .font(RAWDeskTokens.Typography.control)
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken.textSecondary
                        )
                        .multilineTextAlignment(.center)
                    }

                    dropZone
                        .frame(maxWidth: 620)

                    HStack(
                        alignment: .top,
                        spacing: RAWDeskTokens.Spacing.large
                    ) {
                        welcomeAction(
                            title: "Open Photo Folder",
                            detail:
                                "Reference photos where they are. Nothing is copied or deleted.",
                            systemImage: "folder",
                            primary: true,
                            action: library.openFolderPicker
                        )
                        welcomeAction(
                            title: "Import Photos…",
                            detail:
                                "Review files, then safely add, copy, or move them into your library.",
                            systemImage: "tray.and.arrow.down",
                            primary: false,
                            action: {
                                library.presentImport()
                            }
                        )
                    }
                    .frame(maxWidth: 720)

                    if !library.recentFolders.isEmpty {
                        recentFolders
                            .frame(maxWidth: 720)
                    }

                    Label(
                        "Original image files are never changed by editing in RAWDesk.",
                        systemImage: "lock.shield"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.textSecondary
                    )
                    .accessibilityLabel(
                        "Original image files are never changed by editing in RAWDesk"
                    )

                    Spacer(minLength: 32)
                }
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height
                )
                .padding(.horizontal, RAWDeskTokens.Spacing.xLarge)
            }
        }
        .background(RAWDeskTokens.ColorToken.canvas)
        .accessibilityIdentifier("Welcome workspace")
    }

    private var dropZone: some View {
        VStack(spacing: RAWDeskTokens.Spacing.small) {
            Image(
                systemName:
                    isDropTargeted
                    ? "arrow.down.circle.fill"
                    : "arrow.down.circle"
            )
            .font(.system(size: 24))
            .foregroundStyle(
                isDropTargeted
                    ? RAWDeskTokens.ColorToken.selection
                    : RAWDeskTokens.ColorToken.textSecondary
            )
            Text("Drop photos or a folder here")
                .font(RAWDeskTokens.Typography.workspaceHeader)
            Text(
                "Dropped items are opened in place. Hold Option while dropping to review them in Import."
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )
            .multilineTextAlignment(.center)
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(
            isDropTargeted
                ? RAWDeskTokens.ColorToken.selection.opacity(0.12)
                : RAWDeskTokens.ColorToken.panel,
            in: RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.group
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.group
            )
            .strokeBorder(
                isDropTargeted
                    ? RAWDeskTokens.ColorToken.selection
                    : RAWDeskTokens.ColorToken.textSecondary
                        .opacity(0.45),
                style: StrokeStyle(
                    lineWidth: isDropTargeted ? 2 : 1,
                    dash: [7, 5]
                )
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            let modifiers =
                NSEvent.modifierFlags.intersection(
                    .deviceIndependentFlagsMask
                )
            guard let plan =
                WelcomeDropActionPlanner.plan(
                    urls: urls,
                    optionHeld:
                        modifiers.contains(.option)
                ) else {
                return false
            }
            switch plan {
            case let .presentImport(droppedURLs):
                library.presentImport(
                    sourceURLs: droppedURLs
                )
            case let .openFolder(folder):
                library.open(folder: folder)
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Drop photos or a folder here. Dropped items are opened in place. Hold Option while dropping to review them in Import."
        )
    }

    private var recentFolders: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Text("Recent Folders")
                .font(RAWDeskTokens.Typography.sectionHeader)
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 180, maximum: 320),
                        spacing: RAWDeskTokens.Spacing.small
                    ),
                ],
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.small
            ) {
                ForEach(
                    library.recentFolders.prefix(6),
                    id: \.self
                ) { url in
                    Button {
                        library.reopen(recent: url)
                    } label: {
                        HStack(spacing: RAWDeskTokens.Spacing.small) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(displayName(for: url))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        !FileManager.default.fileExists(
                            atPath: url.path
                        )
                    )
                    .help(url.path)
                }
            }
        }
    }

    private func welcomeAction(
        title: String,
        detail: String,
        systemImage: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            welcomeActionButton(
                title: title,
                systemImage: systemImage,
                primary: primary,
                action: action
            )
            Text(detail)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func welcomeActionButton(
        title: String,
        systemImage: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if primary {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.large)
            .frame(
                minHeight:
                    RAWDeskTokens.Size.primaryButtonHeight
            )
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(
                minHeight:
                    RAWDeskTokens.Size.primaryButtonHeight
            )
        }
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}

struct RAWLibraryWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var viewer: PhotoViewerViewModel
    @ObservedObject var compareViewer: PhotoViewerViewModel
    @ObservedObject var referenceViewer: PhotoViewerViewModel
    @Binding var displayMode: LibraryDisplayMode
    @Binding var filmstripHeight: CGFloat
    @Binding var isFilmstripVisible: Bool
    @State private var gridScrollPositionID:
        PhotoAsset.ID?

    let onCropChange: (NormalizedCrop) -> Void
    let onGuidedUprightGuidesChange:
        ([GuidedUprightGuide]) -> Void
    let onSpotRemovalChange: (SpotRemoval) -> Void
    let onBrushStrokeCommit:
        (LocalAdjustmentMask.ID, BrushStroke) -> Void
    let onObjectMaskPoint: (Double, Double) -> Void
    let onPointColorSample: (PointColorSample) -> Void
    let onMaskColorRangeSample: (PointColorSample) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if activeSpecialMode != nil {
                specialWorkspace
            } else {
                RAWLibraryControlBar(
                    library: library,
                    displayMode: $displayMode
                )
                if library.isScanning, library.assets.isEmpty {
                    loadingView
                } else if library.filtered.isEmpty {
                    filteredEmptyView
                } else {
                    regularWorkspace
                }
            }
            RAWLibraryStatusBar(
                library: library,
                showsThumbnailSize:
                    activeSpecialMode == nil
                    && displayMode == .grid
            )
        }
        .background(RAWDeskTokens.ColorToken.canvas)
        .frame(minWidth: 480)
        .accessibilityIdentifier("Library workspace")
    }

    @ViewBuilder
    private var regularWorkspace: some View {
        switch displayMode {
        case .grid:
            // The filmstrip is present in Grid as well as Loupe. Grid is the
            // surface for choosing; the filmstrip is the constant thread of
            // where you are in the shoot, and losing it when switching views
            // is what forces a trip back to Grid to navigate.
            VStack(spacing: 0) {
                ThumbnailGridView(
                    library: library,
                    scrollPositionID:
                        $gridScrollPositionID,
                    onOpenLoupe: { id in
                        if library.selectionID != id {
                            library.select(id)
                        }
                        displayMode = .loupe
                    }
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .layoutPriority(1)
                if isFilmstripVisible {
                    libraryFilmstripDivider
                    DevelopFilmstripView(library: library)
                        .frame(
                            height:
                                clampedLibraryFilmstripHeight
                        )
                }
            }
        case .loupe:
            VStack(spacing: 0) {
                imagePreview
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .frame(minHeight: 260)
                    .layoutPriority(1)
                if isFilmstripVisible {
                    libraryFilmstripDivider
                    DevelopFilmstripView(library: library)
                        .frame(
                            height:
                                clampedLibraryFilmstripHeight
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var specialWorkspace: some View {
        VStack(spacing: 0) {
            Group {
                if library.referenceState != nil {
                    PhotoReferenceWorkspaceView(
                        library: library,
                        referenceViewer: referenceViewer,
                        activeViewer: viewer,
                        onCropChange: onCropChange,
                        onGuidedUprightGuidesChange:
                            onGuidedUprightGuidesChange,
                        onSpotRemovalChange: onSpotRemovalChange,
                        onBrushStrokeCommit: onBrushStrokeCommit,
                        onObjectMaskPoint: onObjectMaskPoint,
                        onPointColorSample: onPointColorSample,
                        onMaskColorRangeSample:
                            onMaskColorRangeSample
                    )
                } else if library.surveyState != nil {
                    PhotoSurveyWorkspaceView(library: library)
                } else if library.compareState != nil {
                    PhotoCompareWorkspaceView(
                        library: library,
                        selectViewer: compareViewer,
                        candidateViewer: viewer
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .frame(minHeight: 300)
            .layoutPriority(1)

            libraryFilmstripDivider

            Group {
                if library.referenceState != nil {
                    PhotoReferenceFilmstripView(library: library)
                } else if library.surveyState != nil {
                    PhotoSurveyFilmstripView(library: library)
                } else if library.compareState != nil {
                    PhotoCompareFilmstripView(library: library)
                }
            }
            .frame(height: clampedLibraryFilmstripHeight)
        }
    }

    private var libraryFilmstripDivider: some View {
        RAWResizableDivider(
            value: $filmstripHeight,
            range: RAWDeskTokens.Size.libraryFilmstripRange,
            axis: .vertical,
            dragMultiplier: -1,
            label: "Library filmstrip height"
        )
    }

    private var clampedLibraryFilmstripHeight: CGFloat {
        min(
            RAWDeskTokens.Size.libraryFilmstripMaximum,
            max(
                RAWDeskTokens.Size.libraryFilmstripMinimum,
                filmstripHeight
            )
        )
    }

    private var imagePreview: some View {
        ImagePreviewView(
            viewer: viewer,
            asset: library.selectedAsset,
            onCropChange: onCropChange,
            onGuidedUprightGuidesChange:
                onGuidedUprightGuidesChange,
            onSpotRemovalChange: onSpotRemovalChange,
            onBrushStrokeCommit: onBrushStrokeCommit,
            onObjectMaskPoint: onObjectMaskPoint,
            onPointColorSample: onPointColorSample,
            onMaskColorRangeSample: onMaskColorRangeSample
        )
        .overlay(alignment: .top) {
            if viewer.isShowingOriginal {
                RAWStateBadge(
                    text: "Original",
                    systemImage: "eye",
                    tone: .accent
                )
                .padding(RAWDeskTokens.Spacing.small)
            }
        }
    }

    private var loadingView: some View {
        RAWEmptyState(
            title: "Loading Photos",
            indicator: .progress,
            message: "RAWDesk is reading the folder locally."
        )
    }

    private var filteredEmptyView: some View {
        RAWEmptyState(
            title:
                library.isScanning
                ? "Loading Photos"
                : "No Matching Photos",
            systemImage:
                library.isScanning
                ? "photo.badge.arrow.down"
                : "line.3.horizontal.decrease.circle",
            message:
                library.filter.isActive
                ? emptyStateClearDescription
                : "This collection does not contain any available photos."
        ) {
            if library.filter.isActive {
                Button(emptyStateClearTitle) {
                    library.filter = FilterState()
                }
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
            }
        }
    }

    private var emptyStateClearDescription: String {
        let hasSearch = !library.filter.searchText.isEmpty
        switch (
            hasSearch,
            library.filter.hasFacetFilters
        ) {
        case (true, true):
            return "Clear the active search and filters to show all available photos."
        case (true, false):
            return "Clear the active search to show all available photos."
        case (false, true):
            return "Clear the active filters to show all available photos."
        case (false, false):
            return "This collection does not contain any available photos."
        }
    }

    private var emptyStateClearTitle: String {
        let hasSearch = !library.filter.searchText.isEmpty
        switch (
            hasSearch,
            library.filter.hasFacetFilters
        ) {
        case (true, true):
            return "Clear Search and Filters"
        case (true, false):
            return "Clear Search"
        case (false, true):
            return "Clear Filters"
        case (false, false):
            return "Show All Photos"
        }
    }

    private var activeSpecialMode:
        (
            title: String,
            detail: String,
            finish: () -> Void
        )? {
        if library.compareState != nil {
            return (
                "Compare",
                "Select and Candidate",
                library.endCompare
            )
        }
        if let state = library.surveyState {
            return (
                "Survey",
                "\(state.photoIDs.count) photos",
                library.endSurvey
            )
        }
        if library.referenceState != nil {
            return (
                "Reference",
                "Edits apply to Active only",
                library.endReferenceView
            )
        }
        return nil
    }
}

struct RAWLibraryControlBar: View {
    @ObservedObject var library: LibraryViewModel
    @Binding var displayMode: LibraryDisplayMode

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                displayPicker
                sortMenu
                filterMenu
                activeFilterChip
                // Thumbnail size now lives in the status bar under the grid.
                // Here it was the first control `ViewThatFits` dropped, so it
                // disappeared into a menu at exactly the window sizes where
                // the grid is most cramped.
                Spacer(minLength: 0)
                modeButtons
                selectionSummary
            }
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                displayPicker
                sortMenu
                filterMenu
                activeFilterChip
                Menu("View Actions", systemImage: "ellipsis.circle") {
                    modeMenu
                    Divider()
                    thumbnailSizeMenu
                }
                Spacer(minLength: 0)
                selectionSummary
            }
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                displayPicker
                compactFilterMenu
                activeFilterChip
                compactActionMenu
                Spacer(minLength: 0)
                selectionSummary
            }
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .frame(height: RAWDeskTokens.Size.workspaceControlBar)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Library control bar")
    }

    private var displayPicker: some View {
        Picker("Library view", selection: $displayMode) {
            ForEach(LibraryDisplayMode.allCases) { mode in
                Label(mode.name, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 148)
        .help("Switch between Grid and Loupe")
    }

    private var sortMenu: some View {
        Menu {
            sortOptions
        } label: {
            Label(
                "Sort",
                systemImage:
                    library.sortAscending
                    ? "arrow.up"
                    : "arrow.down"
            )
        }
        .help("Sort photos by \(library.sort.name)")
    }

    @ViewBuilder
    private var sortOptions: some View {
        Picker("Sort by", selection: $library.sort) {
            ForEach(LibrarySort.allCases) { sort in
                Text(sort.name).tag(sort)
            }
        }
        Divider()
        Button {
            library.sortAscending.toggle()
        } label: {
            Label(
                library.sortAscending
                    ? "Ascending"
                    : "Descending",
                systemImage:
                    library.sortAscending
                    ? "arrow.up"
                    : "arrow.down"
            )
        }
    }

    private var filterMenu: some View {
        Menu {
            filterOptions
        } label: {
            Label(
                library.filter.hasFacetFilters
                    ? "Filtered"
                    : "Filter",
                systemImage:
                    library.filter.hasFacetFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help(
            library.filter.hasFacetFilters
                ? "Change or clear active filters"
                : "Filter visible photos"
        )
    }

    private var compactFilterMenu: some View {
        Menu {
            filterOptions
        } label: {
            Image(
                systemName:
                    library.filter.hasFacetFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .rawIconButtonTarget()
        .help(
            library.filter.hasFacetFilters
                ? "Change or clear active filters"
                : "Filter visible photos"
        )
        .accessibilityLabel(
            library.filter.hasFacetFilters
                ? "Active filters"
                : "Filter photos"
        )
    }

    @ViewBuilder
    private var filterOptions: some View {
        Picker("Filter", selection: $library.filter.primary) {
            ForEach(LibraryFilter.allCases) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        Divider()
        Menu("Minimum Rating") {
            ForEach(0...5, id: \.self) { rating in
                Button(
                    rating == 0
                        ? "Any Rating"
                        : "\(rating)+ Stars"
                ) {
                    library.filter.minimumRating = rating
                }
            }
        }
        if library.filter.hasFacetFilters {
            Divider()
            Button("Clear Filters") {
                library.filter.clearFacetFilters()
            }
        }
    }

    private var compactActionMenu: some View {
        Menu {
            Menu(
                "Sort",
                systemImage:
                    library.sortAscending
                    ? "arrow.up"
                    : "arrow.down"
            ) {
                sortOptions
            }
            Divider()
            modeMenu
            Divider()
            thumbnailSizeMenu
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .rawIconButtonTarget()
        .help(
            "Sort, thumbnail size, and photo view actions"
        )
        .accessibilityLabel("More library controls")
    }

    @ViewBuilder
    private var activeFilterChip: some View {
        if let presentation =
            LibraryActiveFilterChipPresentation(
                filter: library.filter
            ) {
            Button {
                library.filter.clearFacetFilters()
            } label: {
                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(presentation.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textPrimary
                )
                .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
                .frame(
                    maxWidth: 116,
                    minHeight: RAWDeskTokens.Size.iconTarget
                )
                .background(
                    RAWDeskTokens.ColorToken.controlElevated,
                    in: RoundedRectangle(
                        cornerRadius:
                            RAWDeskTokens.Radius.control
                    )
                )
            }
            .buttonStyle(.borderless)
            .help("Clear active library filters")
            .accessibilityLabel("Clear active filters")
            .accessibilityValue(
                presentation.accessibilityValue
            )
        }
    }

    private var modeButtons: some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            Button("Compare") {
                library.toggleCompare()
            }
            .disabled(!library.canStartCompare)
            Button("Survey") {
                library.toggleSurvey()
            }
            .disabled(!library.canStartSurvey)
            Button("Reference") {
                library.toggleReferenceView()
            }
            .disabled(!library.canStartReference)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if library.selectedIDs.count > 1 {
            RAWStateBadge(
                text: "\(library.selectedIDs.count) selected",
                systemImage: "checkmark.circle",
                tone: .accent
            )
        } else if library.selectionID != nil {
            Text("1 selected")
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
        }
    }

    @ViewBuilder
    private var modeMenu: some View {
        Button("Compare Photos") {
            library.toggleCompare()
        }
        .disabled(!library.canStartCompare)
        Button("Survey Selected Photos") {
            library.toggleSurvey()
        }
        .disabled(!library.canStartSurvey)
        Button("Open Reference View") {
            library.toggleReferenceView()
        }
        .disabled(!library.canStartReference)
    }

    private var thumbnailSizeMenu: some View {
        Menu("Thumbnail Size") {
            Button("Small") {
                library.thumbnailPixelSize = 160
            }
            Button("Medium") {
                library.thumbnailPixelSize = 256
            }
            Button("Large") {
                library.thumbnailPixelSize = 384
            }
        }
    }
}

struct LibraryActiveFilterChipPresentation:
    Equatable
{
    let title: String
    let accessibilityValue: String

    init?(filter: FilterState) {
        guard filter.hasFacetFilters else {
            return nil
        }

        if filter.activeFacetCount > 1 {
            title = "\(filter.activeFacetCount) Filters"
        } else if filter.primary != .all {
            title = filter.primary.displayName
        } else if filter.minimumRating > 0 {
            title = "\(filter.minimumRating)+ Stars"
        } else if let keyword = filter.keyword {
            title =
                "Keyword: "
                + PhotoUserState.displayKeywordPath(
                    keyword
                )
        } else if filter.colorLabels.count == 1,
                  let color = filter.colorLabels.first {
            title = color.filterName
        } else {
            title = "\(filter.colorLabels.count) Colors"
        }
        accessibilityValue = title
    }
}

struct RAWLibraryStatusBar: View {
    @ObservedObject var library: LibraryViewModel
    /// Thumbnail size only means something while the grid is on screen.
    var showsThumbnailSize = false

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Text(
                "\(library.filtered.count) "
                    + (library.filtered.count == 1 ? "photo" : "photos")
            )
            if library.filter.isActive {
                RAWStateBadge(
                    text: "Filter applied",
                    systemImage: "line.3.horizontal.decrease",
                    tone: .neutral
                )
            }
            Spacer(minLength: 0)
            if showsThumbnailSize {
                thumbnailSizeControl
            }
            if library.selectedIDs.count > 1 {
                Text("\(library.selectedIDs.count) selected")
            } else if library.selectionID != nil {
                Text("1 selected")
            }
        }
        .font(RAWDeskTokens.Typography.metadata)
        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        .padding(.horizontal, RAWDeskTokens.Spacing.medium)
        .frame(height: RAWDeskTokens.Size.canvasStatusBar)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
    }

    /// Grid density, kept in the status bar directly under the grid it
    /// governs, so it is always reachable rather than folded into a menu at
    /// narrow window sizes.
    private var thumbnailSizeControl: some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            Image(systemName: "square.grid.3x3")
                .imageScale(.small)
                .accessibilityHidden(true)
            Slider(
                value: $library.thumbnailPixelSize,
                in: 128...512,
                step: 32
            )
            .rawKeyboardAdjustableSlider(
                value: $library.thumbnailPixelSize,
                in: 128...512,
                step: 32
            )
            .rawSliderTarget()
            .frame(width: 88)
            .accessibilityLabel("Thumbnail size")
            .accessibilityValue(
                "\(Int(library.thumbnailPixelSize)) pixels"
            )
            // Exact pixel entry carried over from the control bar so moving
            // the control does not cost the precise input.
            TextField(
                "Thumbnail size in pixels",
                value: rawDoubleBinding(
                    $library.thumbnailPixelSize,
                    in: 128...512
                ),
                format: .number.precision(
                    .fractionLength(0)
                )
            )
            .rawNumericField(width: 46)
            .accessibilityLabel(
                "Thumbnail size in pixels"
            )
        }
        .help("Thumbnail size")
    }
}

struct RAWLibraryInspectorView: View {
    @ObservedObject var library: LibraryViewModel
    let onEditInDevelop: () -> Void

    @State private var keywordDraft = ""
    // Stacked panels, not tabs: a photographer reviewing a photo wants the
    // rating and its metadata at the same time. Open state persists, so the
    // panel a user works in stays open across launches.
    @AppStorage("rawdesk.ui.libraryInspectorKeywordsExpanded")
    private var isKeywordsExpanded = true
    @AppStorage("rawdesk.ui.libraryInspectorMetadataExpanded")
    private var isMetadataExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if let asset = library.selectedAsset {
                stackedInspector(asset)
            } else {
                RAWEmptyState(
                    title: "No Photo Selected",
                    systemImage: "photo",
                    message:
                        "Select a photo to review its information."
                )
            }
        }
        .rawPanelBackground()
        .accessibilityIdentifier("Library inspector")
    }

    private func stackedInspector(
        _ asset: PhotoAsset
    ) -> some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.large
            ) {
                identityHeader(asset)

                // Always visible: culling is the reason this panel exists.
                RAWReviewControls(
                    library: library,
                    asset: asset
                )

                // Option-click a header for solo mode, the same gesture the
                // Develop inspector already uses.
                RAWInspectorSection(
                    title: "Keywording",
                    isExpanded: $isKeywordsExpanded,
                    onSolo: {
                        isKeywordsExpanded = true
                        isMetadataExpanded = false
                    }
                ) {
                    keywording(asset)
                }

                RAWInspectorSection(
                    title: "Metadata",
                    isExpanded: $isMetadataExpanded,
                    onSolo: {
                        isMetadataExpanded = true
                        isKeywordsExpanded = false
                    }
                ) {
                    MetadataInspectorView(
                        library: library,
                        asset: asset,
                        showsReviewControls: false,
                        isEmbedded: true
                    )
                }

                actions(asset)
            }
            .padding(RAWDeskTokens.Spacing.medium)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func identityHeader(
        _ asset: PhotoAsset
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.xSmall
        ) {
            Text(asset.filename)
                .font(
                    RAWDeskTokens.Typography.workspaceHeader
                )
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                RAWFormatBadge(
                    asset: asset,
                    loadState: asset.loadState
                )
                if !asset.userState.adjustments.isNeutral {
                    RAWStateBadge(
                        text: "Edited",
                        systemImage: "slider.horizontal.3",
                        tone: .accent
                    )
                }
            }
        }
    }

    private func keywording(
        _ asset: PhotoAsset
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.xSmall
        ) {
            if asset.userState.keywords.isEmpty {
                Text("No keywords")
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
            } else {
                Text(
                    asset.userState.keywords
                        .map(
                            PhotoUserState
                                .displayKeywordPath
                        )
                        .joined(separator: " \u{00B7} ")
                )
                .font(RAWDeskTokens.Typography.metadata)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                TextField(
                    "Add keyword\u{2026}",
                    text: $keywordDraft
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitKeyword(for: asset)
                }
                Button("Add") {
                    commitKeyword(for: asset)
                }
                .disabled(
                    keywordDraft
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
            .controlSize(.small)
        }
    }

    private func actions(
        _ asset: PhotoAsset
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Button {
                _ = library.toggleQuickCollection(
                    for: asset.id
                )
            } label: {
                Label(
                    library.isInQuickCollection(asset.id)
                        ? "Remove from Quick Collection"
                        : "Add to Quick Collection",
                    systemImage:
                        library.isInQuickCollection(asset.id)
                        ? "bolt.circle.fill"
                        : "bolt.circle"
                )
            }
            .buttonStyle(.bordered)

            Button(action: onEditInDevelop) {
                Label(
                    "Edit in Develop",
                    systemImage: "slider.horizontal.3"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.large)
            .frame(
                minHeight:
                    RAWDeskTokens.Size.primaryButtonHeight
            )
        }
    }


    private func commitKeyword(for asset: PhotoAsset) {
        let values = PhotoUserState.normalizedKeywords(
            keywordDraft.components(
                separatedBy: CharacterSet(
                    charactersIn: ",;\n"
                )
            )
        )
        guard !values.isEmpty else { return }
        library.addKeywords(values, for: asset.id)
        keywordDraft = ""
    }
}

struct RAWDevelopWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var viewer: PhotoViewerViewModel
    @Binding var isFilmstripVisible: Bool
    @Binding var filmstripHeight: CGFloat

    let onCropChange: (NormalizedCrop) -> Void
    let onGuidedUprightGuidesChange:
        ([GuidedUprightGuide]) -> Void
    let onSpotRemovalChange: (SpotRemoval) -> Void
    let onBrushStrokeCommit:
        (LocalAdjustmentMask.ID, BrushStroke) -> Void
    let onObjectMaskPoint: (Double, Double) -> Void
    let onPointColorSample: (PointColorSample) -> Void
    let onMaskColorRangeSample: (PointColorSample) -> Void
    let onActivateTool: (DevelopCanvasTool) -> Void
    let onFinishTool: () -> Void
    let onCancelTool: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The vertical tool rail moved into the Develop inspector, under
            // the histogram, where the tools are labelled and sit next to the
            // controls that adjust them. The image well keeps its width.
            HStack(spacing: 0) {
                canvas
            }
            if isFilmstripVisible {
                RAWResizableDivider(
                    value: $filmstripHeight,
                    range:
                        RAWDeskTokens.Size
                            .developFilmstripRange,
                    axis: .vertical,
                    dragMultiplier: -1,
                    label: "Develop filmstrip height"
                )
                DevelopFilmstripView(library: library)
                    .frame(height: clampedFilmstripHeight)
            }
        }
        .background(RAWDeskTokens.ColorToken.canvas)
        .accessibilityIdentifier("Develop workspace")
    }

    private var clampedFilmstripHeight: CGFloat {
        min(
            RAWDeskTokens.Size.developFilmstripMaximum,
            max(
                RAWDeskTokens.Size.developFilmstripMinimum,
                filmstripHeight
            )
        )
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            if let activeTool {
                RAWDevelopToolModeBar(
                    tool: activeTool,
                    viewer: viewer,
                    onDone: onFinishTool,
                    onCancel: onCancelTool
                )
            } else {
                RAWDevelopCanvasControlBar(viewer: viewer)
            }

            Group {
                if library.isScanning, library.assets.isEmpty {
                    VStack(spacing: RAWDeskTokens.Spacing.medium) {
                        ProgressView()
                        Text("Loading photos…")
                    }
                } else if library.selectedAsset == nil {
                    RAWEmptyState(
                        title: "Select a Photo",
                        systemImage: "photo",
                        message:
                            "Choose a photo in Library or the filmstrip to start developing."
                    )
                } else {
                    ImagePreviewView(
                        viewer: viewer,
                        asset: library.selectedAsset,
                        onCropChange: onCropChange,
                        onGuidedUprightGuidesChange:
                            onGuidedUprightGuidesChange,
                        onSpotRemovalChange:
                            onSpotRemovalChange,
                        onBrushStrokeCommit:
                            onBrushStrokeCommit,
                        onObjectMaskPoint:
                            onObjectMaskPoint,
                        onPointColorSample:
                            onPointColorSample,
                        onMaskColorRangeSample:
                            onMaskColorRangeSample,
                        showsInlineToolCompletion: false,
                        onCancelActiveTool: onCancelTool
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RAWDeskTokens.ColorToken.canvas)

            RAWPhotoCanvasStatusBar(
                viewer: viewer,
                asset: library.selectedAsset
            )
        }
    }

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
}

struct RAWDevelopToolModeBar: View {
    let tool: DevelopCanvasTool
    @ObservedObject var viewer: PhotoViewerViewModel
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(tool.name, systemImage: tool.systemImage)
                .font(RAWDeskTokens.Typography.workspaceHeader)
            Text(toolInstructions)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .lineLimit(1)
            Spacer(minLength: RAWDeskTokens.Spacing.small)
            if tool == .mask {
                Toggle(
                    "Show Overlay",
                    isOn: maskOverlayBinding
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(
                    "The overlay is a preview and is never included in export."
                )
            }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, RAWDeskTokens.Spacing.medium)
        .frame(height: RAWDeskTokens.Size.workspaceControlBar)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var toolInstructions: String {
        switch tool {
        case .crop:
            return "Drag the crop handles. Return finishes; Escape restores the starting crop."
        case .remove:
            return "Drag target and source circles. Changes remain non-destructive."
        case .mask:
            return "Paint the selected mask. The colored overlay is preview-only."
        case .guidedUpright:
            return "Draw guides along lines that should be vertical or horizontal."
        case .pointColor:
            return "Click a color in the photo to create a precise swatch."
        }
    }

    private var maskOverlayBinding: Binding<Bool> {
        Binding(
            get: { viewer.visualizedLocalMaskID != nil },
            set: { show in
                viewer.setLocalMaskVisualization(
                    show ? viewer.selectedLocalMaskID : nil
                )
            }
        )
    }
}

struct RAWDevelopCanvasControlBar: View {
    @ObservedObject var viewer: PhotoViewerViewModel

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Button {
                viewer.toggleOriginal()
            } label: {
                Label(
                    viewer.isShowingOriginal
                        ? "Show Edit"
                        : "Before / After",
                    systemImage:
                        viewer.isShowingOriginal
                        ? "rectangle.on.rectangle"
                        : "eye"
                )
            }
            .help("Hold or press backslash to compare with the original")

            Spacer(minLength: 0)

            if viewer.softProofSettings.isEnabled {
                RAWStateBadge(
                    text:
                        "Soft Proof: "
                        + viewer.softProofSettings.profile.shortName
                        + " · "
                        + viewer.softProofSettings
                            .renderingIntent.name,
                    systemImage: "printer",
                    tone: .accent
                )
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, RAWDeskTokens.Spacing.medium)
        .frame(height: RAWDeskTokens.Size.workspaceControlBar)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
    }

}

struct RAWPhotoCanvasStatusBar: View {
    @ObservedObject var viewer: PhotoViewerViewModel
    let asset: PhotoAsset?

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Button("Fit") {
                viewer.transform.fit()
            }
            Button("100%") {
                viewer.transform.actualSize()
            }
            if !viewer.transform.fitToWindow {
                Text(
                    "\(Int((viewer.transform.zoom * 100).rounded()))%"
                )
                .monospacedDigit()
                .frame(width: 46, alignment: .leading)
            }

            Spacer(minLength: 0)

            if viewer.isShowingOriginal {
                RAWStateBadge(
                    text: "Original",
                    systemImage: "eye",
                    tone: .accent
                )
            }
            if viewer.softProofSettings.isEnabled {
                RAWStateBadge(
                    text: "Proof",
                    systemImage: "printer",
                    tone: .accent
                )
            }

            Spacer(minLength: 0)

            if let asset {
                Text(asset.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                RAWFormatBadge(
                    asset: asset,
                    loadState: viewer.loadState,
                    rawDecodeSource:
                        viewer.rawDecodeSource
                )
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(RAWDeskTokens.Typography.metadata)
        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .frame(height: RAWDeskTokens.Size.canvasStatusBar)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
        .accessibilityIdentifier("Photo canvas status bar")
    }
}
