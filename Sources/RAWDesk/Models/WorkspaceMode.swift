import Foundation

public enum PhotoWorkspaceMode:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case library
    case develop

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .library: return "Library"
        case .develop: return "Develop"
        }
    }

    public var systemImage: String {
        switch self {
        case .library: return "rectangle.grid.2x2"
        case .develop: return "slider.horizontal.3"
        }
    }
}

public enum LibraryDisplayMode:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case grid
    case loupe

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .grid: return "Grid"
        case .loupe: return "Loupe"
        }
    }

    public var systemImage: String {
        switch self {
        case .grid: return "square.grid.3x3"
        case .loupe: return "rectangle.inset.filled"
        }
    }
}

public enum DevelopCanvasTool:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case crop
    case remove
    case mask
    case guidedUpright
    case pointColor

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .crop: return "Crop"
        case .remove: return "Heal / Clone"
        case .mask: return "Mask"
        case .guidedUpright: return "Guided Upright"
        case .pointColor: return "Point Color"
        }
    }

    /// One word, for the labelled tool row where five tools share the
    /// inspector's width. `name` remains the full accessible label.
    public var shortName: String {
        switch self {
        case .crop: return "Crop"
        case .remove: return "Heal"
        case .mask: return "Mask"
        case .guidedUpright: return "Upright"
        case .pointColor: return "Color"
        }
    }

    public var systemImage: String {
        switch self {
        case .crop: return "crop"
        case .remove: return "bandage"
        case .mask: return "circle.lefthalf.filled"
        case .guidedUpright: return "ruler"
        case .pointColor: return "eyedropper"
        }
    }
}

public enum WorkspaceDestination:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case library
    case develop
    case people
    case map

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .library: return "Library"
        case .develop: return "Develop"
        case .people: return "People"
        case .map: return "Map"
        }
    }

    public var systemImage: String {
        switch self {
        case .library: return "rectangle.grid.2x2"
        case .develop: return "slider.horizontal.3"
        case .people: return "person.2"
        case .map: return "map"
        }
    }
}

enum RAWDeskUICommand: Sendable {
    case showLibrary
    case showDevelop
    case showPeople
    case showMap
    case toggleSidebar
    case toggleInspector
    case toggleFilmstrip
    case toggleAllPanels
}

public enum WorkspaceMode:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case library
    case people
    case map

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .library: return "Library"
        case .people: return "People"
        case .map: return "Map"
        }
    }

    public var systemImage: String {
        switch self {
        case .library: return "rectangle.grid.2x2"
        case .people: return "person.2"
        case .map: return "map"
        }
    }
}

public enum PhotoCompareRole: String, Equatable, Sendable {
    case select
    case candidate

    public var name: String {
        switch self {
        case .select: return "Select"
        case .candidate: return "Candidate"
        }
    }

    public var systemImage: String {
        switch self {
        case .select: return "checkmark.circle.fill"
        case .candidate: return "circle.lefthalf.filled"
        }
    }
}

public struct PhotoCompareState: Equatable, Sendable {
    public var selectID: PhotoAsset.ID
    public var candidateID: PhotoAsset.ID

    public init(
        selectID: PhotoAsset.ID,
        candidateID: PhotoAsset.ID
    ) {
        self.selectID = selectID
        self.candidateID = candidateID
    }
}

public enum PhotoComparePlanner {
    public static func start(
        primaryID: PhotoAsset.ID?,
        selectedIDs: Set<PhotoAsset.ID>,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoCompareState? {
        guard visibleIDs.count >= 2 else { return nil }
        let selectID =
            primaryID.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? visibleIDs[0]
        let selectedCandidate = visibleIDs.first {
            $0 != selectID && selectedIDs.contains($0)
        }
        guard let candidateID =
            selectedCandidate
            ?? neighbor(
                of: selectID,
                excluding: selectID,
                direction: 1,
                visibleIDs: visibleIDs
            ) else {
            return nil
        }
        return PhotoCompareState(
            selectID: selectID,
            candidateID: candidateID
        )
    }

    public static func movingCandidate(
        in state: PhotoCompareState,
        direction: Int,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoCompareState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        guard let candidateID = neighbor(
            of: reconciled.candidateID,
            excluding: reconciled.selectID,
            direction: direction,
            visibleIDs: visibleIDs
        ) else {
            return reconciled
        }
        return PhotoCompareState(
            selectID: reconciled.selectID,
            candidateID: candidateID
        )
    }

    public static func promotingCandidate(
        in state: PhotoCompareState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoCompareState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        let newSelectID = reconciled.candidateID
        guard let newCandidateID = neighbor(
            of: newSelectID,
            excluding: newSelectID,
            direction: 1,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        return PhotoCompareState(
            selectID: newSelectID,
            candidateID: newCandidateID
        )
    }

    public static func swapping(
        _ state: PhotoCompareState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoCompareState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        return PhotoCompareState(
            selectID: reconciled.candidateID,
            candidateID: reconciled.selectID
        )
    }

    public static func settingCandidate(
        _ id: PhotoAsset.ID,
        in state: PhotoCompareState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoCompareState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        guard id != reconciled.selectID,
              visibleIDs.contains(id) else {
            return reconciled
        }
        return PhotoCompareState(
            selectID: reconciled.selectID,
            candidateID: id
        )
    }

    public static func reconcile(
        _ state: PhotoCompareState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoCompareState? {
        guard visibleIDs.count >= 2 else { return nil }
        let selectID: PhotoAsset.ID
        if visibleIDs.contains(state.selectID) {
            selectID = state.selectID
        } else if visibleIDs.contains(state.candidateID) {
            selectID = state.candidateID
        } else {
            selectID = visibleIDs[0]
        }

        if state.candidateID != selectID,
           visibleIDs.contains(state.candidateID) {
            return PhotoCompareState(
                selectID: selectID,
                candidateID: state.candidateID
            )
        }
        guard let candidateID = neighbor(
            of: selectID,
            excluding: selectID,
            direction: 1,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        return PhotoCompareState(
            selectID: selectID,
            candidateID: candidateID
        )
    }

    private static func neighbor(
        of id: PhotoAsset.ID,
        excluding excludedID: PhotoAsset.ID,
        direction: Int,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoAsset.ID? {
        guard visibleIDs.count >= 2 else { return nil }
        let step = direction < 0 ? -1 : 1
        let start = visibleIDs.firstIndex(of: id) ?? 0
        for distance in 1...visibleIDs.count {
            let rawIndex =
                start + (distance * step)
            let wrappedIndex =
                (rawIndex % visibleIDs.count + visibleIDs.count)
                % visibleIDs.count
            let candidate = visibleIDs[wrappedIndex]
            if candidate != excludedID {
                return candidate
            }
        }
        return nil
    }
}

public enum PhotoSurveyRole: String, Equatable, Sendable {
    case active
    case selected

    public var name: String {
        switch self {
        case .active: return "Active"
        case .selected: return "Survey"
        }
    }

    public var systemImage: String {
        switch self {
        case .active: return "scope"
        case .selected: return "rectangle.3.group"
        }
    }
}

public struct PhotoSurveyState: Equatable, Sendable {
    public var photoIDs: [PhotoAsset.ID]
    public var activeID: PhotoAsset.ID

    public init(
        photoIDs: [PhotoAsset.ID],
        activeID: PhotoAsset.ID
    ) {
        self.photoIDs = photoIDs
        self.activeID = activeID
    }
}

public enum PhotoSurveyPlanner {
    public static func start(
        primaryID: PhotoAsset.ID?,
        selectedIDs: Set<PhotoAsset.ID>,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoSurveyState? {
        let photoIDs = visibleIDs.filter(selectedIDs.contains)
        guard photoIDs.count >= 2 else { return nil }
        let activeID =
            primaryID.flatMap {
                photoIDs.contains($0) ? $0 : nil
            }
            ?? photoIDs[0]
        return PhotoSurveyState(
            photoIDs: photoIDs,
            activeID: activeID
        )
    }

    public static func adding(
        _ id: PhotoAsset.ID,
        to state: PhotoSurveyState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoSurveyState? {
        guard visibleIDs.contains(id) else {
            return reconcile(state, visibleIDs: visibleIDs)
        }
        var included = Set(state.photoIDs)
        included.insert(id)
        let photoIDs = visibleIDs.filter(included.contains)
        guard photoIDs.count >= 2 else { return nil }
        return PhotoSurveyState(
            photoIDs: photoIDs,
            activeID: id
        )
    }

    public static func activating(
        _ id: PhotoAsset.ID,
        in state: PhotoSurveyState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoSurveyState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        guard reconciled.photoIDs.contains(id) else {
            return reconciled
        }
        return PhotoSurveyState(
            photoIDs: reconciled.photoIDs,
            activeID: id
        )
    }

    public static func movingActive(
        in state: PhotoSurveyState,
        direction: Int,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoSurveyState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        let photoIDs = reconciled.photoIDs
        guard let currentIndex = photoIDs.firstIndex(
            of: reconciled.activeID
        ) else {
            return reconciled
        }
        let step = direction < 0 ? -1 : 1
        let rawIndex = currentIndex + step
        let nextIndex =
            (rawIndex % photoIDs.count + photoIDs.count)
            % photoIDs.count
        return PhotoSurveyState(
            photoIDs: photoIDs,
            activeID: photoIDs[nextIndex]
        )
    }

    public static func removing(
        _ id: PhotoAsset.ID,
        from state: PhotoSurveyState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoSurveyState? {
        guard let reconciled = reconcile(
            state,
            visibleIDs: visibleIDs
        ) else {
            return nil
        }
        guard let removedIndex = reconciled.photoIDs
            .firstIndex(of: id) else {
            return reconciled
        }
        var photoIDs = reconciled.photoIDs
        photoIDs.remove(at: removedIndex)
        guard photoIDs.count >= 2 else { return nil }
        let activeID: PhotoAsset.ID
        if reconciled.activeID == id {
            activeID = photoIDs[
                min(removedIndex, photoIDs.count - 1)
            ]
        } else {
            activeID = reconciled.activeID
        }
        return PhotoSurveyState(
            photoIDs: photoIDs,
            activeID: activeID
        )
    }

    public static func reconcile(
        _ state: PhotoSurveyState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoSurveyState? {
        let included = Set(state.photoIDs)
        let photoIDs = visibleIDs.filter(included.contains)
        guard photoIDs.count >= 2 else { return nil }
        let activeID =
            photoIDs.contains(state.activeID)
            ? state.activeID
            : photoIDs[0]
        return PhotoSurveyState(
            photoIDs: photoIDs,
            activeID: activeID
        )
    }
}

public enum PhotoReferenceLayout:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case sideBySide
    case topBottom

    public var name: String {
        switch self {
        case .sideBySide: return "Left / Right"
        case .topBottom: return "Top / Bottom"
        }
    }

    public var systemImage: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .topBottom: return "rectangle.split.1x2"
        }
    }
}

public struct PhotoReferenceState: Equatable, Sendable {
    public var referenceID: PhotoAsset.ID?
    public var activeID: PhotoAsset.ID
    public var layout: PhotoReferenceLayout
    public var isReferenceLocked: Bool

    public init(
        referenceID: PhotoAsset.ID?,
        activeID: PhotoAsset.ID,
        layout: PhotoReferenceLayout = .sideBySide,
        isReferenceLocked: Bool = false
    ) {
        self.referenceID = referenceID
        self.activeID = activeID
        self.layout = layout
        self.isReferenceLocked = isReferenceLocked
    }
}

public enum PhotoReferencePlanner {
    public static func start(
        activeID: PhotoAsset.ID?,
        selectedIDs: Set<PhotoAsset.ID>,
        visibleIDs: [PhotoAsset.ID],
        availableIDs: Set<PhotoAsset.ID>,
        lockedReferenceID: PhotoAsset.ID? = nil,
        layout: PhotoReferenceLayout = .sideBySide
    ) -> PhotoReferenceState? {
        let reusableLockedID = lockedReferenceID.flatMap {
            availableIDs.contains($0) ? $0 : nil
        }
        let resolvedActiveID =
            activeID.flatMap {
                visibleIDs.contains($0) ? $0 : nil
            }
            ?? visibleIDs.first {
                $0 != reusableLockedID
            }
            ?? visibleIDs.first
        guard let activeID = resolvedActiveID else {
            return nil
        }
        let selectedReferenceID = visibleIDs.first {
            $0 != activeID && selectedIDs.contains($0)
        }
        let usableLockedReferenceID = reusableLockedID.flatMap {
            $0 != activeID
                ? $0
                : nil
        }
        let referenceID =
            usableLockedReferenceID
            ?? selectedReferenceID
        return PhotoReferenceState(
            referenceID: referenceID,
            activeID: activeID,
            layout: layout,
            isReferenceLocked:
                referenceID != nil
                && referenceID == usableLockedReferenceID
        )
    }

    public static func settingReference(
        _ id: PhotoAsset.ID,
        in state: PhotoReferenceState,
        availableIDs: Set<PhotoAsset.ID>
    ) -> PhotoReferenceState {
        guard id != state.activeID,
              availableIDs.contains(id) else {
            return state
        }
        var updated = state
        updated.referenceID = id
        return updated
    }

    public static func settingActive(
        _ id: PhotoAsset.ID,
        in state: PhotoReferenceState,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoReferenceState {
        guard visibleIDs.contains(id),
              id != state.activeID else {
            return state
        }
        var updated = state
        if id == state.referenceID {
            updated.referenceID = state.activeID
        }
        updated.activeID = id
        return updated
    }

    public static func movingActive(
        in state: PhotoReferenceState,
        direction: Int,
        visibleIDs: [PhotoAsset.ID]
    ) -> PhotoReferenceState {
        let candidates = visibleIDs.filter {
            $0 != state.referenceID
        }
        guard !candidates.isEmpty else { return state }
        let step = direction < 0 ? -1 : 1
        let currentIndex =
            candidates.firstIndex(of: state.activeID)
            ?? (step > 0 ? -1 : 0)
        let rawIndex = currentIndex + step
        let nextIndex =
            (rawIndex % candidates.count + candidates.count)
            % candidates.count
        var updated = state
        updated.activeID = candidates[nextIndex]
        return updated
    }

    public static func swapping(
        _ state: PhotoReferenceState
    ) -> PhotoReferenceState {
        guard let referenceID = state.referenceID else {
            return state
        }
        var updated = state
        updated.referenceID = state.activeID
        updated.activeID = referenceID
        return updated
    }

    public static func reconcile(
        _ state: PhotoReferenceState,
        visibleIDs: [PhotoAsset.ID],
        availableIDs: Set<PhotoAsset.ID>
    ) -> PhotoReferenceState? {
        guard !visibleIDs.isEmpty else { return nil }
        var updated = state
        if let referenceID = updated.referenceID,
           !availableIDs.contains(referenceID) {
            updated.referenceID = nil
            updated.isReferenceLocked = false
        }
        if !visibleIDs.contains(updated.activeID) {
            updated.activeID =
                visibleIDs.first {
                    $0 != updated.referenceID
                }
                ?? visibleIDs[0]
        }
        if updated.referenceID == updated.activeID {
            updated.referenceID = nil
            updated.isReferenceLocked = false
        }
        return updated
    }
}
