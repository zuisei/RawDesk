# RAWDesk 共通コンポーネント状態マトリクス

更新日: 2026-07-30  
対象仕様: `RAWDesk_UI改善書_v1.0-draft.md` §10

## 記号

- `E`: RAWDeskが状態を明示的に描画または文言化する
- `OS`: SwiftUI / AppKit標準Controlの状態表現を使用する
- `N/A — 理由`: コンポーネントの責務上、その状態を持たない

`N/A` は未実装の省略ではない。状態がデータ、処理、選択、または入力の
どれにも該当しない表示専用コンポーネントについて、適用しない理由を記録する。
Hover / Pressed / Focused / Disabledを`OS`とした行は、macOS補助設定を含む
最終見た目を `RAWDesk_ACCESSIBILITY_QA_MATRIX.md` で手動確認する。
最新sourceでは全ViewのTypography / Color / Radius / Spacingを
`RAWDeskTokens`へ接続し、selection / warning / destructive / successを
macOS semantic colorのSwiftUI / AppKit共通Tokenへ集約した。SwiftUI
MaterialとList/Form既定scroll背景はopaqueなchrome / panel /
controlElevatedへ置換した。旧semantic font / color、状態色直書き、
Material、数値radius / spacing / padding、AppKit直書きfont、
`ContentUnavailableView`の再混入は
`UIStateContractTests.testWorkspaceViewsDoNotBypassSharedDesignTokens`で検出する。
この静的証拠は最新ReleaseのHover / Focus / 折返しの目視確認を代替しない。
2026-07-30の1296×768 runtimeではDefault / Selected / Disabled /
Loading相当の主要状態をWelcome、Import、Library、Develop、People、
Map、Compareで確認した。Import method cardでは視覚選択とAX selected
traitの不一致を実際に検出し、装飾badgeをAXから除外してButton自身へ
selected / not-selectedを明示した。PreflightSummary detailにも全項目を
まとめたAX valueを追加した。修正版binaryの最終AX再確認とHover /
Focused / OS accessibility設定別の見た目は手動マトリクスに残す。

## 全状態

| Component | Default | Hover | Pressed | Selected | Focused | Disabled | Loading | Error | Mixed value | Multi-selection |
|---|---|---|---|---|---|---|---|---|---|---|
| WorkspaceSwitcher | E — 4 workspace | OS — segmented Picker | OS — segmented Picker | E — accent segment | OS — keyboard focus | N/A — workspace自体は常時到達可能 | N/A — navigation control | N/A — navigation control | N/A —単一destination | N/A —単一destination |
| GlobalToolbar | E —常設操作 | OS — Button / Menu | OS — Button / Menu | E — workspace / panel / proof状態 | OS — toolbar focus | OS —選択依存操作 | E — task progressを実行中だけ表示 | N/A —詳細errorは該当workspace内 | N/A — command surface | E —複数選択でもExport等を維持 |
| SidebarSection | E —見出し+任意件数+内容（0件数字非表示） | OS — header Button | OS — header Button | E — expanded / collapsed | OS — header focus | N/A — section headerは常時操作可能 | N/A — content側の責務 | N/A — content側の責務 | N/A — navigation section | N/A — navigation section |
| InspectorSection | E —共通header / divider | OS — header / Reset | OS — header / Reset | E — expanded / solo | OS — native controls | E — section enable / Reset | N/A — content側の責務 | N/A — content側の責務 | N/A — section自体には値なし | E —内容がmulti-selection値を受け取る |
| InspectorRow | E —30px共通行 | N/A —表示layout、子Controlが所有 | N/A —表示layout、子Controlが所有 | N/A —値行は選択対象でない | N/A —子Controlが所有 | N/A —子Controlが所有 | N/A —値表示行 | N/A —message componentへ委譲 | N/A —SliderRowへ委譲 | N/A —SliderRowへ委譲 |
| SliderRow | E —label / slider / numeric | OS — Slider / TextField | OS — Slider / TextField | N/A —連続値Control | OS — slider / field focus | OS —親sectionから継承 | N/A —同期処理を待たない | N/A —不正入力は直前値へ復帰 | E —中立track + `—` | E —選択値差分をMixedへ変換 |
| NumericField | E —固定幅monospaced | OS — TextField | OS — TextField | N/A —連続値入力 | E —focus時に実値を入力可能 | OS —親sectionから継承 | N/A —同期入力 | N/A —parse失敗時は直前値へ復帰 | E —未focus時`—` | E —Mixed値編集で全対象へ適用 |
| ToolRailButton | E —40×40 icon | OS — Button | OS — Button | E —accent背景 + Canvas mode bar | OS — native button focus | E —写真未選択時disabled | N/A —tool入口 | N/A —tool結果はInlineErrorへ | N/A —mode選択 | N/A —active photoのtool |
| PhotoCanvasStatusBar | E —zoom / file / RAW状態 | N/A —表示専用 | N/A —内包ControlだけOS | N/A —status表示 | N/A —内包ControlだけOS | N/A —表示専用 | E —asset読込状態 | E —Preview / UnreadableをIcon+Label | N/A —単一Canvas | N/A —単一Active Photo |
| ThumbnailCell | E —photo + states | E —Quick Actions | E —tap / double-click gesture | E —2px selection | E —Active Photo 3px | E —Missing時Quick Actionsなし | E —ProgressView | E —Missing / Preview / Unreadable | N/A —現像値を直接編集しない | E —selection枠 + Control Bar件数 |
| FilmstripCell | E —ThumbnailCell共有 | E —Quick Actions | E —tap gesture | E —2px selection | E —Active Photo 3px | E —Missing時Quick Actionsなし | E —ProgressView | E —Missing / Preview / Unreadable | N/A —現像値を直接編集しない | E —複数選択状態を共有 |
| ReviewControls | E —Rating / Flag / Color | OS — Button / Menu | OS — Button / Menu | E —Picked / Rejected / rating / color名 | OS — native controls | OS —親workspaceから継承 | N/A —即時catalog操作 | N/A —失敗はworkspace messageへ | N/A —離散評価値 | E —共有selectionへ適用 |
| FormatBadge | E —中立形式名 | N/A —表示専用 | N/A —表示専用 | N/A —formatは選択状態でない | N/A —表示専用 | N/A —表示専用 | N/A —loader表示とは分離 | E —Preview warning / Unreadable destructive | N/A —単一format | N/A —cellごとのformat |
| EditStatusBadge | E —Icon+`Edited` | N/A —表示専用 | N/A —表示専用 | N/A —編集済み状態そのもの | N/A —表示専用 | N/A —表示専用 | N/A —保存待ちを示さない | N/A —error badgeではない | N/A —個別asset状態 | N/A —cellごとの状態 |
| MissingStatus | E —Icon+`Missing` | N/A —表示専用 | N/A —表示専用 | N/A —欠落状態そのもの | N/A —表示専用 | N/A —表示専用 | N/A —欠落はloadingでない | E —warning tone + label | N/A —個別asset状態 | N/A —cellごとの状態 |
| LocalOnlyBadge | E —lock icon + text | N/A —表示専用 | N/A —表示専用 | N/A —安全属性 | N/A —表示専用 | N/A —表示専用 | N/A —処理状態でない | N/A —errorでない | N/A —安全属性 | N/A —安全属性 |
| ProgressBanner | E —task名 / status / percentage + safe Cancel | OS —Cancel / detail Button | OS —Cancel / detail Button | E —toolbar detail popover | OS —Button focus | N/A —実行中のみ存在 | E —progress値と読み上げ | N/A —失敗結果はInlineErrorへ | N/A —単一task | N/A —単一task |
| InlineError | E —title / detail / Icon | N/A —表示専用 | N/A —表示専用 | N/A —message | N/A —表示専用 | N/A —表示専用 | N/A —進捗とは分離 | E —warning / destructive / success tone | N/A —message | N/A —message |
| EmptyState | E —0件別文言 + CTA | OS —内包CTA | OS —内包CTA | N/A —選択対象なし | OS —内包CTA | OS —条件未成立時CTA非表示 | E —Loading Photos | E —Missing / 読込不能は別文言 | N/A —値入力なし | N/A —結果0件 |
| PreflightSummary | E —total / new / dup / unsupported | OS —detail Button | OS —detail Button | E —popover open | OS —detail Button | E —preflight前disabled +理由Help | E —Analyze中はfooter progressへ | E —unavailable / warning / naming詳細 | N/A —集計値 | N/A —import item集計 |
| PrimaryFooterBar | E —summary +単一Primary CTA | OS —Button | OS —Button | N/A —footer action | OS —Button focus | E —理由を近接表示 | E —progress + safe Cancel | E —完了 / 警告 / 失敗件数 | N/A —値入力なし | N/A —import item集計 |

## 実装境界

- `WorkspaceSwitcher` は`RAWWorkspaceSwitcher`、`SidebarSection`は
  `RAWSidebarSection`として実装し、Libraryの4節で同じ見出し・件数・
  開閉・Accessibility規約を共有する。開閉値は呼び出し側の
  `AppStorage`で永続化する。
- `InspectorRow`は`RAWInspectorRow`、`ToolRailButton`は
  `RAWToolRailButton`として実装し、30px行高と40×40操作Targetを
  呼び出し側の個別実装から分離する。
- `ThumbnailCell` と `FilmstripCell` は `ThumbnailCellView` を共有する。
- `FormatBadge` は `RAWFormatBadge`、その他の小状態は `RAWStateBadge` と
  Icon+Label規約を共有する。
- `ProgressBanner` はImport Footerの`RAWProgressBanner`（進捗 +
  safe Cancel）と、Global Toolbarの`ToolbarTaskProgressView`
  （詳細Popover入口）を組み合わせる。Importの通常時は
  `RAWPreflightSummary`と`RAWPrimaryFooterBar`を使用する。
- `NumericField` はSlider内の`RAWSliderRow`と、Slider外の
  `rawNumericField`で12pt monospaced、右寄せ、最大桁幅を共有する。
- `EmptyState` は`RAWEmptyState`を共有しつつ、Welcome、filter 0件、
  folder loading、Import source空、People analysis、Canvas loading /
  Missing / unreadableの文言・indicator・CTAを各状態で分ける。
- 見た目、Focus ring、Increase Contrast、Reduce Transparency、accent色別の
  最終判定はsource監査では閉じず、手動マトリクスに残す。
