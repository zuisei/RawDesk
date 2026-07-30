import Foundation
import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

public struct SidecarNotice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

private enum CatalogLoadSource: Sendable {
    case builtIn(CatalogSmartCollection)
    case photoCollection(UUID)
}

@MainActor
public final class LibraryViewModel: ObservableObject {

    @Published public private(set) var assets: [PhotoAsset] = []
    @Published public var workspaceMode: WorkspaceMode = .library {
        didSet {
            if workspaceMode != .library {
                compareState = nil
                surveyState = nil
                captureReferenceLockAndClear()
            }
        }
    }
    @Published public private(set) var compareState:
        PhotoCompareState?
    @Published public private(set) var surveyState:
        PhotoSurveyState?
    @Published public private(set) var referenceState:
        PhotoReferenceState?
    @Published public private(set) var lockedReferenceID:
        PhotoAsset.ID?
    @Published public var filter = FilterState() {
        didSet {
            if let activeSavedCollection,
               filter != activeSavedCollection.filter {
                self.activeSavedCollection = nil
            }
            reconcileSelectionWithFilter()
        }
    }
    @Published public private(set) var selectionID: PhotoAsset.ID?
    @Published public private(set) var selectedIDs:
        Set<PhotoAsset.ID> = [] {
        didSet {
            if selectedIDs.count < 2,
               isAutoSyncEnabled {
                isAutoSyncEnabled = false
            }
        }
    }
    @Published public private(set) var rootURL: URL?
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var scanError: String?
    @Published public var recursiveScan: Bool = true
    @Published public private(set) var recentFolders: [URL] = []
    @Published public var thumbnailPixelSize: CGFloat = 256
    @Published public var sort: LibrarySort = .captureDate {
        didSet {
            reconcileSelectionWithFilter()
        }
    }
    @Published public var sortAscending = false {
        didSet {
            reconcileSelectionWithFilter()
        }
    }
    @Published public private(set) var copiedAdjustments: PhotoAdjustments?
    @Published public private(set) var isAutoSyncEnabled = false
    @Published public var isSyncSettingsPresented = false
    @Published public var selectedSyncAdjustmentGroups =
        PhotoAdjustmentGroup.all
    @Published public private(set) var historyRevision = 0
    @Published public var sidecarNotice: SidecarNotice?
    @Published public private(set) var catalogCollection: CatalogSmartCollection?
    @Published public private(set) var activeSavedCollection: SavedSmartCollection?
    @Published public private(set) var savedSmartCollections: [SavedSmartCollection] = []
    @Published public private(set) var activePhotoCollection:
        CatalogPhotoCollection?
    @Published public private(set) var photoCollections:
        [CatalogPhotoCollection] = []
    @Published public private(set) var collectionSets:
        [CatalogCollectionSet] = []
    @Published public private(set) var photoCollectionMemberships:
        [PhotoAsset.ID: Set<UUID>] = [:]
    @Published public private(set) var quickCollectionPhotoIDs:
        Set<PhotoAsset.ID> = []
    @Published public private(set) var catalogSummary = CatalogSummary()
    @Published public private(set) var catalogError: String?
    @Published public var isImportPresented = false
    @Published public private(set) var pendingImportSourceURLs:
        [URL] = []
    @Published public var isAutoImportSettingsPresented = false
    @Published public var isCaptureTimeAutoStackPresented = false
    @Published public var isColorLabelSetEditorPresented = false
    @Published public private(set) var colorLabelSets:
        [PhotoColorLabelSet] = [.standard]
    @Published public private(set) var activeColorLabelSetID:
        PhotoColorLabelSet.ID = PhotoColorLabelSet.standardID
    @Published public private(set) var importProgress: PhotoImportProgress?
    @Published public private(set) var importPeopleProgress:
        PeopleScanProgress?
    @Published public private(set) var autoImportProgress:
        PhotoImportProgress?
    @Published public private(set) var autoImportSettings =
        AutoImportSettings()
    @Published public private(set) var autoImportStatus =
        AutoImportStatus()
    @Published public private(set) var lastAutoImportAssets:
        [PhotoAsset] = []
    @Published public private(set)
        var locationMetadataRefreshProgress:
            LocationMetadataRefreshProgress?
    @Published public private(set) var savedMapLocations:
        [SavedMapLocation] = []
    @Published public var editingSavedMapLocation:
        SavedMapLocation?
    @Published public private(set) var mapFocusRequest:
        MapFocusRequest?
    @Published public private(set) var loadedGPXTracklog:
        GPXTracklog?
    @Published public var gpxMatchSettings =
        GPXMatchSettings()
    @Published public var isGPXTracklogPresented = false
    @Published public private(set) var isLoadingGPXTracklog =
        false
    @Published public var isGPXTrackVisible = true
    @Published public private(set) var isManagingKeywords = false
    @Published public private(set) var duplicateScanProgress:
        CatalogDuplicateScanProgress?
    @Published public private(set) var duplicateScanResult:
        CatalogDuplicateScanResult?
    @Published public private(set) var exactDuplicateGroups:
        [CatalogExactDuplicateGroup] = []
    @Published public private(set) var cullingScanProgress:
        AssistedCullingProgress?
    @Published public private(set) var cullingScanResult:
        AssistedCullingScanResult?
    @Published public private(set) var photoStacks:
        [CatalogPhotoStack] = []
    @Published public var cullingCriteria =
        AssistedCullingCriteria.default {
        didSet {
            if catalogCollection == .assistedCulling {
                refreshCullingStackSuggestions()
                reconcileSelectionWithFilter()
            }
        }
    }
    @Published public var cullingReviewFilter:
        AssistedCullingReviewFilter = .all {
        didSet {
            if catalogCollection == .assistedCulling {
                reconcileSelectionWithFilter()
            }
        }
    }

    private let scanner = PhotoLibraryScanner()
    private let userStateStore: UserStateStore
    private let recentStore: RecentFolderStore
    private let colorLabelSetStore: PhotoColorLabelSetStore
    private let autoImportSettingsStore: AutoImportSettingsStore
    private let savedMapLocationStore: SavedMapLocationStore
    private let catalogStore: CatalogStore
    private let photoImportService: PhotoImportService
    private let autoImportService: AutoImportService
    private let watchedFolderMonitor: WatchedFolderMonitor
    private let catalogDuplicateScanner: CatalogDuplicateScanner
    private let assistedCullingAnalyzer: AssistedCullingAnalyzer
    private let peopleAnalyzer: PeopleAnalyzer
    private var scanTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    private var duplicateScanTask: Task<Void, Never>?
    private var cullingScanTask: Task<Void, Never>?
    private var autoImportScanTask: Task<Void, Never>?
    private var locationMetadataRefreshTask: Task<Void, Never>?
    private var autoImportBatchRunning = false
    private var autoImportRescanRequested = false
    private var autoImportStabilityTracker =
        AutoImportStabilityTracker()
    private var persistenceTasks: [PhotoAsset.ID: Task<Void, Never>] = [:]
    private var pendingStates: [PhotoAsset.ID: PhotoUserState] = [:]
    private var adjustmentUndo: [PhotoAsset.ID: [PhotoAdjustments]] = [:]
    private var adjustmentRedo: [PhotoAsset.ID: [PhotoAdjustments]] = [:]
    private var activeHistoryGroups: Set<PhotoAsset.ID> = []
    private var historyGroupTasks: [PhotoAsset.ID: Task<Void, Never>] = [:]
    private var bookmarkURLs: [URL] = []
    private var duplicateOrderByID: [PhotoAsset.ID: Int] = [:]
    private var duplicateGroupNumberByID: [PhotoAsset.ID: Int] = [:]
    private var duplicateAnchorIDs: Set<PhotoAsset.ID> = []
    private var duplicateHashByID: [PhotoAsset.ID: String] = [:]
    private var duplicateBasisByID:
        [PhotoAsset.ID: CatalogDuplicateMatchBasis] = [:]
    private var cullingAnalysisByID:
        [PhotoAsset.ID: AssistedCullingAnalysis] = [:]
    private var cullingStackNumberByID: [PhotoAsset.ID: Int] = [:]
    private var referenceLayoutPreference:
        PhotoReferenceLayout = .sideBySide
    private var pendingWorkspaceSelectionID:
        PhotoAsset.ID?
    private var hasAttemptedWorkspaceRestore = false

    public init(
        userStateStore: UserStateStore = .shared,
        recentStore: RecentFolderStore = .shared,
        colorLabelSetStore: PhotoColorLabelSetStore = .shared,
        autoImportSettingsStore:
            AutoImportSettingsStore = .shared,
        savedMapLocationStore:
            SavedMapLocationStore = .shared,
        catalogStore: CatalogStore = .shared,
        assistedCullingAnalyzer: AssistedCullingAnalyzer? = nil,
        peopleAnalyzer: PeopleAnalyzer? = nil,
        autoImportService: AutoImportService? = nil,
        watchedFolderMonitor: WatchedFolderMonitor =
            WatchedFolderMonitor()
    ) {
        self.userStateStore = userStateStore
        self.recentStore = recentStore
        self.colorLabelSetStore = colorLabelSetStore
        self.autoImportSettingsStore = autoImportSettingsStore
        self.savedMapLocationStore = savedMapLocationStore
        self.catalogStore = catalogStore
        let resolvedPeopleAnalyzer = peopleAnalyzer
            ?? (
                catalogStore === CatalogStore.shared
                    ? PeopleAnalyzer.shared
                    : PeopleAnalyzer(catalogStore: catalogStore)
            )
        self.peopleAnalyzer = resolvedPeopleAnalyzer
        photoImportService = PhotoImportService(
            catalogStore: catalogStore
        )
        catalogDuplicateScanner = CatalogDuplicateScanner(
            catalogStore: catalogStore
        )
        self.assistedCullingAnalyzer = assistedCullingAnalyzer
            ?? AssistedCullingAnalyzer(catalogStore: catalogStore)
        self.autoImportService = autoImportService
            ?? AutoImportService(
                catalogStore: catalogStore,
                photoImportService: photoImportService,
                peopleAnalyzer: resolvedPeopleAnalyzer
            )
        self.watchedFolderMonitor = watchedFolderMonitor
        let colorLabelLibrary = colorLabelSetStore.load()
        colorLabelSets = colorLabelLibrary.sets
        activeColorLabelSetID = colorLabelLibrary.activeSetID
        let storedAutoImportSettings =
            autoImportSettingsStore.load()
        autoImportSettings = storedAutoImportSettings
        autoImportStabilityTracker =
            AutoImportStabilityTracker(
                settleInterval:
                    storedAutoImportSettings.settleInterval
            )
        savedMapLocations =
            savedMapLocationStore.load().locations
        recentFolders = recentStore.recents()
        _ = userStateStore.loadAll()
        catalogError = catalogStore.startupWarning
        savedSmartCollections =
            (try? catalogStore.savedSmartCollections()) ?? []
        collectionSets =
            (try? catalogStore.collectionSets()) ?? []
        photoCollections =
            (try? catalogStore.photoCollections()) ?? []
        photoCollectionMemberships =
            (try? catalogStore.photoCollectionMemberships()) ?? [:]
        quickCollectionPhotoIDs =
            (try? catalogStore.quickCollectionPhotoIDs()) ?? []
        refreshPhotoStacks()
        refreshCatalogSummary()
        reconfigureAutoImportMonitoring()

        // Drop the memoised `filtered` result whenever anything published
        // changes. `objectWillChange` fires before the value settles, and the
        // next read happens during the render that change triggers, so the
        // recompute always sees the new state.
        filteredCacheInvalidation = objectWillChange
            .sink { [weak self] _ in
                self?.filteredCache = nil
            }
    }

    private var filteredCacheInvalidation: AnyCancellable?

    deinit {
        scanTask?.cancel()
        catalogTask?.cancel()
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        autoImportScanTask?.cancel()
        locationMetadataRefreshTask?.cancel()
        watchedFolderMonitor.stop()
        for (id, task) in persistenceTasks {
            task.cancel()
            if let state = pendingStates[id] {
                userStateStore.set(id: id, state: state)
                try? catalogStore.updateUserState(id: id, state: state)
            }
        }
        for task in historyGroupTasks.values {
            task.cancel()
        }
        for u in bookmarkURLs {
            u.stopAccessingSecurityScopedResource()
        }
    }

    /// Memoised result of `computeFiltered`, cleared whenever anything the view
    /// model publishes changes.
    ///
    /// One render of Library-with-filmstrip reads `filtered` seven times, and
    /// each read allocated a filtered copy of the whole catalogue, sorted it
    /// through `localizedStandardCompare`, and rebuilt stack ordering. It was
    /// re-entered on every published change, so every rating keystroke and
    /// every arrow-key move paid for it again.
    ///
    /// Invalidating from `objectWillChange` rather than from a `didSet` on each
    /// input is deliberate: the inputs are numerous and some are private
    /// non-published state, so an explicit list would rot silently into stale
    /// results. Anything that can change what the UI sees fires this.
    private var filteredCache: [PhotoAsset]?

    public var filtered: [PhotoAsset] {
        if let filteredCache { return filteredCache }
        let value = computeFiltered()
        filteredCache = value
        return value
    }

    private func computeFiltered() -> [PhotoAsset] {
        var visible = filter.isActive
            ? assets.filter { filter.matches($0) }
            : assets
        if catalogCollection == .assistedCulling {
            visible = visible.filter {
                cullingReviewFilter.contains(
                    cullingDecision(for: $0.id)
                )
            }
        }
        if catalogCollection == .exactDuplicates {
            return visible.sorted {
                let lhsRank = duplicateOrderByID[$0.id] ?? .max
                let rhsRank = duplicateOrderByID[$1.id] ?? .max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                return $0.path.localizedStandardCompare($1.path)
                    == .orderedAscending
            }
        }
        let ordered = activePhotoCollection == nil
            ? sort.sorted(visible, ascending: sortAscending)
            : visible
        return Self.applyPhotoStacks(
            to: ordered,
            stacks: photoStacks
        )
    }

    nonisolated static func applyPhotoStacks(
        to sortedAssets: [PhotoAsset],
        stacks: [CatalogPhotoStack]
    ) -> [PhotoAsset] {
        guard !stacks.isEmpty else { return sortedAssets }
        let visibleByID = Dictionary(
            uniqueKeysWithValues: sortedAssets.map { ($0.id, $0) }
        )
        var stackByPhotoID: [
            PhotoAsset.ID: CatalogPhotoStack
        ] = [:]
        for stack in stacks {
            for photoID in stack.memberIDs
            where stackByPhotoID[photoID] == nil {
                stackByPhotoID[photoID] = stack
            }
        }
        var emittedStackIDs: Set<UUID> = []
        var result: [PhotoAsset] = []
        result.reserveCapacity(sortedAssets.count)

        for asset in sortedAssets {
            guard let stack = stackByPhotoID[asset.id] else {
                result.append(asset)
                continue
            }
            guard emittedStackIDs.insert(stack.id).inserted else {
                continue
            }
            let visibleMembers = stack.memberIDs.compactMap {
                visibleByID[$0]
            }
            if stack.isCollapsed {
                if let representative = visibleMembers.first {
                    result.append(representative)
                }
            } else {
                result.append(contentsOf: visibleMembers)
            }
        }
        return result
    }

    public var selectedAsset: PhotoAsset? {
        guard let id = selectionID else { return nil }
        return assets.first(where: { $0.id == id })
    }

    public var compareSelectAsset: PhotoAsset? {
        guard let id = compareState?.selectID else { return nil }
        return assets.first(where: { $0.id == id })
    }

    public var surveyAssets: [PhotoAsset] {
        guard let surveyState else { return [] }
        let assetsByID = Dictionary(
            uniqueKeysWithValues: assets.map { ($0.id, $0) }
        )
        return surveyState.photoIDs.compactMap {
            assetsByID[$0]
        }
    }

    public var referenceAsset: PhotoAsset? {
        guard let id = referenceState?.referenceID else {
            return nil
        }
        return assets.first(where: { $0.id == id })
    }

    public var canStartCompare: Bool {
        workspaceMode == .library && filtered.count >= 2
    }

    public var canStartSurvey: Bool {
        guard workspaceMode == .library else { return false }
        if compareState != nil || surveyState != nil {
            return true
        }
        if let referenceState {
            return referenceState.referenceID != nil
        }
        let visibleIDs = Set(filtered.map(\.id))
        return selectedIDs.filter(visibleIDs.contains).count >= 2
    }

    public var canStartReference: Bool {
        guard workspaceMode == .library else { return false }
        return referenceState != nil
            || surveyState?.activeID != nil
            || compareState?.candidateID != nil
            || selectionID != nil
    }

    public var displayTitle: String {
        if referenceState != nil {
            return "Reference View"
        }
        if compareState != nil {
            return "Compare"
        }
        if surveyState != nil {
            return "Survey"
        }
        if workspaceMode == .people {
            return "People"
        }
        return activePhotoCollection?.name
            ?? activeSavedCollection?.name
            ?? catalogCollection?.name
            ?? rootURL?.lastPathComponent
            ?? importDisplayTitle
            ?? "RAWDesk"
    }

    public var activeColorLabelSet: PhotoColorLabelSet {
        colorLabelSets.first { $0.id == activeColorLabelSetID }
            ?? colorLabelSets.first
            ?? .standard
    }

    public func colorLabelName(
        for label: PhotoColorLabel
    ) -> String {
        activeColorLabelSet[label]
    }

    public func activateColorLabelSet(
        _ id: PhotoColorLabelSet.ID
    ) {
        guard colorLabelSets.contains(where: { $0.id == id }) else {
            return
        }
        activeColorLabelSetID = id
        persistColorLabelSets()
    }

    /// Creates or replaces a preset. Returns a validation message on failure.
    @discardableResult
    public func saveColorLabelSet(
        _ set: PhotoColorLabelSet,
        makeActive: Bool = true
    ) -> String? {
        let set = set.normalized
        if let validationMessage = set.validationMessage {
            return validationMessage
        }
        let duplicateName = colorLabelSets.contains {
            $0.id != set.id
                && PhotoColorLabelSet.comparisonKey($0.name)
                    == PhotoColorLabelSet.comparisonKey(set.name)
        }
        if duplicateName {
            return "A color-label preset already uses this name."
        }
        if let index = colorLabelSets.firstIndex(where: {
            $0.id == set.id
        }) {
            colorLabelSets[index] = set
        } else {
            colorLabelSets.append(set)
        }
        if makeActive {
            activeColorLabelSetID = set.id
        }
        persistColorLabelSets()
        return nil
    }

    @discardableResult
    public func deleteColorLabelSet(
        _ id: PhotoColorLabelSet.ID
    ) -> String? {
        guard colorLabelSets.count > 1 else {
            return "Keep at least one color-label preset."
        }
        guard let index = colorLabelSets.firstIndex(where: {
            $0.id == id
        }) else {
            return "The color-label preset no longer exists."
        }
        colorLabelSets.remove(at: index)
        if activeColorLabelSetID == id {
            activeColorLabelSetID =
                colorLabelSets[min(index, colorLabelSets.count - 1)].id
        }
        persistColorLabelSets()
        return nil
    }

    private func persistColorLabelSets() {
        colorLabelSetStore.save(
            PhotoColorLabelSetLibrary(
                activeSetID: activeColorLabelSetID,
                sets: colorLabelSets
            )
        )
    }

    private var importDisplayTitle: String?

    public func presentImport(
        sourceURLs: [URL] = []
    ) {
        pendingImportSourceURLs = sourceURLs
        isImportPresented = true
    }

    public func dismissImport() {
        isImportPresented = false
        pendingImportSourceURLs = []
    }

    public var canEnableAutoImport: Bool {
        autoImportSettings.validationMessage(
            requiringComplete: true
        ) == nil
    }

    public func presentAutoImportSettings() {
        isAutoImportSettingsPresented = true
    }

    @discardableResult
    public func saveAutoImportSettings(
        _ rawSettings: AutoImportSettings
    ) -> String? {
        let settings = rawSettings.normalized
        if let validation =
            settings.templateValidationMessage {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: validation
            )
            return validation
        }
        if settings.enabled,
           let validation = settings.validationMessage(
               requiringComplete: true
           ) {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: validation
            )
            return validation
        }
        autoImportSettings = settings
        autoImportSettingsStore.save(settings)
        reconfigureAutoImportMonitoring()
        return nil
    }

    @discardableResult
    public func setAutoImportEnabled(
        _ enabled: Bool
    ) -> String? {
        var settings = autoImportSettings
        settings.enabled = enabled
        if enabled,
           let validation = settings.validationMessage(
               requiringComplete: true
           ) {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: validation
            )
            isAutoImportSettingsPresented = true
            return validation
        }
        autoImportSettings = settings.normalized
        autoImportSettingsStore.save(autoImportSettings)
        reconfigureAutoImportMonitoring()
        return nil
    }

    public func runAutoImportNow() {
        guard autoImportSettings.enabled else {
            isAutoImportSettingsPresented = true
            return
        }
        scheduleAutoImportScan(delay: 0)
    }

    public func showLastAutoImport() {
        guard !lastAutoImportAssets.isEmpty else { return }
        scanTask?.cancel()
        catalogTask?.cancel()
        catalogCollection = nil
        activeSavedCollection = nil
        activePhotoCollection = nil
        importDisplayTitle = "Last Auto Import"
        rootURL = nil
        filter = FilterState()
        assets = lastAutoImportAssets
        selectionID = Self.selectionAfterScan(
            current: nil,
            assets: assets
        )
        selectedIDs = selectionID.map { [$0] } ?? []
        selectionAnchorID = selectionID
    }

    private func reconfigureAutoImportMonitoring() {
        autoImportScanTask?.cancel()
        autoImportScanTask = nil
        autoImportBatchRunning = false
        autoImportRescanRequested = false
        watchedFolderMonitor.stop()
        autoImportProgress = nil
        autoImportStabilityTracker.reset(
            settleInterval:
                autoImportSettings.settleInterval
        )

        guard autoImportSettings.enabled else {
            autoImportStatus = AutoImportStatus(
                phase: .off,
                message: "Auto Import is off.",
                lastRunDate:
                    autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
            return
        }
        guard let watchedFolderURL =
                autoImportSettings.watchedFolderURL else {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: "Choose a watched folder.",
                lastRunDate: autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
            return
        }
        if let validation =
            autoImportSettings.validationMessage(
                requiringComplete: true
            ) {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: validation,
                lastRunDate: autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
            return
        }
        do {
            try watchedFolderMonitor.start(
                folderURL: watchedFolderURL
            ) { [weak self] in
                Task { @MainActor in
                    self?.scheduleAutoImportScan(
                        delay: 0.35
                    )
                }
            }
            autoImportStatus = AutoImportStatus(
                phase: .watching,
                message: autoImportWatchingMessage(
                    for: watchedFolderURL
                ),
                lastRunDate:
                    autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
            scheduleAutoImportScan(delay: 0)
        } catch {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: error.localizedDescription,
                lastRunDate:
                    autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
        }
    }

    private func scheduleAutoImportScan(
        delay: TimeInterval
    ) {
        guard autoImportSettings.enabled else { return }
        if autoImportBatchRunning {
            autoImportRescanRequested = true
            return
        }
        autoImportScanTask?.cancel()
        autoImportScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                do {
                    try await Task.sleep(
                        for: .seconds(delay)
                    )
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            let nextDelay = await self.pollAutoImport()
            guard !Task.isCancelled else { return }
            self.autoImportScanTask = nil
            if self.autoImportRescanRequested {
                self.autoImportRescanRequested = false
                self.scheduleAutoImportScan(delay: 0.35)
            } else if let nextDelay {
                self.scheduleAutoImportScan(
                    delay: nextDelay
                )
            }
        }
    }

    private func pollAutoImport() async -> TimeInterval? {
        guard autoImportSettings.enabled,
              let watchedFolderURL =
                autoImportSettings.watchedFolderURL else {
            return nil
        }
        guard !isImportPresented,
              importProgress == nil else {
            return 1
        }
        do {
            let snapshots = try await autoImportService
                .snapshots(in: watchedFolderURL)
            let ready = autoImportStabilityTracker
                .readyCandidates(from: snapshots)
            let waitingCount =
                autoImportStabilityTracker.waitingCount
            if ready.isEmpty {
                if waitingCount > 0 {
                    autoImportStatus = AutoImportStatus(
                        phase: .settling,
                        message:
                            "Waiting for \(waitingCount) file(s) to finish writing.",
                        pendingCount: waitingCount,
                        lastRunDate:
                            autoImportStatus.lastRunDate,
                        lastImportedCount:
                            autoImportStatus.lastImportedCount
                    )
                    return min(
                        1,
                        autoImportSettings.settleInterval
                            / 2
                    )
                }
                autoImportStatus = AutoImportStatus(
                    phase: .watching,
                    message: autoImportWatchingMessage(
                        for: watchedFolderURL
                    ),
                    lastRunDate:
                        autoImportStatus.lastRunDate,
                    lastImportedCount:
                        autoImportStatus.lastImportedCount
                )
                return nil
            }

            autoImportBatchRunning = true
            autoImportStatus = AutoImportStatus(
                phase: .checking,
                message:
                    "Checking \(ready.count) stable file(s).",
                pendingCount: ready.count,
                lastRunDate:
                    autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
            defer {
                autoImportBatchRunning = false
                autoImportProgress = nil
            }
            let result = try await autoImportService.run(
                settings: autoImportSettings,
                sourceURLs: ready,
                colorLabelSet: activeColorLabelSet
            ) { [weak self] progress in
                await self?.setAutoImportProgress(progress)
            }
            autoImportStabilityTracker.retry(
                result.retryURLs
            )
            applyAutoImportResult(result)
            if autoImportSettings.analyzePeopleAfterImport,
               result.importResult.importedCount > 0 {
                NotificationCenter.default.post(
                    name: .rawDeskPeopleAnalysisDidChange,
                    object: nil
                )
            }
            advanceAutoImportSequence(
                processedCandidateCount: ready.count,
                importedCount:
                    result.importResult.importedCount
            )

            let lastRun = Date()
            if let firstFailure = result.failures.first {
                autoImportStatus = AutoImportStatus(
                    phase: .attention,
                    message: firstFailure,
                    pendingCount: result.retryURLs.count,
                    lastRunDate: lastRun,
                    lastImportedCount:
                        result.importResult.importedCount
                )
            } else if let firstWarning = result.warnings.first {
                autoImportStatus = AutoImportStatus(
                    phase: .attention,
                    message: firstWarning,
                    pendingCount: result.retryURLs.count,
                    lastRunDate: lastRun,
                    lastImportedCount:
                        result.importResult.importedCount
                )
            } else if result.retainedDuplicateCount > 0 {
                autoImportStatus = AutoImportStatus(
                    phase: .attention,
                    message:
                        "\(result.retainedDuplicateCount) exact duplicate(s) retained in the watched folder.",
                    lastRunDate: lastRun,
                    lastImportedCount:
                        result.importResult.importedCount
                )
            } else {
                autoImportStatus = AutoImportStatus(
                    phase: .watching,
                    message: autoImportCompletionMessage(
                        result.importResult
                    ),
                    lastRunDate: lastRun,
                    lastImportedCount:
                        result.importResult.importedCount
                )
            }
            return result.retryURLs.isEmpty ? nil : 1
        } catch is CancellationError {
            return nil
        } catch {
            autoImportStatus = AutoImportStatus(
                phase: .attention,
                message: error.localizedDescription,
                lastRunDate:
                    autoImportStatus.lastRunDate,
                lastImportedCount:
                    autoImportStatus.lastImportedCount
            )
            return 2
        }
    }

    private func setAutoImportProgress(
        _ progress: PhotoImportProgress
    ) {
        autoImportProgress = progress
        let phase: AutoImportActivityPhase
        switch progress.phase {
        case .discovering, .hashing:
            phase = .checking
        case .copying, .cataloging, .removingSources,
             .analyzingPeople:
            phase = .importing
        }
        let message: String
        if progress.phase == .analyzingPeople {
            message = progress.filename.map {
                "Analyzing \($0) locally for People."
            } ?? progress.phase.name
        } else {
            message = progress.filename
                ?? progress.phase.name
        }
        autoImportStatus = AutoImportStatus(
            phase: phase,
            message: message,
            pendingCount:
                max(0, progress.total - progress.completed),
            lastRunDate:
                autoImportStatus.lastRunDate,
            lastImportedCount:
                autoImportStatus.lastImportedCount
        )
    }

    private func autoImportCompletionMessage(
        _ result: PhotoImportResult
    ) -> String {
        let noun = result.importedCount == 1
            ? "photo"
            : "photos"
        var message =
            "\(result.importedCount) \(noun) imported safely."
        guard autoImportSettings.analyzePeopleAfterImport,
              result.importedCount > 0 else {
            return message
        }
        if result.peopleUnavailableCount > 0 {
            message +=
                " People analysis needs attention for \(result.peopleUnavailableCount)."
        } else if result.peopleFaceCount > 0 {
            let faceNoun = result.peopleFaceCount == 1
                ? "face suggestion"
                : "face suggestions"
            message +=
                " \(result.peopleFaceCount) \(faceNoun) ready in People."
        } else {
            message += " Local People analysis found no faces."
        }
        return message
    }

    private func autoImportWatchingMessage(
        for watchedFolderURL: URL
    ) -> String {
        let folderName = watchedFolderURL.lastPathComponent
        guard autoImportStatus.lastRunDate != nil else {
            return "Watching \(folderName)."
        }
        let count = autoImportStatus.lastImportedCount
        let noun = count == 1 ? "photo" : "photos"
        return "Watching \(folderName). Last import added \(count) \(noun)."
    }

    private func applyAutoImportResult(
        _ result: AutoImportRunResult
    ) {
        for asset in result.importResult.importedAssets {
            userStateStore.set(
                id: asset.id,
                state: asset.userState
            )
        }
        if !result.importResult.importedAssets.isEmpty {
            lastAutoImportAssets =
                result.importResult.importedAssets
        }
        refreshPhotoStacks()
        refreshCatalogSummary()

        guard let destination =
                autoImportSettings.destinationFolderURL,
              rootURL?.standardizedFileURL.path
                == destination.standardizedFileURL.path,
              !result.importResult.importedAssets.isEmpty else {
            return
        }
        var byID = Dictionary(
            uniqueKeysWithValues:
                assets.map { ($0.id, $0) }
        )
        for asset in result.importResult.importedAssets {
            byID[asset.id] = asset
        }
        assets = sort.sorted(
            Array(byID.values),
            ascending: sortAscending
        )
        selectionID = Self.selectionAfterScan(
            current: selectionID,
            assets: assets
        )
    }

    private func advanceAutoImportSequence(
        processedCandidateCount: Int,
        importedCount: Int
    ) {
        guard autoImportSettings.usesSequence,
              processedCandidateCount > 0,
              importedCount > 0 else {
            return
        }
        autoImportSettings.sequenceStart = min(
            999_999,
            autoImportSettings.sequenceStart
                + processedCandidateCount
        )
        autoImportSettingsStore.save(autoImportSettings)
    }

    public func preflightImport(
        _ request: PhotoImportRequest
    ) async throws -> PhotoImportPreflight {
        importProgress = PhotoImportProgress(
            phase: .discovering,
            completed: 0,
            total: 0
        )
        defer { importProgress = nil }
        return try await photoImportService.preflight(request) {
            [self] progress in
            await setImportProgress(progress)
        }
    }

    public func executeImport(
        _ preflight: PhotoImportPreflight,
        analyzePeopleAfterImport: Bool = false
    ) async throws -> PhotoImportResult {
        importProgress = PhotoImportProgress(
            phase: preflight.request.mode.requiresDestination
                ? .copying
                : .hashing,
            completed: 0,
            total: preflight.importableCount
        )
        importPeopleProgress = nil
        defer {
            importProgress = nil
            importPeopleProgress = nil
        }
        var result = try await photoImportService.execute(
            preflight,
            colorLabelSet: activeColorLabelSet
        ) {
            [self] progress in
            await setImportProgress(progress)
        }
        applyImportResult(result)
        importProgress = nil
        if analyzePeopleAfterImport {
            result = await addingPeopleAnalysis(
                to: result
            )
        }
        return result
    }

    private func setImportProgress(_ progress: PhotoImportProgress) {
        importProgress = progress
    }

    private func setImportPeopleProgress(
        _ progress: PeopleScanProgress
    ) {
        importPeopleProgress = progress
    }

    private func addingPeopleAnalysis(
        to rawResult: PhotoImportResult
    ) async -> PhotoImportResult {
        var result = rawResult
        let photoIDs = Set(result.importedAssets.map(\.id))
        guard !photoIDs.isEmpty else { return result }
        do {
            let scan = try await peopleAnalyzer.scan(
                photoIDs: photoIDs
            ) { [weak self] progress in
                await self?.setImportPeopleProgress(
                    progress
                )
            }
            result.peopleAnalyzedCount = scan.analyzedCount
            result.peopleCachedCount = scan.cachedCount
            result.peopleFaceCount = scan.faces.count
            result.peopleUnavailableCount =
                scan.unavailablePaths.count
            if !scan.unavailablePaths.isEmpty {
                result.warnings.append(
                    "\(scan.unavailablePaths.count) imported photo"
                        + "\(scan.unavailablePaths.count == 1 ? "" : "s") could not be analyzed for People. The import itself completed safely."
                )
            }
            refreshCatalogSummary()
            NotificationCenter.default.post(
                name: .rawDeskPeopleAnalysisDidChange,
                object: nil
            )
        } catch is CancellationError {
            result.warnings.append(
                "The import completed safely; local People analysis was stopped."
            )
        } catch {
            result.warnings.append(
                "The import completed safely, but local People analysis could not finish: \(error.localizedDescription)"
            )
        }
        return result
    }

    public func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder containing photos."
        if panel.runModal() == .OK, let url = panel.url {
            open(folder: url)
        }
    }

    public func open(folder url: URL) {
        scanTask?.cancel()
        catalogTask?.cancel()
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        duplicateScanProgress = nil
        clearDuplicateReview()
        cullingScanProgress = nil
        clearCullingReview()
        scanError = nil
        catalogCollection = nil
        activeSavedCollection = nil
        activePhotoCollection = nil
        importDisplayTitle = nil
        rootURL = url
        let bookmark = SecurityScopedBookmarkStore.makeBookmark(for: url)
        recentStore.record(url: url, bookmark: bookmark)
        recentFolders = recentStore.recents()

        isScanning = true
        let recursive = recursiveScan
        var states = userStateStore.loadAll()
        if let catalogStates = try? catalogStore.userStates(
            rootPath: url.path
        ) {
            for (id, state) in catalogStates where states[id] == nil {
                states[id] = state
            }
        }
        let catalogStore = catalogStore
        let colorLabelSet = activeColorLabelSet

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan(
                rootURL: url,
                recursive: recursive,
                userStates: states,
                colorLabelSet: colorLabelSet
            )
            if Task.isCancelled { return }
            let catalogFailure = await Task.detached(priority: .utility) {
                do {
                    try catalogStore.upsert(
                        assets: result.assets,
                        rootURL: url,
                        recursive: recursive
                    )
                    return nil as String?
                } catch {
                    return error.localizedDescription
                }
            }.value
            await MainActor.run {
                for asset in result.assets
                where states[asset.id] == nil && asset.userState != .empty {
                    self.userStateStore.set(id: asset.id, state: asset.userState)
                }
                self.assets = result.assets
                self.scanError = result.errors.isEmpty
                    ? nil
                    : "\(result.errors.count) scan warning(s)."
                self.isScanning = false
                self.selectionID = Self.selectionAfterScan(
                    current:
                        self.pendingWorkspaceSelectionID
                        ?? self.selectionID,
                    assets: result.assets
                )
                self.pendingWorkspaceSelectionID = nil
                let available = Set(result.assets.map(\.id))
                self.selectedIDs.formIntersection(available)
                if self.selectedIDs.isEmpty, let selectionID = self.selectionID {
                    self.selectedIDs = [selectionID]
                }
                self.selectionAnchorID = self.selectionID
                self.catalogError = catalogFailure
                    ?? self.catalogStore.startupWarning
                self.refreshCatalogSummary()
            }
        }
    }

    public func showCatalog(_ collection: CatalogSmartCollection) {
        activeSavedCollection = nil
        activePhotoCollection = nil
        importDisplayTitle = nil
        catalogCollection = collection
        if collection == .assistedCulling {
            startAssistedCullingScan(forceReanalysis: false)
            return
        }
        if collection == .exactDuplicates {
            startExactDuplicateScan(forceRehash: false)
            return
        }
        startCatalogLoad(
            source: .builtIn(collection),
            filterToApply: FilterState(searchText: filter.searchText)
        )
    }

    public func verifyAssistedCullingAgain() {
        guard catalogCollection == .assistedCulling else { return }
        startAssistedCullingScan(forceReanalysis: true)
    }

    public func cancelAssistedCullingScan() {
        cullingScanTask?.cancel()
        cullingScanTask = nil
        cullingScanProgress = nil
        isScanning = false
    }

    public func cullingAnalysis(
        for id: PhotoAsset.ID
    ) -> AssistedCullingAnalysis? {
        cullingAnalysisByID[id]
    }

    public func cullingDecision(
        for id: PhotoAsset.ID
    ) -> AssistedCullingDecision {
        cullingAnalysisByID[id]?.evaluation(
            criteria: cullingCriteria
        ).decision ?? .review
    }

    public func cullingEvaluation(
        for id: PhotoAsset.ID
    ) -> AssistedCullingEvaluation? {
        cullingAnalysisByID[id]?.evaluation(
            criteria: cullingCriteria
        )
    }

    public func cullingStackNumber(
        for id: PhotoAsset.ID
    ) -> Int? {
        cullingStackNumberByID[id]
    }

    public func photoStack(
        for photoID: PhotoAsset.ID
    ) -> CatalogPhotoStack? {
        photoStacks.first { $0.memberIDs.contains(photoID) }
    }

    public var canPresentCaptureTimeAutoStack: Bool {
        guard !isScanning,
              catalogCollection != .exactDuplicates else {
            return false
        }
        let stackedIDs = Set(photoStacks.flatMap(\.memberIDs))
        return captureTimeAutoStackScopeAssets.lazy.filter {
            !$0.catalogMissing && !stackedIDs.contains($0.id)
        }.prefix(2).count == 2
    }

    public func presentCaptureTimeAutoStack() {
        guard canPresentCaptureTimeAutoStack else { return }
        isCaptureTimeAutoStackPresented = true
    }

    public func captureTimeAutoStackPreview(
        maximumGap: TimeInterval
    ) -> CaptureTimeAutoStackPreview {
        CaptureTimeAutoStackPlanner.preview(
            assets: captureTimeAutoStackScopeAssets,
            existingStacks: photoStacks,
            maximumGap: maximumGap
        )
    }

    private var captureTimeAutoStackScopeAssets: [PhotoAsset] {
        guard let activeSavedCollection else { return assets }
        return assets.filter(activeSavedCollection.filter.matches)
    }

    public func photoStackMembership(
        for photoID: PhotoAsset.ID
    ) -> CatalogPhotoStackMembership? {
        photoStack(for: photoID)?.membership(for: photoID)
    }

    public var canStackSelectedPhotos: Bool {
        let selected = assets.filter {
            selectedIDs.contains($0.id)
        }
        guard selected.count >= 2 else { return false }
        return Set(selected.map {
            $0.url.deletingLastPathComponent()
                .standardizedFileURL.path
        }).count == 1
    }

    public var canSplitSelectedPhotoStack: Bool {
        guard !selectedIDs.isEmpty else { return false }
        let containingStacks = photoStacks.filter { stack in
            stack.memberIDs.contains {
                selectedIDs.contains($0)
            }
        }
        guard containingStacks.count == 1,
              let stack = containingStacks.first,
              selectedIDs.allSatisfy({
                  stack.memberIDs.contains($0)
              }),
              selectedIDs.count < stack.memberIDs.count else {
            return false
        }
        return !(selectedIDs.count == 1
            && selectedIDs.contains(stack.topPhotoID ?? ""))
    }

    @discardableResult
    public func stackSelectedPhotos(
        topPhotoID: PhotoAsset.ID? = nil
    ) -> Bool {
        let topID = topPhotoID
            ?? selectionID
            ?? filtered.first(where: {
                selectedIDs.contains($0.id)
            })?.id
        guard let topID else { return false }
        let selected = selectedIDs.contains(topID)
            ? selectedIDs
            : [topID]
        let ordered = [topID] + filtered.compactMap {
            selected.contains($0.id) && $0.id != topID
                ? $0.id
                : nil
        }
        guard ordered.count >= 2 else {
            catalogError = CatalogStoreError
                .photoStackRequiresMultiplePhotos
                .localizedDescription
            return false
        }
        do {
            let stack = try catalogStore.createPhotoStack(
                photoIDs: ordered
            )
            refreshPhotoStacks()
            refreshCatalogSummary()
            reconcileSelectionWithFilter()
            sidecarNotice = SidecarNotice(
                title: "Stack created",
                message:
                    "\(stack.photoCount) photos are grouped. The active photo is on top."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Could not create stack",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func createSuggestedCullingStacks() -> Bool {
        guard catalogCollection == .assistedCulling,
              let suggestions = cullingScanResult?.suggestedStacks,
              !suggestions.isEmpty else {
            return false
        }
        do {
            let created = try catalogStore.createSuggestedPhotoStacks(
                suggestions
            )
            refreshPhotoStacks()
            refreshCatalogSummary()
            refreshCullingStackSuggestions()
            reconcileSelectionWithFilter()
            sidecarNotice = SidecarNotice(
                title: "Suggested stacks created",
                message:
                    "\(created.count) stack\(created.count == 1 ? "" : "s") created from \(created.reduce(0) { $0 + $1.photoCount }) photos."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Could not create suggested stacks",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func createCaptureTimePhotoStacks(
        maximumGap: TimeInterval
    ) -> Bool {
        let preview = captureTimeAutoStackPreview(
            maximumGap: maximumGap
        )
        guard !preview.groups.isEmpty else {
            sidecarNotice = SidecarNotice(
                title: "No stacks to create",
                message:
                    "Increase the maximum capture-time gap, or add photos with usable capture times."
            )
            return false
        }
        do {
            let created = try catalogStore.createSuggestedPhotoStacks(
                preview.photoIDGroups
            )
            refreshPhotoStacks()
            refreshCatalogSummary()
            refreshCullingStackSuggestions()
            reconcileSelectionWithFilter()
            isCaptureTimeAutoStackPresented = false
            sidecarNotice = SidecarNotice(
                title: "Capture-time stacks created",
                message:
                    "\(created.count) stack\(created.count == 1 ? "" : "s") created from \(created.reduce(0) { $0 + $1.photoCount }) photos. Existing stacks and source files were left unchanged."
            )
            return true
        } catch {
            refreshPhotoStacks()
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Could not create capture-time stacks",
                message: error.localizedDescription
            )
            return false
        }
    }

    public func togglePhotoStack(
        containing photoID: PhotoAsset.ID
    ) {
        guard let stack = photoStack(for: photoID) else { return }
        setPhotoStack(
            stack,
            collapsed: !stack.isCollapsed
        )
    }

    public func setPhotoStack(
        _ stack: CatalogPhotoStack,
        collapsed: Bool
    ) {
        do {
            try catalogStore.setPhotoStackCollapsed(
                id: stack.id,
                collapsed: collapsed
            )
            refreshPhotoStacks()
            reconcileSelectionWithFilter()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func setAllPhotoStacksCollapsed(_ collapsed: Bool) {
        do {
            try catalogStore.setAllPhotoStacksCollapsed(collapsed)
            refreshPhotoStacks()
            reconcileSelectionWithFilter()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func unstackPhoto(
        containing photoID: PhotoAsset.ID
    ) {
        guard let stack = photoStack(for: photoID) else { return }
        do {
            try catalogStore.unstackPhotoStack(id: stack.id)
            refreshPhotoStacks()
            refreshCatalogSummary()
            refreshCullingStackSuggestions()
            reconcileSelectionWithFilter()
            sidecarNotice = SidecarNotice(
                title: "Stack released",
                message:
                    "\(stack.photoCount) photos are shown individually again."
            )
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func removePhotoFromStack(_ photoID: PhotoAsset.ID) {
        do {
            try catalogStore.removePhotosFromStacks(
                photoIDs: [photoID]
            )
            refreshPhotoStacks()
            refreshCatalogSummary()
            refreshCullingStackSuggestions()
            reconcileSelectionWithFilter()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    @discardableResult
    public func splitSelectedPhotoStack() -> Bool {
        guard canSplitSelectedPhotoStack else { return false }
        let separatedCount = selectedIDs.count
        do {
            _ = try catalogStore.splitPhotoStack(
                photoIDs: Array(selectedIDs)
            )
            refreshPhotoStacks()
            refreshCatalogSummary()
            refreshCullingStackSuggestions()
            reconcileSelectionWithFilter()
            sidecarNotice = SidecarNotice(
                title: "Stack split",
                message: separatedCount == 1
                    ? "The selected photo is now separate from the stack."
                    : "The selected photos are now grouped in a separate stack."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Could not split stack",
                message: error.localizedDescription
            )
            return false
        }
    }

    public func movePhotoInStack(
        _ photoID: PhotoAsset.ID,
        _ move: CatalogPhotoStackMove
    ) {
        do {
            _ = try catalogStore.movePhotoInStack(
                photoID: photoID,
                move
            )
            refreshPhotoStacks()
            reconcileSelectionWithFilter()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func setCullingManualDecision(
        _ decision: AssistedCullingDecision?,
        for id: PhotoAsset.ID
    ) {
        guard var analysis = cullingAnalysisByID[id] else { return }
        do {
            try catalogStore.setCullingManualDecision(
                decision,
                id: id
            )
            analysis.manualDecision = decision
            cullingAnalysisByID[id] = analysis
            if var result = cullingScanResult {
                result.analysesByID[id] = analysis
                cullingScanResult = result
            }
            reconcileSelectionWithFilter()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func applyCullingFlags() {
        applyCullingBatch(
            applyFlags: true,
            selectRating: nil,
            rejectRating: nil
        )
    }

    public func applyCullingRatings(
        selectRating: Int,
        rejectRating: Int
    ) {
        applyCullingBatch(
            applyFlags: false,
            selectRating: selectRating,
            rejectRating: rejectRating
        )
    }

    public func applyCullingColorLabels(
        selectLabel: PhotoColorLabel = .green,
        rejectLabel: PhotoColorLabel = .red
    ) {
        applyCullingBatch(
            applyFlags: false,
            selectRating: nil,
            rejectRating: nil,
            selectColorLabel: selectLabel,
            rejectColorLabel: rejectLabel
        )
    }

    private func startAssistedCullingScan(
        forceReanalysis: Bool
    ) {
        scanTask?.cancel()
        catalogTask?.cancel()
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        duplicateScanProgress = nil
        clearDuplicateReview()
        flushPendingPersistence()
        filter = FilterState(searchText: filter.searchText)
        scanError = nil
        catalogError = catalogStore.startupWarning
        rootURL = nil
        isScanning = true
        cullingScanProgress = AssistedCullingProgress()

        if !forceReanalysis {
            assets = []
            selectionID = nil
            selectedIDs = []
            selectionAnchorID = nil
            clearCullingReview()
        }

        let previousSelection = selectionID
        let states = userStateStore.loadAll()
        let criteria = cullingCriteria
        cullingScanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await assistedCullingAnalyzer.scan(
                    forceReanalysis: forceReanalysis,
                    criteria: criteria
                ) { [weak self] progress in
                    await self?.setCullingScanProgress(progress)
                }
                try Task.checkCancellation()
                let entries = try catalogStore.entries(
                    for: .assistedCulling
                )
                let summary = try catalogStore.summary()
                let stacks = try catalogStore.photoStacks()
                try Task.checkCancellation()
                guard catalogCollection == .assistedCulling else {
                    return
                }

                var loadedAssets: [PhotoAsset] = []
                loadedAssets.reserveCapacity(entries.count)
                for entry in entries {
                    var asset = entry.asset
                    if let localState = states[entry.id] {
                        asset.userState = localState
                    } else {
                        userStateStore.set(
                            id: entry.id,
                            state: entry.userState
                        )
                    }
                    loadedAssets.append(asset)
                }

                photoStacks = stacks
                applyCullingResult(result)
                assets = loadedAssets
                catalogSummary = summary
                catalogError = catalogStore.startupWarning
                isScanning = false
                cullingScanProgress = nil
                selectionID = Self.selectionAfterScan(
                    current: previousSelection,
                    assets: filtered
                )
                let available = Set(filtered.map(\.id))
                selectedIDs.formIntersection(available)
                if selectedIDs.isEmpty, let selectionID {
                    selectedIDs = [selectionID]
                }
                selectionAnchorID = selectionID
                cullingScanTask = nil
            } catch is CancellationError {
                if catalogCollection == .assistedCulling {
                    isScanning = false
                    cullingScanProgress = nil
                }
                cullingScanTask = nil
            } catch {
                guard catalogCollection == .assistedCulling else {
                    return
                }
                catalogError = error.localizedDescription
                isScanning = false
                cullingScanProgress = nil
                cullingScanTask = nil
            }
        }
    }

    private func setCullingScanProgress(
        _ progress: AssistedCullingProgress
    ) {
        guard catalogCollection == .assistedCulling else { return }
        cullingScanProgress = progress
    }

    private func applyCullingResult(
        _ incomingResult: AssistedCullingScanResult
    ) {
        var result = incomingResult
        result.suggestedStacks = uncommittedCullingSuggestions(
            result.suggestedStacks
        )
        cullingScanResult = result
        cullingAnalysisByID = result.analysesByID
        updateCullingStackNumbers(result.suggestedStacks)
    }

    private func refreshCullingStackSuggestions() {
        guard var result = cullingScanResult else { return }
        result.suggestedStacks =
            AssistedCullingAnalyzer.suggestedStacks(
                assets: assets,
                analysesByID: cullingAnalysisByID,
                criteria: cullingCriteria
            )
        result.suggestedStacks = uncommittedCullingSuggestions(
            result.suggestedStacks
        )
        cullingScanResult = result
        updateCullingStackNumbers(result.suggestedStacks)
    }

    private func uncommittedCullingSuggestions(
        _ suggestions: [[PhotoAsset.ID]]
    ) -> [[PhotoAsset.ID]] {
        let persistedIDs = Set(
            photoStacks.flatMap(\.memberIDs)
        )
        return suggestions.filter { stack in
            stack.count >= 2
                && stack.allSatisfy {
                    !persistedIDs.contains($0)
                }
        }
    }

    private func updateCullingStackNumbers(
        _ stacks: [[PhotoAsset.ID]]
    ) {
        cullingStackNumberByID = [:]
        for (offset, stack) in stacks.enumerated() {
            for id in stack {
                cullingStackNumberByID[id] = offset + 1
            }
        }
    }

    private func clearCullingReview() {
        cullingScanResult = nil
        cullingAnalysisByID = [:]
        cullingStackNumberByID = [:]
    }

    private func applyCullingBatch(
        applyFlags: Bool,
        selectRating: Int?,
        rejectRating: Int?,
        selectColorLabel: PhotoColorLabel? = nil,
        rejectColorLabel: PhotoColorLabel? = nil
    ) {
        guard catalogCollection == .assistedCulling else { return }
        flushPendingPersistence()
        var updates: [String: PhotoUserState] = [:]
        var selectedCount = 0
        var rejectedCount = 0
        let selectColorLabelName = selectColorLabel.map {
            activeColorLabelSet[$0]
        }
        let rejectColorLabelName = rejectColorLabel.map {
            activeColorLabelSet[$0]
        }

        for asset in assets {
            let decision = cullingDecision(for: asset.id)
            guard decision != .review else { continue }
            var state = asset.userState
            switch decision {
            case .select:
                if applyFlags {
                    state.pickStatus = .picked
                }
                if let selectRating {
                    state.rating = max(0, min(5, selectRating))
                }
                if let selectColorLabel {
                    state.assignColorLabel(
                        selectColorLabel,
                        metadataValue: selectColorLabelName
                    )
                }
                selectedCount += 1
            case .reject:
                if applyFlags {
                    state.pickStatus = .rejected
                }
                if let rejectRating {
                    state.rating = max(0, min(5, rejectRating))
                }
                if let rejectColorLabel {
                    state.assignColorLabel(
                        rejectColorLabel,
                        metadataValue: rejectColorLabelName
                    )
                }
                rejectedCount += 1
            case .review:
                continue
            }
            updates[asset.id] = state
        }

        guard !updates.isEmpty else {
            sidecarNotice = SidecarNotice(
                title: "No culling results to apply",
                message:
                    "No analyzed photo currently matches the Select or Reject criteria."
            )
            return
        }

        do {
            try catalogStore.updateUserStates(updates)
            userStateStore.set(statesByID: updates)
            for (id, state) in updates {
                persistenceTasks[id]?.cancel()
                persistenceTasks[id] = nil
                pendingStates[id] = nil
                if let index = assets.firstIndex(where: {
                    $0.id == id
                }) {
                    assets[index].userState = state
                }
            }
            refreshCatalogSummary()
            let action: String
            if applyFlags {
                action = "Pick and Reject flags"
            } else if selectColorLabel != nil
                || rejectColorLabel != nil {
                action = "color labels"
            } else {
                action = "star ratings"
            }
            sidecarNotice = SidecarNotice(
                title: "Culling \(action) applied",
                message:
                    "\(selectedCount) Select and \(rejectedCount) Reject results were updated in one catalog transaction. Image files and XMP sidecars were not modified."
            )
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func verifyExactDuplicatesAgain() {
        guard catalogCollection == .exactDuplicates else { return }
        startExactDuplicateScan(forceRehash: true)
    }

    public func cancelExactDuplicateScan() {
        duplicateScanTask?.cancel()
        duplicateScanTask = nil
        duplicateScanProgress = nil
        isScanning = false
    }

    public func duplicateGroupNumber(
        for id: PhotoAsset.ID
    ) -> Int? {
        duplicateGroupNumberByID[id]
    }

    public func isDuplicateAnchor(_ id: PhotoAsset.ID) -> Bool {
        duplicateAnchorIDs.contains(id)
    }

    public func duplicateContentHash(
        for id: PhotoAsset.ID
    ) -> String? {
        duplicateHashByID[id]
    }

    public func duplicateMatchBasis(
        for id: PhotoAsset.ID
    ) -> CatalogDuplicateMatchBasis? {
        duplicateBasisByID[id]
    }

    private func startExactDuplicateScan(forceRehash: Bool) {
        scanTask?.cancel()
        catalogTask?.cancel()
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        cullingScanProgress = nil
        clearCullingReview()
        flushPendingPersistence()
        filter = FilterState(searchText: filter.searchText)
        scanError = nil
        catalogError = catalogStore.startupWarning
        rootURL = nil
        isScanning = true
        duplicateScanProgress = CatalogDuplicateScanProgress()

        if !forceRehash {
            assets = []
            selectionID = nil
            selectedIDs = []
            selectionAnchorID = nil
            clearDuplicateReview()
        }

        let previousSelection = selectionID
        let states = userStateStore.loadAll()
        duplicateScanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await catalogDuplicateScanner.scan(
                    forceRehash: forceRehash
                ) { [weak self] progress in
                    await self?.setDuplicateScanProgress(progress)
                }
                try Task.checkCancellation()
                let entries = try catalogStore.entries(
                    for: .exactDuplicates
                )
                let summary = try catalogStore.summary()
                let stacks = try catalogStore.photoStacks()
                try Task.checkCancellation()
                guard catalogCollection == .exactDuplicates else {
                    return
                }

                var loadedAssets: [PhotoAsset] = []
                loadedAssets.reserveCapacity(entries.count)
                for entry in entries {
                    var asset = entry.asset
                    if let localState = states[entry.id] {
                        asset.userState = localState
                    } else {
                        userStateStore.set(
                            id: entry.id,
                            state: entry.userState
                        )
                    }
                    loadedAssets.append(asset)
                }

                applyDuplicateGroups(result.groups)
                photoStacks = stacks
                assets = loadedAssets
                duplicateScanResult = result
                catalogSummary = summary
                catalogError = catalogStore.startupWarning
                isScanning = false
                duplicateScanProgress = nil
                selectionID = Self.selectionAfterScan(
                    current: previousSelection,
                    assets: loadedAssets
                )
                let available = Set(loadedAssets.map(\.id))
                selectedIDs.formIntersection(available)
                if selectedIDs.isEmpty, let selectionID {
                    selectedIDs = [selectionID]
                }
                selectionAnchorID = selectionID
                duplicateScanTask = nil
            } catch is CancellationError {
                if catalogCollection == .exactDuplicates {
                    isScanning = false
                    duplicateScanProgress = nil
                }
                duplicateScanTask = nil
            } catch {
                guard catalogCollection == .exactDuplicates else {
                    return
                }
                catalogError = error.localizedDescription
                isScanning = false
                duplicateScanProgress = nil
                duplicateScanTask = nil
            }
        }
    }

    private func setDuplicateScanProgress(
        _ progress: CatalogDuplicateScanProgress
    ) {
        guard catalogCollection == .exactDuplicates else { return }
        duplicateScanProgress = progress
    }

    private func applyDuplicateGroups(
        _ groups: [CatalogExactDuplicateGroup]
    ) {
        exactDuplicateGroups = groups
        duplicateOrderByID = [:]
        duplicateGroupNumberByID = [:]
        duplicateAnchorIDs = []
        duplicateHashByID = [:]
        duplicateBasisByID = [:]

        var rank = 0
        for (groupOffset, group) in groups.enumerated() {
            if let anchorID = group.anchorID {
                duplicateAnchorIDs.insert(anchorID)
            }
            for member in group.members {
                duplicateOrderByID[member.id] = rank
                duplicateGroupNumberByID[member.id] =
                    groupOffset + 1
                duplicateHashByID[member.id] = group.contentHash
                duplicateBasisByID[member.id] =
                    group.matchBasis
                rank += 1
            }
        }
    }

    private func clearDuplicateReview() {
        exactDuplicateGroups = []
        duplicateScanResult = nil
        duplicateOrderByID = [:]
        duplicateGroupNumberByID = [:]
        duplicateAnchorIDs = []
        duplicateHashByID = [:]
        duplicateBasisByID = [:]
    }

    public func showSavedSmartCollection(
        _ collection: SavedSmartCollection
    ) {
        catalogCollection = nil
        activePhotoCollection = nil
        importDisplayTitle = nil
        activeSavedCollection = collection
        startCatalogLoad(
            source: .builtIn(.allPhotos),
            filterToApply: collection.filter
        )
    }

    @discardableResult
    public func saveCurrentFilterAsSmartCollection(
        named name: String,
        parentSetID: UUID? = nil
    ) -> SavedSmartCollection? {
        guard filter.isActive else { return nil }
        let collection = SavedSmartCollection(
            name: name,
            filter: filter,
            parentSetID: parentSetID
        )
        do {
            try catalogStore.saveSmartCollection(collection)
            refreshCollectionOrganization()
            return savedSmartCollections.first {
                $0.id == collection.id
            } ?? collection
        } catch {
            catalogError = error.localizedDescription
            return nil
        }
    }

    public func deleteSmartCollection(_ collection: SavedSmartCollection) {
        let wasActive = activeSavedCollection?.id == collection.id
        do {
            try catalogStore.deleteSmartCollection(id: collection.id)
            refreshCollectionOrganization()
            if wasActive {
                showCatalog(.allPhotos)
            }
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public var targetPhotoCollection: CatalogPhotoCollection? {
        photoCollections.first(where: \.isTarget)
    }

    public func collectionSets(
        in parentSetID: UUID?
    ) -> [CatalogCollectionSet] {
        collectionSets
            .filter { $0.parentSetID == parentSetID }
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
    }

    public func photoCollections(
        in parentSetID: UUID?
    ) -> [CatalogPhotoCollection] {
        photoCollections
            .filter { $0.parentSetID == parentSetID }
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
    }

    public func smartCollections(
        in parentSetID: UUID?
    ) -> [SavedSmartCollection] {
        savedSmartCollections
            .filter { $0.parentSetID == parentSetID }
            .sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
    }

    public func showPhotoCollection(
        _ collection: CatalogPhotoCollection
    ) {
        catalogCollection = nil
        activeSavedCollection = nil
        activePhotoCollection = collection
        importDisplayTitle = nil
        startCatalogLoad(
            source: .photoCollection(collection.id),
            filterToApply: FilterState(
                searchText: filter.searchText
            )
        )
    }

    @discardableResult
    public func createCollectionSet(
        named name: String,
        parentSetID: UUID? = nil
    ) -> CatalogCollectionSet? {
        let collectionSet = CatalogCollectionSet(
            name: name,
            parentSetID: parentSetID
        )
        do {
            try catalogStore.saveCollectionSet(collectionSet)
            refreshCollectionOrganization()
            return collectionSet
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Collection set failed",
                message: error.localizedDescription
            )
            return nil
        }
    }

    @discardableResult
    public func createPhotoCollection(
        named name: String,
        parentSetID: UUID? = nil,
        includeSelectedPhotos: Bool = true
    ) -> CatalogPhotoCollection? {
        let collection = CatalogPhotoCollection(
            name: name,
            parentSetID: parentSetID
        )
        let selectedPhotoIDs = includeSelectedPhotos
            ? currentSelectionInAssetOrder()
            : []
        do {
            try catalogStore.savePhotoCollection(collection)
            do {
                if !selectedPhotoIDs.isEmpty {
                    try catalogStore.setPhotoCollectionMembership(
                        collectionID: collection.id,
                        photoIDs: selectedPhotoIDs,
                        included: true
                    )
                }
            } catch {
                try? catalogStore.deletePhotoCollection(
                    id: collection.id
                )
                throw error
            }
            refreshCollectionOrganization()
            sidecarNotice = SidecarNotice(
                title: "Collection created",
                message:
                    "\(collection.name) contains \(selectedPhotoIDs.count) photo\(selectedPhotoIDs.count == 1 ? "" : "s"). No image file was moved or copied."
            )
            return photoCollections.first {
                $0.id == collection.id
            } ?? collection
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Collection failed",
                message: error.localizedDescription
            )
            return nil
        }
    }

    @discardableResult
    public func saveQuickCollection(
        named name: String,
        parentSetID: UUID? = nil,
        clearAfterSaving: Bool
    ) -> CatalogPhotoCollection? {
        let collection = CatalogPhotoCollection(
            name: name,
            parentSetID: parentSetID
        )
        do {
            let copiedCount = try catalogStore.saveQuickCollection(
                as: collection,
                clearQuickCollection: clearAfterSaving
            )
            refreshQuickCollectionMembership()
            refreshCollectionOrganization()
            refreshCatalogSummary()
            if clearAfterSaving,
               catalogCollection == .quickCollection {
                assets = []
                selectionID = nil
                selectedIDs = []
                selectionAnchorID = nil
            }
            sidecarNotice = SidecarNotice(
                title: "Quick Collection saved",
                message:
                    "\(collection.name) contains \(copiedCount) photo\(copiedCount == 1 ? "" : "s").\(clearAfterSaving ? " Quick Collection was cleared." : "") No image file was moved or copied."
            )
            return photoCollections.first {
                $0.id == collection.id
            } ?? collection
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Save Quick Collection failed",
                message: error.localizedDescription
            )
            return nil
        }
    }

    @discardableResult
    public func duplicatePhotoCollection(
        _ collection: CatalogPhotoCollection
    ) -> CatalogPhotoCollection? {
        do {
            let duplicate =
                try catalogStore.duplicatePhotoCollection(
                    id: collection.id
                )
            refreshCollectionOrganization()
            sidecarNotice = SidecarNotice(
                title: "Collection duplicated",
                message:
                    "\(duplicate.name) contains the same \(duplicate.photoCount) photo\(duplicate.photoCount == 1 ? "" : "s"). No image file was copied."
            )
            return photoCollections.first {
                $0.id == duplicate.id
            } ?? duplicate
        } catch {
            catalogError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func duplicateCollectionSet(
        _ collectionSet: CatalogCollectionSet
    ) -> CatalogCollectionSet? {
        do {
            let duplicate =
                try catalogStore.duplicateCollectionSet(
                    id: collectionSet.id
                )
            refreshCollectionOrganization()
            sidecarNotice = SidecarNotice(
                title: "Collection set duplicated",
                message:
                    "\(duplicate.name) contains independent copies of the set's collections and memberships. No image file was copied."
            )
            return collectionSets.first {
                $0.id == duplicate.id
            } ?? duplicate
        } catch {
            catalogError = error.localizedDescription
            return nil
        }
    }

    public func collectionSetPath(
        _ collectionSet: CatalogCollectionSet
    ) -> String {
        let byID = Dictionary(
            uniqueKeysWithValues: collectionSets.map {
                ($0.id, $0)
            }
        )
        var names: [String] = [collectionSet.name]
        var current = collectionSet.parentSetID
        var visited: Set<UUID> = [collectionSet.id]
        while let currentID = current,
              visited.insert(currentID).inserted,
              let parent = byID[currentID] {
            names.append(parent.name)
            current = parent.parentSetID
        }
        return names.reversed().joined(separator: " / ")
    }

    public func availableParentCollectionSets(
        excludingSubtreeOf collectionSetID: UUID? = nil
    ) -> [CatalogCollectionSet] {
        guard let collectionSetID else {
            return collectionSets.sorted {
                collectionSetPath($0)
                    .localizedStandardCompare(
                        collectionSetPath($1)
                    ) == .orderedAscending
            }
        }
        let children = Dictionary(
            grouping: collectionSets,
            by: \.parentSetID
        )
        var excluded: Set<UUID> = []
        var pending = [collectionSetID]
        while let current = pending.popLast() {
            guard excluded.insert(current).inserted else {
                continue
            }
            pending.append(
                contentsOf:
                    (children[current] ?? []).map(\.id)
            )
        }
        return collectionSets
            .filter { !excluded.contains($0.id) }
            .sorted {
                collectionSetPath($0)
                    .localizedStandardCompare(
                        collectionSetPath($1)
                    ) == .orderedAscending
            }
    }

    @discardableResult
    public func updateCollectionSet(
        _ collectionSet: CatalogCollectionSet,
        name: String,
        parentSetID: UUID?
    ) -> Bool {
        var updated = collectionSet
        updated.name = CatalogCollectionSet(
            id: collectionSet.id,
            name: name,
            parentSetID: parentSetID,
            createdAt: collectionSet.createdAt
        ).name
        updated.parentSetID = parentSetID
        do {
            try catalogStore.saveCollectionSet(updated)
            refreshCollectionOrganization()
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Collection set failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func updatePhotoCollection(
        _ collection: CatalogPhotoCollection,
        name: String,
        parentSetID: UUID?
    ) -> Bool {
        var updated = collection
        updated.name = CatalogPhotoCollection(
            id: collection.id,
            name: name,
            parentSetID: parentSetID,
            createdAt: collection.createdAt,
            isTarget: collection.isTarget,
            photoCount: collection.photoCount
        ).name
        updated.parentSetID = parentSetID
        do {
            try catalogStore.savePhotoCollection(updated)
            refreshCollectionOrganization()
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Collection failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func moveSmartCollection(
        _ collection: SavedSmartCollection,
        to parentSetID: UUID?
    ) -> Bool {
        var updated = collection
        updated.parentSetID = parentSetID
        do {
            try catalogStore.saveSmartCollection(updated)
            refreshCollectionOrganization()
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Smart collection failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func updateSmartCollection(
        _ collection: SavedSmartCollection,
        name: String,
        parentSetID: UUID?
    ) -> Bool {
        let updated = SavedSmartCollection(
            id: collection.id,
            name: name,
            filter: collection.filter,
            createdAt: collection.createdAt,
            parentSetID: parentSetID
        )
        do {
            try catalogStore.saveSmartCollection(updated)
            refreshCollectionOrganization()
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Smart collection failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func duplicateSmartCollection(
        _ collection: SavedSmartCollection
    ) -> SavedSmartCollection? {
        let duplicate = SavedSmartCollection(
            name: "\(collection.name) Copy",
            filter: collection.filter,
            parentSetID: collection.parentSetID
        )
        do {
            try catalogStore.saveSmartCollection(duplicate)
            refreshCollectionOrganization()
            return savedSmartCollections.first {
                $0.id == duplicate.id
            } ?? duplicate
        } catch {
            catalogError = error.localizedDescription
            return nil
        }
    }

    public func deletePhotoCollection(
        _ collection: CatalogPhotoCollection
    ) {
        do {
            try catalogStore.deletePhotoCollection(id: collection.id)
            let wasActive =
                activePhotoCollection?.id == collection.id
            refreshCollectionOrganization()
            sidecarNotice = SidecarNotice(
                title: "Collection deleted",
                message:
                    "\(collection.name) was removed. No catalog photo or image file was deleted."
            )
            if wasActive {
                showCatalog(.allPhotos)
            }
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func deleteCollectionSet(
        _ collectionSet: CatalogCollectionSet
    ) {
        let activePhotoID = activePhotoCollection?.id
        let activeSmartID = activeSavedCollection?.id
        do {
            try catalogStore.deleteCollectionSet(id: collectionSet.id)
            refreshCollectionOrganization()
            sidecarNotice = SidecarNotice(
                title: "Collection set deleted",
                message:
                    "\(collectionSet.name) and its contained collections were removed. No catalog photo or image file was deleted."
            )
            if activePhotoID != nil
                    && !photoCollections.contains(where: {
                        $0.id == activePhotoID
                    })
                || activeSmartID != nil
                    && !savedSmartCollections.contains(where: {
                        $0.id == activeSmartID
                    }) {
                showCatalog(.allPhotos)
            }
        } catch {
            catalogError = error.localizedDescription
        }
    }

    @discardableResult
    public func setTargetPhotoCollection(
        _ collection: CatalogPhotoCollection?
    ) -> Bool {
        do {
            try catalogStore.setTargetPhotoCollection(
                id: collection?.id
            )
            refreshCollectionOrganization()
            sidecarNotice = SidecarNotice(
                title: "Target Collection",
                message: collection.map {
                    "B now adds or removes photos in \($0.name)."
                } ?? "B now adds or removes photos in Quick Collection."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            return false
        }
    }

    public func isInPhotoCollection(
        _ id: PhotoAsset.ID,
        collectionID: UUID
    ) -> Bool {
        photoCollectionMemberships[id]?.contains(collectionID)
            == true
    }

    public func isInAnyPhotoCollection(
        _ id: PhotoAsset.ID
    ) -> Bool {
        !(photoCollectionMemberships[id] ?? []).isEmpty
    }

    public func collectionsContaining(
        _ id: PhotoAsset.ID
    ) -> [CatalogPhotoCollection] {
        let memberships = photoCollectionMemberships[id] ?? []
        return photoCollections.filter {
            memberships.contains($0.id)
        }
    }

    public func willAddToPhotoCollection(
        _ collection: CatalogPhotoCollection,
        for id: PhotoAsset.ID
    ) -> Bool {
        !mutationTargets(for: id).allSatisfy {
            isInPhotoCollection(
                $0,
                collectionID: collection.id
            )
        }
    }

    @discardableResult
    public func setPhotoCollectionMembership(
        _ collection: CatalogPhotoCollection,
        for id: PhotoAsset.ID,
        included: Bool
    ) -> Bool {
        let targets = mutationTargets(for: id)
        guard !targets.isEmpty else { return false }
        do {
            let changed =
                try catalogStore.setPhotoCollectionMembership(
                    collectionID: collection.id,
                    photoIDs: targets,
                    included: included
                )
            refreshCollectionOrganization()
            if activePhotoCollection?.id == collection.id,
               !included {
                removeVisibleAssets(withIDs: Set(targets))
            }
            sidecarNotice = SidecarNotice(
                title: collection.name,
                message:
                    "\(included ? "Added" : "Removed") \(targets.count) photo\(targets.count == 1 ? "" : "s") \(included ? "to" : "from") the collection. No image file or catalog photo was deleted."
            )
            return changed > 0
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Collection failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func togglePhotoCollectionMembership(
        _ collection: CatalogPhotoCollection,
        for id: PhotoAsset.ID
    ) -> Bool {
        setPhotoCollectionMembership(
            collection,
            for: id,
            included: willAddToPhotoCollection(
                collection,
                for: id
            )
        )
    }

    @discardableResult
    public func toggleTargetCollectionForSelection() -> Bool {
        guard let selectionID else { return false }
        if let targetPhotoCollection {
            return togglePhotoCollectionMembership(
                targetPhotoCollection,
                for: selectionID
            )
        }
        return toggleQuickCollection(for: selectionID)
    }

    @discardableResult
    public func removeSelectionFromActivePhotoCollection() -> Bool {
        guard let collection = activePhotoCollection,
              let selectionID else {
            return false
        }
        return togglePhotoCollectionMembership(
            collection,
            for: selectionID
        )
    }

    @discardableResult
    public func movePhotoInActiveCollection(
        _ id: PhotoAsset.ID,
        _ move: CatalogCollectionMemberMove
    ) -> Bool {
        guard let collection = activePhotoCollection,
              let index = assets.firstIndex(where: {
                  $0.id == id
              }) else {
            return false
        }
        var reordered = assets
        let destination: Int
        switch move {
        case .beginning:
            destination = 0
        case .up:
            destination = max(0, index - 1)
        case .down:
            destination = min(reordered.count - 1, index + 1)
        case .end:
            destination = reordered.count - 1
        }
        guard destination != index else { return false }
        let asset = reordered.remove(at: index)
        reordered.insert(asset, at: destination)
        do {
            try catalogStore.reorderPhotoCollection(
                collectionID: collection.id,
                photoIDs: reordered.map(\.id)
            )
            assets = reordered
            return true
        } catch {
            catalogError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func movePhotoInActiveCollection(
        _ id: PhotoAsset.ID,
        before targetID: PhotoAsset.ID
    ) -> Bool {
        guard let collection = activePhotoCollection,
              id != targetID,
              let sourceIndex = assets.firstIndex(where: {
                  $0.id == id
              }),
              assets.contains(where: {
                  $0.id == targetID
              }) else {
            return false
        }
        var reordered = assets
        let asset = reordered.remove(at: sourceIndex)
        guard let destination = reordered.firstIndex(where: {
            $0.id == targetID
        }) else {
            return false
        }
        reordered.insert(asset, at: destination)
        do {
            try catalogStore.reorderPhotoCollection(
                collectionID: collection.id,
                photoIDs: reordered.map(\.id)
            )
            assets = reordered
            return true
        } catch {
            catalogError = error.localizedDescription
            return false
        }
    }

    public func isInQuickCollection(
        _ id: PhotoAsset.ID
    ) -> Bool {
        quickCollectionPhotoIDs.contains(id)
    }

    public func willAddToQuickCollection(
        for id: PhotoAsset.ID
    ) -> Bool {
        !mutationTargets(for: id).allSatisfy {
            quickCollectionPhotoIDs.contains($0)
        }
    }

    @discardableResult
    public func toggleQuickCollection(
        for id: PhotoAsset.ID
    ) -> Bool {
        let targets = mutationTargets(for: id)
        guard !targets.isEmpty else { return false }
        let shouldInclude = willAddToQuickCollection(for: id)
        do {
            let changed = try catalogStore
                .setQuickCollectionMembership(
                    photoIDs: targets,
                    included: shouldInclude
                )
            refreshQuickCollectionMembership()
            refreshCatalogSummary()

            if catalogCollection == .quickCollection,
               !shouldInclude {
                let removed = Set(targets)
                assets.removeAll { removed.contains($0.id) }
                selectedIDs.subtract(removed)
                selectionID = Self.selectionAfterScan(
                    current:
                        selectionID.flatMap {
                            removed.contains($0) ? nil : $0
                        },
                    assets: assets
                )
                if selectedIDs.isEmpty, let selectionID {
                    selectedIDs = [selectionID]
                }
                selectionAnchorID = selectionID
            }

            let action = shouldInclude ? "Added" : "Removed"
            sidecarNotice = SidecarNotice(
                title: "Quick Collection",
                message:
                    "\(action) \(targets.count) photo\(targets.count == 1 ? "" : "s") \(shouldInclude ? "to" : "from") Quick Collection. No image file or catalog photo was deleted."
            )
            return changed > 0
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Quick Collection failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func toggleQuickCollectionForSelection() -> Bool {
        guard let selectionID else { return false }
        return toggleQuickCollection(for: selectionID)
    }

    @discardableResult
    public func clearQuickCollection() -> Bool {
        do {
            let removedCount =
                try catalogStore.clearQuickCollection()
            refreshQuickCollectionMembership()
            refreshCatalogSummary()
            if catalogCollection == .quickCollection {
                assets = []
                selectionID = nil
                selectedIDs = []
                selectionAnchorID = nil
            }
            sidecarNotice = SidecarNotice(
                title: "Quick Collection cleared",
                message:
                    "Removed \(removedCount) photo\(removedCount == 1 ? "" : "s") from Quick Collection. No image file or catalog photo was deleted."
            )
            return removedCount > 0
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Quick Collection failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    public func locateMissingPhoto(_ id: PhotoAsset.ID) {
        guard let asset = assets.first(where: { $0.id == id }),
              asset.catalogMissing else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Relink"
        panel.message =
            "Choose the current location of \(asset.filename)."
        panel.nameFieldStringValue = asset.filename
        panel.allowedContentTypes = FileTypeDetector.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = nearestExistingDirectory(
            from: asset.url.deletingLastPathComponent()
        )
        if panel.runModal() == .OK, let url = panel.url {
            _ = relinkMissingPhoto(id, to: url)
        }
    }

    @discardableResult
    public func relinkMissingPhoto(
        _ id: PhotoAsset.ID,
        to replacementURL: URL
    ) -> Bool {
        guard let index = assets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        flushPendingPersistence()
        do {
            let result = try catalogStore.relinkPhoto(
                id: id,
                to: replacementURL
            )
            let replacement = result.entry.asset
            let replacementID = replacement.id
            userStateStore.set(
                id: replacementID,
                state: replacement.userState
            )
            if replacementID != id {
                userStateStore.remove(id: id)
                if let undo = adjustmentUndo.removeValue(forKey: id) {
                    adjustmentUndo[replacementID] = undo
                }
                if let redo = adjustmentRedo.removeValue(forKey: id) {
                    adjustmentRedo[replacementID] = redo
                }
                selectedIDs.remove(id)
                selectedIDs.insert(replacementID)
                if selectionID == id {
                    selectionID = replacementID
                }
                if selectionAnchorID == id {
                    selectionAnchorID = replacementID
                }
            }
            assets[index] = replacement
            refreshQuickCollectionMembership()
            refreshCollectionOrganization()
            refreshPhotoStacks()
            reconcileCatalogMembership(for: replacementID)
            refreshCatalogSummary()
            sidecarNotice = SidecarNotice(
                title: "Photo relinked",
                message:
                    "\(replacement.filename) is connected to its new location. Existing edits and organization metadata were preserved."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Relink failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func removeFromCatalog(_ id: PhotoAsset.ID) -> Bool {
        guard assets.contains(where: { $0.id == id }) else { return false }
        flushPendingPersistence()
        do {
            try catalogStore.removePhoto(id: id)
            userStateStore.remove(id: id)
            assets.removeAll { $0.id == id }
            selectedIDs.remove(id)
            selectionID = Self.selectionAfterScan(
                current: selectionID == id ? nil : selectionID,
                assets: assets
            )
            if selectedIDs.isEmpty, let selectionID {
                selectedIDs = [selectionID]
            }
            selectionAnchorID = selectionID
            adjustmentUndo[id] = nil
            adjustmentRedo[id] = nil
            refreshQuickCollectionMembership()
            refreshCollectionOrganization()
            refreshPhotoStacks()
            refreshCatalogSummary()
            sidecarNotice = SidecarNotice(
                title: "Removed from catalog",
                message:
                    "The catalog record was removed. RAWDesk did not delete or modify any image file."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            sidecarNotice = SidecarNotice(
                title: "Catalog removal failed",
                message: error.localizedDescription
            )
            return false
        }
    }

    private func startCatalogLoad(
        source: CatalogLoadSource,
        filterToApply: FilterState,
        preferredSelectionID: PhotoAsset.ID? = nil
    ) {
        scanTask?.cancel()
        catalogTask?.cancel()
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        duplicateScanTask = nil
        cullingScanTask = nil
        duplicateScanProgress = nil
        cullingScanProgress = nil
        clearDuplicateReview()
        clearCullingReview()
        flushPendingPersistence()
        filter = filterToApply
        scanError = nil
        catalogError = catalogStore.startupWarning
        rootURL = nil
        isScanning = true
        let previousSelection =
            preferredSelectionID ?? selectionID
        let catalogStore = catalogStore
        let states = userStateStore.loadAll()

        catalogTask = Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) {
                do {
                    try catalogStore.refreshMissingStatus()
                    let entries: [CatalogEntry]
                    switch source {
                    case let .builtIn(collection):
                        entries = try catalogStore.entries(
                            for: collection
                        )
                    case let .photoCollection(id):
                        entries = try catalogStore.entries(
                            forPhotoCollection: id
                        )
                    }
                    return (
                        entries: entries,
                        summary: try catalogStore.summary(),
                        stacks: try catalogStore.photoStacks(),
                        error: nil as String?
                    )
                } catch {
                    return (
                        entries: [] as [CatalogEntry],
                        summary: CatalogSummary(),
                        stacks: [] as [CatalogPhotoStack],
                        error: error.localizedDescription
                    )
                }
            }.value
            guard !Task.isCancelled, let self else { return }

            var loadedAssets: [PhotoAsset] = []
            loadedAssets.reserveCapacity(loaded.entries.count)
            for entry in loaded.entries {
                var asset = entry.asset
                if let localState = states[entry.id] {
                    asset.userState = localState
                } else {
                    self.userStateStore.set(
                        id: entry.id,
                        state: entry.userState
                    )
                }
                loadedAssets.append(asset)
            }
            self.assets = loadedAssets
            self.photoStacks = loaded.stacks
            self.catalogSummary = loaded.summary
            self.catalogError = loaded.error
                ?? self.catalogStore.startupWarning
            self.isScanning = false
            self.selectionID = Self.selectionAfterScan(
                current: previousSelection,
                assets: loadedAssets
            )
            let available = Set(loadedAssets.map(\.id))
            if let preferredSelectionID,
               available.contains(preferredSelectionID) {
                self.selectedIDs = [preferredSelectionID]
            } else {
                self.selectedIDs.formIntersection(available)
            }
            if self.selectedIDs.isEmpty,
               let selectionID = self.selectionID {
                self.selectedIDs = [selectionID]
            }
            self.selectionAnchorID = self.selectionID
        }
    }

    private func applyImportResult(_ result: PhotoImportResult) {
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        duplicateScanProgress = nil
        cullingScanProgress = nil
        clearDuplicateReview()
        clearCullingReview()
        refreshPhotoStacks()
        for asset in result.importedAssets {
            userStateStore.set(id: asset.id, state: asset.userState)
        }
        refreshCatalogSummary()
        guard !result.importedAssets.isEmpty else { return }

        scanTask?.cancel()
        catalogTask?.cancel()
        catalogCollection = nil
        activeSavedCollection = nil
        activePhotoCollection = nil
        importDisplayTitle = "Last Import"
        rootURL = nil
        filter = FilterState()
        assets = result.importedAssets
        selectionID = Self.selectionAfterScan(
            current: nil,
            assets: result.importedAssets
        )
        selectedIDs = selectionID.map { [$0] } ?? []
        selectionAnchorID = selectionID
    }

    nonisolated static func selectionAfterScan(current: PhotoAsset.ID?, assets: [PhotoAsset]) -> PhotoAsset.ID? {
        if let current, assets.contains(where: { $0.id == current }) {
            return current
        }
        return assets.first?.id
    }

    nonisolated static func selectionForVisibleAssets(
        current: PhotoAsset.ID?,
        assets: [PhotoAsset],
        filter: FilterState
    ) -> PhotoAsset.ID? {
        let visible = filter.isActive ? assets.filter { filter.matches($0) } : assets
        if let current, visible.contains(where: { $0.id == current }) {
            return current
        }
        return visible.first?.id
    }

    private func reconcileSelectionWithFilter() {
        if referenceState != nil {
            reconcileReferenceState()
            return
        }
        if compareState != nil {
            reconcileCompareState()
            return
        }
        if surveyState != nil {
            reconcileSurveyState()
            return
        }
        let visible = filtered
        if let selectionID,
           !visible.contains(where: { $0.id == selectionID }) {
            self.selectionID = visible.first?.id
        } else if selectionID == nil {
            selectionID = visible.first?.id
        }
        let visibleIDs = Set(visible.map(\.id))
        selectedIDs.formIntersection(visibleIDs)
        if selectedIDs.isEmpty, let selectionID {
            selectedIDs = [selectionID]
        }
        selectionAnchorID = selectionID
    }

    public func reopen(recent url: URL) {
        if let bm = recentStore.bookmark(for: url),
           let resolved = SecurityScopedBookmarkStore.resolve(bookmark: bm) {
            if resolved.needsStopAccess {
                bookmarkURLs.append(resolved.url)
            }
            open(folder: resolved.url)
        } else {
            open(folder: url)
        }
    }

    @discardableResult
    public func restoreLastWorkspaceIfAvailable()
        -> PhotoWorkspaceMode? {
        guard !hasAttemptedWorkspaceRestore else {
            return nil
        }
        hasAttemptedWorkspaceRestore = true
        guard rootURL == nil, assets.isEmpty else {
            return nil
        }

        if let snapshot =
            recentStore.workspaceSnapshot() {
            let url = URL(
                fileURLWithPath: snapshot.rootPath,
                isDirectory: true
            )
            if FileManager.default.fileExists(
                atPath: url.path
            ) {
                pendingWorkspaceSelectionID =
                    snapshot.selectionID
                reopen(recent: url)
                return snapshot.photoWorkspace
            }
        }

        if let url = recentFolders.first(
            where: {
                FileManager.default.fileExists(
                    atPath: $0.path
                )
            }
        ) {
            reopen(recent: url)
            return .library
        }

        // Add imports are catalog-backed and do not establish an opened
        // folder workspace. Restore the catalog itself so a relaunch does
        // not incorrectly return to the empty Welcome screen.
        if catalogSummary[.allPhotos] > 0 {
            showCatalog(.allPhotos)
            return .library
        }

        return nil
    }

    public func persistWorkspace(
        photoWorkspace: PhotoWorkspaceMode
    ) {
        guard let rootURL else { return }
        recentStore.recordWorkspace(
            rootURL: rootURL,
            selectionID: selectionID,
            photoWorkspace: photoWorkspace
        )
    }

    public func cancelScan() {
        scanTask?.cancel()
        catalogTask?.cancel()
        duplicateScanTask?.cancel()
        cullingScanTask?.cancel()
        scanTask = nil
        catalogTask = nil
        duplicateScanTask = nil
        cullingScanTask = nil
        duplicateScanProgress = nil
        cullingScanProgress = nil
        isScanning = false
    }

    public func removeRecent(_ url: URL) {
        recentStore.remove(url: url)
        recentFolders = recentStore.recents()
    }

    public func clearRecents() {
        recentStore.clear()
        recentFolders = recentStore.recents()
    }

    // MARK: - Compare

    public func toggleCompare() {
        if compareState == nil {
            startCompare()
        } else {
            endCompare()
        }
    }

    public func startCompare() {
        guard workspaceMode == .library else { return }
        let survey = surveyState
        let reference = referenceState
        let primaryID =
            survey?.activeID
            ?? reference?.activeID
            ?? selectionID
        let referenceIDs: Set<PhotoAsset.ID>? =
            reference.map { state in
                var ids = [state.activeID]
                if let referenceID = state.referenceID {
                    ids.append(referenceID)
                }
                return Set(ids)
            }
        let selectedIDs =
            survey.map { Set($0.photoIDs) }
            ?? referenceIDs
            ?? self.selectedIDs
        guard let state = PhotoComparePlanner.start(
            primaryID: primaryID,
            selectedIDs: selectedIDs,
            visibleIDs: filtered.map(\.id)
        ) else {
            return
        }
        surveyState = nil
        applyCompareState(state)
    }

    public func endCompare() {
        compareState = nil
    }

    public func setCompareCandidate(_ id: PhotoAsset.ID) {
        guard let compareState,
              let state = PhotoComparePlanner.settingCandidate(
                id,
                in: compareState,
                visibleIDs: filtered.map(\.id)
              ) else {
            return
        }
        applyCompareState(state)
    }

    public func moveCompareCandidate(direction: Int) {
        guard let compareState,
              let state = PhotoComparePlanner.movingCandidate(
                in: compareState,
                direction: direction,
                visibleIDs: filtered.map(\.id)
              ) else {
            return
        }
        applyCompareState(state)
    }

    public func promoteCompareCandidate() {
        guard let compareState,
              let state = PhotoComparePlanner.promotingCandidate(
                in: compareState,
                visibleIDs: filtered.map(\.id)
              ) else {
            endCompare()
            return
        }
        applyCompareState(state)
    }

    public func swapComparePhotos() {
        guard let compareState,
              let state = PhotoComparePlanner.swapping(
                compareState,
                visibleIDs: filtered.map(\.id)
              ) else {
            endCompare()
            return
        }
        applyCompareState(state)
    }

    public func reconcileCompareState() {
        guard let compareState else { return }
        guard let state = PhotoComparePlanner.reconcile(
            compareState,
            visibleIDs: filtered.map(\.id)
        ) else {
            endCompare()
            reconcileSelectionWithFilter()
            return
        }
        applyCompareState(state)
    }

    public func compareRole(
        for id: PhotoAsset.ID
    ) -> PhotoCompareRole? {
        guard let compareState else { return nil }
        if compareState.selectID == id {
            return .select
        }
        if compareState.candidateID == id {
            return .candidate
        }
        return nil
    }

    public var compareCandidatePosition:
        (position: Int, total: Int)? {
        guard let candidateID = compareState?.candidateID else {
            return nil
        }
        let visibleIDs = filtered.map(\.id)
        guard let index = visibleIDs.firstIndex(of: candidateID) else {
            return nil
        }
        return (index + 1, visibleIDs.count)
    }

    private func applyCompareState(
        _ state: PhotoCompareState
    ) {
        captureReferenceLockAndClear()
        surveyState = nil
        compareState = state
        selectionID = state.candidateID
        selectedIDs = [state.candidateID]
        selectionAnchorID = state.candidateID
    }

    // MARK: - Survey

    public func toggleSurvey() {
        if surveyState == nil {
            startSurvey()
        } else {
            endSurvey()
        }
    }

    public func startSurvey() {
        guard workspaceMode == .library else { return }
        let comparison = compareState
        let reference = referenceState
        let primaryID =
            comparison?.candidateID
            ?? reference?.activeID
            ?? selectionID
        let referenceIDs: Set<PhotoAsset.ID>? =
            reference.flatMap { state in
                guard let referenceID = state.referenceID else {
                    return nil
                }
                return Set([state.activeID, referenceID])
            }
        let selectedIDs =
            comparison.map {
                Set([$0.selectID, $0.candidateID])
            }
            ?? referenceIDs
            ?? self.selectedIDs
        guard let state = PhotoSurveyPlanner.start(
            primaryID: primaryID,
            selectedIDs: selectedIDs,
            visibleIDs: filtered.map(\.id)
        ) else {
            return
        }
        compareState = nil
        applySurveyState(state)
    }

    public func endSurvey() {
        surveyState = nil
    }

    public func setSurveyActive(_ id: PhotoAsset.ID) {
        guard let surveyState,
              let state = PhotoSurveyPlanner.activating(
                id,
                in: surveyState,
                visibleIDs: filtered.map(\.id)
              ) else {
            return
        }
        applySurveyState(state)
    }

    public func addSurveyPhoto(_ id: PhotoAsset.ID) {
        guard let surveyState,
              let state = PhotoSurveyPlanner.adding(
                id,
                to: surveyState,
                visibleIDs: filtered.map(\.id)
              ) else {
            return
        }
        applySurveyState(state)
    }

    public func moveSurveyActive(direction: Int) {
        guard let surveyState,
              let state = PhotoSurveyPlanner.movingActive(
                in: surveyState,
                direction: direction,
                visibleIDs: filtered.map(\.id)
              ) else {
            return
        }
        applySurveyState(state)
    }

    public func removeSurveyPhoto(_ id: PhotoAsset.ID) {
        guard let surveyState else { return }
        if let state = PhotoSurveyPlanner.removing(
            id,
            from: surveyState,
            visibleIDs: filtered.map(\.id)
        ) {
            applySurveyState(state)
            return
        }
        finishSurveySelection(
            photoIDs: surveyState.photoIDs.filter { $0 != id },
            preferredActive:
                surveyState.activeID == id
                ? nil
                : surveyState.activeID
        )
    }

    public func keepOnlyActiveSurveyPhoto() {
        guard let activeID = surveyState?.activeID else { return }
        surveyState = nil
        selectionID = activeID
        selectedIDs = [activeID]
        selectionAnchorID = activeID
    }

    public func reconcileSurveyState() {
        guard let surveyState else { return }
        guard let state = PhotoSurveyPlanner.reconcile(
            surveyState,
            visibleIDs: filtered.map(\.id)
        ) else {
            let visibleIDs = Set(filtered.map(\.id))
            finishSurveySelection(
                photoIDs: surveyState.photoIDs.filter(
                    visibleIDs.contains
                ),
                preferredActive: surveyState.activeID
            )
            return
        }
        applySurveyState(state)
    }

    public func surveyRole(
        for id: PhotoAsset.ID
    ) -> PhotoSurveyRole? {
        guard let surveyState,
              surveyState.photoIDs.contains(id) else {
            return nil
        }
        return surveyState.activeID == id
            ? .active
            : .selected
    }

    private func applySurveyState(
        _ state: PhotoSurveyState
    ) {
        captureReferenceLockAndClear()
        compareState = nil
        surveyState = state
        selectionID = state.activeID
        selectedIDs = Set(state.photoIDs)
        selectionAnchorID = state.activeID
    }

    private func finishSurveySelection(
        photoIDs: [PhotoAsset.ID],
        preferredActive: PhotoAsset.ID?
    ) {
        surveyState = nil
        let visibleIDs = Set(filtered.map(\.id))
        let remaining = photoIDs.filter(visibleIDs.contains)
        let activeID =
            preferredActive.flatMap {
                remaining.contains($0) ? $0 : nil
            }
            ?? remaining.first
            ?? filtered.first?.id
        selectionID = activeID
        selectedIDs =
            remaining.isEmpty
            ? activeID.map { Set([$0]) } ?? []
            : Set(remaining)
        selectionAnchorID = activeID
    }

    // MARK: - Reference View

    public func toggleReferenceView() {
        if referenceState == nil {
            startReferenceView()
        } else {
            endReferenceView()
        }
    }

    public func startReferenceView() {
        guard workspaceMode == .library else { return }
        let comparison = compareState
        let survey = surveyState
        let activeID =
            survey?.activeID
            ?? comparison?.candidateID
            ?? selectionID
        let selectedIDs: Set<PhotoAsset.ID>
        if let survey {
            selectedIDs = Set(survey.photoIDs)
        } else if let comparison {
            selectedIDs = Set([
                comparison.selectID,
                comparison.candidateID,
            ])
        } else {
            selectedIDs = self.selectedIDs
        }
        guard let state = PhotoReferencePlanner.start(
            activeID: activeID,
            selectedIDs: selectedIDs,
            visibleIDs: filtered.map(\.id),
            availableIDs: Set(assets.map(\.id)),
            lockedReferenceID: lockedReferenceID,
            layout: referenceLayoutPreference
        ) else {
            return
        }
        applyReferenceState(state)
    }

    public func endReferenceView() {
        captureReferenceLockAndClear()
    }

    public func setReferencePhoto(_ id: PhotoAsset.ID) {
        guard let referenceState else { return }
        let state = PhotoReferencePlanner.settingReference(
            id,
            in: referenceState,
            availableIDs: Set(assets.map(\.id))
        )
        applyReferenceState(state)
    }

    public func clearReferencePhoto() {
        guard var state = referenceState else { return }
        state.referenceID = nil
        state.isReferenceLocked = false
        lockedReferenceID = nil
        applyReferenceState(state)
    }

    public func setReferenceActivePhoto(_ id: PhotoAsset.ID) {
        guard let referenceState else { return }
        let state = PhotoReferencePlanner.settingActive(
            id,
            in: referenceState,
            visibleIDs: filtered.map(\.id)
        )
        applyReferenceState(state)
    }

    public func moveReferenceActive(direction: Int) {
        guard let referenceState else { return }
        let state = PhotoReferencePlanner.movingActive(
            in: referenceState,
            direction: direction,
            visibleIDs: filtered.map(\.id)
        )
        applyReferenceState(state)
    }

    public func swapReferencePhotos() {
        guard let referenceState else { return }
        applyReferenceState(
            PhotoReferencePlanner.swapping(referenceState)
        )
    }

    public func setReferenceLayout(
        _ layout: PhotoReferenceLayout
    ) {
        guard var state = referenceState else { return }
        state.layout = layout
        referenceLayoutPreference = layout
        applyReferenceState(state)
    }

    public func setReferenceLocked(_ locked: Bool) {
        guard var state = referenceState else { return }
        state.isReferenceLocked =
            locked && state.referenceID != nil
        lockedReferenceID =
            state.isReferenceLocked
            ? state.referenceID
            : nil
        referenceState = state
    }

    public func reconcileReferenceState() {
        guard let referenceState else { return }
        guard let state = PhotoReferencePlanner.reconcile(
            referenceState,
            visibleIDs: filtered.map(\.id),
            availableIDs: Set(assets.map(\.id))
        ) else {
            captureReferenceLockAndClear()
            selectionID = nil
            selectedIDs = []
            selectionAnchorID = nil
            return
        }
        applyReferenceState(state)
    }

    public var referenceActivePosition:
        (position: Int, total: Int)? {
        guard let activeID = referenceState?.activeID else {
            return nil
        }
        let candidates = filtered.filter {
            $0.id != referenceState?.referenceID
        }
        guard let index = candidates.firstIndex(
            where: { $0.id == activeID }
        ) else {
            return nil
        }
        return (index + 1, candidates.count)
    }

    private func applyReferenceState(
        _ state: PhotoReferenceState
    ) {
        compareState = nil
        surveyState = nil
        referenceState = state
        referenceLayoutPreference = state.layout
        lockedReferenceID =
            state.isReferenceLocked
            ? state.referenceID
            : nil
        selectionID = state.activeID
        selectedIDs = [state.activeID]
        selectionAnchorID = state.activeID
    }

    private func captureReferenceLockAndClear() {
        guard let state = referenceState else { return }
        lockedReferenceID =
            state.isReferenceLocked
            ? state.referenceID
            : nil
        referenceState = nil
    }

    // MARK: - Selection navigation

    private var selectionAnchorID: PhotoAsset.ID?

    public var selectedAssets: [PhotoAsset] {
        assets.filter { selectedIDs.contains($0.id) }
    }

    public var canSelectAllVisiblePhotos: Bool {
        workspaceMode == .library
            && compareState == nil
            && surveyState == nil
            && referenceState == nil
            && !filtered.isEmpty
    }

    public func selectAllVisiblePhotos() {
        guard canSelectAllVisiblePhotos else { return }
        let visibleIDs = filtered.map(\.id)
        guard let firstID = visibleIDs.first else { return }
        let activeID =
            selectionID.flatMap {
                visibleIDs.contains($0) ? $0 : nil
            }
            ?? firstID
        selectedIDs = Set(visibleIDs)
        selectionID = activeID
        selectionAnchorID = activeID
    }

    public func select(
        _ id: PhotoAsset.ID,
        extending: Bool = false,
        range: Bool = false
    ) {
        let visible = filtered
        guard visible.contains(where: { $0.id == id }) else { return }

        if referenceState != nil {
            setReferenceActivePhoto(id)
            return
        }
        if compareState != nil {
            setCompareCandidate(id)
            return
        }
        if surveyState != nil {
            addSurveyPhoto(id)
            return
        }

        if range, let anchor = selectionAnchorID {
            let rangeIDs = Self.selectionRangeIDs(
                anchor: anchor,
                target: id,
                assets: visible
            )
            if extending {
                selectedIDs.formUnion(rangeIDs)
            } else {
                selectedIDs = rangeIDs
            }
            selectionID = id
            return
        }

        if extending {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
                if selectionID == id {
                    selectionID = visible.first(where: { selectedIDs.contains($0.id) })?.id
                }
            } else {
                selectedIDs.insert(id)
                selectionID = id
            }
            if selectedIDs.isEmpty {
                selectedIDs = [id]
                selectionID = id
            }
            selectionAnchorID = id
            return
        }

        selectionID = id
        selectedIDs = [id]
        selectionAnchorID = id
    }

    nonisolated static func selectionRangeIDs(
        anchor: PhotoAsset.ID,
        target: PhotoAsset.ID,
        assets: [PhotoAsset]
    ) -> Set<PhotoAsset.ID> {
        guard let anchorIndex = assets.firstIndex(where: { $0.id == anchor }),
              let targetIndex = assets.firstIndex(where: { $0.id == target }) else {
            return [target]
        }
        let lower = min(anchorIndex, targetIndex)
        let upper = max(anchorIndex, targetIndex)
        return Set(assets[lower...upper].map(\.id))
    }

    public func selectNext() {
        if referenceState != nil {
            moveReferenceActive(direction: 1)
            return
        }
        if compareState != nil {
            moveCompareCandidate(direction: 1)
            return
        }
        if surveyState != nil {
            moveSurveyActive(direction: 1)
            return
        }
        let visible = filtered
        guard !visible.isEmpty else { return }
        if let id = selectionID, let i = visible.firstIndex(where: { $0.id == id }) {
            let next = visible.index(after: i)
            if next < visible.endIndex {
                select(visible[next].id)
            }
        } else {
            if let id = visible.first?.id { select(id) }
        }
    }

    public func selectPrevious() {
        if referenceState != nil {
            moveReferenceActive(direction: -1)
            return
        }
        if compareState != nil {
            moveCompareCandidate(direction: -1)
            return
        }
        if surveyState != nil {
            moveSurveyActive(direction: -1)
            return
        }
        let visible = filtered
        guard !visible.isEmpty else { return }
        if let id = selectionID, let i = visible.firstIndex(where: { $0.id == id }) {
            if i > visible.startIndex {
                select(visible[visible.index(before: i)].id)
            }
        } else {
            if let id = visible.last?.id { select(id) }
        }
    }

    // MARK: - User state mutations

    public func setRating(_ rating: Int, for id: PhotoAsset.ID) {
        for target in mutationTargets(for: id) {
            mutateUserState(id: target) { $0.rating = max(0, min(5, rating)) }
        }
    }

    public func setColorLabel(
        _ colorLabel: PhotoColorLabel,
        for id: PhotoAsset.ID
    ) {
        let metadataValue = colorLabel == .none
            ? nil
            : activeColorLabelSet[colorLabel]
        for target in mutationTargets(for: id) {
            mutateUserState(id: target) {
                $0.assignColorLabel(
                    colorLabel,
                    metadataValue: metadataValue
                )
            }
        }
    }

    public func toggleColorLabelFilter(_ colorLabel: PhotoColorLabel) {
        if filter.colorLabels.contains(colorLabel) {
            filter.colorLabels.remove(colorLabel)
        } else {
            filter.colorLabels.insert(colorLabel)
        }
    }
    public func toggleFlag(for id: PhotoAsset.ID) {
        let targets = mutationTargets(for: id)
        let shouldFlag = targets.contains { target in
            assets.first(where: { $0.id == target })?.userState.flagged == false
        }
        for target in targets {
            mutateUserState(id: target) {
                $0.flagged = shouldFlag
                if shouldFlag {
                    $0.rejected = false
                }
            }
        }
    }
    public func setPickStatus(_ status: PhotoPickStatus, for id: PhotoAsset.ID) {
        for target in mutationTargets(for: id) {
            mutateUserState(id: target) { $0.pickStatus = status }
        }
    }

    public func addKeywords(
        _ keywords: [String],
        for id: PhotoAsset.ID
    ) {
        let additions = PhotoUserState.normalizedKeywords(keywords)
        guard !additions.isEmpty else { return }
        for target in mutationTargets(for: id) {
            mutateUserState(id: target) { state in
                state.keywords = PhotoUserState.normalizedKeywords(
                    state.keywords + additions
                )
            }
        }
    }

    public func removeKeyword(
        _ keyword: String,
        for id: PhotoAsset.ID
    ) {
        for target in mutationTargets(for: id) {
            mutateUserState(id: target) { state in
                state.keywords.removeAll {
                    $0.compare(
                        keyword,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
                }
            }
        }
    }

    public func setKeywords(
        _ keywords: [String],
        for id: PhotoAsset.ID
    ) {
        let normalized = PhotoUserState.normalizedKeywords(keywords)
        for target in mutationTargets(for: id) {
            mutateUserState(id: target) { $0.keywords = normalized }
        }
    }

    public func previewCatalogKeywordChange(
        _ change: CatalogKeywordChange
    ) async throws -> CatalogKeywordChangePreview {
        let catalogStore = catalogStore
        return try await Task.detached(priority: .userInitiated) {
            try catalogStore.previewKeywordChange(change)
        }.value
    }

    @discardableResult
    public func applyCatalogKeywordChange(
        _ change: CatalogKeywordChange
    ) async throws -> CatalogKeywordChangeResult {
        guard !isManagingKeywords else {
            throw CatalogStoreError.queryFailed(
                "Another keyword change is already in progress."
            )
        }
        flushPendingPersistence()
        isManagingKeywords = true
        defer { isManagingKeywords = false }

        let catalogStore = catalogStore
        let result = try await Task.detached(priority: .userInitiated) {
            try catalogStore.applyKeywordChange(change)
        }.value

        userStateStore.set(statesByID: result.updatedStates)
        for (id, state) in result.updatedStates {
            persistenceTasks[id]?.cancel()
            persistenceTasks[id] = nil
            pendingStates[id] = nil
            if let index = assets.firstIndex(where: { $0.id == id }) {
                assets[index].userState = state
            }
        }

        if let catalogCollection {
            assets.removeAll { !catalogCollection.contains($0) }
        }

        let activeCollectionID = activeSavedCollection?.id
        savedSmartCollections = result.savedSmartCollections
        if let activeCollectionID,
           let updated = savedSmartCollections.first(where: {
               $0.id == activeCollectionID
           }) {
            activeSavedCollection = updated
            filter = updated.filter
        } else if let keyword = filter.keyword,
                  PhotoUserState.keywordPath(
                      keyword,
                      isEqualToOrDescendantOf:
                          result.preview.sourcePath
                  ) {
            var updatedFilter = filter
            updatedFilter.keyword =
                PhotoUserState.replacingKeywordBranch(
                    in: keyword,
                    sourcePath: result.preview.sourcePath,
                    destinationPath: result.preview.destinationPath
                )
            filter = updatedFilter
        } else {
            reconcileSelectionWithFilter()
        }

        refreshCatalogSummary()
        catalogError = catalogStore.startupWarning
        let photoCount = result.preview.affectedPhotoCount
        let collectionCount =
            result.preview.affectedSmartCollectionCount
        var details = [
            "\(photoCount) photo\(photoCount == 1 ? "" : "s") updated."
        ]
        if collectionCount > 0 {
            details.append(
                "\(collectionCount) smart collection"
                    + "\(collectionCount == 1 ? "" : "s") followed the change."
            )
        }
        details.append(
            "Image files and XMP sidecars were not modified."
        )
        sidecarNotice = SidecarNotice(
            title: "Keyword hierarchy \(change.actionName)",
            message: details.joined(separator: "\n")
        )
        return result
    }

    public func keywordDefinition(
        for path: String
    ) throws -> CatalogKeywordDefinition {
        do {
            return try catalogStore.keywordDefinition(for: path)
        } catch {
            catalogError = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    public func saveKeywordDefinition(
        _ definition: CatalogKeywordDefinition
    ) -> Bool {
        do {
            try catalogStore.saveKeywordDefinition(definition)
            catalogError = catalogStore.startupWarning
            sidecarNotice = SidecarNotice(
                title: "Keyword export settings saved",
                message:
                    "\(PhotoUserState.displayKeywordPath(definition.path)) will use the new synonym and export rules. Image files and XMP sidecars were not modified."
            )
            return true
        } catch {
            catalogError = error.localizedDescription
            return false
        }
    }

    public func exportKeywords(
        for asset: PhotoAsset
    ) -> [String] {
        do {
            return try catalogStore.exportKeywords(
                for: asset.userState.keywords
            )
        } catch {
            catalogError = error.localizedDescription
            return PhotoUserState.flatKeywords(
                from: asset.userState.keywords
            )
        }
    }

    public func readMetadataFromXMPSidecars() {
        let targets = sidecarTargets()
        guard !targets.isEmpty else { return }

        var imported = 0
        var failures: [String] = []
        var warnings: [String] = []
        for id in targets {
            guard let index = assets.firstIndex(where: { $0.id == id }) else {
                continue
            }
            let asset = assets[index]
            do {
                let result = try XMPSidecarService.read(
                    for: asset.url,
                    merging: asset.userState,
                    colorLabelSet: activeColorLabelSet
                )
                guard result.importedFieldCount > 0 else {
                    failures.append(
                        "\(asset.filename): no compatible metadata"
                    )
                    continue
                }
                let previous = asset.userState.adjustments
                if previous != result.state.adjustments {
                    recordAdjustmentHistory(
                        previous: previous,
                        for: id,
                        coalescing: false
                    )
                }
                persistenceTasks[id]?.cancel()
                persistenceTasks[id] = nil
                pendingStates[id] = nil
                assets[index].userState = result.state
                assets[index].xmpSidecarURL =
                    XMPSidecarService.existingSidecarURL(for: asset.url)
                assets[index].xmpImportedOnScan = true
                userStateStore.set(id: id, state: result.state)
                try? catalogStore.updateUserState(
                    id: id,
                    state: result.state
                )
                reconcileCatalogMembership(for: id)
                imported += 1
                warnings.append(contentsOf: result.warnings.map {
                    "\(asset.filename): \($0)"
                })
            } catch {
                failures.append(
                    "\(asset.filename): \(error.localizedDescription)"
                )
            }
        }
        historyRevision &+= 1
        sidecarNotice = SidecarNotice(
            title: imported > 0 ? "XMP metadata read" : "XMP import failed",
            message: sidecarMessage(
                successCount: imported,
                action: "read",
                failures: failures,
                warnings: warnings
            )
        )
    }

    public func saveMetadataToXMPSidecars() {
        let targets = sidecarTargets()
        guard !targets.isEmpty else { return }

        flushPendingPersistence()
        var saved = 0
        var failures: [String] = []
        var warnings: [String] = []
        for id in targets {
            guard let index = assets.firstIndex(where: { $0.id == id }) else {
                continue
            }
            let asset = assets[index]
            do {
                let result = try XMPSidecarService.write(
                    state: asset.userState,
                    for: asset.url,
                    colorLabelSet: activeColorLabelSet
                )
                assets[index].xmpSidecarURL = result.url
                if result.stateWritten != asset.userState {
                    assets[index].userState = result.stateWritten
                    userStateStore.set(
                        id: id,
                        state: result.stateWritten
                    )
                    try? catalogStore.updateUserState(
                        id: id,
                        state: result.stateWritten
                    )
                    reconcileCatalogMembership(for: id)
                }
                saved += 1
                warnings.append(contentsOf: result.warnings.map {
                    "\(asset.filename): \($0)"
                })
            } catch {
                failures.append(
                    "\(asset.filename): \(error.localizedDescription)"
                )
            }
        }
        sidecarNotice = SidecarNotice(
            title: saved > 0 ? "XMP metadata saved" : "XMP save failed",
            message: sidecarMessage(
                successCount: saved,
                action: "saved",
                failures: failures,
                warnings: warnings
            )
        )
        refreshCatalogSummary()
    }
    public func toggleFavorite(for id: PhotoAsset.ID) {
        let targets = mutationTargets(for: id)
        let shouldFavorite = targets.contains { target in
            assets.first(where: { $0.id == target })?.userState.favorite == false
        }
        for target in targets {
            mutateUserState(id: target) { $0.favorite = shouldFavorite }
        }
    }
    public func setNote(_ note: String, for id: PhotoAsset.ID) {
        mutateUserState(id: id, persistImmediately: false) { $0.note = note }
    }
    public func setAdjustments(
        _ adjustments: PhotoAdjustments,
        for id: PhotoAsset.ID,
        coalescingHistory: Bool = true
    ) {
        guard let index = assets.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        let previous = assets[index].userState.adjustments
        let normalized = adjustments.normalized
        guard previous != normalized else { return }
        let automaticTargets =
            isAutoSyncEnabled
                && canSynchronizeSelectedAdjustments
                && selectionID == id
            ? orderedSelectedIDs.filter { $0 != id }
            : []

        setAdjustmentsDirect(
            normalized,
            for: id,
            coalescingHistory: coalescingHistory
        )

        guard !automaticTargets.isEmpty else {
            return
        }
        for targetID in automaticTargets {
            guard let target = assets.first(
                where: { $0.id == targetID }
            )?.userState.adjustments else {
                continue
            }
            let synchronized =
                PhotoAdjustmentSyncPlanner
                    .applyingAutomaticChanges(
                        from: previous,
                        to: normalized,
                        onto: target
                    )
            setAdjustmentsDirect(
                synchronized,
                for: targetID,
                coalescingHistory: coalescingHistory
            )
        }
    }

    /// Restores the snapshot captured when an interactive canvas tool began.
    /// The temporary drag/paint history entry is removed so Cancel behaves as
    /// a true cancellation rather than as another edit.
    public func cancelInteractiveAdjustments(
        restoring adjustments: PhotoAdjustments,
        for id: PhotoAsset.ID
    ) {
        endHistoryGroup(for: id)
        applyAdjustmentsWithoutHistory(
            adjustments,
            to: id
        )
        if adjustmentUndo[id]?.last == adjustments {
            adjustmentUndo[id]?.removeLast()
            if adjustmentUndo[id]?.isEmpty == true {
                adjustmentUndo[id] = nil
            }
        }
        adjustmentRedo[id] = []
        historyRevision &+= 1
    }

    private func setAdjustmentsDirect(
        _ adjustments: PhotoAdjustments,
        for id: PhotoAsset.ID,
        coalescingHistory: Bool
    ) {
        guard let index = assets.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        let previous = assets[index].userState.adjustments
        let normalized = adjustments.normalized
        guard previous != normalized else { return }

        recordAdjustmentHistory(
            previous: previous,
            for: id,
            coalescing: coalescingHistory
        )
        mutateUserState(id: id, persistImmediately: false) {
            $0.adjustments = normalized
        }
    }

    public func resetAdjustments(for id: PhotoAsset.ID) {
        if isAutoSyncEnabled,
           canSynchronizeSelectedAdjustments,
           selectionID == id {
            for targetID in orderedSelectedIDs {
                setAdjustmentsDirect(
                    .neutral,
                    for: targetID,
                    coalescingHistory: false
                )
            }
        } else {
            setAdjustments(
                .neutral,
                for: id,
                coalescingHistory: false
            )
        }
    }

    @discardableResult
    public func rotateLeft(for id: PhotoAsset.ID) -> PhotoAdjustments? {
        mutateOrientation(for: id) {
            $0.rotationDegrees = ($0.rotationDegrees + 270) % 360
        }
    }

    @discardableResult
    public func rotateRight(for id: PhotoAsset.ID) -> PhotoAdjustments? {
        mutateOrientation(for: id) {
            $0.rotationDegrees = ($0.rotationDegrees + 90) % 360
        }
    }

    @discardableResult
    public func flipHorizontal(for id: PhotoAsset.ID) -> PhotoAdjustments? {
        mutateOrientation(for: id) {
            $0.flipHorizontal.toggle()
        }
    }

    @discardableResult
    public func flipVertical(for id: PhotoAsset.ID) -> PhotoAdjustments? {
        mutateOrientation(for: id) {
            $0.flipVertical.toggle()
        }
    }

    public func copyAdjustments(from id: PhotoAsset.ID) {
        guard let asset = assets.first(where: { $0.id == id }) else { return }
        copiedAdjustments = asset.userState.adjustments
    }

    public var canSynchronizeSelectedAdjustments: Bool {
        workspaceMode == .library
            && compareState == nil
            && surveyState == nil
            && referenceState == nil
            && selectionID != nil
            && selectedIDs.count > 1
            && selectionID.map(selectedIDs.contains) == true
    }

    public var adjustmentSyncTargetCount: Int {
        guard canSynchronizeSelectedAdjustments else {
            return 0
        }
        return max(0, selectedIDs.count - 1)
    }

    public func setAutoSyncEnabled(_ enabled: Bool) {
        isAutoSyncEnabled =
            enabled && canSynchronizeSelectedAdjustments
    }

    public func presentSyncSettings() {
        guard canSynchronizeSelectedAdjustments else {
            return
        }
        isSyncSettingsPresented = true
    }

    public func selectAllSyncAdjustmentGroups() {
        selectedSyncAdjustmentGroups =
            PhotoAdjustmentGroup.all
    }

    public func selectModifiedSyncAdjustmentGroups() {
        guard let source = selectedAsset?
            .userState.adjustments else {
            selectedSyncAdjustmentGroups = []
            return
        }
        selectedSyncAdjustmentGroups =
            PhotoAdjustmentSyncPlanner.modifiedGroups(
                in: source
            )
    }

    @discardableResult
    public func synchronizeSelectedAdjustments(
        groups: Set<PhotoAdjustmentGroup>? = nil
    ) -> Int {
        guard canSynchronizeSelectedAdjustments,
              let sourceID = selectionID,
              let source = assets.first(
                where: { $0.id == sourceID }
              )?.userState.adjustments else {
            return 0
        }
        let chosenGroups =
            groups ?? selectedSyncAdjustmentGroups
        guard !chosenGroups.isEmpty else { return 0 }

        var synchronizedCount = 0
        for targetID in orderedSelectedIDs
            where targetID != sourceID {
            guard let target = assets.first(
                where: { $0.id == targetID }
            )?.userState.adjustments else {
                continue
            }
            let synchronized =
                PhotoAdjustmentSyncPlanner.merging(
                    source: source,
                    into: target,
                    groups: chosenGroups
                )
            guard synchronized != target else { continue }
            setAdjustmentsDirect(
                synchronized,
                for: targetID,
                coalescingHistory: false
            )
            synchronizedCount += 1
        }
        return synchronizedCount
    }

    private var orderedSelectedIDs:
        [PhotoAsset.ID] {
        assets.compactMap {
            selectedIDs.contains($0.id)
                ? $0.id
                : nil
        }
    }

    public func pasteAdjustments(to id: PhotoAsset.ID) {
        guard let copiedAdjustments else { return }
        for target in mutationTargets(for: id) {
            setAdjustments(copiedAdjustments, for: target, coalescingHistory: false)
        }
    }

    public func applyPreset(_ preset: DevelopmentPreset, to id: PhotoAsset.ID) {
        for target in mutationTargets(for: id) {
            guard let current = assets
                .first(where: { $0.id == target })?
                .userState.adjustments else {
                continue
            }
            var presetAdjustments = preset.adjustments
            // Built-in presets change editing controls; the independently
            // selected rendering foundation remains intact.
            presetAdjustments.developmentProfile = current.developmentProfile
            setAdjustments(
                presetAdjustments,
                for: target,
                coalescingHistory: false
            )
        }
    }

    public func createVersion(
        for id: PhotoAsset.ID,
        name: String? = nil,
        softProofSettings:
            SoftProofSettings? = nil
    ) {
        guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
        let current = assets[index].userState
        let versionName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let versionName, !versionName.isEmpty {
            resolvedName = versionName
        } else {
            resolvedName = "Version \(current.versions.count + 1)"
        }
        mutateUserState(id: id) { state in
            state.versions.append(EditVersion(
                name: resolvedName,
                adjustments: state.adjustments,
                softProofSettings:
                    softProofSettings
            ))
            if state.versions.count > 50 {
                state.versions.removeFirst(state.versions.count - 50)
            }
        }
    }

    public func applyVersion(_ versionID: EditVersion.ID, to id: PhotoAsset.ID) {
        guard let version = assets
            .first(where: { $0.id == id })?
            .userState.versions
            .first(where: { $0.id == versionID }) else { return }
        setAdjustments(version.adjustments, for: id, coalescingHistory: false)
    }

    public func deleteVersion(_ versionID: EditVersion.ID, from id: PhotoAsset.ID) {
        mutateUserState(id: id) { state in
            state.versions.removeAll { $0.id == versionID }
        }
    }

    public func canUndoAdjustments(for id: PhotoAsset.ID?) -> Bool {
        guard let id else { return false }
        return !(adjustmentUndo[id] ?? []).isEmpty
    }

    public func canRedoAdjustments(for id: PhotoAsset.ID?) -> Bool {
        guard let id else { return false }
        return !(adjustmentRedo[id] ?? []).isEmpty
    }

    public func adjustmentHistoryDepth(for id: PhotoAsset.ID?) -> Int {
        guard let id else { return 0 }
        return (adjustmentUndo[id] ?? []).count
    }

    public func adjustmentFutureDepth(for id: PhotoAsset.ID?) -> Int {
        guard let id else { return 0 }
        return (adjustmentRedo[id] ?? []).count
    }

    public func undoAdjustments(for id: PhotoAsset.ID) {
        endHistoryGroup(for: id)
        guard let previous = adjustmentUndo[id]?.popLast(),
              let index = assets.firstIndex(where: { $0.id == id }) else { return }
        let current = assets[index].userState.adjustments
        adjustmentRedo[id, default: []].append(current)
        applyAdjustmentsWithoutHistory(previous, to: id)
        historyRevision &+= 1
    }

    public func redoAdjustments(for id: PhotoAsset.ID) {
        endHistoryGroup(for: id)
        guard let next = adjustmentRedo[id]?.popLast(),
              let index = assets.firstIndex(where: { $0.id == id }) else { return }
        let current = assets[index].userState.adjustments
        adjustmentUndo[id, default: []].append(current)
        applyAdjustmentsWithoutHistory(next, to: id)
        historyRevision &+= 1
    }

    private func mutateUserState(
        id: PhotoAsset.ID,
        persistImmediately: Bool = true,
        _ change: (inout PhotoUserState) -> Void
    ) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        var state = assets[idx].userState
        change(&state)
        assets[idx].userState = state
        reconcileCatalogMembership(for: id)
        if persistImmediately {
            persistenceTasks[id]?.cancel()
            persistenceTasks[id] = nil
            pendingStates[id] = nil
            userStateStore.set(id: id, state: state)
            try? catalogStore.updateUserState(id: id, state: state)
            refreshCatalogSummary()
        } else {
            schedulePersistence(id: id, state: state)
        }
    }

    private func mutationTargets(for id: PhotoAsset.ID) -> [PhotoAsset.ID] {
        if surveyState != nil || referenceState != nil {
            return [id]
        }
        if selectedIDs.count > 1, selectedIDs.contains(id) {
            return assets.compactMap { selectedIDs.contains($0.id) ? $0.id : nil }
        }
        return [id]
    }

    private func currentSelectionInAssetOrder()
        -> [PhotoAsset.ID] {
        let selected = filtered.compactMap {
            selectedIDs.contains($0.id) ? $0.id : nil
        }
        if !selected.isEmpty {
            return selected
        }
        return selectionID.map { [$0] } ?? []
    }

    private func removeVisibleAssets(
        withIDs removed: Set<PhotoAsset.ID>
    ) {
        assets.removeAll { removed.contains($0.id) }
        selectedIDs.subtract(removed)
        selectionID = Self.selectionAfterScan(
            current:
                selectionID.flatMap {
                    removed.contains($0) ? nil : $0
                },
            assets: assets
        )
        if selectedIDs.isEmpty, let selectionID {
            selectedIDs = [selectionID]
        }
        selectionAnchorID = selectionID
    }

    private func sidecarTargets() -> [PhotoAsset.ID] {
        if !selectedIDs.isEmpty {
            return assets.compactMap {
                selectedIDs.contains($0.id) ? $0.id : nil
            }
        }
        return selectionID.map { [$0] } ?? []
    }

    private func sidecarMessage(
        successCount: Int,
        action: String,
        failures: [String],
        warnings: [String]
    ) -> String {
        var parts: [String] = []
        if successCount > 0 {
            parts.append(
                "\(successCount) photo\(successCount == 1 ? "" : "s") \(action)."
            )
        }
        if !failures.isEmpty {
            parts.append(failures.prefix(4).joined(separator: "\n"))
            if failures.count > 4 {
                parts.append("…and \(failures.count - 4) more.")
            }
        }
        if !warnings.isEmpty {
            parts.append(warnings.prefix(2).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private func mutateOrientation(
        for id: PhotoAsset.ID,
        _ change: (inout PhotoAdjustments) -> Void
    ) -> PhotoAdjustments? {
        for target in mutationTargets(for: id) {
            guard let asset = assets.first(where: { $0.id == target }) else { continue }
            var adjustments = asset.userState.adjustments
            change(&adjustments)
            setAdjustments(adjustments, for: target, coalescingHistory: false)
        }
        return assets.first(where: { $0.id == id })?.userState.adjustments
    }

    private func schedulePersistence(id: PhotoAsset.ID, state: PhotoUserState) {
        persistenceTasks[id]?.cancel()
        pendingStates[id] = state
        persistenceTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.userStateStore.set(id: id, state: state)
            try? self.catalogStore.updateUserState(id: id, state: state)
            self.persistenceTasks[id] = nil
            self.pendingStates[id] = nil
            self.refreshCatalogSummary()
        }
    }

    public func flushPendingPersistence() {
        for (id, task) in persistenceTasks {
            task.cancel()
            if let state = pendingStates[id] {
                userStateStore.set(id: id, state: state)
                try? catalogStore.updateUserState(id: id, state: state)
            }
        }
        persistenceTasks.removeAll()
        pendingStates.removeAll()
        refreshCatalogSummary()
    }

    private func recordAdjustmentHistory(
        previous: PhotoAdjustments,
        for id: PhotoAsset.ID,
        coalescing: Bool
    ) {
        if !coalescing {
            endHistoryGroup(for: id)
        }

        if !activeHistoryGroups.contains(id) {
            var stack = adjustmentUndo[id, default: []]
            stack.append(previous)
            if stack.count > 100 {
                stack.removeFirst(stack.count - 100)
            }
            adjustmentUndo[id] = stack
            adjustmentRedo[id] = []
            activeHistoryGroups.insert(id)
            historyRevision &+= 1
        }

        historyGroupTasks[id]?.cancel()
        if coalescing {
            historyGroupTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self else { return }
                self.endHistoryGroup(for: id)
            }
        } else {
            endHistoryGroup(for: id)
        }
    }

    private func endHistoryGroup(for id: PhotoAsset.ID) {
        historyGroupTasks[id]?.cancel()
        historyGroupTasks[id] = nil
        activeHistoryGroups.remove(id)
    }

    private func applyAdjustmentsWithoutHistory(
        _ adjustments: PhotoAdjustments,
        to id: PhotoAsset.ID
    ) {
        mutateUserState(id: id, persistImmediately: false) {
            $0.adjustments = adjustments.normalized
        }
    }

    public func updateMetadata(_ metadata: PhotoMetadata, for id: PhotoAsset.ID) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[idx].metadata = metadata
        try? catalogStore.updateMetadata(id: id, metadata: metadata)
        refreshCatalogSummary()
    }

    public var locationMutationTargetCount: Int {
        if !selectedIDs.isEmpty {
            return selectedIDs.count
        }
        return selectionID == nil ? 0 : 1
    }

    public func setLocationForSelection(
        _ location: PhotoLocation
    ) {
        mutateLocationsForSelection { state in
            state.setLocation(location)
        }
    }

    public func removeLocationFromSelection() {
        mutateLocationsForSelection { state in
            state.removeLocation()
        }
    }

    public func useEmbeddedLocationForSelection() {
        mutateLocationsForSelection { state in
            state.useEmbeddedLocation()
        }
    }

    private func mutateLocationsForSelection(
        _ change: (inout PhotoUserState) -> Void
    ) {
        let targets = selectedIDs.isEmpty
            ? Set(selectionID.map { [$0] } ?? [])
            : selectedIDs
        guard !targets.isEmpty else { return }

        var updates: [PhotoAsset.ID: PhotoUserState] = [:]
        for index in assets.indices
        where targets.contains(assets[index].id) {
            var state = assets[index].userState
            change(&state)
            assets[index].userState = state
            updates[assets[index].id] = state
        }
        guard !updates.isEmpty else { return }

        for id in updates.keys {
            persistenceTasks[id]?.cancel()
            persistenceTasks[id] = nil
            pendingStates[id] = nil
        }
        userStateStore.set(statesByID: updates)
        try? catalogStore.updateUserStates(updates)
        for id in updates.keys {
            reconcileCatalogMembership(for: id)
        }
        refreshCatalogSummary()
    }

    public func showMap() {
        workspaceMode = .map
        if assets.isEmpty, !isScanning {
            showCatalog(.allPhotos)
        }
        refreshLocationMetadataIfNeeded()
    }

    public func showPeople() {
        workspaceMode = .people
    }

    public func showCatalogPhoto(id: PhotoAsset.ID) {
        workspaceMode = .library
        activeSavedCollection = nil
        activePhotoCollection = nil
        importDisplayTitle = nil
        catalogCollection = .allPhotos
        startCatalogLoad(
            source: .builtIn(.allPhotos),
            filterToApply: FilterState(),
            preferredSelectionID: id
        )
    }

    @discardableResult
    public func presentNewSavedMapLocation(
        center: PhotoLocation? = nil
    ) -> Bool {
        guard let center =
                center ?? selectedAsset?.effectiveLocation else {
            sidecarNotice = SidecarNotice(
                title: "Choose a map location",
                message:
                    "Center the map or select a photo with a location before creating a saved location."
            )
            return false
        }
        editingSavedMapLocation = SavedMapLocation(
            name: "Saved Location \(savedMapLocations.count + 1)",
            center: center
        )
        return true
    }

    public func presentSavedMapLocationEditor(
        _ location: SavedMapLocation
    ) {
        editingSavedMapLocation = location
    }

    @discardableResult
    public func saveSavedMapLocation(
        _ rawLocation: SavedMapLocation
    ) -> String? {
        let location = SavedMapLocation(
            id: rawLocation.id,
            name: rawLocation.name,
            folder: rawLocation.folder,
            center: rawLocation.center,
            radiusMeters: rawLocation.radiusMeters,
            isPrivate: rawLocation.isPrivate,
            isVisible: rawLocation.isVisible
        )
        if let validationMessage =
                location.validationMessage {
            return validationMessage
        }
        let foldedName = location.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let foldedFolder = location.folder.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if savedMapLocations.contains(where: {
            $0.id != location.id
                && $0.name.folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive,
                    ],
                    locale: Locale(
                        identifier: "en_US_POSIX"
                    )
                ) == foldedName
                && $0.folder.folding(
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive,
                    ],
                    locale: Locale(
                        identifier: "en_US_POSIX"
                    )
                ) == foldedFolder
        }) {
            return "That folder already contains a saved location with this name."
        }
        if let index = savedMapLocations.firstIndex(
            where: { $0.id == location.id }
        ) {
            savedMapLocations[index] = location
        } else {
            savedMapLocations.append(location)
        }
        persistSavedMapLocations()
        editingSavedMapLocation = nil
        return nil
    }

    public func deleteSavedMapLocation(
        _ id: SavedMapLocation.ID
    ) {
        savedMapLocations.removeAll { $0.id == id }
        persistSavedMapLocations()
        if editingSavedMapLocation?.id == id {
            editingSavedMapLocation = nil
        }
    }

    public func setSavedMapLocationVisible(
        _ id: SavedMapLocation.ID,
        visible: Bool
    ) {
        guard let index = savedMapLocations.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        savedMapLocations[index].isVisible = visible
        persistSavedMapLocations()
    }

    public func focusSavedMapLocation(
        _ id: SavedMapLocation.ID
    ) {
        guard savedMapLocations.contains(
            where: { $0.id == id }
        ) else {
            return
        }
        showMap()
        mapFocusRequest = MapFocusRequest(locationID: id)
    }

    public func savedMapLocation(
        id: SavedMapLocation.ID
    ) -> SavedMapLocation? {
        savedMapLocations.first { $0.id == id }
    }

    public func privateSavedLocation(
        containing asset: PhotoAsset
    ) -> SavedMapLocation? {
        guard let location = asset.effectiveLocation else {
            return nil
        }
        return savedMapLocations.first {
            $0.isPrivate && $0.contains(location)
        }
    }

    public func shouldSuppressLocationOnExport(
        for asset: PhotoAsset
    ) -> Bool {
        privateSavedLocation(containing: asset) != nil
    }

    private func persistSavedMapLocations() {
        let library = SavedMapLocationLibrary(
            locations: savedMapLocations
        )
        savedMapLocations = library.locations
        savedMapLocationStore.save(library)
    }

    public var gpxAutoTagPreview: GPXAutoTagPreview? {
        guard let loadedGPXTracklog else { return nil }
        let scopedAssets: [PhotoAsset]
        switch gpxMatchSettings.photoScope {
        case .selected:
            scopedAssets = selectedAssets
        case .visible:
            scopedAssets = filtered
        }
        return GPXAutoTagPreview.make(
            tracklog: loadedGPXTracklog,
            assets: scopedAssets,
            settings: gpxMatchSettings
        )
    }

    public func loadGPXTracklogPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "gpx")
                ?? .xml,
        ]
        panel.title = "Load GPS Tracklog"
        panel.prompt = "Load Tracklog"
        panel.message =
            "Choose a GPX tracklog with timestamped track points."
        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }
        isLoadingGPXTracklog = true
        Task { [weak self] in
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                do {
                    return (
                        try GPXTracklogParser.parse(
                            url: url
                        ) as GPXTracklog?,
                        nil as String?
                    )
                } catch {
                    return (
                        nil as GPXTracklog?,
                        error.localizedDescription
                    )
                }
            }.value
            guard let self else { return }
            self.isLoadingGPXTracklog = false
            if let tracklog = result.0 {
                self.loadedGPXTracklog = tracklog
                self.isGPXTrackVisible = true
                self.isGPXTracklogPresented = true
                self.showMap()
            } else {
                self.sidecarNotice = SidecarNotice(
                    title: "Tracklog could not be loaded",
                    message:
                        result.1 ?? "The GPX file is unavailable."
                )
            }
        }
    }

    public func setLoadedGPXTracklog(
        _ tracklog: GPXTracklog?
    ) {
        loadedGPXTracklog = tracklog
        isGPXTrackVisible = tracklog != nil
    }

    public func clearGPXTracklog() {
        loadedGPXTracklog = nil
        isGPXTrackVisible = false
        isGPXTracklogPresented = false
    }

    @discardableResult
    public func applyGPXAutoTag() -> Int {
        guard let preview = gpxAutoTagPreview,
              !preview.locationsByPhotoID.isEmpty else {
            return 0
        }
        applyLocations(preview.locationsByPhotoID)
        sidecarNotice = SidecarNotice(
            title: "Tracklog locations applied",
            message:
                "\(preview.matchedCount) photo\(preview.matchedCount == 1 ? "" : "s") matched the GPX timeline."
        )
        return preview.matchedCount
    }

    private func applyLocations(
        _ locationsByID:
            [PhotoAsset.ID: PhotoLocation]
    ) {
        guard !locationsByID.isEmpty else { return }
        var updates: [PhotoAsset.ID: PhotoUserState] = [:]
        for index in assets.indices {
            let id = assets[index].id
            guard let location = locationsByID[id] else {
                continue
            }
            var state = assets[index].userState
            state.setLocation(location)
            assets[index].userState = state
            updates[id] = state
        }
        guard !updates.isEmpty else { return }
        for id in updates.keys {
            persistenceTasks[id]?.cancel()
            persistenceTasks[id] = nil
            pendingStates[id] = nil
        }
        userStateStore.set(statesByID: updates)
        try? catalogStore.updateUserStates(updates)
        for id in updates.keys {
            reconcileCatalogMembership(for: id)
        }
        refreshCatalogSummary()
    }

    public func refreshLocationMetadataIfNeeded() {
        guard locationMetadataRefreshTask == nil else { return }
        let candidates = assets.filter {
            !$0.catalogMissing
                && $0.metadata?.readerVersion
                    != MetadataReader.currentReaderVersion
        }
        guard !candidates.isEmpty else {
            locationMetadataRefreshProgress = nil
            return
        }

        locationMetadataRefreshProgress =
            LocationMetadataRefreshProgress(
                completed: 0,
                total: candidates.count
            )
        let catalogStore = catalogStore
        locationMetadataRefreshTask = Task { [weak self] in
            guard let self else { return }
            var completed = 0
            for start in stride(
                from: 0,
                to: candidates.count,
                by: 8
            ) {
                if Task.isCancelled { break }
                let end = min(start + 8, candidates.count)
                let batch = Array(candidates[start..<end])
                let results = await withTaskGroup(
                    of: (PhotoAsset.ID, PhotoMetadata).self,
                    returning:
                        [(PhotoAsset.ID, PhotoMetadata)].self
                ) { group in
                    for asset in batch {
                        let id = asset.id
                        let url = asset.url
                        group.addTask(priority: .utility) {
                            (
                                id,
                                MetadataReader.read(url: url)
                            )
                        }
                    }
                    var values:
                        [(PhotoAsset.ID, PhotoMetadata)] = []
                    for await value in group {
                        values.append(value)
                    }
                    return values
                }
                if Task.isCancelled { break }
                for (id, metadata) in results {
                    if let index = self.assets.firstIndex(
                        where: { $0.id == id }
                    ) {
                        self.assets[index].metadata = metadata
                    }
                    try? catalogStore.updateMetadata(
                        id: id,
                        metadata: metadata
                    )
                }
                completed += results.count
                self.locationMetadataRefreshProgress =
                    LocationMetadataRefreshProgress(
                        completed: completed,
                        total: candidates.count
                    )
                await Task.yield()
            }
            if !Task.isCancelled {
                self.refreshCatalogSummary()
            }
            self.locationMetadataRefreshProgress = nil
            self.locationMetadataRefreshTask = nil
        }
    }

    public func updateLoadState(_ state: ImageLoadState, for id: PhotoAsset.ID) {
        guard let idx = assets.firstIndex(where: { $0.id == id }) else { return }
        if assets[idx].loadState == state { return }
        assets[idx].loadState = state
    }

    public func updateLoadOutcome(
        _ state: ImageLoadState,
        rawDecodeSource:
            RAWImageLoader.DecodeSource?,
        for id: PhotoAsset.ID
    ) {
        guard let idx =
            assets.firstIndex(
                where: { $0.id == id }
            ) else {
            return
        }
        guard assets[idx].loadState != state
                || assets[idx].rawDecodeSource
                    != rawDecodeSource else {
            return
        }
        assets[idx].loadState = state
        assets[idx].rawDecodeSource =
            assets[idx].format.isRaw
                ? rawDecodeSource
                : nil
    }

    private func nearestExistingDirectory(from url: URL) -> URL? {
        var candidate = url.standardizedFileURL
        let fileManager = FileManager.default
        while true {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private func refreshCatalogSummary() {
        do {
            catalogSummary = try catalogStore.summary()
            if catalogStore.startupWarning == nil {
                catalogError = nil
            }
        } catch {
            catalogError = error.localizedDescription
        }
    }

    public func refreshCatalogOverview() {
        refreshCatalogSummary()
    }

    private func refreshPhotoStacks() {
        do {
            photoStacks = try catalogStore.photoStacks()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    private func refreshQuickCollectionMembership() {
        do {
            quickCollectionPhotoIDs =
                try catalogStore.quickCollectionPhotoIDs()
        } catch {
            catalogError = error.localizedDescription
        }
    }

    private func refreshCollectionOrganization() {
        let activePhotoID = activePhotoCollection?.id
        let activeSmartID = activeSavedCollection?.id
        do {
            collectionSets = try catalogStore.collectionSets()
            photoCollections = try catalogStore.photoCollections()
            savedSmartCollections =
                try catalogStore.savedSmartCollections()
            photoCollectionMemberships =
                try catalogStore.photoCollectionMemberships()
            if let activePhotoID {
                activePhotoCollection = photoCollections.first {
                    $0.id == activePhotoID
                }
            }
            if let activeSmartID {
                activeSavedCollection =
                    savedSmartCollections.first {
                        $0.id == activeSmartID
                    }
            }
        } catch {
            catalogError = error.localizedDescription
        }
    }

    private func reconcileCatalogMembership(for id: PhotoAsset.ID) {
        guard let catalogCollection,
              let index = assets.firstIndex(where: { $0.id == id }),
              !catalogCollection.contains(assets[index]) else {
            return
        }
        assets.remove(at: index)
        selectedIDs.remove(id)
        selectionID = Self.selectionAfterScan(
            current: selectionID == id ? nil : selectionID,
            assets: assets
        )
        if selectedIDs.isEmpty, let selectionID {
            selectedIDs = [selectionID]
        }
        selectionAnchorID = selectionID
    }
}
