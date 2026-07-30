import Foundation
import AppKit
import SwiftUI

@MainActor
public final class PhotoViewerViewModel: ObservableObject {

    @Published public private(set) var image: NSImage?
    @Published public private(set) var baseImage: NSImage?
    @Published public private(set) var colorSamplingImage:
        NSImage?
    @Published public private(set) var loadState: ImageLoadState = .idle
    @Published public private(set) var rawDecodeSource:
        RAWImageLoader.DecodeSource?
    @Published public var transform = ImageTransformState()
    @Published public private(set) var currentAssetID: PhotoAsset.ID?
    @Published public private(set) var histogram: HistogramData = .empty
    @Published public private(set) var isDeveloping = false
    @Published public private(set)
        var isSoftProofRendering = false
    @Published public private(set)
        var softProofDestinationGamutFraction:
            Double?
    @Published public private(set)
        var softProofMonitorGamutFraction:
            Double?
    @Published public private(set)
        var softProofMonitorName: String?
    @Published public private(set)
        var softProofErrorMessage: String?
    @Published public private(set)
        var softProofSettings =
            SoftProofSettings.disabled
    @Published public private(set) var isShowingOriginal = false
    @Published public private(set) var isCropEditing = false
    @Published public private(set) var isGuidedUprightEditing = false
    @Published public private(set) var isRemovalEditing = false
    @Published public private(set) var selectedSpotRemovalID: SpotRemoval.ID?
    @Published public private(set) var isBrushEditing = false
    @Published public private(set) var selectedLocalMaskID: LocalAdjustmentMask.ID?
    @Published public private(set) var selectedBrushPrimaryOperationID:
        MaskPrimaryOperation.ID?
    @Published public private(set) var isObjectMaskPicking = false
    @Published public private(set) var objectMaskTargetID: LocalAdjustmentMask.ID?
    @Published public private(set) var pendingMaskPrimaryCombination:
        MaskCombinationMode = .add
    @Published public private(set) var isGeneratingObjectMask = false
    @Published public private(set) var objectMaskMessage: String?
    @Published public private(set) var isMaskColorRangePicking = false
    @Published public private(set) var maskColorRangeTargetID: LocalAdjustmentMask.ID?
    @Published public private(set) var maskColorRangeOperationTargetID: MaskRangeOperation.ID?
    @Published public private(set) var pendingMaskRangeCombination: MaskCombinationMode = .intersect
    @Published public private(set) var selectedMaskRangeOperationID: MaskRangeOperation.ID?
    @Published public private(set) var visualizedLocalMaskID: LocalAdjustmentMask.ID?
    @Published public private(set) var isPointColorPicking = false
    @Published public private(set) var pointColorMaskTargetID: LocalAdjustmentMask.ID?
    @Published public private(set) var selectedPointColorID: PointColorAdjustment.ID?
    @Published public private(set) var visualizedPointColorID: PointColorAdjustment.ID?

    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var softProofTask: Task<Void, Never>?
    private var histogramTask: Task<Void, Never>?
    private let loader: ImageLoader
    private let renderQueue: PhotoRenderQueue
    private let previewTarget: CGFloat = 3840
    private var currentAdjustments: PhotoAdjustments = .neutral
    private var developedImage: NSImage?
    private var softProofRevision = 0
    private var screenChangeObserver:
        NSObjectProtocol?

    public init(
        loader: ImageLoader = .shared,
        renderQueue: PhotoRenderQueue = .preview
    ) {
        self.loader = loader
        self.renderQueue = renderQueue
        screenChangeObserver =
            NotificationCenter.default
                .addObserver(
                    forName:
                        NSWindow
                            .didChangeScreenNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?
                            .refreshSoftProofForScreen()
                    }
                }
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default
                .removeObserver(
                    screenChangeObserver
                )
        }
    }

    public func display(_ asset: PhotoAsset?) {
        guard let asset else {
            loadTask?.cancel()
            renderTask?.cancel()
            softProofTask?.cancel()
            histogramTask?.cancel()
            softProofRevision &+= 1
            image = nil
            baseImage = nil
            colorSamplingImage = nil
            developedImage = nil
            loadState = .idle
            rawDecodeSource = nil
            currentAssetID = nil
            transform = ImageTransformState()
            histogram = .empty
            isDeveloping = false
            isSoftProofRendering = false
            softProofDestinationGamutFraction = nil
            softProofMonitorGamutFraction = nil
            softProofMonitorName = nil
            softProofErrorMessage = nil
            isShowingOriginal = false
            isCropEditing = false
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedLocalMaskID = nil
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isGeneratingObjectMask = false
            objectMaskMessage = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            selectedPointColorID = nil
            visualizedPointColorID = nil
            currentAdjustments = .neutral
            return
        }
        if currentAssetID == asset.id, baseImage != nil {
            updateAdjustments(asset.userState.adjustments, for: asset.id)
            return
        }
        loadTask?.cancel()
        renderTask?.cancel()
        softProofTask?.cancel()
        histogramTask?.cancel()
        softProofRevision &+= 1
        currentAssetID = asset.id
        image = nil
        baseImage = nil
        colorSamplingImage = nil
        developedImage = nil
        loadState = .loading
        rawDecodeSource = nil
        transform = ImageTransformState()
        histogram = .empty
        isDeveloping = false
        isSoftProofRendering = false
        softProofDestinationGamutFraction = nil
        softProofMonitorGamutFraction = nil
        softProofMonitorName = nil
        softProofErrorMessage = nil
        isShowingOriginal = false
        isCropEditing = false
        isGuidedUprightEditing = false
        isRemovalEditing = false
        selectedSpotRemovalID = nil
        isBrushEditing = false
        selectedLocalMaskID = nil
        selectedBrushPrimaryOperationID = nil
        isObjectMaskPicking = false
        objectMaskTargetID = nil
        isGeneratingObjectMask = false
        objectMaskMessage = nil
        isMaskColorRangePicking = false
        maskColorRangeTargetID = nil
        maskColorRangeOperationTargetID = nil
        selectedMaskRangeOperationID = nil
        visualizedLocalMaskID = nil
        isPointColorPicking = false
        pointColorMaskTargetID = nil
        selectedPointColorID = nil
        visualizedPointColorID = nil
        currentAdjustments = asset.userState.adjustments.normalized

        let assetCopy = asset
        loadTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.loader.load(asset: assetCopy, kind: .preview(target: self.previewTarget))
            if Task.isCancelled { return }
            await MainActor.run {
                guard self.currentAssetID == assetCopy.id else { return }
                self.loadState = outcome.state
                self.rawDecodeSource =
                    outcome.rawDecodeSource
                self.baseImage = outcome.image
                if let base = outcome.image {
                    self.render(base: base, adjustments: self.currentAdjustments)
                } else {
                    self.image = nil
                }
            }
        }
    }

    public func updateAdjustments(_ adjustments: PhotoAdjustments, for assetID: PhotoAsset.ID) {
        guard currentAssetID == assetID else { return }
        let normalized = adjustments.normalized
        var visualizationChanged = false
        if let visualizedPointColorID,
           !normalized.pointColors.contains(where: { $0.id == visualizedPointColorID }) {
            self.visualizedPointColorID = nil
            visualizationChanged = true
        }
        if let selectedPointColorID,
           !normalized.pointColors.contains(where: { $0.id == selectedPointColorID }) {
            self.selectedPointColorID = normalized.pointColors.first?.id
        }
        if let visualizedLocalMaskID,
           !normalized.localMasks.contains(where: { $0.id == visualizedLocalMaskID }) {
            self.visualizedLocalMaskID = nil
            visualizationChanged = true
        }
        if let selectedMaskRangeOperationID,
           !normalized.localMasks.contains(where: { mask in
               mask.rangeOperations.contains(where: { $0.id == selectedMaskRangeOperationID })
           }) {
            self.selectedMaskRangeOperationID = nil
        }
        if let selectedBrushPrimaryOperationID,
           !normalized.localMasks.contains(where: { mask in
               mask.primaryOperations.contains(
                   where: { $0.id == selectedBrushPrimaryOperationID && $0.kind == .brush }
               )
           }) {
            self.selectedBrushPrimaryOperationID = nil
            isBrushEditing = false
        }
        if let objectMaskTargetID,
           !normalized.localMasks.contains(where: { $0.id == objectMaskTargetID }) {
            isObjectMaskPicking = false
            self.objectMaskTargetID = nil
        }
        if let pointColorMaskTargetID,
           !normalized.localMasks.contains(where: { $0.id == pointColorMaskTargetID }) {
            isPointColorPicking = false
            self.pointColorMaskTargetID = nil
        }
        if let maskColorRangeTargetID,
           !normalized.localMasks.contains(where: { $0.id == maskColorRangeTargetID }) {
            isMaskColorRangePicking = false
            self.maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
        } else if let maskColorRangeOperationTargetID,
                  !normalized.localMasks.contains(where: { mask in
                      mask.rangeOperations.contains(
                          where: { $0.id == maskColorRangeOperationTargetID }
                      )
                  }) {
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            self.maskColorRangeOperationTargetID = nil
        }
        guard normalized != currentAdjustments
                || isShowingOriginal
                || visualizationChanged else {
            return
        }
        let previous = currentAdjustments
        currentAdjustments = normalized
        isShowingOriginal = false
        guard let baseImage else { return }

        if isCropEditing {
            var previousWithoutCrop = previous
            previousWithoutCrop.crop = .fullFrame
            var normalizedWithoutCrop = normalized
            normalizedWithoutCrop.crop = .fullFrame
            if previousWithoutCrop == normalizedWithoutCrop {
                return
            }
        } else if isRemovalEditing || isBrushEditing || isObjectMaskPicking {
            var previousForOverlay = previous
            previousForOverlay.crop = .fullFrame
            previousForOverlay.straighten = 0
            previousForOverlay.optics = .neutral
            previousForOverlay.geometry = .neutral
            var normalizedForOverlay = normalized
            normalizedForOverlay.crop = .fullFrame
            normalizedForOverlay.straighten = 0
            normalizedForOverlay.optics = .neutral
            normalizedForOverlay.geometry = .neutral
            if previousForOverlay == normalizedForOverlay {
                return
            }
        }
        render(base: baseImage, adjustments: normalized)
    }

    public func setShowingOriginal(_ show: Bool) {
        guard let baseImage else { return }
        guard show != isShowingOriginal else { return }
        isShowingOriginal = show
        renderTask?.cancel()
        isDeveloping = false
        if show {
            acceptDevelopedImage(baseImage)
        } else {
            render(base: baseImage, adjustments: currentAdjustments)
        }
    }

    public func toggleOriginal() {
        setShowingOriginal(!isShowingOriginal)
    }

    public func toggleSoftProofing() {
        setSoftProofEnabled(
            !softProofSettings.isEnabled
        )
    }

    public func setSoftProofEnabled(_ enabled: Bool) {
        var settings = softProofSettings
        settings.isEnabled = enabled
        updateSoftProofSettings(settings)
    }

    public func setSoftProofProfile(
        _ profile: SoftProofProfile
    ) {
        var settings = softProofSettings
        settings.profile = profile
        updateSoftProofSettings(settings)
    }

    public func setSoftProofRenderingIntent(
        _ intent: SoftProofRenderingIntent
    ) {
        var settings = softProofSettings
        settings.renderingIntent = intent
        updateSoftProofSettings(settings)
    }

    public func setSoftProofGamutWarning(
        _ enabled: Bool
    ) {
        var settings = softProofSettings
        settings.showDestinationGamutWarning =
            enabled
        updateSoftProofSettings(settings)
    }

    public func setSoftProofMonitorGamutWarning(
        _ enabled: Bool
    ) {
        var settings = softProofSettings
        settings.showMonitorGamutWarning =
            enabled
        updateSoftProofSettings(settings)
    }

    public func setSoftProofPaperAndInk(
        _ enabled: Bool
    ) {
        var settings = softProofSettings
        settings.simulatePaperAndInk = enabled
        updateSoftProofSettings(settings)
    }

    public func restoreSoftProofSettings(
        _ settings: SoftProofSettings
    ) {
        updateSoftProofSettings(settings)
    }

    private func updateSoftProofSettings(
        _ settings: SoftProofSettings
    ) {
        let normalized = settings.normalized
        guard normalized != softProofSettings else {
            return
        }
        softProofSettings = normalized
        guard let baseImage else {
            isSoftProofRendering = false
            softProofDestinationGamutFraction = nil
            softProofMonitorGamutFraction = nil
            softProofMonitorName = nil
            softProofErrorMessage = nil
            return
        }
        if isShowingOriginal {
            acceptDevelopedImage(baseImage)
        } else {
            render(
                base: baseImage,
                adjustments: currentAdjustments
            )
        }
    }

    public func finishInteractiveTools() {
        if isCropEditing {
            setCropEditing(false)
        } else if isGuidedUprightEditing {
            setGuidedUprightEditing(false)
        } else if isRemovalEditing {
            setRemovalEditing(false)
        } else if isBrushEditing {
            setBrushEditing(false)
        } else if isObjectMaskPicking {
            setObjectMaskPicking(false)
        } else if isMaskColorRangePicking {
            setMaskColorRangePicking(false)
        } else if isPointColorPicking {
            setPointColorPicking(false)
        }
        if isShowingOriginal {
            setShowingOriginal(false)
        }
    }

    public func setCropEditing(_ enabled: Bool) {
        guard enabled != isCropEditing else { return }
        isCropEditing = enabled
        if enabled {
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedLocalMaskID = nil
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        }
        guard let baseImage else { return }
        if isShowingOriginal {
            acceptDevelopedImage(baseImage)
        } else {
            render(base: baseImage, adjustments: currentAdjustments)
        }
    }

    public func setGuidedUprightEditing(_ enabled: Bool) {
        guard enabled != isGuidedUprightEditing else { return }
        isGuidedUprightEditing = enabled
        if enabled {
            isCropEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedLocalMaskID = nil
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            isShowingOriginal = false
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        }
        guard let baseImage else { return }
        render(base: baseImage, adjustments: currentAdjustments)
    }

    public func setRemovalEditing(
        _ enabled: Bool,
        selectedSpotID: SpotRemoval.ID? = nil
    ) {
        guard enabled != isRemovalEditing
                || (selectedSpotID != nil && selectedSpotID != selectedSpotRemovalID) else {
            return
        }
        isRemovalEditing = enabled
        if enabled {
            isCropEditing = false
            isGuidedUprightEditing = false
            isBrushEditing = false
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            selectedLocalMaskID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            selectedSpotRemovalID = selectedSpotID
                ?? selectedSpotRemovalID
                ?? currentAdjustments.spotRemovals.first?.id
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        } else {
            selectedSpotRemovalID = nil
        }
        guard let baseImage else { return }
        if isShowingOriginal {
            acceptDevelopedImage(baseImage)
        } else {
            render(base: baseImage, adjustments: currentAdjustments)
        }
    }

    public func selectSpotRemoval(_ id: SpotRemoval.ID?) {
        selectedSpotRemovalID = id
    }

    public func setBrushEditing(
        _ enabled: Bool,
        selectedMaskID: LocalAdjustmentMask.ID? = nil,
        primaryOperationID: MaskPrimaryOperation.ID? = nil
    ) {
        guard enabled != isBrushEditing
                || (selectedMaskID != nil && selectedMaskID != selectedLocalMaskID)
                || primaryOperationID != selectedBrushPrimaryOperationID else {
            return
        }
        isBrushEditing = enabled
        if enabled {
            isCropEditing = false
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            selectedLocalMaskID = selectedMaskID
                ?? selectedLocalMaskID
                ?? currentAdjustments.localMasks.first(where: { $0.kind == .brush })?.id
            selectedBrushPrimaryOperationID = primaryOperationID
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        } else {
            selectedLocalMaskID = nil
            selectedBrushPrimaryOperationID = nil
        }
        guard let baseImage else { return }
        if isShowingOriginal {
            acceptDevelopedImage(baseImage)
        } else {
            render(base: baseImage, adjustments: currentAdjustments)
        }
    }

    public func selectLocalMask(_ id: LocalAdjustmentMask.ID?) {
        selectedLocalMaskID = id
    }

    public func setObjectMaskPicking(
        _ enabled: Bool,
        targetMaskID: LocalAdjustmentMask.ID? = nil,
        combination: MaskCombinationMode = .add
    ) {
        guard enabled != isObjectMaskPicking
                || (
                    enabled
                        && (
                            targetMaskID != objectMaskTargetID
                                || combination != pendingMaskPrimaryCombination
                        )
                ) else {
            return
        }
        isObjectMaskPicking = enabled
        if enabled {
            isCropEditing = false
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedLocalMaskID = nil
            selectedBrushPrimaryOperationID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            objectMaskMessage = nil
            objectMaskTargetID = targetMaskID
            pendingMaskPrimaryCombination = combination
            isShowingOriginal = false
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        } else {
            objectMaskTargetID = nil
        }
        guard let baseImage else { return }
        render(base: baseImage, adjustments: currentAdjustments)
    }

    public func setObjectMaskGeneration(
        _ generating: Bool,
        message: String? = nil
    ) {
        isGeneratingObjectMask = generating
        objectMaskMessage = message
    }

    public func setMaskColorRangePicking(
        _ enabled: Bool,
        selectedMaskID: LocalAdjustmentMask.ID? = nil,
        operationID: MaskRangeOperation.ID? = nil,
        combination: MaskCombinationMode = .intersect
    ) {
        guard enabled != isMaskColorRangePicking
                || (
                    enabled
                        && (
                            (selectedMaskID != nil
                                && selectedMaskID != maskColorRangeTargetID)
                                || operationID != maskColorRangeOperationTargetID
                                || combination != pendingMaskRangeCombination
                        )
                ) else {
            return
        }
        isMaskColorRangePicking = enabled
        if enabled {
            isCropEditing = false
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            visualizedLocalMaskID = nil
            selectedLocalMaskID = selectedMaskID
                ?? selectedLocalMaskID
                ?? currentAdjustments.localMasks.first?.id
            maskColorRangeTargetID = selectedMaskID ?? selectedLocalMaskID
            maskColorRangeOperationTargetID = operationID
            pendingMaskRangeCombination = combination
            isShowingOriginal = false
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        } else {
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
        }
        guard let baseImage else { return }
        render(base: baseImage, adjustments: currentAdjustments)
    }

    public func selectMaskRangeOperation(_ id: MaskRangeOperation.ID?) {
        selectedMaskRangeOperationID = id
    }

    public func setLocalMaskVisualization(_ id: LocalAdjustmentMask.ID?) {
        let validID = id.flatMap { candidate in
            currentAdjustments.localMasks.contains(where: { $0.id == candidate })
                ? candidate
                : nil
        }
        guard validID != visualizedLocalMaskID || isShowingOriginal else { return }
        visualizedLocalMaskID = validID
        if let validID {
            selectedLocalMaskID = validID
            isCropEditing = false
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            isPointColorPicking = false
            pointColorMaskTargetID = nil
            visualizedPointColorID = nil
            isShowingOriginal = false
        }
        guard let baseImage else { return }
        render(base: baseImage, adjustments: currentAdjustments)
    }

    public func setPointColorPicking(
        _ enabled: Bool,
        selectedMaskID: LocalAdjustmentMask.ID? = nil
    ) {
        guard enabled != isPointColorPicking
                || (enabled && selectedMaskID != pointColorMaskTargetID) else {
            return
        }
        isPointColorPicking = enabled
        if enabled {
            isCropEditing = false
            isGuidedUprightEditing = false
            isRemovalEditing = false
            selectedSpotRemovalID = nil
            isBrushEditing = false
            selectedLocalMaskID = nil
            selectedBrushPrimaryOperationID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            selectedMaskRangeOperationID = nil
            visualizedLocalMaskID = nil
            visualizedPointColorID = nil
            pointColorMaskTargetID = selectedMaskID
            isShowingOriginal = false
            transform.rotationDegrees = 0
            transform.flipHorizontal = false
            transform.flipVertical = false
            transform.fit()
        } else {
            pointColorMaskTargetID = nil
        }
        guard let baseImage else { return }
        render(base: baseImage, adjustments: currentAdjustments)
    }

    public func selectPointColor(_ id: PointColorAdjustment.ID?) {
        selectedPointColorID = id
        if visualizedPointColorID != nil {
            setPointColorVisualization(id)
        }
    }

    public func setPointColorVisualization(
        _ id: PointColorAdjustment.ID?
    ) {
        let validID = id.flatMap { candidate in
            currentAdjustments.pointColors.contains(where: { $0.id == candidate })
                ? candidate
                : nil
        }
        guard validID != visualizedPointColorID || isShowingOriginal else { return }
        visualizedPointColorID = validID
        if let validID {
            selectedPointColorID = validID
            isPointColorPicking = false
            isGuidedUprightEditing = false
            pointColorMaskTargetID = nil
            isObjectMaskPicking = false
            objectMaskTargetID = nil
            isMaskColorRangePicking = false
            maskColorRangeTargetID = nil
            maskColorRangeOperationTargetID = nil
            visualizedLocalMaskID = nil
            isShowingOriginal = false
        }
        guard let baseImage else { return }
        render(base: baseImage, adjustments: currentAdjustments)
    }

    private func render(base: NSImage, adjustments: PhotoAdjustments) {
        renderTask?.cancel()
        softProofTask?.cancel()
        softProofRevision &+= 1
        isSoftProofRendering = false

        var renderAdjustments = adjustments
        if isCropEditing {
            renderAdjustments.crop = .fullFrame
        } else if isGuidedUprightEditing {
            // Guides are authored in the pre-geometry image space. Showing
            // that stable full frame prevents endpoint refinements from
            // feeding the already-corrected result back into the solver.
            renderAdjustments.crop = .fullFrame
            renderAdjustments.straighten = 0
            renderAdjustments.geometry = .neutral
        } else if isRemovalEditing || isBrushEditing || isObjectMaskPicking {
            renderAdjustments.crop = .fullFrame
            renderAdjustments.straighten = 0
            renderAdjustments.optics = .neutral
            renderAdjustments.geometry = .neutral
        }

        if renderAdjustments.isNeutral
            && visualizedPointColorID == nil
            && visualizedLocalMaskID == nil {
            isDeveloping = false
            acceptDevelopedImage(base)
            return
        }

        isDeveloping = true
        let assetID = currentAssetID
        let cropEditing = isCropEditing
        let guidedUprightEditing =
            isGuidedUprightEditing
        let removalEditing = isRemovalEditing
        let brushEditing = isBrushEditing
        let objectMaskPicking = isObjectMaskPicking
        let maskColorRangePicking = isMaskColorRangePicking
        let pointColorVisualization = visualizedPointColorID
        let localMaskVisualization = visualizedLocalMaskID
        let proofSettings = softProofSettings
        let monitorProfile =
            currentSoftProofMonitorProfile()
        isSoftProofRendering = proofSettings.isEnabled
        if proofSettings.isEnabled {
            softProofErrorMessage = nil
        }
        renderTask = Task { [weak self] in
            guard let self else { return }
            let proofOutcome:
                SoftProofRenderOutcome
            let developedResult: NSImage?
            if proofSettings.isEnabled {
                proofOutcome =
                    await self.renderQueue
                        .renderSoftProof(
                            image: base,
                            adjustments:
                                renderAdjustments,
                            settings: proofSettings,
                            monitorProfile:
                                monitorProfile,
                            visualizePointColorID:
                                pointColorVisualization,
                            visualizeLocalMaskID:
                                localMaskVisualization
                        )
                if proofOutcome.result == nil {
                    developedResult =
                        await self.renderQueue
                            .render(
                                image: base,
                                adjustments:
                                    renderAdjustments,
                                visualizePointColorID:
                                    pointColorVisualization,
                                visualizeLocalMaskID:
                                    localMaskVisualization
                            )
                } else {
                    developedResult = nil
                }
            } else {
                proofOutcome =
                    SoftProofRenderOutcome()
                developedResult =
                    await self.renderQueue.render(
                        image: base,
                        adjustments: renderAdjustments,
                        visualizePointColorID:
                            pointColorVisualization,
                        visualizeLocalMaskID:
                            localMaskVisualization
                    )
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentAssetID == assetID,
                      self.currentAdjustments == adjustments,
                      self.softProofSettings == proofSettings,
                      self.isCropEditing == cropEditing,
                      self.isGuidedUprightEditing
                        == guidedUprightEditing,
                      self.isRemovalEditing == removalEditing,
                      self.isBrushEditing == brushEditing,
                      self.isObjectMaskPicking == objectMaskPicking,
                      self.isMaskColorRangePicking == maskColorRangePicking,
                      self.visualizedPointColorID == pointColorVisualization,
                      self.visualizedLocalMaskID == localMaskVisualization,
                      !self.isShowingOriginal else { return }
                self.isDeveloping = false
                self.isSoftProofRendering = false
                if let proofResult =
                    proofOutcome.result {
                    self.developedImage = nil
                    self.image =
                        proofResult.displayImage
                    self.colorSamplingImage =
                        proofResult.proofImage
                    self.softProofDestinationGamutFraction =
                        proofResult
                            .destinationGamutFraction
                    self.softProofMonitorGamutFraction =
                        proofResult
                            .monitorGamutFraction
                    self.softProofMonitorName =
                        proofResult.monitorName
                    self.softProofErrorMessage = nil
                    self.updateHistogram(
                        for: proofResult.proofImage
                    )
                } else if proofSettings.isEnabled {
                    let fallback =
                        developedResult ?? base
                    self.developedImage = fallback
                    self.image = fallback
                    self.colorSamplingImage =
                        fallback
                    self
                        .softProofDestinationGamutFraction =
                        nil
                    self.softProofMonitorGamutFraction =
                        nil
                    self.softProofMonitorName =
                        monitorProfile?.name
                    self.softProofErrorMessage =
                        proofOutcome.errorMessage
                        ?? "Soft proofing could not render this profile."
                    self.updateHistogram(
                        for: fallback
                    )
                } else {
                    self.acceptDevelopedImage(
                        developedResult ?? base
                    )
                }
            }
        }
    }

    private func acceptDevelopedImage(
        _ source: NSImage
    ) {
        developedImage = source
        applySoftProof(to: source)
    }

    private func applySoftProof(to source: NSImage) {
        softProofTask?.cancel()
        softProofRevision &+= 1
        let revision = softProofRevision
        let settings = softProofSettings

        guard settings.isEnabled else {
            isSoftProofRendering = false
            softProofDestinationGamutFraction = nil
            softProofMonitorGamutFraction = nil
            softProofMonitorName = nil
            softProofErrorMessage = nil
            image = source
            colorSamplingImage = source
            updateHistogram(for: source)
            return
        }

        let monitorProfile =
            currentSoftProofMonitorProfile()
        isSoftProofRendering = true
        softProofErrorMessage = nil
        softProofTask = Task { [weak self] in
            let outcome = await Task.detached(
                priority: .userInitiated
            ) {
                do {
                    return SoftProofRenderOutcome(
                        result:
                            try SoftProofProcessor
                                .apply(
                                    to: source,
                                    settings: settings,
                                    monitorProfile:
                                        monitorProfile
                                )
                    )
                } catch {
                    return SoftProofRenderOutcome(
                        errorMessage:
                            error.localizedDescription
                    )
                }
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.softProofRevision == revision,
                  self.softProofSettings == settings else {
                return
            }
            self.isSoftProofRendering = false
            if let result = outcome.result {
                self.image = result.displayImage
                self.colorSamplingImage =
                    result.proofImage
                self
                    .softProofDestinationGamutFraction =
                    result.destinationGamutFraction
                self.softProofMonitorGamutFraction =
                    result.monitorGamutFraction
                self.softProofMonitorName =
                    result.monitorName
                self.softProofErrorMessage = nil
                self.updateHistogram(
                    for: result.proofImage
                )
            } else {
                self.image = source
                self.colorSamplingImage = source
                self
                    .softProofDestinationGamutFraction =
                    nil
                self.softProofMonitorGamutFraction =
                    nil
                self.softProofMonitorName =
                    monitorProfile?.name
                self.softProofErrorMessage =
                    outcome.errorMessage
                    ?? "Soft proofing could not render this profile."
                self.updateHistogram(for: source)
            }
        }
    }

    private func currentSoftProofMonitorProfile()
        -> SoftProofMonitorProfile?
    {
        let screen =
            NSApplication.shared
                .keyWindow?.screen
            ?? NSScreen.main
        guard let screen,
              let colorSpace =
                screen.colorSpace?.cgColorSpace else {
            return nil
        }
        return SoftProofMonitorProfile(
            name: screen.localizedName,
            colorSpace: colorSpace
        )
    }

    private func refreshSoftProofForScreen() {
        guard softProofSettings.isEnabled,
              let baseImage else {
            return
        }
        if isShowingOriginal {
            acceptDevelopedImage(baseImage)
        } else {
            render(
                base: baseImage,
                adjustments: currentAdjustments
            )
        }
    }

    private func updateHistogram(for image: NSImage) {
        histogramTask?.cancel()
        let assetID = currentAssetID
        histogramTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                HistogramAnalyzer.analyze(image)
            }.value
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.currentAssetID == assetID else { return }
                self.histogram = result ?? .empty
            }
        }
    }
}
