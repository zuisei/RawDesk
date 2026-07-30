import SwiftUI
import MapKit
import AppKit

struct MapWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel

    @State private var requestedRegion: MKCoordinateRegion?
    @State private var regionRequestID = 0
    @State private var fitPinsRequestID = 0
    @State private var visibleRegion: MKCoordinateRegion?
    @AppStorage("rawdesk.map.photoScope")
    private var photoScopeRaw =
        MapPhotoScope.all.rawValue
    @AppStorage("rawdesk.map.displayStyle")
    private var displayStyleRaw =
        MapDisplayStyle.standard.rawValue
    @State private var isAssigningLocation = false
    @State private var searchText = ""
    @State private var searchMessage: String?
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    private var photoScope: MapPhotoScope {
        get {
            MapPhotoScope(
                rawValue: photoScopeRaw
            ) ?? .all
        }
        nonmutating set {
            photoScopeRaw = newValue.rawValue
        }
    }

    private var photoScopeBinding:
        Binding<MapPhotoScope> {
        Binding(
            get: { photoScope },
            set: { photoScope = $0 }
        )
    }

    private var displayStyle: MapDisplayStyle {
        get {
            MapDisplayStyle(
                rawValue: displayStyleRaw
            ) ?? .standard
        }
        nonmutating set {
            displayStyleRaw = newValue.rawValue
        }
    }

    private var displayStyleBinding:
        Binding<MapDisplayStyle> {
        Binding(
            get: { displayStyle },
            set: { displayStyle = $0 }
        )
    }

    private var sourceAssets: [PhotoAsset] {
        library.filtered.filter { !$0.catalogMissing }
    }

    private var locatedAssets: [PhotoAsset] {
        sourceAssets.filter { $0.effectiveLocation != nil }
    }

    private var pinAssets: [PhotoAsset] {
        switch photoScope {
        case .all, .tagged:
            return locatedAssets
        case .untagged:
            return []
        case .visible:
            guard let visibleRegion else { return locatedAssets }
            return locatedAssets.filter {
                guard let coordinate =
                        $0.effectiveLocation?.coordinate else {
                    return false
                }
                return visibleRegion.contains(coordinate)
            }
        }
    }

    private var filmstripAssets: [PhotoAsset] {
        switch photoScope {
        case .all:
            return sourceAssets
        case .tagged:
            return locatedAssets
        case .untagged:
            return sourceAssets.filter {
                $0.effectiveLocation == nil
            }
        case .visible:
            guard let visibleRegion else { return locatedAssets }
            return locatedAssets.filter {
                guard let coordinate =
                        $0.effectiveLocation?.coordinate else {
                    return false
                }
                return visibleRegion.contains(coordinate)
            }
        }
    }

    private var annotationGroups: [PhotoMapAnnotationGroup] {
        PhotoMapAnnotationGroup.groups(for: pinAssets)
    }

    private var visibleSavedLocations: [SavedMapLocation] {
        library.savedMapLocations.filter(\.isVisible)
    }

    var body: some View {
        VStack(spacing: 0) {
            mapToolbar
            Divider()
            styledMap
                .overlay(alignment: .topLeading) {
                    mapStatusOverlay
                }
            Divider()
            filmstrip
        }
        .task {
            library.refreshLocationMetadataIfNeeded()
        }
        .onChange(of: library.selectionID) { _, _ in
            searchMessage = nil
        }
        .onChange(of: library.assets.map(\.id)) { _, _ in
            library.refreshLocationMetadataIfNeeded()
        }
        .onChange(of: library.mapFocusRequest) { _, request in
            guard let request,
                  let location = library.savedMapLocation(
                      id: request.locationID
                  ) else {
                return
            }
            requestMapRegion(cameraRegion(for: location))
        }
    }

    private var mapToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                mapSearchControl
                photoScopeControl
                mapStyleControl
                Spacer(
                    minLength:
                        RAWDeskTokens.Spacing.small
                )
                tracklogMenu
                saveAreaButton
                showSelectedButton
                fitPinsButton
                setLocationButton
            }

            HStack(spacing: RAWDeskTokens.Spacing.small) {
                mapSearchControl
                photoScopeControl
                mapActionsMenu
            }
        }
        .controlSize(.small)
        .padding(
            .horizontal,
            RAWDeskTokens.Spacing.medium
        )
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    private var mapSearchControl: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
            TextField(
                "Search a place or address",
                text: $searchText
            )
            .textFieldStyle(.plain)
            .focused($searchFocused)
            .onSubmit {
                search()
            }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                }
                .buttonStyle(.plain)
                .rawIconButtonTarget()
                .help("Clear map search")
                .accessibilityLabel("Clear map search")
            }
        }
        .padding(
            .horizontal,
            RAWDeskTokens.Spacing.small
        )
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .background(
            RAWDeskTokens.ColorToken.controlElevated,
            in: RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.control
            )
        )
        .frame(
            minWidth: 190,
            idealWidth: 300,
            maxWidth: 380
        )
    }

    private var photoScopeControl: some View {
        Picker(
            "Photos",
            selection: photoScopeBinding
        ) {
            ForEach(MapPhotoScope.allCases) { scope in
                Text(scope.name).tag(scope)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 118)
    }

    private var mapStyleControl: some View {
        Picker(
            "Map style",
            selection: displayStyleBinding
        ) {
            ForEach(MapDisplayStyle.allCases) { style in
                Text(style.name).tag(style)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 108)
    }

    private var tracklogMenu: some View {
        Menu {
            Button("Load GPX Tracklog…") {
                library.loadGPXTracklogPicker()
            }
            if let tracklog =
                    library.loadedGPXTracklog {
                Button("Tracklog Settings…") {
                    library.isGPXTracklogPresented = true
                }
                Toggle(
                    "Show Track on Map",
                    isOn: $library.isGPXTrackVisible
                )
                Button("Fit Track") {
                    fitTracklog(tracklog)
                }
                Divider()
                Button("Clear Tracklog") {
                    library.clearGPXTracklog()
                }
            }
        } label: {
            Label(
                "Tracklog",
                systemImage:
                    "point.topleft.down.to.point.bottomright.curvepath"
            )
        }
        .help("Load or match a timestamped GPX route")
    }

    private var saveAreaButton: some View {
        Button {
            saveArea()
        } label: {
            Label(
                "Save Area",
                systemImage: "mappin.and.ellipse"
            )
        }
        .help("Create a saved location at the map center")
    }

    private var showSelectedButton: some View {
        Button {
            showSelectedOnMap()
        } label: {
            Label("Show Selected", systemImage: "scope")
        }
        .disabled(
            library.selectedAsset?
                .effectiveLocation == nil
        )
        .help("Center the map on the active photo")
    }

    private var fitPinsButton: some View {
        Button {
            fitPinsRequestID += 1
        } label: {
            Label(
                "Fit Pins",
                systemImage:
                    "arrow.up.left.and.down.right"
            )
        }
        .disabled(locatedAssets.isEmpty)
        .help("Fit all visible location pins")
    }

    private var setLocationButton: some View {
        Button {
            isAssigningLocation.toggle()
        } label: {
            Label(
                isAssigningLocation
                    ? "Click the Map"
                    : "Set Location",
                systemImage:
                    isAssigningLocation
                    ? "mappin.circle.fill"
                    : "mappin.circle"
            )
        }
        .modifier(
            MapAssignmentButtonModifier(
                isActive: isAssigningLocation
            )
        )
        .disabled(
            library.locationMutationTargetCount == 0
        )
        .help(
            isAssigningLocation
                ? "Click the map to assign that coordinate to the selected photos"
                : "Assign a map coordinate to the selected photos"
        )
        .accessibilityIdentifier("Map set location")
    }

    private var mapActionsMenu: some View {
        Menu {
            Picker(
                "Map Style",
                selection: displayStyleBinding
            ) {
                ForEach(
                    MapDisplayStyle.allCases
                ) { style in
                    Text(style.name).tag(style)
                }
            }
            Divider()
            tracklogMenu
            Button("Save Area") {
                saveArea()
            }
            Button("Show Selected") {
                showSelectedOnMap()
            }
            .disabled(
                library.selectedAsset?
                    .effectiveLocation == nil
            )
            Button("Fit Pins") {
                fitPinsRequestID += 1
            }
            .disabled(locatedAssets.isEmpty)
            Divider()
            Button(
                isAssigningLocation
                    ? "Cancel Set Location"
                    : "Set Location"
            ) {
                isAssigningLocation.toggle()
            }
            .disabled(
                library.locationMutationTargetCount
                    == 0
            )
        } label: {
            Label(
                "Map Actions",
                systemImage: "ellipsis.circle"
            )
        }
        .labelStyle(.iconOnly)
        .rawIconButtonTarget()
        .help("Map style, tracklog, and location actions")
        .accessibilityLabel("Map actions")
    }

    private func saveArea() {
        let center = visibleRegion?.center
            ?? library.selectedAsset?
                .effectiveLocation?.coordinate
        let location = center.flatMap {
            PhotoLocation(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
        _ = library.presentNewSavedMapLocation(
            center: location
        )
    }

    private var styledMap: some View {
        interactiveMap
    }

    private var interactiveMap: some View {
        PhotoMapCanvas(
            displayStyle: displayStyle,
            photoGroups: annotationGroups,
            selectedAssetIDs: library.selectedIDs,
            savedLocations: visibleSavedLocations,
            trackCoordinates:
                library.isGPXTrackVisible
                ? library.loadedGPXTracklog?
                    .displayCoordinates ?? []
                : [],
            requestedRegion: requestedRegion,
            regionRequestID: regionRequestID,
            fitPinsRequestID: fitPinsRequestID,
            isAssigningLocation: isAssigningLocation,
            taggedCount: locatedAssets.count,
            totalCount: sourceAssets.count,
            onVisibleRegionChange: { region in
                visibleRegion = region
            },
            onAssignCoordinate: { coordinate in
                guard isAssigningLocation,
                      let location = PhotoLocation(
                          latitude: coordinate.latitude,
                          longitude: coordinate.longitude
                      ) else {
                    return
                }
                let targetCount =
                    library.locationMutationTargetCount
                library.setLocationForSelection(location)
                isAssigningLocation = false
                searchMessage =
                    "Location set for \(targetCount) selected photo\(targetCount == 1 ? "" : "s")."
            },
            onSelectPhotoGroup: { group in
                select(group)
            },
            onFocusSavedLocation: { id in
                library.focusSavedMapLocation(id)
            }
        )
        .overlay {
            if isAssigningLocation {
                RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
                    .stroke(
                        RAWDeskTokens.ColorToken.selection,
                        style: StrokeStyle(
                            lineWidth: 3,
                            dash: [7, 5]
                        )
                    )
                    .padding(RAWDeskTokens.Spacing.small)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var mapStatusOverlay: some View {
        if let progress =
                library.locationMetadataRefreshProgress {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                ProgressView(value: progress.fraction)
                    .frame(width: 70)
                Text(
                    "Reading GPS \(progress.completed)/\(progress.total)"
                )
                    .monospacedDigit()
            }
            .font(RAWDeskTokens.Typography.metadata)
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.small
            )
            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            .background(
                RAWDeskTokens.ColorToken
                    .controlElevated,
                in: RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.control
                )
            )
            .padding(RAWDeskTokens.Spacing.medium)
        } else if let searchMessage {
            Text(searchMessage)
                .font(RAWDeskTokens.Typography.metadata)
                .padding(
                    .horizontal,
                    RAWDeskTokens.Spacing.small
                )
                .padding(
                    .vertical,
                    RAWDeskTokens.Spacing.xSmall
                )
                .background(
                    RAWDeskTokens.ColorToken
                        .controlElevated,
                    in: RoundedRectangle(
                        cornerRadius:
                            RAWDeskTokens.Radius
                                .control
                    )
                )
                .padding(RAWDeskTokens.Spacing.medium)
        } else if isAssigningLocation {
            Label(
                "Click anywhere to place \(library.locationMutationTargetCount) selected photo\(library.locationMutationTargetCount == 1 ? "" : "s")",
                systemImage: "mappin.and.ellipse"
            )
            .font(RAWDeskTokens.Typography.badge)
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.small
            )
            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            .background(
                RAWDeskTokens.ColorToken
                    .controlElevated,
                in: RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.control
                )
            )
            .padding(RAWDeskTokens.Spacing.medium)
        }
    }

    private var filmstrip: some View {
        VStack(spacing: 0) {
            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                HStack {
                    Label(
                        photoScope.name,
                        systemImage:
                            photoScope.systemImage
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .sectionHeader
                    )
                    Text("\(filmstripAssets.count)")
                        .font(
                            RAWDeskTokens.Typography
                                .metadata
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                        .monospacedDigit()
                    Spacer()
                    Text(
                        "\(locatedAssets.count) tagged · \(sourceAssets.count - locatedAssets.count) untagged"
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                    .monospacedDigit()
                }
                HStack {
                    Label(
                        "Location edits stay in the catalog; original EXIF is unchanged.",
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
                    Spacer()
                }
            }
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.medium
            )
            .padding(.vertical, RAWDeskTokens.Spacing.small)

            if filmstripAssets.isEmpty {
                VStack(
                    spacing:
                        RAWDeskTokens.Spacing.small
                ) {
                    Image(systemName: photoScope.systemImage)
                        .font(
                            RAWDeskTokens.Typography
                                .workspaceHeader
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                    Text(photoScope.emptyMessage)
                        .font(
                            RAWDeskTokens.Typography
                                .control
                        )
                    if photoScope == .untagged {
                        Text(
                            "Choose another filter or remove a photo’s location."
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(
                        spacing:
                            RAWDeskTokens.Spacing.small
                    ) {
                        ForEach(filmstripAssets) { asset in
                            ThumbnailCellView(
                                asset: asset,
                                isSelected:
                                    library.selectedIDs.contains(
                                        asset.id
                                    ),
                                isActive:
                                    library.selectionID
                                    == asset.id,
                                compareRole: nil,
                                surveyRole: nil,
                                pixelSize: 220,
                                duplicateGroupNumber: nil,
                                isDuplicateAnchor: false,
                                isInQuickCollection:
                                    library.isInQuickCollection(
                                        asset.id
                                    ),
                                isInPhotoCollection:
                                    library.isInAnyPhotoCollection(
                                        asset.id
                                    ),
                                cullingEvaluation: nil,
                                cullingAnalysis: nil,
                                cullingStackNumber: nil,
                                stackMembership: nil,
                                onStackToggle: {},
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
                            .frame(width: 124, height: 142)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(asset.filename)
                            .accessibilityValue(
                                asset.effectiveLocation.map {
                                    "Located at \($0.coordinateText)"
                                } ?? "No location"
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                library.select(asset.id)
                            }
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
                            .contextMenu {
                                if asset.effectiveLocation != nil {
                                    Button("Show Location") {
                                        library.select(asset.id)
                                        showSelectedOnMap()
                                    }
                                    Button("Remove Location") {
                                        library.select(asset.id)
                                        library
                                            .removeLocationFromSelection()
                                    }
                                } else {
                                    Button("Set Location on Map") {
                                        library.select(asset.id)
                                        isAssigningLocation = true
                                    }
                                }
                                if asset.userState.locationOverride
                                        != nil
                                    || asset.userState
                                        .locationIsRemoved {
                                    Button("Use Camera GPS") {
                                        library.select(asset.id)
                                        library
                                            .useEmbeddedLocationForSelection()
                                    }
                                }
                                Divider()
                                Button("Show in Finder") {
                                    NSWorkspace.shared
                                        .activateFileViewerSelecting(
                                            [asset.url]
                                        )
                                }
                            }
                        }
                    }
                    .padding(
                        .horizontal,
                        RAWDeskTokens.Spacing.small
                    )
                    .padding(
                        .bottom,
                        RAWDeskTokens.Spacing.small
                    )
                }
            }
        }
        .frame(minHeight: 172, idealHeight: 180, maxHeight: 210)
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    private func select(_ group: PhotoMapAnnotationGroup) {
        let currentIndex = library.selectionID.flatMap { current in
            group.assets.firstIndex(where: { $0.id == current })
        }
        let targetIndex = currentIndex.map {
            ($0 + 1) % group.assets.count
        } ?? 0
        let target = group.assets[targetIndex]
        let modifiers = NSEvent.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        library.select(
            target.id,
            extending: modifiers.contains(.command),
            range: modifiers.contains(.shift)
        )
    }

    private func showSelectedOnMap() {
        guard let location =
                library.selectedAsset?.effectiveLocation else {
            return
        }
        requestMapRegion(
            MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.025,
                    longitudeDelta: 0.025
                )
            )
        )
    }

    private func fitTracklog(_ tracklog: GPXTracklog) {
        let coordinates = tracklog.displayCoordinates
        guard !coordinates.isEmpty else { return }
        var minimumLatitude = coordinates[0].latitude
        var maximumLatitude = coordinates[0].latitude
        var minimumLongitude = coordinates[0].longitude
        var maximumLongitude = coordinates[0].longitude
        for coordinate in coordinates.dropFirst() {
            minimumLatitude = min(
                minimumLatitude,
                coordinate.latitude
            )
            maximumLatitude = max(
                maximumLatitude,
                coordinate.latitude
            )
            minimumLongitude = min(
                minimumLongitude,
                coordinate.longitude
            )
            maximumLongitude = max(
                maximumLongitude,
                coordinate.longitude
            )
        }
        requestMapRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude:
                        (minimumLatitude + maximumLatitude) / 2,
                    longitude:
                        (minimumLongitude + maximumLongitude) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max(
                        0.01,
                        (maximumLatitude - minimumLatitude)
                            * 1.25
                    ),
                    longitudeDelta: max(
                        0.01,
                        (maximumLongitude - minimumLongitude)
                            * 1.25
                    )
                )
            )
        )
    }

    private func cameraRegion(
        for location: SavedMapLocation
    ) -> MKCoordinateRegion {
        let latitudeDelta = max(
            0.002,
            location.radiusMeters / 111_000 * 2.6
        )
        let longitudeScale = max(
            0.15,
            cos(
                location.center.latitude
                    * Double.pi / 180
            )
        )
        return MKCoordinateRegion(
            center: location.center.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta:
                    latitudeDelta / longitudeScale
            )
        )
    }

    private func search() {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        searchFocused = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let visibleRegion {
            request.region = visibleRegion
        }
        Task {
            defer { isSearching = false }
            do {
                let response = try await MKLocalSearch(
                    request: request
                ).start()
                guard let item = response.mapItems.first else {
                    searchMessage = "No matching place found."
                    return
                }
                requestMapRegion(
                    MKCoordinateRegion(
                        center: item.placemark.coordinate,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.04,
                            longitudeDelta: 0.04
                        )
                    )
                )
                searchMessage = item.name ?? query
            } catch {
                searchMessage =
                    "Map search failed: \(error.localizedDescription)"
            }
        }
    }

    private func requestMapRegion(
        _ region: MKCoordinateRegion
    ) {
        requestedRegion = region
        regionRequestID += 1
    }
}

struct LocationInspectorView: View {
    @ObservedObject var library: LibraryViewModel

    @ViewBuilder
    var body: some View {
        if library.selectedAsset == nil {
            Text("Select a photo to inspect its location.")
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        } else {
            SelectedLocationInspectorView(library: library)
        }
    }
}

private struct SelectedLocationInspectorView: View {
    @ObservedObject var library: LibraryViewModel

    @State private var latitude = ""
    @State private var longitude = ""
    @State private var altitude = ""
    @State private var validationMessage: String?

    private var asset: PhotoAsset? {
        library.selectedAsset
    }

    @ViewBuilder
    var body: some View {
        if let asset {
            selectedInspector(asset)
                .onAppear {
                    loadDraft()
                }
                .onChange(of: library.selectionID) { _, _ in
                    loadDraft()
                }
                .onChange(of: asset.effectiveLocation) { _, _ in
                    loadDraft()
                }
        } else {
            Text("Select a photo to inspect its location.")
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
    }

    private var inspectorHeader: some View {
        HStack {
            Label("Location", systemImage: "mappin.and.ellipse")
                .font(
                    RAWDeskTokens.Typography
                        .workspaceHeader
                )
            Spacer()
            if library.locationMutationTargetCount > 1 {
                Text(
                    "\(library.locationMutationTargetCount) selected"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
            }
        }
        .padding(
            .horizontal,
            RAWDeskTokens.Spacing.medium
        )
        .padding(.vertical, RAWDeskTokens.Spacing.small)
    }

    private func selectedInspector(
        _ asset: PhotoAsset
    ) -> some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: RAWDeskTokens.Spacing.large
                ) {
                    selectedPhotoHeader(asset)

                    VStack(
                        alignment: .leading,
                        spacing:
                            RAWDeskTokens.Spacing.small
                    ) {
                        Label(
                            asset.locationSource.name,
                            systemImage:
                                asset.locationSource.systemImage
                        )
                        .font(
                            RAWDeskTokens.Typography
                                .sectionHeader
                        )
                        .foregroundStyle(
                            asset.effectiveLocation == nil
                                ? RAWDeskTokens
                                    .ColorToken
                                    .textSecondary
                                : RAWDeskTokens.ColorToken.selection
                        )

                        if let location =
                                asset.effectiveLocation {
                            Text(location.coordinateText)
                                .font(
                                    RAWDeskTokens
                                        .Typography.numeric
                                )
                            if let altitudeText =
                                    location.altitudeText {
                                Text(altitudeText)
                                    .font(
                                        RAWDeskTokens
                                            .Typography
                                            .metadata
                                    )
                                    .foregroundStyle(
                                        RAWDeskTokens
                                            .ColorToken
                                            .textSecondary
                                    )
                            }
                        } else {
                            Text(
                                "This photo has no effective GPS coordinate."
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

                        if let privateLocation =
                                library.privateSavedLocation(
                                    containing: asset
                                ) {
                            Label(
                                "Private export · \(privateLocation.name)",
                                systemImage: "lock.fill"
                            )
                            .font(
                                RAWDeskTokens.Typography
                                    .badge
                            )
                            .foregroundStyle(
                                RAWDeskTokens.ColorToken
                                    .warning
                            )

                            Text(
                                "Photos inside this saved area omit location metadata when exported."
                            )
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
                    .padding(RAWDeskTokens.Spacing.medium)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background(
                        RAWDeskTokens.ColorToken
                            .controlElevated,
                        in: RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius
                                    .group
                        )
                    )
                    .accessibilityElement(children: .combine)

                    VStack(
                        alignment: .leading,
                        spacing:
                            RAWDeskTokens.Spacing.small
                    ) {
                        Text("Coordinates")
                            .font(
                                RAWDeskTokens.Typography
                                    .sectionHeader
                            )
                            .foregroundStyle(
                                RAWDeskTokens.ColorToken
                                    .textSecondary
                            )
                        coordinateField(
                            "Latitude",
                            text: $latitude,
                            prompt: "−90…90"
                        )
                        coordinateField(
                            "Longitude",
                            text: $longitude,
                            prompt: "−180…180"
                        )
                        coordinateField(
                            "Altitude",
                            text: $altitude,
                            prompt: "Optional metres"
                        )
                    }

                    if let validationMessage {
                        Label(
                            validationMessage,
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .font(
                            RAWDeskTokens.Typography
                                .metadata
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken.warning
                        )
                    }

                    Button {
                        applyCoordinates()
                    } label: {
                        Label(
                            library.locationMutationTargetCount > 1
                                ? "Apply to Selected Photos"
                                : "Apply Coordinates",
                            systemImage: "checkmark.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .rawPrimaryButtonHeight()

                    VStack(
                        spacing:
                            RAWDeskTokens.Spacing.small
                    ) {
                        Button("Remove Location") {
                            library.removeLocationFromSelection()
                            loadDraft()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(
                            asset.effectiveLocation == nil
                                && !asset.userState
                                    .locationIsRemoved
                        )

                        Button("Use Camera GPS") {
                            library
                                .useEmbeddedLocationForSelection()
                            loadDraft()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(
                            asset.userState.locationOverride == nil
                                && !asset.userState
                                    .locationIsRemoved
                        )
                    }

                    Text(
                        "RAWDesk keeps the camera’s embedded GPS intact. Manual coordinates and removals are nondestructive catalog changes, and exports use the effective location shown here."
                    )
                    .font(
                        RAWDeskTokens.Typography.metadata
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
                .padding(RAWDeskTokens.Spacing.medium)
            }
        }
    }

    private func selectedPhotoHeader(
        _ asset: PhotoAsset
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.xSmall
        ) {
            Text(asset.filename)
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
                .lineLimit(2)
                .truncationMode(.middle)
            Text(asset.url.deletingLastPathComponent().path)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func coordinateField(
        _ label: String,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.xSmall
        ) {
            Text(label)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
            TextField(prompt, text: text)
                .rawNumericField()
                .accessibilityLabel(label)
        }
    }

    private func loadDraft() {
        validationMessage = nil
        guard let location = asset?.effectiveLocation else {
            latitude = ""
            longitude = ""
            altitude = ""
            return
        }
        latitude = Self.decimal(location.latitude, digits: 6)
        longitude = Self.decimal(location.longitude, digits: 6)
        altitude = location.altitude.map {
            Self.decimal($0, digits: 1)
        } ?? ""
    }

    private func applyCoordinates() {
        let normalizedLatitude = latitude.replacingOccurrences(
            of: ",",
            with: "."
        )
        let normalizedLongitude = longitude.replacingOccurrences(
            of: ",",
            with: "."
        )
        let normalizedAltitude = altitude.replacingOccurrences(
            of: ",",
            with: "."
        )
        guard let latitudeValue = Double(normalizedLatitude),
              let longitudeValue = Double(
                  normalizedLongitude
              ) else {
            validationMessage =
                "Enter numeric latitude and longitude values."
            return
        }
        let altitudeValue: Double?
        if normalizedAltitude.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            altitudeValue = nil
        } else if let value = Double(normalizedAltitude) {
            altitudeValue = value
        } else {
            validationMessage =
                "Altitude must be a number of metres or left empty."
            return
        }
        guard let location = PhotoLocation(
            latitude: latitudeValue,
            longitude: longitudeValue,
            altitude: altitudeValue
        ) else {
            validationMessage =
                "Latitude must be −90…90 and longitude −180…180."
            return
        }
        library.setLocationForSelection(location)
        validationMessage = nil
        loadDraft()
    }

    private static func decimal(
        _ value: Double,
        digits: Int
    ) -> String {
        String(
            format: "%.\(digits)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

enum MapPhotoScope:
    String,
    CaseIterable,
    Identifiable
{
    case all
    case tagged
    case untagged
    case visible

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: return "All Photos"
        case .tagged: return "Tagged"
        case .untagged: return "Untagged"
        case .visible: return "Visible on Map"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "photo.on.rectangle.angled"
        case .tagged: return "mappin.and.ellipse"
        case .untagged: return "mappin.slash"
        case .visible: return "rectangle.dashed"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "No photos are visible."
        case .tagged: return "No photos have a location."
        case .untagged: return "Every visible photo has a location."
        case .visible: return "No photo pins are inside this map area."
        }
    }
}

enum MapDisplayStyle:
    String,
    CaseIterable,
    Identifiable
{
    case standard
    case hybrid
    case satellite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: return "Standard"
        case .hybrid: return "Hybrid"
        case .satellite: return "Satellite"
        }
    }
}

struct PhotoMapAnnotationGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let assets: [PhotoAsset]

    var accessibilityName: String {
        if assets.count == 1 {
            return assets[0].filename
        }
        return "\(assets.count) photos at this location"
    }

    var helpText: String {
        assets.prefix(5).map(\.filename)
            .joined(separator: "\n")
            + (assets.count > 5
                ? "\n…and \(assets.count - 5) more"
                : "")
    }

    static func groups(
        for assets: [PhotoAsset]
    ) -> [PhotoMapAnnotationGroup] {
        let grouped = Dictionary(grouping: assets) { asset in
            guard let location = asset.effectiveLocation else {
                return ""
            }
            let latitude = Int(
                (location.latitude * 100_000).rounded()
            )
            let longitude = Int(
                (location.longitude * 100_000).rounded()
            )
            return "\(latitude)|\(longitude)"
        }
        return grouped.compactMap { key, values in
            guard !key.isEmpty,
                  let first = values.first,
                  let coordinate =
                    first.effectiveLocation?.coordinate else {
                return nil
            }
            return PhotoMapAnnotationGroup(
                id: key,
                coordinate: coordinate,
                assets: values.sorted {
                    $0.filename.localizedStandardCompare(
                        $1.filename
                    ) == .orderedAscending
                }
            )
        }
        .sorted { $0.id < $1.id }
    }
}

private struct MapAssignmentButtonModifier:
    ViewModifier
{
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private extension MKCoordinateRegion {
    func contains(
        _ coordinate: CLLocationCoordinate2D
    ) -> Bool {
        let latitudeHalf = span.latitudeDelta / 2
        let longitudeHalf = span.longitudeDelta / 2
        let minimumLatitude = center.latitude - latitudeHalf
        let maximumLatitude = center.latitude + latitudeHalf
        guard coordinate.latitude >= minimumLatitude,
              coordinate.latitude <= maximumLatitude else {
            return false
        }
        let normalizedCenter = Self.normalizedLongitude(
            center.longitude
        )
        let normalizedCoordinate = Self.normalizedLongitude(
            coordinate.longitude
        )
        var distance = abs(
            normalizedCoordinate - normalizedCenter
        )
        if distance > 180 {
            distance = 360 - distance
        }
        return distance <= longitudeHalf
    }

    static func normalizedLongitude(
        _ longitude: Double
    ) -> Double {
        var value = longitude.truncatingRemainder(
            dividingBy: 360
        )
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}
