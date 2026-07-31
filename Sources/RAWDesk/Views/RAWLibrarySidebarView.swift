import AppKit
import SwiftUI

private struct RAWLibraryCollectionNode: Identifiable {
    enum Kind {
        case set(CatalogCollectionSet)
        case photo(CatalogPhotoCollection)
        case smart(SavedSmartCollection)
    }

    var kind: Kind
    var children: [RAWLibraryCollectionNode]?

    var id: String {
        switch kind {
        case let .set(value):
            return "set-\(value.id.uuidString)"
        case let .photo(value):
            return "photo-\(value.id.uuidString)"
        case let .smart(value):
            return "smart-\(value.id.uuidString)"
        }
    }
}

private enum RAWLibraryCollectionCreation: String, Identifiable {
    case photo
    case set
    case smart
    case quick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: return "New Collection"
        case .set: return "New Collection Set"
        case .smart: return "New Smart Collection"
        case .quick: return "Save Quick Collection"
        }
    }
}

private enum RAWLibraryCollectionDeletion: Identifiable {
    case set(CatalogCollectionSet)
    case photo(CatalogPhotoCollection)
    case smart(SavedSmartCollection)

    var id: String {
        switch self {
        case let .set(value):
            return "set-\(value.id.uuidString)"
        case let .photo(value):
            return "photo-\(value.id.uuidString)"
        case let .smart(value):
            return "smart-\(value.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case let .set(value): return value.name
        case let .photo(value): return value.name
        case let .smart(value): return value.name
        }
    }
}

/// The compact Library navigator used by the redesigned workspace.
///
/// It intentionally keeps the navigation surface to four persistent,
/// collapsible sections. The legacy sidebar remains available from the
/// toolbar rollback menu while the redesign is being verified.
struct RAWLibrarySidebarView: View {
    @ObservedObject var library: LibraryViewModel

    @AppStorage("rawdesk.library.sidebar.catalogExpanded")
    private var isCatalogExpanded = true
    @AppStorage("rawdesk.library.sidebar.collectionsExpanded")
    private var isCollectionsExpanded = true
    @AppStorage("rawdesk.library.sidebar.foldersExpanded")
    private var isFoldersExpanded = true
    @AppStorage("rawdesk.library.sidebar.servicesExpanded")
    private var isServicesExpanded = true

    @State private var collectionCreation:
        RAWLibraryCollectionCreation?
    @State private var collectionDeletion:
        RAWLibraryCollectionDeletion?
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var collectionTree: [RAWLibraryCollectionNode] {
        collectionNodes(parentSetID: nil, visited: [])
    }

    private var recentFolders: [URL] {
        library.recentFolders.filter {
            $0.standardizedFileURL.path
                != library.rootURL?.standardizedFileURL.path
        }
    }

    private var collectionCount: Int {
        library.collectionSets.count
            + library.photoCollections.count
            + library.savedSmartCollections.count
    }

    private var folderCount: Int {
        (library.rootURL == nil ? 0 : 1)
            + recentFolders.count
    }

    var body: some View {
        List {
            RAWSidebarSection(
                "Catalog",
                count:
                    library.catalogSummary[
                        .allPhotos
                    ],
                isExpanded: $isCatalogExpanded
            ) {
                catalogContents
            }

            RAWSidebarSection(
                "Collections",
                count: collectionCount,
                isExpanded: $isCollectionsExpanded
            ) {
                collectionsContents
            } trailing: {
                collectionActionsMenu
            }

            RAWSidebarSection(
                "Folders",
                count: folderCount,
                isExpanded: $isFoldersExpanded
            ) {
                foldersContents
            }

            RAWSidebarSection(
                "Services",
                isExpanded: $isServicesExpanded
            ) {
                servicesContents
            }
        }
        .listStyle(.sidebar)
        .rawPanelScrollBackground()
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 0.16),
            value: isCatalogExpanded
        )
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 0.16),
            value: isCollectionsExpanded
        )
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 0.16),
            value: isFoldersExpanded
        )
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 0.16),
            value: isServicesExpanded
        )
        .sheet(item: $collectionCreation) { creation in
            RAWLibraryCollectionCreationView(
                library: library,
                creation: creation
            ) {
                collectionCreation = nil
            }
        }
        .alert(
            "Delete Collection?",
            isPresented: Binding(
                get: { collectionDeletion != nil },
                set: {
                    if !$0 {
                        collectionDeletion = nil
                    }
                }
            ),
            presenting: collectionDeletion
        ) { deletion in
            Button("Cancel", role: .cancel) {
                collectionDeletion = nil
            }
            Button("Delete", role: .destructive) {
                performDeletion(deletion)
                collectionDeletion = nil
            }
        } message: { deletion in
            Text(
                "\(deletion.name) will be removed from the catalog organization. No photo or image file will be deleted."
            )
        }
    }

    /// The catalog queries that have nowhere else to be reached from.
    ///
    /// Eleven always-present rows pushed Collections and Folders below the
    /// fold. Picked, Rejected and Five Stars are gone because the Filter menu
    /// one control bar away already says exactly that
    /// (`LibraryFilter.flaggedOnly`, `.rejectedOnly`, Minimum Rating); With
    /// Location and Without Location are gone because the Map module already
    /// partitions on the same field. Edited and With Keywords stay — nothing
    /// else in the app reaches them. Duplicates and Assisted Culling are
    /// Services, and have always been listed there instead.
    private static let catalogCollections:
        [CatalogSmartCollection] = [
            .allPhotos,
            .recentlyAdded,
            .quickCollection,
            .edited,
            .withKeywords,
            .missingFiles,
        ]

    @ViewBuilder
    private var catalogContents: some View {
        ForEach(Self.catalogCollections) { collection in
            Button {
                library.showCatalog(collection)
            } label: {
                HStack(spacing: RAWDeskTokens.Spacing.small) {
                    Image(systemName: collection.systemImage)
                        .frame(width: 18)
                    Text(collection.name)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    let count =
                        library.catalogSummary[collection]
                    if count > 0 {
                        Text("\(count)")
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
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityLabel(
                                "Target collection"
                            )
                    }
                    if library.catalogCollection == collection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(collection.name)
            .accessibilityIdentifier(
                collection == .quickCollection
                    ? "Quick Collection"
                    : "Catalog \(collection.name)"
            )
        }

        if let error = library.catalogError {
            Label(
                error,
                systemImage: "exclamationmark.triangle"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.warning)
        }
    }

    @ViewBuilder
    private var collectionsContents: some View {
        if collectionTree.isEmpty {
            Text(
                "Create collections to keep selections without moving image files."
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            OutlineGroup(
                collectionTree,
                children: \.children
            ) { node in
                collectionRow(node)
            }
        }
    }

    @ViewBuilder
    private var foldersContents: some View {
        if let rootURL = library.rootURL {
            folderRow(
                rootURL,
                title: rootURL.lastPathComponent,
                systemImage: "folder.fill",
                isCurrent: true
            )
        }

        ForEach(recentFolders, id: \.self) { url in
            folderRow(
                url,
                title: url.lastPathComponent,
                systemImage: "clock.arrow.circlepath",
                isCurrent: false
            )
        }

        // Lives here rather than under Auto Import: it governs what happens
        // when a folder is opened, and opening a folder happens on this row.
        Toggle(
            "Include subfolders when opening",
            isOn: $library.recursiveScan
        )
        .help(
            "Open every photo beneath the chosen folder, not only the ones directly inside it"
        )

        Button {
            library.openFolderPicker()
        } label: {
            Label(
                "Open Folder…",
                systemImage: "folder.badge.plus"
            )
        }
        .buttonStyle(.plain)
        .help("Open photos in place without copying them")

        Button {
            library.presentImport()
        } label: {
            Label(
                "Import Photos…",
                systemImage: "tray.and.arrow.down"
            )
        }
        .buttonStyle(.plain)
        .help("Add, copy, or safely move photos into the catalog")
    }

    @ViewBuilder
    private var servicesContents: some View {
        serviceDisclosure(
            collection: .exactDuplicates,
            status: duplicateStatus,
            count:
                library.catalogSummary
                    .exactDuplicateGroupCount,
            progress:
                library.duplicateScanProgress?
                    .fractionCompleted
        ) {
            Button("Open Duplicate Review") {
                library.showCatalog(.exactDuplicates)
            }
            if library.catalogCollection == .exactDuplicates {
                Button("Verify Again") {
                    library.verifyExactDuplicatesAgain()
                }
            }
        }

        serviceDisclosure(
            collection: .assistedCulling,
            status: cullingStatus,
            count:
                library.cullingScanResult?
                    .candidateCount ?? 0,
            progress:
                library.cullingScanProgress?
                    .fractionCompleted
        ) {
            Button("Open Assisted Culling") {
                library.showCatalog(.assistedCulling)
            }
            if library.catalogCollection == .assistedCulling {
                Button("Analyze Again") {
                    library.verifyAssistedCullingAgain()
                }
            }
        }

        DisclosureGroup {
            Toggle(
                "Watch for new photos",
                isOn: Binding(
                    get: {
                        library.autoImportSettings.enabled
                    },
                    set: {
                        _ = library.setAutoImportEnabled($0)
                    }
                )
            )

            Text(library.autoImportStatus.message)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .fixedSize(horizontal: false, vertical: true)

            if let progress = library.autoImportProgress {
                ProgressView(
                    value: progress.fraction ?? 0
                )
                .accessibilityLabel(
                    progress.filename
                        ?? progress.phase.name
                )
            }

            HStack {
                Button("Settings…") {
                    library.presentAutoImportSettings()
                }
                Spacer()
                Button("Check Now") {
                    library.runAutoImportNow()
                }
                .disabled(
                    !library.autoImportSettings.enabled
                )
            }

            if !library.lastAutoImportAssets.isEmpty {
                Button("Show Last Import") {
                    library.showLastAutoImport()
                }
            }
        } label: {
            serviceLabel(
                title: "Auto Import",
                systemImage:
                    library.autoImportStatus.phase
                        .systemImage,
                status: autoImportStatus,
                count:
                    library.autoImportStatus
                        .pendingCount
            )
        }
        .accessibilityIdentifier("Auto Import service")
    }

    private var collectionActionsMenu: some View {
        Menu {
            Button("New Collection…") {
                collectionCreation = .photo
            }
            Button("New Collection Set…") {
                collectionCreation = .set
            }
            Button("New Smart Collection…") {
                collectionCreation = .smart
            }
            .disabled(!library.filter.isActive)
            Divider()
            Button("Save Quick Collection…") {
                collectionCreation = .quick
            }
            .disabled(
                library.catalogSummary[
                    .quickCollection
                ] == 0
            )
        } label: {
            Image(systemName: "plus")
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
        }
        .menuStyle(.borderlessButton)
        .rawIconButtonTarget()
        .fixedSize()
        .help("Create or save a collection")
        .accessibilityLabel("Collection actions")
    }

    @ViewBuilder
    private func collectionRow(
        _ node: RAWLibraryCollectionNode
    ) -> some View {
        switch node.kind {
        case let .set(collectionSet):
            Label(
                collectionSet.name,
                systemImage: "tray.full"
            )
            .lineLimit(1)
            .contextMenu {
                Button("Duplicate Collection Set") {
                    _ = library
                        .duplicateCollectionSet(collectionSet)
                }
                Button(
                    "Delete Collection Set",
                    role: .destructive
                ) {
                    collectionDeletion = .set(collectionSet)
                }
            }

        case let .photo(collection):
            Button {
                library.showPhotoCollection(collection)
            } label: {
                HStack {
                    Label(
                        collection.name,
                        systemImage: "rectangle.stack"
                    )
                    .lineLimit(1)
                    Spacer()
                    if collection.photoCount > 0 {
                        Text("\(collection.photoCount)")
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
                    if collection.isTarget {
                        Image(systemName: "plus")
                            .font(RAWDeskTokens.Typography.sectionHeader)
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityLabel(
                                "Target collection"
                            )
                    }
                    if library.activePhotoCollection?.id
                        == collection.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(
                    collection.isTarget
                        ? "Use Quick Collection as Target"
                        : "Set as Target Collection"
                ) {
                    _ = library.setTargetPhotoCollection(
                        collection.isTarget
                            ? nil
                            : collection
                    )
                }
                Button("Duplicate Collection") {
                    _ = library
                        .duplicatePhotoCollection(collection)
                }
                Button(
                    "Delete Collection",
                    role: .destructive
                ) {
                    collectionDeletion = .photo(collection)
                }
            }

        case let .smart(collection):
            Button {
                library.showSavedSmartCollection(collection)
            } label: {
                HStack {
                    Label(
                        collection.name,
                        systemImage:
                            "line.3.horizontal.decrease.circle"
                    )
                    .lineLimit(1)
                    Spacer()
                    if library.activeSavedCollection?.id
                        == collection.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Duplicate Smart Collection") {
                    _ = library
                        .duplicateSmartCollection(collection)
                }
                Button(
                    "Delete Smart Collection",
                    role: .destructive
                ) {
                    collectionDeletion = .smart(collection)
                }
            }
        }
    }

    private func folderRow(
        _ url: URL,
        title: String,
        systemImage: String,
        isCurrent: Bool
    ) -> some View {
        let exists =
            FileManager.default.fileExists(
                atPath: url.path
            )
        return Button {
            if !isCurrent {
                library.reopen(recent: url)
            }
        } label: {
            HStack {
                Label(
                    title.isEmpty ? url.path : title,
                    systemImage:
                        exists
                        ? systemImage
                        : "folder.badge.questionmark"
                )
                .lineLimit(1)
                Spacer()
                if isCurrent {
                    Text("Open")
                        .font(
                            RAWDeskTokens.Typography.badge
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .help(url.path)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared
                    .activateFileViewerSelecting([url])
            }
            .disabled(!exists)
            if !isCurrent {
                Button("Remove from Recent") {
                    library.removeRecent(url)
                }
            }
        }
    }

    private func serviceDisclosure<Content: View>(
        collection: CatalogSmartCollection,
        status: String,
        count: Int,
        progress: Double?,
        @ViewBuilder content:
            @escaping () -> Content
    ) -> some View {
        DisclosureGroup {
            // Where Auto Import already prints its own status. The collapsed
            // row carries it as a tooltip; opened, it is spelled out here.
            Text(status)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .fixedSize(horizontal: false, vertical: true)
            if let progress {
                ProgressView(value: progress)
                    .accessibilityLabel(
                        "\(collection.name) progress"
                    )
            }
            content()
        } label: {
            serviceLabel(
                title: collection.name,
                systemImage: collection.systemImage,
                status: status,
                count: count
            )
        }
        .accessibilityIdentifier(
            "Service \(collection.name)"
        )
    }

    private func serviceLabel(
        title: String,
        systemImage: String,
        status: String,
        count: Int
    ) -> some View {
        // One line, like every other navigator row. The status line made each
        // of the three Services rows twice the height of a Catalog row for a
        // sentence that is unchanged most of the time; it is now the row's
        // tooltip, and it is printed in full when the row is expanded.
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
                .lineLimit(1)
                .accessibilityLabel(
                    Text("\(title), \(status)")
                )
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                    .monospacedDigit()
            }
        }
        .help(status)
    }

    private var duplicateStatus: String {
        if library.duplicateScanProgress != nil {
            return "Analyzing locally"
        }
        let count =
            library.catalogSummary
                .exactDuplicateGroupCount
        return count == 0
            ? "Not analyzed"
            : "\(count) verified group\(count == 1 ? "" : "s")"
    }

    private var cullingStatus: String {
        if library.cullingScanProgress != nil {
            return "Analyzing locally"
        }
        guard let result = library.cullingScanResult else {
            return "Not analyzed"
        }
        return
            "\(result.analyzedCount) analyzed · "
            + "\(result.candidateCount) candidates"
    }

    private var autoImportStatus: String {
        guard library.autoImportSettings.enabled else {
            return "Off"
        }
        if let watched =
            library.autoImportSettings
                .watchedFolderURL {
            return "Watching \(watched.lastPathComponent)"
        }
        return library.autoImportStatus.phase.name
    }

    private func collectionNodes(
        parentSetID: UUID?,
        visited: Set<UUID>
    ) -> [RAWLibraryCollectionNode] {
        var nodes: [RAWLibraryCollectionNode] = []
        for collectionSet in
            library.collectionSets(in: parentSetID) {
            guard !visited.contains(collectionSet.id) else {
                continue
            }
            var nextVisited = visited
            nextVisited.insert(collectionSet.id)
            let children = collectionNodes(
                parentSetID: collectionSet.id,
                visited: nextVisited
            )
            nodes.append(
                RAWLibraryCollectionNode(
                    kind: .set(collectionSet),
                    children:
                        children.isEmpty
                        ? nil
                        : children
                )
            )
        }
        nodes.append(
            contentsOf:
                library.photoCollections(
                    in: parentSetID
                ).map {
                    RAWLibraryCollectionNode(
                        kind: .photo($0),
                        children: nil
                    )
                }
        )
        nodes.append(
            contentsOf:
                library.smartCollections(
                    in: parentSetID
                ).map {
                    RAWLibraryCollectionNode(
                        kind: .smart($0),
                        children: nil
                    )
                }
        )
        return nodes
    }

    private func performDeletion(
        _ deletion: RAWLibraryCollectionDeletion
    ) {
        switch deletion {
        case let .set(value):
            library.deleteCollectionSet(value)
        case let .photo(value):
            library.deletePhotoCollection(value)
        case let .smart(value):
            library.deleteSmartCollection(value)
        }
    }
}

private struct RAWLibraryCollectionCreationView:
    View {
    @ObservedObject var library: LibraryViewModel
    let creation: RAWLibraryCollectionCreation
    let onDismiss: () -> Void

    @State private var name = ""
    @State private var parentSetID: UUID?
    @State private var includeSelectedPhotos = true
    @State private var clearQuickCollection = false

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
            Text(creation.title)
                .font(RAWDeskTokens.Typography.workspaceHeader)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker(
                "Collection Set",
                selection: $parentSetID
            ) {
                Text("None").tag(UUID?.none)
                ForEach(
                    library
                        .availableParentCollectionSets()
                ) { collectionSet in
                    Text(
                        library.collectionSetPath(
                            collectionSet
                        )
                    )
                    .tag(Optional(collectionSet.id))
                }
            }

            if creation == .photo {
                Toggle(
                    "Include selected photos",
                    isOn: $includeSelectedPhotos
                )
            }

            if creation == .quick {
                Toggle(
                    "Clear Quick Collection after saving",
                    isOn: $clearQuickCollection
                )
            }

            if creation == .smart {
                Text(
                    "The current search and filters will remain live as the catalog changes."
                )
                .font(
                    RAWDeskTokens.Typography.metadata
                )
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
            } else {
                Text(
                    "This changes catalog organization only. No image file will be moved, copied, or deleted."
                )
                .font(
                    RAWDeskTokens.Typography.metadata
                )
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onDismiss)
                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedName.isEmpty)
            }
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(width: 420)
    }

    private var normalizedName: String {
        name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func create() {
        let result: Any?
        switch creation {
        case .photo:
            result = library.createPhotoCollection(
                named: normalizedName,
                parentSetID: parentSetID,
                includeSelectedPhotos:
                    includeSelectedPhotos
            )
        case .set:
            result = library.createCollectionSet(
                named: normalizedName,
                parentSetID: parentSetID
            )
        case .smart:
            result = library
                .saveCurrentFilterAsSmartCollection(
                    named: normalizedName,
                    parentSetID: parentSetID
                )
        case .quick:
            result = library.saveQuickCollection(
                named: normalizedName,
                parentSetID: parentSetID,
                clearAfterSaving:
                    clearQuickCollection
            )
        }
        if result != nil {
            onDismiss()
        }
    }
}
