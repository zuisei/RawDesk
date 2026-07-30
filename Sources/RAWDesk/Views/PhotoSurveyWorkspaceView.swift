import SwiftUI
import AppKit

struct PhotoSurveyWorkspaceView: View {
    @ObservedObject var library: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            surveyToolbar
            Divider()
            SurveyMosaicView(library: library)
        }
        .background(RAWDeskTokens.ColorToken.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Photo survey workspace")
    }

    private var surveyToolbar: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(
                "Survey — \(library.surveyAssets.count) photos",
                systemImage: "rectangle.3.group"
            )
                .font(RAWDeskTokens.Typography.workspaceHeader)

            Spacer(minLength: 12)

            Button {
                library.moveSurveyActive(direction: -1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Previous Active Photo (←)")
            .accessibilityIdentifier("Previous survey photo")

            Button {
                library.moveSurveyActive(direction: 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .rawIconButtonTarget()
            .help("Next Active Photo (→)")
            .accessibilityIdentifier("Next survey photo")

            Divider().frame(height: 18)

            Button {
                library.startCompare()
            } label: {
                Label(
                    "Compare",
                    systemImage: "rectangle.split.2x1"
                )
            }
            .help("Compare the Active photo with another selection")
            .accessibilityIdentifier("Survey to compare")

            Button {
                library.keepOnlyActiveSurveyPhoto()
            } label: {
                Label(
                    "Keep Active",
                    systemImage: "scope"
                )
            }
            .help("Leave Survey with only the Active photo selected")
            .accessibilityIdentifier("Keep active survey photo")

            Button("Done") {
                library.endSurvey()
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .controlSize(.small)
            .accessibilityIdentifier("Finish photo survey")
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.medium)
        .padding(.vertical, RAWDeskTokens.Spacing.small)
        .frame(
            minHeight:
                RAWDeskTokens.Size
                    .workspaceControlBar
        )
        .background(RAWDeskTokens.ColorToken.chrome)
    }
}

struct PhotoSurveyLayoutMetrics: Equatable {
    var columns: Int
    var rows: Int
    var cellWidth: CGFloat
    var cellHeight: CGFloat
}

enum PhotoSurveyLayoutPlanner {
    static let spacing =
        RAWDeskTokens.Spacing.small
    static let padding =
        RAWDeskTokens.Spacing.medium
    static let minimumCellWidth: CGFloat = 210
    static let minimumCellHeight: CGFloat = 176

    static func metrics(
        photoCount: Int,
        width: CGFloat,
        height: CGFloat
    ) -> PhotoSurveyLayoutMetrics {
        guard photoCount > 0 else {
            return PhotoSurveyLayoutMetrics(
                columns: 1,
                rows: 0,
                cellWidth: max(0, width - padding * 2),
                cellHeight: 0
            )
        }
        let desiredColumns: Int
        switch photoCount {
        case 1: desiredColumns = 1
        case 2...4: desiredColumns = 2
        case 5...9: desiredColumns = 3
        case 10...16: desiredColumns = 4
        default:
            desiredColumns = min(
                6,
                Int(ceil(sqrt(Double(photoCount))))
            )
        }
        let usableWidth = max(1, width - padding * 2)
        let widthLimitedColumns = max(
            1,
            Int(
                (usableWidth + spacing)
                    / (minimumCellWidth + spacing)
            )
        )
        let columns = min(
            photoCount,
            max(1, min(desiredColumns, widthLimitedColumns))
        )
        let rows = Int(
            ceil(Double(photoCount) / Double(columns))
        )
        let cellWidth =
            (usableWidth - spacing * CGFloat(columns - 1))
            / CGFloat(columns)
        let usableHeight = max(1, height - padding * 2)
        let fittedHeight =
            (usableHeight - spacing * CGFloat(rows - 1))
            / CGFloat(rows)
        return PhotoSurveyLayoutMetrics(
            columns: columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: max(minimumCellHeight, fittedHeight)
        )
    }
}

private struct SurveyMosaicView: View {
    @ObservedObject var library: LibraryViewModel

    var body: some View {
        GeometryReader { proxy in
            let assets = library.surveyAssets
            let metrics = PhotoSurveyLayoutPlanner.metrics(
                photoCount: assets.count,
                width: proxy.size.width,
                height: proxy.size.height
            )
            let rows = assets.chunked(
                into: metrics.columns
            )

            ScrollView {
                LazyVStack(spacing: PhotoSurveyLayoutPlanner.spacing) {
                    ForEach(
                        Array(rows.enumerated()),
                        id: \.offset
                    ) { _, row in
                        HStack(
                            spacing:
                                PhotoSurveyLayoutPlanner.spacing
                        ) {
                            ForEach(row) { asset in
                                SurveyPhotoTile(
                                    asset: asset,
                                    isActive:
                                        library.surveyState?
                                            .activeID == asset.id,
                                    library: library
                                )
                                .frame(
                                    width: metrics.cellWidth,
                                    height: metrics.cellHeight
                                )
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .center
                        )
                    }
                }
                .padding(PhotoSurveyLayoutPlanner.padding)
            }
        }
    }
}

private struct SurveyPhotoTile: View {
    let asset: PhotoAsset
    let isActive: Bool
    @ObservedObject var library: LibraryViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var image: NSImage?
    @State private var loadState: ImageLoadState = .idle
    @State private var isHovering = false

    private let loader = ImageLoader.shared
    private var loadID: String {
        "\(asset.id)|\(asset.userState.adjustments.hashValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            tileHeader
            Divider()
            preview
            Divider()
            reviewControls
        }
        .background(RAWDeskTokens.ColorToken.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.group
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.group
            )
                .strokeBorder(
                    isActive
                        ? RAWDeskTokens.ColorToken.selection
                        : RAWDeskTokens.ColorToken.textPrimary.opacity(0.22),
                    lineWidth: isActive ? 3 : 1
                )
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.group))
        .onTapGesture {
            library.setSurveyActive(asset.id)
        }
        .onHover { isHovering = $0 }
        .task(id: loadID) {
            await load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            isActive
                ? "Active survey photo"
                : "Selected survey photo"
        )
        .accessibilityLabel(
            Text(
                "\(isActive ? "Active" : "Survey") photo, \(asset.filename)"
            )
        )
    }

    private var tileHeader: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Label(
                isActive ? "Active" : "Selected",
                systemImage: isActive
                    ? "scope"
                    : "rectangle.3.group"
            )
            .font(RAWDeskTokens.Typography.sectionHeader)
            .foregroundStyle(
                isActive
                    ? RAWDeskTokens.ColorToken.selection
                    : RAWDeskTokens.ColorToken
                        .textSecondary
            )
            Text(asset.filename)
                .font(RAWDeskTokens.Typography.control)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(asset.format.displayName)
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            Button {
                library.removeSurveyPhoto(asset.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .rawIconButtonTarget()
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            .opacity(isHovering || isActive ? 1 : 0.5)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.12),
                value: isHovering
            )
            .help("Remove \(asset.filename) from Survey")
            .accessibilityLabel(
                Text("Remove \(asset.filename) from Survey")
            )
        }
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    private var preview: some View {
        ZStack {
            RAWDeskTokens.ColorToken.canvas
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(RAWDeskTokens.Spacing.xSmall)
            } else {
                switch loadState {
                case .idle, .loading:
                    ProgressView("Loading…")
                        .controlSize(.small)
                case .failed(let reason):
                    ErrorPlaceholderView(
                        kind: .failed(reason)
                    )
                case .unsupported(let reason):
                    ErrorPlaceholderView(
                        kind: .unsupported(reason)
                    )
                case .loaded:
                    ErrorPlaceholderView(
                        kind: .failed("Image data missing.")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var reviewControls: some View {
        RAWReviewControls(
            library: library,
            asset: asset,
            compact: true
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, RAWDeskTokens.Spacing.small)
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .background(RAWDeskTokens.ColorToken.chrome)
    }

    private func load() async {
        image = nil
        loadState = .loading
        library.updateLoadOutcome(
            .loading,
            rawDecodeSource: nil,
            for: asset.id
        )
        let outcome = await loader.load(
            asset: asset,
            kind: .preview(target: 1_600)
        )
        guard !Task.isCancelled else { return }
        let displayedImage: NSImage?
        if let base = outcome.image,
           !asset.userState.adjustments.isNeutral {
            displayedImage =
                await PhotoRenderQueue.thumbnails.render(
                    image: base,
                    adjustments: asset.userState.adjustments
                )
        } else {
            displayedImage = outcome.image
        }
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard !Task.isCancelled else { return }
            image = displayedImage
            loadState = outcome.state
            library.updateLoadOutcome(
                outcome.state,
                rawDecodeSource:
                    outcome.rawDecodeSource,
                for: asset.id
            )
        }
    }
}

struct PhotoSurveyFilmstripView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let cellWidth: CGFloat = 112

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: RAWDeskTokens.Spacing.small) {
                    ForEach(library.filtered) { asset in
                        ThumbnailCellView(
                            asset: asset,
                            isSelected:
                                library.selectedIDs.contains(asset.id),
                            isActive:
                                library.selectionID == asset.id,
                            compareRole: nil,
                            surveyRole:
                                library.surveyRole(for: asset.id),
                            pixelSize: cellWidth * 2,
                            duplicateGroupNumber:
                                library.duplicateGroupNumber(
                                    for: asset.id
                                ),
                            isDuplicateAnchor:
                                library.isDuplicateAnchor(asset.id),
                            isInQuickCollection:
                                library.isInQuickCollection(asset.id),
                            isInPhotoCollection:
                                library.isInAnyPhotoCollection(
                                    asset.id
                                ),
                            cullingEvaluation:
                                library.cullingEvaluation(for: asset.id),
                            cullingAnalysis:
                                library.cullingAnalysis(for: asset.id),
                            cullingStackNumber:
                                library.cullingStackNumber(
                                    for: asset.id
                                ),
                            stackMembership:
                                library.catalogCollection
                                    == .exactDuplicates
                                    ? nil
                                    : library.photoStackMembership(
                                        for: asset.id
                                    ),
                            onStackToggle: {
                                library.togglePhotoStack(
                                    containing: asset.id
                                )
                            },
                            onLoadStateChange: {
                                state,
                                rawDecodeSource in
                                library.updateLoadOutcome(
                                    state,
                                    rawDecodeSource:
                                        rawDecodeSource,
                                    for: asset.id
                                )
                            }
                        )
                        .frame(
                            width: cellWidth,
                            height: cellWidth + 22
                        )
                        .contentShape(Rectangle())
                        .id(asset.id)
                        .onTapGesture {
                            library.addSurveyPhoto(asset.id)
                        }
                    }
                }
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            }
            .background(RAWDeskTokens.ColorToken.chrome)
            .onAppear {
                scrollToActive(
                    library.surveyState?.activeID,
                    proxy: proxy,
                    animated: false
                )
            }
            .onChange(
                of: library.surveyState?.activeID
            ) { _, id in
                scrollToActive(
                    id,
                    proxy: proxy,
                    animated: !reduceMotion
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Survey filmstrip")
    }

    private func scrollToActive(
        _ id: PhotoAsset.ID?,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let id else { return }
        if animated {
            withAnimation(.snappy(duration: 0.22)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
