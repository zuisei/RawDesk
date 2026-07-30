# RAWDesk UI Redesign — Implementation and Verification Ledger

更新日: 2026-07-30  
仕様書: `~/Downloads/RAWDesk_UI改善書_v1.0-draft.md`  
対象: RAWDesk 0.1.1 (build 2), macOS 14+

## 結論

仕様書の P0 / P1 / P2 に記載された必須アプリ実装はsource上で完了した。
最新sourceのdebug / release build、全自動テスト、Sony α ARW実fixture、
原本ハッシュ、リリースバイナリの安全境界を確認済みである。
受け入れ条件から実装と試験を逆引きする最終監査も行い、仕様上の共通部品が
画面内helperに留まっていた箇所を明示的な共有Viewへ統合した。
全ViewのToken正規化、semantic state colorの共通化、opaque背景化、
全EmptyStateの共通化後に最新releaseを実画像で起動し、1296×768で
Welcome、Import、Library Grid / Loupe、Sony ARW Info、Develop、
Soft Proof、People、Map、Compareを確認した。そこでImport方式Buttonの
Accessibility selected traitとPreflight detailのAccessibility valueに
不整合を見つけ、source / test / releaseを修正した。画面ロック解除後、
最終releaseでAX、Survey、Referenceを再確認した。さらに隔離catalogの
再起動時にSQLiteへ3枚残っているのにWelcomeへ戻る問題を再現し、
Recent Folderがないcatalog-only workspaceをAll Photographsへ復元する
fallbackと回帰試験を追加した。再build後の再起動で3枚、Loupe、
Sidebar section状態の復元まで確認した。
その後、4,706枚の実catalogでRAW thumbnailが一斉にspinner待機する
性能問題を再現・監査した。RAW disk cacheの即時復元、embedded
grid thumbnail fast path、decoder metadata永続化、cancel可能な
Preview優先queueを追加し、Sony ARW / Canon CR2実fixture、
4,706-photo model、隔離releaseのcold / warm Gridで再確認した。

ただし、次の3項目はまだ受け入れ完了としていない。

1. 要件表に残る狭幅、keyboard、loading / error、Mixed / Effects等の個別手動行
2. 初見ユーザー3名以上による理解度テスト
3. VoiceOver / Full Keyboard Access / Increase Contrast / Reduce Transparency / accent color を実際のmacOS設定で切り替える全組み合わせの手動確認

実施手順と記録票は次の文書に分離した。

- `Docs/RAWDesk_FIRST_USE_USABILITY_TEST.md`
- `Docs/RAWDesk_ACCESSIBILITY_QA_MATRIX.md`
- `Docs/RAWDesk_COMPONENT_STATE_MATRIX.md`
- `Docs/RAWDesk_UI_REQUIREMENT_TRACEABILITY.md`
- `Docs/RAWDesk_RUNTIME_QA_2026-07-30.md`
- `Docs/RAWDesk_THUMBNAIL_PERFORMANCE_QA_2026-07-30.md`

## 変更しない境界

- Keychain、Chrome、外部アカウントへアクセスしない。
- 元画像のバイト列を書き換えない。
- RAW処理、カタログ、XMP、Import安全処理は非破壊のまま維持する。
- UIランタイムQAは`scripts/run-isolated-ui-qa.sh --reset`で開始する。
  release appをQA専用bundle idへ複製・再署名し、Application Support、
  `HOME`、`CFFIXED_USER_HOME`も一時directoryへ向けることで、通常の
  RAWDesk catalog / cache / user state / `@AppStorage` / window stateを
  変更しない。再起動復元では`--reset`なし、終了時は`--cleanup`を使う。
- QA終了後はアプリを終了し、上記環境変数を解除して一時QA directoryだけを削除する。

最終確認時点でリリースアプリは終了済み、隔離用環境変数は解除済みである。
既知のQA一時directoryと`local.rawdesk.app.uiqa` preference domainも
残っていない。通常設定は`grid`、通常plistのSHA-256と更新日時は
`ef9bcaa5defd6f39041a86e54d70464a066fdbab17f103bef01c5e11eb461255` /
2026-07-30 08:44:32 JSTのままである。

## 実装結果

| ID | 要件 | 優先度 | 結果 | 主な確認 |
|---|---|---:|---|---|
| P0-1 | Design Tokenと共通コンポーネント | P0 | 実装済み | `RAWDeskDesignSystem.swift`、共有WorkspaceSwitcher / SidebarSection / InspectorSection・Row / Slider / ToolRailButton / Badge / Review / ProgressBanner / PreflightSummary / PrimaryFooterBar / Divider / EmptyState / NumericField。固定RGBに加えmacOS accent / systemOrange / systemRed / systemGreenをselection / warning / destructive / success Tokenへ集約。全Viewの旧semantic font/color、Material、任意radius・spacing・padding、標準`ContentUnavailableView`を除去し、再混入をsource contract testで禁止 |
| P0-2 | Global ToolbarとWorkspace切替 | P0 | 実装済み | `RAWWorkspaceSwitcher`でLibrary / Develop / People / Map、Open / Import / Exportラベル、Search固定、Overflow |
| P0-3 | Sidebar / Inspector / Filmstripの独立開閉・可変・記憶 | P0 | 実装済み・再起動合格 | `RAWSidebarSection`、6px操作領域のDivider、Workspace別幅、Library/Develop別Filmstrip高。catalog-only workspaceの起動fallbackを追加し、隔離再起動で3 photos / Loupe / Catalog collapseを復元。Sidebar件数は右寄せで0件を隠す |
| P0-4 | Empty / Welcome刷新 | P0 | 実装済み | 左右ペイン非表示、Open / Import、Drop Zone、Recent Folders、原本保護文。0件、filter 0件、folder読込中、People解析中、Import source空、CanvasのMissing / unreadable / loadingをtoken固定の`RAWEmptyState`へ統合 |
| P0-5 | Library Grid / Loupe明示切替 | P0 | 実装済み | 常設上下分割を撤去、Loupe Filmstrip、選択・Grid scroll位置維持、Space / Return / keypad Enter / double-click、検索を保持するActive Filter解除チップ |
| P0-6 | Library InspectorをQuick Review / Infoに限定 | P0 | 実装済み | Develop調整項目なし、評価・Flag・Color・Keyword・Develop導線。RAW previewはⓘ説明Popover、読込不能はerror summary + `Show Details` sheet |
| P0-7 | Develop固定部と14 Accordion / Solo | P0 | 実装済み | Histogram / Profile固定、Light / Color初期展開、全SliderのMixed値、Reset、Effects Headerの非破壊ON/OFF |
| P0-8 | Tool RailとTool Mode Bar | P0 | 実装済み | Crop / Heal / Mask / Upright / Point Color、Done / Cancel常設 |
| P0-9 | Import不透明3領域 | P0 | 実装済み | Source / Review / File Handling、1100pxでもFooter表示 |
| P0-10 | Add / Copy / Move安全説明と固定Footer | P0 | 実装済み | 選択前に全文表示、Move削除条件、共有`RAWPreflightSummary` / `RAWPrimaryFooterBar` / `RAWProgressBanner`、途中Cancelの完了件数・原本保持、警告だけでもattention表示、全失敗時は空のLast Importを非表示、単一Primary CTA |
| P1-1 | Typography / Contrast / Spacing / Target | P1 | 実装済み | 仕様トークンへ全Viewを統一し、Toolbar / Sidebar / Inspector / Filmstrip / Rail / 操作Targetの実Viewへ接続。全9 Sliderは28px以上、全26 Primary buttonは34px以上で、個数一致をsource contractで固定。7 typography roleとdivider alphaもexact test対象。数値入力は共有`rawNumericField`、AppKit文字も10/11/13pt tokenを使用。Gridに残っていた5pxを含め4/8/12/16/24以外の非ゼロspacing/paddingを撤去。SwiftUI MaterialとList/Form既定scroll背景を撤去しopaque Token背景へ統一 |
| P1-2 | 共通状態と中立RAW badge | P1 | 実装済み | Missing / Preview / Unreadable / Edited / Mixed / Multi-selection / Active Photo。全共通コンポーネントのDefault〜Multi-selectionを状態表で明示。RAW decode sourceをloader→asset/viewer→Thumbnail・Filmstrip・Canvas・Infoへ伝播し、埋め込み/Quick Look時だけwarning色の`ARW · Preview`、RAW decode時は中立`ARW`を表示。cache hitでもsourceを維持し、Missing時の重複badgeは単一状態へ統合 |
| P1-3 | Canvas Status Barと可変Filmstrip | P1 | 実装済み | Zoom /状態/RAW情報、Library 112–156、Develop 120–168、選択数/Auto Sync/Filter状態 |
| P1-4 | Compare / Survey / Reference共通Shell | P1 | 実装済み | Mode header、Done、役割ラベル、共有ReviewControls、適応Toolbar |
| P1-5 | Keyboard / Focus / Help / Label | P1 | 実装済み | ⌘1–4、G/E/Space/Return/keypad Enter、D、⌘⌥S/I/F/0、Tooltip、AX label。Loupe toggleはLibrary + 写真選択時だけeventを消費し、focused controlを優先 |
| P2-1 | People IAと安全注記 | P2 | 実装済み | Named / Suggested / Review / Ignored、ローカル解析・本人確認ではない旨 |
| P2-2 | Map IAとPrivacy | P2 | 実装済み | With/Without Location、位置Inspector、Private export効果、原本EXIF非変更 |
| P2-3 | Soft Proof | P2 | 実装済み | 常設ON状態、Profile/Intent、Gamut Warning文字凡例、Proof Version |
| P2-4 | Sync / Auto Sync / Auto Import | P2 | 実装済み | 複数選択Banner、基本補正からMask / Remove / Crop / Tone CurveまでのMixed値、監視状態、コンパクトカード |
| P2-5 | 大規模Library | P2 | 実装済み・自動/実画面試験合格 | Lazy表示、検索/絞込/Sort、10,000件filter/sort、4,706-photo modelのwarm first viewport、RAW disk cache即時復元、embedded Grid fast path、cancel可能なPreview優先queue。Sony ARW / Canon CR2実fixtureと隔離release cold / warm Gridを確認 |
| P2-6 | Accessibility 1–8 | P2 | 実装・修正版AX spot check合格 | Label/Tooltip、VoiceOver announcement、非色依存、Sliderキー操作/直接入力、Reduce Motion、Material非依存。最終RuntimeでImport methodは単一selected、Preflight rootは全detail valueを公開 |

## 主要仕様の実装位置

| 領域 | 主なファイル |
|---|---|
| App shell / pane persistence / responsive layout | `Sources/RAWDesk/Views/ContentView.swift`, `Sources/RAWDesk/Views/RAWDeskDesignSystem.swift` |
| Empty / Library / Develop / Import shell | `Sources/RAWDesk/Views/WorkspaceShellViews.swift` |
| Tokens / shared controls / EmptyState / NumericField / SidebarSection / InspectorRow / ToolRailButton / Import footer components / resizable divider / slider behavior | `Sources/RAWDesk/Views/RAWDeskDesignSystem.swift` |
| Toolbar / workspace switcher / accessible labels | `Sources/RAWDesk/Views/ToolbarContent.swift` |
| Develop inspector / accordion / mixed values / numeric fields | `Sources/RAWDesk/Views/EditingInspectorView.swift` |
| Library sidebar | `Sources/RAWDesk/Views/RAWLibrarySidebarView.swift` |
| Grid / culling controls / thumbnail states | `Sources/RAWDesk/Views/ThumbnailGridView.swift` |
| Capture-time stack numeric input | `Sources/RAWDesk/Views/CaptureTimeAutoStackView.swift` |

## 受け入れ結果

| ID | 受け入れ条件 | 結果 | 証拠 |
|---|---|---|---|
| QA-1 | 1100×700〜1728×1117、横スクロールなし | 最新1296×768合格・最終binary 1100×700部分合格・他サイズ保留 | 最新UIは1296×768でWelcome〜Compareまで横scroll・Footer欠落・主要文字切れなし。最終binaryは1100×700でImport / Survey / Reference / Loupe再起動を確認。1440以上と未操作状態は未再確認 |
| QA-2 | Sony α ARW end-to-end、原本不変 | 自動合格・最新UI decode表示合格 | 実fixture統合テストがRAW decode / Develop / export / 原本不変を確認。最新runtimeでSony ARWをImport→選択→Info / Loupe / Developし、`RAW (CIRAWFilter)`、`SONY ILCE-7M4`を確認 |
| QA-3 | Keychain / Chrome / 外部アカウント追加なし | 合格 | Entitlementなし、Security/WebKit/Network/CloudKit/AuthenticationServices importなし、該当未解決symbolなし |
| QA-4 | Build / 全回帰テスト | 合格 | debug / release build成功、342 tests / 0 failures、Sony / Canon実fixture、21 UI state-contract tests、catalog-only restoreとRAW thumbnail performance regressionを含む |
| QA-5 | 初見理解度テスト n≥3 | 未実施 | 外部参加者が必要。記録票を用意済み |
| A11Y-M | §11.2-9 手動macOS設定マトリクス | 未実施 | ユーザーのシステム設定を無断変更しないため、実施票を用意済み |
| QA-6 | 最新追加差分のrelease操作 | 最終spot check合格 | 隔離catalogでWelcome / Import / Grid / Loupe / Info / Develop / Soft Proof / People / Map / Compare / Survey / Referenceを確認。Runtimeで2件のAX不整合とcatalog再起動復元を検出・修正し、最終binaryでAXと再起動を再確認 |

## Layout QA

| 状態 | 1100×700 | 1296×768 | 1440×900 | 最大作業領域 |
|---|---:|---:|---:|---:|
| Empty | 最終Release合格 | 最新Release合格 | source branch確認・最新待ち | source branch確認・最新待ち |
| Library Grid / Loupe | 最終Release Loupe合格 | 最新Release中央724px合格 | 旧Release合格・最新待ち | 旧Release1718×1024合格・最新待ち |
| Develop / Crop / Auto Sync | 旧ReleaseでDone/Cancel可視・最新待ち | 旧Release合格・最新待ち | 旧Release合格・最新待ち | 旧Release合格・最新待ち |
| Import / Move | 最終ReleaseでFooter / AX可視 | 最新Release合格 | source branch確認・最新待ち | source branch確認・最新待ち |
| People / Map | 旧Release合格・最新待ち | source branch確認・最新待ち | source branch確認・最新待ち | source branch確認・最新待ち |
| Compare / Survey / Reference | 最終ReleaseでSurvey / Reference合格 | 現行ReleaseでCompare合格 | source branch確認・最新待ち | source branch確認・最新待ち |

1296×768の旧Library Release画面では、左240px + 6px divider + 中央724px + 6px divider + 右320px = 1296px。最新sourceも同じ寸法plannerを使うが、Token正規化後の折返しを実画面で再確認する。

## Sony α ARW QA

使用fixture:

`testraw/ETH01641.ARW`

SHA-256（QA前後で同一）:

`8ef951da2d11428fde25201372a91193ab24dae7e451fe806b028b8ac7db1ced`

自動試験:

`SonyARWIntegrationTests.testRealSonyAlphaARWRoundTripPreservesOriginal`

実fixture試験ではRAW decode sourceが取得できること、同じthumbnailをcacheから再取得してもsourceが失われないこと、現像・export後も原本hashとXMP不在が維持されることを確認した。

最新runtimeではInfoに `ARW RAW (CIRAWFilter) Status Ready` と
`SONY ILCE-7M4`を表示し、通常のGrid / Filmstripでは中立色の`ARW`
badgeだけを表示した。Library Loupe、Develop、Soft Proofでも同じSony
ARWの実previewを確認した。

## Fixture integrity

| File | SHA-256 |
|---|---|
| `testraw/ETH01535.JPG` | `079b085d700489a1f6c6e0762e2806f9f74f66c51dccf43aa052a667be58e26a` |
| `testraw/ETH01641.ARW` | `8ef951da2d11428fde25201372a91193ab24dae7e451fe806b028b8ac7db1ced` |
| `testraw/IMG_0002.CR2` | `bc8c36ab10367a18519bd326232c764bcf9361a9ca2fbf4e0f1a3d6e4a03fc27` |

`testraw` は上記3ファイルのみで、QAによるXMP追加はない。

## Build / test

最終コマンド:

```sh
RAWDESK_SUPPORT_DIRECTORY_OVERRIDE=/tmp/rawdesk-thumbnail-opt-full-20260730 \
  RAWDESK_SONY_ARW_FIXTURE_DIR=testraw \
  swift test
```

結果: 342 tests、0 failures。Sony / Canon実fixture試験はskipされていない。4,706-photo warm RAW first viewport、legacy cache即時復元、decoder metadata永続化、queued load cancel、Preview priorityを検証するperformance regressionを追加した。catalog-only workspace restore regressionに加え、Mixed値4条件、nested Auto Sync、Import途中Cancel 2経路、Effects Header ON/OFFの保存・手動Sync・Auto Sync・pixel bypass、Space / Return / keypad EnterのLoupe toggleとfocused-control保護、固定RGB、divider alpha、7 typography role、macOS semantic state colorのToken exact値、Mixed表示・Filmstrip status・Active Photo枠・Active Filter解除チップ、Cancel結果、Preflight詳細、warning-only結果、空のLast Import抑止、Toolbar task進捗、通常Drop / Option-drop、Missing単一状態、RAW Preview説明 / Unreadable error sheet、RAW decode / embedded preview / Quick Look / failure badge分岐を確認する21 UI state-contract testsを含む。静的契約は全Viewの旧semantic font/color、selection / warning / destructive / successの直書き、SwiftUI Material、数値radius、仕様外spacing/padding、AppKit直書き文字、`ContentUnavailableView`の再混入を禁止し、全Primary button / native Sliderの共有Target適用と主要共通Viewの利用も固定する。Workspace、Import、People、Canvasの空・読込・解析・失敗状態は共有`RAWEmptyState`へ接続した。SwiftPM test processは隔離した一時storageを使用し、release appは起動していない。

Release:

- App: `build/RAWDesk.app`
- Version: 0.1.1 (2)
- Minimum macOS: 14.0
- Release binary SHA-256: `ea0c64972a3df1dd4c767ea0cd86eceb14e31466bc2ac1ccaf14628b8a38b52f`
- `codesign --verify --deep --strict`: 合格
- Signature: ad hoc
- Entitlements: なし
- 外部ライブラリ依存: なし。Apple system frameworksと`libsqlite3`のみ
- Bundle内の通常ファイル: `Info.plist`、実行バイナリ、`AppIcon.icns`、`CodeResources`の4点
- `com.apple.quarantine`: なし（`com.apple.provenance`のみ付与）

この確認はマルウェア対策ソフトによる全ファイルスキャンではない。2026-07-30確認時点で、このMacには `clamscan` / `freshclam` が入っていないため、AVスキャン済みとは表現しない。

## Security boundary verification

以下をsource、link symbol、entitlement、dynamic dependencyの4面で確認した。

- Keychain API / Security.frameworkの利用追加なし
- Chrome / WebKit操作なし
- 外部アカウント認証なし
- Network / CloudKit / AuthenticationServicesの利用追加なし
- リリースアプリに権限entitlementなし
- 元画像3点のハッシュ不変

確認対象はRAWDeskのsourceと生成したrelease appであり、Mac全体のウイルス感染有無を保証するものではない。

## Accessibility implementation evidence

- icon-only controlにAccessibility LabelとHelp/Tooltip、28×28以上の操作Target
- Sidebar / Control Bar / Center / Inspector / Bottomの論理的なView順
- Workspace、選択、Active Photo、Tool ModeのVoiceOver announcement
- Rating / Flag / Color / Warningを文字またはIcon+Labelで表現
- Soft Proof gamut warningにRed / Blue / Purpleの文字凡例
- 9個の明示的SliderすべてにArrow / Shift+Arrow modifierと28px以上の操作Target
- 26個のPrimary buttonすべてに34px以上の高さ
- 上記2件はViewごとの個数一致をsource contractで継続検証
- すべてのSliderに直接数値入力を併設
- Slider外の数値入力も共有`rawNumericField`で12pt monospacedへ統一
- Reduce Motion時は対象animationを無効化
- 可変DividerはAccessibility adjustable actionと現在値を提供
- 最新runtimeのAX treeでToolbar、Workspace switcher、Library selection /
  Active Photo、Sony RAW metadata、Develop tools / Slider、People、
  Map、Compare roleを確認
- Import methodで視覚選択とAX selected traitの不一致を検出し、
  装飾badgeをAXから除外して各Buttonへselected / not-selectedを明示
- Preflight detail本文がAX treeへ出ない問題を検出し、Popover rootへ
  labelと全detail valueを追加。最終binaryのAX treeで全文公開を確認

上記は§11.2の1–8に対する実装・source/AX確認である。OS設定を実際に切り替える§11.2-9の全組み合わせは別紙で未実施として管理する。

## Visual evidence

Baseline:

`Evidence/2026-07-29/full-ui-audit-before/01-empty-library.png`〜`12-auto-import.png`

最終同一viewport比較:

- `Evidence/2026-07-29/full-ui-audit-after/compare-empty-before-after-1296x768.png`
- `Evidence/2026-07-29/full-ui-audit-after/compare-library-before-after-1296x768.png`
- `Evidence/2026-07-29/full-ui-audit-after/compare-develop-before-after-1296x768.png`
- `Evidence/2026-07-29/full-ui-audit-after/compare-import-before-after-1296x768.png`

Token正規化前のRelease app最終画面（最新合格証拠には使わない）:

`Evidence/2026-07-29/full-ui-audit-after/44-release-library-inspector-1296x768-final.png`

Token正規化後の現行UI runtime:

`Evidence/2026-07-30/ui-spec-runtime/01-welcome-current-release.png`〜
`19-restart-persistence-current-release.jpg`

RAW thumbnail performance修正後の隔離Release:

- `Evidence/2026-07-30/performance/01-fast-grid-cold-release.jpg`
- `Evidence/2026-07-30/performance/02-fast-grid-warm-restart-release.jpg`
- `Evidence/2026-07-30/performance/03-normal-4706-fast-grid-release.jpg`
- `Evidence/2026-07-30/performance/04-normal-4706-scroll-fast-grid-release.jpg`

仕様Referenceとの同一viewport比較:

- `Evidence/2026-07-30/ui-spec-runtime/compare-01-welcome-reference-current-1296x768.jpg`
- `Evidence/2026-07-30/ui-spec-runtime/compare-02-library-reference-current-1296x768.jpg`
- `Evidence/2026-07-30/ui-spec-runtime/compare-03-develop-reference-current-1296x768.jpg`
- `Evidence/2026-07-30/ui-spec-runtime/compare-04-import-reference-current-1296x768.jpg`

画面ごとの判定と修正履歴:

`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md`

## 残る受け入れ作業

source監査と自動試験で既知の必須実装漏れはない。ただし最新Releaseの
視覚・操作受け入れは閉じていない。ゴールを閉じるには、別紙に従って次を記録する。

1. 未再実施の狭幅・Option-drop・task detail・Effects / Mixed・
   loading / error・各keyboard行を手動記録する
2. 初見ユーザー3名以上の理解度テスト結果
3. macOS accessibility設定マトリクスの手動結果

失敗行が出た場合は、その観察事実から追加修正を起票し、修正後に該当行だけでなく隣接サイズ・状態も再確認する。
