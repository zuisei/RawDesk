# RAWDesk UI改善書 v1.0-draft — Requirement Traceability

更新日: 2026-07-30  
仕様: `~/Downloads/RAWDesk_UI改善書_v1.0-draft.md`  
対象: RAWDesk 0.1.1 (build 2), macOS 14+

## 判定記号

| Status | Meaning |
|---|---|
| PASS-AUTO | 自動テストまたは機械検査で確認 |
| PASS-SOURCE | 実装をsourceで確認し、build済み |
| PASS-RUNTIME-1296 | 最新UIを1296×768の実画面で確認 |
| PASS-RUNTIME-1100 | 最新UIを1100×700の実画面で確認 |
| PRIOR-VISUAL | 直前Releaseの実画面証拠。最新sourceの合格判定には使わない |
| N/A-P2 | 仕様自身が任意のP2としている項目で、必須受け入れ条件ではない |
| PENDING-RUNTIME | 最新buildの実画面確認待ち |
| PENDING-EXTERNAL | 初見の外部参加者が必要 |
| PENDING-OS-MANUAL | macOS補助設定を実際に変更する手動確認が必要 |

`PASS-SOURCE` は目視操作の代替ではない。とくにFocus順、VoiceOver音声、
OS補助設定、ドラッグ修飾キーは、該当する手動行を別に残す。
2026-07-30の全View Token正規化、semantic state color共通化、
Material撤去、opaque List/Form、全EmptyState / NumericField、
Control Bar狭幅fallback、仕様名に対応する共有Viewへの最終統合後に
releaseを実画像で起動し、1296×768でWelcome、Import、Library Grid /
Loupe / Info、Develop、Soft Proof、People、Map、Compareを確認した。
その実行中にImport methodのselected traitとPreflight detailのAX公開に
不整合を見つけて修正した。解除後は修正版releaseを1100×700で再確認し、
Import methodの単一選択、Preflight detailのAX値、Survey / Referenceを
合格とした。さらに再起動試験で、Add取り込み後にDBへ3枚残っていても
Recent FolderがないとWelcomeへ戻る不具合を再現し、catalogのAll Photosへ
復元するfallbackを追加した。同じ隔離catalogでLoupe、選択写真、
Sidebar collapseを含む再起動復元を確認した。
最終binaryはSHA-256
`ea0c64972a3df1dd4c767ea0cd86eceb14e31466bc2ac1ccaf14628b8a38b52f`、
342 tests合格である。4,706枚の実catalogで見つかったRAW thumbnail
待機問題に対して、cache即時復元、embedded Grid fast path、
cancel可能なPreview優先queueを追加し、Sony ARW / Canon CR2実fixtureと
隔離Releaseのcold / warm Gridを確認した。
`PASS-RUNTIME-1296`と`PASS-RUNTIME-1100`は、
それぞれの最新release実画面確認を示す。個別の未操作状態と他window sizeは
引き続き`PENDING-RUNTIME`を残す。画面別証拠は
`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md`に記録した。
自動解除、Keychain操作、Chrome操作、システム設定変更は行わず、
隔離QA終了後にアプリ停止・QA一時領域なし・QA preference domainなしを
確認した。

## 3. Information Architecture / Global Toolbar

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| IA-01 | Global / Workspace / Contextの三層 | PASS-SOURCE, PASS-RUNTIME-1296 | `ContentView.swift`, `ToolbarContent.swift`, `WorkspaceShellViews.swift`; runtime 01–15 |
| IA-02 | Library / Develop / People / Mapを独立した仕事場として切替 | PASS-AUTO, PASS-RUNTIME-1296 | `WorkspaceDestination`; runtime 07–14 |
| TB-01 | Toolbar高さ48、Sidebar / Open / Import / Workspace / Search / Inspectorを常設 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWDeskTokens.Size.toolbarHeight`; runtime 01–15 |
| TB-02 | Open / Import / Exportはラベル付き | PASS-SOURCE, PASS-RUNTIME-1296 | `ToolbarContent.swift`; runtime 01–15 |
| TB-03 | Exportは選択時、Soft ProofはDevelop時、Taskは実行中だけ表示 | PASS-SOURCE | `MainToolbar.body`, `activeTaskProgress` |
| TB-04 | Background taskをクリックして詳細Popover | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `ToolbarTaskProgressView`, `ActiveToolbarTaskProgress`; UI state-contract test |
| TB-05 | Rotate / Zoom / Compare / Survey / Reference等をOverflowへ | PASS-SOURCE | `photoViewActions` |
| TB-06 | 1296pxで裸のアイコン列を作らず、icon-onlyにはHelpとAX label | PASS-SOURCE, PASS-RUNTIME-1296 | `MainToolbar`; runtime AX tree 01–15 |
| TB-07 | Search位置をWorkspace間で固定 | PASS-SOURCE, PASS-RUNTIME-1296 | `ContentView.searchable`; runtime 07–15 |
| TB-08 | Search対象はfilename / keyword / camera / note（lensも含む） | PASS-AUTO | `FilterState.matches`; search unit tests |

## 4–5. Welcome / Library

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| W-01 | 写真0件では左右paneと無効Inspectorを表示しない | PASS-SOURCE, PASS-RUNTIME-1296 | `shouldShowWelcome`; runtime 01 |
| W-02 | Open / Importの2 CTAと違いの説明 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWWelcomeWorkspaceView`; runtime 01 |
| W-03 | Drop Zone、Recent Folders、原本保護文 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWWelcomeWorkspaceView`; runtime 01 |
| W-04 | 通常dropはOpen相当 | PASS-SOURCE | `dropDestination` → `library.open(folder:)` |
| W-05 | Option-dropは対象をImportへ引き継ぐ | PASS-AUTO, PENDING-RUNTIME | `WelcomeDropActionPlanner`; planner + `testImportPresentationCarriesDroppedSourcesAndClearsOnDismiss` |
| L-01 | Grid / Loupeを明示切替し、常設上下previewを撤去 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWLibraryWorkspaceView.regularWorkspace`; runtime 07, 10 |
| L-02 | Space / Return / keypad Enter / G / EとダブルクリックでGrid / Loupe移動 | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `KeyboardHandler`; `ThumbnailGridView.onOpenLoupe`; `KeyboardHandlerTests.testSpaceReturnAndKeypadEnterToggleLibraryLoupe` |
| L-03 | Loupe Filmstrip 112–156px、既定128px | PASS-SOURCE, PASS-RUNTIME-1296 | `libraryFilmstripHeight`, `RAWResizableDivider`; runtime 10 |
| L-04 | Original表示中のbadge | PASS-SOURCE | `RAWLibraryWorkspaceView.imagePreview` |
| L-05 | 選択写真とGrid scroll位置を往復後も保持 | PASS-SOURCE | ViewModel selection + `scrollPositionID` |
| L-06 | Control BarにGrid/Loupe、Sort、Filter、size、Compare/Survey/Reference、Active Filter解除チップ、選択数 | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWLibraryControlBar.activeFilterChip`; facet解除後もGlobal Searchを保持するUI state-contract test。full / compact / narrowの3段階で、narrowはFilterとActionsを28px Menuへ畳む。既存Controlはafter 39, 44、解除チップとnarrow fallbackは最新release確認待ち |
| L-07 | ThumbnailのFormat / Pick / Edit / Rating / Color状態 | PASS-SOURCE, PASS-RUNTIME-1296 | `ThumbnailCellView`; runtime 07–10 |
| L-08 | Missing / Preview / Unreadableを段階表示 | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `ImageLoader.LoadOutcome.rawDecodeSource`をasset/viewerへ伝播し、`RAWFormatBadgePresentation`がRAW decode / embedded preview / Quick Look / failureを分岐。cache hit source保持のSony実fixture testとbadge contract test、Missing単一状態testが合格。最新release表示待ち |
| L-09 | Hover時だけPick / Reject / Rating quick actions | PASS-SOURCE | `ThumbnailCellView.quickActionLayer` |
| L-10 | Multi-selectionとActive Photoを2px / 3px枠で区別 | PASS-AUTO, PASS-SOURCE, PASS-RUNTIME-1296 | `ThumbnailSelectionPresentation`; runtime 08, 15 |
| L-11 | SidebarをCatalog / Collections / Folders / Servicesの4節へ整理、状態保存 | PASS-SOURCE, PASS-RUNTIME-1296, PASS-RUNTIME-1100 | `RAWLibrarySidebarView` + `RAWSidebarSection`; runtime 07–10, 19。3枚のcatalog、Loupe、選択写真、Catalog section collapseを同じ隔離catalogで再起動復元 |
| L-12 | 0件countを非表示 | PASS-SOURCE | `RAWLibrarySidebarView.catalogContents` |
| L-13 | Duplicates / Culling / Auto Importの状態と詳細内設定 | PASS-SOURCE | `servicesContents` |
| L-14 | Assisted Culling countは解析済みcandidate数 | PASS-SOURCE | `cullingScanResult?.candidateCount` |
| L-15 | Library InspectorはQuick Review / Infoだけ | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWLibraryInspectorView`; runtime 07–10, 15 |
| L-16 | Quick ReviewにRating / Flag / Color / Keyword / Quick Collection / Develop CTA | PASS-SOURCE | `RAWLibraryInspectorView.quickReview` |
| L-17 | InfoにRAW decoder / Preview / error詳細、ⓘ説明Popover、`Show Details` error sheet | PASS-AUTO, PASS-SOURCE, PASS-RUNTIME-1296, PENDING-RUNTIME | runtime 09でSony `RAW (CIRAWFilter)`と機種を確認。Preview / unreadableの追加状態は自動合格・手動保留 |
| L-18 | 幅1200未満でLibrary Inspectorを初期collapse | PASS-SOURCE, PASS-RUNTIME-1100 | `configureInitialLayout`; runtime 19で1100×700起動時にInspectorがcollapse |
| L-19 | 1296pxで中央幅720px以上 | PASS-AUTO, PASS-RUNTIME-1296 | `RAWDeskResponsiveLayout`; runtime 07–10で240 / center / 300 paneを確認 |
| L-20 | Inspectorなしでもkeyboard / hoverで主要選別可能 | PASS-SOURCE | `KeyboardHandler`, `ThumbnailCellView` |

## 6. Develop

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| D-01 | Histogram、Soft Proof、Profileを固定し、Accordionだけscroll | PASS-SOURCE, PASS-RUNTIME-1296 | `EditingInspectorView.fixedInspectorHeader`; runtime 11–12 |
| D-02 | 14 sectionsを規定順で表示 | PASS-SOURCE | Light / Color / Tone Curve / Color Mixer / Point Color / Color Grading / Calibration / Masks / Remove / Optics / Crop & Geometry / Effects / Detail / Versions |
| D-03 | 初期展開Light / Color、状態をWorkspaceで保存 | PASS-SOURCE | `@AppStorage rawdesk.develop.section.*` |
| D-04 | Option-click Solo Mode | PASS-SOURCE | `RAWInspectorSection.onSolo` |
| D-05 | 共通Section Header / Reset、意味があるsectionだけ有効SW | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWInspectorSection`, `adjustmentGroup`; Effectsだけに非破壊ON/OFFを表示し、保存・manual/Auto Sync・pixel bypass test |
| D-06 | Slider + monospaced NumericField、double-click Reset | PASS-SOURCE | `RAWSliderRow` |
| D-07 | Masks / Remove / Crop & Geometry / Point Color headerとTool連動 | PASS-SOURCE | `interactiveTool(for:)`, `onActivateTool` |
| D-08 | Tool RailはCrop / Heal·Clone / Mask / Guided Upright / Point Color | PASS-SOURCE, PASS-RUNTIME-1296 | `DevelopCanvasTool`, `RAWDevelopToolRail`; runtime 11 AX tree |
| D-09 | Tool modeにDone / Cancelと操作説明を常設 | PASS-SOURCE, PRIOR-VISUAL, PENDING-RUNTIME | `RAWDevelopToolModeBar`; after 27, 30 |
| D-10 | Mask overlay toggleと「exportへ含まれない」Help | PASS-SOURCE | `RAWDevelopToolModeBar.maskOverlayBinding` |
| D-11 | Canvas status barにFit / 100% / 状態 / filename / RAW状態 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWPhotoCanvasStatusBar`; runtime 11–12 |
| D-12 | 左SidebarはNavigator / Presets / Versions / History list / Folders | PASS-SOURCE, PASS-RUNTIME-1296 | `DevelopSidebarView`; runtime 11 |
| D-13 | Historyに常設Undo / Redo / Reset button列を置かない | PASS-SOURCE | `DevelopSidebarView` |
| D-14 | Develop Filmstrip 120–168、既定136、表示切替 | PASS-SOURCE, PASS-RUNTIME-1296, PENDING-RUNTIME | `RAWDevelopWorkspaceView`; runtime 11–12。keyboard切替は保留 |
| D-15 | Filmstripに選択数 / Auto Sync / Filter状態 | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `DevelopFilmstripStatus`; two UI state-contract tests |
| D-16 | 複数選択時のAuto Sync bannerと全SliderのMixed値 | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `autoSyncBanner`, `PhotoAdjustmentMixedValuePlanner`, `RAWSliderPresentation`, nested Mask / Point Color / Remove / Crop / Tone Curve bindings; mixed + Auto Sync + UI state-contract tests |
| D-17 | ⌥⌘0ですべてのpanelを一時非表示 | PASS-SOURCE | `toggleAllPanels`, `arePanelsTemporarilyHidden` |
| D-18 | 1100×700でDone / Cancelが隠れない | PRIOR-VISUAL, PENDING-RUNTIME | after 30 |
| D-19 | 1296×768でCanvasを最大領域にする | PASS-AUTO, PASS-RUNTIME-1296 | responsive layout test; runtime 11–12 |
| D-20 | Preset hover preview | N/A-P2 | 仕様が「実装コスト高ならP2」の任意項目。既存one-click presetは維持 |

## 7. Import

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| I-01 | 不透明modal、角丸12、外周24 | PASS-SOURCE, PASS-RUNTIME-1296 | `importPresentationOverlay`, `PhotoImportView`; runtime 02–06 |
| I-02 | Source / Review / File Handlingの3領域 | PASS-SOURCE, PASS-RUNTIME-1296 | `PhotoImportView`; runtime 02–06 |
| I-03 | Source空状態にもChoose CTA | PASS-SOURCE | `reviewEmptyState` |
| I-04 | Add / Copy / Moveを説明全文付きradio cardで選択 | PASS-SOURCE, PASS-RUNTIME-1296, PASS-RUNTIME-1100 | runtime 02–05, 16。最終binaryのAX treeでAddだけSelected、Copy / MoveはNot selected |
| I-05 | Move選択前から元ファイル影響を読める | PASS-SOURCE, PASS-RUNTIME-1296 | `methodExplanation`; runtime 02–05 |
| I-06 | MoveのFrom / To、SHA-256 + catalog + final check、既catalog例外 | PASS-SOURCE, PASS-RUNTIME-1296 | `moveSafetyDisclosure`; runtime 05。実際のMoveは安全上実行せず |
| I-07 | Move CTAをMove and Importへ変更 | PASS-SOURCE | `primaryButtonTitle` |
| I-08 | Preflight summaryをFooterへ常設 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWPreflightSummary`; runtime 03–05 |
| I-09 | Preflight clickでUnavailable / size / XMP / naming / warning詳細 | PASS-AUTO, PASS-SOURCE, PASS-RUNTIME-1296, PASS-RUNTIME-1100 | runtime 04, 16。最終binaryのAX detailにUnavailable / copy size / XMP / naming / warningを公開 |
| I-10 | Disabled理由をCTA近接表示 | PASS-SOURCE | `importDisabledReason` |
| I-11 | FooterのPrimary CTAは常に1つ、件数を含む | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWPrimaryFooterBar`; runtime 02–06 |
| I-12 | 実行中Progress + Cancel、全面停止しない | PASS-SOURCE | `RAWProgressBanner`, toolbar task |
| I-13 | Cancelは未commit copyを除去し、完了済み件数と原本結果を明示 | PASS-AUTO, PENDING-RUNTIME | `testCancelDuringCatalogingReturnsCompletedPhotos`, `testCancelAfterMoveCatalogingRetainsEveryOriginal`; `PhotoImportResultPresentation` state-contract tests |
| I-14 | 完了結果にImported / Copied / Moved / Retained / Reused / Skipped / Failed | PASS-AUTO, PASS-SOURCE | `resultSection`; warning-only resultもattention状態にするcontract test |
| I-15 | Show Last Import / Reveal Problems | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `PhotoImportResultPresentation`, `ImportProblemsView`; 全失敗時は空のLast Importを出さないcontract test |
| I-16 | 1100×700でFooter常時可視 | PASS-RUNTIME-1100 | runtime 16 |
| I-17 | Import内部のAdd / Copy / Move安全ロジックは変更しない | PASS-AUTO | existing import test suite |

## 8. People / Map / Review Modes / Soft Proof

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| P-01 | People左IA: Named / Suggested / Needs Review / Ignored / Background | PASS-SOURCE, PRIOR-VISUAL, PENDING-RUNTIME | `PeopleSidebarView`; after 31 |
| P-02 | Suggestedは点線+Label、Confirmedは実線+名前 | PASS-SOURCE, PRIOR-VISUAL, PENDING-RUNTIME | `PeopleWorkspaceView`; after 31 |
| P-03 | Source / confidence / Assign / Create / Unassign / Not a Face | PASS-SOURCE | `PeopleInspectorView` |
| P-04 | ローカル解析、提案≠本人確認の常設文 | PASS-SOURCE, PASS-RUNTIME-1296 | People footer / header; runtime 13 |
| M-01 | With / Without / Saved Private / GPX / Map Style | PASS-SOURCE, PASS-RUNTIME-1296 | `MapSidebarView`; runtime 14 |
| M-02 | Search / Fit / GPX preview / saved radius | PASS-SOURCE | `MapWorkspaceView` |
| M-03 | Coordinates / Source / Camera GPS / Remove Location | PASS-SOURCE, PASS-RUNTIME-1296 | `LocationInspectorView`; runtime 14 |
| M-04 | Private locationのexport効果を明文表示 | PASS-SOURCE | `LocationInspectorView` |
| M-05 | 位置変更はcatalogのみ、原本EXIF不変 | PASS-AUTO, PASS-RUNTIME-1296 | export/location tests; runtime 14の常設説明 |
| R-01 | Compare / Survey / Referenceにmode headerと常設Done | PASS-SOURCE, PASS-RUNTIME-1296, PASS-RUNTIME-1100 | Compareはruntime 15、Survey / Referenceはruntime 17–18 |
| R-02 | ReviewControlsを共有 | PASS-SOURCE | `RAWReviewControls` |
| R-03 | Compare Select / Candidate、Swap / Promote、Zoom/Pan sync | PASS-SOURCE, PASS-RUNTIME-1296, PENDING-RUNTIME | runtime 15でSelect / Candidate / Doneを確認。追加action操作は保留 |
| R-04 | Survey Active太枠、Survey除外とCatalog削除を別操作 | PASS-SOURCE, PASS-RUNTIME-1100 | `PhotoSurveyWorkspaceView`; runtime 17でActive太枠とRemove from Surveyを確認。Catalog削除とはsourceで別action |
| R-05 | Reference / Active role、編集はActiveだけ、layout切替 | PASS-SOURCE, PASS-RUNTIME-1100, PENDING-RUNTIME | `PhotoReferenceWorkspaceView`; runtime 18でReference / Active roleとActive側編集表示を確認。layout切替操作は保留 |
| R-06 | Filmstripにもrole label、色だけで区別しない | PASS-SOURCE, PASS-RUNTIME-1100 | runtime 17–18でfilmstripのActive / Selected / Reference labelを確認 |
| SP-01 | ON時にprofile / intentをCanvas上部へ常設 | PASS-SOURCE, PASS-RUNTIME-1296 | `RAWDevelopCanvasControlBar`; runtime 12 |
| SP-02 | 設定をHistogram下のPopoverへ集約 | PASS-SOURCE | `SoftProofControlsView` |
| SP-03 | Red / Blue / Purple文字凡例、warningはexportされないHelp | PASS-SOURCE | control bar + proof popover |
| SP-04 | Create Proof VersionをPopover主操作にする | PASS-SOURCE | `SoftProofControlsView` |

## 9–10. Tokens / Shared Components

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| T-01 | canvas / chrome / panel / elevated / text / divider / selection / warning / destructive / success色 | PASS-AUTO, PASS-SOURCE | `RAWDeskTokens.ColorToken`; 固定RGBとmacOS accent / systemOrange / systemRed / systemGreenのexact contract test。SwiftUIとAppKitの直書き再混入も禁止 |
| T-02 | 18 / 14 / 12 / 13 / 11 / 12 / 10pt typography | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWDeskTokens.Typography`; 7 roleのexact値を検証し、SwiftUIの旧semantic fontとAppKit直書きfontの再混入を禁止するsource contract test。Map clusterも10pt Badge tokenへ統一 |
| T-03 | 4 / 8 / 12 / 16 / 24 spacing | PASS-AUTO, PASS-SOURCE | `RAWDeskTokens.Spacing`; exact token contractと、horizontal / verticalを含む全Viewの非ゼロ数値spacing/padding再混入を禁止するsource contract test。旧5px Grid間隔も4pxへ統一 |
| T-04 | Toolbar / Sidebar / Inspector / Filmstrip / Rail / button / Slider targetの寸法 | PASS-SOURCE, PASS-AUTO, PENDING-RUNTIME | 全可変域を`RAWDeskTokens.Size`へ集約し`ContentView` / `WorkspaceShellViews` / shared controlsへ接続。全9 Sliderに28px target + keyboard modifier、全26 Primary buttonに34px heightを適用し、Viewごとの個数一致とexact tokenを自動検査 |
| T-05 | 6 / 8 / 12 radius | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWDeskTokens.Radius`; exact値と全Viewの数値radius再混入を禁止するsource contract test |
| T-06 | FormatBadgeを中立色に統一 | PASS-SOURCE, PRIOR-VISUAL, PENDING-RUNTIME | `RAWFormatBadge`; after 44 |
| C-01 | WorkspaceSwitcher / GlobalToolbar | PASS-SOURCE, PENDING-OS-MANUAL | `RAWWorkspaceSwitcher`, `MainToolbar`; shared-use source contract; component state matrix |
| C-02 | SidebarSection / InspectorSection | PASS-SOURCE, PENDING-OS-MANUAL | `RAWSidebarSection`, `RAWInspectorSection`; shared-use source contract; component state matrix |
| C-03 | InspectorRow / SliderRow / NumericField / Mixed | PASS-AUTO, PASS-SOURCE, PENDING-OS-MANUAL | `RAWInspectorRow`, `RAWSliderRow`, `rawNumericField`; Slider外の数値入力も12pt monospacedへ共有化。Mixed state-contract tests; component state matrix |
| C-04 | ToolRailButton / CanvasStatusBar | PASS-SOURCE, PENDING-OS-MANUAL | `RAWToolRailButton`, `RAWPhotoCanvasStatusBar`; shared-use source contract; component state matrix |
| C-05 | Thumbnail / Filmstrip / ReviewControls | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | shared views; selection/state contract tests; component state matrix |
| C-06 | Format / Edit / Missing / Local-only badge | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWFormatBadge`, `RAWStateBadge`, Icon+Label規約; badge state-contract tests; component state matrix |
| C-07 | Progress / InlineError / EmptyState | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWProgressBanner`, `ToolbarTaskProgressView`, `RAWInlineMessage`, `RAWEmptyState`; 標準`ContentUnavailableView`に加えWorkspace loading、People analysis、Import source空、Canvas loading / missing / unreadableを共有token実装へ統合し、再混入をsource contractで禁止。progress state-contract test; component state matrix |
| C-08 | PreflightSummary / PrimaryFooter | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `RAWPreflightSummary`, `RAWPrimaryFooterBar`; shared-use source contractとtwo preflight state-contract tests; component state matrix |

## 11. Keyboard / Accessibility / Window Sizes

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| K-01 | 既存shortcutを維持 | PASS-SOURCE | `RAWDeskApp.commands`, `KeyboardHandler` |
| K-02 | ⌘1–4 workspace | PASS-SOURCE | `RAWDeskApp` |
| K-03 | G / E / Space / Return / keypad Enter、D | PASS-AUTO, PASS-SOURCE, PENDING-RUNTIME | `KeyboardHandler`; Library + photo選択時だけLoupe toggleを消費し、focused button / 他Workspaceへ譲るunit test |
| K-04 | ⌘⌥S / I / F / 0 | PASS-SOURCE | `RAWDeskApp` |
| K-05 | 裸Tabをpanel切替に使わない | PASS-SOURCE | command audit |
| K-06 | 写真shortcutはTextField / Search / Slider / Stepper編集中に発火しない | PASS-AUTO | `KeyboardHandlerTests` |
| A-01 | icon-onlyにAX label + Help、28×28以上の操作Target | PASS-SOURCE; PENDING-OS-MANUAL | 全`iconOnly` / Image-only Buttonのstatic audit、`rawIconButtonTarget`、40×40 Tool Rail、prior AX tree |
| A-02 | Tab順とaccent focus ring | PENDING-OS-MANUAL | `RAWDesk_ACCESSIBILITY_QA_MATRIX.md` |
| A-03 | Workspace / Selection / Active / Toolのannouncement | PASS-SOURCE; PENDING-OS-MANUAL | `AccessibilityNotification.Announcement` |
| A-04 | Rating / Flag / Colorは文字・数値併記 | PASS-SOURCE | `RAWReviewControls`, `ThumbnailCellView`; compact controlsでも設定済みPick / Reject / Color名を表示 |
| A-05 | Gamut warning文字凡例 | PASS-SOURCE | proof controls |
| A-06 | Error / Warning / SuccessはIcon + Label | PASS-SOURCE | badge/message components |
| A-07 | SliderのArrow / Shift-Arrow / direct input | PASS-SOURCE; PENDING-OS-MANUAL | `RAWSliderKeyboardModifier`, `RAWSliderRow` |
| A-08 | Reduce MotionでAccordion / mode transitionを即時化 | PASS-SOURCE; PENDING-OS-MANUAL | reduce-motion environment |
| WS-01 | 1100×700で横scrollなし、Footer / Done / Cancel可視 | PASS-SOURCE, PASS-RUNTIME-1100, PENDING-RUNTIME | runtime 16–19でImport Footer、Survey / Reference Done、Library復元を確認。Develop tool modeのDone / CancelとActive Filter追加後の狭幅Control Barは保留 |
| WS-02 | 1296×768でLibrary center 724px | PASS-AUTO, PASS-RUNTIME-1296 | layout test; runtime 07–10 |
| WS-03 | ≥1440で3 panes + Filmstrip | PRIOR-VISUAL, PENDING-RUNTIME | after 13–14, 35–37 |
| WS-04 | 1200–1439のInspector初期300px、既存値は保持 | PASS-SOURCE | `configureInitialLayout` |

## 12–14. Migration / Acceptance / Open Decisions

| ID | Requirement | Status | Evidence |
|---|---|---|---|
| MIG-01 | ViewModel / Catalog / RAW / Import safetyを維持 | PASS-AUTO | full regression suite |
| MIG-02 | 1 phase分のLegacy rollback | PASS-SOURCE | `rawdesk.ui.useLegacyLayout`, toolbar toggle |
| AC-01 | 初見n≥3がアプリ目的と非破壊性を説明 | PENDING-EXTERNAL | `RAWDesk_FIRST_USE_USABILITY_TEST.md` |
| AC-02 | 初見n≥3がOpen / Importを区別 | PENDING-EXTERNAL | same |
| AC-03 | 初見n≥3がLibrary / Developを区別 | PENDING-EXTERNAL | same |
| AC-04 | Sony ARW Open→Develop→edit→Before→JPEG export、原本hash不変 | PASS-AUTO, PRIOR-VISUAL, PENDING-RUNTIME | Sony integration test; after 41 |
| AC-05 | RAW decode / embedded preview / unreadable詳細をInfoで確認 | PASS-AUTO, PASS-SOURCE, PASS-RUNTIME-1296, PENDING-RUNTIME | runtime 09でSony RAW decodeを確認。embedded preview / unreadableの手動状態は保留 |
| AC-06 | Remove from Catalogに「fileは削除されない」 | PASS-SOURCE | `MetadataInspectorView` |
| AC-07 | Keychain / Chrome / external accountアクセス追加0 | PASS-AUTO | source/symbol/entitlement scan |
| O-01 | §14-1 未監査screen | source解消、部分PASS-RUNTIME-1296 / 1100、PENDING-RUNTIME | Token正規化後のPeople / Map / Compare / Soft Proofをruntime 12–15、Survey / Referenceをruntime 17–18で確認。Sync詳細は保留 |
| O-02 | Assisted Culling countの意味 | 解消 | candidate countのみ |
| O-03 | 紫pillの正体 | 解消 | custom titlebar/purple controlなし。標準`.titleBar` + `.unified` |
| O-04 | Library / Develop state共有範囲 | 解消 | selection共有、pane/filmstrip/accordionはWorkspace別保存、Grid scroll保持 |
| O-05 | Search scope / position | 解消 | Global searchable、filename/keyword/camera/note/lens |
| O-06 | Shortcut conflict / text input / IME | source・unit解消、手動IME確認待ち | `KeyboardHandler`, manual matrix |
| O-07 | 10,000件performance | PASS-AUTO, PASS-RUNTIME-1100, PASS-RUNTIME-1296 | 10,000件filter/sort、4,706-photo modelのwarm first viewport 24 RAW cells、legacy disk cache、cancel / Preview priorityを自動確認。Sony ARW / Canon CR2 embedded fast path、隔離Release cold / warm Grid、通常4,706-photo catalogの起動直後と5-page scroll後をruntime確認。`RAWDesk_THUMBNAIL_PERFORMANCE_QA_2026-07-30.md` |
| O-08 | Localization | 現行方針確定 | Product UIは英語。検証書は日本語 |
| O-09 | Drop既定動作 | 解消 | Open既定、OptionでImport |
| O-10 | Legacy退避 | 解消 | 1 phase rollback toggle |

## 現在残っている証明

source監査で判明したActive Filter解除チップ、狭幅Control Bar fallback、
全ViewのTypography / Color / Radius / Spacing Token逸脱、Material依存、
標準および個別実装のEmptyStateとList/Form既定背景を修正した。検索文字を
保持したfacet解除と、旧semantic font / color / Material、状態色直書き、
数値radius / spacing / padding、AppKit直書きfont、`ContentUnavailableView`
の再混入を止める自動試験も追加した。
受け入れを完全に閉じる前に
必要なのは次の3種類である。

1. 最新release buildで、Option-drop、task detail Popover、Import cancel result /
   Reveal Problems、Active Photo枠、Develop Filmstrip
   status、全SliderのMixed表示、Effects Header ON/OFF、Missing単一badge、
   RAW preview説明 / unreadable details、Active Filter解除チップ、
   Space / Return / keypad Enterに加え、全WorkspaceのToken適用後の
   文字折返し、コントラスト、opaque背景を実画面確認する。
2. 初見ユーザー3名以上の理解度試験を実施する。
3. ユーザーの許可を得てmacOS accessibility設定マトリクスを実施し、
   終了後に設定を完全復元する。

解除後にImport AX、Survey、Reference、同一catalogの再起動復元までは
実施済みである。1には個別状態を実際に作る操作が残る。
2と3は参加者またはユーザーの明示的な関与なしに合格を記録しない。
