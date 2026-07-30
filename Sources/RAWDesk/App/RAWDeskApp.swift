import SwiftUI
import AppKit

@main
struct RAWDeskApp: App {

    @FocusedObject private var library: LibraryViewModel?
    @FocusedObject private var viewer: PhotoViewerViewModel?

    var body: some Scene {
        WindowGroup("RAWDesk") {
            ContentView()
                // The unified title bar and toolbar add 52 points outside
                // the SwiftUI content. Keeping the content minimum at 648
                // makes the documented 1100 × 700 window size attainable.
                .frame(minWidth: 1100, minHeight: 648)
                // Native controls — segmented pickers, prominent buttons,
                // list selection — otherwise paint themselves with whatever
                // accent the user set in System Settings. The photograph has
                // to be the only saturated thing on screen, so they inherit
                // the app's own restrained selection colour instead.
                .tint(RAWDeskTokens.ColorToken.selection)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Edit") {
                    if let id = library?.selectionID {
                        library?.undoAdjustments(for: id)
                    }
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!(library?.canUndoAdjustments(for: library?.selectionID) ?? false))

                Button("Redo Edit") {
                    if let id = library?.selectionID {
                        library?.redoAdjustments(for: id)
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(library?.canRedoAdjustments(for: library?.selectionID) ?? false))
            }

            CommandGroup(replacing: .newItem) {
                Button("Import Photos…") {
                    library?.presentImport()
                }
                .keyboardShortcut(
                    "i",
                    modifiers: [.command, .shift]
                )
                .disabled(library == nil)

                Button("Open Folder…") {
                    library?.openFolderPicker()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(library == nil)

                Divider()

                Menu("Auto Import") {
                    Button(
                        library?.autoImportSettings.enabled == true
                            ? "Disable Auto Import"
                            : "Enable Auto Import"
                    ) {
                        let enabled =
                            library?.autoImportSettings.enabled
                                ?? false
                        _ = library?.setAutoImportEnabled(
                            !enabled
                        )
                    }
                    .disabled(library == nil)

                    Button("Process Stable Files Now") {
                        library?.runAutoImportNow()
                    }
                    .disabled(
                        library?.autoImportSettings.enabled
                            != true
                    )

                    Divider()

                    Button("Auto Import Settings…") {
                        library?.presentAutoImportSettings()
                    }
                    .disabled(library == nil)
                }
            }
            CommandGroup(after: .saveItem) {
                Button("Export…") {
                    NotificationCenter.default.post(name: .rawDeskExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }

            CommandMenu("Metadata") {
                Menu("Color Label Set") {
                    ForEach(
                        library?.colorLabelSets
                            ?? [PhotoColorLabelSet.standard]
                    ) { set in
                        Button {
                            library?.activateColorLabelSet(set.id)
                        } label: {
                            Label(
                                set.name,
                                systemImage:
                                    library?.activeColorLabelSetID
                                        == set.id
                                    ? "checkmark"
                                    : "paintpalette"
                            )
                        }
                    }
                    Divider()
                    Button("Edit Color Label Sets…") {
                        library?.isColorLabelSetEditorPresented = true
                    }
                }
                .disabled(library == nil)

                Divider()

                Button("Read Metadata from XMP Sidecar") {
                    library?.readMetadataFromXMPSidecars()
                }
                .disabled(library?.selectionID == nil)

                Button("Save Metadata to XMP Sidecar") {
                    library?.saveMetadataToXMPSidecars()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(library?.selectionID == nil)

                Divider()

                Button("Show Location on Map") {
                    library?.showMap()
                }
                .disabled(library?.selectionID == nil)

                Button("Remove Location") {
                    library?.removeLocationFromSelection()
                }
                .disabled(
                    library?.selectedAsset?.effectiveLocation == nil
                )

                Button("Use Camera GPS") {
                    library?.useEmbeddedLocationForSelection()
                }
                .disabled(
                    library?.selectedAsset?.userState
                        .locationOverride == nil
                        && library?.selectedAsset?.userState
                            .locationIsRemoved != true
                )
            }

            CommandMenu("Map") {
                Button("Show Map") {
                    library?.showMap()
                }
                .keyboardShortcut(
                    "3",
                    modifiers: [.command, .option]
                )
                .disabled(library == nil)

                Divider()

                Button("Load GPX Tracklog…") {
                    library?.loadGPXTracklogPicker()
                }
                .disabled(library == nil)

                Button("Tracklog Settings…") {
                    library?.isGPXTracklogPresented = true
                }
                .disabled(
                    library?.loadedGPXTracklog == nil
                )

                Button(
                    library?.isGPXTrackVisible == true
                        ? "Hide Tracklog"
                        : "Show Tracklog"
                ) {
                    guard let library else { return }
                    library.isGPXTrackVisible.toggle()
                }
                .disabled(
                    library?.loadedGPXTracklog == nil
                )

                Button(
                    "Auto-Tag \(library?.gpxAutoTagPreview?.matchedCount ?? 0) Photos"
                ) {
                    _ = library?.applyGPXAutoTag()
                }
                .disabled(
                    library?.gpxAutoTagPreview?
                        .matchedCount == 0
                )

                Divider()

                Button("New Saved Location…") {
                    _ = library?
                        .presentNewSavedMapLocation()
                }
                .disabled(
                    library?.selectedAsset?
                        .effectiveLocation == nil
                )
            }

            CommandMenu("Photo") {
                Button("Select All Visible Photos") {
                    library?.selectAllVisiblePhotos()
                }
                .disabled(
                    !(library?.canSelectAllVisiblePhotos ?? false)
                )

                Divider()

                Button(targetCollectionActionTitle) {
                    _ = library?
                        .toggleTargetCollectionForSelection()
                }
                .disabled(library?.selectionID == nil)

                Menu("Collections") {
                    ForEach(
                        library?.photoCollections ?? []
                    ) { collection in
                        Button {
                            guard let library,
                                  let id =
                                      library.selectionID else {
                                return
                            }
                            _ = library
                                .togglePhotoCollectionMembership(
                                    collection,
                                    for: id
                                )
                        } label: {
                            let included =
                                library?.selectionID.map {
                                    library?
                                        .isInPhotoCollection(
                                            $0,
                                            collectionID:
                                                collection.id
                                        ) == true
                                } ?? false
                            Label(
                                collection.name,
                                systemImage:
                                    included
                                    ? "checkmark"
                                    : "rectangle.stack"
                            )
                        }
                    }
                }
                .disabled(
                    library?.selectionID == nil
                        || library?.photoCollections.isEmpty != false
                )

                Divider()

                Menu("Set Color Label") {
                    PhotoColorLabelMenuItems(
                        current:
                            library?.selectedAsset?
                                .userState.colorLabel,
                        labelSet:
                            library?.activeColorLabelSet
                                ?? .standard,
                        editAction: {
                            library?
                                .isColorLabelSetEditorPresented = true
                        }
                    ) { label in
                        if let id = library?.selectionID {
                            library?.setColorLabel(label, for: id)
                        }
                    }
                }
                .disabled(library?.selectionID == nil)

                Divider()

                Button("Group into Stack") {
                    _ = library?.stackSelectedPhotos()
                }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(
                    !(library?.canStackSelectedPhotos ?? false)
                )

                Button("Auto Stack by Capture Time…") {
                    library?.presentCaptureTimeAutoStack()
                }
                .disabled(
                    !(library?.canPresentCaptureTimeAutoStack ?? false)
                )

                Divider()

                Button(
                    selectedStack?.isCollapsed == true
                        ? "Expand Stack"
                        : "Collapse Stack"
                ) {
                    if let id = library?.selectionID {
                        library?.togglePhotoStack(containing: id)
                    }
                }
                .disabled(selectedStack == nil)

                Divider()

                Button("Move Photo to Top of Stack") {
                    if let id = library?.selectionID {
                        library?.movePhotoInStack(id, .top)
                    }
                }
                .disabled(
                    selectedStack == nil
                        || selectedStack?.topPhotoID
                            == library?.selectionID
                )

                Button("Move Photo Up in Stack") {
                    if let id = library?.selectionID {
                        library?.movePhotoInStack(id, .up)
                    }
                }
                .disabled(
                    selectedStack == nil
                        || selectedStack?.memberIDs.first
                            == library?.selectionID
                )

                Button("Move Photo Down in Stack") {
                    if let id = library?.selectionID {
                        library?.movePhotoInStack(id, .down)
                    }
                }
                .disabled(
                    selectedStack == nil
                        || selectedStack?.memberIDs.last
                            == library?.selectionID
                )

                Divider()

                Button("Split Stack") {
                    _ = library?.splitSelectedPhotoStack()
                }
                .disabled(
                    !(library?.canSplitSelectedPhotoStack ?? false)
                )

                Button("Remove Photo from Stack") {
                    if let id = library?.selectionID {
                        library?.removePhotoFromStack(id)
                    }
                }
                .disabled(selectedStack == nil)

                Button("Unstack") {
                    if let id = library?.selectionID {
                        library?.unstackPhoto(containing: id)
                    }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(selectedStack == nil)

                Divider()

                Button("Expand All Stacks") {
                    library?.setAllPhotoStacksCollapsed(false)
                }
                .disabled(library?.photoStacks.isEmpty != false)

                Button("Collapse All Stacks") {
                    library?.setAllPhotoStacksCollapsed(true)
                }
                .disabled(library?.photoStacks.isEmpty != false)
            }

            CommandGroup(after: .toolbar) {
                Button("Library Workspace") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .showLibrary
                    )
                }
                .keyboardShortcut(
                    "1",
                    modifiers: [.command]
                )
                .disabled(library == nil)

                Button("Develop Workspace") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .showDevelop
                    )
                }
                .keyboardShortcut(
                    "2",
                    modifiers: [.command]
                )
                .disabled(library?.selectionID == nil)

                Button("Map Workspace") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .showMap
                    )
                }
                .keyboardShortcut(
                    "3",
                    modifiers: [.command]
                )
                .disabled(library == nil)

                Divider()

                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .toggleSidebar
                    )
                }
                .keyboardShortcut(
                    "s",
                    modifiers: [.command, .option]
                )

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .toggleInspector
                    )
                }
                .keyboardShortcut(
                    "i",
                    modifiers: [.command, .option]
                )

                Button("Toggle Filmstrip") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .toggleFilmstrip
                    )
                }
                .keyboardShortcut(
                    "f",
                    modifiers: [.command, .option]
                )

                Button("Hide or Restore All Panels") {
                    NotificationCenter.default.post(
                        name: .rawDeskUICommand,
                        object: RAWDeskUICommand
                            .toggleAllPanels
                    )
                }
                .keyboardShortcut(
                    "0",
                    modifiers: [.command, .option]
                )

                Divider()

                Button(
                    library?.compareState == nil
                        ? "Compare Photos"
                        : "Finish Comparing"
                ) {
                    library?.toggleCompare()
                }
                .keyboardShortcut("c", modifiers: [])
                .disabled(
                    library?.compareState == nil
                        && !(library?.canStartCompare ?? false)
                )

                Button(
                    library?.surveyState == nil
                        ? "Survey Photos"
                        : "Finish Surveying"
                ) {
                    library?.toggleSurvey()
                }
                .keyboardShortcut("n", modifiers: [])
                .disabled(
                    library?.surveyState == nil
                        && !(library?.canStartSurvey ?? false)
                )

                Button(
                    library?.referenceState == nil
                        ? "Open in Reference View"
                        : "Finish Reference View"
                ) {
                    library?.toggleReferenceView()
                }
                .keyboardShortcut("r", modifiers: [.shift])
                .disabled(
                    library?.referenceState == nil
                        && !(library?.canStartReference ?? false)
                )

                Divider()

                Button("Swap Select and Candidate") {
                    library?.swapComparePhotos()
                }
                .disabled(library?.compareState == nil)

                Button("Make Candidate the Select") {
                    library?.promoteCompareCandidate()
                }
                .disabled(library?.compareState == nil)

                Divider()

                Button("Zoom In") { viewer?.transform.zoomIn() }
                    .keyboardShortcut("=", modifiers: [.command])
                    .disabled(library?.surveyState != nil)
                Button("Zoom Out") { viewer?.transform.zoomOut() }
                    .keyboardShortcut("-", modifiers: [.command])
                    .disabled(library?.surveyState != nil)
                Button("Fit to Window") { viewer?.transform.fit() }
                    .keyboardShortcut("0", modifiers: [.command])
                    .disabled(library?.surveyState != nil)
                Button("Actual Size") { viewer?.transform.actualSize() }
                    .keyboardShortcut(
                        "1",
                        modifiers: [.command, .shift]
                    )
                    .disabled(library?.surveyState != nil)
                Button("Toggle Original") { viewer?.toggleOriginal() }
                    .keyboardShortcut("\\", modifiers: [])
                    .disabled(library?.surveyState != nil)
                Button(
                    viewer?.softProofSettings.isEnabled == true
                        ? "Disable Soft Proofing"
                        : "Enable Soft Proofing"
                ) {
                    viewer?.toggleSoftProofing()
                }
                .disabled(
                    library?.selectionID == nil
                        || library?.surveyState != nil
                )
                Divider()
                Button("Rotate Right") {
                    if let id = library?.selectionID,
                       let adjustments = library?.rotateRight(for: id) {
                        viewer?.updateAdjustments(adjustments, for: id)
                    }
                }
                    .keyboardShortcut("]", modifiers: [.command])
                Button("Rotate Left") {
                    if let id = library?.selectionID,
                       let adjustments = library?.rotateLeft(for: id) {
                        viewer?.updateAdjustments(adjustments, for: id)
                    }
                }
                    .keyboardShortcut("[", modifiers: [.command])
                Button("Flip Horizontal") {
                    if let id = library?.selectionID,
                       let adjustments = library?.flipHorizontal(for: id) {
                        viewer?.updateAdjustments(adjustments, for: id)
                    }
                }
                Button("Flip Vertical") {
                    if let id = library?.selectionID,
                       let adjustments = library?.flipVertical(for: id) {
                        viewer?.updateAdjustments(adjustments, for: id)
                    }
                }
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Edit Settings") {
                    if let id = library?.selectionID {
                        library?.copyAdjustments(from: id)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(library?.selectionID == nil)

                Button("Paste Edit Settings") {
                    if let id = library?.selectionID {
                        library?.pasteAdjustments(to: id)
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(library?.selectionID == nil || library?.copiedAdjustments == nil)

                Divider()

                Button("Synchronize Edit Settings…") {
                    library?.presentSyncSettings()
                }
                .keyboardShortcut(
                    "s",
                    modifiers: [.command, .shift]
                )
                .disabled(
                    !(library?
                        .canSynchronizeSelectedAdjustments
                        ?? false)
                )

                Button(
                    library?.isAutoSyncEnabled == true
                        ? "Disable Auto Sync"
                        : "Enable Auto Sync"
                ) {
                    guard let library else { return }
                    library.setAutoSyncEnabled(
                        !library.isAutoSyncEnabled
                    )
                }
                .disabled(
                    !(library?
                        .canSynchronizeSelectedAdjustments
                        ?? false)
                )

                Divider()

                Button("Next Photo") { library?.selectNext() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Previous Photo") { library?.selectPrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
        }
    }

    private var targetCollectionActionTitle: String {
        guard let library else {
            return "Add to Target Collection"
        }
        if let target = library.targetPhotoCollection {
            guard let id = library.selectionID else {
                return "Add to \(target.name)"
            }
            return library.willAddToPhotoCollection(
                target,
                for: id
            )
                ? "Add to \(target.name)"
                : "Remove from \(target.name)"
        }
        guard let id = library.selectionID else {
            return "Add to Quick Collection"
        }
        return library.willAddToQuickCollection(for: id)
            ? "Add to Quick Collection"
            : "Remove from Quick Collection"
    }

    private var selectedStack: CatalogPhotoStack? {
        guard let id = library?.selectionID else { return nil }
        return library?.photoStack(for: id)
    }
}

extension Notification.Name {
    static let rawDeskExport = Notification.Name("rawdesk.export")
    static let rawDeskUICommand =
        Notification.Name("rawdesk.ui.command")
}
