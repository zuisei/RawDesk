import SwiftUI
import AppKit

private struct SavedLocationFolderGroup: Identifiable {
    var name: String
    var locations: [SavedMapLocation]
    var id: String { name }
}

private struct CollectionSidebarNode: Identifiable {
    enum Kind {
        case collectionSet(CatalogCollectionSet)
        case photoCollection(CatalogPhotoCollection)
        case smartCollection(SavedSmartCollection)
    }

    var kind: Kind
    var children: [CollectionSidebarNode]?

    var id: String {
        switch kind {
        case let .collectionSet(value):
            return "set-\(value.id.uuidString)"
        case let .photoCollection(value):
            return "photo-\(value.id.uuidString)"
        case let .smartCollection(value):
            return "smart-\(value.id.uuidString)"
        }
    }

    var name: String {
        switch kind {
        case let .collectionSet(value):
            return value.name
        case let .photoCollection(value):
            return value.name
        case let .smartCollection(value):
            return value.name
        }
    }
}

private enum CatalogCollectionEditorMode {
    case createPhoto(parentSetID: UUID?)
    case editPhoto(CatalogPhotoCollection)
    case editSmart(SavedSmartCollection)
    case createSet(parentSetID: UUID?)
    case editSet(CatalogCollectionSet)
    case saveQuick(parentSetID: UUID?)
}

private struct CatalogCollectionEditorRequest: Identifiable {
    var id = UUID()
    var mode: CatalogCollectionEditorMode
}

private enum CatalogCollectionDeletionKind {
    case collectionSet(CatalogCollectionSet)
    case photoCollection(CatalogPhotoCollection)
    case smartCollection(SavedSmartCollection)
}

private struct CatalogCollectionDeletionRequest: Identifiable {
    var id = UUID()
    var kind: CatalogCollectionDeletionKind
}

struct LibrarySidebarView: View {
    @State private var showingSaveSmartCollection = false
    @State private var smartCollectionName = ""
    @State private var smartCollectionParentSetID: UUID?
    @State private var collectionEditorRequest:
        CatalogCollectionEditorRequest?
    @State private var collectionDeletionRequest:
        CatalogCollectionDeletionRequest?
    @State private var keywordManagementRequest:
        KeywordManagementRequest?
    @State private var keywordExportSettingsNode:
        KeywordSummaryNode?

    private func displayName(for url: URL) -> String {
        let last = url.lastPathComponent
        if last.isEmpty || last == "/" { return url.path }
        return last
    }

    @ObservedObject var library: LibraryViewModel
    @ObservedObject var people: PeopleViewModel

    private var savedLocationFolders:
        [SavedLocationFolderGroup] {
        Dictionary(
            grouping: library.savedMapLocations,
            by: \.folder
        )
        .map {
            SavedLocationFolderGroup(
                name: $0.key,
                locations: $0.value.sorted {
                    $0.name.localizedStandardCompare(
                        $1.name
                    ) == .orderedAscending
                }
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    private var displayedPeopleCount: Int {
        people.lastScanResult == nil
            ? library.catalogSummary.peopleCount
            : people.namedPersonCount
    }

    private var collectionTree: [CollectionSidebarNode] {
        collectionNodes(parentSetID: nil, visited: [])
    }

    private func collectionNodes(
        parentSetID: UUID?,
        visited: Set<UUID>
    ) -> [CollectionSidebarNode] {
        var result: [CollectionSidebarNode] = []
        for collectionSet in library.collectionSets(
            in: parentSetID
        ) {
            guard !visited.contains(collectionSet.id) else {
                continue
            }
            var nextVisited = visited
            nextVisited.insert(collectionSet.id)
            let children = collectionNodes(
                parentSetID: collectionSet.id,
                visited: nextVisited
            )
            result.append(CollectionSidebarNode(
                kind: .collectionSet(collectionSet),
                children: children.isEmpty ? nil : children
            ))
        }
        result.append(
            contentsOf:
                library.photoCollections(in: parentSetID).map {
                    CollectionSidebarNode(
                        kind: .photoCollection($0),
                        children: nil
                    )
                }
        )
        result.append(
            contentsOf:
                library.smartCollections(in: parentSetID).map {
                    CollectionSidebarNode(
                        kind: .smartCollection($0),
                        children: nil
                    )
                }
        )
        return result
    }

    var body: some View {
        List {
            Section("Catalog") {
                ForEach(
                    CatalogSmartCollection.allCases.filter {
                        $0 != .assistedCulling
                            && $0 != .exactDuplicates
                    }
                ) { collection in
                    Button {
                        library.showCatalog(collection)
                    } label: {
                        HStack {
                            Image(systemName: collection.systemImage)
                                .frame(width: 18)
                            Text(collection.name)
                            Spacer()
                            if collection == .exactDuplicates,
                               let progress =
                                   library.duplicateScanProgress {
                                ProgressView(
                                    value: progress.fractionCompleted
                                )
                                .frame(width: 34)
                                .controlSize(.mini)
                                .accessibilityLabel(
                                    Text("Duplicate scan progress")
                                )
                            } else if collection == .assistedCulling,
                                      let progress =
                                          library.cullingScanProgress {
                                ProgressView(
                                    value: progress.fractionCompleted
                                )
                                .frame(width: 34)
                                .controlSize(.mini)
                                .accessibilityLabel(
                                    Text("Assisted Culling progress")
                                )
                            } else if
                                library.catalogSummary[
                                    collection
                                ] > 0 {
                                Text(
                                    "\(library.catalogSummary[collection])"
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
                            if collection == .quickCollection,
                               library.targetPhotoCollection == nil {
                                Image(systemName: "plus")
                                    .font(RAWDeskTokens.Typography.sectionHeader)
                                    .foregroundStyle(
                                        RAWDeskTokens.ColorToken.selection
                                    )
                                    .accessibilityLabel(
                                        "Target Collection"
                                    )
                            }
                            if library.catalogCollection == collection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(
                        collection == .quickCollection
                            ? (
                                library.targetPhotoCollection.map {
                                    "B currently targets \($0.name)"
                                }
                                ?? "Target Collection · press B to add or remove"
                            )
                            : collection.name
                    )
                    .contextMenu {
                        if collection == .quickCollection {
                            Button("Save Quick Collection…") {
                                collectionEditorRequest =
                                    CatalogCollectionEditorRequest(
                                        mode: .saveQuick(
                                            parentSetID: nil
                                        )
                                    )
                            }
                            .disabled(
                                library.catalogSummary[
                                    .quickCollection
                                ] == 0
                            )
                            Button("Clear Quick Collection") {
                                _ = library.clearQuickCollection()
                            }
                            .disabled(
                                library.catalogSummary[
                                    .quickCollection
                                ] == 0
                            )
                        }
                    }
                    .accessibilityIdentifier(
                        collection == .quickCollection
                            ? "Quick Collection"
                            : "Catalog \(collection.name)"
                    )
                }

                if let error = library.catalogError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                }
            }

            Section {
                if savedLocationFolders.isEmpty {
                    Text(
                        "Save a map area for quick navigation or private export."
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                } else {
                    ForEach(savedLocationFolders) { folder in
                        DisclosureGroup(folder.name) {
                            ForEach(folder.locations) { location in
                                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: {
                                                location.isVisible
                                            },
                                            set: { visible in
                                                library
                                                    .setSavedMapLocationVisible(
                                                        location.id,
                                                        visible:
                                                            visible
                                                    )
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .help(
                                        location.isVisible
                                            ? "Hide on map"
                                            : "Show on map"
                                    )

                                    Button {
                                        library
                                            .focusSavedMapLocation(
                                                location.id
                                            )
                                    } label: {
                                        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                                            Image(
                                                systemName:
                                                    location
                                                        .isPrivate
                                                    ? "lock.fill"
                                                    : "mappin"
                                            )
                                            .foregroundStyle(
                                                location.isPrivate
                                                    ? RAWDeskTokens
                                                        .ColorToken
                                                        .warning
                                                    : RAWDeskTokens
                                                        .ColorToken
                                                        .selection
                                            )
                                            Text(location.name)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(
                                                systemName:
                                                    "chevron.right"
                                            )
                                            .font(RAWDeskTokens.Typography.badge)
                                            .foregroundStyle(
                                                RAWDeskTokens
                                                    .ColorToken
                                                    .textSecondary
                                            )
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(
                                            "Location Options…"
                                        ) {
                                            library
                                                .presentSavedMapLocationEditor(
                                                    location
                                                )
                                        }
                                        Button(
                                            "Delete Saved Location",
                                            role: .destructive
                                        ) {
                                            library
                                                .deleteSavedMapLocation(
                                                    location.id
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Saved Locations")
                    Spacer()
                    Button {
                        _ = library
                            .presentNewSavedMapLocation()
                    } label: {
                        Image(systemName: "plus")
                            .font(RAWDeskTokens.Typography.metadata)
                    }
                    .buttonStyle(.plain)
                    .rawIconButtonTarget()
                    .disabled(
                        library.selectedAsset?
                            .effectiveLocation == nil
                    )
                    .help(
                        "Create a saved location around the selected photo"
                    )
                    .accessibilityLabel(
                        "Create a saved location around the selected photo"
                    )
                }
            }

            Section {
                if collectionTree.isEmpty {
                    Text(
                        "Create a collection, collection set, or live smart collection."
                    )
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                } else {
                    OutlineGroup(
                        collectionTree,
                        children: \.children
                    ) { node in
                        collectionNodeRow(node)
                    }
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Menu {
                        Button("New Collection…") {
                            collectionEditorRequest =
                                CatalogCollectionEditorRequest(
                                    mode: .createPhoto(
                                        parentSetID: nil
                                    )
                                )
                        }
                        Button("New Collection Set…") {
                            collectionEditorRequest =
                                CatalogCollectionEditorRequest(
                                    mode: .createSet(
                                        parentSetID: nil
                                    )
                                )
                        }
                        Button("New Smart Collection…") {
                            smartCollectionName =
                                suggestedCollectionName
                            smartCollectionParentSetID = nil
                            showingSaveSmartCollection = true
                        }
                        .disabled(!library.filter.isActive)
                        Divider()
                        Button("Save Quick Collection…") {
                            collectionEditorRequest =
                                CatalogCollectionEditorRequest(
                                    mode: .saveQuick(
                                        parentSetID: nil
                                    )
                                )
                        }
                        .disabled(
                            library.catalogSummary[
                                .quickCollection
                            ] == 0
                        )
                    } label: {
                        Image(systemName: "plus")
                            .font(RAWDeskTokens.Typography.metadata)
                    }
                    .menuStyle(.borderlessButton)
                    .rawIconButtonTarget()
                    .fixedSize()
                    .help("Create or save a collection")
                    .accessibilityLabel(
                        "Create or save a collection"
                    )
                }
            }

            Section("Folders") {
                Button {
                    library.showPeople()
                    people.startIfNeeded()
                } label: {
                    HStack {
                        Label("People", systemImage: "person.2")
                        Spacer()
                        if displayedPeopleCount > 0 {
                            Text(
                                "\(displayedPeopleCount)"
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
                        if library.workspaceMode == .people {
                            Image(systemName: "checkmark")
                                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Show People")

                Button {
                    library.showMap()
                } label: {
                    HStack {
                        Label("Map", systemImage: "map")
                        Spacer()
                        if library.workspaceMode == .map {
                            Image(systemName: "checkmark")
                                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("Show Map")

                Button {
                    library.presentImport()
                } label: {
                    Label(
                        "Import Photos…",
                        systemImage: "tray.and.arrow.down"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Import photos"))

                Button {
                    library.openFolderPicker()
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open folder"))

                Toggle("Recursive scan", isOn: $library.recursiveScan)
                    .toggleStyle(.switch)
            }

            Section("Services") {
                serviceCatalogButton(
                    .exactDuplicates
                )
                serviceCatalogButton(
                    .assistedCulling
                )

                Divider()

                Toggle(
                    isOn: Binding(
                        get: {
                            library.autoImportSettings.enabled
                        },
                        set: {
                            _ = library.setAutoImportEnabled($0)
                        }
                    )
                ) {
                    Label(
                        library.autoImportStatus.phase.name,
                        systemImage:
                            library.autoImportStatus.phase
                                .systemImage
                    )
                    .foregroundStyle(autoImportStatusColor)
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier(
                    "Auto Import sidebar toggle"
                )

                Text(library.autoImportStatus.message)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .lineLimit(3)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .accessibilityIdentifier(
                        "Auto Import status"
                    )

                if let progress = library.autoImportProgress {
                    VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                        ProgressView(
                            value: progress.fraction ?? 0
                        )
                        HStack {
                            Text(
                                progress.filename
                                    ?? progress.phase.name
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                            Spacer()
                            if progress.total > 0 {
                                Text(
                                    "\(progress.completed)/\(progress.total)"
                                )
                                .monospacedDigit()
                            }
                        }
                        .font(RAWDeskTokens.Typography.badge)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }
                }

                HStack {
                    Button("Settings…") {
                        library.presentAutoImportSettings()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)

                    Spacer()

                    Button("Check Now") {
                        library.runAutoImportNow()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                    .disabled(
                        !library.autoImportSettings.enabled
                    )
                }

                if !library.lastAutoImportAssets.isEmpty {
                    Button {
                        library.showLastAutoImport()
                    } label: {
                        HStack {
                            Label(
                                "Last Auto Import",
                                systemImage: "clock.arrow.circlepath"
                            )
                            Spacer()
                            Text(
                                "\(library.lastAutoImportAssets.count)"
                            )
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                            .monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Filters") {
                let filters: [LibraryFilter] = LibraryFilter.allCases
                ForEach(filters, id: \.self) { (filter: LibraryFilter) in
                    Button {
                        library.filter.primary = filter
                    } label: {
                        HStack {
                            Image(systemName: icon(for: filter))
                                .frame(width: 18)
                            Text(filter.displayName)
                            Spacer()
                            if library.filter.primary == filter {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Text("Min rating")
                    Spacer()
                    Stepper("\(library.filter.minimumRating)",
                            value: $library.filter.minimumRating, in: 0...5)
                        .labelsHidden()
                    Text("\(library.filter.minimumRating)★")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    HStack {
                        Text("Color labels")
                        Spacer()
                        Button(library.activeColorLabelSet.name) {
                            library.isColorLabelSetEditorPresented = true
                        }
                        .buttonStyle(.plain)
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .help("Edit color-label sets")
                        if !library.filter.colorLabels.isEmpty {
                            Button("Any") {
                                library.filter.colorLabels = []
                            }
                            .buttonStyle(.plain)
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .help("Show every color label")
                        }
                    }
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(
                                .flexible(),
                                spacing: RAWDeskTokens.Spacing.xSmall
                            ),
                            count: PhotoColorLabel.allCases.count
                        ),
                        spacing: RAWDeskTokens.Spacing.xSmall
                    ) {
                        ForEach(PhotoColorLabel.allCases) { label in
                            ColorLabelFilterButton(
                                label: label,
                                displayName:
                                    label == .none
                                    ? "Unlabeled"
                                    : library.colorLabelName(
                                        for: label
                                    ),
                                isSelected:
                                    library.filter.colorLabels
                                        .contains(label),
                                count:
                                    library.catalogSummary
                                        .colorLabelCounts[label] ?? 0
                            ) {
                                library.toggleColorLabelFilter(label)
                            }
                        }
                    }
                }

                if library.filter.isActive {
                    Button {
                        library.filter = FilterState()
                    } label: {
                        Label("Clear filters", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                }
            }

            if !library.catalogSummary.keywordCounts.isEmpty {
                Section("Keywords") {
                    OutlineGroup(
                        library.catalogSummary.keywordTree,
                        children: \.outlineChildren
                    ) { item in
                        Button {
                            library.filter.keyword =
                                library.filter.keyword == item.path
                                    ? nil
                                    : item.path
                        } label: {
                            HStack {
                                Image(
                                    systemName: item.children.isEmpty
                                        ? "tag"
                                        : "folder"
                                )
                                    .frame(width: 18)
                                Text(item.name)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(item.count)")
                                    .font(RAWDeskTokens.Typography.metadata)
                                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                                    .monospacedDigit()
                                if library.filter.keyword == item.path {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename Keyword…") {
                                keywordManagementRequest =
                                    KeywordManagementRequest(
                                        node: item,
                                        mode: .rename
                                    )
                            }
                            Button("Move or Merge Hierarchy…") {
                                keywordManagementRequest =
                                    KeywordManagementRequest(
                                        node: item,
                                        mode: .moveOrMerge
                                    )
                            }
                            Button("Synonyms & Export Settings…") {
                                keywordExportSettingsNode = item
                            }
                            Divider()
                            Button(
                                "Delete Hierarchy from Catalog…",
                                role: .destructive
                            ) {
                                keywordManagementRequest =
                                    KeywordManagementRequest(
                                        node: item,
                                        mode: .delete
                                    )
                            }
                        }
                    }
                }
            }

            let recents = library.recentFolders.filter { $0.path != library.rootURL?.path }
            if !recents.isEmpty {
                Section {
                    ForEach(recents, id: \.self) { url in
                        let exists = FileManager.default.fileExists(atPath: url.path)
                        Button {
                            library.reopen(recent: url)
                        } label: {
                            HStack {
                                Image(systemName: exists ? "folder" : "folder.badge.questionmark")
                                    .foregroundStyle(
                                        exists
                                            ? RAWDeskTokens
                                                .ColorToken
                                                .textPrimary
                                            : RAWDeskTokens
                                                .ColorToken
                                                .textSecondary
                                    )
                                Text(displayName(for: url))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(
                                        exists
                                            ? RAWDeskTokens
                                                .ColorToken
                                                .textPrimary
                                            : RAWDeskTokens
                                                .ColorToken
                                                .textSecondary
                                    )
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!exists)
                        .help(url.path)
                        .contextMenu {
                            Button("Remove from Recent") {
                                library.removeRecent(url)
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .disabled(!exists)
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Button {
                            library.clearRecents()
                        } label: {
                            Image(systemName: "trash")
                                .font(RAWDeskTokens.Typography.metadata)
                        }
                        .buttonStyle(.plain)
                        .rawIconButtonTarget()
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .help("Clear recent folders")
                        .accessibilityLabel(
                            "Clear recent folders"
                        )
                    }
                }
            }

            Section("Display") {
                if library.activePhotoCollection != nil {
                    HStack {
                        Label(
                            "Collection Order",
                            systemImage: "line.3.horizontal"
                        )
                        Spacer()
                        Text("User")
                            .font(RAWDeskTokens.Typography.metadata)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }
                    .help(
                        "Use a photo context menu to change its position"
                    )
                } else {
                    HStack {
                        Label(
                            "Sort",
                            systemImage: "arrow.up.arrow.down"
                        )
                        Spacer()
                        Picker("Sort", selection: $library.sort) {
                            ForEach(LibrarySort.allCases) { sort in
                                Text(sort.name).tag(sort)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 110)

                        Button {
                            library.sortAscending.toggle()
                        } label: {
                            Image(
                                systemName:
                                    library.sortAscending
                                    ? "arrow.up"
                                    : "arrow.down"
                            )
                        }
                        .buttonStyle(.plain)
                        .rawIconButtonTarget()
                        .help(
                            library.sortAscending
                                ? "Ascending"
                                : "Descending"
                        )
                        .accessibilityLabel(
                            library.sortAscending
                                ? "Sort ascending"
                                : "Sort descending"
                        )
                    }
                }

                HStack {
                    Image(systemName: "photo")
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
                    thumbnailPixelSizeField
                    Image(systemName: "photo.fill")
                }
            }
        }
        .listStyle(.sidebar)
        .rawPanelScrollBackground()
        .sheet(isPresented: $showingSaveSmartCollection) {
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
                Text("Save Smart Collection")
                    .font(RAWDeskTokens.Typography.workspaceHeader)
                Text(
                    "The current search, format, rating, and keyword filters will stay live as the catalog changes."
                )
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

                TextField("Collection name", text: $smartCollectionName)
                    .textFieldStyle(.roundedBorder)

                Picker(
                    "Collection Set",
                    selection: $smartCollectionParentSetID
                ) {
                    Text("None").tag(UUID?.none)
                    ForEach(
                        library.availableParentCollectionSets()
                    ) { collectionSet in
                        Text(
                            library.collectionSetPath(
                                collectionSet
                            )
                        )
                        .tag(Optional(collectionSet.id))
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingSaveSmartCollection = false
                    }
                    Button("Save") {
                        if library.saveCurrentFilterAsSmartCollection(
                            named: smartCollectionName,
                            parentSetID:
                                smartCollectionParentSetID
                        ) != nil {
                            showingSaveSmartCollection = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        smartCollectionName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }
            }
            .padding(RAWDeskTokens.Spacing.xLarge)
            .frame(width: 380)
        }
        .sheet(item: $collectionEditorRequest) { request in
            CatalogCollectionEditorView(
                library: library,
                request: request
            ) {
                collectionEditorRequest = nil
            }
        }
        .alert(item: $collectionDeletionRequest) { request in
            Alert(
                title: Text(
                    collectionDeletionTitle(for: request)
                ),
                message: Text(
                    "The collection organization will be removed, but no catalog photo or image file will be deleted."
                ),
                primaryButton: .destructive(
                    Text("Delete")
                ) {
                    performCollectionDeletion(request)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $keywordManagementRequest) { request in
            CatalogKeywordManagementView(
                library: library,
                request: request
            )
        }
        .sheet(item: $keywordExportSettingsNode) { node in
            CatalogKeywordExportSettingsView(
                library: library,
                node: node
            )
        }
    }

    private func serviceCatalogButton(
        _ collection: CatalogSmartCollection
    ) -> some View {
        Button {
            library.showCatalog(collection)
        } label: {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Image(systemName: collection.systemImage)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(collection.name)
                    Text(serviceStatus(for: collection))
                        .font(
                            RAWDeskTokens.Typography.metadata
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if collection == .exactDuplicates,
                   let progress =
                    library.duplicateScanProgress {
                    ProgressView(
                        value:
                            progress.fractionCompleted
                    )
                    .frame(width: 36)
                    .controlSize(.mini)
                } else if
                    collection == .assistedCulling,
                    let progress =
                        library.cullingScanProgress {
                    ProgressView(
                        value:
                            progress.fractionCompleted
                    )
                    .frame(width: 36)
                    .controlSize(.mini)
                } else if
                    serviceCount(for: collection) > 0 {
                    Text(
                        "\(serviceCount(for: collection))"
                    )
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                    .monospacedDigit()
                }
                if library.catalogCollection
                    == collection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken.selection
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collection.name)
        .accessibilityIdentifier(
            "Catalog \(collection.name)"
        )
    }

    private func serviceCount(
        for collection: CatalogSmartCollection
    ) -> Int {
        switch collection {
        case .exactDuplicates:
            return library.catalogSummary
                .exactDuplicateGroupCount
        case .assistedCulling:
            return library.cullingScanResult?
                .candidateCount ?? 0
        default:
            return 0
        }
    }

    private func serviceStatus(
        for collection: CatalogSmartCollection
    ) -> String {
        switch collection {
        case .exactDuplicates:
            let count = serviceCount(
                for: collection
            )
            return count == 0
                ? "Not analyzed"
                : "\(count) verified groups"
        case .assistedCulling:
            if let result =
                library.cullingScanResult {
                return
                    "\(result.analyzedCount) analyzed · "
                    + "\(result.candidateCount) candidates"
            }
            return "Analyze locally when opened"
        default:
            return ""
        }
    }

    @ViewBuilder
    private func collectionNodeRow(
        _ node: CollectionSidebarNode
    ) -> some View {
        switch node.kind {
        case let .collectionSet(collectionSet):
            HStack {
                Image(systemName: "tray.full")
                    .frame(width: 18)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                Text(collectionSet.name)
                    .lineLimit(1)
            }
            .contextMenu {
                Button("New Collection in Set…") {
                    collectionEditorRequest =
                        CatalogCollectionEditorRequest(
                            mode: .createPhoto(
                                parentSetID: collectionSet.id
                            )
                        )
                }
                Button("New Collection Set in Set…") {
                    collectionEditorRequest =
                        CatalogCollectionEditorRequest(
                            mode: .createSet(
                                parentSetID: collectionSet.id
                            )
                        )
                }
                Button("New Smart Collection in Set…") {
                    smartCollectionName =
                        suggestedCollectionName
                    smartCollectionParentSetID =
                        collectionSet.id
                    showingSaveSmartCollection = true
                }
                .disabled(!library.filter.isActive)
                Divider()
                Button("Duplicate Collection Set") {
                    _ = library
                        .duplicateCollectionSet(collectionSet)
                }
                Button("Rename or Move…") {
                    collectionEditorRequest =
                        CatalogCollectionEditorRequest(
                            mode: .editSet(collectionSet)
                        )
                }
                Button(
                    "Delete Collection Set",
                    role: .destructive
                ) {
                    collectionDeletionRequest =
                        CatalogCollectionDeletionRequest(
                            kind: .collectionSet(
                                collectionSet
                            )
                        )
                }
            }
            .draggable(
                "rawdesk-collection-set:\(collectionSet.id.uuidString)"
            )
            .dropDestination(for: String.self) { values, _ in
                handleCollectionDrop(
                    values,
                    into: collectionSet.id
                )
            }
            .accessibilityIdentifier(
                "Collection Set \(collectionSet.name)"
            )

        case let .photoCollection(collection):
            Button {
                library.showPhotoCollection(collection)
            } label: {
                HStack {
                    Image(systemName: "rectangle.stack")
                        .frame(width: 18)
                    Text(collection.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(collection.photoCount)")
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .monospacedDigit()
                    if collection.isTarget {
                        Image(systemName: "plus")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityLabel(
                                "Target Collection"
                            )
                    }
                    if library.activePhotoCollection?.id
                        == collection.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(
                    collection.isTarget
                        ? "Use Quick Collection as Target"
                        : "Set As Target Collection"
                ) {
                    _ = library.setTargetPhotoCollection(
                        collection.isTarget ? nil : collection
                    )
                }
                Divider()
                Button("Add Selected Photos") {
                    if let id = library.selectionID {
                        _ = library
                            .setPhotoCollectionMembership(
                                collection,
                                for: id,
                                included: true
                            )
                    }
                }
                .disabled(library.selectionID == nil)
                Button("Remove Selected Photos") {
                    if let id = library.selectionID {
                        _ = library
                            .setPhotoCollectionMembership(
                                collection,
                                for: id,
                                included: false
                            )
                    }
                }
                .disabled(library.selectionID == nil)
                Divider()
                Button("Duplicate Collection") {
                    _ = library
                        .duplicatePhotoCollection(collection)
                }
                Button("Rename or Move…") {
                    collectionEditorRequest =
                        CatalogCollectionEditorRequest(
                            mode: .editPhoto(collection)
                        )
                }
                Button(
                    "Delete Collection",
                    role: .destructive
                ) {
                    collectionDeletionRequest =
                        CatalogCollectionDeletionRequest(
                            kind: .photoCollection(
                                collection
                            )
                        )
                }
            }
            .draggable(
                "rawdesk-photo-collection:\(collection.id.uuidString)"
            )
            .dropDestination(for: String.self) { values, _ in
                handlePhotoDrop(
                    values,
                    into: collection
                )
            }
            .help(
                collection.isTarget
                    ? "Target Collection · press B to add or remove"
                    : collection.name
            )
            .accessibilityIdentifier(
                "Photo Collection \(collection.name)"
            )

        case let .smartCollection(collection):
            Button {
                library.showSavedSmartCollection(collection)
            } label: {
                HStack {
                    Image(
                        systemName:
                            "line.3.horizontal.decrease.circle"
                    )
                    .frame(width: 18)
                    Text(collection.name)
                        .lineLimit(1)
                    Spacer()
                    if library.activeSavedCollection?.id
                        == collection.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Menu("Move to Collection Set") {
                    Button {
                        _ = library.moveSmartCollection(
                            collection,
                            to: nil
                        )
                    } label: {
                        Label(
                            "None",
                            systemImage:
                                collection.parentSetID == nil
                                ? "checkmark"
                                : "tray"
                        )
                    }
                    ForEach(
                        library.availableParentCollectionSets()
                    ) { collectionSet in
                        Button {
                            _ = library.moveSmartCollection(
                                collection,
                                to: collectionSet.id
                            )
                        } label: {
                            Label(
                                library.collectionSetPath(
                                    collectionSet
                                ),
                                systemImage:
                                    collection.parentSetID
                                        == collectionSet.id
                                    ? "checkmark"
                                    : "tray"
                            )
                        }
                    }
                }
                Button("Duplicate Smart Collection") {
                    _ = library
                        .duplicateSmartCollection(collection)
                }
                Button("Rename or Move…") {
                    collectionEditorRequest =
                        CatalogCollectionEditorRequest(
                            mode: .editSmart(collection)
                        )
                }
                Button(
                    "Delete Smart Collection",
                    role: .destructive
                ) {
                    collectionDeletionRequest =
                        CatalogCollectionDeletionRequest(
                            kind: .smartCollection(
                                collection
                            )
                        )
                }
            }
            .draggable(
                "rawdesk-smart-collection:\(collection.id.uuidString)"
            )
            .accessibilityIdentifier(
                "Smart Collection \(collection.name)"
            )
        }
    }

    private func handlePhotoDrop(
        _ values: [String],
        into collection: CatalogPhotoCollection
    ) -> Bool {
        guard let value = values.first(where: {
            $0.hasPrefix("rawdesk-photo:")
        }) else {
            return false
        }
        let photoID = String(
            value.dropFirst("rawdesk-photo:".count)
        )
        _ = library.setPhotoCollectionMembership(
            collection,
            for: photoID,
            included: true
        )
        return true
    }

    private func handleCollectionDrop(
        _ values: [String],
        into parentSetID: UUID
    ) -> Bool {
        for value in values {
            if value.hasPrefix(
                "rawdesk-photo-collection:"
            ),
               let id = UUID(
                   uuidString: String(
                       value.dropFirst(
                           "rawdesk-photo-collection:".count
                       )
                   )
               ),
               let collection =
                   library.photoCollections.first(where: {
                       $0.id == id
                   }) {
                return library.updatePhotoCollection(
                    collection,
                    name: collection.name,
                    parentSetID: parentSetID
                )
            }
            if value.hasPrefix(
                "rawdesk-smart-collection:"
            ),
               let id = UUID(
                   uuidString: String(
                       value.dropFirst(
                           "rawdesk-smart-collection:".count
                       )
                   )
               ),
               let collection =
                   library.savedSmartCollections.first(where: {
                       $0.id == id
                   }) {
                return library.moveSmartCollection(
                    collection,
                    to: parentSetID
                )
            }
            if value.hasPrefix(
                "rawdesk-collection-set:"
            ),
               let id = UUID(
                   uuidString: String(
                       value.dropFirst(
                           "rawdesk-collection-set:".count
                       )
                   )
               ),
               let collectionSet =
                   library.collectionSets.first(where: {
                       $0.id == id
                   }) {
                return library.updateCollectionSet(
                    collectionSet,
                    name: collectionSet.name,
                    parentSetID: parentSetID
                )
            }
        }
        return false
    }

    private func collectionDeletionTitle(
        for request: CatalogCollectionDeletionRequest
    ) -> String {
        switch request.kind {
        case let .collectionSet(value):
            return "Delete “\(value.name)” and its contents?"
        case let .photoCollection(value):
            return "Delete “\(value.name)”?"
        case let .smartCollection(value):
            return "Delete “\(value.name)”?"
        }
    }

    private func performCollectionDeletion(
        _ request: CatalogCollectionDeletionRequest
    ) {
        switch request.kind {
        case let .collectionSet(value):
            library.deleteCollectionSet(value)
        case let .photoCollection(value):
            library.deletePhotoCollection(value)
        case let .smartCollection(value):
            library.deleteSmartCollection(value)
        }
    }

    private var autoImportStatusColor: Color {
        switch library.autoImportStatus.phase {
        case .attention:
            return RAWDeskTokens.ColorToken.warning
        case .watching:
            return RAWDeskTokens.ColorToken.success
        case .checking, .importing:
            return RAWDeskTokens.ColorToken.selection
        case .off, .settling:
            return RAWDeskTokens.ColorToken
                .textSecondary
        }
    }

    private var thumbnailPixelSizeField: some View {
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
        .rawNumericField(width: 48)
    }

    private var suggestedCollectionName: String {
        if !library.filter.colorLabels.isEmpty {
            let names = PhotoColorLabel.allCases.compactMap {
                library.filter.colorLabels.contains($0)
                    ? ($0 == .none
                        ? "Unlabeled"
                        : library.colorLabelName(for: $0))
                    : nil
            }
            return names.count == 1
                ? "\(names[0]) Photos"
                : "\(names.joined(separator: " + ")) Photos"
        }
        if let keyword = library.filter.keyword {
            return PhotoUserState.displayKeywordPath(keyword)
        }
        if library.filter.minimumRating > 0 {
            return "\(library.filter.minimumRating)+ Stars"
        }
        if library.filter.primary != .all {
            return library.filter.primary.displayName
        }
        let search = library.filter.searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return search.isEmpty ? "Smart Collection" : search
    }

    private func icon(for filter: LibraryFilter) -> String {
        switch filter {
        case .all: return "photo.stack"
        case .rawOnly: return "camera.aperture"
        case .sonyARWOnly: return "camera"
        case .canonCR2Only: return "camera"
        case .favoritesOnly: return "heart"
        case .flaggedOnly: return "flag"
        case .rejectedOnly: return "xmark.circle"
        case .errorsOnly: return "exclamationmark.triangle"
        }
    }
}

private struct CatalogCollectionEditorView: View {
    @ObservedObject var library: LibraryViewModel
    let request: CatalogCollectionEditorRequest
    let onDismiss: () -> Void

    @State private var name: String
    @State private var parentSetID: UUID?
    @State private var includeSelectedPhotos: Bool
    @State private var clearQuickCollection = false

    init(
        library: LibraryViewModel,
        request: CatalogCollectionEditorRequest,
        onDismiss: @escaping () -> Void
    ) {
        self.library = library
        self.request = request
        self.onDismiss = onDismiss
        switch request.mode {
        case let .createPhoto(parentSetID):
            _name = State(initialValue: "Collection")
            _parentSetID = State(initialValue: parentSetID)
            _includeSelectedPhotos = State(
                initialValue: library.selectionID != nil
            )
        case let .editPhoto(collection):
            _name = State(initialValue: collection.name)
            _parentSetID = State(
                initialValue: collection.parentSetID
            )
            _includeSelectedPhotos = State(initialValue: false)
        case let .editSmart(collection):
            _name = State(initialValue: collection.name)
            _parentSetID = State(
                initialValue: collection.parentSetID
            )
            _includeSelectedPhotos = State(initialValue: false)
        case let .createSet(parentSetID):
            _name = State(initialValue: "Collection Set")
            _parentSetID = State(initialValue: parentSetID)
            _includeSelectedPhotos = State(initialValue: false)
        case let .editSet(collectionSet):
            _name = State(initialValue: collectionSet.name)
            _parentSetID = State(
                initialValue: collectionSet.parentSetID
            )
            _includeSelectedPhotos = State(initialValue: false)
        case let .saveQuick(parentSetID):
            _name = State(initialValue: "Quick Collection")
            _parentSetID = State(initialValue: parentSetID)
            _includeSelectedPhotos = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
            Text(title)
                .font(RAWDeskTokens.Typography.workspaceHeader)
            Text(description)
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Collection Set", selection: $parentSetID) {
                Text("None").tag(UUID?.none)
                ForEach(availableCollectionSets) { collectionSet in
                    Text(library.collectionSetPath(collectionSet))
                        .tag(Optional(collectionSet.id))
                }
            }

            if case .createPhoto = request.mode {
                Toggle(
                    "Include selected photos",
                    isOn: $includeSelectedPhotos
                )
                .disabled(library.selectionID == nil)
            }

            if case .saveQuick = request.mode {
                Toggle(
                    "Clear Quick Collection after saving",
                    isOn: $clearQuickCollection
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onDismiss)
                Button(actionTitle) {
                    if save() {
                        onDismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(width: 420)
    }

    private var availableCollectionSets:
        [CatalogCollectionSet] {
        if case let .editSet(collectionSet) = request.mode {
            return library.availableParentCollectionSets(
                excludingSubtreeOf: collectionSet.id
            )
        }
        return library.availableParentCollectionSets()
    }

    private var title: String {
        switch request.mode {
        case .createPhoto:
            return "New Collection"
        case .editPhoto:
            return "Collection Options"
        case .editSmart:
            return "Smart Collection Options"
        case .createSet:
            return "New Collection Set"
        case .editSet:
            return "Collection Set Options"
        case .saveQuick:
            return "Save Quick Collection"
        }
    }

    private var actionTitle: String {
        switch request.mode {
        case .editPhoto, .editSmart, .editSet:
            return "Save"
        case .createPhoto, .createSet:
            return "Create"
        case .saveQuick:
            return "Save"
        }
    }

    private var description: String {
        switch request.mode {
        case .createPhoto:
            return "A regular collection groups catalog photos without moving or copying the source files."
        case .editPhoto:
            return "Rename the collection or move it into a collection set."
        case .editSmart:
            return "Rename the smart collection or move it into a collection set."
        case .createSet:
            return "A collection set organizes collections and can contain nested sets."
        case .editSet:
            return "Rename the set or move it within the collection hierarchy."
        case .saveQuick:
            return "Convert the current Quick Collection into a persistent regular collection."
        }
    }

    private func save() -> Bool {
        switch request.mode {
        case .createPhoto:
            return library.createPhotoCollection(
                named: name,
                parentSetID: parentSetID,
                includeSelectedPhotos: includeSelectedPhotos
            ) != nil
        case let .editPhoto(collection):
            return library.updatePhotoCollection(
                collection,
                name: name,
                parentSetID: parentSetID
            )
        case let .editSmart(collection):
            return library.updateSmartCollection(
                collection,
                name: name,
                parentSetID: parentSetID
            )
        case .createSet:
            return library.createCollectionSet(
                named: name,
                parentSetID: parentSetID
            ) != nil
        case let .editSet(collectionSet):
            return library.updateCollectionSet(
                collectionSet,
                name: name,
                parentSetID: parentSetID
            )
        case .saveQuick:
            return library.saveQuickCollection(
                named: name,
                parentSetID: parentSetID,
                clearAfterSaving: clearQuickCollection
            ) != nil
        }
    }
}

private enum KeywordManagementMode: String {
    case rename
    case moveOrMerge
    case delete

    var title: String {
        switch self {
        case .rename:
            return "Rename Keyword"
        case .moveOrMerge:
            return "Move or Merge Hierarchy"
        case .delete:
            return "Delete Keyword Hierarchy"
        }
    }
}

private struct KeywordManagementRequest: Identifiable {
    let id = UUID()
    var node: KeywordSummaryNode
    var mode: KeywordManagementMode
}

private struct CatalogKeywordManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryViewModel
    let request: KeywordManagementRequest

    @State private var newName: String
    @State private var destinationPath = ""
    @State private var preview: CatalogKeywordChangePreview?
    @State private var previewError: String?
    @State private var isLoadingPreview = false
    @State private var isApplying = false
    @State private var showingDeleteConfirmation = false

    init(
        library: LibraryViewModel,
        request: KeywordManagementRequest
    ) {
        self.library = library
        self.request = request
        _newName = State(initialValue: request.node.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
            HStack(spacing: RAWDeskTokens.Spacing.medium) {
                Image(systemName: headerIcon)
                    .font(RAWDeskTokens.Typography.modalTitle)
                    .foregroundStyle(
                        request.mode == .delete
                            ? RAWDeskTokens.ColorToken
                                .destructive
                            : RAWDeskTokens.ColorToken
                                .selection
                    )
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(request.mode.title)
                        .font(RAWDeskTokens.Typography.workspaceHeader)
                    Text(
                        PhotoUserState.displayKeywordPath(
                            request.node.path
                        )
                    )
                    .font(RAWDeskTokens.Typography.control)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
            }

            inputSection

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Text("Catalog impact")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                previewContent
            }
            .padding(RAWDeskTokens.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RAWDeskTokens.ColorToken.controlElevated,
                in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
            )

            Label(
                "This changes catalog metadata only. Image files and XMP sidecars stay untouched until you explicitly save XMP.",
                systemImage: "lock.doc"
            )
            .font(RAWDeskTokens.Typography.control)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)

                Spacer()

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(
                    actionButtonTitle,
                    role: request.mode == .delete ? .destructive : nil
                ) {
                    if request.mode == .delete {
                        showingDeleteConfirmation = true
                    } else {
                        Task { await applyChange() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(width: 520)
        .frame(minHeight: 440)
        .interactiveDismissDisabled(isApplying)
        .task(id: previewKey) {
            await refreshPreview(for: previewKey)
        }
        .alert(
            "Delete this keyword hierarchy?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete from Catalog", role: .destructive) {
                Task { await applyChange() }
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        switch request.mode {
        case .rename:
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Text("New name")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                TextField("Keyword name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Text(
                    "Descendant keywords keep their existing paths below this node. Renaming into an existing sibling merges exact duplicates."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        case .moveOrMerge:
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Text("New full hierarchy path")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                TextField(
                    "For example: Places > Europe",
                    text: $destinationPath
                )
                .textFieldStyle(.roundedBorder)
                Text(
                    "The selected node becomes this path. Descendants follow it, and an existing destination hierarchy is merged without duplicate assignments."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        case .delete:
            Text(
                "The selected node and every descendant assignment will be removed from all catalog photos. Photos, edits, ratings, notes, and files are preserved."
            )
            .font(RAWDeskTokens.Typography.control)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if isLoadingPreview {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking the complete catalog…")
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        } else if let previewError {
            Label(previewError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if let preview {
            if let destinationPath = preview.destinationPath {
                LabeledContent("Resulting hierarchy") {
                    Text(
                        PhotoUserState.displayKeywordPath(destinationPath)
                    )
                    .multilineTextAlignment(.trailing)
                }
            }
            LabeledContent("Photos") {
                Text("\(preview.affectedPhotoCount)")
                    .monospacedDigit()
            }
            LabeledContent("Assignments") {
                Text("\(preview.affectedKeywordAssignmentCount)")
                    .monospacedDigit()
            }
            LabeledContent("Hierarchy paths") {
                Text("\(preview.affectedKeywordPathCount)")
                    .monospacedDigit()
            }
            if preview.missingPhotoCount > 0 {
                LabeledContent("Missing-file records included") {
                    Text("\(preview.missingPhotoCount)")
                        .monospacedDigit()
                }
            }
            if preview.mergedAssignmentCount > 0 {
                LabeledContent("Duplicate assignments merged") {
                    Text("\(preview.mergedAssignmentCount)")
                        .monospacedDigit()
                }
            }
            if preview.affectedSmartCollectionCount > 0 {
                LabeledContent("Smart collections updated") {
                    Text("\(preview.affectedSmartCollectionCount)")
                        .monospacedDigit()
                }
            }
            if preview.affectedDefinitionCount > 0 {
                LabeledContent("Export definitions updated") {
                    Text("\(preview.affectedDefinitionCount)")
                        .monospacedDigit()
                }
            }
            if preview.affectedPhotoCount == 0
                && preview.affectedSmartCollectionCount == 0
                && preview.affectedDefinitionCount == 0 {
                Text("No matching catalog records remain.")
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        } else {
            Text("Enter a valid destination to preview the change.")
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
    }

    private var proposedChange: CatalogKeywordChange? {
        switch request.mode {
        case .rename:
            guard !newName.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                return nil
            }
            return .rename(
                sourcePath: request.node.path,
                newName: newName
            )
        case .moveOrMerge:
            guard !destinationPath.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                return nil
            }
            return .moveOrMerge(
                sourcePath: request.node.path,
                destinationPath: destinationPath
            )
        case .delete:
            return .delete(sourcePath: request.node.path)
        }
    }

    private var previewKey: String {
        [
            request.mode.rawValue,
            request.node.path,
            newName,
            destinationPath,
        ].joined(separator: "\u{1F}")
    }

    private var canApply: Bool {
        guard let preview,
              preview.affectedPhotoCount > 0
                || preview.affectedSmartCollectionCount > 0
                || preview.affectedDefinitionCount > 0 else {
            return false
        }
        return proposedChange != nil
            && previewError == nil
            && !isLoadingPreview
            && !isApplying
            && !library.isManagingKeywords
    }

    private var actionButtonTitle: String {
        switch request.mode {
        case .rename:
            return "Rename"
        case .moveOrMerge:
            return "Move or Merge"
        case .delete:
            return "Delete from Catalog…"
        }
    }

    private var headerIcon: String {
        switch request.mode {
        case .rename:
            return "pencil"
        case .moveOrMerge:
            return "arrow.triangle.merge"
        case .delete:
            return "trash"
        }
    }

    private var deleteConfirmationMessage: String {
        let count = preview?.affectedPhotoCount ?? 0
        return "Remove this hierarchy from \(count) catalog photo"
            + "\(count == 1 ? "" : "s")? Image files and XMP sidecars will not be changed."
    }

    @MainActor
    private func refreshPreview(for key: String) async {
        preview = nil
        previewError = nil
        guard let change = proposedChange else {
            isLoadingPreview = false
            return
        }
        isLoadingPreview = true
        do {
            try await Task.sleep(for: .milliseconds(160))
            let result = try await library.previewCatalogKeywordChange(
                change
            )
            guard !Task.isCancelled, key == previewKey else { return }
            preview = result
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, key == previewKey else { return }
            previewError = error.localizedDescription
        }
        if key == previewKey {
            isLoadingPreview = false
        }
    }

    @MainActor
    private func applyChange() async {
        guard let change = proposedChange, canApply else { return }
        isApplying = true
        previewError = nil
        do {
            _ = try await library.applyCatalogKeywordChange(change)
            dismiss()
        } catch {
            previewError = error.localizedDescription
            isApplying = false
            await refreshPreview(for: previewKey)
        }
    }
}

private struct CatalogKeywordExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: LibraryViewModel
    let node: KeywordSummaryNode

    @State private var synonymsText = ""
    @State private var includeOnExport = true
    @State private var exportSynonyms = true
    @State private var exportContainingKeywords = false
    @State private var isLoaded = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
            HStack(spacing: RAWDeskTokens.Spacing.medium) {
                Image(systemName: "tag.circle")
                    .font(RAWDeskTokens.Typography.modalTitle)
                    .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text("Synonyms & Export Settings")
                        .font(RAWDeskTokens.Typography.workspaceHeader)
                    Text(
                        PhotoUserState.displayKeywordPath(node.path)
                    )
                    .font(RAWDeskTokens.Typography.control)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
            }

            if let loadError {
                Label(
                    loadError,
                    systemImage: "exclamationmark.triangle"
                )
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(RAWDeskTokens.ColorToken.warning)
            }

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Text("Synonyms")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                TextEditor(text: $synonymsText)
                    .font(RAWDeskTokens.Typography.control)
                    .frame(height: 88)
                    .padding(RAWDeskTokens.Spacing.xSmall)
                    .background(
                        RAWDeskTokens.ColorToken
                            .controlElevated,
                        in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                            .stroke(
                                RAWDeskTokens.ColorToken.textPrimary.opacity(0.14),
                                lineWidth: 1
                            )
                    }
                Text(
                    "Separate synonyms with commas or new lines. Entries containing hierarchy separators are skipped."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Toggle(
                    "Include this keyword on export",
                    isOn: $includeOnExport
                )
                Toggle(
                    "Include synonyms on export",
                    isOn: $exportSynonyms
                )
                .disabled(!includeOnExport || synonyms.isEmpty)
                Toggle(
                    "Include containing hierarchy keywords",
                    isOn: $exportContainingKeywords
                )
                .disabled(!includeOnExport)
            }

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                Text("IPTC preview")
                    .font(RAWDeskTokens.Typography.sectionHeader)
                Text(exportPreview.isEmpty
                     ? "Nothing from this keyword will be exported."
                     : exportPreview.joined(separator: ", "))
                    .font(RAWDeskTokens.Typography.control)
                    .foregroundStyle(
                        exportPreview.isEmpty
                            ? RAWDeskTokens.ColorToken
                                .textSecondary
                            : RAWDeskTokens.ColorToken
                                .textPrimary
                    )
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(RAWDeskTokens.Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RAWDeskTokens.ColorToken.controlElevated,
                in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group)
            )

            Label(
                "These rules apply to exported image metadata where supported. Assignments and XMP sidecars are not changed.",
                systemImage: "square.and.arrow.up"
            )
            .font(RAWDeskTokens.Typography.control)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let definition = CatalogKeywordDefinition(
                        path: node.path,
                        synonyms: synonyms,
                        includeOnExport: includeOnExport,
                        exportSynonyms: exportSynonyms,
                        exportContainingKeywords:
                            exportContainingKeywords
                    )
                    if library.saveKeywordDefinition(definition) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isLoaded)
            }
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(width: 500)
        .task {
            guard !isLoaded else { return }
            do {
                let definition = try library.keywordDefinition(
                    for: node.path
                )
                synonymsText = definition.synonyms.joined(
                    separator: "\n"
                )
                includeOnExport = definition.includeOnExport
                exportSynonyms = definition.exportSynonyms
                exportContainingKeywords =
                    definition.exportContainingKeywords
                isLoaded = true
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var synonyms: [String] {
        let pieces = synonymsText.components(
            separatedBy: CharacterSet(charactersIn: ",\n")
        )
        return PhotoUserState.normalizedKeywordSynonyms(pieces)
    }

    private var exportPreview: [String] {
        guard includeOnExport else { return [] }
        var values = [PhotoUserState.keywordLeaf(node.path)]
        if exportSynonyms {
            values.append(contentsOf: synonyms)
        }
        if exportContainingKeywords {
            let segments = PhotoUserState.keywordSegments(in: node.path)
            values.append(contentsOf: segments.dropLast())
        }
        return PhotoUserState.normalizedKeywords(values)
    }
}
