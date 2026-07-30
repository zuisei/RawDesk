import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import RAWDesk

final class UIStateContractTests: XCTestCase {
    func testDesignTokensMatchTheImprovementSpecification() throws {
        XCTAssertEqual(
            RAWDeskTokens.Spacing.xxSmall,
            2
        )
        XCTAssertEqual(
            RAWDeskTokens.Spacing.xSmall,
            4
        )
        XCTAssertEqual(
            RAWDeskTokens.Spacing.small,
            8
        )
        XCTAssertEqual(
            RAWDeskTokens.Spacing.medium,
            12
        )
        XCTAssertEqual(
            RAWDeskTokens.Spacing.large,
            16
        )
        XCTAssertEqual(
            RAWDeskTokens.Spacing.xLarge,
            24
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.toolbarHeight,
            48
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.leftSidebar,
            240
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.leftSidebarMinimum,
            220
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.leftSidebarMaximum,
            280
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.leftSidebarRange,
            220...280
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.rightInspector,
            320
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.rightInspectorCompact,
            300
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.rightInspectorMaximum,
            380
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.rightInspectorRange,
            300...380
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.developFilmstrip,
            136
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.developFilmstripMinimum,
            120
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.developFilmstripMaximum,
            168
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.developFilmstripRange,
            120...168
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.libraryFilmstrip,
            128
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.libraryFilmstripMinimum,
            112
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.libraryFilmstripMaximum,
            156
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.libraryFilmstripRange,
            112...156
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.toolRail,
            40
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.iconTarget,
            28
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.primaryButtonHeight,
            34
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.inspectorRow,
            30
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.workspaceControlBar,
            36
        )
        XCTAssertEqual(
            RAWDeskTokens.Size.canvasStatusBar,
            28
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.modalTitleSize,
            18
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.workspaceHeaderSize,
            14
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.sectionHeaderSize,
            12
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.controlSize,
            13
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.metadataSize,
            11
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.numericSize,
            12
        )
        XCTAssertEqual(
            RAWDeskTokens.Typography.badgeSize,
            10
        )
        XCTAssertEqual(
            RAWDeskTokens.Radius.control,
            6
        )
        XCTAssertEqual(
            RAWDeskTokens.Radius.group,
            8
        )
        XCTAssertEqual(
            RAWDeskTokens.Radius.modal,
            12
        )

        // The image well is deliberately well below `panel`, not a few steps
        // below it, so a photograph reads as the brightest object on screen.
        try assertColor(
            RAWDeskTokens.ColorToken.canvas,
            red: 10,
            green: 11,
            blue: 12
        )
        try assertColor(
            RAWDeskTokens.ColorToken.chrome,
            red: 26,
            green: 28,
            blue: 31
        )
        try assertColor(
            RAWDeskTokens.ColorToken.panel,
            red: 32,
            green: 35,
            blue: 40
        )
        try assertColor(
            RAWDeskTokens.ColorToken.controlElevated,
            red: 42,
            green: 46,
            blue: 52
        )
        try assertColor(
            RAWDeskTokens.ColorToken.textPrimary,
            red: 241,
            green: 243,
            blue: 245
        )
        try assertColor(
            RAWDeskTokens.ColorToken.textSecondary,
            red: 169,
            green: 176,
            blue: 186
        )
        try assertColor(
            RAWDeskTokens.ColorToken.divider,
            red: 255,
            green: 255,
            blue: 255,
            alpha: 0.12
        )
        // Selection is a fixed, low-saturation blue rather than the system
        // accent: the photograph must stay the only saturated object on
        // screen, and a user-chosen accent would otherwise repaint the whole
        // interface an arbitrary hue.
        try assertColor(
            RAWDeskTokens.ColorToken.selection,
            red: 92,
            green: 124,
            blue: 168
        )
        try assertColor(
            RAWDeskTokens.ColorToken.sliderTrack,
            red: 58,
            green: 63,
            blue: 70
        )
        try assertColor(
            RAWDeskTokens.ColorToken.sliderFill,
            red: 139,
            green: 147,
            blue: 160
        )
        try assertColor(
            RAWDeskTokens.ColorToken.sliderKnob,
            red: 200,
            green: 205,
            blue: 212
        )
        try assertColor(
            RAWDeskTokens.ColorToken.sliderOrigin,
            red: 78,
            green: 84,
            blue: 92
        )
        try assertSystemColor(
            RAWDeskTokens.ColorToken.warning,
            matches: .systemOrange
        )
        try assertSystemColor(
            RAWDeskTokens.ColorToken.destructive,
            matches: .systemRed
        )
        try assertSystemColor(
            RAWDeskTokens.ColorToken.success,
            matches: .systemGreen
        )
    }

    func testWorkspaceViewsDoNotBypassSharedDesignTokens()
        throws
    {
        let packageRoot = URL(
            fileURLWithPath: #filePath
        )
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        let viewsDirectory = packageRoot
            .appendingPathComponent(
                "Sources/RAWDesk/Views",
                isDirectory: true
            )
        let viewFiles = try FileManager.default
            .contentsOfDirectory(
                at: viewsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let forbiddenFragments = [
            ".font(.caption",
            ".font(.caption2",
            ".font(.callout",
            ".font(.headline",
            ".font(.subheadline",
            ".font(.body",
            ".font(.title2",
            ".font(.title3",
            ".font(.largeTitle",
            ".font(.system(size:9",
            "NSFont.systemFont(ofSize:9",
            ".foregroundStyle(.secondary)",
            ".foregroundStyle(.tertiary)",
            ".foregroundStyle(.primary)",
            ".foregroundColor(.secondary)",
            ".foregroundColor(.tertiary)",
            ".foregroundColor(.primary)",
            ".quaternary",
            "Color.secondary",
            "Color.primary",
            "NSColor.secondaryLabelColor",
            "NSColor.labelColor",
            "NSColor.windowBackgroundColor",
            "NSColor.controlBackgroundColor",
            "Color(nsColor:.controlBackgroundColor)",
            "Color(nsColor:.windowBackgroundColor)",
            "Color(nsColor:.underPageBackgroundColor)",
            "Color(nsColor:.textBackgroundColor)",
            "Color(nsColor:.tertiaryLabelColor)",
            ".ultraThinMaterial",
            ".thinMaterial",
            ".regularMaterial",
            ".thickMaterial",
            ".ultraThickMaterial",
            "ContentUnavailableView",
        ]
        let rawRadiusPatterns = [
            #"cornerRadius:[0-9]"#,
            #"\.cornerRadius\([0-9]"#,
        ]
        let rawSpacingPatterns = [
            #"spacing:[1-9]"#,
            #"[Ss]pacing:[1-9]"#,
            #"spacing:[^)]*[1-9]"#,
            #"\.padding\(-?[0-9]"#,
            #"\.padding\(\.[A-Za-z]+,-?[0-9]"#,
            #"(spacing|padding):CGFloat=[1-9]"#,
        ]
        let rawSemanticColorFragments = [
            "Color.accentColor",
            "Color.orange",
            "Color(nsColor:.systemOrange)",
            "NSColor.controlAccentColor",
            "NSColor.systemOrange",
            ".foregroundStyle(.tint)",
            ".foregroundStyle(.orange)",
            ".foregroundStyle(.red)",
            ".foregroundStyle(.green)",
            ".tint(.orange)",
            ".tint(.red)",
            ".tint(.green)",
            "tint:.orange",
            "tint:.red",
            "tint:.green",
        ]

        for file in viewFiles {
            let source = try String(
                contentsOf: file,
                encoding: .utf8
            )
            let compact = source.replacingOccurrences(
                of: #"\s+"#,
                with: "",
                options: .regularExpression
            )
            let primaryButtonCount = occurrenceCount(
                of: ".buttonStyle(.borderedProminent)",
                in: compact
            )
            let primaryButtonHeightCount = occurrenceCount(
                of: ".rawPrimaryButtonHeight()",
                in: compact
            )
            XCTAssertEqual(
                primaryButtonHeightCount,
                primaryButtonCount,
                "\(file.lastPathComponent) must give every prominent button the shared 34-point primary height"
            )

            let nativeSliderCount = regularExpressionMatchCount(
                #"(?<![A-Za-z0-9_])Slider\("#,
                in: compact
            )
            XCTAssertEqual(
                occurrenceCount(
                    of: ".rawKeyboardAdjustableSlider(",
                    in: compact
                ),
                nativeSliderCount,
                "\(file.lastPathComponent) must give every native Slider fine and coarse keyboard adjustment"
            )
            XCTAssertEqual(
                occurrenceCount(
                    of: ".rawSliderTarget()",
                    in: compact
                ),
                nativeSliderCount,
                "\(file.lastPathComponent) must give every native Slider the shared 28-point interaction target"
            )

            for fragment in forbiddenFragments {
                XCTAssertFalse(
                    compact.contains(fragment),
                    "\(file.lastPathComponent) bypasses the shared design system with \(fragment)"
                )
            }
            if file.lastPathComponent
                != "RAWDeskDesignSystem.swift" {
                XCTAssertFalse(
                    compact.contains(
                        "NSFont.systemFont("
                    ),
                    "\(file.lastPathComponent) bypasses RAWDeskTokens.Typography for AppKit text"
                )
                XCTAssertFalse(
                    compact.contains("Font.system("),
                    "\(file.lastPathComponent) bypasses RAWDeskTokens.Typography for SwiftUI text"
                )
                XCTAssertFalse(
                    compact.contains("Color(red:"),
                    "\(file.lastPathComponent) hard-codes an RGB interface color instead of RAWDeskTokens.ColorToken"
                )
                for fragment in rawSemanticColorFragments {
                    XCTAssertFalse(
                        compact.contains(fragment),
                        "\(file.lastPathComponent) bypasses RAWDeskTokens.ColorToken with \(fragment)"
                    )
                }
            }
            if file.lastPathComponent
                == "PhotoImportView.swift" {
                XCTAssertTrue(
                    compact.contains("RAWEmptyState("),
                    "PhotoImportView must use the shared EmptyState for its source-review zero state"
                )
                XCTAssertTrue(
                    compact.contains("RAWPreflightSummary("),
                    "PhotoImportView must use the shared PreflightSummary"
                )
                XCTAssertTrue(
                    compact.contains("RAWPrimaryFooterBar"),
                    "PhotoImportView must use the shared PrimaryFooterBar"
                )
                XCTAssertTrue(
                    compact.contains("RAWProgressBanner("),
                    "PhotoImportView must use the shared non-blocking ProgressBanner"
                )
                XCTAssertTrue(
                    compact.contains(
                        ".accessibilityAddTraits("
                    )
                    && compact.contains(
                        ".accessibilityRemoveTraits("
                    ),
                    "Import method cards must expose exactly one selected accessibility state"
                )
                XCTAssertTrue(
                    compact.contains(
                        "presentation.accessibilityDetailSummary"
                    ),
                    "The preflight detail popover must expose its full summary to accessibility clients"
                )
            }
            if file.lastPathComponent
                == "ErrorPlaceholderView.swift" {
                XCTAssertTrue(
                    compact.contains("RAWEmptyState("),
                    "Canvas loading, missing, and unreadable placeholders must use the shared EmptyState"
                )
            }
            if file.lastPathComponent
                == "RAWLibrarySidebarView.swift" {
                XCTAssertTrue(
                    compact.contains("RAWSidebarSection("),
                    "Library navigation must use the shared persistent SidebarSection"
                )
            }
            if file.lastPathComponent
                == "MetadataInspectorView.swift" {
                XCTAssertTrue(
                    compact.contains("RAWInspectorRow{"),
                    "Metadata rows must use the shared 30-point InspectorRow"
                )
            }
            // The Develop tools moved from a vertical rail beside the image
            // into a labelled row in the inspector, under the histogram. The
            // contract follows them: they must still use the shared button.
            if file.lastPathComponent
                == "EditingInspectorView.swift" {
                XCTAssertTrue(
                    compact.contains("RAWToolRailButton("),
                    "Develop tools must use the shared ToolRailButton"
                )
            }
            if file.lastPathComponent
                == "ToolbarContent.swift" {
                XCTAssertTrue(
                    compact.contains("RAWWorkspaceSwitcher("),
                    "The global toolbar must use the shared WorkspaceSwitcher"
                )
            }
            for pattern in rawRadiusPatterns {
                XCTAssertNil(
                    compact.range(
                        of: pattern,
                        options: .regularExpression
                    ),
                    "\(file.lastPathComponent) uses a numeric radius instead of RAWDeskTokens.Radius"
                )
            }
            for pattern in rawSpacingPatterns {
                XCTAssertNil(
                    compact.range(
                        of: pattern,
                        options: .regularExpression
                    ),
                    "\(file.lastPathComponent) uses numeric spacing instead of RAWDeskTokens.Spacing"
                )
            }
        }
    }

    func testEmbeddedRAWPreviewExplainsDecoderAndCamera() throws {
        let asset = makeRAWAsset(
            "SONY_0001.ARW",
            loadState: .loaded,
            cameraModel: "Sony α7 IV"
        )
        let presentation = try XCTUnwrap(
            RAWDecodeDetailPresentation.make(
                asset: asset,
                decodeSource: .embeddedPreview
            )
        )

        XCTAssertEqual(presentation.kind, .preview)
        XCTAssertEqual(
            presentation.summary,
            "Embedded preview — Sony α7 IV RAW decoder unsupported"
        )
        XCTAssertTrue(
            presentation.message.contains(
                "Embedded preview"
            )
        )
        XCTAssertTrue(
            presentation.message.contains(
                "Camera: Sony α7 IV"
            )
        )
        XCTAssertTrue(
            presentation.message.contains(
                "original file was not changed"
            )
        )
        XCTAssertEqual(
            presentation.actionTitle,
            "Explain RAW preview"
        )
    }

    func testUnreadableRAWProvidesErrorSheetDetails() throws {
        let asset = makeRAWAsset(
            "DAMAGED.ARW",
            loadState: .failed(
                reason: "Invalid TIFF header"
            )
        )
        let presentation = try XCTUnwrap(
            RAWDecodeDetailPresentation.make(
                asset: asset,
                decodeSource: nil
            )
        )

        XCTAssertEqual(
            presentation.kind,
            .unreadable
        )
        XCTAssertEqual(
            presentation.summary,
            "RAW decode failure"
        )
        XCTAssertTrue(
            presentation.message.contains(
                "Invalid TIFF header"
            )
        )
        XCTAssertTrue(
            presentation.message.contains(
                "original file was not changed"
            )
        )
        XCTAssertEqual(
            presentation.actionTitle,
            "Show Details"
        )
    }

    func testRAWFormatBadgeDistinguishesDecodePreviewAndFailure() {
        let loaded = makeRAWAsset(
            "SONY_0002.ARW",
            loadState: .loaded
        )

        let embedded =
            RAWFormatBadgePresentation(
                asset: loaded,
                rawDecodeSource:
                    .embeddedPreview
            )
        XCTAssertEqual(
            embedded.text,
            "ARW · Preview"
        )
        XCTAssertEqual(embedded.tone, .warning)

        let quickLook =
            RAWFormatBadgePresentation(
                asset: loaded,
                rawDecodeSource: .quickLook
            )
        XCTAssertEqual(
            quickLook.text,
            "ARW · Preview"
        )
        XCTAssertEqual(
            quickLook.tone,
            .warning
        )

        let decoded =
            RAWFormatBadgePresentation(
                asset: loaded,
                rawDecodeSource: .ciRAWFilter
            )
        XCTAssertEqual(decoded.text, "ARW")
        XCTAssertEqual(decoded.tone, .neutral)

        let failed =
            RAWFormatBadgePresentation(
                asset: makeRAWAsset(
                    "DAMAGED_2.ARW",
                    loadState:
                        .failed(
                            reason: "Invalid data"
                        )
                )
            )
        XCTAssertEqual(failed.text, "Unreadable")
        XCTAssertEqual(
            failed.systemImage,
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(
            failed.tone,
            .destructive
        )
    }

    func testMixedSliderPresentationUsesDashAndNeutralState() {
        let mixed = RAWSliderPresentation(
            value: 1.25,
            isMixed: true,
            format: {
                String(format: "%+.2f", $0)
            }
        )

        XCTAssertEqual(
            mixed.fieldPlaceholder,
            "—"
        )
        XCTAssertEqual(
            mixed.accessibilityValue,
            "Mixed values"
        )
        XCTAssertTrue(mixed.usesNeutralTint)
        XCTAssertTrue(mixed.showsMixedMarker)
    }

    func testFocusedMixedSliderExposesActiveValueForInput() {
        let focused = RAWSliderPresentation(
            value: 1.25,
            isMixed: true,
            isFieldFocused: true,
            format: {
                String(format: "%+.2f", $0)
            }
        )

        XCTAssertEqual(
            focused.fieldPlaceholder,
            "+1.25"
        )
        XCTAssertEqual(
            focused.accessibilityValue,
            "+1.25"
        )
        XCTAssertTrue(focused.usesNeutralTint)
        XCTAssertFalse(focused.showsMixedMarker)
    }

    func testConcreteSliderPresentationKeepsFormattedValue() {
        let concrete = RAWSliderPresentation(
            value: -0.35,
            isMixed: false,
            format: {
                String(format: "%+.2f", $0)
            }
        )

        XCTAssertEqual(
            concrete.fieldPlaceholder,
            "-0.35"
        )
        XCTAssertEqual(
            concrete.accessibilityValue,
            "-0.35"
        )
        // Neutral is the resting state. A panel of twelve accented sliders
        // would compete with the photograph, so an idle slider stays grey
        // even when it holds a real, non-default value.
        XCTAssertTrue(
            concrete.usesNeutralTint
        )
        XCTAssertFalse(
            concrete.showsMixedMarker
        )
    }

    /// A slider row's formatter and parser must be inverses. Rows that show a
    /// 0…1 value as a percent used the shared parser, which reads the number in
    /// the slider's own units — so typing back the "4%" the row was showing
    /// meant 4.0, and clamped a 0.005…0.25 brush size straight to its maximum.
    func testPercentSliderParsesBackTheValueItDisplays() {
        let format: (Double) -> String = {
            "\(Int(($0 * 100).rounded()))%"
        }
        let parse: (String) -> Double? = { text in
            RAWSliderRow.defaultParse(text).map { $0 / 100 }
        }

        for value in [0.005, 0.04, 0.25, 0.5, 1.0] {
            let shown = format(value)
            let readBack = try? XCTUnwrap(parse(shown))
            XCTAssertEqual(
                readBack ?? .nan,
                value,
                accuracy: 0.005,
                "\(shown) must read back as \(value)"
            )
        }

        // The shared parser is still correct for rows in their own units.
        XCTAssertEqual(
            RAWSliderRow.defaultParse("-0.35"),
            -0.35
        )
        XCTAssertEqual(RAWSliderRow.defaultParse("12%"), 12)
        XCTAssertEqual(RAWSliderRow.defaultParse("45°"), 45)
        XCTAssertNil(RAWSliderRow.defaultParse("abc"))
    }

    func testActiveSliderIsTheOnlyOneAccented() {
        let active = RAWSliderPresentation(
            value: -0.35,
            isMixed: false,
            isSliderActive: true,
            format: {
                String(format: "%+.2f", $0)
            }
        )

        XCTAssertFalse(active.usesNeutralTint)
        XCTAssertEqual(active.accessibilityValue, "-0.35")

        // A mixed selection has no single real value, so its fill is never
        // accented even while the user is dragging it.
        let activeMixed = RAWSliderPresentation(
            value: -0.35,
            isMixed: true,
            isSliderActive: true,
            format: {
                String(format: "%+.2f", $0)
            }
        )

        XCTAssertTrue(activeMixed.usesNeutralTint)
    }

    func testDevelopFilmstripStatusCoversSelectionSyncAndFilter() {
        let status = DevelopFilmstripStatus(
            selectedCount: 3,
            isAutoSyncEnabled: true,
            isFilterActive: true,
            filteredCount: 9
        )

        XCTAssertEqual(
            status.selectionText,
            "3 selected"
        )
        XCTAssertEqual(
            status.selectionAccessibilityLabel,
            "3 photos selected"
        )
        XCTAssertEqual(
            status.autoSyncText,
            "Auto Sync ON"
        )
        XCTAssertEqual(
            status.autoSyncAccessibilityLabel,
            "Auto Sync on"
        )
        XCTAssertTrue(status.isAutoSyncActive)
        XCTAssertTrue(status.showsFilterBadge)
        XCTAssertEqual(
            status.photoCountText,
            "9 photos"
        )
    }

    func testDevelopFilmstripHidesRedundantSingleSelectionStatus() {
        let status = DevelopFilmstripStatus(
            selectedCount: 1,
            isAutoSyncEnabled: false,
            isFilterActive: false,
            filteredCount: 0
        )

        XCTAssertNil(status.selectionText)
        XCTAssertNil(
            status.selectionAccessibilityLabel
        )
        XCTAssertEqual(
            status.autoSyncText,
            "Auto Sync OFF"
        )
        XCTAssertFalse(status.isAutoSyncActive)
        XCTAssertFalse(status.showsFilterBadge)
        XCTAssertEqual(
            status.photoCountText,
            "0 photos"
        )
    }

    func testActiveFilterChipSummarizesAndClearsFacetsWithoutSearch() throws {
        var filter = FilterState(
            searchText: "Sony",
            primary: .sonyARWOnly,
            minimumRating: 3,
            keyword: "Places|Japan",
            colorLabels: [.red, .blue]
        )
        let combined = try XCTUnwrap(
            LibraryActiveFilterChipPresentation(
                filter: filter
            )
        )

        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.hasFacetFilters)
        XCTAssertEqual(filter.activeFacetCount, 4)
        XCTAssertEqual(combined.title, "4 Filters")
        XCTAssertEqual(
            combined.accessibilityValue,
            "4 Filters"
        )

        filter.clearFacetFilters()

        XCTAssertEqual(filter.searchText, "Sony")
        XCTAssertTrue(filter.isActive)
        XCTAssertFalse(filter.hasFacetFilters)
        XCTAssertEqual(filter.activeFacetCount, 0)
        XCTAssertNil(
            LibraryActiveFilterChipPresentation(
                filter: filter
            )
        )

        let rating = try XCTUnwrap(
            LibraryActiveFilterChipPresentation(
                filter: FilterState(
                    minimumRating: 5
                )
            )
        )
        XCTAssertEqual(rating.title, "5+ Stars")

        let keyword = try XCTUnwrap(
            LibraryActiveFilterChipPresentation(
                filter: FilterState(
                    keyword: "Places|Japan"
                )
            )
        )
        XCTAssertEqual(
            keyword.title,
            "Keyword: Places › Japan"
        )
    }

    func testThumbnailSelectionStrokeSeparatesSelectedAndActive() {
        XCTAssertEqual(
            ThumbnailSelectionPresentation
                .strokeWidth(
                    isSelected: false,
                    isActive: false,
                    compareRole: nil,
                    surveyRole: nil
                ),
            0
        )
        XCTAssertEqual(
            ThumbnailSelectionPresentation
                .strokeWidth(
                    isSelected: true,
                    isActive: false,
                    compareRole: nil,
                    surveyRole: nil
                ),
            2
        )
        XCTAssertEqual(
            ThumbnailSelectionPresentation
                .strokeWidth(
                    isSelected: true,
                    isActive: true,
                    compareRole: nil,
                    surveyRole: nil
                ),
            3
        )
        XCTAssertEqual(
            ThumbnailSelectionPresentation
                .strokeWidth(
                    isSelected: false,
                    isActive: false,
                    compareRole: .candidate,
                    surveyRole: nil
                ),
            3
        )
        XCTAssertEqual(
            ThumbnailSelectionPresentation
                .strokeWidth(
                    isSelected: false,
                    isActive: false,
                    compareRole: nil,
                    surveyRole: .selected
                ),
            2
        )
        XCTAssertEqual(
            ThumbnailSelectionPresentation
                .strokeWidth(
                    isSelected: false,
                    isActive: false,
                    compareRole: nil,
                    surveyRole: .active
                ),
            3
        )
    }

    func testMissingThumbnailUsesOneStatusInsteadOfDuplicateBadges() {
        let missing =
            ThumbnailBadgePresentation(
                catalogMissing: true
            )
        XCTAssertTrue(
            missing.showsMissingStatus
        )
        XCTAssertFalse(
            missing.showsFormatStatus
        )

        let available =
            ThumbnailBadgePresentation(
                catalogMissing: false
            )
        XCTAssertFalse(
            available.showsMissingStatus
        )
        XCTAssertTrue(
            available.showsFormatStatus
        )
    }

    func testCanceledImportPresentationStatesCompletedCountAndSafety() {
        let presentation =
            PhotoImportResultPresentation(
                result: PhotoImportResult(
                    importedAssets: [
                        makeAsset("first.jpg"),
                        makeAsset("second.jpg"),
                    ],
                    wasCancelled: true
                )
            )

        XCTAssertEqual(
            presentation.title,
            "Import Canceled"
        )
        XCTAssertEqual(
            presentation.headline,
            "2 photos completed before cancel"
        )
        XCTAssertEqual(
            presentation.cancellationDetail,
            "Completed photos remain imported. Uncommitted copies were removed, and original files were not changed."
        )
        XCTAssertTrue(
            presentation.requiresAttention
        )
        XCTAssertFalse(
            presentation.showsRevealProblems
        )
        XCTAssertTrue(
            presentation.showsLastImport
        )
    }

    func testSuccessfulImportPresentationRemainsPositive() {
        let presentation =
            PhotoImportResultPresentation(
                result: PhotoImportResult(
                    importedAssets: [
                        makeAsset("only.jpg"),
                    ]
                )
            )

        XCTAssertEqual(
            presentation.title,
            "Import Complete"
        )
        XCTAssertEqual(
            presentation.headline,
            "1 photo imported"
        )
        XCTAssertNil(
            presentation.cancellationDetail
        )
        XCTAssertFalse(
            presentation.requiresAttention
        )
        XCTAssertFalse(
            presentation.showsRevealProblems
        )
        XCTAssertTrue(
            presentation.showsLastImport
        )
    }

    func testWarningOnlyImportUsesAttentionStateAndProblemAction() {
        let presentation =
            PhotoImportResultPresentation(
                result: PhotoImportResult(
                    importedAssets: [
                        makeAsset("warning.jpg"),
                    ],
                    warnings: [
                        "A source sidecar was retained.",
                    ]
                )
            )

        XCTAssertTrue(
            presentation.requiresAttention
        )
        XCTAssertTrue(
            presentation.showsRevealProblems
        )
        XCTAssertTrue(
            presentation.showsLastImport
        )
    }

    func testFailedImportDoesNotOfferAnEmptyLastImport() {
        let presentation =
            PhotoImportResultPresentation(
                result: PhotoImportResult(
                    failures: [
                        "unreadable.jpg could not be imported",
                    ]
                )
            )

        XCTAssertTrue(
            presentation.requiresAttention
        )
        XCTAssertTrue(
            presentation.showsRevealProblems
        )
        XCTAssertFalse(
            presentation.showsLastImport
        )
    }

    func testPreflightPresentationExposesEveryPopoverDetail() {
        let sourceRoot = URL(
            fileURLWithPath: "/tmp/source",
            isDirectory: true
        )
        let destination = URL(
            fileURLWithPath: "/tmp/destination",
            isDirectory: true
        )
        let ready = PhotoImportItem(
            sourceURL:
                sourceRoot.appendingPathComponent(
                    "ready.arw"
                ),
            rootURL: sourceRoot,
            fileSize: 2_048,
            format: .sonyARW,
            sidecarURL:
                sourceRoot.appendingPathComponent(
                    "ready.xmp"
                ),
            status: .ready
        )
        let unavailable = PhotoImportItem(
            sourceURL:
                sourceRoot.appendingPathComponent(
                    "offline.cr2"
                ),
            rootURL: sourceRoot,
            fileSize: 0,
            format: .canonCR2,
            status:
                .unavailable(
                    reason: "Volume offline"
                )
        )
        let request = PhotoImportRequest(
            sourceURLs: [sourceRoot],
            mode: .copyToFolder,
            destinationURL: destination,
            recursive: false
        )
        let presentation =
            PhotoImportPreflightPresentation(
                preflight: PhotoImportPreflight(
                    request: request,
                    items: [
                        ready,
                        unavailable,
                    ],
                    warnings: [
                        "One folder could not be inspected.",
                    ]
                )
            )

        XCTAssertEqual(
            presentation.footerSummary,
            "2 total · 1 new · 0 duplicates · 0 unsupported"
        )
        XCTAssertEqual(
            presentation.unavailableCount,
            1
        )
        XCTAssertEqual(
            presentation.estimatedCopySize,
            ByteCountFormatter.string(
                fromByteCount: 2_048,
                countStyle: .file
            )
        )
        XCTAssertEqual(
            presentation.xmpCompanionCount,
            1
        )
        XCTAssertTrue(
            presentation.namingConflictDetail
                .contains("never overwrite")
        )
        XCTAssertEqual(
            presentation.warningCount,
            1
        )
        XCTAssertEqual(
            presentation.warnings,
            [
                "One folder could not be inspected.",
            ]
        )
        XCTAssertEqual(
            presentation.accessibilityDetailSummary,
            "Unavailable 1. "
            + "Estimated copy size "
            + ByteCountFormatter.string(
                fromByteCount: 2_048,
                countStyle: .file
            )
            + ". XMP companions 1. "
            + "Naming conflicts Checked during transfer; "
            + "conflicts use a safe numbered suffix and never overwrite. "
            + "Warnings 1. One folder could not be inspected."
        )
    }

    func testPreflightPresentationTracksCurrentNamingOptions() {
        let source = URL(
            fileURLWithPath: "/tmp/source/photo.jpg"
        )
        let originalRequest = PhotoImportRequest(
            sourceURLs: [source]
        )
        let preflight = PhotoImportPreflight(
            request: originalRequest,
            items: [
                PhotoImportItem(
                    sourceURL: source,
                    rootURL:
                        source.deletingLastPathComponent(),
                    fileSize: 1,
                    format: .jpeg,
                    status: .ready
                ),
            ]
        )
        let addPresentation =
            PhotoImportPreflightPresentation(
                preflight: preflight
            )
        XCTAssertEqual(
            addPresentation.estimatedCopySize,
            "No copy"
        )
        XCTAssertEqual(
            addPresentation.namingConflictDetail,
            "No destination naming for Add."
        )

        let invalidRequest = PhotoImportRequest(
            sourceURLs: [source],
            mode: .copyToFolder,
            destinationURL: URL(
                fileURLWithPath: "/tmp/destination",
                isDirectory: true
            ),
            folderOrganization: .customTemplate,
            customFolderTemplate: "../Escape"
        )
        let invalidPresentation =
            PhotoImportPreflightPresentation(
                preflight: preflight,
                request: invalidRequest
            )
        XCTAssertTrue(
            invalidPresentation.namingConflictDetail
                .hasPrefix("Template needs attention:")
        )
    }

    func testToolbarTaskProgressClampsAndDescribesCompletion() {
        let progress = ActiveToolbarTaskProgress(
            title: "Import",
            status: "Copying and verifying: photo.arw",
            fraction: 1.4,
            accessibilityLabel: "Import progress"
        )

        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.percentage, 100)
        XCTAssertEqual(
            progress.accessibilityValue,
            "100 percent"
        )
        XCTAssertEqual(
            progress.completionText,
            "100% complete"
        )
    }

    func testWelcomeDropPlannerSeparatesOpenAndOptionImport() {
        let folder = URL(
            fileURLWithPath: "/tmp/photos",
            isDirectory: true
        )
        let photo =
            folder.appendingPathComponent(
                "photo.arw"
            )

        XCTAssertEqual(
            WelcomeDropActionPlanner.plan(
                urls: [folder],
                optionHeld: false,
                isDirectory: { _ in true }
            ),
            .openFolder(folder)
        )
        XCTAssertEqual(
            WelcomeDropActionPlanner.plan(
                urls: [photo],
                optionHeld: false,
                isDirectory: { _ in false }
            ),
            .openFolder(folder)
        )
        XCTAssertEqual(
            WelcomeDropActionPlanner.plan(
                urls: [
                    photo,
                    folder,
                ],
                optionHeld: true
            ),
            .presentImport([
                photo,
                folder,
            ])
        )
        XCTAssertNil(
            WelcomeDropActionPlanner.plan(
                urls: [],
                optionHeld: true
            )
        )
    }

    private func makeAsset(
        _ filename: String
    ) -> PhotoAsset {
        let url = URL(
            fileURLWithPath:
                "/tmp/\(filename)"
        )
        return PhotoAsset(
            id: filename,
            url: url,
            path: url.path,
            filename: filename,
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            loadState: .idle,
            metadata: nil,
            userState: PhotoUserState()
        )
    }

    private func makeRAWAsset(
        _ filename: String,
        loadState: ImageLoadState,
        cameraModel: String? = nil
    ) -> PhotoAsset {
        let url = URL(
            fileURLWithPath:
                "/tmp/\(filename)"
        )
        return PhotoAsset(
            id: filename,
            url: url,
            path: url.path,
            filename: filename,
            fileExtension: "arw",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .sonyARW,
            loadState: loadState,
            metadata: PhotoMetadata(
                cameraModel: cameraModel
            ),
            userState: PhotoUserState()
        )
    }

    private func assertColor(
        _ color: Color,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let converted = try XCTUnwrap(
            NSColor(color).usingColorSpace(
                .deviceRGB
            ),
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.redComponent,
            red / 255,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.greenComponent,
            green / 255,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.blueComponent,
            blue / 255,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.alphaComponent,
            alpha,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
    }

    private func occurrenceCount(
        of needle: String,
        in haystack: String
    ) -> Int {
        haystack.components(
            separatedBy: needle
        ).count - 1
    }

    private func regularExpressionMatchCount(
        _ pattern: String,
        in value: String
    ) -> Int {
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            XCTFail(
                "Invalid regular expression: \(pattern)"
            )
            return 0
        }
        return expression.numberOfMatches(
            in: value,
            range: NSRange(
                value.startIndex...,
                in: value
            )
        )
    }

    private func assertSystemColor(
        _ color: Color,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let converted = try XCTUnwrap(
            NSColor(color).usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        let expectedConverted = try XCTUnwrap(
            expected.usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.redComponent,
            expectedConverted.redComponent,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.greenComponent,
            expectedConverted.greenComponent,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.blueComponent,
            expectedConverted.blueComponent,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            converted.alphaComponent,
            expectedConverted.alphaComponent,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
    }
}
