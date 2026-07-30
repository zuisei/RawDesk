import Foundation

public struct XMPImportResult: Equatable, Sendable {
    public var state: PhotoUserState
    public var importedFieldCount: Int
    public var usedExactRAWDeskPayload: Bool
    public var warnings: [String]

    public init(
        state: PhotoUserState,
        importedFieldCount: Int,
        usedExactRAWDeskPayload: Bool,
        warnings: [String] = []
    ) {
        self.state = state
        self.importedFieldCount = importedFieldCount
        self.usedExactRAWDeskPayload = usedExactRAWDeskPayload
        self.warnings = warnings
    }
}

public struct XMPWriteResult: Equatable, Sendable {
    public var url: URL
    public var preservedExistingPacket: Bool
    public var wroteExactRAWDeskPayload: Bool
    public var stateWritten: PhotoUserState
    public var warnings: [String]

    public init(
        url: URL,
        preservedExistingPacket: Bool,
        wroteExactRAWDeskPayload: Bool,
        stateWritten: PhotoUserState,
        warnings: [String] = []
    ) {
        self.url = url
        self.preservedExistingPacket = preservedExistingPacket
        self.wroteExactRAWDeskPayload = wroteExactRAWDeskPayload
        self.stateWritten = stateWritten
        self.warnings = warnings
    }
}

public enum XMPSidecarError: LocalizedError, Equatable {
    case sidecarNotFound
    case sidecarTooLarge
    case malformedPacket
    case missingRDFDescription
    case cannotEncodeState
    case cannotWrite(String)

    public var errorDescription: String? {
        switch self {
        case .sidecarNotFound:
            return "No XMP sidecar exists beside this photo."
        case .sidecarTooLarge:
            return "The XMP sidecar is too large to read safely."
        case .malformedPacket:
            return "The XMP sidecar is not valid RDF/XML."
        case .missingRDFDescription:
            return "The XMP packet does not contain a writable RDF description."
        case .cannotEncodeState:
            return "RAWDesk could not encode the current edit state."
        case let .cannotWrite(reason):
            return "RAWDesk could not save the XMP sidecar: \(reason)"
        }
    }
}

/// Reads and writes external XMP packets without modifying the source photo.
///
/// Shared development controls use Adobe's Camera Raw namespace so ratings and
/// common global edits can move between RAWDesk, Lightroom, Camera Raw, and
/// other XMP-aware tools. A namespaced JSON payload preserves RAWDesk-only
/// features such as masks, Point Color, repairs, profiles, and named versions.
/// Existing unknown XMP properties are retained when a packet is updated.
public enum XMPSidecarService {
    public static let cameraRawNamespace =
        "http://ns.adobe.com/camera-raw-settings/1.0/"
    public static let xmpNamespace =
        "http://ns.adobe.com/xap/1.0/"
    public static let rdfNamespace =
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    public static let dcNamespace =
        "http://purl.org/dc/elements/1.1/"
    public static let lightroomNamespace =
        "http://ns.adobe.com/lightroom/1.0/"
    public static let exifNamespace =
        "http://ns.adobe.com/exif/1.0/"
    public static let rawDeskNamespace =
        "https://rawdesk.local/ns/edit-state/1.0/"

    private static let xmpMetaNamespace = "adobe:ns:meta/"
    private static let maximumPacketBytes = 64 * 1_024 * 1_024
    private static let maximumExactPayloadBytes = 48 * 1_024 * 1_024

    public static func canonicalSidecarURL(for photoURL: URL) -> URL {
        photoURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    public static func existingSidecarURL(for photoURL: URL) -> URL? {
        let lower = canonicalSidecarURL(for: photoURL)
        if FileManager.default.fileExists(atPath: lower.path) {
            return actualCaseURL(for: lower)
        }
        let upper = lower.deletingPathExtension().appendingPathExtension("XMP")
        if FileManager.default.fileExists(atPath: upper.path) {
            return actualCaseURL(for: upper)
        }
        return nil
    }

    public static func read(
        for photoURL: URL,
        merging base: PhotoUserState = .empty,
        colorLabelSet: PhotoColorLabelSet = .standard
    ) throws -> XMPImportResult {
        guard let sidecarURL = existingSidecarURL(for: photoURL) else {
            throw XMPSidecarError.sidecarNotFound
        }
        return try read(
            from: sidecarURL,
            merging: base,
            colorLabelSet: colorLabelSet
        )
    }

    public static func read(
        from sidecarURL: URL,
        merging base: PhotoUserState = .empty,
        colorLabelSet: PhotoColorLabelSet = .standard
    ) throws -> XMPImportResult {
        let data = try safePacketData(from: sidecarURL)
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw XMPSidecarError.malformedPacket
        }

        let packetProperties = propertyMap(in: document)
        var properties = packetProperties
        var state = base
        var importedFieldCount = 0
        var usedExactPayload = false
        var warnings: [String] = []
        var shouldImportToneCurve = true
        var shouldImportKeywords = true

        if let encodedState = property(
            named: "State",
            namespace: rawDeskNamespace,
            in: packetProperties
        ) {
            let compact = encodedState.filter { !$0.isWhitespace }
            if compact.utf8.count <= maximumExactPayloadBytes * 2,
               let payload = Data(
                   base64Encoded: compact,
                   options: [.ignoreUnknownCharacters]
               ),
               payload.count <= maximumExactPayloadBytes {
                do {
                    state = try JSONDecoder().decode(
                        PhotoUserState.self,
                        from: payload
                    )
                    usedExactPayload = true
                    importedFieldCount += 1
                } catch {
                    warnings.append(
                        "The embedded RAWDesk edit payload was invalid; compatible XMP fields were still read."
                    )
                }
            } else {
                warnings.append(
                    "The embedded RAWDesk edit payload was too large or invalid; compatible XMP fields were still read."
                )
            }
        }

        if usedExactPayload,
           let encodedSnapshot = property(
               named: "SharedSnapshot",
               namespace: rawDeskNamespace,
               in: packetProperties
           ),
           let snapshotData = Data(
               base64Encoded: encodedSnapshot.filter { !$0.isWhitespace },
               options: [.ignoreUnknownCharacters]
           ),
           let savedSnapshot = try? JSONDecoder().decode(
               [String: String].self,
               from: snapshotData
           ) {
            let currentSnapshot = sharedSnapshot(in: document)
            properties = packetProperties.filter { key, value in
                guard isSharedSnapshotKey(key) else { return true }
                return savedSnapshot[key] != value
            }
            let curveKey = toneCurveSnapshotKey
            shouldImportToneCurve =
                savedSnapshot[curveKey] != currentSnapshot[curveKey]
            let keywordsKey = keywordSnapshotKey
            let hierarchicalKey = hierarchicalKeywordSnapshotKey
            shouldImportKeywords =
                savedSnapshot[keywordsKey] != currentSnapshot[keywordsKey]
                || savedSnapshot[hierarchicalKey]
                    != currentSnapshot[hierarchicalKey]
        }

        let pickValue = integerProperty(
            ["Pick"],
            namespace: cameraRawNamespace,
            in: properties
        )
        if let rating = doubleProperty(
            ["Rating"],
            namespace: xmpNamespace,
            in: properties
        ) {
            if rating < 0 {
                state.rating = 0
                if pickValue == nil {
                    state.pickStatus = .rejected
                }
            } else {
                state.rating = Int(rating.rounded())
            }
            importedFieldCount += 1
        }
        if let labelValue = property(
            named: "Label",
            namespace: xmpNamespace,
            in: properties
        ) {
            if let colorLabel = colorLabelSet.color(
                matchingMetadataValue: labelValue
            ) ?? PhotoColorLabel(xmpValue: labelValue) {
                state.assignColorLabel(
                    colorLabel,
                    metadataValue: labelValue
                )
                importedFieldCount += 1
            } else {
                state.colorLabel = .none
                state.colorLabelMetadataValue =
                    PhotoColorLabelSet.normalizedMetadataValue(
                        labelValue
                    )
                importedFieldCount += 1
                warnings.append(
                    "The custom XMP color label “\(labelValue)” was retained as unmatched metadata because it is not present in the active color-label set."
                )
            }
        }
        if let pickValue {
            state.pickStatus = pickValue < 0
                ? .rejected
                : (pickValue > 0 ? .picked : .unflagged)
            importedFieldCount += 1
        }
        if let favorite = boolProperty(
            ["Favorite"],
            namespace: rawDeskNamespace,
            in: properties
        ) {
            state.favorite = favorite
            importedFieldCount += 1
        }
        if let note = property(
            named: "Note",
            namespace: rawDeskNamespace,
            in: properties
        ) {
            state.note = note
            importedFieldCount += 1
        }
        let flatKeywords = bagValues(
            named: "subject",
            namespace: dcNamespace,
            in: document
        )
        let hierarchicalKeywords = bagValues(
            named: "hierarchicalSubject",
            namespace: lightroomNamespace,
            in: document
        )
        if shouldImportKeywords,
           flatKeywords != nil || hierarchicalKeywords != nil {
            state.keywords = PhotoUserState.mergedXMPKeywords(
                flat: flatKeywords ?? [],
                hierarchical: hierarchicalKeywords ?? []
            )
            importedFieldCount += 1
        }
        if let location = xmpLocation(in: properties) {
            state.setLocation(location)
            importedFieldCount += 1
        }

        var adjustments = state.adjustments

        func importDouble(
            _ names: [String],
            namespace: String = cameraRawNamespace,
            _ apply: (Double) -> Void
        ) {
            guard let value = doubleProperty(
                names,
                namespace: namespace,
                in: properties
            ) else { return }
            apply(value)
            importedFieldCount += 1
        }

        importDouble(["Exposure2012", "Exposure"]) {
            adjustments.exposure = $0
        }
        importDouble(["Contrast2012", "Contrast"]) {
            adjustments.contrast = $0
        }
        importDouble(["Highlights2012"]) {
            adjustments.highlights = $0
        }
        importDouble(["Shadows2012"]) {
            adjustments.shadows = $0
        }
        importDouble(["Whites2012"]) {
            adjustments.whites = $0
        }
        importDouble(["Blacks2012"]) {
            adjustments.blacks = $0
        }

        let whiteBalance = property(
            named: "WhiteBalance",
            namespace: cameraRawNamespace,
            in: properties
        )?.lowercased()
        if whiteBalance == "as shot" {
            adjustments.temperature = 0
            adjustments.tint = 0
            importedFieldCount += 1
        } else {
            importDouble(["Temperature"]) {
                adjustments.temperature = ($0 - 6_500) / 25
            }
            importDouble(["Tint"]) {
                adjustments.tint = $0 / 1.5
            }
        }
        importDouble(["Vibrance"]) {
            adjustments.vibrance = $0
        }
        importDouble(["Saturation"]) {
            adjustments.saturation = $0
        }

        if let profileRawValue = property(
            named: "DevelopmentProfile",
            namespace: rawDeskNamespace,
            in: properties
        ), let profile = DevelopmentProfile(rawValue: profileRawValue) {
            let amount = doubleProperty(
                ["DevelopmentProfileAmount"],
                namespace: rawDeskNamespace,
                in: properties
            ) ?? adjustments.developmentProfile.amount
            adjustments.developmentProfile = DevelopmentProfileSettings(
                profile: profile,
                amount: amount
            )
            importedFieldCount += 1
        }

        if shouldImportToneCurve, let curve = toneCurve(in: document) {
            adjustments.toneCurve = curve
            importedFieldCount += 1
        }

        for channel in ColorMixerChannel.allCases {
            var value = adjustments.colorMixer[channel]
            let suffix = channel.name
            var changed = false
            if let hue = doubleProperty(
                ["HueAdjustment\(suffix)"],
                namespace: cameraRawNamespace,
                in: properties
            ) {
                value.hue = hue
                changed = true
            }
            if let saturation = doubleProperty(
                ["SaturationAdjustment\(suffix)"],
                namespace: cameraRawNamespace,
                in: properties
            ) {
                value.saturation = saturation
                changed = true
            }
            if let luminance = doubleProperty(
                ["LuminanceAdjustment\(suffix)"],
                namespace: cameraRawNamespace,
                in: properties
            ) {
                value.luminance = luminance
                changed = true
            }
            if changed {
                adjustments.colorMixer[channel] = value
                importedFieldCount += 1
            }
        }

        var grading = adjustments.colorGrading
        func importWheel(
            _ region: ColorGradingRegion,
            hueNames: [String],
            saturationNames: [String],
            luminanceNames: [String]
        ) {
            var wheel = grading[region]
            var changed = false
            if let hue = doubleProperty(
                hueNames,
                namespace: cameraRawNamespace,
                in: properties
            ) {
                wheel.hue = hue
                changed = true
            }
            if let saturation = doubleProperty(
                saturationNames,
                namespace: cameraRawNamespace,
                in: properties
            ) {
                wheel.saturation = saturation
                changed = true
            }
            if let luminance = doubleProperty(
                luminanceNames,
                namespace: cameraRawNamespace,
                in: properties
            ) {
                wheel.luminance = luminance
                changed = true
            }
            if changed {
                grading[region] = wheel
                importedFieldCount += 1
            }
        }
        importWheel(
            .shadows,
            hueNames: ["ColorGradeShadowHue", "SplitToningShadowHue"],
            saturationNames: [
                "ColorGradeShadowSat",
                "SplitToningShadowSaturation",
            ],
            luminanceNames: ["ColorGradeShadowLum"]
        )
        importWheel(
            .midtones,
            hueNames: ["ColorGradeMidtoneHue"],
            saturationNames: ["ColorGradeMidtoneSat"],
            luminanceNames: ["ColorGradeMidtoneLum"]
        )
        importWheel(
            .highlights,
            hueNames: [
                "ColorGradeHighlightHue",
                "SplitToningHighlightHue",
            ],
            saturationNames: [
                "ColorGradeHighlightSat",
                "SplitToningHighlightSaturation",
            ],
            luminanceNames: ["ColorGradeHighlightLum"]
        )
        importWheel(
            .global,
            hueNames: ["ColorGradeGlobalHue"],
            saturationNames: ["ColorGradeGlobalSat"],
            luminanceNames: ["ColorGradeGlobalLum"]
        )
        importDouble(["ColorGradeBlending"]) {
            grading.blending = $0
        }
        importDouble(["SplitToningBalance", "ColorGradeBalance"]) {
            grading.balance = $0
        }
        adjustments.colorGrading = grading

        var calibration = adjustments.calibration
        importDouble(["ShadowTint"]) {
            calibration.shadowsTint = $0
        }
        importDouble(["RedHue"]) {
            calibration.redPrimaryHue = $0
        }
        importDouble(["RedSaturation"]) {
            calibration.redPrimarySaturation = $0
        }
        importDouble(["GreenHue"]) {
            calibration.greenPrimaryHue = $0
        }
        importDouble(["GreenSaturation"]) {
            calibration.greenPrimarySaturation = $0
        }
        importDouble(["BlueHue"]) {
            calibration.bluePrimaryHue = $0
        }
        importDouble(["BlueSaturation"]) {
            calibration.bluePrimarySaturation = $0
        }
        adjustments.calibration = calibration

        importDouble(["Texture"]) {
            adjustments.texture = $0
        }
        importDouble(["Clarity2012", "Clarity"]) {
            adjustments.clarity = $0
        }
        importDouble(["Dehaze"]) {
            adjustments.dehaze = $0
        }
        importDouble(["PostCropVignetteAmount", "VignetteAmount"]) {
            adjustments.vignette = $0
        }
        importDouble(["GrainAmount"]) {
            adjustments.grainAmount = $0
        }
        importDouble(["GrainSize"]) {
            adjustments.grainSize = $0
        }
        importDouble(["GrainFrequency", "GrainRoughness"]) {
            adjustments.grainRoughness = $0
        }

        importDouble(["Sharpness"]) {
            adjustments.sharpening = $0
        }
        importDouble(["SharpenRadius"]) {
            adjustments.sharpeningRadius = $0
        }
        importDouble(["SharpenDetail"]) {
            adjustments.sharpeningDetail = $0
        }
        importDouble(["SharpenEdgeMasking"]) {
            adjustments.sharpeningMasking = $0
        }
        importDouble(["LuminanceSmoothing"]) {
            adjustments.noiseReduction = $0
        }
        importDouble(["LuminanceNoiseReductionDetail"]) {
            adjustments.noiseReductionDetail = $0
        }
        importDouble(["LuminanceNoiseReductionContrast"]) {
            adjustments.noiseReductionContrast = $0
        }
        importDouble(["ColorNoiseReduction"]) {
            adjustments.colorNoiseReduction = $0
        }
        importDouble(["ColorNoiseReductionDetail"]) {
            adjustments.colorNoiseDetail = $0
        }
        importDouble(["ColorNoiseReductionSmoothness"]) {
            adjustments.colorNoiseSmoothness = $0
        }

        var optics = adjustments.optics
        importDouble(["LensManualDistortionAmount"]) {
            optics.distortion = $0
        }
        importDouble(["LensManualVignetteAmount"]) {
            optics.vignette = $0
        }
        importDouble(["ChromaticAberrationR"]) {
            optics.redCyanShift = $0
        }
        importDouble(["ChromaticAberrationB"]) {
            optics.blueYellowShift = $0
        }
        importDouble(["DefringePurpleAmount"]) {
            optics.purpleDefringe = $0
        }
        importDouble(["DefringeGreenAmount"]) {
            optics.greenDefringe = $0
        }
        adjustments.optics = optics

        var geometry = adjustments.geometry
        importDouble(["PerspectiveVertical"]) {
            geometry.vertical = $0
        }
        importDouble(["PerspectiveHorizontal"]) {
            geometry.horizontal = $0
        }
        importDouble(["PerspectiveAspect"]) {
            geometry.aspect = $0
        }
        importDouble(["PerspectiveScale"]) {
            geometry.scale = $0
        }
        importDouble(["PerspectiveX"]) {
            geometry.offsetX = $0
        }
        importDouble(["PerspectiveY"]) {
            geometry.offsetY = $0
        }
        if let constrain = boolProperty(
            ["PerspectiveConstrainCrop", "CropConstrainToWarp"],
            namespace: cameraRawNamespace,
            in: properties
        ) {
            geometry.constrainCrop = constrain
            importedFieldCount += 1
        }
        adjustments.geometry = geometry

        let hasCrop = boolProperty(
            ["HasCrop"],
            namespace: cameraRawNamespace,
            in: properties
        )
        if hasCrop == false {
            adjustments.crop = .fullFrame
            importedFieldCount += 1
        } else {
            let left = doubleProperty(
                ["CropLeft"],
                namespace: cameraRawNamespace,
                in: properties
            )
            let top = doubleProperty(
                ["CropTop"],
                namespace: cameraRawNamespace,
                in: properties
            )
            let right = doubleProperty(
                ["CropRight"],
                namespace: cameraRawNamespace,
                in: properties
            )
            let bottom = doubleProperty(
                ["CropBottom"],
                namespace: cameraRawNamespace,
                in: properties
            )
            if let left, let top, let right, let bottom,
               hasCrop == true || right > left || bottom > top {
                adjustments.crop = NormalizedCrop(
                    x: left,
                    y: top,
                    width: right - left,
                    height: bottom - top
                )
                importedFieldCount += 1
            }
        }
        importDouble(["CropAngle"]) {
            adjustments.straighten = $0
        }

        state = PhotoUserState(
            rating: state.rating,
            flagged: state.flagged,
            rejected: state.rejected,
            favorite: state.favorite,
            colorLabel: state.colorLabel,
            colorLabelMetadataValue:
                state.colorLabelMetadataValue,
            note: state.note,
            keywords: state.keywords,
            locationOverride: state.locationOverride,
            locationIsRemoved: state.locationIsRemoved,
            adjustments: adjustments,
            versions: state.versions
        )
        return XMPImportResult(
            state: state,
            importedFieldCount: importedFieldCount,
            usedExactRAWDeskPayload: usedExactPayload,
            warnings: warnings
        )
    }

    @discardableResult
    public static func write(
        state: PhotoUserState,
        for photoURL: URL,
        colorLabelSet: PhotoColorLabelSet = .standard
    ) throws -> XMPWriteResult {
        let existingURL = existingSidecarURL(for: photoURL)
        let destination = existingURL ?? canonicalSidecarURL(for: photoURL)
        let document: XMLDocument
        let description: XMLElement

        if let existingURL {
            let data = try safePacketData(from: existingURL)
            do {
                document = try XMLDocument(data: data, options: [])
            } catch {
                throw XMPSidecarError.malformedPacket
            }
            guard let found = rdfDescription(in: document) else {
                throw XMPSidecarError.missingRDFDescription
            }
            description = found
        } else {
            let created = makeDocument()
            document = created.document
            description = created.description
        }

        let existingKeywords = bagValues(
            named: "subject",
            namespace: dcNamespace,
            in: document
        )
        let existingHierarchicalKeywords = bagValues(
            named: "hierarchicalSubject",
            namespace: lightroomNamespace,
            in: document
        )
        let existingColorLabelValue = property(
            named: "Label",
            namespace: xmpNamespace,
            in: propertyMap(in: document)
        )
        let previousRAWDeskState = embeddedRAWDeskState(in: document)
        var stateToWrite = state
        let shouldReplaceKeywords: Bool
        if existingURL == nil {
            shouldReplaceKeywords = true
        } else if let previousRAWDeskState {
            shouldReplaceKeywords =
                previousRAWDeskState.keywords != state.keywords
        } else {
            shouldReplaceKeywords =
                (existingKeywords == nil
                    && existingHierarchicalKeywords == nil)
                || !state.keywords.isEmpty
        }
        if !shouldReplaceKeywords {
            stateToWrite.keywords = PhotoUserState.mergedXMPKeywords(
                flat: existingKeywords ?? [],
                hierarchical: existingHierarchicalKeywords ?? []
            )
        }
        let shouldReplaceColorLabel: Bool
        if existingURL == nil {
            shouldReplaceColorLabel = true
        } else if let previousRAWDeskState {
            shouldReplaceColorLabel =
                previousRAWDeskState.colorLabel != state.colorLabel
                || previousRAWDeskState.colorLabelMetadataValue
                    != state.colorLabelMetadataValue
        } else {
            shouldReplaceColorLabel =
                existingColorLabelValue == nil
                || state.colorLabel != .none
        }
        if !shouldReplaceColorLabel {
            stateToWrite.colorLabelMetadataValue =
                PhotoColorLabelSet.normalizedMetadataValue(
                    existingColorLabelValue
                )
            stateToWrite.colorLabel = existingColorLabelValue.flatMap {
                colorLabelSet.color(matchingMetadataValue: $0)
                    ?? PhotoColorLabel(xmpValue: $0)
            } ?? .none
        }
        let shouldReplaceLocation: Bool
        if existingURL == nil {
            shouldReplaceLocation =
                state.locationOverride != nil
                    || state.locationIsRemoved
        } else if let previousRAWDeskState {
            shouldReplaceLocation =
                previousRAWDeskState.locationOverride
                    != state.locationOverride
                    || previousRAWDeskState.locationIsRemoved
                        != state.locationIsRemoved
                    || state.locationOverride != nil
                    || state.locationIsRemoved
        } else {
            shouldReplaceLocation =
                state.locationOverride != nil
                    || state.locationIsRemoved
        }

        ensureNamespace(
            prefix: "crs",
            uri: cameraRawNamespace,
            on: description
        )
        ensureNamespace(prefix: "xmp", uri: xmpNamespace, on: description)
        ensureNamespace(prefix: "dc", uri: dcNamespace, on: description)
        ensureNamespace(
            prefix: "lr",
            uri: lightroomNamespace,
            on: description
        )
        ensureNamespace(
            prefix: "rawdesk",
            uri: rawDeskNamespace,
            on: description
        )
        ensureNamespace(
            prefix: "exif",
            uri: exifNamespace,
            on: description
        )

        let adjustments = state.adjustments.normalized
        let pick = state.rejected ? -1 : (state.flagged ? 1 : 0)
        setAttribute(
            "Rating",
            prefix: "xmp",
            uri: xmpNamespace,
            value: String(state.rating),
            on: description
        )
        if shouldReplaceColorLabel {
            removeProperty(
                named: "Label",
                namespace: xmpNamespace,
                from: description
            )
            if state.colorLabel != .none,
               let label =
                   state.colorLabelMetadataValue
                    ?? state.colorLabel.xmpValue {
                setAttribute(
                    "Label",
                    prefix: "xmp",
                    uri: xmpNamespace,
                    value: label,
                    on: description
                )
            }
        }
        setAttribute(
            "Pick",
            prefix: "crs",
            uri: cameraRawNamespace,
            value: String(pick),
            on: description
        )
        setAttribute(
            "MetadataDate",
            prefix: "xmp",
            uri: xmpNamespace,
            value: metadataTimestamp(),
            on: description
        )
        setAttribute(
            "Favorite",
            prefix: "rawdesk",
            uri: rawDeskNamespace,
            value: boolString(state.favorite),
            on: description
        )
        setTextElement(
            "Note",
            prefix: "rawdesk",
            uri: rawDeskNamespace,
            value: state.note,
            on: description
        )
        if shouldReplaceLocation {
            for name in [
                "GPSVersionID",
                "GPSLatitude",
                "GPSLongitude",
                "GPSAltitude",
                "GPSAltitudeRef",
            ] {
                removeProperty(
                    named: name,
                    namespace: exifNamespace,
                    from: description
                )
            }
            if !state.locationIsRemoved,
               let location = state.locationOverride {
                setAttribute(
                    "GPSVersionID",
                    prefix: "exif",
                    uri: exifNamespace,
                    value: "2.3.0.0",
                    on: description
                )
                setAttribute(
                    "GPSLatitude",
                    prefix: "exif",
                    uri: exifNamespace,
                    value: xmpCoordinate(
                        location.latitude,
                        positiveReference: "N",
                        negativeReference: "S"
                    ),
                    on: description
                )
                setAttribute(
                    "GPSLongitude",
                    prefix: "exif",
                    uri: exifNamespace,
                    value: xmpCoordinate(
                        location.longitude,
                        positiveReference: "E",
                        negativeReference: "W"
                    ),
                    on: description
                )
                if let altitude = location.altitude {
                    setAttribute(
                        "GPSAltitude",
                        prefix: "exif",
                        uri: exifNamespace,
                        value: xmpRational(
                            abs(altitude)
                        ),
                        on: description
                    )
                    setAttribute(
                        "GPSAltitudeRef",
                        prefix: "exif",
                        uri: exifNamespace,
                        value: altitude < 0 ? "1" : "0",
                        on: description
                    )
                }
            }
        }
        if shouldReplaceKeywords {
            setBagElement(
                "subject",
                prefix: "dc",
                uri: dcNamespace,
                values: PhotoUserState.flatKeywords(
                    from: stateToWrite.keywords
                ),
                on: description
            )
            setBagElement(
                "hierarchicalSubject",
                prefix: "lr",
                uri: lightroomNamespace,
                values: stateToWrite.keywords,
                on: description
            )
        }
        setAttribute(
            "SchemaVersion",
            prefix: "rawdesk",
            uri: rawDeskNamespace,
            value: "1",
            on: description
        )
        setAttribute(
            "DevelopmentProfile",
            prefix: "rawdesk",
            uri: rawDeskNamespace,
            value: adjustments.developmentProfile.profile.rawValue,
            on: description
        )
        setAttribute(
            "DevelopmentProfileAmount",
            prefix: "rawdesk",
            uri: rawDeskNamespace,
            value: decimal(adjustments.developmentProfile.amount),
            on: description
        )

        let standardProperties: [(String, String)] = [
            ("ProcessVersion", "11.0"),
            ("HasSettings", boolString(!adjustments.isNeutral)),
            ("RawFileName", photoURL.lastPathComponent),
            ("Exposure2012", decimal(adjustments.exposure)),
            ("Contrast2012", decimal(adjustments.contrast)),
            ("Highlights2012", decimal(adjustments.highlights)),
            ("Shadows2012", decimal(adjustments.shadows)),
            ("Whites2012", decimal(adjustments.whites)),
            ("Blacks2012", decimal(adjustments.blacks)),
            (
                "WhiteBalance",
                adjustments.temperature == 0 && adjustments.tint == 0
                    ? "As Shot"
                    : "Custom"
            ),
            (
                "Temperature",
                decimal(6_500 + adjustments.temperature * 25)
            ),
            ("Tint", decimal(adjustments.tint * 1.5)),
            ("Vibrance", decimal(adjustments.vibrance)),
            ("Saturation", decimal(adjustments.saturation)),
            (
                "ToneCurveName2012",
                adjustments.toneCurve.isNeutral ? "Linear" : "Custom"
            ),
            ("Texture", decimal(adjustments.texture)),
            ("Clarity2012", decimal(adjustments.clarity)),
            ("Dehaze", decimal(adjustments.dehaze)),
            ("PostCropVignetteAmount", decimal(adjustments.vignette)),
            ("GrainAmount", decimal(adjustments.grainAmount)),
            ("GrainSize", decimal(adjustments.grainSize)),
            ("GrainFrequency", decimal(adjustments.grainRoughness)),
            ("Sharpness", decimal(adjustments.sharpening)),
            ("SharpenRadius", decimal(adjustments.sharpeningRadius)),
            ("SharpenDetail", decimal(adjustments.sharpeningDetail)),
            (
                "SharpenEdgeMasking",
                decimal(adjustments.sharpeningMasking)
            ),
            ("LuminanceSmoothing", decimal(adjustments.noiseReduction)),
            (
                "LuminanceNoiseReductionDetail",
                decimal(adjustments.noiseReductionDetail)
            ),
            (
                "LuminanceNoiseReductionContrast",
                decimal(adjustments.noiseReductionContrast)
            ),
            (
                "ColorNoiseReduction",
                decimal(adjustments.colorNoiseReduction)
            ),
            (
                "ColorNoiseReductionDetail",
                decimal(adjustments.colorNoiseDetail)
            ),
            (
                "ColorNoiseReductionSmoothness",
                decimal(adjustments.colorNoiseSmoothness)
            ),
            (
                "LensManualDistortionAmount",
                decimal(adjustments.optics.distortion)
            ),
            (
                "LensManualVignetteAmount",
                decimal(adjustments.optics.vignette)
            ),
            (
                "ChromaticAberrationR",
                decimal(adjustments.optics.redCyanShift)
            ),
            (
                "ChromaticAberrationB",
                decimal(adjustments.optics.blueYellowShift)
            ),
            (
                "DefringePurpleAmount",
                decimal(adjustments.optics.purpleDefringe)
            ),
            (
                "DefringeGreenAmount",
                decimal(adjustments.optics.greenDefringe)
            ),
            (
                "PerspectiveVertical",
                decimal(adjustments.geometry.vertical)
            ),
            (
                "PerspectiveHorizontal",
                decimal(adjustments.geometry.horizontal)
            ),
            ("PerspectiveAspect", decimal(adjustments.geometry.aspect)),
            ("PerspectiveScale", decimal(adjustments.geometry.scale)),
            ("PerspectiveX", decimal(adjustments.geometry.offsetX)),
            ("PerspectiveY", decimal(adjustments.geometry.offsetY)),
            (
                "PerspectiveConstrainCrop",
                boolString(adjustments.geometry.constrainCrop)
            ),
            ("HasCrop", boolString(!adjustments.crop.isFullFrame)),
            ("CropLeft", decimal(adjustments.crop.x)),
            ("CropTop", decimal(adjustments.crop.y)),
            (
                "CropRight",
                decimal(adjustments.crop.x + adjustments.crop.width)
            ),
            (
                "CropBottom",
                decimal(adjustments.crop.y + adjustments.crop.height)
            ),
            ("CropAngle", decimal(adjustments.straighten)),
            (
                "CropConstrainToWarp",
                boolString(adjustments.geometry.constrainCrop)
            ),
        ]
        for (name, value) in standardProperties {
            setAttribute(
                name,
                prefix: "crs",
                uri: cameraRawNamespace,
                value: value,
                on: description
            )
        }

        for channel in ColorMixerChannel.allCases {
            let value = adjustments.colorMixer[channel]
            let suffix = channel.name
            setCameraRawAttribute(
                "HueAdjustment\(suffix)",
                value: value.hue,
                on: description
            )
            setCameraRawAttribute(
                "SaturationAdjustment\(suffix)",
                value: value.saturation,
                on: description
            )
            setCameraRawAttribute(
                "LuminanceAdjustment\(suffix)",
                value: value.luminance,
                on: description
            )
        }

        let grading = adjustments.colorGrading
        let gradingProperties: [(String, Double)] = [
            ("ColorGradeShadowHue", grading.shadows.hue),
            ("ColorGradeShadowSat", grading.shadows.saturation),
            ("ColorGradeShadowLum", grading.shadows.luminance),
            ("SplitToningShadowHue", grading.shadows.hue),
            (
                "SplitToningShadowSaturation",
                grading.shadows.saturation
            ),
            ("ColorGradeMidtoneHue", grading.midtones.hue),
            ("ColorGradeMidtoneSat", grading.midtones.saturation),
            ("ColorGradeMidtoneLum", grading.midtones.luminance),
            ("ColorGradeHighlightHue", grading.highlights.hue),
            (
                "ColorGradeHighlightSat",
                grading.highlights.saturation
            ),
            (
                "ColorGradeHighlightLum",
                grading.highlights.luminance
            ),
            ("SplitToningHighlightHue", grading.highlights.hue),
            (
                "SplitToningHighlightSaturation",
                grading.highlights.saturation
            ),
            ("ColorGradeGlobalHue", grading.global.hue),
            ("ColorGradeGlobalSat", grading.global.saturation),
            ("ColorGradeGlobalLum", grading.global.luminance),
            ("ColorGradeBlending", grading.blending),
            ("SplitToningBalance", grading.balance),
        ]
        for (name, value) in gradingProperties {
            setCameraRawAttribute(name, value: value, on: description)
        }

        let calibration = adjustments.calibration
        let calibrationProperties: [(String, Double)] = [
            ("ShadowTint", calibration.shadowsTint),
            ("RedHue", calibration.redPrimaryHue),
            ("RedSaturation", calibration.redPrimarySaturation),
            ("GreenHue", calibration.greenPrimaryHue),
            ("GreenSaturation", calibration.greenPrimarySaturation),
            ("BlueHue", calibration.bluePrimaryHue),
            ("BlueSaturation", calibration.bluePrimarySaturation),
        ]
        for (name, value) in calibrationProperties {
            setCameraRawAttribute(name, value: value, on: description)
        }

        setSequenceElement(
            "ToneCurvePV2012",
            values: toneCurveStrings(adjustments.toneCurve),
            on: description
        )

        var warnings: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let stateData = try? encoder.encode(stateToWrite) else {
            throw XMPSidecarError.cannotEncodeState
        }
        let wroteExactPayload: Bool
        if stateData.count <= maximumExactPayloadBytes {
            setTextElement(
                "State",
                prefix: "rawdesk",
                uri: rawDeskNamespace,
                value: stateData.base64EncodedString(),
                on: description
            )
            wroteExactPayload = true
        } else {
            removeElements(
                named: "State",
                namespace: rawDeskNamespace,
                from: description
            )
            wroteExactPayload = false
            warnings.append(
                "The exact RAWDesk payload exceeded the XMP safety limit; Adobe-compatible global fields were still saved."
            )
        }

        if let snapshotData = try? JSONEncoder().encode(
            sharedSnapshot(in: document)
        ) {
            setTextElement(
                "SharedSnapshot",
                prefix: "rawdesk",
                uri: rawDeskNamespace,
                value: snapshotData.base64EncodedString(),
                on: description
            )
        }

        let output = document.xmlData(options: [.nodePrettyPrint])
        do {
            try output.write(to: destination, options: [.atomic])
        } catch {
            throw XMPSidecarError.cannotWrite(error.localizedDescription)
        }
        return XMPWriteResult(
            url: destination,
            preservedExistingPacket: existingURL != nil,
            wroteExactRAWDeskPayload: wroteExactPayload,
            stateWritten: stateToWrite,
            warnings: warnings
        )
    }

    private static func safePacketData(from url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XMPSidecarError.sidecarNotFound
        }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize,
           size > maximumPacketBytes {
            throw XMPSidecarError.sidecarTooLarge
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maximumPacketBytes else {
                throw XMPSidecarError.sidecarTooLarge
            }
            return data
        } catch let error as XMPSidecarError {
            throw error
        } catch {
            throw XMPSidecarError.malformedPacket
        }
    }

    private static func actualCaseURL(for url: URL) -> URL {
        guard let name = try? url.resourceValues(forKeys: [.nameKey]).name,
              !name.isEmpty else {
            return url
        }
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    private static func makeDocument() -> (
        document: XMLDocument,
        description: XMLElement
    ) {
        let root = XMLElement(name: "x:xmpmeta")
        root.addNamespace(
            XMLNode.namespace(
                withName: "x",
                stringValue: xmpMetaNamespace
            ) as! XMLNode
        )
        let rdf = XMLElement(name: "rdf:RDF")
        rdf.addNamespace(
            XMLNode.namespace(
                withName: "rdf",
                stringValue: rdfNamespace
            ) as! XMLNode
        )
        let description = XMLElement(name: "rdf:Description")
        description.addAttribute(
            XMLNode.attribute(
                withName: "rdf:about",
                stringValue: ""
            ) as! XMLNode
        )
        rdf.addChild(description)
        root.addChild(rdf)

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return (document, description)
    }

    private static func rdfDescription(
        in document: XMLDocument
    ) -> XMLElement? {
        allElements(in: document).first {
            matches($0, namespace: rdfNamespace, localName: "Description")
        }
    }

    private static func propertyMap(
        in document: XMLDocument
    ) -> [String: String] {
        var result: [String: String] = [:]
        let recognized = Set([
            cameraRawNamespace,
            xmpNamespace,
            dcNamespace,
            lightroomNamespace,
            exifNamespace,
            rawDeskNamespace,
        ])
        let elements = allElements(in: document)

        for element in elements {
            guard let namespace = namespaceURI(of: element),
                  recognized.contains(namespace),
                  elementChildren(of: element).isEmpty,
                  let value = element.stringValue else {
                continue
            }
            result[propertyKey(
                namespace: namespace,
                localName: localName(of: element)
            )] = value
        }

        for element in elements {
            for attribute in element.attributes ?? [] {
                guard let namespace = namespaceURI(of: attribute),
                      recognized.contains(namespace),
                      let value = attribute.stringValue else {
                    continue
                }
                result[propertyKey(
                    namespace: namespace,
                    localName: localName(of: attribute)
                )] = value
            }
        }
        return result
    }

    private static var toneCurveSnapshotKey: String {
        propertyKey(
            namespace: cameraRawNamespace,
            localName: "ToneCurvePV2012Sequence"
        )
    }

    private static var keywordSnapshotKey: String {
        propertyKey(
            namespace: dcNamespace,
            localName: "subjectBag"
        )
    }

    private static var hierarchicalKeywordSnapshotKey: String {
        propertyKey(
            namespace: lightroomNamespace,
            localName: "hierarchicalSubjectBag"
        )
    }

    private static func sharedSnapshot(
        in document: XMLDocument
    ) -> [String: String] {
        var result = propertyMap(in: document).filter {
            isSharedSnapshotKey($0.key)
        }
        if let sequence = toneCurveSequenceSignature(in: document) {
            result[toneCurveSnapshotKey] = sequence
        }
        if let keywords = bagValues(
            named: "subject",
            namespace: dcNamespace,
            in: document
        ) {
            result[keywordSnapshotKey] = keywordSignature(keywords)
        }
        if let hierarchicalKeywords = bagValues(
            named: "hierarchicalSubject",
            namespace: lightroomNamespace,
            in: document
        ) {
            result[hierarchicalKeywordSnapshotKey] = keywordSignature(
                hierarchicalKeywords
            )
        }
        return result
    }

    private static func isSharedSnapshotKey(_ key: String) -> Bool {
        if key.hasPrefix("\(cameraRawNamespace)|") {
            return true
        }
        if key == propertyKey(namespace: xmpNamespace, localName: "Rating") {
            return true
        }
        if key == propertyKey(namespace: xmpNamespace, localName: "Label") {
            return true
        }
        if key == keywordSnapshotKey {
            return true
        }
        if key == hierarchicalKeywordSnapshotKey {
            return true
        }
        let rawDeskNames = [
            "Favorite",
            "Note",
            "DevelopmentProfile",
            "DevelopmentProfileAmount",
        ]
        return rawDeskNames.contains {
            key == propertyKey(namespace: rawDeskNamespace, localName: $0)
        }
    }

    private static func toneCurveSequenceSignature(
        in document: XMLDocument
    ) -> String? {
        guard let curveElement = allElements(in: document).first(where: {
            matches(
                $0,
                namespace: cameraRawNamespace,
                localName: "ToneCurvePV2012"
            )
        }) else {
            return nil
        }
        let values = allElements(in: curveElement)
            .filter {
                matches($0, namespace: rdfNamespace, localName: "li")
            }
            .compactMap(\.stringValue)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        return values.isEmpty ? nil : values.joined(separator: "|")
    }

    private static func keywordSignature(_ values: [String]) -> String {
        let normalized = PhotoUserState.normalizedKeywords(values)
        return "\(normalized.count)|" + normalized.joined(separator: "\u{1F}")
    }

    private static func embeddedRAWDeskState(
        in document: XMLDocument
    ) -> PhotoUserState? {
        guard let encoded = property(
            named: "State",
            namespace: rawDeskNamespace,
            in: propertyMap(in: document)
        ) else {
            return nil
        }
        let compact = encoded.filter { !$0.isWhitespace }
        guard compact.utf8.count <= maximumExactPayloadBytes * 2,
              let data = Data(
                  base64Encoded: compact,
                  options: [.ignoreUnknownCharacters]
              ),
              data.count <= maximumExactPayloadBytes else {
            return nil
        }
        return try? JSONDecoder().decode(PhotoUserState.self, from: data)
    }

    private static func bagValues(
        named name: String,
        namespace: String,
        in document: XMLDocument
    ) -> [String]? {
        guard let property = allElements(in: document).first(where: {
            matches($0, namespace: namespace, localName: name)
        }) else {
            return nil
        }
        return allElements(in: property)
            .filter {
                matches($0, namespace: rdfNamespace, localName: "li")
            }
            .compactMap(\.stringValue)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func property(
        named name: String,
        namespace: String,
        in properties: [String: String]
    ) -> String? {
        properties[propertyKey(namespace: namespace, localName: name)]
    }

    private static func doubleProperty(
        _ names: [String],
        namespace: String,
        in properties: [String: String]
    ) -> Double? {
        for name in names {
            guard let raw = property(
                named: name,
                namespace: namespace,
                in: properties
            ) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(trimmed), value.isFinite {
                return value
            }
        }
        return nil
    }

    private static func integerProperty(
        _ names: [String],
        namespace: String,
        in properties: [String: String]
    ) -> Int? {
        doubleProperty(
            names,
            namespace: namespace,
            in: properties
        ).map { Int($0.rounded()) }
    }

    private static func boolProperty(
        _ names: [String],
        namespace: String,
        in properties: [String: String]
    ) -> Bool? {
        for name in names {
            guard let raw = property(
                named: name,
                namespace: namespace,
                in: properties
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() else {
                continue
            }
            if ["true", "1", "yes"].contains(raw) { return true }
            if ["false", "0", "no"].contains(raw) { return false }
        }
        return nil
    }

    private static func xmpLocation(
        in properties: [String: String]
    ) -> PhotoLocation? {
        guard let latitudeText = property(
            named: "GPSLatitude",
            namespace: exifNamespace,
            in: properties
        ),
        let longitudeText = property(
            named: "GPSLongitude",
            namespace: exifNamespace,
            in: properties
        ),
        let latitude = parseXMPCoordinate(
            latitudeText,
            positiveReference: "N",
            negativeReference: "S"
        ),
        let longitude = parseXMPCoordinate(
            longitudeText,
            positiveReference: "E",
            negativeReference: "W"
        ) else {
            return nil
        }
        var altitude = property(
            named: "GPSAltitude",
            namespace: exifNamespace,
            in: properties
        ).flatMap(parseXMPRational)
        if altitude != nil,
           integerProperty(
               ["GPSAltitudeRef"],
               namespace: exifNamespace,
               in: properties
           ) == 1 {
            altitude = -abs(altitude ?? 0)
        }
        return PhotoLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude
        )
    }

    private static func parseXMPCoordinate(
        _ rawValue: String,
        positiveReference: Character,
        negativeReference: Character
    ) -> Double? {
        let compact = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        guard !compact.isEmpty else { return nil }
        let last = compact.last
        let sign: Double
        let coordinateText: String
        if last == negativeReference {
            sign = -1
            coordinateText = String(compact.dropLast())
        } else if last == positiveReference {
            sign = 1
            coordinateText = String(compact.dropLast())
        } else {
            sign = compact.hasPrefix("-") ? -1 : 1
            coordinateText = compact
        }
        let components = coordinateText
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { Double($0) }
        guard !components.isEmpty else { return nil }
        let degrees = abs(components[0])
        let minutes = components.count > 1
            ? abs(components[1])
            : 0
        let seconds = components.count > 2
            ? abs(components[2])
            : 0
        guard minutes < 60, seconds < 60 else { return nil }
        return sign
            * (degrees + minutes / 60 + seconds / 3_600)
    }

    private static func parseXMPRational(
        _ rawValue: String
    ) -> Double? {
        let components = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", maxSplits: 1)
        if components.count == 2,
           let numerator = Double(components[0]),
           let denominator = Double(components[1]),
           denominator != 0 {
            return numerator / denominator
        }
        return Double(rawValue)
    }

    private static func xmpCoordinate(
        _ value: Double,
        positiveReference: Character,
        negativeReference: Character
    ) -> String {
        let absolute = abs(value)
        let degrees = floor(absolute)
        let minutes = (absolute - degrees) * 60
        let reference = value < 0
            ? negativeReference
            : positiveReference
        return String(
            format: "%.0f,%.8f%@",
            locale: Locale(identifier: "en_US_POSIX"),
            degrees,
            minutes,
            String(reference)
        )
    }

    private static func xmpRational(
        _ value: Double
    ) -> String {
        let denominator = 1_000
        let numerator = Int(
            (value * Double(denominator)).rounded()
        )
        return "\(numerator)/\(denominator)"
    }

    private static func toneCurve(in document: XMLDocument) -> ToneCurve? {
        guard let curveElement = allElements(in: document).first(where: {
            matches(
                $0,
                namespace: cameraRawNamespace,
                localName: "ToneCurvePV2012"
            )
        }) else {
            return nil
        }
        let points = allElements(in: curveElement)
            .filter {
                matches($0, namespace: rdfNamespace, localName: "li")
            }
            .compactMap { element -> (Double, Double)? in
                guard let text = element.stringValue else { return nil }
                let values = text.split(separator: ",", maxSplits: 1)
                guard values.count == 2,
                      let x = Double(
                          values[0].trimmingCharacters(
                              in: .whitespacesAndNewlines
                          )
                      ),
                      let y = Double(
                          values[1].trimmingCharacters(
                              in: .whitespacesAndNewlines
                          )
                      ),
                      x.isFinite,
                      y.isFinite else {
                    return nil
                }
                return (x, y)
            }
            .sorted { $0.0 < $1.0 }
        guard points.count >= 2 else { return nil }

        func interpolatedOutput(at input: Double) -> Double {
            if input <= points[0].0 { return points[0].1 }
            if input >= points[points.count - 1].0 {
                return points[points.count - 1].1
            }
            for index in 1..<points.count {
                let right = points[index]
                let left = points[index - 1]
                guard input <= right.0 else { continue }
                let distance = max(0.000_1, right.0 - left.0)
                let fraction = (input - left.0) / distance
                return left.1 + (right.1 - left.1) * fraction
            }
            return input
        }

        let inputs = [0.0, 64, 128, 192, 255]
        let outputs = inputs.map {
            min(1, max(0, interpolatedOutput(at: $0) / 255))
        }
        return ToneCurve(
            black: outputs[0],
            shadows: outputs[1],
            midtones: outputs[2],
            highlights: outputs[3],
            white: outputs[4]
        )
    }

    private static func setCameraRawAttribute(
        _ name: String,
        value: Double,
        on description: XMLElement
    ) {
        setAttribute(
            name,
            prefix: "crs",
            uri: cameraRawNamespace,
            value: decimal(value),
            on: description
        )
    }

    private static func setAttribute(
        _ localName: String,
        prefix: String,
        uri: String,
        value: String,
        on element: XMLElement
    ) {
        ensureNamespace(prefix: prefix, uri: uri, on: element)
        for attribute in element.attributes ?? []
        where matches(attribute, namespace: uri, localName: localName) {
            if let name = attribute.name {
                element.removeAttribute(forName: name)
            }
        }
        element.addAttribute(
            XMLNode.attribute(
                withName: "\(prefix):\(localName)",
                stringValue: value
            ) as! XMLNode
        )
    }

    private static func setTextElement(
        _ localName: String,
        prefix: String,
        uri: String,
        value: String,
        on description: XMLElement
    ) {
        ensureNamespace(prefix: prefix, uri: uri, on: description)
        removeElements(
            named: localName,
            namespace: uri,
            from: description
        )
        let element = XMLElement(
            name: "\(prefix):\(localName)",
            stringValue: value
        )
        description.addChild(element)
    }

    private static func setSequenceElement(
        _ localName: String,
        values: [String],
        on description: XMLElement
    ) {
        ensureNamespace(
            prefix: "crs",
            uri: cameraRawNamespace,
            on: description
        )
        ensureNamespace(prefix: "rdf", uri: rdfNamespace, on: description)
        removeElements(
            named: localName,
            namespace: cameraRawNamespace,
            from: description
        )
        let property = XMLElement(name: "crs:\(localName)")
        let sequence = XMLElement(name: "rdf:Seq")
        for value in values {
            sequence.addChild(
                XMLElement(name: "rdf:li", stringValue: value)
            )
        }
        property.addChild(sequence)
        description.addChild(property)
    }

    private static func setBagElement(
        _ localName: String,
        prefix: String,
        uri: String,
        values: [String],
        on description: XMLElement
    ) {
        ensureNamespace(prefix: prefix, uri: uri, on: description)
        ensureNamespace(prefix: "rdf", uri: rdfNamespace, on: description)
        removeElements(
            named: localName,
            namespace: uri,
            from: description
        )
        guard !values.isEmpty else { return }
        let property = XMLElement(name: "\(prefix):\(localName)")
        let bag = XMLElement(name: "rdf:Bag")
        for value in values {
            bag.addChild(XMLElement(name: "rdf:li", stringValue: value))
        }
        property.addChild(bag)
        description.addChild(property)
    }

    private static func removeElements(
        named localName: String,
        namespace: String,
        from description: XMLElement
    ) {
        for child in elementChildren(of: description)
        where matches(
            child,
            namespace: namespace,
            localName: localName
        ) {
            child.detach()
        }
    }

    private static func removeProperty(
        named localName: String,
        namespace: String,
        from description: XMLElement
    ) {
        for attribute in description.attributes ?? []
        where matches(
            attribute,
            namespace: namespace,
            localName: localName
        ) {
            if let name = attribute.name {
                description.removeAttribute(forName: name)
            }
        }
        removeElements(
            named: localName,
            namespace: namespace,
            from: description
        )
    }

    private static func ensureNamespace(
        prefix: String,
        uri: String,
        on element: XMLElement
    ) {
        if element.namespaces?.contains(where: {
            $0.name == prefix && $0.stringValue == uri
        }) == true {
            return
        }
        element.addNamespace(
            XMLNode.namespace(
                withName: prefix,
                stringValue: uri
            ) as! XMLNode
        )
    }

    private static func allElements(in node: XMLNode) -> [XMLElement] {
        var result: [XMLElement] = []
        if let element = node as? XMLElement {
            result.append(element)
        }
        for child in node.children ?? [] {
            result.append(contentsOf: allElements(in: child))
        }
        return result
    }

    private static func elementChildren(
        of node: XMLNode
    ) -> [XMLElement] {
        (node.children ?? []).compactMap { $0 as? XMLElement }
    }

    private static func matches(
        _ node: XMLNode,
        namespace: String,
        localName expectedLocalName: String
    ) -> Bool {
        guard localName(of: node) == expectedLocalName else { return false }
        if namespaceURI(of: node) == namespace {
            return true
        }
        let prefix: String
        switch namespace {
        case cameraRawNamespace: prefix = "crs"
        case xmpNamespace: prefix = "xmp"
        case dcNamespace: prefix = "dc"
        case rdfNamespace: prefix = "rdf"
        case rawDeskNamespace: prefix = "rawdesk"
        default: return false
        }
        return node.name == "\(prefix):\(expectedLocalName)"
    }

    private static func namespaceURI(of node: XMLNode) -> String? {
        if let uri = node.uri, !uri.isEmpty {
            return uri
        }
        guard let prefix = node.name?.split(separator: ":").first,
              node.name?.contains(":") == true else {
            return nil
        }
        switch prefix {
        case "crs": return cameraRawNamespace
        case "xmp": return xmpNamespace
        case "dc": return dcNamespace
        case "rdf": return rdfNamespace
        case "rawdesk": return rawDeskNamespace
        default: return nil
        }
    }

    private static func localName(of node: XMLNode) -> String {
        if let localName = node.localName, !localName.isEmpty {
            return localName
        }
        return node.name?.split(separator: ":").last.map(String.init) ?? ""
    }

    private static func propertyKey(
        namespace: String,
        localName: String
    ) -> String {
        "\(namespace)|\(localName)"
    }

    private static func toneCurveStrings(_ curve: ToneCurve) -> [String] {
        let points: [(Int, Double)] = [
            (0, curve.black),
            (64, curve.shadows),
            (128, curve.midtones),
            (192, curve.highlights),
            (255, curve.white),
        ]
        return points.map { input, output in
            "\(input), \(Int((output * 255).rounded()))"
        }
    }

    private static func decimal(_ value: Double) -> String {
        let finite = value.isFinite ? value : 0
        if abs(finite - finite.rounded()) < 0.000_001 {
            return String(Int(finite.rounded()))
        }
        var formatted = String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            finite
        )
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted == "-0" ? "0" : formatted
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "True" : "False"
    }

    private static func metadataTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter.string(from: Date())
    }
}
