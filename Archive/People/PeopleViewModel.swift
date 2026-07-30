import Foundation
import SwiftUI

@MainActor
public final class PeopleViewModel: ObservableObject {
    @Published public private(set) var snapshot = PeopleSnapshot()
    @Published public private(set) var assetsByID:
        [PhotoAsset.ID: PhotoAsset] = [:]
    @Published public private(set) var isScanning = false
    @Published public private(set) var scanProgress:
        PeopleScanProgress?
    @Published public private(set) var lastScanResult:
        PeopleScanResult?
    @Published public private(set) var errorMessage: String?
    @Published public private(set)
        var automaticAnalysisEnabled: Bool
    @Published public private(set) var scanOrigin:
        PeopleScanOrigin?
    @Published public private(set)
        var backgroundStatusMessage: String?
    @Published public var selectedGroupID: String?
    @Published public var selectedFaceID: String?
    @Published public var searchText = ""
    @Published public var groupingSensitivity:
        PeopleGroupingSensitivity = .balanced {
        didSet {
            rebuildSnapshot()
        }
    }

    private let catalogStore: CatalogStore
    private let analyzer: PeopleAnalyzer
    private let preferencesStore:
        PeopleAnalysisPreferencesStore
    private var people: [CatalogPerson] = []
    private var faces: [CatalogFace] = []
    private var scanTask: Task<Void, Never>?
    private var scanGeneration: UUID?
    private var hasStarted = false
    private var refreshAfterScan = false
    private var automaticRescanRequested = false

    public init(
        catalogStore: CatalogStore = .shared,
        analyzer: PeopleAnalyzer? = nil,
        preferencesStore:
            PeopleAnalysisPreferencesStore = .shared
    ) {
        self.catalogStore = catalogStore
        self.analyzer = analyzer
            ?? (
                catalogStore === CatalogStore.shared
                    ? PeopleAnalyzer.shared
                    : PeopleAnalyzer(catalogStore: catalogStore)
            )
        self.preferencesStore = preferencesStore
        automaticAnalysisEnabled =
            preferencesStore.load()
                .automaticAnalysisEnabled
    }

    deinit {
        scanTask?.cancel()
    }

    public var allGroups: [PeopleGroup] {
        snapshot.namedGroups
            + snapshot.suggestedGroups
            + snapshot.singleFaces.map { face in
                PeopleGroup(
                    id: "single:\(face.id)",
                    name: "Unconfirmed Face",
                    kind: .suggested,
                    faces: [face]
                )
            }
    }

    public var visibleNamedGroups: [PeopleGroup] {
        filtered(snapshot.namedGroups)
    }

    public var visibleSuggestedGroups: [PeopleGroup] {
        filtered(snapshot.suggestedGroups)
    }

    public var visibleSingleFaces: [CatalogFace] {
        let query = normalizedSearch
        guard !query.isEmpty else {
            return snapshot.singleFaces
        }
        return snapshot.singleFaces.filter {
            filename(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    public var selectedGroup: PeopleGroup? {
        guard let selectedGroupID else { return nil }
        return allGroups.first { $0.id == selectedGroupID }
    }

    public var selectedFace: CatalogFace? {
        if let selectedFaceID,
           let face = faces.first(where: { $0.id == selectedFaceID }) {
            return face
        }
        return selectedGroup?.representativeFace
    }

    public var selectedPerson: CatalogPerson? {
        guard let personID = selectedGroup?.personID else {
            return nil
        }
        return people.first { $0.id == personID }
    }

    public var mergeDestinations: [CatalogPerson] {
        let sourceID = selectedPerson?.id
        return people.filter { $0.id != sourceID }
    }

    public var namedPersonCount: Int {
        snapshot.namedGroups.count
    }

    public var activeFaceCount: Int {
        snapshot.namedGroups.reduce(0) { $0 + $1.faces.count }
            + snapshot.suggestedGroups.reduce(0) {
                $0 + $1.faces.count
            }
            + snapshot.singleFaces.count
    }

    public var unconfirmedFaceCount: Int {
        snapshot.suggestedGroups.reduce(0) {
            $0 + $1.faces.count
        } + snapshot.singleFaces.count
    }

    public var isAutomaticScan: Bool {
        scanOrigin == .automatic
    }

    public func asset(for face: CatalogFace) -> PhotoAsset? {
        assetsByID[face.photoID]
    }

    public func filename(for face: CatalogFace) -> String {
        assetsByID[face.photoID]?.filename ?? "Unavailable photo"
    }

    public func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !isScanning else { return }
        startScan(forceReanalysis: false)
    }

    public func startAutomaticAnalysisIfNeeded() {
        guard automaticAnalysisEnabled,
              !isScanning else {
            return
        }
        beginScan(
            forceReanalysis: false,
            origin: .automatic
        )
    }

    public func catalogDidChange() {
        guard automaticAnalysisEnabled else { return }
        if isScanning {
            automaticRescanRequested = true
        } else {
            startAutomaticAnalysisIfNeeded()
        }
    }

    public func applicationDidBecomeActive() {
        startAutomaticAnalysisIfNeeded()
    }

    public func applicationDidBecomeInactive() {
        if isAutomaticScan {
            cancelScan()
        }
    }

    public func setAutomaticAnalysisEnabled(
        _ enabled: Bool
    ) {
        guard enabled != automaticAnalysisEnabled else {
            return
        }
        automaticAnalysisEnabled = enabled
        preferencesStore.save(
            PeopleAnalysisPreferences(
                automaticAnalysisEnabled: enabled
            )
        )
        backgroundStatusMessage = nil
        automaticRescanRequested = false
        if enabled {
            startAutomaticAnalysisIfNeeded()
        } else if isAutomaticScan {
            cancelScan()
        }
    }

    public func startScan(forceReanalysis: Bool) {
        beginScan(
            forceReanalysis: forceReanalysis,
            origin: .interactive
        )
    }

    private func beginScan(
        forceReanalysis: Bool,
        origin: PeopleScanOrigin
    ) {
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        isScanning = true
        scanOrigin = origin
        scanProgress = PeopleScanProgress()
        errorMessage = nil
        automaticRescanRequested = false
        if origin == .automatic {
            backgroundStatusMessage = nil
        }

        let analyzer = analyzer
        let catalogStore = catalogStore
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await analyzer.scan(
                    forceReanalysis: forceReanalysis
                ) { [weak self] progress in
                    await self?.setProgress(
                        progress,
                        generation: generation
                    )
                }
                try Task.checkCancellation()
                let loaded = try await Task.detached(
                    priority: .utility
                ) {
                    (
                        people: try catalogStore.catalogPeople(),
                        entries: try catalogStore.entries(
                            for: .allPhotos
                        )
                    )
                }.value
                try Task.checkCancellation()
                finishScan(
                    result: result,
                    people: loaded.people,
                    entries: loaded.entries,
                    origin: origin,
                    generation: generation
                )
            } catch is CancellationError {
                finishCancelledScan(
                    generation: generation
                )
            } catch {
                finishFailedScan(
                    error,
                    origin: origin,
                    generation: generation
                )
            }
        }
    }

    private func finishScan(
        result: PeopleScanResult,
        people loadedPeople: [CatalogPerson],
        entries: [CatalogEntry],
        origin: PeopleScanOrigin,
        generation: UUID
    ) {
        guard scanGeneration == generation else { return }
        people = loadedPeople
        faces = result.faces
        assetsByID = Dictionary(
            uniqueKeysWithValues:
                entries.map {
                    ($0.id, $0.asset)
                }
        )
        lastScanResult = result
        if origin == .automatic,
           !result.unavailablePaths.isEmpty {
            let count = result.unavailablePaths.count
            backgroundStatusMessage =
                "Background analysis could not process "
                + "\(count) photo"
                + "\(count == 1 ? "" : "s"). "
                + "It will retry later."
        }
        rebuildSnapshot()
        if refreshAfterScan {
            refreshAfterScan = false
            do {
                try reloadCatalogState()
            } catch {
                if origin == .automatic {
                    backgroundStatusMessage =
                        error.localizedDescription
                } else {
                    errorMessage =
                        error.localizedDescription
                }
            }
        }
        let shouldRescan =
            automaticAnalysisEnabled
                && automaticRescanRequested
        automaticRescanRequested = false
        isScanning = false
        scanProgress = nil
        scanTask = nil
        scanGeneration = nil
        scanOrigin = nil
        NotificationCenter.default.post(
            name: .rawDeskPeopleAnalysisDidChange,
            object: nil
        )
        if shouldRescan {
            startAutomaticAnalysisIfNeeded()
        }
    }

    private func finishCancelledScan(
        generation: UUID
    ) {
        guard scanGeneration == generation else { return }
        isScanning = false
        scanProgress = nil
        scanTask = nil
        scanGeneration = nil
        scanOrigin = nil
    }

    private func finishFailedScan(
        _ error: Error,
        origin: PeopleScanOrigin,
        generation: UUID
    ) {
        guard scanGeneration == generation else { return }
        if origin == .automatic {
            backgroundStatusMessage =
                "Background analysis will retry later: "
                + error.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
        automaticRescanRequested = false
        isScanning = false
        scanProgress = nil
        scanTask = nil
        scanGeneration = nil
        scanOrigin = nil
    }

    public func cancelScan() {
        scanGeneration = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanProgress = nil
        scanOrigin = nil
        automaticRescanRequested = false
    }

    public func refreshFromCatalog() {
        if isScanning {
            refreshAfterScan = true
            return
        }
        do {
            try reloadCatalogState()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectGroup(_ group: PeopleGroup) {
        selectedGroupID = group.id
        selectedFaceID = group.representativeFace?.id
    }

    public func selectFace(_ face: CatalogFace) {
        selectedFaceID = face.id
        if selectedGroupID == nil
            || selectedGroup?.faces.contains(where: {
                $0.id == face.id
            }) != true {
            if let group = allGroups.first(where: {
                $0.faces.contains(where: { $0.id == face.id })
            }) {
                selectedGroupID = group.id
            }
        }
    }

    public func nameGroup(
        _ group: PeopleGroup,
        name: String
    ) {
        performCatalogChange {
            if let personID = group.personID {
                try catalogStore.renamePerson(
                    id: personID,
                    name: name
                )
            } else {
                _ = try catalogStore.createPerson(
                    name: name,
                    faceIDs: group.faces.map(\.id)
                )
            }
        }
    }

    public func assignGroup(
        _ group: PeopleGroup,
        to personID: UUID
    ) {
        performCatalogChange {
            try catalogStore.assignFaces(
                group.faces.map(\.id),
                to: personID
            )
        }
    }

    public func mergeSelectedPerson(
        into destinationID: UUID
    ) {
        guard let sourceID = selectedPerson?.id else { return }
        performCatalogChange {
            try catalogStore.mergePeople(
                sourceID: sourceID,
                destinationID: destinationID
            )
        }
    }

    public func unassignFace(_ face: CatalogFace) {
        performCatalogChange {
            try catalogStore.unassignFaces([face.id])
        }
    }

    public func ignoreFace(_ face: CatalogFace) {
        performCatalogChange {
            try catalogStore.ignoreFaces([face.id])
        }
    }

    public func ignoreGroup(_ group: PeopleGroup) {
        performCatalogChange {
            try catalogStore.ignoreFaces(group.faces.map(\.id))
        }
    }

    public func restoreIgnoredFaces() {
        let ignored = faces.filter {
            $0.disposition == .ignored
        }
        guard !ignored.isEmpty else { return }
        performCatalogChange {
            try catalogStore.restoreIgnoredFaces(
                ignored.map(\.id)
            )
        }
    }

    public func deleteSelectedPerson() {
        guard let id = selectedPerson?.id else { return }
        performCatalogChange {
            try catalogStore.deletePerson(id: id)
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func filtered(
        _ groups: [PeopleGroup]
    ) -> [PeopleGroup] {
        let query = normalizedSearch
        guard !query.isEmpty else { return groups }
        return groups.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || group.faces.contains {
                    filename(for: $0)
                        .localizedCaseInsensitiveContains(query)
                }
        }
    }

    private func setProgress(
        _ progress: PeopleScanProgress,
        generation: UUID
    ) {
        guard scanGeneration == generation else { return }
        scanProgress = progress
    }

    private func performCatalogChange(
        _ change: () throws -> Void
    ) {
        do {
            try change()
            try reloadCatalogState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadCatalogState() throws {
        people = try catalogStore.catalogPeople()
        let candidates = try catalogStore.peopleAnalysisCandidates(
            engineVersion: PeopleAnalyzer.currentEngineVersion
        )
        faces = candidates.flatMap {
            $0.cachedFaces ?? []
        }
        assetsByID = Dictionary(
            uniqueKeysWithValues:
                try catalogStore.entries(for: .allPhotos)
                    .map { ($0.id, $0.asset) }
        )
        rebuildSnapshot()
    }

    private func rebuildSnapshot() {
        let previousGroupID = selectedGroupID
        let previousFaceID = selectedFaceID
        snapshot = PeopleAnalyzer.makeSnapshot(
            people: people,
            faces: faces,
            similarityThreshold: groupingSensitivity.threshold
        )

        if let previousGroupID,
           allGroups.contains(where: { $0.id == previousGroupID }) {
            selectedGroupID = previousGroupID
        } else {
            selectedGroupID = allGroups.first?.id
        }
        if let previousFaceID,
           faces.contains(where: { $0.id == previousFaceID }),
           selectedGroup?.faces.contains(where: {
               $0.id == previousFaceID
           }) == true {
            selectedFaceID = previousFaceID
        } else {
            selectedFaceID = selectedGroup?.representativeFace?.id
        }
    }
}
