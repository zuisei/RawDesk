# RAWDesk UI改善案 — Lightroom的操作性への整合

**目的:** 機能を増やさず、既存機能の**操作性と視覚的規律**をLightroom Classicの慣習に寄せる。
**前提:** `RAWDesk UI改善書 v1.0-draft`の要件はsource上実装済み
（`Docs/RAWDesk_UI_REDESIGN_IMPLEMENTATION.md`）。本書はその**次段階**であり、
既存仕様の否定ではない。
**根拠:** 現行releaseの実画面（`Evidence/2026-07-30/ui-spec-runtime/`）と現行source。
**状態:** **実装済み・実画面確認済み（2026-07-30）**。A〜K の11項目に加え、
指摘を受けた module picker の作り替えを適用した。
`swift build` / `swift test` 355件 0 failures / release app bundle /
隔離起動での目視・操作確認まで実施。目視QAで見つかった不具合2件も修正済み。§5に詳細。
**日付:** 2026-07-30

> 本書は**新機能を提案しない**。すべての項目は、既に存在する機能・値・
> componentの**配置、表現、既定値**の変更である。新しいpanelや新しい編集
> parameterは一つも追加しない。

---

## 0. 中心となる診断

Lightroomの視覚的規律は一つの原則に集約される — **画面上で彩度を持つ物体は
写真だけ**。chromeは明度差と細い1pxのインジケータで状態を伝える。

RAWDeskは配色token自体は正しく階層化されている（`canvas` 18,19,21 <
`chrome` 26,28,31 < `panel` 32,35,40 — `RAWDeskDesignSystem.swift:6-20`）。
問題は明度階層ではなく、**その上に載る彩度**である。

`selection = Color.accentColor`（`RAWDeskDesignSystem.swift:37`）が、
system accent（既定で鮮やかな青）として次のすべてを塗っている:

- Develop右panelの**12本以上のslider track**（`:1150-1157`）
- Library の Grid / Loupe segmented control の塗り
- 右panel の Quick Review / Info tab の塗り
- 「Edit in Develop」「Add to Quick Collection」の塗り

結果として、`07-library-grid-current-release.png`では**3枚の写真より3つの青い
UI要素が先に目に入る**。`11-develop-current-release.jpg`では、写真の右隣に
飽和した青い横棒が12本並ぶ。これが「デザイン性」として最も損をしている箇所で、
**修正は単一tokenと1行の条件式**で始まる。

canvasとpanelの明度差が14/255しかないことも、写真の領域が最も暗い面である
という関係を弱めている。tokenの順序は正しいので、差を広げるだけでよい。

---

## 1. 操作性の項目別提案

各項目は「現状（根拠付き）」「Lightroomの慣習」「提案」「変更対象」で構成する。
優先度は**設計上の効果の大きさ**順。

---

### A. アクセント色の規律を戻す ★最優先

**現状**
`selection = Color.accentColor`（`RAWDeskDesignSystem.swift:37`）。
slider tintは`usesNeutralTint ? textSecondary : selection`（`:1150-1157`）で、
その`usesNeutralTint`は**`isMixed`のときだけtrue**（`:1087`）。
つまり通常の単写真編集では全sliderがaccent塗り。

**Lightroomの慣習**
slider trackは無彩色の細い溝。値が動いても色は変わらない。
選択状態はpanelの明度差と細い枠線で示し、塗りは使わない。

**提案**
1. `usesNeutralTint`の既定を反転する。**既定を無彩色**とし、accentは
   「今フォーカスしているslider」だけに限定する。`isMixed`の`—`表示は現状維持。
   無彩色tintの経路は既にあるので配線は不要だが、`RAWSliderPresentation`は
   slider側のfocus状態を現状受け取っていない（`:1106-1111`は
   `value`/`isMixed`/`format`のみ）ため、その受け渡しが1つ増える。
2. `selection`を彩度の低い値に置き換える。`Color.accentColor`直参照をやめ、
   固定の低彩度青（例: 92,124,168程度）にすると、systemのaccent設定に
   引きずられて画面が突然赤や紫に染まる事故もなくなる。
3. 塗りで示している選択状態を明度差＋1pxのインジケータに置き換える
   （Grid/Loupe segmented、Quick Review/Info tab）。
4. accentの塗りを許すのは**画面内で最も重要な1つのCTAのみ**とする。
   Libraryでは「Edit in Develop」。「Add to Quick Collection」は
   secondary扱いにして塗りを外す。
5. `canvas`をあと6〜8/255暗くし、写真領域とpanelの分離を明確にする。

**変更対象**
`Sources/RAWDesk/Views/RAWDeskDesignSystem.swift:6-10`（canvas）、`:37`（selection）、
`:1087`（usesNeutralTint）、`:1150-1157`（tint適用）

**効果**
1ファイルの数行で、Library / Develop / People / Map / Compare の全画面に効く。
本書で最も投資効率が高い。

---

### B. 同じデータに2つの操作語彙がある ★最優先

**現状**
評価・pick・color labelの操作が、**tabによって別のcontrolになる**。

| フィールド | Quick Review tab | Info tab |
|---|---|---|
| Rating | `☆ Rate ⌄` テキストボタン | 金色star×5（直接クリック） |
| Pick | `⚐ Pick` / `⊗ Reject` テキストボタン | `Pick status` dropdown |
| Favorite | （なし） | toggle switch |
| Color | `◎ Color ⌄` テキストボタン | `Color label` dropdown |

根拠: `07-library-grid-current-release.png`（Quick Review）と
`10-library-loupe-current-release.jpg`（Info）。同一の写真属性に対して、
片方はテキストボタン、片方はstar / toggle / dropdownである。

**Lightroomの慣習**
flag・star・color labelは**どこでも同一のグリフ**で、常に直接クリックできる。
dropdownやtoggle switchは使わない。キーボードは`P`/`X`/`U`、`1`–`5`、`6`–`9`。

**提案**
1. 共有componentを1つ作り（`RAWRatingControl`）、両tabと
   thumbnail cellとfilmstripで同じものを使う。star常にstar、pick常にflag、
   color常に色swatch。
2. `Pick status` dropdownと`Favorite` toggleを廃止し、flag glyphの直接クリックに統一。
   Favoriteはpick flagと意味が重複しているので、**表示を1つに寄せる**
   （データモデルは変更しない）。
3. dropdownの`None ⌄`は、色swatch列＋選択中に細枠、に置き換える。

**変更対象**
`Sources/RAWDesk/Views/PhotoInspectorView.swift`、
`Sources/RAWDesk/Views/MetadataInspectorView.swift`、
`Sources/RAWDesk/Views/RAWDeskDesignSystem.swift`（共有control追加）

**注意**
これはデータモデルの変更ではない。`PhotoUserState`はそのまま。
表示と入力の語彙を1つに揃えるだけである。

---

### C. Grid に filmstrip がない

**現状**
filmstripは**LoupeとDevelopにはあるが、Gridにはない**。
Loupe: `10-library-loupe-current-release.jpg`、Develop: `11-develop-current-release.jpg`。
実装は`WorkspaceShellViews.swift:376,419`（Library側）と`:1223`（Develop側）。
Grid（`07-library-grid-current-release.png`）の下端はstatus barのみ。

**Lightroomの慣習**
filmstripは**全moduleで常設**。Grid moduleでも下端に出る。
これにより「今どの範囲を見ているか」がmodule間で連続する。

**提案**
Gridでもfilmstripを表示する。token（`Size.libraryFilmstrip: 128`,
`libraryFilmstripRange`）とdivider（`:434-441`）は既にあるので、
表示条件を広げるだけでよい。
Gridとfilmstripが同じ写真を二重に見せることになるが、これはLightroomでも
同じで、役割が違う（Grid=選別のための面、filmstrip=移動のための帯）。

**変更対象**
`Sources/RAWDesk/Views/WorkspaceShellViews.swift:376-449`

---

### D. 右panelがtabではなく積層collapsibleであるべき

**現状**
`Quick Review` / `Info` の2 tab（`07-...png`, `10-...jpg`）。
tabなので、片方を見ている間もう片方は完全に隠れる。

**Lightroomの慣習**
右panelは**積層した折りたたみpanel**。Libraryなら
Histogram → Quick Develop → Keywording → Keyword List → Metadata。
複数を同時に開ける。Option-clickで1つだけ開く solo mode。

**提案**
1. tabを廃し、`Quick Review`の内容と`Info`の内容を積層collapsible sectionにする。
   `RAWSidebarSection`（`RAWDeskDesignSystem.swift:188`）が既にあるので流用できる。
2. 開閉状態を`@AppStorage`で永続化（既に`rawdesk.ui.*`の前例がある）。
3. section headerのOption-clickで solo mode。

**変更対象**
`Sources/RAWDesk/Views/PhotoInspectorView.swift`、
`Sources/RAWDesk/Views/ContentView.swift`

---

### E. Navigator が preview になっていない

**現状**
Developの左panel冒頭は`Section("Navigator")`（`ContentView.swift:1893`）だが、
中身は**テキストのみ** — ファイル名、`Sony ARW · RAW`、`ILCE-7M4`、レンズ名。
画像preview要素は含まれていない（`:1893-1938`を確認）。

**Lightroomの慣習**
Navigatorは左panel最上段の**loupe preview**で、`Fit` / `Fill` / `1:1` / `2:1`の
zoom presetを持つ。拡大中は表示範囲の枠を示す。

**提案**
1. Navigatorの中身をpreview画像にする。`ImageCache`のpreviewは既に存在するので
   新しい生成処理は不要。
2. 現在テキストで出している camera / lens は、Navigatorの下か既存のInfoへ移す。
   `Navigator`というラベルの下にメタデータが並ぶ現状は名前と中身が合っていない。
3. canvas status barに既にある`Fit  100%`（`11-...jpg`左下）とzoom presetを連動させる。
   新しい機能ではなく、既にある2つの表示を1つの操作に繋ぐ。

**変更対象**
`Sources/RAWDesk/Views/ContentView.swift:1893-1938`

---

### F. Soft Proof が3箇所にある

**現状**
同一機能のcontrolが3つの独立したviewに存在する:

| 場所 | 実装 |
|---|---|
| global toolbar 右上 | `ToolbarContent.swift:223` |
| 画像上の control bar | `WorkspaceShellViews.swift:1457` |
| 右panel の toggle | `EditingInspectorView.swift:2120` |

`11-develop-current-release.jpg`で3つ同時に見える。

**Lightroomの慣習**
Soft Proofingは Histogram 直下のチェックボックス**1箇所**のみ。

**提案**
右panel（`EditingInspectorView.swift:2120`、histogram直下）に一本化し、
global toolbarとimage control barから外す。
画像上のcontrol barは`Before / After`だけに絞る。
キーボード`S`（`ToolbarContent.swift:227`の`.help`が示す）は維持する。

**変更対象**
`Sources/RAWDesk/Views/ToolbarContent.swift:223-227`、
`Sources/RAWDesk/Views/WorkspaceShellViews.swift:1457`

---

### G. 双極sliderが左端から塗られている

**現状**
sliderは素のSwiftUI `Slider`（`RAWDeskDesignSystem.swift:1134-1138`）。
SwiftUIのSliderは**常に range の最小値から**塗る。
Exposure・Contrast・Highlights・Temperature等は`-100...100`（`:1094`）の双極値なので、
0のときに「左半分が塗られた」状態に見える。`11-...jpg`の12本すべてがこの状態。

**Lightroomの慣習**
双極パラメータは**中央（0）から**左右に塗る。0の位置にtickがある。
一目で「どちら側にどれだけ振ったか」が分かる。

**提案**
中央原点のcustom trackにする。`resetValue`が既に`0`（`:1096`）なので
原点の値は既知で、追加のデータは要らない。0位置にtick markを置く。

**既にLightroom準拠なので維持する点**
double-clickでreset（`:1158-1160`）と、キーボードでの増減
（`.rawKeyboardAdjustableSlider`, `:1139-1143`）は既に正しい。変更しない。

**変更対象**
`Sources/RAWDesk/Views/RAWDeskDesignSystem.swift:1134-1160`

---

### H. 数値fieldの箱が12個並んで重い

**現状**
値のTextFieldに`controlElevated`の背景と角丸が常時付く
（`RAWDeskDesignSystem.swift:1182-1190`）。sliderが12本あれば箱も12個。

**Lightroomの慣習**
値は右寄せのplain text。hoverでscrubbable（左右dragで増減）、clickで編集。
枠は編集中のみ。

**提案**
既定を背景なしのplain textにし、hoverとfocus時のみ`controlElevated`を出す。
幅（`:1173`の58pt）とmonospacedDigit（`:1170`）は維持。

**変更対象**
`Sources/RAWDesk/Views/RAWDeskDesignSystem.swift:1161-1191`

---

### I. 全cellに「Unrated」と書かれている

**現状**
Grid cellとfilmstrip cellの全てに`Unrated`のテキストラベル
（`07-...png`の3枚、`10-...jpg`と`11-...jpg`のfilmstrip）。

**Lightroomの慣習**
未評価は**何も表示しない**。評価済みのみstarを出す。
情報がないことを文字で主張しない。

**提案**
unratedのときラベルを出さない。評価済みのときのみstar glyphを出す。
cellの下端が空くので、そのぶんサムネイルを大きく使える。

**変更対象**
`Sources/RAWDesk/Views/ThumbnailCellView.swift`

---

### J. Grid にサムネイルサイズ調整がなく、下方が死んでいる

**現状**
`07-library-grid-current-release.png`は写真3枚で、grid領域の**下2/3が空白**。
サムネイルサイズを変える操作が画面上にない。

**Lightroomの慣習**
Grid下端のtoolbarに**thumbnail sizeのslider**がある。列数が連続的に変わる。

**提案**
既存の canvas status bar（`Size.canvasStatusBar: 28`、`07-...png`の
`3 photos … 1 selected`の帯）にsize sliderを追加する。
新しいbarは作らない。既にある帯の空きを使う。

**変更対象**
`Sources/RAWDesk/Views/WorkspaceShellViews.swift`、
`Sources/RAWDesk/Views/ThumbnailGridView.swift`

---

### K. 縦のtool railが無ラベルで意味が読めない

**現状**
Develop左、panelと画像の間に5つのアイコンだけの縦列
（`Size.toolRail: 40`、`11-...jpg`のx≈266）。
crop以外はアイコンから機能が推測しにくく、選択状態も弱い。

**Lightroomの慣習**
tool群は右panelのHistogram直下に**ラベル付きの横列**で並ぶ
（Crop Overlay / Spot Removal / Graduated / Radial / Brush）。
選択すると、そのtoolのオプションがすぐ下に開く。

**提案**
いずれか一方。Bを推奨する。

- **A案**: railを残し、hover tooltipと選択状態（背景＋左端2pxのindicator）を明確化。変更は小さい。
- **B案（推奨）**: tool群を右panel上部へ移し、ラベルを付ける。選択時にそのtoolの
  設定を直下に展開する。Lightroomの操作順序（tool選択 → 直下で調整 → 確定）に一致し、
  視線が画面を横断しない。railは廃止して画像領域が40pt広がる。

**変更対象**
`Sources/RAWDesk/Views/WorkspaceShellViews.swift`、
`Sources/RAWDesk/Views/EditingInspectorView.swift`、
`Sources/RAWDesk/Views/RAWDeskDesignSystem.swift:110`（`toolRail`）

---

## 2. 既にLightroom準拠であり、変更しない点

改善案が既存の良い判断を壊さないよう明記する。

- **module picker**（Library / Develop / People / Map、上部中央）— Lightroomの
  module構造と同じ考え方で、位置も適切。
- **slider の double-click reset**（`RAWDeskDesignSystem.swift:1158-1160`）— Lightroom同様。
- **slider のキーボード増減**（`:1139-1143`）。
- **Develop の filmstrip**（`WorkspaceShellViews.swift:1223`）— 存在自体は正しい。
- **histogram の clipping三角**（`11-...jpg`右上）— Lightroomと同じ位置と役割。
- **`Fit  100%` のzoom表示**（canvas status bar左）。
- **token階層そのもの**（`canvas` < `chrome` < `panel` < `controlElevated`）—
  順序は正しい。A案で差を広げるだけで、設計を変える必要はない。
- **Mixed値の `—` 表示**（`:1079-1086`）— 複数選択時の表現として妥当。

---

## 3. 適用順序

視覚的効果と実装コストの比で並べた。前半3つで印象の大半が変わる。

| 順 | 項目 | 対象ファイル数 | 効果範囲 |
|---|---|---|---|
| 1 | **A. アクセント色の規律** | 1 | 全画面 |
| 2 | **G+H. slider の中央原点と数値field** | 1 | Develop / 全inspector |
| 3 | **I. Unrated ラベル除去** | 1 | Grid / filmstrip / Compare / Survey |
| 4 | **B. 評価controlの語彙統一** | 3 | Library 右panel全体 |
| 5 | **F. Soft Proof の一本化** | 2 | Develop |
| 6 | **C. Grid の filmstrip** | 1 | Library |
| 7 | **E. Navigator を preview 化** | 1 | Develop |
| 8 | **D. 右panel を積層collapsible化** | 2 | Library 右panel |
| 9 | **J. thumbnail size** | 2 | Library Grid |
| 10 | **K. tool rail** | 3 | Develop |

1〜3は`RAWDeskDesignSystem.swift`と`ThumbnailCellView.swift`だけで完結し、
機能に触れないため回帰リスクが小さい。**ここだけ先に入れて実画面で確認する**のを勧める。

**2はGとHに分割できる。** Hは`controlElevated`背景を条件付きにするだけの数行で、
Gは素の`Slider`をcustom trackに置き換える必要がある。最短で見た目を変えたい場合、
**HをGより先に入れる**とよい。効果の大半はA（無彩色化）とHで出る。

**K（tool rail）はA案とB案の選択が必要。** B案を推奨しているが、Developで手が
動く位置が変わるため、実装前に判断を仰ぎたい唯一の項目である。

---

## 4. 検証について

既存の受け入れ体制をそのまま使える。

- 変更後は`Evidence/2026-07-30/ui-spec-runtime/`と同じ画面・同じ解像度
  （1296×768、1100×700）で撮り直し、before/afterを並べる。
- token逸脱を止める自動試験が既にある
  （`Docs/RAWDesk_UI_REQUIREMENT_TRACEABILITY.md`の「現在残っている証明」）。
  A案でtokenの値を変える場合、その試験は**値ではなくtoken経由であること**を
  見ているので、通り続けるはずである。実行して確認すること。
- B案とD案はaccessibility traitに影響する。`Docs/RAWDesk_ACCESSIBILITY_QA_MATRIX.md`の
  該当行を再実施する必要がある。
- 実画面確認を行う場合は`scripts/run-isolated-ui-qa.sh`を使う。通常の
  catalog・preference domainから隔離される。

---

## 5. 実装結果（2026-07-30）

11項目すべて適用済み。検証は `swift build`、`swift test`（355件 0 failures、
baselineは354件 — 新規テスト1件追加）、`scripts/build-app.sh` による
release bundle まで。

### 実装中に判明した本書の誤り — J

**J（サムネイルサイズ操作が画面上にない）は誤りだった。** 操作は
`WorkspaceShellViews.swift` の Library control bar に既に存在していた。
ただし `ViewThatFits` の中にあり、**最初に切り捨てられる要素**だったため、
1296×768 では "View Actions" menu の中へ退避していた。screenshotに写って
いなかったのはそのためで、「存在しない」ではなく「狭い窓では消える」が正しい。

対応は変更した。新規追加ではなく、grid直下の status bar へ**移動**した
（`RAWLibraryStatusBar`）。Lightroomと同じ位置で、かつ幅に関係なく常に
出る。既存の pixel 数値入力も一緒に移し、機能は失っていない。

### 主要な変更点

| 項目 | 変更 |
|---|---|
| A | `canvas` 18,19,21 → 10,11,12。`selection` を `Color.accentColor` から固定の低彩度青(92,124,168)へ。app rootに `.tint(...)` を追加し、native controlのsystem accent塗りも抑制。`usesNeutralTint` の既定を反転し accent は操作中の1本のみ。 |
| B | `RAWReviewControls` を star直接クリック＋flag＋色swatchへ統一。`RAWStarRating` を共有componentとして design system へ。Info tabの Pick dropdown / Favorite toggle / Color dropdown を廃止。Compare / Survey / Reference も同じcomponentなので同時に揃った。 |
| C | Grid にも filmstrip。`isDevelopFilmstripVisible` を `isFilmstripVisible` へ一般化し、⌥⌘F が Library でも効くようにした（`@AppStorage` key は互換のため変更せず）。 |
| D | Quick Review / Info の tab を廃止。既存の `RAWInspectorSection`（Option-clickのsolo modeを既に持っていた）を流用して積層collapsibleへ。開閉状態は `@AppStorage` に永続化。 |
| E | Navigator を `viewer.image` の実preview＋Fit/100%へ。camera / lens は "Camera" section へ分離。 |
| F | Soft Proof を右panel 1箇所へ。global toolbar と image control bar から削除。gamut warning と legend は Proof Settings popover に同一内容が既にあったため情報は失っていない。`S` shortcut と proof状態badgeは維持。 |
| G | 中央原点の `RAWSliderTrack` を新設。native `Slider` は `.opacity(0)` で上に重ね、drag・keyboard・VoiceOver・28pt targetを維持。0位置にtick。 |
| H | 数値fieldの `controlElevated` 背景を hover / focus 時のみに。 |
| I | `Unrated` ラベルを削除（`ThumbnailCellView`）。 |
| J | 上記のとおり status bar へ移動。 |
| K | B案。tool群を Develop inspector の histogram直下へラベル付き横列で移動。`RAWToolRailButton` に `caption` を追加して共有componentのまま使用。縦railを廃止し画像領域が40pt広がった。 |

### 実装中に自分で見つけて直した回帰

`RAWReviewControls` の `compact` を無視して書いてしまい、Survey / Compare /
Reference の狭いoverlayで幅が約2倍になっていた（旧: icon 4個 ≈112pt、
新: star5＋flag2＋swatch5 ≈220pt）。`compact` 時に glyph と間隔を詰める形に
修正し、5段階評価と5色すべて操作可能なまま元の幅感に戻した。
機能を削って幅を稼ぐ選択はしていない。

あわせて `Spacing.xxSmall`(2pt) を追加した。1つのcontrol内で隣接する
glyph同士の間隔で、`xSmall`(4pt) だと別のcontrolに見えるため。

### 更新したテスト

設計意図が変わったため、**通すためではなく意図を書き換える形で**更新した。

- `testDesignTokensMatchTheImprovementSpecification` — `canvas` の新値、
  `selection` を `assertSystemColor`(controlAccent) から固定値の
  `assertColor` へ。slider / rating の新token 6件を追加。
- `testConcreteSliderPresentationKeepsFormattedValue` — 待機中のsliderは
  無彩色が正、へ反転（`XCTAssertFalse` → `XCTAssertTrue`）。
- `testActiveSliderIsTheOnlyOneAccented` — 新規。操作中のみaccent、
  かつ Mixed は操作中でも無彩色であることを固定。
- `testWorkspaceViewsDoNotBypassSharedDesignTokens` — 「Develop tools must
  use the shared ToolRailButton」の対象を `WorkspaceShellViews.swift` から
  tool群の移動先 `EditingInspectorView.swift` へ。契約は削除していない。

### 実画面QAで見つけて直した不具合（2026-07-30、`run-isolated-ui-qa.sh`）

buildとtestを通過していたが、実際に触って初めて分かった不具合が2件あった。
どちらも自動テストでは検出できない種類のもので、目視QAの価値を示している。

1. **sliderが完全に動かなかった（ユーザー報告）。** G の実装で native `Slider`
   を `.opacity(0)` で隠して上にcustom trackを描いていたが、**SwiftUIは完全に
   透明なviewをhit testしない**ため、click も drag も一切届かなかった。
   見た目は正しく、値も正しく表示されるのに操作だけが死んでいる状態。
   修正: native `Slider` を不透明のまま**下**に置き、custom trackを
   `.allowsHitTesting(false)` で**上**から不透明に被せる構成へ変更。
   これで click-to-set / drag / keyboard / VoiceOver がすべて native の
   ままになる。drag と double-click reset を実画面で確認済み。
2. **右panelで「Reject」が2行に折返していた。** 統一controlが
   star5＋Pick＋Reject＋swatch5 でinspector幅を超えていた。
   修正: pick / reject をglyphのみに（Lightroomのflagと同じ）。
   語彙統一の意図とも整合し、幅も収まった。文言はhelpと
   accessibility labelに残している。

### 追加変更 — module picker（ユーザー指摘）

`Library / Develop / People / Map` は native `.pickerStyle(.segmented)` で、
選択中がpillとして塗られていた。pillは「今いる場所」ではなく「押すボタン」に
見えるため、Lightroomの流儀ではない、という指摘。

`RAWWorkspaceSwitcher`（`ToolbarContent.swift:85`）を、現在のmoduleだけ
明るいsemibold・他は暗いregular・区切りはhairlineのみ、という素のテキスト表現に
作り替えた。pillは廃止。accessibilityは `.isSelected` traitで表現している。

### 実画面で確認できた項目

`scripts/run-isolated-ui-qa.sh` で隔離起動して確認済み:

- A — slider trackが無彩色、accentの塗りが消えている
- G — 0のsliderは中央にknob・fillなし。Contrastをdragすると中央tickから
  knobまでfillが伸びる。double-click resetも動作
- H — 数値が箱なしのplain textで表示
- I — grid cell / filmstrip cell に `Unrated` が出ない
- B — star5＋flag2＋swatch5が1行の統一controlとして表示
- D — `Keywording`（展開）/`Metadata`（折畳）の積層collapsible。tabは無い
- C — Grid下端にfilmstripが出る
- E — Navigatorが実preview＋`Fit`/`100%`、Cameraは別section
- F — Soft Proofは右panelのみ。image control barは `Before / After` だけ
- J — status barにサイズsliderと数値（256）
- K — histogram直下に `Crop / Heal / Mask / Upright / Color` のラベル付き
  横列。5個とも折返さずに収まる。縦railは無い

### 未確認として残っている項目

- 1100×700 など狭い window での縦方向の圧迫（Grid filmstripを足した影響）
- `MetadataInspectorView` を `isEmbedded: true` で埋めた際の長い metadata の
  scroll 挙動
- VoiceOver / Full Keyboard Access / Increase Contrast の実設定での確認
  （`Docs/RAWDesk_ACCESSIBILITY_QA_MATRIX.md` の該当行）

`Evidence/2026-07-30/ui-spec-runtime/` と同じ画面・同じ解像度で撮り直して
before/after を並べる作業も未実施。

### 隔離の実際の範囲（重要）

`run-isolated-ui-qa.sh` は catalog / support / preference domain を
`/tmp/rawdesk-isolated-ui-qa` へ隔離する。今回それは機能していた
（catalogは `/tmp/.../support/catalog.sqlite` に作られた）。

ただし**起動したQAアプリは実際の写真フォルダ
`<ユーザーの写真フォルダ>` を root として184枚を索引した**。
隔離されるのはRAWDesk自身の保存先であって、**写真そのものは実データを読む**。
読み取りのみで、Import の Copy / Move は実行していないため originals は
変更していないが、「完全に隔離」という表現は正確ではない。

---

## 6. 本書が扱っていないこと

- **新機能**: 一つも提案していない。すべて既存の値・component・表示の再配置。
- **安全性に関わるUI**: Auto Importの削除確認、Relinkの成功メッセージ、
  export時のembedded preview警告などは、性質が異なるため
  `Docs/RAWDESK_P0_VERIFICATION.md`に分離してある。本書と独立に扱える。
- **外部の改善書**: `~/Downloads/RAWDesk_UI改善書_v1.0-draft.md`は
  リポジトリ外のため参照していない。本書はリポジトリ内のsourceと
  実画面証拠のみを根拠にしている。
- **実装**: 本書作成時点で`Sources/`は変更していない。
