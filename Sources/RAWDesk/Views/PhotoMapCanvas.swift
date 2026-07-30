import SwiftUI
import MapKit
import AppKit

struct PhotoMapCanvas: NSViewRepresentable {
    var displayStyle: MapDisplayStyle
    var photoGroups: [PhotoMapAnnotationGroup]
    var selectedAssetIDs: Set<PhotoAsset.ID>
    var savedLocations: [SavedMapLocation]
    var trackCoordinates: [CLLocationCoordinate2D]
    var requestedRegion: MKCoordinateRegion?
    var regionRequestID: Int
    var fitPinsRequestID: Int
    var isAssigningLocation: Bool
    var taggedCount: Int
    var totalCount: Int
    var onVisibleRegionChange: (MKCoordinateRegion) -> Void
    var onAssignCoordinate: (CLLocationCoordinate2D) -> Void
    var onSelectPhotoGroup: (PhotoMapAnnotationGroup) -> Void
    var onFocusSavedLocation: (SavedMapLocation.ID) -> Void

    func makeNSView(
        context: Context
    ) -> SnapshotPhotoMapView {
        SnapshotPhotoMapView()
    }

    func updateNSView(
        _ mapView: SnapshotPhotoMapView,
        context: Context
    ) {
        mapView.configure(
            displayStyle: displayStyle,
            photoGroups: photoGroups,
            selectedAssetIDs: selectedAssetIDs,
            savedLocations: savedLocations,
            trackCoordinates: trackCoordinates,
            requestedRegion: requestedRegion,
            regionRequestID: regionRequestID,
            fitPinsRequestID: fitPinsRequestID,
            isAssigningLocation: isAssigningLocation,
            taggedCount: taggedCount,
            totalCount: totalCount,
            onVisibleRegionChange: onVisibleRegionChange,
            onAssignCoordinate: onAssignCoordinate,
            onSelectPhotoGroup: onSelectPhotoGroup,
            onFocusSavedLocation: onFocusSavedLocation
        )
    }
}

final class SnapshotPhotoMapView: NSView {
    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(
            latitude: 20,
            longitude: 0
        ),
        span: MKCoordinateSpan(
            latitudeDelta: 120,
            longitudeDelta: 160
        )
    )

    private var displayStyle: MapDisplayStyle = .standard
    private var photoGroups: [PhotoMapAnnotationGroup] = []
    private var selectedAssetIDs: Set<PhotoAsset.ID> = []
    private var savedLocations: [SavedMapLocation] = []
    private var trackCoordinates: [CLLocationCoordinate2D] = []
    private var isAssigningLocation = false

    private var currentRegion = defaultRegion
    private var snapshot:
        MKMapSnapshotter.Snapshot?
    private var snapshotSize = CGSize.zero
    private var snapshotter: MKMapSnapshotter?
    private var snapshotGeneration = 0
    private var snapshotWorkItem: DispatchWorkItem?
    private var didPerformInitialFit = false
    private var lastRegionRequestID = 0
    private var lastFitPinsRequestID = 0

    private var dragOrigin: NSPoint?
    private var dragRegion: MKCoordinateRegion?
    private var liveImageOffset = CGSize.zero
    private var accumulatedDragDistance: CGFloat = 0

    private var onVisibleRegionChange:
        ((MKCoordinateRegion) -> Void)?
    private var onAssignCoordinate:
        ((CLLocationCoordinate2D) -> Void)?
    private var onSelectPhotoGroup:
        ((PhotoMapAnnotationGroup) -> Void)?
    private var onFocusSavedLocation:
        ((SavedMapLocation.ID) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor =
            RAWDeskTokens.ColorToken.canvasNS.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Photo map")
        setAccessibilityChildren([])
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func configure(
        displayStyle: MapDisplayStyle,
        photoGroups: [PhotoMapAnnotationGroup],
        selectedAssetIDs: Set<PhotoAsset.ID>,
        savedLocations: [SavedMapLocation],
        trackCoordinates: [CLLocationCoordinate2D],
        requestedRegion: MKCoordinateRegion?,
        regionRequestID: Int,
        fitPinsRequestID: Int,
        isAssigningLocation: Bool,
        taggedCount: Int,
        totalCount: Int,
        onVisibleRegionChange:
            @escaping (MKCoordinateRegion) -> Void,
        onAssignCoordinate:
            @escaping (CLLocationCoordinate2D) -> Void,
        onSelectPhotoGroup:
            @escaping (PhotoMapAnnotationGroup) -> Void,
        onFocusSavedLocation:
            @escaping (SavedMapLocation.ID) -> Void
    ) {
        let styleChanged = self.displayStyle != displayStyle
        self.displayStyle = displayStyle
        self.photoGroups = photoGroups
        self.selectedAssetIDs = selectedAssetIDs
        self.savedLocations = savedLocations
        self.trackCoordinates = trackCoordinates
        self.isAssigningLocation = isAssigningLocation
        self.onVisibleRegionChange = onVisibleRegionChange
        self.onAssignCoordinate = onAssignCoordinate
        self.onSelectPhotoGroup = onSelectPhotoGroup
        self.onFocusSavedLocation = onFocusSavedLocation
        setAccessibilityValue(
            "\(taggedCount) tagged, \(totalCount - taggedCount) untagged"
        )
        setAccessibilityChildren([])
        resetCursorRects()

        var regionChanged = false
        if regionRequestID != lastRegionRequestID {
            lastRegionRequestID = regionRequestID
            if let requestedRegion {
                didPerformInitialFit = true
                currentRegion = constrained(requestedRegion)
                regionChanged = true
            }
        }
        if fitPinsRequestID != lastFitPinsRequestID {
            lastFitPinsRequestID = fitPinsRequestID
            didPerformInitialFit = true
            if let fitted = fittedRegion() {
                currentRegion = fitted
                regionChanged = true
            }
        }
        if !didPerformInitialFit,
           !photoGroups.isEmpty {
            didPerformInitialFit = true
            if let fitted = fittedRegion() {
                currentRegion = fitted
                regionChanged = true
            }
        }

        if regionChanged {
            onVisibleRegionChange(currentRegion)
        }
        if styleChanged || regionChanged || snapshot == nil {
            scheduleSnapshot(immediate: snapshot == nil)
        } else {
            needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        guard bounds.width >= 2,
              bounds.height >= 2 else {
            return
        }
        if abs(snapshotSize.width - bounds.width) > 1
            || abs(snapshotSize.height - bounds.height) > 1 {
            scheduleSnapshot()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(
            bounds,
            cursor:
                isAssigningLocation
                ? .crosshair
                : .openHand
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragRegion = currentRegion
        liveImageOffset = .zero
        accumulatedDragDistance = 0
        if !isAssigningLocation {
            NSCursor.closedHand.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isAssigningLocation,
              let origin = dragOrigin,
              let region = dragRegion,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let deltaX = point.x - origin.x
        let deltaY = point.y - origin.y
        liveImageOffset = CGSize(
            width: deltaX,
            height: deltaY
        )
        accumulatedDragDistance = max(
            accumulatedDragDistance,
            hypot(deltaX, deltaY)
        )
        currentRegion = constrained(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude:
                        region.center.latitude
                        + Double(deltaY / bounds.height)
                            * region.span.latitudeDelta,
                    longitude:
                        region.center.longitude
                        - Double(deltaX / bounds.width)
                            * region.span.longitudeDelta
                ),
                span: region.span
            )
        )
        onVisibleRegionChange?(currentRegion)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if !isAssigningLocation {
            NSCursor.pop()
        }
        let point = convert(event.locationInWindow, from: nil)
        let wasClick = accumulatedDragDistance < 4
        dragOrigin = nil
        dragRegion = nil
        if wasClick {
            handleClick(at: point)
        } else {
            scheduleSnapshot(immediate: true)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return }
        let factor = pow(1.012, Double(delta))
        zoom(by: factor)
    }

    override func magnify(with event: NSEvent) {
        let factor = 1 / max(0.15, 1 + Double(event.magnification))
        zoom(by: factor)
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "+", "=":
            zoom(by: 0.72)
        case "-", "_":
            zoom(by: 1.4)
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        RAWDeskTokens.ColorToken.canvasNS.setFill()
        bounds.fill()

        if let snapshot {
            let destination = bounds.offsetBy(
                dx: liveImageOffset.width,
                dy: liveImageOffset.height
            )
            snapshot.image.draw(
                in: destination,
                from: NSRect(
                    origin: .zero,
                    size: snapshot.image.size
                ),
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [
                    .interpolation:
                        NSImageInterpolation.high.rawValue
                ]
            )
            drawSavedAreas(using: snapshot)
            drawTrack(using: snapshot)
            drawPhotoPins(using: snapshot)
            drawSavedLocationPins(using: snapshot)
            drawMapCredit()
        } else {
            drawLoadingState()
        }
    }

    private func handleClick(at point: NSPoint) {
        if isAssigningLocation,
           let coordinate = coordinate(at: point) {
            onAssignCoordinate?(coordinate)
            return
        }

        if let group = photoGroups
            .reversed()
            .first(where: {
                guard let pin = mapPoint(for: $0.coordinate) else {
                    return false
                }
                return hypot(
                    point.x - pin.x,
                    point.y - (pin.y - 16)
                ) <= 21
            }) {
            onSelectPhotoGroup?(group)
            return
        }

        if let location = savedLocations
            .reversed()
            .first(where: {
                guard let pin = mapPoint(
                    for: $0.center.coordinate
                ) else {
                    return false
                }
                return hypot(
                    point.x - pin.x,
                    point.y - pin.y
                ) <= 24
            }) {
            onFocusSavedLocation?(location.id)
        }
    }

    private func zoom(by factor: Double) {
        currentRegion = constrained(
            MKCoordinateRegion(
                center: currentRegion.center,
                span: MKCoordinateSpan(
                    latitudeDelta:
                        currentRegion.span.latitudeDelta * factor,
                    longitudeDelta:
                        currentRegion.span.longitudeDelta * factor
                )
            )
        )
        liveImageOffset = .zero
        onVisibleRegionChange?(currentRegion)
        scheduleSnapshot()
    }

    private func fittedRegion() -> MKCoordinateRegion? {
        let coordinates =
            photoGroups.map(\.coordinate)
            + savedLocations.map(\.center.coordinate)
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.04,
                    longitudeDelta: 0.04
                )
            )
        }

        var minimumLatitude = first.latitude
        var maximumLatitude = first.latitude
        var minimumLongitude = first.longitude
        var maximumLongitude = first.longitude
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
        return constrained(
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
                        (maximumLatitude - minimumLatitude) * 1.35
                    ),
                    longitudeDelta: max(
                        0.01,
                        (maximumLongitude - minimumLongitude) * 1.35
                    )
                )
            )
        )
    }

    private func constrained(
        _ region: MKCoordinateRegion
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: max(
                    -84.5,
                    min(84.5, region.center.latitude)
                ),
                longitude: normalizedLongitude(
                    region.center.longitude
                )
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(
                    0.0005,
                    min(168, region.span.latitudeDelta)
                ),
                longitudeDelta: max(
                    0.0005,
                    min(360, region.span.longitudeDelta)
                )
            )
        )
    }

    private func scheduleSnapshot(
        immediate: Bool = false
    ) {
        guard bounds.width >= 2,
              bounds.height >= 2 else {
            return
        }
        snapshotWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.renderSnapshot()
        }
        snapshotWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (immediate ? 0 : 0.14),
            execute: workItem
        )
    }

    private func renderSnapshot() {
        let size = bounds.size
        guard size.width >= 2,
              size.height >= 2 else {
            return
        }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        snapshotter?.cancel()

        let options = MKMapSnapshotter.Options()
        options.region = currentRegion
        options.size = size
        options.mapType = displayStyle.mapType
        options.showsBuildings = true
        options.pointOfInterestFilter = .includingAll

        let snapshotter = MKMapSnapshotter(options: options)
        self.snapshotter = snapshotter
        snapshotter.start { [weak self] snapshot, _ in
            DispatchQueue.main.async {
                guard let self,
                      generation == self.snapshotGeneration,
                      let snapshot else {
                    return
                }
                self.snapshot = snapshot
                self.snapshotSize = size
                self.liveImageOffset = .zero
                self.needsDisplay = true
            }
        }
    }

    private func mapPoint(
        for coordinate: CLLocationCoordinate2D
    ) -> NSPoint? {
        guard let snapshot,
              snapshotSize.width > 0,
              snapshotSize.height > 0 else {
            return nil
        }
        let point = snapshot.point(for: coordinate)
        return NSPoint(
            x:
                point.x * bounds.width / snapshotSize.width
                + liveImageOffset.width,
            y:
                point.y * bounds.height / snapshotSize.height
                + liveImageOffset.height
        )
    }

    private func coordinate(
        at point: NSPoint
    ) -> CLLocationCoordinate2D? {
        guard let snapshot,
              snapshotSize.width > 0,
              snapshotSize.height > 0 else {
            return nil
        }
        let snapshotPoint = CGPoint(
            x:
                (point.x - liveImageOffset.width)
                * snapshotSize.width / bounds.width,
            y:
                (point.y - liveImageOffset.height)
                * snapshotSize.height / bounds.height
        )
        let center = currentRegion.center
        let centerPoint = snapshot.point(for: center)
        let longitudeStep = max(
            0.0001,
            min(1, currentRegion.span.longitudeDelta / 8)
        )
        let east = CLLocationCoordinate2D(
            latitude: center.latitude,
            longitude:
                normalizedLongitude(
                    center.longitude + longitudeStep
                )
        )
        let eastPoint = snapshot.point(for: east)
        let pixelsPerLongitude =
            (eastPoint.x - centerPoint.x) / longitudeStep
        guard abs(pixelsPerLongitude) > 0.000_001 else {
            return nil
        }
        let longitude = normalizedLongitude(
            center.longitude
            + (snapshotPoint.x - centerPoint.x)
                / pixelsPerLongitude
        )

        var lowerLatitude = -85.0
        var upperLatitude = 85.0
        for _ in 0..<38 {
            let candidate =
                (lowerLatitude + upperLatitude) / 2
            let candidatePoint = snapshot.point(
                for: CLLocationCoordinate2D(
                    latitude: candidate,
                    longitude: center.longitude
                )
            )
            if candidatePoint.y > snapshotPoint.y {
                lowerLatitude = candidate
            } else {
                upperLatitude = candidate
            }
        }
        let latitude =
            (lowerLatitude + upperLatitude) / 2
        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    private func drawSavedAreas(
        using snapshot: MKMapSnapshotter.Snapshot
    ) {
        for location in savedLocations {
            guard let center = mapPoint(
                for: location.center.coordinate
            ) else {
                continue
            }
            let latitudeOffset =
                location.radiusMeters / 111_000
            let longitudeScale = max(
                0.15,
                cos(
                    location.center.latitude
                        * Double.pi / 180
                )
            )
            let eastCoordinate = CLLocationCoordinate2D(
                latitude: location.center.latitude,
                longitude:
                    location.center.longitude
                    + latitudeOffset / longitudeScale
            )
            let northCoordinate = CLLocationCoordinate2D(
                latitude:
                    location.center.latitude
                    + latitudeOffset,
                longitude: location.center.longitude
            )
            guard let east = mapPoint(for: eastCoordinate),
                  let north = mapPoint(for: northCoordinate) else {
                continue
            }
            let radiusX = max(2, abs(east.x - center.x))
            let radiusY = max(2, abs(north.y - center.y))
            let ellipse = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - radiusX,
                    y: center.y - radiusY,
                    width: radiusX * 2,
                    height: radiusY * 2
                )
            )
            let color =
                location.isPrivate
                ? RAWDeskTokens.ColorToken.warningNS
                : RAWDeskTokens.ColorToken.selectionNS
            color.withAlphaComponent(0.12).setFill()
            color.withAlphaComponent(0.9).setStroke()
            ellipse.lineWidth = 1.5
            ellipse.fill()
            ellipse.stroke()
        }
    }

    private func drawTrack(
        using snapshot: MKMapSnapshotter.Snapshot
    ) {
        guard trackCoordinates.count > 1 else { return }
        let path = NSBezierPath()
        var hasPoint = false
        for coordinate in trackCoordinates {
            guard let point = mapPoint(for: coordinate) else {
                continue
            }
            if hasPoint {
                path.line(to: point)
            } else {
                path.move(to: point)
                hasPoint = true
            }
        }
        guard hasPoint else { return }
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        RAWDeskTokens.ColorToken.selectionNS
            .withAlphaComponent(0.86)
            .setStroke()
        path.stroke()
    }

    private func drawPhotoPins(
        using snapshot: MKMapSnapshotter.Snapshot
    ) {
        for group in photoGroups {
            guard let point = mapPoint(
                for: group.coordinate
            ) else {
                continue
            }
            let selected = group.assets.contains {
                selectedAssetIDs.contains($0.id)
            }
            let accent =
                RAWDeskTokens.ColorToken.selectionNS
            let circleRect = NSRect(
                x: point.x - 14,
                y: point.y - 32,
                width: 28,
                height: 28
            )
            let triangle = NSBezierPath()
            triangle.move(
                to: NSPoint(
                    x: point.x - 5,
                    y: point.y - 7
                )
            )
            triangle.line(
                to: NSPoint(
                    x: point.x + 5,
                    y: point.y - 7
                )
            )
            triangle.line(to: point)
            triangle.close()
            (
                selected
                    ? accent
                    : RAWDeskTokens.ColorToken
                        .controlElevatedNS
            ).setFill()
            accent.setStroke()
            triangle.fill()
            triangle.stroke()

            let circle = NSBezierPath(ovalIn: circleRect)
            circle.lineWidth = 2
            (
                selected
                    ? accent
                    : RAWDeskTokens.ColorToken
                        .controlElevatedNS
            ).setFill()
            (
                selected
                    ? RAWDeskTokens.ColorToken
                        .textPrimaryNS
                    : accent
            ).setStroke()
            circle.fill()
            circle.stroke()

            let label =
                group.assets.count > 1
                ? "\(group.assets.count)"
                : "●"
            let attributes: [NSAttributedString.Key: Any] = [
                .font:
                    RAWDeskTokens.Typography.badgeNS,
                .foregroundColor:
                    selected
                    ? RAWDeskTokens.ColorToken
                        .textPrimaryNS
                    : accent
            ]
            var resolvedAttributes = attributes
            if group.assets.count > 1 {
                resolvedAttributes[.font] =
                    RAWDeskTokens.Typography.badgeNS
            }
            let size = label.size(
                withAttributes: resolvedAttributes
            )
            label.draw(
                at: NSPoint(
                    x: point.x - size.width / 2,
                    y:
                        circleRect.midY
                        - size.height / 2
                ),
                withAttributes: resolvedAttributes
            )
        }
    }

    private func drawSavedLocationPins(
        using snapshot: MKMapSnapshotter.Snapshot
    ) {
        for location in savedLocations {
            guard let point = mapPoint(
                for: location.center.coordinate
            ) else {
                continue
            }
            let color =
                location.isPrivate
                ? RAWDeskTokens.ColorToken.warningNS
                : RAWDeskTokens.ColorToken.selectionNS
            let title =
                location.isPrivate
                ? "Private · \(location.name)"
                : location.name
            let attributes: [NSAttributedString.Key: Any] = [
                .font: RAWDeskTokens.Typography.badgeNS,
                .foregroundColor:
                    RAWDeskTokens.ColorToken
                        .textPrimaryNS
            ]
            let textSize = title.size(
                withAttributes: attributes
            )
            let width = min(210, textSize.width + 18)
            let rect = NSRect(
                x: point.x - width / 2,
                y: point.y - 15,
                width: width,
                height: 23
            )
            let capsule = NSBezierPath(
                roundedRect: rect,
                xRadius: 11.5,
                yRadius: 11.5
            )
            RAWDeskTokens.ColorToken
                .controlElevatedNS
                .setFill()
            color.setStroke()
            capsule.lineWidth = 1.5
            capsule.fill()
            capsule.stroke()
            title.draw(
                in: rect.insetBy(dx: 9, dy: 5),
                withAttributes: attributes
            )
        }
    }

    private func drawMapCredit() {
        let title = "Map data © Apple"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: RAWDeskTokens.Typography.metadataNS,
            .foregroundColor:
                RAWDeskTokens.ColorToken.textSecondaryNS,
        ]
        let size = title.size(withAttributes: attributes)
        let rect = NSRect(
            x: 7,
            y: bounds.height - size.height - 6,
            width: size.width + 8,
            height: size.height + 3
        )
        let background = NSBezierPath(
            roundedRect: rect,
            xRadius: RAWDeskTokens.Radius.control,
            yRadius: RAWDeskTokens.Radius.control
        )
        RAWDeskTokens.ColorToken.chromeNS.setFill()
        background.fill()
        title.draw(
            at: NSPoint(
                x: rect.minX + 4,
                y: rect.minY + 1
            ),
            withAttributes: attributes
        )
    }

    private func drawLoadingState() {
        let title = "Loading map…"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: RAWDeskTokens.Typography.controlNS,
            .foregroundColor:
                RAWDeskTokens.ColorToken.textSecondaryNS,
        ]
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    private func normalizedLongitude(
        _ longitude: Double
    ) -> Double {
        var value = longitude
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}

private extension MapDisplayStyle {
    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .hybrid: return .hybrid
        case .satellite: return .satellite
        }
    }
}
