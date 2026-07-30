import SwiftUI

struct RAWDecodeDetailPresentation:
    Equatable,
    Identifiable
{
    enum Kind: Hashable {
        case preview
        case unreadable
    }

    let kind: Kind
    let summary: String
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String

    var id: Kind { kind }

    static func make(
        asset: PhotoAsset,
        decodeSource: RAWImageLoader.DecodeSource?
    ) -> RAWDecodeDetailPresentation? {
        guard asset.isRaw else { return nil }

        if case .failed(let reason) = asset.loadState {
            return RAWDecodeDetailPresentation(
                kind: .unreadable,
                summary: "RAW decode failure",
                title: "RAW file could not be read",
                message:
                    "File: \(asset.filename)\n"
                    + "Error: \(reason)\n\n"
                    + "The original file was not changed.",
                systemImage:
                    "exclamationmark.triangle.fill",
                actionTitle: "Show Details"
            )
        }

        let unsupportedReason: String?
        if case .unsupported(let reason) =
            asset.loadState {
            unsupportedReason = reason
        } else {
            unsupportedReason = nil
        }

        let previewSource: String?
        switch decodeSource {
        case .embeddedPreview:
            previewSource = "Embedded preview"
        case .quickLook:
            previewSource = "Quick Look preview"
        case .ciRAWFilter, .coreImage:
            previewSource = nil
        case nil:
            previewSource =
                unsupportedReason == nil
                ? nil
                : "Embedded preview"
        }
        guard let previewSource else {
            return nil
        }

        let cameraModel = asset.metadata?
            .cameraModel?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let cameraDetail =
            cameraModel.flatMap {
                $0.isEmpty ? nil : "Camera: \($0)\n"
            } ?? ""
        let decoderDetail =
            unsupportedReason.flatMap {
                $0.isEmpty
                    ? nil
                    : "Decoder detail: \($0)\n"
            } ?? ""
        let summary =
            cameraModel.flatMap {
                $0.isEmpty
                    ? nil
                    : "\(previewSource) — \($0) RAW decoder unsupported"
            }
            ?? "\(previewSource) — RAW decoder unsupported"

        return RAWDecodeDetailPresentation(
            kind: .preview,
            summary: summary,
            title: "Why a RAW preview is shown",
            message:
                "\(previewSource) is being shown because this Mac's "
                + "RAW decoder could not render the RAW data.\n"
                + cameraDetail
                + decoderDetail
                + "\nPreview rendering can limit maximum detail. "
                + "The original file was not changed.",
            systemImage: "info.circle",
            actionTitle: "Explain RAW preview"
        )
    }
}

struct MetadataInspectorView: View {
    @ObservedObject var library: LibraryViewModel
    let asset: PhotoAsset?
    /// False when the host panel already shows the shared review controls, so
    /// stars and flags are not offered twice on the same screen.
    var showsReviewControls = true
    /// True when this sits inside a host that already scrolls, so it must not
    /// nest a second scroll view.
    var isEmbedded = false

    @State private var noteDraft: String = ""
    @State private var noteAssetID: PhotoAsset.ID?
    @State private var keywordDraft: String = ""
    @State private var loadedMetadataForID: PhotoAsset.ID?
    @State private var showingCatalogRemovalConfirmation = false
    @State private var showingRAWPreviewDetails = false
    @State private var rawErrorDetails:
        RAWDecodeDetailPresentation?
    @State private var rawDecodeSource:
        RAWImageLoader.DecodeSource?

    var body: some View {
        Group {
            if isEmbedded {
                sections
            } else {
                ScrollView {
                    sections
                        .padding(RAWDeskTokens.Spacing.medium)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                }
            }
        }
        .sheet(item: $rawErrorDetails) { detail in
            RAWDecodeErrorDetailSheet(
                presentation: detail
            )
        }
        .task(id: asset?.id) {
            showingRAWPreviewDetails = false
            rawErrorDetails = nil
            await ensureMetadata(for: asset)
            await inspectRawDecoder(for: asset)
            if asset?.id != noteAssetID {
                noteDraft = asset?.userState.note ?? ""
                keywordDraft = ""
                noteAssetID = asset?.id
            }
        }
    }

    private func fileSection(_ asset: PhotoAsset) -> some View {
        let rawDetail =
            RAWDecodeDetailPresentation.make(
                asset: asset,
                decodeSource: rawDecodeSource
            )
        return VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            Text(asset.filename)
                .font(RAWDeskTokens.Typography.workspaceHeader)
                .lineLimit(1).truncationMode(.middle)
            Text(asset.path)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle)
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                RAWFormatBadge(
                    asset: asset,
                    loadState: asset.loadState,
                    rawDecodeSource:
                        rawDecodeSource
                )
                if asset.isRaw {
                    RAWStateBadge(
                        text: rawDecoderStatus(asset),
                        systemImage: "camera.aperture",
                        tone: .neutral
                    )
                    if rawDetail?.kind == .preview,
                       let rawDetail {
                        Button {
                            showingRAWPreviewDetails =
                                true
                        } label: {
                            Image(
                                systemName:
                                    rawDetail.systemImage
                            )
                        }
                        .buttonStyle(.plain)
                        .rawIconButtonTarget()
                        .help(rawDetail.actionTitle)
                        .accessibilityLabel(
                            rawDetail.actionTitle
                        )
                        .popover(
                            isPresented:
                                $showingRAWPreviewDetails,
                            arrowEdge: .trailing
                        ) {
                            RAWDecodeDetailPopover(
                                presentation: rawDetail
                            )
                        }
                    }
                }
                Spacer()
            }
            row("Size", DisplayFormatters.bytes(asset.fileSize))
            row("Created", DisplayFormatters.date(asset.creationDate))
            row("Modified", DisplayFormatters.date(asset.modificationDate))
            row("Status", statusText(asset.loadState))
            row(
                "XMP sidecar",
                asset.xmpSidecarURL?.lastPathComponent ?? "None"
            )
            if let rawDetail {
                row(
                    rawDetail.kind == .preview
                        ? "RAW detail"
                        : "RAW error",
                    rawDetail.summary
                )
                if rawDetail.kind == .unreadable {
                    Button(rawDetail.actionTitle) {
                        rawErrorDetails = rawDetail
                    }
                    .rawSecondaryTextAction()
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                    .accessibilityHint(
                        "Opens the RAW error details sheet"
                    )
                }
            }
            if asset.xmpImportedOnScan {
                Text("Compatible metadata was loaded from the sidecar.")
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            HStack {
                Button("Read XMP") {
                    library.readMetadataFromXMPSidecars()
                }
                .disabled(asset.xmpSidecarURL == nil)

                Button("Save XMP") {
                    library.saveMetadataToXMPSidecars()
                }
                .disabled(asset.catalogMissing)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if asset.catalogMissing {
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
                    Label(
                        "The original is offline or has moved.",
                        systemImage: "questionmark.folder"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.warning)

                    HStack {
                        Button("Locate Original…") {
                            library.locateMissingPhoto(asset.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .rawPrimaryButtonHeight()

                        Button("Remove from Catalog…", role: .destructive) {
                            showingCatalogRemovalConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
                .confirmationDialog(
                    "Remove \(asset.filename) from the catalog?",
                    isPresented: $showingCatalogRemovalConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove from Catalog", role: .destructive) {
                        _ = library.removeFromCatalog(asset.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "The catalog record, edits, and organization metadata will be removed. No image file will be deleted."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.medium
        ) {
            if let asset {
                fileSection(asset)
                Divider()
                userStateSection(asset)
                Divider()
                metadataSection(asset)
            } else {
                Text("No selection")
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .padding(.top, RAWDeskTokens.Spacing.xLarge)
            }
        }
    }

    private func userStateSection(_ asset: PhotoAsset) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Text("Organization").font(RAWDeskTokens.Typography.sectionHeader)

            // Rating, pick, and colour label all go through the one shared
            // control. They used to appear here as gold stars, a switch, and
            // two menus while Quick Review showed the same three fields as
            // text buttons — the same data in two different vocabularies.
            if showsReviewControls {
                RAWReviewControls(
                    library: library,
                    asset: asset
                )
            }

            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Button {
                    library.toggleFavorite(for: asset.id)
                } label: {
                    Label(
                        "Favorite",
                        systemImage:
                            asset.userState.favorite
                            ? "heart.fill"
                            : "heart"
                    )
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .rawIconButtonTarget()
                .help("Favorite")
                .accessibilityLabel("Favorite")
                .accessibilityAddTraits(
                    asset.userState.favorite
                        ? [.isButton, .isSelected]
                        : [.isButton]
                )

                Spacer(minLength: 0)

                Button {
                    library.isColorLabelSetEditorPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .rawIconButtonTarget()
                .help("Edit color-label sets")
                .accessibilityLabel(
                    "Edit color-label sets"
                )
            }

            if asset.userState.colorLabel == .none,
               let unmatched =
                   asset.userState.colorLabelMetadataValue {
                Label(
                    "Unmatched XMP label: \(unmatched)",
                    systemImage: "exclamationmark.circle"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.warning)
            }

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                HStack {
                    Text("Keywords")
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    Spacer()
                    if library.selectedIDs.count > 1 {
                        Text("\(library.selectedIDs.count) selected")
                            .font(RAWDeskTokens.Typography.badge)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }
                }

                if asset.userState.keywords.isEmpty {
                    Text("No keywords")
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 72, maximum: 180),
                                spacing: RAWDeskTokens.Spacing.xSmall,
                                alignment: .leading
                            ),
                        ],
                        alignment: .leading,
                        spacing: RAWDeskTokens.Spacing.xSmall
                    ) {
                        ForEach(asset.userState.keywords, id: \.self) {
                            keyword in
                            KeywordChip(keyword: keyword) {
                                library.removeKeyword(
                                    keyword,
                                    for: asset.id
                                )
                            }
                        }
                    }
                }

                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    TextField(
                        "Add keywords or hierarchy…",
                        text: $keywordDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        commitKeywords(for: asset)
                    }

                    Button("Add") {
                        commitKeywords(for: asset)
                    }
                    .disabled(parsedKeywordDraft.isEmpty)
                }
                .controlSize(.small)

                Text(
                    "Use > for hierarchy; separate keywords with commas or semicolons."
                )
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Note").font(RAWDeskTokens.Typography.metadata).foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                TextEditor(text: $noteDraft)
                    .frame(minHeight: 60, maxHeight: 120)
                    .font(RAWDeskTokens.Typography.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                            .stroke(RAWDeskTokens.ColorToken.textSecondary.opacity(0.3))
                    )
                    .onChange(of: noteDraft) { _, newValue in
                        if let id = noteAssetID {
                            library.setNote(newValue, for: id)
                        }
                    }
            }
        }
    }

    private var parsedKeywordDraft: [String] {
        PhotoUserState.normalizedKeywords(
            keywordDraft
                .components(
                    separatedBy: CharacterSet(
                        charactersIn: ",;\n"
                    )
                )
        )
    }

    private func commitKeywords(for asset: PhotoAsset) {
        let keywords = parsedKeywordDraft
        guard !keywords.isEmpty else { return }
        library.addKeywords(keywords, for: asset.id)
        keywordDraft = ""
    }

    private func metadataSection(_ asset: PhotoAsset) -> some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            Text("Image").font(RAWDeskTokens.Typography.sectionHeader)
            row("Dimensions", DisplayFormatters.dimensions(asset.metadata?.pixelWidth, asset.metadata?.pixelHeight))
            row("Capture date", DisplayFormatters.date(asset.metadata?.captureDate))
            row("Color profile", DisplayFormatters.placeholder(asset.metadata?.colorProfile))

            Text("Camera").font(RAWDeskTokens.Typography.sectionHeader).padding(.top, RAWDeskTokens.Spacing.xSmall)
            row("Make", DisplayFormatters.placeholder(asset.metadata?.cameraMake))
            row("Model", DisplayFormatters.placeholder(asset.metadata?.cameraModel))
            row("Lens", DisplayFormatters.placeholder(asset.metadata?.lensModel))

            Text("Exposure").font(RAWDeskTokens.Typography.sectionHeader).padding(.top, RAWDeskTokens.Spacing.xSmall)
            row("ISO", DisplayFormatters.iso(asset.metadata?.iso))
            row("Shutter", DisplayFormatters.shutter(asset.metadata?.shutterSpeed))
            row("Aperture", DisplayFormatters.aperture(asset.metadata?.aperture))
            row("Focal length", DisplayFormatters.focalLength(asset.metadata?.focalLength))
            row("Exposure bias", DisplayFormatters.exposureBias(asset.metadata?.exposureBias))

            Text("Location").font(RAWDeskTokens.Typography.sectionHeader).padding(.top, RAWDeskTokens.Spacing.xSmall)
            row("Source", asset.locationSource.name)
            if let location = asset.effectiveLocation {
                row("Coordinates", location.coordinateText)
                if let altitude = location.altitudeText {
                    row("Altitude", altitude)
                }
            } else {
                row("Coordinates", "—")
            }
            Button {
                library.showMap()
            } label: {
                Label(
                    asset.effectiveLocation == nil
                        ? "Set on Map"
                        : "Show on Map",
                    systemImage: "map"
                )
            }
            .rawSecondaryTextAction()
            .font(RAWDeskTokens.Typography.metadata)
            .accessibilityIdentifier("Metadata show map")

            if let err = asset.metadata?.error {
                Text(err)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                    .padding(.top, RAWDeskTokens.Spacing.xSmall)
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        RAWInspectorRow {
            HStack(alignment: .firstTextBaseline) {
                Text(key)
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                    .frame(
                        width: 100,
                        alignment: .leading
                    )
                Text(value)
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    private func statusText(_ state: ImageLoadState) -> String {
        switch state {
        case .idle: return "Idle"
        case .loading: return "Loading"
        case .loaded: return "Ready"
        case .failed(let r): return "Failed — \(r)"
        case .unsupported(let r): return "Unsupported — \(r)"
        }
    }

    private func rawDecoderStatus(
        _ asset: PhotoAsset
    ) -> String {
        if let rawDecodeSource {
            switch rawDecodeSource {
            case .ciRAWFilter:
                return "RAW (CIRAWFilter)"
            case .coreImage:
                return "RAW (Core Image)"
            case .embeddedPreview:
                return "Embedded preview — RAW decoder unsupported"
            case .quickLook:
                return "Quick Look preview — RAW decoder unsupported"
            }
        }
        switch asset.loadState {
        case .unsupported:
            return "Embedded preview / unsupported decoder"
        case .failed:
            return "Unreadable"
        case .idle, .loading:
            return "Checking RAW decoder"
        case .loaded:
            return "Checking RAW decoder"
        }
    }

    private func inspectRawDecoder(
        for asset: PhotoAsset?
    ) async {
        rawDecodeSource =
            asset?.rawDecodeSource
        guard let asset, asset.isRaw,
              !asset.catalogMissing else {
            return
        }
        if asset.rawDecodeSource != nil {
            return
        }
        let id = asset.id
        let url = asset.url
        let source =
            await Task.detached(
                priority: .utility
            ) {
                try? RAWImageLoader.loadResult(
                    url: url,
                    targetLongestEdge: 320
                ).source
            }.value
        guard !Task.isCancelled,
              self.asset?.id == id else {
            return
        }
        rawDecodeSource = source
    }

    private func ensureMetadata(for asset: PhotoAsset?) async {
        guard let asset,
              asset.metadata?.readerVersion
                != MetadataReader.currentReaderVersion,
              loadedMetadataForID != asset.id else {
            return
        }
        loadedMetadataForID = asset.id
        let url = asset.url
        let id = asset.id
        let metadata = await Task.detached(priority: .utility) {
            MetadataReader.read(url: url)
        }.value
        await MainActor.run {
            library.updateMetadata(metadata, for: id)
        }
    }
}

private struct RAWDecodeDetailPopover: View {
    let presentation: RAWDecodeDetailPresentation

    var body: some View {
        RAWInlineMessage(
            title: presentation.title,
            message: presentation.message,
            systemImage: presentation.systemImage,
            tone: .neutral
        )
        .padding(RAWDeskTokens.Spacing.medium)
        .frame(width: 340)
        .accessibilityIdentifier(
            "RAW preview explanation"
        )
    }
}

private struct RAWDecodeErrorDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: RAWDecodeDetailPresentation

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.large
        ) {
            Text("RAW Error Details")
                .font(RAWDeskTokens.Typography.modalTitle)

            RAWInlineMessage(
                title: presentation.title,
                message: presentation.message,
                systemImage: presentation.systemImage,
                tone: .destructive
            )

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(width: 480)
        .accessibilityIdentifier(
            "RAW error details sheet"
        )
    }
}

private struct KeywordChip: View {
    let keyword: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8))
            Text(PhotoUserState.displayKeywordPath(keyword))
                .font(RAWDeskTokens.Typography.metadata)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .rawIconButtonTarget()
            .help("Remove \(keyword)")
            .accessibilityLabel(Text("Remove \(keyword)"))
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .background(
            RAWDeskTokens.ColorToken.selection.opacity(0.12),
            in: Capsule()
        )
        .foregroundStyle(RAWDeskTokens.ColorToken.selection)
        .help(PhotoUserState.displayKeywordPath(keyword))
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(RAWDeskTokens.Typography.badge)
            .padding(.horizontal, RAWDeskTokens.Spacing.xSmall).padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control))
    }
}

