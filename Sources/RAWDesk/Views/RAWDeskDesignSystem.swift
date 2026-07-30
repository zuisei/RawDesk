import SwiftUI
import AppKit

enum RAWDeskTokens {
    enum ColorToken {
        /// The image well. Deliberately the darkest surface in the app so a
        /// photograph reads as the brightest object on screen. Kept clearly
        /// below `panel` rather than a few steps below it.
        static let canvas = Color(
            red: 10 / 255,
            green: 11 / 255,
            blue: 12 / 255
        )
        static let chrome = Color(
            red: 26 / 255,
            green: 28 / 255,
            blue: 31 / 255
        )
        static let panel = Color(
            red: 32 / 255,
            green: 35 / 255,
            blue: 40 / 255
        )
        static let controlElevated = Color(
            red: 42 / 255,
            green: 46 / 255,
            blue: 52 / 255
        )
        static let textPrimary = Color(
            red: 241 / 255,
            green: 243 / 255,
            blue: 245 / 255
        )
        static let textSecondary = Color(
            red: 169 / 255,
            green: 176 / 255,
            blue: 186 / 255
        )
        static let divider = Color.white.opacity(0.12)

        /// A fixed, low-saturation blue rather than the system accent.
        /// Two reasons: the photograph must stay the only saturated object on
        /// screen, and a user-chosen system accent would otherwise repaint the
        /// whole interface an arbitrary hue.
        static let selection = Color(
            red: 92 / 255,
            green: 124 / 255,
            blue: 168 / 255
        )

        /// Slider chrome. Neutral by default; `selection` appears only on the
        /// control the user is actually operating.
        static let sliderTrack = Color(
            red: 58 / 255,
            green: 63 / 255,
            blue: 70 / 255
        )
        static let sliderFill = Color(
            red: 139 / 255,
            green: 147 / 255,
            blue: 160 / 255
        )
        static let sliderKnob = Color(
            red: 200 / 255,
            green: 205 / 255,
            blue: 212 / 255
        )
        /// The tick marking a bipolar slider's origin.
        static let sliderOrigin = Color(
            red: 78 / 255,
            green: 84 / 255,
            blue: 92 / 255
        )

        /// Star ratings. A muted gold rather than a pure yellow, so a rated
        /// photo reads clearly without shouting over the thumbnail.
        static let ratingStar = Color(
            red: 201 / 255,
            green: 162 / 255,
            blue: 39 / 255
        )
        /// Unfilled stars: visible enough to show the control's extent.
        static let ratingStarEmpty = Color(
            red: 78 / 255,
            green: 84 / 255,
            blue: 92 / 255
        )
        static let warning = Color(
            nsColor: .systemOrange
        )
        static let destructive = Color(
            nsColor: .systemRed
        )
        static let success = Color(
            nsColor: .systemGreen
        )

        static let canvasNS = NSColor(canvas)
        static let chromeNS = NSColor(chrome)
        static let panelNS = NSColor(panel)
        static let controlElevatedNS =
            NSColor(controlElevated)
        static let textPrimaryNS = NSColor(textPrimary)
        static let textSecondaryNS =
            NSColor(textSecondary)
        static let dividerNS =
            NSColor.white.withAlphaComponent(0.12)
        static let selectionNS = NSColor(selection)
        static let warningNS = NSColor.systemOrange
        static let destructiveNS = NSColor.systemRed
        static let successNS = NSColor.systemGreen

        /// Dynamic color sampled from a photo. This is image content, not
        /// interface chrome, so it intentionally sits outside the fixed
        /// semantic palette.
        static func imageSample(
            red: Double,
            green: Double,
            blue: Double
        ) -> Color {
            Color(
                red: red,
                green: green,
                blue: blue
            )
        }
    }

    enum Spacing {
        /// Hairline gap between adjacent glyphs in a single control — the
        /// stars of a rating, the swatches of a colour label — where xSmall
        /// would read as separate controls rather than one.
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }

    enum Size {
        static let toolbarHeight: CGFloat = 48
        static let leftSidebar: CGFloat = 240
        static let leftSidebarMinimum: CGFloat = 220
        static let leftSidebarMaximum: CGFloat = 280
        static let leftSidebarRange =
            leftSidebarMinimum...leftSidebarMaximum
        static let rightInspector: CGFloat = 320
        static let rightInspectorCompact: CGFloat = 300
        static let rightInspectorMaximum: CGFloat = 380
        static let rightInspectorRange =
            rightInspectorCompact...rightInspectorMaximum
        static let developFilmstrip: CGFloat = 136
        static let developFilmstripMinimum: CGFloat = 120
        static let developFilmstripMaximum: CGFloat = 168
        static let developFilmstripRange =
            developFilmstripMinimum...developFilmstripMaximum
        static let libraryFilmstrip: CGFloat = 128
        static let libraryFilmstripMinimum: CGFloat = 112
        static let libraryFilmstripMaximum: CGFloat = 156
        static let libraryFilmstripRange =
            libraryFilmstripMinimum...libraryFilmstripMaximum
        static let toolRail: CGFloat = 40
        static let iconTarget: CGFloat = 28
        static let primaryButtonHeight: CGFloat = 34
        static let inspectorRow: CGFloat = 30
        static let workspaceControlBar: CGFloat = 36
        static let canvasStatusBar: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 6
        static let group: CGFloat = 8
        static let modal: CGFloat = 12
    }

    enum Typography {
        static let modalTitleSize: CGFloat = 18
        static let workspaceHeaderSize: CGFloat = 14
        static let sectionHeaderSize: CGFloat = 12
        static let controlSize: CGFloat = 13
        static let metadataSize: CGFloat = 11
        static let numericSize: CGFloat = 12
        static let badgeSize: CGFloat = 10

        static let modalTitle = Font.system(
            size: modalTitleSize,
            weight: .semibold
        )
        static let workspaceHeader = Font.system(
            size: workspaceHeaderSize,
            weight: .semibold
        )
        static let sectionHeader = Font.system(
            size: sectionHeaderSize,
            weight: .semibold
        )
        static let control = Font.system(
            size: controlSize,
            weight: .regular
        )
        static let metadata = Font.system(
            size: metadataSize,
            weight: .regular
        )
        static let numeric = Font.system(
            size: numericSize,
            weight: .regular,
            design: .monospaced
        )
        static let badge = Font.system(
            size: badgeSize,
            weight: .medium
        )

        static let controlNS = NSFont.systemFont(
            ofSize: controlSize,
            weight: .regular
        )
        static let metadataNS = NSFont.systemFont(
            ofSize: metadataSize,
            weight: .regular
        )
        static let badgeNS = NSFont.systemFont(
            ofSize: badgeSize,
            weight: .medium
        )
    }
}

struct RAWPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RAWDeskTokens.ColorToken.panel)
            .foregroundStyle(RAWDeskTokens.ColorToken.textPrimary)
    }
}

/// Shared collapsible navigation section used by workspace sidebars. Expansion
/// state is owned by the caller so it can be persisted with AppStorage.
struct RAWSidebarSection<
    Content: View,
    Trailing: View
>: View {
    let title: String
    let count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        count: Int? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content:
            @escaping () -> Content,
        @ViewBuilder trailing:
            @escaping () -> Trailing
    ) {
        self.title = title
        self.count = count.map {
            max($0, 0)
        }
        _isExpanded = isExpanded
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        Section {
            if isExpanded {
                content()
            }
        } header: {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(
                        spacing:
                            RAWDeskTokens.Spacing.xSmall
                    ) {
                        Image(
                            systemName:
                                isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(
                            RAWDeskTokens.Typography.badge
                        )
                        Text(title)
                            .font(
                                RAWDeskTokens.Typography
                                    .sectionHeader
                            )
                        Spacer(minLength: 0)
                        if let count,
                           count > 0 {
                            Text("\(count)")
                                .font(
                                    RAWDeskTokens.Typography
                                        .metadata
                                )
                                .foregroundStyle(
                                    RAWDeskTokens.ColorToken
                                        .textSecondary
                                )
                                .monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(
                    "\(isExpanded ? "Collapse" : "Expand") \(title)"
                )
                .accessibilityValue(
                    count.map {
                        $0 > 0
                            ? "\($0) items"
                            : "No items"
                    } ?? ""
                )

                trailing()
            }
        }
    }
}

extension RAWSidebarSection where Trailing == EmptyView {
    init(
        _ title: String,
        count: Int? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content:
            @escaping () -> Content
    ) {
        self.init(
            title,
            count: count,
            isExpanded: isExpanded,
            content: content
        ) {
            EmptyView()
        }
    }
}

/// Applies the shared 30-point Inspector row rhythm without dictating the
/// row's controls or text layout.
struct RAWInspectorRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(
                minHeight:
                    RAWDeskTokens.Size.inspectorRow
            )
    }
}

extension View {
    func rawPanelBackground() -> some View {
        modifier(RAWPanelBackground())
    }

    func rawIconButtonTarget() -> some View {
        frame(
            minWidth: RAWDeskTokens.Size.iconTarget,
            minHeight: RAWDeskTokens.Size.iconTarget
        )
        .contentShape(Rectangle())
    }

    func rawSliderTarget() -> some View {
        frame(
            minHeight: RAWDeskTokens.Size.iconTarget
        )
        .contentShape(Rectangle())
    }

    /// Secondary text actions in the inspectors — Reset, Reset All, and the
    /// like. macOS's `.link` style paints these the accent colour with web
    /// semantics, which scattered what looked like hyperlinks down the panel.
    /// They are quiet labels that the surrounding row already gives context to.
    func rawSecondaryTextAction() -> some View {
        buttonStyle(.plain)
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )
    }

    func rawPrimaryButtonHeight() -> some View {
        frame(
            minHeight:
                RAWDeskTokens.Size.primaryButtonHeight
        )
    }

    func rawPanelScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(RAWDeskTokens.ColorToken.panel)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textPrimary
            )
    }

    func rawNumericField(
        width: CGFloat? = nil
    ) -> some View {
        textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .font(RAWDeskTokens.Typography.numeric)
            .monospacedDigit()
            .frame(width: width)
    }
}

enum RAWResizeAxis {
    case horizontal
    case vertical
}

enum RAWDeskResponsiveLayout {
    static let splitHandleWidth: CGFloat = 6

    static func minimumCenterWidth(
        for windowWidth: CGFloat
    ) -> CGFloat {
        windowWidth < 1200 ? 480 : 560
    }

    static func sidebarWidthRange(
        for windowWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        if windowWidth < 1440 {
            return RAWDeskTokens.Size.leftSidebarMinimum...RAWDeskTokens.Size.leftSidebar
        }
        return RAWDeskTokens.Size.leftSidebarRange
    }

    static func inspectorWidthRange(
        for windowWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        if windowWidth < 1200 {
            return RAWDeskTokens.Size.rightInspectorCompact...RAWDeskTokens.Size.rightInspector
        }
        if windowWidth < 1440 {
            return RAWDeskTokens.Size.rightInspectorCompact...RAWDeskTokens.Size.rightInspector
        }
        return RAWDeskTokens.Size.rightInspectorRange
    }

    static func guaranteedCenterWidth(
        for windowWidth: CGFloat,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = true
    ) -> CGFloat {
        let sidebar =
            sidebarVisible
            ? sidebarWidthRange(for: windowWidth)
                .upperBound
                + splitHandleWidth
            : 0
        let inspector =
            inspectorVisible
            ? inspectorWidthRange(for: windowWidth)
                .upperBound
                + splitHandleWidth
            : 0
        return windowWidth - sidebar - inspector
    }
}

/// A persistent split handle with a larger interaction target than its
/// one-pixel visual divider. Horizontal movement changes panel width; vertical
/// movement changes filmstrip height.
struct RAWResizableDivider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let axis: RAWResizeAxis
    let dragMultiplier: CGFloat
    let label: String

    @State private var dragStartValue: CGFloat?

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(
                    width: axis == .horizontal ? 1 : nil,
                    height: axis == .vertical ? 1 : nil
                )
        }
        .frame(
            width:
                axis == .horizontal
                ? RAWDeskResponsiveLayout
                    .splitHandleWidth
                : nil,
            height:
                axis == .vertical
                ? RAWDeskResponsiveLayout
                    .splitHandleWidth
                : nil
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if dragStartValue == nil {
                        dragStartValue = value
                    }
                    let translation =
                        axis == .horizontal
                        ? gesture.translation.width
                        : gesture.translation.height
                    let start = dragStartValue ?? value
                    value = clamped(
                        start + (translation * dragMultiplier)
                    )
                }
                .onEnded { _ in
                    dragStartValue = nil
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = clamped(value + 8)
            case .decrement:
                value = clamped(value - 8)
            @unknown default:
                break
            }
        }
    }

    private func clamped(_ candidate: CGFloat) -> CGFloat {
        min(
            range.upperBound,
            max(range.lowerBound, candidate)
        )
    }
}

enum RAWBadgeTone: Equatable {
    case neutral
    case accent
    case warning
    case destructive
    case success

    var foreground: Color {
        switch self {
        case .neutral:
            return RAWDeskTokens.ColorToken.textSecondary
        case .accent, .warning, .destructive, .success:
            return .white
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            return RAWDeskTokens.ColorToken.controlElevated
        case .accent:
            return RAWDeskTokens.ColorToken.selection
        case .warning:
            return RAWDeskTokens.ColorToken.warning
        case .destructive:
            return RAWDeskTokens.ColorToken.destructive
        case .success:
            return RAWDeskTokens.ColorToken.success
        }
    }
}

struct RAWStateBadge: View {
    let text: String
    var systemImage: String?
    var tone: RAWBadgeTone = .neutral

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(RAWDeskTokens.Typography.badge)
        .padding(.horizontal, RAWDeskTokens.Spacing.xSmall)
        .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
        .foregroundStyle(tone.foreground)
        .background(
            tone.background.opacity(tone == .neutral ? 1 : 0.9),
            in: RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.control
            )
        )
        .accessibilityElement(children: .combine)
    }
}

struct RAWFormatBadgePresentation: Equatable {
    let text: String
    let systemImage: String?
    let tone: RAWBadgeTone

    init(
        asset: PhotoAsset,
        loadState: ImageLoadState? = nil,
        rawDecodeSource:
            RAWImageLoader.DecodeSource? = nil
    ) {
        let state = loadState ?? asset.loadState
        let source =
            rawDecodeSource
            ?? asset.rawDecodeSource
        let usesPreview =
            source == .embeddedPreview
            || source == .quickLook

        if asset.catalogMissing {
            text = "Missing"
            systemImage =
                "exclamationmark.triangle.fill"
            tone = .warning
        } else if case .failed = state {
            text = "Unreadable"
            systemImage =
                "exclamationmark.triangle.fill"
            tone = .destructive
        } else if usesPreview {
            text =
                asset.format.shortBadgeName
                + " · Preview"
            systemImage = nil
            tone = .warning
        } else if case .unsupported = state {
            text =
                asset.format.shortBadgeName
                + " · Preview"
            systemImage = nil
            tone = .warning
        } else {
            text = asset.format.shortBadgeName
            systemImage = nil
            tone = .neutral
        }
    }
}

struct RAWFormatBadge: View {
    let asset: PhotoAsset
    var loadState: ImageLoadState?
    var rawDecodeSource:
        RAWImageLoader.DecodeSource? = nil

    private var presentation:
        RAWFormatBadgePresentation {
        RAWFormatBadgePresentation(
            asset: asset,
            loadState: loadState,
            rawDecodeSource: rawDecodeSource
        )
    }

    var body: some View {
        RAWStateBadge(
            text: presentation.text,
            systemImage:
                presentation.systemImage,
            tone: presentation.tone
        )
    }
}

enum RAWEmptyStateLayout {
    case full
    case compact
}

enum RAWEmptyStateIndicator {
    case symbol(String)
    case progress
}

/// Shared presentation for zero-result, filtered, loading, missing, and
/// analysis-pending states. Callers own the state-specific copy and actions.
struct RAWEmptyState<Actions: View>: View {
    let title: String
    let indicator: RAWEmptyStateIndicator
    let message: String
    var layout: RAWEmptyStateLayout = .full

    private let actions: Actions

    init(
        title: String,
        systemImage: String,
        message: String,
        layout: RAWEmptyStateLayout = .full,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        indicator = .symbol(systemImage)
        self.message = message
        self.layout = layout
        self.actions = actions()
    }

    init(
        title: String,
        indicator: RAWEmptyStateIndicator,
        message: String,
        layout: RAWEmptyStateLayout = .full,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.indicator = indicator
        self.message = message
        self.layout = layout
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: RAWDeskTokens.Spacing.medium) {
            indicatorView

            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                Text(title)
                    .font(
                        RAWDeskTokens.Typography.workspaceHeader
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.textPrimary
                    )
                if !message.isEmpty {
                    Text(message)
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken.textSecondary
                        )
                }
            }

            actions
        }
        .multilineTextAlignment(.center)
        .padding(
            layout == .full
                ? RAWDeskTokens.Spacing.xLarge
                : RAWDeskTokens.Spacing.large
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: layout == .full ? .infinity : nil
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .symbol(let systemImage):
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .accessibilityHidden(true)
        case .progress:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel(Text(title))
        }
    }
}

extension RAWEmptyState where Actions == EmptyView {
    init(
        title: String,
        systemImage: String,
        message: String,
        layout: RAWEmptyStateLayout = .full
    ) {
        self.title = title
        indicator = .symbol(systemImage)
        self.message = message
        self.layout = layout
        actions = EmptyView()
    }

    init(
        title: String,
        indicator: RAWEmptyStateIndicator,
        message: String,
        layout: RAWEmptyStateLayout = .full
    ) {
        self.title = title
        self.indicator = indicator
        self.message = message
        self.layout = layout
        actions = EmptyView()
    }
}

private extension FileFormat {
    var shortBadgeName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .sonyARW: return "ARW"
        case .canonCR2: return "CR2"
        case .canonCR3: return "CR3"
        case .dng: return "DNG"
        case .nikonNEF: return "NEF"
        case .fujiRAF: return "RAF"
        case .panasonicRW2: return "RW2"
        case .olympusORF: return "ORF"
        case .unknownRaw: return "RAW"
        case .unsupported: return "Preview"
        }
    }
}

struct RAWProgressBanner<Actions: View>: View {
    let title: String
    var fraction: Double?
    let accessibilityLabel: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.medium) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                if let fraction {
                    ProgressView(
                        value:
                            min(max(fraction, 0), 1)
                    )
                    .frame(width: 56)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(title)
                    .font(
                        RAWDeskTokens.Typography.control
                    )
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(
                fraction.map {
                    "\(Int((min(max($0, 0), 1) * 100).rounded())) percent"
                } ?? "In progress"
            )

            Spacer(minLength: RAWDeskTokens.Spacing.small)
            actions()
        }
    }
}

struct RAWPrimaryFooterBar<
    Summary: View,
    Actions: View
>: View {
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.medium) {
            summary()
                .lineLimit(1)
            Spacer(minLength: RAWDeskTokens.Spacing.small)
            actions()
        }
        .padding(
            .horizontal,
            RAWDeskTokens.Spacing.large
        )
        .frame(minHeight: 68)
    }
}

struct RAWPreflightSummary<Details: View>: View {
    let summary: String
    let isAvailable: Bool
    @Binding var isPresented: Bool
    @ViewBuilder let details: () -> Details

    var body: some View {
        Button {
            guard isAvailable else { return }
            isPresented.toggle()
        } label: {
            HStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                Text(summary)
                    .font(
                        RAWDeskTokens.Typography.control
                    )
                    .monospacedDigit()
                if isAvailable {
                    Image(systemName: "info.circle")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(
            isAvailable
                ? "Show unavailable files, copy size, XMP companions, naming checks, and warnings."
                : "Analyze sources to see preflight details."
        )
        .popover(isPresented: $isPresented) {
            details()
        }
    }
}

struct RAWWorkspaceModeHeader: View {
    let title: String
    var detail: String?
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Text(title)
                .font(RAWDeskTokens.Typography.workspaceHeader)
            if let detail {
                Text(detail)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.textSecondary
                    )
            }
            Spacer(minLength: RAWDeskTokens.Spacing.small)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .frame(height: RAWDeskTokens.Size.workspaceControlBar)
        .padding(.horizontal, RAWDeskTokens.Spacing.medium)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct RAWToolRailButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    /// A short caption shown under the icon. Supplying it switches the button
    /// to the labelled form used by the Develop inspector's tool row; without
    /// it the button stays icon-only.
    var caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let caption {
                    VStack(
                        spacing: RAWDeskTokens.Spacing.xSmall
                    ) {
                        Image(systemName: systemImage)
                            .imageScale(.medium)
                        Text(caption)
                            .font(
                                RAWDeskTokens.Typography
                                    .badge
                            )
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(
                        .vertical,
                        RAWDeskTokens.Spacing.xSmall
                    )
                } else {
                    Image(systemName: systemImage)
                        .frame(
                            width:
                                RAWDeskTokens.Size.toolRail,
                            height:
                                RAWDeskTokens.Size.toolRail
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isSelected
                ? RAWDeskTokens.ColorToken.textPrimary
                : RAWDeskTokens.ColorToken.textSecondary
        )
        // Labelled form marks selection with a brightness step plus a thin
        // indicator rather than a saturated fill.
        .background(
            selectionBackground,
            in: RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.control
            )
        )
        .overlay(alignment: .bottom) {
            if isSelected, caption != nil {
                Rectangle()
                    .fill(
                        RAWDeskTokens.ColorToken.selection
                    )
                    .frame(height: 2)
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
        .disabled(!isEnabled)
    }

    private var selectionBackground: Color {
        guard isSelected else { return .clear }
        return caption == nil
            ? RAWDeskTokens.ColorToken.selection
            : RAWDeskTokens.ColorToken.controlElevated
    }
}

struct RAWInspectorSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var isResetDisabled = false
    var onReset: (() -> Void)?
    var onSolo: (() -> Void)?
    var onActivate: (() -> Void)?
    var sectionEnabled: Binding<Bool>?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Button {
                    if NSEvent.modifierFlags.contains(.option),
                       let onSolo {
                        onSolo()
                        onActivate?()
                    } else {
                        if !isExpanded {
                            onActivate?()
                        }
                        setExpanded(!isExpanded)
                    }
                } label: {
                    HStack(spacing: RAWDeskTokens.Spacing.small) {
                        Image(
                            systemName:
                                isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                        Text(title)
                            .font(
                                RAWDeskTokens.Typography.sectionHeader
                            )
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    "Show or hide \(title). Option-click to show only this section."
                )

                if let sectionEnabled {
                    Toggle(
                        "Enable \(title)",
                        isOn: sectionEnabled
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .frame(
                        minWidth: RAWDeskTokens.Size.iconTarget,
                        minHeight: RAWDeskTokens.Size.iconTarget
                    )
                    .help(
                        sectionEnabled.wrappedValue
                            ? "Temporarily disable \(title) without losing its settings."
                            : "Enable \(title) and restore its saved settings."
                    )
                }

                // Only offered when there is something to reset. A greyed
                // "Reset" on every untouched section — including collapsed
                // ones — was five pieces of dead chrome in the panel, and
                // rendering it in the accent colour made a column of what
                // looked like links down the right edge.
                if let onReset, !isResetDisabled {
                    Button("Reset", action: onReset)
                        .buttonStyle(.plain)
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                        .help("Reset \(title)")
                }
            }
            .frame(minHeight: RAWDeskTokens.Size.inspectorRow)
            .padding(.horizontal, RAWDeskTokens.Spacing.medium)

            if isExpanded {
                VStack(
                    alignment: .leading,
                    spacing: RAWDeskTokens.Spacing.small
                ) {
                    content()
                }
                .disabled(sectionEnabled?.wrappedValue == false)
                .padding(.horizontal, RAWDeskTokens.Spacing.medium)
                .padding(.bottom, RAWDeskTokens.Spacing.medium)
                .transition(
                    reduceMotion
                        ? .identity
                        : .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .background(RAWDeskTokens.ColorToken.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
    }

    private func setExpanded(_ value: Bool) {
        if reduceMotion {
            isExpanded = value
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded = value
            }
        }
    }
}

struct RAWSliderPresentation: Equatable {
    let fieldPlaceholder: String
    let accessibilityValue: String
    let usesNeutralTint: Bool
    let showsMixedMarker: Bool

    init(
        value: Double,
        isMixed: Bool,
        isFieldFocused: Bool = false,
        isSliderActive: Bool = false,
        format: (Double) -> String
    ) {
        let formatted = format(value)
        showsMixedMarker =
            isMixed && !isFieldFocused
        fieldPlaceholder =
            showsMixedMarker ? "—" : formatted
        accessibilityValue =
            showsMixedMarker
                ? "Mixed values"
                : formatted
        // Neutral is the resting state. The accent is reserved for the one
        // slider the user is currently operating, so a panel of twelve
        // sliders does not compete with the photograph for attention.
        // A mixed slider is never accented, even while focused, because its
        // fill does not represent a single real value.
        usesNeutralTint = !isSliderActive || isMixed
    }
}

/// Bipolar slider track. The fill grows from the parameter's origin
/// (`resetValue`) rather than from the range minimum, so a glance shows which
/// direction a value was pushed and by how much; a tick marks the origin. The
/// native `Slider` sits invisibly on top of this and keeps all interaction,
/// keyboard adjustment, and accessibility.
private struct RAWSliderTrack: View {
    let value: Double
    let range: ClosedRange<Double>
    let origin: Double
    let usesNeutralTint: Bool
    let showsMixedMarker: Bool

    // A develop slider is this app's primary instrument, so it is sized to be
    // grabbed and read, not to be visually minimal. The earlier 3pt track and
    // 11pt knob looked tidy and felt like a preferences pane.
    private let knobDiameter: CGFloat = 14
    private let trackHeight: CGFloat = 5
    /// Tall enough to completely cover the native slider underneath, including
    /// its thumb. The native control stays fully opaque and interactive; this
    /// layer is what the user actually sees.
    private let coverHeight: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let travel = max(
                proxy.size.width - knobDiameter,
                1
            )
            let span = range.upperBound - range.lowerBound
            let valueX = knobDiameter / 2
                + travel * fraction(of: value, span: span)
            let originX = knobDiameter / 2
                + travel * fraction(of: origin, span: span)

            ZStack(alignment: .leading) {
                // Opaque, so the native slider beneath is not visible through
                // it. Without this the stock track and thumb show through.
                Rectangle()
                    .fill(RAWDeskTokens.ColorToken.panel)
                Capsule()
                    .fill(
                        RAWDeskTokens.ColorToken.sliderTrack
                    )
                    .frame(height: trackHeight)
                // A mixed selection has no single real value, so no fill.
                if !showsMixedMarker {
                    Capsule()
                        .fill(
                            usesNeutralTint
                                ? RAWDeskTokens.ColorToken
                                    .sliderFill
                                : RAWDeskTokens.ColorToken
                                    .selection
                        )
                        .frame(
                            width: abs(valueX - originX),
                            height: trackHeight
                        )
                        .offset(x: min(valueX, originX))
                }
                Rectangle()
                    .fill(
                        RAWDeskTokens.ColorToken.sliderOrigin
                    )
                    .frame(
                        width: 1,
                        height: trackHeight + 4
                    )
                    .offset(x: originX - 0.5)
                Circle()
                    .fill(
                        RAWDeskTokens.ColorToken.sliderKnob
                    )
                    // A rim and a cast shadow give the knob a physical edge
                    // against both the track and the panel, so it reads as
                    // something to grab rather than a printed dot.
                    .overlay {
                        Circle()
                            .strokeBorder(
                                RAWDeskTokens.ColorToken
                                    .canvas.opacity(0.55),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: RAWDeskTokens.ColorToken
                            .canvas.opacity(0.6),
                        radius: 1.5,
                        y: 1
                    )
                    .frame(
                        width: knobDiameter,
                        height: knobDiameter
                    )
                    .offset(x: valueX - knobDiameter / 2)
            }
            .frame(
                height: proxy.size.height,
                alignment: .center
            )
        }
        .frame(height: coverHeight)
    }

    private func fraction(
        of subject: Double,
        span: Double
    ) -> Double {
        guard span > 0 else { return 0 }
        let clamped = min(
            range.upperBound,
            max(range.lowerBound, subject)
        )
        return (clamped - range.lowerBound) / span
    }
}

struct RAWSliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -100...100
    var step: Double = 1
    var resetValue: Double = 0
    var isMixed = false
    var format: (Double) -> String = {
        String(format: "%+.2f", $0)
    }

    @State private var textValue = ""
    @State private var isSliderEditing = false
    @State private var isFieldHovering = false
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        // "Active" means the user is actually working this control: dragging
        // the slider, or typing in its value field.
        let sliderPresentation =
            RAWSliderPresentation(
                value: value,
                isMixed: isMixed,
                isSliderActive:
                    isSliderEditing || textFieldFocused,
                format: format
            )
        let fieldPresentation =
            RAWSliderPresentation(
                value: value,
                isMixed: isMixed,
                isFieldFocused:
                    textFieldFocused,
                format: format
            )
        RAWInspectorRow {
            Grid(
                horizontalSpacing:
                    RAWDeskTokens.Spacing.small
            ) {
                GridRow {
                    // Wide enough for "Temperature", the longest label in the
                    // panel. 72 truncated it to "Temperat…"; the value column
                    // is where the width was reclaimed instead.
                    Text(title)
                        .font(
                            RAWDeskTokens.Typography.control
                        )
                        .lineLimit(1)
                        .frame(
                            width: 84,
                            alignment: .leading
                        )
                    // The native Slider stays fully opaque and underneath, so
                    // it keeps every behaviour macOS gives it: click-to-set,
                    // drag, keyboard, VoiceOver. The custom track is drawn over
                    // it and passes clicks straight through. An earlier attempt
                    // hid the Slider with `.opacity(0)` instead — SwiftUI stops
                    // hit-testing a fully transparent view, which left the
                    // sliders looking right and completely dead.
                    ZStack {
                        Slider(
                            value: $value,
                            in: range,
                            step: step
                        ) { editing in
                            isSliderEditing = editing
                        }
                        .rawKeyboardAdjustableSlider(
                            value: $value,
                            in: range,
                            step: step
                        )
                        .rawSliderTarget()
                        .accessibilityLabel(title)
                        .accessibilityValue(
                            sliderPresentation
                                .accessibilityValue
                        )
                        .onTapGesture(count: 2) {
                            value = resetValue
                        }

                        RAWSliderTrack(
                            value: value,
                            range: range,
                            origin: resetValue,
                            usesNeutralTint:
                                sliderPresentation
                                    .usesNeutralTint,
                            showsMixedMarker:
                                sliderPresentation
                                    .showsMixedMarker
                        )
                        // Purely the visual. Hit testing off so every click
                        // and drag reaches the Slider beneath it.
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                    }
                    TextField(
                        fieldPresentation
                            .fieldPlaceholder,
                        text: $textValue
                    )
                    .textFieldStyle(.plain)
                    .font(
                        RAWDeskTokens.Typography.numeric
                    )
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .focused($textFieldFocused)
                    // Sized to the widest real value ("+100.00"). It was wide
                    // enough to leave a visible dead gap between the end of
                    // the track and the number.
                    .frame(width: 48)
                    .frame(
                        minHeight:
                            RAWDeskTokens.Size.iconTarget
                    )
                    .padding(
                        .horizontal,
                        RAWDeskTokens.Spacing.xSmall
                    )
                    // The value reads as text at rest. Twelve permanently
                    // boxed fields put more visual weight beside the photo
                    // than the numbers deserve; the box appears when the
                    // field is actually a target.
                    .background(
                        isFieldHovering || textFieldFocused
                            ? RAWDeskTokens.ColorToken
                                .controlElevated
                            : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius
                                    .control
                        )
                    )
                    .onHover { hovering in
                        isFieldHovering = hovering
                    }
                    .onSubmit(commitTextValue)
                    .onChange(
                        of: textFieldFocused
                    ) { _, focused in
                        if focused {
                            textValue =
                                isMixed
                                ? ""
                                : format(value)
                        } else {
                            commitTextValue()
                        }
                    }
                    .accessibilityValue(
                        fieldPresentation
                            .accessibilityValue
                    )
                }
            }
        }
    }

    private func commitTextValue() {
        let sanitized = textValue
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "°", with: "")
        guard let parsed = Double(sanitized) else {
            textValue = format(value)
            return
        }
        value = min(range.upperBound, max(range.lowerBound, parsed))
        textValue = format(value)
    }
}

/// Keeps slider keyboard adjustment consistent across the app. Arrow keys use
/// the declared fine step; Shift-arrow uses a 10× coarse step.
private struct RAWSliderKeyboardModifier<
    Value: BinaryFloatingPoint
>: ViewModifier {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value

    func body(content: Content) -> some View {
        content
            .focusable()
            .onKeyPress(
                keys: [.leftArrow, .rightArrow]
            ) { press in
                let direction: Value =
                    press.key == .leftArrow ? -1 : 1
                let multiplier: Value =
                    press.modifiers.contains(.shift) ? 10 : 1
                let candidate =
                    value + (direction * step * multiplier)
                value = min(
                    range.upperBound,
                    max(range.lowerBound, candidate)
                )
                return .handled
            }
    }
}

extension View {
    func rawKeyboardAdjustableSlider<
        Value: BinaryFloatingPoint
    >(
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        step: Value
    ) -> some View {
        modifier(
            RAWSliderKeyboardModifier(
                value: value,
                range: range,
                step: step
            )
        )
    }
}

func rawClampedBinding<Value: Comparable>(
    _ source: Binding<Value>,
    in range: ClosedRange<Value>
) -> Binding<Value> {
    Binding(
        get: { source.wrappedValue },
        set: { candidate in
            source.wrappedValue = min(
                range.upperBound,
                max(range.lowerBound, candidate)
            )
        }
    )
}

func rawDoubleBinding(
    _ source: Binding<CGFloat>,
    in range: ClosedRange<CGFloat>
) -> Binding<Double> {
    Binding(
        get: { Double(source.wrappedValue) },
        set: { candidate in
            source.wrappedValue = min(
                range.upperBound,
                max(
                    range.lowerBound,
                    CGFloat(candidate)
                )
            )
        }
    )
}

/// Five directly clickable stars. Clicking the current rating clears it, which
/// is how every photo tool behaves. Shared so a rating looks and works the same
/// in the inspector, Compare, Survey, and Reference.
struct RAWStarRating: View {
    @Binding var rating: Int
    /// Tightens the glyphs for the review workspaces, where the control shares
    /// a narrow overlay with other status. All five stars stay operable.
    var compact = false

    var body: some View {
        HStack(
            spacing: compact
                ? RAWDeskTokens.Spacing.xxSmall
                : RAWDeskTokens.Spacing.xSmall
        ) {
            ForEach(1...5, id: \.self) { position in
                Image(
                    systemName: position <= rating
                        ? "star.fill"
                        : "star"
                )
                .imageScale(compact ? .small : .medium)
                .foregroundStyle(
                    position <= rating
                        ? RAWDeskTokens.ColorToken.ratingStar
                        : RAWDeskTokens.ColorToken
                            .ratingStarEmpty
                )
                .onTapGesture {
                    rating = rating == position ? 0 : position
                }
                .accessibilityLabel(
                    Text("\(position) star")
                )
                .accessibilityAddTraits(
                    position <= rating
                        ? [.isButton, .isSelected]
                        : [.isButton]
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One vocabulary for rating, flagging, and colour labelling: stars are always
/// stars, pick and reject are always flags, and a colour label is always a
/// swatch. The same control is used wherever these fields are editable, so the
/// same photo attribute never appears as a menu in one panel and a switch in
/// another.
struct RAWReviewControls: View {
    @ObservedObject var library: LibraryViewModel
    let asset: PhotoAsset
    var compact = false

    var body: some View {
        HStack(
            spacing:
                compact
                ? RAWDeskTokens.Spacing.xSmall
                : RAWDeskTokens.Spacing.small
        ) {
            RAWStarRating(
                rating: Binding(
                    get: { asset.userState.rating },
                    set: {
                        library.setRating($0, for: asset.id)
                    }
                ),
                compact: compact
            )
            .help("Rating (0–5)")

            // Flags are glyphs, never glyph-plus-word. The words made the row
            // wider than the inspector and wrapped "Reject" onto two lines;
            // the filled/outline state already carries the meaning, and the
            // help text and accessibility label carry the words.
            Button {
                library.setPickStatus(.picked, for: asset.id)
            } label: {
                Label(
                    asset.userState.flagged
                        ? "Picked"
                        : "Pick",
                    systemImage:
                        asset.userState.flagged
                        ? "flag.fill"
                        : "flag"
                )
                .labelStyle(.iconOnly)
            }
            .help("Pick photo (P)")
            .frame(
                minWidth:
                    RAWDeskTokens.Size.iconTarget,
                minHeight:
                    RAWDeskTokens.Size.iconTarget
            )
            .accessibilityLabel(
                asset.userState.flagged
                    ? "Picked"
                    : "Pick photo"
            )

            Button {
                library.setPickStatus(.rejected, for: asset.id)
            } label: {
                Label(
                    asset.userState.rejected
                        ? "Rejected"
                        : "Reject",
                    systemImage:
                        asset.userState.rejected
                        ? "xmark.circle.fill"
                        : "xmark.circle"
                )
                .labelStyle(.iconOnly)
            }
            .accessibilityLabel(
                asset.userState.rejected
                    ? "Rejected"
                    : "Reject photo"
            )
            .help("Reject photo (X)")
            .frame(
                minWidth:
                    RAWDeskTokens.Size.iconTarget,
                minHeight:
                    RAWDeskTokens.Size.iconTarget
            )

            colorLabelSwatches
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }

    /// Colour labels as swatches. Clicking the active swatch clears the label,
    /// mirroring how the stars behave, so no separate "None" control is needed.
    private var colorLabelSwatches: some View {
        let swatch: CGFloat = compact ? 9 : 11
        return HStack(
            spacing: compact
                ? RAWDeskTokens.Spacing.xxSmall
                : RAWDeskTokens.Spacing.xSmall
        ) {
            ForEach(
                PhotoColorLabel.allCases.filter { $0 != .none }
            ) { label in
                let isActive =
                    asset.userState.colorLabel == label
                RoundedRectangle(
                    cornerRadius: RAWDeskTokens.Radius.control
                )
                .fill(label.swatchColor)
                .frame(width: swatch, height: swatch)
                .overlay {
                    if isActive {
                        RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius.control
                        )
                        .strokeBorder(
                            RAWDeskTokens.ColorToken
                                .textPrimary,
                            lineWidth: 1.5
                        )
                        // Sits just outside the swatch so the fill colour
                        // stays readable underneath the ring.
                        .padding(
                            -RAWDeskTokens.Spacing.xSmall / 2
                        )
                    }
                }
                .onTapGesture {
                    library.setColorLabel(
                        isActive ? .none : label,
                        for: asset.id
                    )
                }
                .help(
                    library.colorLabelName(for: label)
                )
                .accessibilityLabel(
                    library.colorLabelName(for: label)
                )
                .accessibilityAddTraits(
                    isActive
                        ? [.isButton, .isSelected]
                        : [.isButton]
                )
            }
        }
        .frame(
            minHeight: RAWDeskTokens.Size.iconTarget
        )
        .accessibilityElement(children: .contain)
    }

}

struct RAWInlineMessage: View {
    let title: String
    let message: String
    var systemImage = "info.circle"
    var tone: RAWBadgeTone = .neutral

    var body: some View {
        HStack(
            alignment: .top,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.background)
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text(title)
                    .font(RAWDeskTokens.Typography.sectionHeader)
                Text(message)
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken.textSecondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(RAWDeskTokens.Spacing.medium)
        .background(
            RAWDeskTokens.ColorToken.controlElevated.opacity(0.72),
            in: RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.group
            )
        )
        .accessibilityElement(children: .combine)
    }
}
