import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @StateObject private var library = LibraryViewModel()
    @StateObject private var viewer = PhotoViewerViewModel()
    @StateObject private var compareViewer =
        PhotoViewerViewModel()
    @StateObject private var referenceViewer =
        PhotoViewerViewModel()
    @StateObject private var people = PeopleViewModel()
    @State private var photoWorkspaceMode:
        PhotoWorkspaceMode = .library
    @AppStorage("rawdesk.ui.libraryDisplayMode")
    private var libraryDisplayModeRaw =
        LibraryDisplayMode.grid.rawValue
    @AppStorage("rawdesk.ui.librarySidebarVisible")
    private var isLibrarySidebarVisible = true
    @AppStorage("rawdesk.ui.librarySidebarWidth")
    private var librarySidebarWidth =
        Double(RAWDeskTokens.Size.leftSidebar)
    @AppStorage("rawdesk.ui.libraryInspectorVisible")
    private var isLibraryInspectorVisible = true
    @AppStorage("rawdesk.ui.libraryInspectorWidth")
    private var libraryInspectorWidth =
        Double(RAWDeskTokens.Size.rightInspector)
    @AppStorage("rawdesk.ui.libraryFilmstripHeight")
    private var libraryFilmstripHeight =
        Double(RAWDeskTokens.Size.libraryFilmstrip)
    @AppStorage("rawdesk.ui.developSidebarVisible")
    private var isDevelopSidebarVisible = true
    @AppStorage("rawdesk.ui.developSidebarWidth")
    private var developSidebarWidth =
        Double(RAWDeskTokens.Size.leftSidebar)
    @AppStorage("rawdesk.ui.developInspectorVisible")
    private var isDevelopInspectorVisible = true
    @AppStorage("rawdesk.ui.developInspectorWidth")
    private var developInspectorWidth =
        Double(RAWDeskTokens.Size.rightInspector)
    @AppStorage("rawdesk.ui.developFilmstripVisible")
    private var isFilmstripVisible = true
    @AppStorage("rawdesk.ui.developFilmstripHeight")
    private var developFilmstripHeight =
        Double(RAWDeskTokens.Size.developFilmstrip)
    @AppStorage("rawdesk.ui.peopleSidebarVisible")
    private var isPeopleSidebarVisible = true
    @AppStorage("rawdesk.ui.peopleSidebarWidth")
    private var peopleSidebarWidth =
        Double(RAWDeskTokens.Size.leftSidebar)
    @AppStorage("rawdesk.ui.peopleInspectorVisible")
    private var isPeopleInspectorVisible = true
    @AppStorage("rawdesk.ui.peopleInspectorWidth")
    private var peopleInspectorWidth =
        Double(RAWDeskTokens.Size.rightInspector)
    @AppStorage("rawdesk.ui.mapSidebarVisible")
    private var isMapSidebarVisible = true
    @AppStorage("rawdesk.ui.mapSidebarWidth")
    private var mapSidebarWidth =
        Double(RAWDeskTokens.Size.leftSidebar)
    @AppStorage("rawdesk.ui.mapInspectorVisible")
    private var isMapInspectorVisible = true
    @AppStorage("rawdesk.ui.mapInspectorWidth")
    private var mapInspectorWidth =
        Double(RAWDeskTokens.Size.rightInspector)
    @State private var arePanelsTemporarilyHidden = false
    @State private var didConfigureInitialCompactLayout = false
    @State private var toolStartAdjustments:
        [PhotoAsset.ID: PhotoAdjustments] = [:]

    @State private var exportError: String?
    @State private var showExportError = false
    @State private var isExporting = false

    private var libraryDisplayMode:
        LibraryDisplayMode {
        get {
            LibraryDisplayMode(
                rawValue: libraryDisplayModeRaw
            ) ?? .grid
        }
        nonmutating set {
            libraryDisplayModeRaw = newValue.rawValue
        }
    }

    private var libraryDisplayModeBinding:
        Binding<LibraryDisplayMode> {
        Binding(
            get: { libraryDisplayMode },
            set: { libraryDisplayMode = $0 }
        )
    }

    private var workspaceSearch: Binding<String> {
        Binding(
            get: {
                library.workspaceMode == .people
                    ? people.searchText
                    : library.filter.searchText
            },
            set: { value in
                if library.workspaceMode == .people {
                    people.searchText = value
                } else {
                    library.filter.searchText = value
                }
            }
        )
    }

    @ViewBuilder
    private var developWorkspaceContent: some View {
        VSplitView {
            Group {
                if library.isScanning,
                   library.assets.isEmpty {
                    WorkspaceLoadingView(
                        title: "Loading photos…"
                    )
                } else if library.selectedAsset == nil {
                    WorkspaceEmptyView(
                        hasOpenFolder:
                            library.rootURL != nil,
                        onOpenFolder:
                            library.openFolderPicker
                    )
                } else {
                    ImagePreviewView(
                        viewer: viewer,
                        asset: library.selectedAsset,
                        onCropChange: updateCrop,
                        onGuidedUprightGuidesChange:
                            updateGuidedUprightGuides,
                        onSpotRemovalChange:
                            updateSpotRemoval,
                        onBrushStrokeCommit:
                            appendBrushStroke,
                        onObjectMaskPoint:
                            addObjectMask,
                        onPointColorSample:
                            addPointColorSample,
                        onMaskColorRangeSample:
                            addMaskColorRangeSample
                    )
                }
            }
            .frame(minHeight: 360)
            .background(RAWDeskTokens.ColorToken.canvas)

            DevelopFilmstripView(library: library)
                .frame(
                    minHeight: 132,
                    idealHeight: 148,
                    maxHeight: 168
                )
        }
        .frame(minWidth: 560)
        .background(RAWDeskTokens.ColorToken.canvas)
    }

    @ViewBuilder
    private var keyboardHandler: KeyboardHandler {
        KeyboardHandler(
            onPrev: { library.selectPrevious() },
            onNext: { library.selectNext() },
            onSelectAll: {
                library.selectAllVisiblePhotos()
            },
            onRating: { rating in
                if let id = library.selectionID {
                    library.setRating(rating, for: id)
                }
            },
            onColorLabel: { label, advances in
                if let id = library.selectionID {
                    library.setColorLabel(label, for: id)
                    if advances {
                        library.selectNext()
                    }
                }
            },
            onFlag: {
                if let id = library.selectionID {
                    library.toggleFlag(for: id)
                }
            },
            onPickStatus: { status in
                if let id = library.selectionID {
                    library.setPickStatus(status, for: id)
                }
            },
            onToggleQuickCollection: {
                _ = library.toggleTargetCollectionForSelection()
            },
            onToggleSoftProofing: {
                guard library.selectionID != nil,
                      library.surveyState == nil else {
                    return
                }
                viewer.toggleSoftProofing()
            },
            onShowGrid: {
                guard !library.isImportPresented else {
                    return
                }
                showWorkspace(.library)
                libraryDisplayMode = .grid
            },
            onShowLoupe: {
                guard !library.isImportPresented,
                      library.selectionID != nil else {
                    return
                }
                showWorkspace(.library)
                libraryDisplayMode = .loupe
            },
            canToggleLoupe:
                !library.isImportPresented
                && activeDestination == .library
                && library.selectionID != nil,
            onToggleLoupe: {
                guard !library.isImportPresented,
                      activeDestination == .library,
                      library.selectionID != nil else {
                    return
                }
                libraryDisplayMode =
                    libraryDisplayMode == .grid
                    ? .loupe
                    : .grid
            },
            onShowDevelop: {
                guard !library.isImportPresented,
                      library.selectionID != nil else {
                    return
                }
                showWorkspace(.develop)
            }
        )
    }

    @ViewBuilder
    private var exportProgressOverlay: some View {
        if isExporting {
            ZStack {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                VStack(spacing: RAWDeskTokens.Spacing.small) {
                    ProgressView()
                    Text("Developing full-resolution export…")
                        .font(RAWDeskTokens.Typography.control)
                }
                .padding(RAWDeskTokens.Spacing.xLarge)
                .background(
                    RAWDeskTokens.ColorToken.controlElevated,
                    in: RoundedRectangle(
                        cornerRadius:
                            RAWDeskTokens.Radius.modal
                    )
                )
                .shadow(radius: 12)
            }
        }
    }

    @ViewBuilder
    private var importPresentationOverlay: some View {
        if library.isImportPresented {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture { }
                    PhotoImportView(
                        library: library,
                        initialSourceURLs:
                            library.pendingImportSourceURLs,
                        onDismiss: {
                            library.dismissImport()
                        }
                    )
                    .frame(
                        width: min(
                            1180,
                            proxy.size.width - 48
                        ),
                        height: min(
                            760,
                            proxy.size.height - 48
                        )
                    )
                    .background(
                        RAWDeskTokens.ColorToken.panel,
                        in: RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius.modal
                        )
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius.modal
                        )
                    )
                    .shadow(radius: 28, y: 12)
                }
                .transition(
                    reduceMotion ? .identity : .opacity
                )
            }
            .zIndex(100)
        }
    }

    private var primaryWorkspace: some View {
        redesignedPrimaryWorkspace
        // The module picker already names the current module, three inches to
        // the right. Repeating "Develop" in the title said the same word twice
        // and spent the title on the one thing already on screen; the catalog
        // or folder name is what the title should carry.
        .navigationTitle(library.displayTitle)
        .toolbar {
            MainToolbar(
                library: library,
                viewer: viewer,
                photoWorkspaceMode:
                    $photoWorkspaceMode,
                isSidebarVisible:
                    activeSidebarVisibilityBinding,
                isInspectorVisible:
                    activeInspectorVisibilityBinding,
                isFilmstripVisible:
                    $isFilmstripVisible,
                arePanelsTemporarilyHidden:
                    $arePanelsTemporarilyHidden,
                onExport: exportSelected
            )
        }
        .searchable(
            text: workspaceSearch,
            prompt:
                library.workspaceMode == .people
                    ? "Search people or filenames"
                    : "Search filename, keyword, camera, or note"
        )
    }

    private var redesignedPrimaryWorkspace:
        some View {
        GeometryReader { proxy in
            Group {
                if shouldShowWelcome {
                    RAWWelcomeWorkspaceView(
                        library: library
                    )
                } else {
                    HStack(spacing: 0) {
                        if activeSidebarIsVisible {
                            redesignedSidebar
                                .frame(
                                    width:
                                        sidebarWidth(
                                            for:
                                                proxy.size
                                                    .width
                                        )
                                )
                            RAWResizableDivider(
                                value:
                                    sidebarWidthBinding(
                                        for:
                                            proxy.size.width
                                    ),
                                range:
                                    sidebarWidthRange(
                                        for:
                                            proxy.size.width
                                    ),
                                axis: .horizontal,
                                dragMultiplier: 1,
                                label:
                                    "\(activeDestination.name) sidebar width"
                            )
                        }

                        redesignedCenter
                            .frame(
                                minWidth:
                                    minimumCenterWidth(
                                        for: proxy.size.width
                                    )
                            )

                        if activeInspectorIsVisible {
                            RAWResizableDivider(
                                value:
                                    inspectorWidthBinding(
                                        for:
                                            proxy.size.width
                                    ),
                                range:
                                    inspectorWidthRange(
                                        for:
                                            proxy.size.width
                                    ),
                                axis: .horizontal,
                                dragMultiplier: -1,
                                label:
                                    "\(activeDestination.name) inspector width"
                            )
                            redesignedInspector
                                .frame(
                                    width:
                                        inspectorWidth(
                                            for:
                                                proxy.size
                                                    .width
                                        )
                                )
                        }
                    }
                }
            }
            .onAppear {
                configureInitialLayout(
                    for: proxy.size.width
                )
            }
            .onChange(of: proxy.size.width) {
                _, width in
                configureInitialLayout(for: width)
            }
        }
    }

    private var shouldShowWelcome: Bool {
        library.workspaceMode == .library
            && library.assets.isEmpty
            && !library.isScanning
    }

    private var activeSidebarIsVisible: Bool {
        guard !arePanelsTemporarilyHidden else {
            return false
        }
        switch activeDestination {
        case .library:
            return isLibrarySidebarVisible
        case .develop:
            return isDevelopSidebarVisible
        case .people:
            return isPeopleSidebarVisible
        case .map:
            return isMapSidebarVisible
        }
    }

    private var activeInspectorIsVisible: Bool {
        guard !arePanelsTemporarilyHidden else {
            return false
        }
        switch activeDestination {
        case .library:
            return isLibraryInspectorVisible
        case .develop:
            return isDevelopInspectorVisible
        case .people:
            return isPeopleInspectorVisible
        case .map:
            return isMapInspectorVisible
        }
    }

    private var activeDestination:
        WorkspaceDestination {
        switch library.workspaceMode {
        case .people:
            return .people
        case .map:
            return .map
        case .library:
            return photoWorkspaceMode == .develop
                ? .develop
                : .library
        }
    }

    private var activeSidebarVisibilityBinding:
        Binding<Bool> {
        Binding(
            get: {
                switch activeDestination {
                case .library:
                    return isLibrarySidebarVisible
                case .develop:
                    return isDevelopSidebarVisible
                case .people:
                    return isPeopleSidebarVisible
                case .map:
                    return isMapSidebarVisible
                }
            },
            set: { value in
                switch activeDestination {
                case .library:
                    isLibrarySidebarVisible = value
                case .develop:
                    isDevelopSidebarVisible = value
                case .people:
                    isPeopleSidebarVisible = value
                case .map:
                    isMapSidebarVisible = value
                }
            }
        )
    }

    private var activeInspectorVisibilityBinding:
        Binding<Bool> {
        Binding(
            get: {
                switch activeDestination {
                case .library:
                    return isLibraryInspectorVisible
                case .develop:
                    return isDevelopInspectorVisible
                case .people:
                    return isPeopleInspectorVisible
                case .map:
                    return isMapInspectorVisible
                }
            },
            set: { value in
                switch activeDestination {
                case .library:
                    isLibraryInspectorVisible = value
                case .develop:
                    isDevelopInspectorVisible = value
                case .people:
                    isPeopleInspectorVisible = value
                case .map:
                    isMapInspectorVisible = value
                }
            }
        )
    }

    private var activeSidebarWidthBinding:
        Binding<CGFloat> {
        Binding(
            get: {
                switch activeDestination {
                case .library:
                    return CGFloat(librarySidebarWidth)
                case .develop:
                    return CGFloat(developSidebarWidth)
                case .people:
                    return CGFloat(peopleSidebarWidth)
                case .map:
                    return CGFloat(mapSidebarWidth)
                }
            },
            set: { value in
                switch activeDestination {
                case .library:
                    librarySidebarWidth = Double(value)
                case .develop:
                    developSidebarWidth = Double(value)
                case .people:
                    peopleSidebarWidth = Double(value)
                case .map:
                    mapSidebarWidth = Double(value)
                }
            }
        )
    }

    private var activeInspectorWidthBinding:
        Binding<CGFloat> {
        Binding(
            get: {
                switch activeDestination {
                case .library:
                    return CGFloat(libraryInspectorWidth)
                case .develop:
                    return CGFloat(developInspectorWidth)
                case .people:
                    return CGFloat(peopleInspectorWidth)
                case .map:
                    return CGFloat(mapInspectorWidth)
                }
            },
            set: { value in
                switch activeDestination {
                case .library:
                    libraryInspectorWidth = Double(value)
                case .develop:
                    developInspectorWidth = Double(value)
                case .people:
                    peopleInspectorWidth = Double(value)
                case .map:
                    mapInspectorWidth = Double(value)
                }
            }
        )
    }

    @ViewBuilder
    private var redesignedSidebar: some View {
        switch activeDestination {
        case .develop:
            DevelopSidebarView(
                library: library,
                viewer: viewer
            )
            .rawPanelBackground()
        case .library:
            RAWLibrarySidebarView(library: library)
            .rawPanelBackground()
        case .people:
            PeopleSidebarView(people: people)
                .rawPanelBackground()
        case .map:
            MapSidebarView(library: library)
                .rawPanelBackground()
        }
    }

    @ViewBuilder
    private var redesignedCenter: some View {
        switch activeDestination {
        case .library:
            RAWLibraryWorkspaceView(
                library: library,
                viewer: viewer,
                compareViewer: compareViewer,
                referenceViewer: referenceViewer,
                displayMode:
                    libraryDisplayModeBinding,
                filmstripHeight:
                    Binding(
                        get: {
                            CGFloat(libraryFilmstripHeight)
                        },
                        set: {
                            libraryFilmstripHeight =
                                Double($0)
                        }
                    ),
                // One filmstrip toggle for the whole app, so ⌥⌘F means the
                // same thing in Library as it does in Develop.
                isFilmstripVisible: $isFilmstripVisible,
                onCropChange: updateCrop,
                onGuidedUprightGuidesChange:
                    updateGuidedUprightGuides,
                onSpotRemovalChange:
                    updateSpotRemoval,
                onBrushStrokeCommit:
                    appendBrushStroke,
                onObjectMaskPoint: addObjectMask,
                onPointColorSample:
                    addPointColorSample,
                onMaskColorRangeSample:
                    addMaskColorRangeSample
            )
        case .develop:
            RAWDevelopWorkspaceView(
                library: library,
                viewer: viewer,
                isFilmstripVisible:
                    $isFilmstripVisible,
                filmstripHeight:
                    Binding(
                        get: {
                            CGFloat(developFilmstripHeight)
                        },
                        set: {
                            developFilmstripHeight =
                                Double($0)
                        }
                    ),
                onCropChange: updateCrop,
                onGuidedUprightGuidesChange:
                    updateGuidedUprightGuides,
                onSpotRemovalChange:
                    updateSpotRemoval,
                onBrushStrokeCommit:
                    appendBrushStroke,
                onObjectMaskPoint: addObjectMask,
                onPointColorSample:
                    addPointColorSample,
                onMaskColorRangeSample:
                    addMaskColorRangeSample,
                onActivateTool:
                    activateDevelopTool,
                onFinishTool:
                    finishDevelopTool,
                onCancelTool:
                    cancelDevelopTool
            )
        case .people:
            PeopleWorkspaceView(
                people: people,
                library: library
            )
            .frame(minWidth: 480)
        case .map:
            MapWorkspaceView(library: library)
                .frame(minWidth: 480)
        }
    }

    @ViewBuilder
    private var redesignedInspector: some View {
        switch activeDestination {
        case .library:
            if library.catalogCollection
                == .assistedCulling {
                AssistedCullingInspectorView(
                    library: library,
                    asset: library.selectedAsset
                )
                .rawPanelBackground()
            } else {
                RAWLibraryInspectorView(
                    library: library,
                    onEditInDevelop: {
                        photoWorkspaceMode = .develop
                    }
                )
            }
        case .develop:
            EditingInspectorView(
                library: library,
                viewer: viewer,
                asset: library.selectedAsset,
                onActivateTool:
                    activateDevelopTool
            )
            .rawPanelBackground()
        case .people:
            PeopleInspectorView(
                people: people,
                library: library
            )
            .rawPanelBackground()
        case .map:
            LocationInspectorView(library: library)
                .rawPanelBackground()
        }
    }

    private func minimumCenterWidth(
        for windowWidth: CGFloat
    ) -> CGFloat {
        RAWDeskResponsiveLayout.minimumCenterWidth(
            for: windowWidth
        )
    }

    private func sidebarWidth(
        for windowWidth: CGFloat
    ) -> CGFloat {
        clamped(
            activeSidebarWidthBinding.wrappedValue,
            to: sidebarWidthRange(for: windowWidth)
        )
    }

    private func inspectorWidth(
        for windowWidth: CGFloat
    ) -> CGFloat {
        clamped(
            activeInspectorWidthBinding.wrappedValue,
            to: inspectorWidthRange(for: windowWidth)
        )
    }

    private func sidebarWidthRange(
        for windowWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        RAWDeskResponsiveLayout.sidebarWidthRange(
            for: windowWidth
        )
    }

    private func inspectorWidthRange(
        for windowWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        RAWDeskResponsiveLayout.inspectorWidthRange(
            for: windowWidth
        )
    }

    private func sidebarWidthBinding(
        for windowWidth: CGFloat
    ) -> Binding<CGFloat> {
        clampedBinding(
            activeSidebarWidthBinding,
            to: sidebarWidthRange(for: windowWidth)
        )
    }

    private func inspectorWidthBinding(
        for windowWidth: CGFloat
    ) -> Binding<CGFloat> {
        clampedBinding(
            activeInspectorWidthBinding,
            to: inspectorWidthRange(for: windowWidth)
        )
    }

    private func clampedBinding(
        _ binding: Binding<CGFloat>,
        to range: ClosedRange<CGFloat>
    ) -> Binding<CGFloat> {
        Binding(
            get: {
                clamped(binding.wrappedValue, to: range)
            },
            set: {
                binding.wrappedValue =
                    clamped($0, to: range)
            }
        )
    }

    private func clamped(
        _ value: CGFloat,
        to range: ClosedRange<CGFloat>
    ) -> CGFloat {
        min(
            range.upperBound,
            max(range.lowerBound, value)
        )
    }

    private func configureInitialLayout(
        for width: CGFloat
    ) {
        guard !didConfigureInitialCompactLayout else {
            return
        }
        didConfigureInitialCompactLayout = true

        let defaults = UserDefaults.standard
        let initialInspectorWidth =
            width < 1440
                ? Double(
                    RAWDeskTokens.Size
                        .rightInspectorCompact
                )
                : Double(
                    RAWDeskTokens.Size
                        .rightInspector
                )
        let inspectorDefaults:
            [(String, (Double) -> Void)] = [
                (
                    "rawdesk.ui.libraryInspectorWidth",
                    { libraryInspectorWidth = $0 }
                ),
                (
                    "rawdesk.ui.developInspectorWidth",
                    { developInspectorWidth = $0 }
                ),
                (
                    "rawdesk.ui.peopleInspectorWidth",
                    { peopleInspectorWidth = $0 }
                ),
                (
                    "rawdesk.ui.mapInspectorWidth",
                    { mapInspectorWidth = $0 }
                ),
            ]
        for (key, setWidth) in inspectorDefaults
        where defaults.object(forKey: key) == nil {
            setWidth(initialInspectorWidth)
        }

        if width < 1200 {
            isLibraryInspectorVisible = false
        }
    }

    private var workspaceWithOverlays: some View {
        primaryWorkspace
            .overlay {
                exportProgressOverlay
            }
            .overlay {
                importPresentationOverlay
            }
    }

    private var workspaceWithPresentations: some View {
        workspaceWithOverlays
        .alert("Export failed", isPresented: $showExportError, presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { msg in
            Text(verbatim: msg)
        }
        .sheet(
            isPresented:
                $library.isCaptureTimeAutoStackPresented
        ) {
            CaptureTimeAutoStackView(library: library)
        }
        .sheet(
            isPresented:
                $library.isSyncSettingsPresented
        ) {
            PhotoSyncSettingsView(library: library)
        }
        .sheet(
            isPresented:
                $library.isAutoImportSettingsPresented
        ) {
            AutoImportSettingsView(library: library)
        }
        .sheet(
            isPresented:
                $library.isColorLabelSetEditorPresented
        ) {
            ColorLabelSetEditorView(library: library)
        }
        .sheet(
            item: $library.editingSavedMapLocation
        ) { location in
            SavedMapLocationEditorView(
                library: library,
                initial: location
            )
        }
        .sheet(
            isPresented: $library.isGPXTracklogPresented
        ) {
            GPXTracklogView(library: library)
        }
    }

    private var workspaceWithSelectionLifecycle:
        some View {
        workspaceWithPresentations
        .modifier(SidecarNoticeAlertModifier(library: library))
        .focusedSceneObject(library)
        .focusedSceneObject(viewer)
        .onChange(of: library.selectionID) { _, _ in
            viewer.display(library.selectedAsset)
            library.persistWorkspace(
                photoWorkspace:
                    photoWorkspaceMode
            )
            announceSelection()
        }
        .onChange(of: library.rootURL) { _, _ in
            library.persistWorkspace(
                photoWorkspace:
                    photoWorkspaceMode
            )
        }
        .onChange(of: photoWorkspaceMode) {
            _, mode in
            library.persistWorkspace(
                photoWorkspace: mode
            )
        }
        .onChange(of: library.assets) { _, _ in
            library.reconcileReferenceState()
            library.reconcileCompareState()
            library.reconcileSurveyState()
            viewer.display(library.selectedAsset)
        }
    }

    var body: some View {
        workspaceWithSelectionLifecycle
        .onChange(of: library.compareState) { _, state in
            if state != nil {
                viewer.finishInteractiveTools()
                compareViewer.finishInteractiveTools()
                referenceViewer.finishInteractiveTools()
            }
        }
        .onChange(of: library.surveyState) { _, state in
            if state != nil {
                viewer.finishInteractiveTools()
                compareViewer.finishInteractiveTools()
                referenceViewer.finishInteractiveTools()
            }
        }
        .onChange(of: library.referenceState) { _, state in
            if state != nil {
                viewer.finishInteractiveTools()
                compareViewer.finishInteractiveTools()
                referenceViewer.finishInteractiveTools()
                referenceViewer.display(library.referenceAsset)
            }
        }
        .onChange(of: viewer.isCropEditing) { _, isEditing in
            if isEditing, library.referenceState != nil {
                library.endReferenceView()
            }
        }
        .onChange(of: viewer.isGuidedUprightEditing) { _, isEditing in
            if isEditing, library.referenceState != nil {
                library.endReferenceView()
            }
        }
        .onChange(of: library.selectedAsset?.userState.adjustments) { _, adjustments in
            if let id = library.selectionID, let adjustments {
                viewer.updateAdjustments(adjustments, for: id)
            }
        }
        .onChange(of: viewer.loadState) {
            _, state in
            if let id = viewer.currentAssetID {
                library.updateLoadOutcome(
                    state,
                    rawDecodeSource:
                        viewer.rawDecodeSource,
                    for: id
                )
            }
        }
        .onChange(of: viewer.rawDecodeSource) {
            _, source in
            if let id = viewer.currentAssetID {
                library.updateLoadOutcome(
                    viewer.loadState,
                    rawDecodeSource: source,
                    for: id
                )
            }
        }
        .onAppear {
            restoreWorkspace()
        }
        .onChange(of: library.workspaceMode) { _, mode in
            if mode == .people {
                people.startIfNeeded()
            }
        }
        .onChange(of: activeDestination) {
            _, destination in
            announce(
                "\(destination.name) workspace"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .rawDeskExport)) { _ in
            exportSelected()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .rawDeskUICommand
            )
        ) { notification in
            guard let command =
                    notification.object
                        as? RAWDeskUICommand else {
                return
            }
            handleUICommand(command)
        }
        .modifier(
            PeopleAnalysisLifecycleModifier(
                people: people,
                library: library
            )
        )
        .background(keyboardHandler)
        .preferredColorScheme(.dark)
    }

    private func restoreWorkspace() {
        if let restoredMode =
            library.restoreLastWorkspaceIfAvailable() {
            photoWorkspaceMode = restoredMode
        }
        let asset = library.selectedAsset
        viewer.display(asset)
    }

    private func showWorkspace(
        _ destination: WorkspaceDestination
    ) {
        switch destination {
        case .library:
            library.workspaceMode = .library
            photoWorkspaceMode = .library
        case .develop:
            guard library.selectionID != nil else {
                return
            }
            library.workspaceMode = .library
            photoWorkspaceMode = .develop
        case .people:
            library.workspaceMode = .people
        case .map:
            library.workspaceMode = .map
        }
    }

    private func handleUICommand(
        _ command: RAWDeskUICommand
    ) {
        switch command {
        case .showLibrary:
            showWorkspace(.library)
        case .showDevelop:
            showWorkspace(.develop)
        case .showPeople:
            showWorkspace(.people)
        case .showMap:
            showWorkspace(.map)
        case .toggleSidebar:
            activeSidebarVisibilityBinding
                .wrappedValue.toggle()
        case .toggleInspector:
            activeInspectorVisibilityBinding
                .wrappedValue.toggle()
        case .toggleFilmstrip:
            isFilmstripVisible.toggle()
        case .toggleAllPanels:
            arePanelsTemporarilyHidden.toggle()
        }
    }

    private func updateCrop(_ crop: NormalizedCrop) {
        guard let asset = library.selectedAsset else { return }
        var adjustments = asset.userState.adjustments
        adjustments.crop = crop
        library.setAdjustments(adjustments, for: asset.id)
        viewer.updateAdjustments(adjustments, for: asset.id)
    }

    private func updateGuidedUprightGuides(
        _ guides: [GuidedUprightGuide]
    ) {
        guard let asset = library.selectedAsset else { return }
        let adjustments = GuidedUprightSolver.applying(
            guides,
            to: asset.userState.adjustments
        )
        library.setAdjustments(adjustments, for: asset.id)
        viewer.updateAdjustments(adjustments, for: asset.id)
    }

    private func updateSpotRemoval(_ spot: SpotRemoval) {
        guard let asset = library.selectedAsset else { return }
        var adjustments = asset.userState.adjustments
        guard let index = adjustments.spotRemovals.firstIndex(where: { $0.id == spot.id }) else {
            return
        }
        adjustments.spotRemovals[index] = spot.normalized
        library.setAdjustments(adjustments, for: asset.id)
        viewer.updateAdjustments(adjustments, for: asset.id)
    }

    private func appendBrushStroke(
        maskID: LocalAdjustmentMask.ID,
        stroke: BrushStroke
    ) {
        guard let asset = library.selectedAsset else { return }
        var adjustments = asset.userState.adjustments
        guard let index = adjustments.localMasks.firstIndex(where: { $0.id == maskID }) else {
            return
        }
        if let operationID = viewer.selectedBrushPrimaryOperationID,
           let operationIndex = adjustments.localMasks[index].primaryOperations
            .firstIndex(where: { $0.id == operationID && $0.kind == .brush }) {
            adjustments.localMasks[index]
                .primaryOperations[operationIndex].strokes.append(stroke)
        } else {
            guard adjustments.localMasks[index].kind == .brush else { return }
            adjustments.localMasks[index].strokes.append(stroke)
        }
        adjustments = adjustments.normalized
        library.setAdjustments(adjustments, for: asset.id, coalescingHistory: false)
        viewer.updateAdjustments(adjustments, for: asset.id)
    }

    private func addPointColorSample(_ sample: PointColorSample) {
        guard let asset = library.selectedAsset else { return }
        var adjustments = asset.userState.adjustments
        let point = PointColorAdjustment(sample: sample)
        if let maskID = viewer.pointColorMaskTargetID {
            guard let maskIndex = adjustments.localMasks.firstIndex(
                where: { $0.id == maskID }
            ), adjustments.localMasks[maskIndex].pointColors.count < 8 else {
                viewer.setPointColorPicking(false)
                return
            }
            adjustments.localMasks[maskIndex].pointColors.append(point)
        } else {
            guard adjustments.pointColors.count < 8 else {
                viewer.setPointColorPicking(false)
                return
            }
            adjustments.pointColors.append(point)
        }
        adjustments = adjustments.normalized
        library.setAdjustments(
            adjustments,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(adjustments, for: asset.id)
        if viewer.pointColorMaskTargetID == nil {
            viewer.selectPointColor(point.id)
        }
        viewer.setPointColorPicking(false)
        toolStartAdjustments = [:]
    }

    private func addObjectMask(normalizedX: Double, normalizedY: Double) {
        guard viewer.isObjectMaskPicking,
              let asset = library.selectedAsset,
              let image = viewer.baseImage else {
            viewer.setObjectMaskPicking(false)
            viewer.setObjectMaskGeneration(
                false,
                message: "Wait for the photo to finish loading, then try again."
            )
            return
        }

        let assetID = asset.id
        let targetMaskID = viewer.objectMaskTargetID
        let combination = viewer.pendingMaskPrimaryCombination
        let sourceAdjustments = asset.userState.adjustments
        let orientationAdjustments = PhotoAdjustments(
            rotationDegrees: sourceAdjustments.rotationDegrees,
            flipHorizontal: sourceAdjustments.flipHorizontal,
            flipVertical: sourceAdjustments.flipVertical
        )
        viewer.setObjectMaskPicking(false)
        viewer.setObjectMaskGeneration(true)

        Task { @MainActor in
            let result: Result<Data, Error> = await Task.detached(
                priority: .userInitiated
            ) {
                Result {
                    let orientedImage = try PhotoProcessor.apply(
                        to: image,
                        adjustments: orientationAdjustments
                    )
                    return try SubjectMaskGenerator.generateObjectMaskPNG(
                        from: orientedImage,
                        normalizedX: normalizedX,
                        normalizedY: normalizedY
                    )
                }
            }.value

            guard viewer.currentAssetID == assetID else { return }
            switch result {
            case let .success(maskData):
                guard let currentAsset = library.assets.first(
                    where: { $0.id == assetID }
                ) else {
                    viewer.setObjectMaskGeneration(
                        false,
                        message: "The photo is no longer in the open library."
                    )
                    return
                }
                var updated = currentAsset.userState.adjustments
                let selectedMaskID: LocalAdjustmentMask.ID
                if let targetMaskID {
                    guard let maskIndex = updated.localMasks.firstIndex(
                        where: { $0.id == targetMaskID }
                    ), updated.localMasks[maskIndex].primaryOperations.count < 16 else {
                        viewer.setObjectMaskGeneration(
                            false,
                            message: "The target mask is no longer available."
                        )
                        return
                    }
                    let count = updated.localMasks[maskIndex].primaryOperations
                        .filter { $0.kind == .object }
                        .count + 1
                    let operation = MaskPrimaryOperation(
                        name: "Object \(count)",
                        kind: .object,
                        combination: combination,
                        rasterMaskData: maskData
                    )
                    updated.localMasks[maskIndex].primaryOperations.append(operation)
                    selectedMaskID = targetMaskID
                } else {
                    guard updated.localMasks.count < 32 else {
                        viewer.setObjectMaskGeneration(
                            false,
                            message: "This photo already has the maximum number of masks."
                        )
                        return
                    }
                    let count = updated.localMasks.filter { $0.kind == .object }.count + 1
                    let mask = LocalAdjustmentMask(
                        name: "Object \(count)",
                        kind: .object,
                        rasterMaskData: maskData
                    )
                    updated.localMasks.append(mask)
                    selectedMaskID = mask.id
                }
                updated = updated.normalized
                library.setAdjustments(
                    updated,
                    for: assetID,
                    coalescingHistory: false
                )
                viewer.updateAdjustments(updated, for: assetID)
                viewer.selectLocalMask(selectedMaskID)
                viewer.setObjectMaskGeneration(
                    false,
                    message: targetMaskID == nil
                        ? "Object selected on this Mac."
                        : "Object added to the mask as \(combination.name)."
                )

            case let .failure(error):
                viewer.setObjectMaskGeneration(
                    false,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func addMaskColorRangeSample(_ sample: PointColorSample) {
        guard let asset = library.selectedAsset,
              let maskID = viewer.maskColorRangeTargetID else {
            viewer.setMaskColorRangePicking(false)
            return
        }
        var adjustments = asset.userState.adjustments
        guard let maskIndex = adjustments.localMasks.firstIndex(
            where: { $0.id == maskID }
        ) else {
            viewer.setMaskColorRangePicking(false)
            return
        }

        let selectedOperationID: MaskRangeOperation.ID
        if let operationID = viewer.maskColorRangeOperationTargetID,
           let operationIndex = adjustments.localMasks[maskIndex].rangeOperations
            .firstIndex(where: { $0.id == operationID }) {
            adjustments.localMasks[maskIndex]
                .rangeOperations[operationIndex].colorSample = sample
            selectedOperationID = operationID
        } else {
            guard adjustments.localMasks[maskIndex].rangeOperations.count < 16 else {
                viewer.setMaskColorRangePicking(false)
                return
            }
            let count = adjustments.localMasks[maskIndex].rangeOperations
                .filter { $0.kind == .color }
                .count + 1
            let operation = MaskRangeOperation(
                name: "Color Range \(count)",
                kind: .color,
                combination: viewer.pendingMaskRangeCombination,
                colorSample: sample
            )
            adjustments.localMasks[maskIndex].rangeOperations.append(operation)
            selectedOperationID = operation.id
        }
        adjustments = adjustments.normalized
        library.setAdjustments(
            adjustments,
            for: asset.id,
            coalescingHistory: false
        )
        viewer.updateAdjustments(adjustments, for: asset.id)
        viewer.selectLocalMask(maskID)
        viewer.selectMaskRangeOperation(selectedOperationID)
        viewer.setMaskColorRangePicking(false)
    }

    private func activateDevelopTool(
        _ tool: DevelopCanvasTool
    ) {
        guard let asset = library.selectedAsset else {
            return
        }
        if currentDevelopTool == tool {
            return
        }
        expandDevelopSection(for: tool)
        captureToolStartIfNeeded()

        switch tool {
        case .crop:
            viewer.setCropEditing(true)
        case .remove:
            startRemovalTool(for: asset)
        case .mask:
            startMaskTool(for: asset)
        case .guidedUpright:
            viewer.setGuidedUprightEditing(true)
        case .pointColor:
            viewer.setPointColorPicking(true)
        }
        announce(
            "\(tool.name) tool. Press Return or Done to apply, or Escape to cancel."
        )
    }

    private func expandDevelopSection(
        for tool: DevelopCanvasTool
    ) {
        let key: String
        switch tool {
        case .crop, .guidedUpright:
            key = "rawdesk.develop.section.geometry"
        case .remove:
            key = "rawdesk.develop.section.remove"
        case .mask:
            key = "rawdesk.develop.section.masks"
        case .pointColor:
            key = "rawdesk.develop.section.pointColor"
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func finishDevelopTool() {
        let finishedTool = currentDevelopTool
        viewer.finishInteractiveTools()
        toolStartAdjustments = [:]
        if let finishedTool {
            announce(
                "\(finishedTool.name) tool applied"
            )
        }
    }

    private func cancelDevelopTool() {
        let cancelledTool = currentDevelopTool
        viewer.finishInteractiveTools()
        for (id, adjustments) in
            toolStartAdjustments {
            library.cancelInteractiveAdjustments(
                restoring: adjustments,
                for: id
            )
        }
        if let asset = library.selectedAsset {
            viewer.updateAdjustments(
                asset.userState.adjustments,
                for: asset.id
            )
        }
        toolStartAdjustments = [:]
        if let cancelledTool {
            announce(
                "\(cancelledTool.name) tool cancelled"
            )
        }
    }

    private func announceSelection() {
        guard let asset = library.selectedAsset else {
            announce("No photo selected")
            return
        }
        let count = library.selectedIDs.count
        let selection =
            count > 1
            ? "\(count) photos selected. "
            : ""
        announce(
            "\(selection)Active photo \(asset.filename)"
        )
    }

    private func announce(_ message: String) {
        AccessibilityNotification
            .Announcement(message)
            .post()
    }

    private var currentDevelopTool:
        DevelopCanvasTool? {
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

    private func captureToolStartIfNeeded() {
        guard toolStartAdjustments.isEmpty,
              let activeID = library.selectionID else {
            return
        }
        let ids: Set<PhotoAsset.ID> =
            library.isAutoSyncEnabled
                ? library.selectedIDs
                : [activeID]
        toolStartAdjustments = Dictionary(
            uniqueKeysWithValues:
                library.assets.compactMap { asset in
                    ids.contains(asset.id)
                        ? (
                            asset.id,
                            asset.userState
                                .adjustments
                        )
                        : nil
                }
        )
    }

    private func startRemovalTool(
        for asset: PhotoAsset
    ) {
        if let existing =
            asset.userState.adjustments
                .spotRemovals.first {
            viewer.setRemovalEditing(
                true,
                selectedSpotID: existing.id
            )
            return
        }
        var updated = asset.userState.adjustments
        guard updated.spotRemovals.count < 128 else {
            return
        }
        let spot = SpotRemoval(
            name: "Heal 1",
            kind: .heal
        )
        updated.spotRemovals.append(spot)
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
        viewer.setRemovalEditing(
            true,
            selectedSpotID: spot.id
        )
    }

    private func startMaskTool(
        for asset: PhotoAsset
    ) {
        if let existing =
            asset.userState.adjustments.localMasks
                .first(where: { $0.kind == .brush }) {
            viewer.setBrushEditing(
                true,
                selectedMaskID: existing.id
            )
            viewer.setLocalMaskVisualization(
                existing.id
            )
            return
        }
        var updated = asset.userState.adjustments
        guard updated.localMasks.count < 32 else {
            return
        }
        let count =
            updated.localMasks.filter {
                $0.kind == .brush
            }.count + 1
        let mask = LocalAdjustmentMask(
            name: "Brush \(count)",
            kind: .brush
        )
        updated.localMasks.append(mask)
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
        viewer.setBrushEditing(
            true,
            selectedMaskID: mask.id
        )
        viewer.setLocalMaskVisualization(mask.id)
    }

    private func exportSelected() {
        guard library.workspaceMode != .people else { return }
        guard let asset = library.selectedAsset, viewer.image != nil else {
            exportError = "No image is currently displayed."
            showExportError = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = (asset.url.deletingPathExtension().lastPathComponent) + "-export"
        panel.canCreateDirectories = true
        panel.title = "Export Image"

        if panel.runModal() == .OK, let url = panel.url {
            let format: ImageExporter.ExportFormat = {
                if url.pathExtension.lowercased() == "png" { return .png }
                return .jpeg(quality: 0.9)
            }()
            let adjustments = asset.userState.adjustments
            let transform = viewer.transform
            let keywords = library.exportKeywords(for: asset)
            isExporting = true
            Task {
                do {
                    try await ImageExporter.export(
                        asset: asset,
                        adjustments: adjustments,
                        transform: transform,
                        to: url,
                        format: format,
                        keywords: keywords,
                        suppressLocation:
                            library
                                .shouldSuppressLocationOnExport(
                                    for: asset
                                )
                    )
                } catch {
                    exportError = error.localizedDescription
                    showExportError = true
                }
                isExporting = false
            }
        }
    }
}

private struct WorkspaceLoadingView: View {
    let title: String

    var body: some View {
        RAWEmptyState(
            title: title,
            indicator: .progress,
            message: "RAWDesk is reading the folder locally."
        )
        .background(RAWDeskTokens.ColorToken.canvas)
    }
}

private struct WorkspaceEmptyView: View {
    let hasOpenFolder: Bool
    let onOpenFolder: () -> Void

    var body: some View {
        RAWEmptyState(
            title:
                hasOpenFolder
                ? "No Photos Here"
                : "Open a Photo Folder",
            systemImage:
                hasOpenFolder
                ? "photo.stack"
                : "folder",
            message:
                hasOpenFolder
                ? "Choose another folder or change the Library filters."
                : "RAWDesk works locally with the photos already on this Mac."
        ) {
            Button(action: onOpenFolder) {
                Label(
                    "Open Folder…",
                    systemImage: "folder"
                )
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .keyboardShortcut("o")
        }
        .background(RAWDeskTokens.ColorToken.canvas)
    }
}

/// The Navigator thumbnail: the developed preview the viewer already holds, so
/// it reflects live edits without decoding anything extra.
private struct DevelopNavigatorPreview: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                // Sized to the photo's own aspect ratio rather than dropped
                // into a fixed landscape box. A portrait frame previously left
                // wide black bars on both sides that read as a broken image.
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(
                        aspectRatio(of: image),
                        contentMode: .fit
                    )
                    .frame(maxHeight: 150)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius.control
                        )
                    )
            } else {
                ZStack {
                    RoundedRectangle(
                        cornerRadius:
                            RAWDeskTokens.Radius.control
                    )
                    .fill(RAWDeskTokens.ColorToken.canvas)
                    Image(systemName: "photo")
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                }
                .frame(height: 96)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Navigator preview")
    }

    private func aspectRatio(of image: NSImage) -> CGFloat {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }
}

private struct DevelopSidebarView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var viewer: PhotoViewerViewModel

    private var selectedAsset: PhotoAsset? {
        library.selectedAsset
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func zoomPreset(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textPrimary
                )
                .padding(
                    .horizontal,
                    RAWDeskTokens.Spacing.small
                )
                .frame(
                    minHeight: RAWDeskTokens.Size.iconTarget
                )
                .background(
                    RAWDeskTokens.ColorToken.controlElevated,
                    in: RoundedRectangle(
                        cornerRadius:
                            RAWDeskTokens.Radius.control
                    )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            title == "Fit"
                ? "Fit the photo to the window"
                : "View at actual pixel size"
        )
    }

    var body: some View {
        List {
            // A Navigator is a preview with zoom presets, not a caption. The
            // section used to hold only text, which left the name "Navigator"
            // describing something that could not navigate.
            Section("Navigator") {
                if let asset = selectedAsset {
                    VStack(
                        alignment: .leading,
                        spacing: RAWDeskTokens.Spacing.xSmall
                    ) {
                        DevelopNavigatorPreview(
                            image: viewer.image
                        )
                        // Zoom presets read as controls, not as blue links.
                        // A List renders a plain Button as accent-coloured
                        // text, which put two hyperlinks under the preview.
                        HStack(
                            spacing:
                                RAWDeskTokens.Spacing.xSmall
                        ) {
                            zoomPreset("Fit") {
                                viewer.transform.fit()
                            }
                            zoomPreset("100%") {
                                viewer.transform.actualSize()
                            }
                            Spacer(minLength: 0)
                        }
                        // The extension already states the format, so the
                        // separate format line only repeats it. RAW files keep
                        // the note because "ARW · RAW" is not obvious from the
                        // extension alone.
                        Text(asset.filename)
                            .font(
                                RAWDeskTokens.Typography
                                    .sectionHeader
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if asset.isRaw {
                            Text(
                                "\(asset.format.displayName) · RAW"
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }
                    }
                    .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                } else {
                    Text("No photo selected")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
            }

            // Camera and lens moved out of Navigator: they describe the
            // capture, not the view.
            if let asset = selectedAsset,
               asset.metadata?.cameraModel != nil
                   || asset.metadata?.lensModel != nil {
                Section("Camera") {
                    VStack(
                        alignment: .leading,
                        spacing: RAWDeskTokens.Spacing.xSmall
                    ) {
                        if let camera =
                            asset.metadata?.cameraModel {
                            Label(
                                camera,
                                systemImage: "camera"
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }
                        if let lens =
                            asset.metadata?.lensModel {
                            Text(lens)
                                .font(RAWDeskTokens.Typography.badge)
                                .foregroundStyle(
                                    RAWDeskTokens.ColorToken
                                        .textSecondary
                                )
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                }
            }

            Section("Presets") {
                ForEach(
                    DevelopmentPreset.allCases
                ) { preset in
                    Button {
                        guard let asset =
                            selectedAsset else {
                            return
                        }
                        library.applyPreset(
                            preset,
                            to: asset.id
                        )
                        if let updated =
                            library.selectedAsset {
                            viewer.updateAdjustments(
                                updated.userState
                                    .adjustments,
                                for: updated.id
                            )
                        }
                    } label: {
                        Label(
                            preset.name,
                            systemImage:
                                preset.systemImage
                        )
                    }
                    .disabled(selectedAsset == nil)
                }
            }

            Section("History") {
                if selectedAsset == nil {
                    Text("No photo selected")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                } else {
                    Label(
                        "Current edit",
                        systemImage: "circle.fill"
                    )
                    .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)

                    let previousCount =
                        library.adjustmentHistoryDepth(
                            for: selectedAsset?.id
                        )
                    if previousCount > 0 {
                        Label(
                            "\(previousCount) earlier state\(previousCount == 1 ? "" : "s")",
                            systemImage:
                                "clock.arrow.circlepath"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }

                    let futureCount =
                        library.adjustmentFutureDepth(
                            for: selectedAsset?.id
                        )
                    if futureCount > 0 {
                        Label(
                            "\(futureCount) redo state\(futureCount == 1 ? "" : "s")",
                            systemImage:
                                "arrow.uturn.forward"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }

                    // Was truncating to "…move through edit…" at the panel's
                    // real width, which is worse than not saying it at all.
                    Text("⌘Z / ⇧⌘Z to step through history")
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

            if let asset = selectedAsset {
                Section("Versions") {
                    Button {
                        library.createVersion(
                            for: asset.id
                        )
                    } label: {
                        Label(
                            "Create Version",
                            systemImage:
                                "plus.square.on.square"
                        )
                    }

                    ForEach(
                        asset.userState.versions
                            .reversed()
                    ) { version in
                        Button {
                            library.applyVersion(
                                version.id,
                                to: asset.id
                            )
                            syncViewer()
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: RAWDeskTokens.Spacing.xSmall
                            ) {
                                Text(version.name)
                                Text(
                                    version.createdAt
                                        .formatted(
                                            date:
                                                .abbreviated,
                                            time:
                                                .shortened
                                        )
                                )
                                .font(RAWDeskTokens.Typography.badge)
                                .foregroundStyle(
                                    RAWDeskTokens.ColorToken
                                        .textSecondary
                                )
                            }
                        }
                    }
                }
            }

            Section("Folders") {
                if let rootURL = library.rootURL {
                    Label(
                        displayName(for: rootURL),
                        systemImage: "folder.fill"
                    )
                    .help(rootURL.path)
                }
                ForEach(
                    library.recentFolders.filter {
                        $0.path !=
                            library.rootURL?.path
                    },
                    id: \.self
                ) { url in
                    Button {
                        library.reopen(recent: url)
                    } label: {
                        Label(
                            displayName(for: url),
                            systemImage: "folder"
                        )
                    }
                    .disabled(
                        !FileManager.default
                            .fileExists(
                                atPath: url.path
                            )
                    )
                    .help(url.path)
                }
            }
        }
        .listStyle(.sidebar)
        .rawPanelScrollBackground()
        // No title here. This sidebar set the window title to "Develop", which
        // overrode the catalog name and put the word on screen twice — once
        // beside the toolbar buttons and once in the module picker.
    }

    private func syncViewer() {
        guard let asset = library.selectedAsset else {
            return
        }
        viewer.updateAdjustments(
            asset.userState.adjustments,
            for: asset.id
        )
    }
}

struct DevelopFilmstripStatus: Equatable {
    let selectionText: String?
    let selectionAccessibilityLabel: String?
    let autoSyncText: String
    let autoSyncAccessibilityLabel: String
    let isAutoSyncActive: Bool
    let showsFilterBadge: Bool
    let photoCountText: String

    init(
        selectedCount: Int,
        isAutoSyncEnabled: Bool,
        isFilterActive: Bool,
        filteredCount: Int
    ) {
        let safeSelectedCount =
            max(0, selectedCount)
        selectionText =
            safeSelectedCount > 1
                ? "\(safeSelectedCount) selected"
                : nil
        selectionAccessibilityLabel =
            safeSelectedCount > 1
                ? "\(safeSelectedCount) photos selected"
                : nil
        autoSyncText =
            isAutoSyncEnabled
                ? "Auto Sync ON"
                : "Auto Sync OFF"
        autoSyncAccessibilityLabel =
            isAutoSyncEnabled
                ? "Auto Sync on"
                : "Auto Sync off"
        isAutoSyncActive = isAutoSyncEnabled
        showsFilterBadge = isFilterActive
        photoCountText =
            "\(max(0, filteredCount)) photos"
    }
}

struct DevelopFilmstripView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    private let cellWidth: CGFloat = 116

    var body: some View {
        let status = DevelopFilmstripStatus(
            selectedCount:
                library.selectedIDs.count,
            isAutoSyncEnabled:
                library.isAutoSyncEnabled,
            isFilterActive:
                library.filter.isActive,
            filteredCount:
                library.filtered.count
        )
        VStack(spacing: 0) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Label(
                    "Filmstrip",
                    systemImage: "film.stack"
                )
                .font(RAWDeskTokens.Typography.sectionHeader)
                Spacer()
                if let selectionText =
                    status.selectionText {
                    Text(
                        selectionText
                    )
                    .accessibilityLabel(
                        status
                            .selectionAccessibilityLabel
                            ?? selectionText
                    )
                }
                Text(
                    status.autoSyncText
                )
                .foregroundStyle(
                    status.isAutoSyncActive
                        ? RAWDeskTokens.ColorToken.selection
                        : RAWDeskTokens.ColorToken
                            .textSecondary
                )
                .accessibilityLabel(
                    status
                        .autoSyncAccessibilityLabel
                )
                if status.showsFilterBadge {
                    Label(
                        "Filtered",
                        systemImage:
                            "line.3.horizontal.decrease"
                    )
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel(
                        "Filter applied"
                    )
                }
                Text(
                    status.photoCountText
                )
            }
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )
            .lineLimit(1)
            .padding(.horizontal, RAWDeskTokens.Spacing.small)
            .frame(
                height:
                    RAWDeskTokens.Size.iconTarget
            )

            Divider()

            if library.filtered.isEmpty {
                Text("No photos match the current filter.")
                    .font(RAWDeskTokens.Typography.control)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: RAWDeskTokens.Spacing.small) {
                            ForEach(
                                library.filtered
                            ) { asset in
                                filmstripCell(asset)
                                    .id(asset.id)
                            }
                        }
                        .padding(
                            .horizontal,
                            RAWDeskTokens.Spacing.small
                        )
                        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                    }
                    .onAppear {
                        scrollToSelection(
                            proxy: proxy,
                            animated: false
                        )
                    }
                    .onChange(
                        of: library.selectionID
                    ) { _, _ in
                        scrollToSelection(
                            proxy: proxy,
                            animated: !reduceMotion
                        )
                    }
                }
            }
        }
        .background(
            RAWDeskTokens.ColorToken.chrome
        )
        .accessibilityIdentifier("Develop filmstrip")
    }

    private func filmstripCell(
        _ asset: PhotoAsset
    ) -> some View {
        ThumbnailCellView(
            asset: asset,
            isSelected:
                library.selectedIDs.contains(
                    asset.id
                ),
            isActive:
                library.selectionID == asset.id,
            compareRole: nil,
            surveyRole: nil,
            pixelSize: cellWidth * 2,
            duplicateGroupNumber:
                library.duplicateGroupNumber(
                    for: asset.id
                ),
            isDuplicateAnchor:
                library.isDuplicateAnchor(asset.id),
            isInQuickCollection:
                library.isInQuickCollection(asset.id),
            isInPhotoCollection:
                library.isInAnyPhotoCollection(
                    asset.id
                ),
            cullingEvaluation:
                library.cullingEvaluation(for: asset.id),
            cullingAnalysis:
                library.cullingAnalysis(for: asset.id),
            cullingStackNumber:
                library.cullingStackNumber(
                    for: asset.id
                ),
            stackMembership:
                library.photoStackMembership(
                    for: asset.id
                ),
            onStackToggle: {
                library.togglePhotoStack(
                    containing: asset.id
                )
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
            }
        )
        .frame(
            width: cellWidth,
            height: cellWidth + 18
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let modifiers =
                NSEvent.modifierFlags
                    .intersection(
                        .deviceIndependentFlagsMask
                    )
            library.select(
                asset.id,
                extending:
                    modifiers.contains(.command),
                range:
                    modifiers.contains(.shift)
            )
        }
    }

    private func scrollToSelection(
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let selectionID =
            library.selectionID else {
            return
        }
        if animated {
            withAnimation(
                .easeOut(duration: 0.18)
            ) {
                proxy.scrollTo(
                    selectionID,
                    anchor: .center
                )
            }
        } else {
            proxy.scrollTo(
                selectionID,
                anchor: .center
            )
        }
    }
}

private struct PeopleAnalysisLifecycleModifier:
    ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var people: PeopleViewModel
    @ObservedObject var library: LibraryViewModel

    func body(content: Content) -> some View {
        content
            .onAppear {
                people.startAutomaticAnalysisIfNeeded()
            }
            .onChange(
                of: library.catalogSummary[.allPhotos]
            ) { _, _ in
                people.catalogDidChange()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    people.applicationDidBecomeActive()
                } else {
                    people.applicationDidBecomeInactive()
                    library.flushPendingPersistence()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .rawDeskPeopleAnalysisDidChange
                )
            ) { _ in
                people.refreshFromCatalog()
                library.refreshCatalogOverview()
            }
    }
}

private struct SidecarNoticeAlertModifier: ViewModifier {
    @ObservedObject var library: LibraryViewModel

    func body(content: Content) -> some View {
        content.alert(item: $library.sidecarNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
