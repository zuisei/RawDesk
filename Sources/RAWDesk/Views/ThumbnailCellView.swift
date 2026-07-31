import SwiftUI
import AppKit

enum ThumbnailSelectionPresentation {
    static func strokeWidth(
        isSelected: Bool,
        isActive: Bool,
        compareRole: PhotoCompareRole?,
        surveyRole: PhotoSurveyRole?
    ) -> CGFloat {
        if compareRole != nil
            || surveyRole == .active {
            return 3
        }
        if surveyRole == .selected {
            return 2
        }
        if isActive {
            return 3
        }
        return isSelected ? 2 : 0
    }
}

struct ThumbnailBadgePresentation: Equatable {
    let showsMissingStatus: Bool
    let showsFormatStatus: Bool

    init(catalogMissing: Bool) {
        showsMissingStatus = catalogMissing
        showsFormatStatus = !catalogMissing
    }
}

struct ThumbnailCellView: View {
    let asset: PhotoAsset
    let isSelected: Bool
    var isActive: Bool = false
    let compareRole: PhotoCompareRole?
    let surveyRole: PhotoSurveyRole?
    let pixelSize: CGFloat
    let duplicateGroupNumber: Int?
    let isDuplicateAnchor: Bool
    let isInQuickCollection: Bool
    let isInPhotoCollection: Bool
    let cullingEvaluation: AssistedCullingEvaluation?
    let cullingAnalysis: AssistedCullingAnalysis?
    let cullingStackNumber: Int?
    let stackMembership: CatalogPhotoStackMembership?
    let onStackToggle: () -> Void
    let onLoadStateChange:
        (
            ImageLoadState,
            RAWImageLoader.DecodeSource?
        ) -> Void
    // Optional, so a host that does not wire them does not get an overlay of
    // buttons that silently do nothing. Only the grid supplies these; every
    // filmstrip previously showed a hover cluster with "Pick photo (P)"
    // tooltips that were inert.
    var onQuickPick: (() -> Void)?
    var onQuickReject: (() -> Void)?
    var onQuickRating: ((Int) -> Void)?

    @State private var image: NSImage?
    @State private var loadState: ImageLoadState = .idle
    @State private var rawDecodeSource:
        RAWImageLoader.DecodeSource?
    @State private var isHovering = false

    private let loader = ImageLoader.shared

    private var loadID: String {
        "\(asset.id)|\(Int(pixelSize.rounded()))|\(asset.userState.adjustments.hashValue)"
    }

    private var badgePresentation:
        ThumbnailBadgePresentation {
        ThumbnailBadgePresentation(
            catalogMissing: asset.catalogMissing
        )
    }

    var body: some View {
        VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            ZStack {
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.control
                )
                .fill(RAWDeskTokens.ColorToken.controlElevated)

                contentLayer
                roleAndCollectionLayer
                formatLayer
                reviewStateLayer
                quickActionLayer
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.control
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.control
                )
                .stroke(
                    selectionStrokeColor,
                    lineWidth: selectionStrokeWidth
                )
            }

            Text(asset.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    isSelected
                        ? RAWDeskTokens.ColorToken.textPrimary
                        : RAWDeskTokens.ColorToken.textSecondary
                )
        }
        .padding(RAWDeskTokens.Spacing.xSmall)
        .opacity(asset.catalogMissing ? 0.58 : 1)
        .onHover { isHovering = $0 }
        .task(id: loadID) {
            await load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(
            isSelected ? [.isSelected] : []
        )
        .help(cullingHelp)
    }

    @ViewBuilder
    private var contentLayer: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .padding(RAWDeskTokens.Spacing.xSmall)
        } else {
            switch loadState {
            case .loading, .idle:
                ProgressView()
                    .controlSize(.small)
            case .failed(let message):
                VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    Image(
                        systemName:
                            "exclamationmark.triangle"
                    )
                    Text(message)
                        .font(
                            RAWDeskTokens.Typography.metadata
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .padding(RAWDeskTokens.Spacing.xSmall)
            case .unsupported:
                VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    Image(
                        systemName:
                            "questionmark.square.dashed"
                    )
                    Text("Preview unavailable")
                        .font(
                            RAWDeskTokens.Typography.metadata
                        )
                }
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
            case .loaded:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var roleAndCollectionLayer: some View {
        VStack {
            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                if badgePresentation
                    .showsMissingStatus {
                    RAWStateBadge(
                        text: "Missing",
                        systemImage:
                            "exclamationmark.triangle.fill",
                        tone: .warning
                    )
                }
                if let compareRole {
                    RAWStateBadge(
                        text: compareRole.name,
                        systemImage:
                            compareRole.systemImage,
                        tone: .accent
                    )
                }
                if let surveyRole {
                    RAWStateBadge(
                        text: surveyRole.name,
                        systemImage:
                            surveyRole.systemImage,
                        tone:
                            surveyRole == .active
                            ? .accent
                            : .neutral
                    )
                }
                if let duplicateGroupNumber {
                    RAWStateBadge(
                        text:
                            "Group \(duplicateGroupNumber)"
                            + (
                                isDuplicateAnchor
                                    ? " · Original"
                                    : " · Duplicate"
                            ),
                        systemImage: "square.on.square",
                        tone:
                            isDuplicateAnchor
                            ? .accent
                            : .neutral
                    )
                } else if let cullingEvaluation {
                    RAWStateBadge(
                        text:
                            cullingBadgeText(
                                cullingEvaluation
                            ),
                        systemImage: "checkmark.seal",
                        tone:
                            cullingBadgeTone(
                                cullingEvaluation
                                    .decision
                            )
                    )
                }
                if let stackMembership,
                   stackMembership.isCollapsed
                    || stackMembership.isTop {
                    stackButton(stackMembership)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(RAWDeskTokens.Spacing.xSmall)
    }

    private var formatLayer: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                if badgePresentation
                    .showsFormatStatus {
                    RAWFormatBadge(
                        asset: asset,
                        loadState: loadState,
                        rawDecodeSource:
                            rawDecodeSource
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(RAWDeskTokens.Spacing.xSmall)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var reviewStateLayer: some View {
        // The scrim is there to keep the badges legible over a photograph. On
        // a photo with nothing to report it was a black band across the bottom
        // edge of the cell containing nothing, so it is drawn with the badges.
        if hasReviewState {
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    // Flags are glyphs, never glyph-plus-word — the same rule
                    // the inspector's review controls follow. Each glyph
                    // already carries its word as an accessibility label.
                    if asset.userState.flagged {
                        Label(
                            "Picked",
                            systemImage: "flag.fill"
                        )
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Picked")
                    } else if asset.userState.rejected {
                        Label(
                            "Rejected",
                            systemImage:
                                "xmark.circle.fill"
                        )
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Rejected")
                    }
                    // An unrated photo shows nothing. Stating the absence of a
                    // rating on every cell spends the badge row on no
                    // information and competes with the thumbnail. The number
                    // stays printed, unlike the flags: which rating it is is
                    // the whole of what the badge has to say.
                    if asset.userState.rating > 0 {
                        Label(
                            "\(asset.userState.rating)",
                            systemImage: "star.fill"
                        )
                        .accessibilityLabel(
                            "\(asset.userState.rating) of 5 stars"
                        )
                    }
                    if asset.userState.colorLabel != .none {
                        // The same swatch the inspector and the filter row
                        // draw. The name is dropped: the colour is the label,
                        // and it is spelled out in the cell's accessibility
                        // description and its tooltip.
                        ColorLabelSwatch(
                            label: asset.userState.colorLabel,
                            size: RAWDeskTokens.Size.badgeSwatch
                        )
                    }
                    if asset.userState.favorite {
                        Image(systemName: "heart.fill")
                            .accessibilityLabel("Favorite")
                    }
                    if isInQuickCollection {
                        Image(systemName: "bolt.circle.fill")
                            .accessibilityLabel(
                                "In Quick Collection"
                            )
                    }
                    if isInPhotoCollection {
                        Image(systemName: "rectangle.stack.fill")
                            .accessibilityLabel(
                                "In a collection"
                            )
                    }
                    if !asset.userState.keywords.isEmpty {
                        Image(systemName: "tag.fill")
                            .accessibilityLabel(
                                "Has keywords"
                            )
                    }
                    if let cullingStackNumber {
                        Text("Stack \(cullingStackNumber)")
                            .accessibilityLabel(
                                "Suggested stack \(cullingStackNumber)"
                            )
                    } else if let membership =
                        expandedStackPosition {
                        Text(
                            "\(membership.position)/\(membership.photoCount)"
                        )
                        .accessibilityLabel(
                            "Photo \(membership.position) of \(membership.photoCount) in stack"
                        )
                    }
                    Spacer(minLength: 0)
                    if !asset.userState.adjustments.isNeutral {
                        Label(
                            "Edited",
                            systemImage:
                                "slider.horizontal.3"
                        )
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Edited")
                    }
                }
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
                .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
                .background(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.03),
                            .black.opacity(0.82),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .allowsHitTesting(false)
        }
    }

    /// A saved stack prints its position only on the members that do not
    /// already carry the stack button in the top-left corner.
    private var expandedStackPosition:
        CatalogPhotoStackMembership? {
        guard let stackMembership,
              !stackMembership.isCollapsed,
              !stackMembership.isTop else {
            return nil
        }
        return stackMembership
    }

    /// How far the hover cluster sits above the bottom edge: enough to clear
    /// the badge row, and no more. The row is one 10-point line inside its own
    /// xSmall padding; with no badges there is no row and no scrim to clear.
    private var quickActionBottomInset: CGFloat {
        guard hasReviewState else {
            return RAWDeskTokens.Spacing.xSmall
        }
        return RAWDeskTokens.Typography.badgeSize
            + RAWDeskTokens.Spacing.small
            + RAWDeskTokens.Spacing.xSmall
    }

    /// Every condition the badge row can draw, so the scrim never appears
    /// without a badge and no badge ever appears without the scrim.
    private var hasReviewState: Bool {
        asset.userState.flagged
            || asset.userState.rejected
            || asset.userState.rating > 0
            || asset.userState.colorLabel != .none
            || asset.userState.favorite
            || isInQuickCollection
            || isInPhotoCollection
            || !asset.userState.keywords.isEmpty
            || cullingStackNumber != nil
            || expandedStackPosition != nil
            || !asset.userState.adjustments.isNeutral
    }

    @ViewBuilder
    private var quickActionLayer: some View {
        if isHovering,
           !asset.catalogMissing,
           let onQuickPick,
           let onQuickReject,
           let onQuickRating {
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                    Button(action: onQuickPick) {
                        Image(
                            systemName:
                                asset.userState.flagged
                                ? "flag.fill"
                                : "flag"
                        )
                        .frame(width: 28, height: 28)
                    }
                    .help("Pick photo (P)")
                    .accessibilityLabel("Pick photo")

                    Button(action: onQuickReject) {
                        Image(
                            systemName:
                                asset.userState.rejected
                                ? "xmark.circle.fill"
                                : "xmark.circle"
                        )
                        .frame(width: 28, height: 28)
                    }
                    .help("Reject photo (X)")
                    .accessibilityLabel("Reject photo")

                    Menu {
                        ForEach(0...5, id: \.self) {
                            rating in
                            Button(
                                rating == 0
                                    ? "No rating"
                                    : "\(rating) "
                                        + (
                                            rating == 1
                                            ? "star"
                                            : "stars"
                                        )
                            ) {
                                onQuickRating(rating)
                            }
                        }
                    } label: {
                        Image(systemName: "star")
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("Set rating")
                    .accessibilityLabel("Set rating")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                // These glyphs sit on top of a photograph, so they need to be
                // legible against anything. Left to the button style they took
                // the accent tint, which is deliberately low-saturation and was
                // barely readable on the scrim.
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textPrimary
                )
                .padding(RAWDeskTokens.Spacing.xSmall)
                .background(
                    RAWDeskTokens.ColorToken.canvas
                        .opacity(0.86),
                    in: RoundedRectangle(
                        cornerRadius:
                            RAWDeskTokens.Radius.control
                    )
                )
                .padding(.bottom, quickActionBottomInset)
            }
        }
    }

    private var accessibilityDescription: String {
        var parts = [
            asset.filename,
            asset.format.displayName,
            "\(asset.userState.rating) of 5 stars",
            asset.userState.flagged
                ? "picked"
                : (
                    asset.userState.rejected
                        ? "rejected"
                        : "unflagged"
                ),
        ]
        if asset.catalogMissing {
            parts.append("missing original")
        }
        if !asset.userState.adjustments.isNeutral {
            parts.append("edited")
        }
        if let compareRole {
            parts.append(
                "compare \(compareRole.name.lowercased())"
            )
        }
        if let surveyRole {
            parts.append(
                "survey \(surveyRole.name.lowercased())"
            )
        }
        if let duplicateGroupNumber {
            parts.append(
                isDuplicateAnchor
                    ? "duplicate group \(duplicateGroupNumber), original catalog item"
                    : "duplicate group \(duplicateGroupNumber), exact image-data match"
            )
        }
        if isInQuickCollection {
            parts.append("in Quick Collection")
        }
        if isInPhotoCollection {
            parts.append("in a regular collection")
        }
        if let cullingEvaluation {
            parts.append(
                "culling \(cullingEvaluation.decision.name.lowercased())"
            )
            parts.append(
                contentsOf: cullingEvaluation.reasons
            )
        }
        if let cullingStackNumber {
            parts.append(
                "suggested stack \(cullingStackNumber)"
            )
        }
        if let stackMembership {
            parts.append(
                "saved stack, photo \(stackMembership.position) of \(stackMembership.photoCount), \(stackMembership.isCollapsed ? "collapsed" : "expanded")"
            )
        }
        if asset.userState.colorLabel != .none {
            let metadataName =
                asset.userState.colorLabelMetadataValue
                ?? asset.userState.colorLabel.name
            parts.append(
                "\(metadataName), \(asset.userState.colorLabel.name.lowercased()) color label"
            )
        }
        if isActive {
            parts.append("active photo")
        }
        return parts.joined(separator: ", ")
    }

    private var selectionStrokeColor: Color {
        if let compareRole {
            return compareRole == .select
                ? RAWDeskTokens.ColorToken.selection
                : RAWDeskTokens.ColorToken.textPrimary
                    .opacity(0.78)
        }
        if let surveyRole {
            return surveyRole == .active
                ? RAWDeskTokens.ColorToken.selection
                : RAWDeskTokens.ColorToken.textPrimary
                    .opacity(0.58)
        }
        return isSelected ? RAWDeskTokens.ColorToken.selection : .clear
    }

    private var selectionStrokeWidth: CGFloat {
        ThumbnailSelectionPresentation
            .strokeWidth(
                isSelected: isSelected,
                isActive: isActive,
                compareRole: compareRole,
                surveyRole: surveyRole
            )
    }

    private var cullingHelp: String {
        guard let cullingEvaluation,
              let cullingAnalysis else {
            return accessibilityDescription
        }
        return [
            "\(cullingEvaluation.decision.name): "
                + cullingEvaluation.explanation,
            cullingAnalysis.scoreSummary,
            cullingStackNumber.map {
                "Suggested Stack \($0)"
            },
            stackMembership.map {
                "Saved stack · \($0.photoCount) photos · \($0.isCollapsed ? "Collapsed" : "Expanded")"
            },
            cullingAnalysis.manualDecision == nil
                ? nil
                : "Manual override",
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func cullingBadgeText(
        _ evaluation: AssistedCullingEvaluation
    ) -> String {
        let suffix =
            cullingAnalysis?.manualDecision == nil
                ? ""
                : " · Manual"
        return evaluation.decision.name + suffix
    }

    private func cullingBadgeTone(
        _ decision: AssistedCullingDecision
    ) -> RAWBadgeTone {
        switch decision {
        case .select: return .success
        case .reject: return .destructive
        case .review: return .neutral
        }
    }

    private func stackButton(
        _ membership: CatalogPhotoStackMembership
    ) -> some View {
        Button(action: onStackToggle) {
            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                Image(
                    systemName:
                        membership.isCollapsed
                        ? "chevron.right"
                        : "chevron.down"
                )
                Text("\(membership.photoCount)")
                    .monospacedDigit()
            }
            .font(RAWDeskTokens.Typography.badge)
            .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            .background(
                RAWDeskTokens.ColorToken.selection.opacity(0.9),
                in: RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.control
                )
            )
            .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            membership.isCollapsed
                ? "Expand stack of \(membership.photoCount) photos"
                : "Collapse stack of \(membership.photoCount) photos"
        )
        .help(
            membership.isCollapsed
                ? "Expand \(membership.photoCount)-photo stack"
                : "Collapse \(membership.photoCount)-photo stack"
        )
    }

    private func load() async {
        // Whatever is already on screen stays there while a re-decode runs.
        // The thumbnail-size slider walks through a dozen pixel sizes in one
        // drag and each one is a different cache key, so restarting this task
        // used to blank every visible cell to a spinner for the whole drag.
        // Rescaling the bitmap we have is what the user expects to see; the
        // sharper decode replaces it when it lands.
        if image == nil {
            loadState = .loading
            rawDecodeSource = nil
        }
        let outcome = await loader.load(
            asset: asset,
            kind: .thumbnail(target: pixelSize)
        )
        guard !Task.isCancelled else { return }
        let displayedImage: NSImage?
        if let base = outcome.image,
           !asset.userState.adjustments.isNeutral {
            displayedImage =
                await PhotoRenderQueue.thumbnails.render(
                    image: base,
                    adjustments:
                        asset.userState.adjustments
                )
        } else {
            displayedImage = outcome.image
        }
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard !Task.isCancelled else { return }
            // Assigned even when nil: a reload that fails must drop the stale
            // bitmap, or the failure state would sit behind a stale image.
            self.image = displayedImage
            self.loadState = outcome.state
            self.rawDecodeSource =
                outcome.rawDecodeSource
            // A successful grid-only thumbnail does not change filtering,
            // sorting, or catalog state. Avoid publishing one mutation per
            // visible cell across the entire Library. Decoder and failure
            // details still propagate when they carry user-facing meaning.
            if outcome.rawDecodeSource != nil
                || outcome.state != .loaded {
                self.onLoadStateChange(
                    outcome.state,
                    outcome.rawDecodeSource
                )
            }
        }
    }
}
