# RAWDesk Accessibility QA Matrix

対象仕様: `RAWDesk_UI改善書_v1.0-draft.md` §11.2  
状態: 最新sourceの静的確認済み、旧ReleaseのAX一部確認済み。最新Releaseで
macOS設定を切り替える手動マトリクスは未実施
更新日: 2026-07-30

## 無断で変更しないもの

この検証はVoiceOver、Full Keyboard Access、Increase Contrast、Reduce Transparency、accent colorなど、ユーザーのmacOS設定を変更する。明示的な許可と復元手順なしに実行しない。

実施前に現在値をスクリーンショットまたはメモで記録し、各試験後に元の設定へ戻す。Keychain、Chrome、外部アカウントは検証対象外であり、触れない。

## §11.2 requirements 1–8

| ID | Requirement | Implementation / static evidence | Manual status |
|---|---|---|---|
| A1 | 全icon-only controlにLabelとTooltip | Toolbar / Tool Rail / Quick Actions / Control Barをstatic audit。AX label + Help + 28×28以上（Tool Railは40×40）。旧ReleaseのAX treeで主要5操作を確認 | 最新Release手動確認待ち |
| A2 | Tab / Shift-Tabの予測可能なFocus順と視認Focus Ring | View順をSidebar→Control Bar→Center→Inspector→Bottomに構成。裸Tabをpanel toggleに不使用 | Full Keyboard Access手動確認待ち |
| A3 | Workspace / Selection / Active Photo / Tool ModeをVoiceOver通知 | accessibility announcementを実装 | VoiceOver音声確認待ち |
| A4 | Rating / Flag / Colorを色だけに依存しない | 星数、Flag label、色名textを提供 | 各accent色手動確認待ち |
| A5 | Gamut Warningの文字凡例 | Red / Blue / Purpleの意味をPopover/Helpに表示 | Contrast設定手動確認待ち |
| A6 | Error / Warning / SuccessをIcon+Labelで区別 | 状態componentとImport結果に実装。RAWは通常`ARW`、fallbackは`ARW · Preview`、失敗は警告icon付き`Unreadable`として文字でも区別 | Contrast設定手動確認待ち |
| A7 | 全SliderがArrow / Shift+Arrow / 数値入力対応 | source上9個すべてにkeyboard modifierと直接入力 | キーボード実操作待ち |
| A8 | Reduce Motionで即時切替 | Reduce Motion environmentに応じてanimation無効 | OS設定手動確認待ち |

最新sourceはSwiftUI Materialを使用せず、chrome / panel / controlElevatedの
opaque背景へ統一し、List / Formも既定scroll背景を隠している。空状態は
`RAWEmptyState`、数値入力は共有12pt monospaced表示へ統一した。これは
Reduce Transparency時の透過残りと文字階層の揺れを減らすsource上の対策であり、
PopoverやOS標準Controlを含む実画面判定はDA-03以降で行う。

## Test sizes

| Size ID | Window size | Notes |
|---|---:|---|
| S1 | 1100×700 | 最小サイズ。横scroll、重なり、Done/Cancel、Import Footerを重点確認 |
| S2 | 1296×768 | 標準。Library中央幅≥720px、Toolbar labelを確認 |
| S3 | 1440×900 | 3 pane + Filmstrip、主要Toolbar labelを確認 |
| S4 | 1728×1117 | 実行環境で可能な場合。現Macでは作業領域が1718×1024へclamp |

## Accent variants

最低限、次を含める。

| Accent ID | Setting |
|---|---|
| C1 | Blue |
| C2 | Purple |
| C3 | Graphite |
| C4 | ユーザーが常用する別accent色 |

## Screen/state set

全設定×全サイズで全画面を網羅すると検証量が非常に大きいため、次の代表状態を固定し、問題が出た設定だけ隣接画面へ展開する。

| State ID | State | Primary checks |
|---|---|---|
| V1 | Empty / Welcome | CTA、Drop Zone、原本保護文、focus order |
| V2 | Library Grid + Inspector | Toolbar、thumbnail states、Quick Review、divider |
| V3 | Library Loupe | Filmstrip、rating/flag/color、status |
| V4 | Develop default | Histogram固定、Light/Color、Slider/NumericField |
| V5 | Develop Crop mode | Tool Rail、mode announcement、Done/Cancel |
| V6 | Soft Proof ON | profile、gamut warning legend、状態非色依存 |
| V7 | Import Move | radio cards、安全文、warning、Footer |
| V8 | Compare / Survey / Reference | role label、shared review controls、Done |
| V9 | People / Map | local-only/privacy copy、非色依存status |

## Manual matrix — VoiceOver

VoiceOverをONにし、各サイズで代表状態を確認する。

| Run | Size | State | Reading order | Control name/value/help | Announcement | Result | Notes |
|---|---|---|---|---|---|---|---|
| VO-01 | S1 | V1 |  |  |  | 未実施 |  |
| VO-02 | S1 | V2 |  |  |  | 未実施 |  |
| VO-03 | S1 | V4/V5 |  |  |  | 未実施 |  |
| VO-04 | S1 | V7 |  |  |  | 未実施 |  |
| VO-05 | S2 | V2/V3 |  |  |  | 未実施 |  |
| VO-06 | S2 | V4/V6 |  |  |  | 未実施 |  |
| VO-07 | S3 | V8/V9 |  |  |  | 未実施 |  |
| VO-08 | S4* | V2/V4 |  |  |  | 未実施 | *可能な作業領域で実施 |

確認操作:

1. ⌘1〜4でWorkspaceを切り替え、Workspace名が通知される。
2. Gridで選択とActive Photoを変更し、filenameと状態が通知される。
3. Cropを開始・Cancelし、Tool Modeの入退場が通知される。
4. Rating / Flag / Colorの名前と現在値を読み上げる。
5. DividerとSliderがadjustable controlとして値を読み上げる。
6. Error / Warning / Successが色名だけではなく意味として読める。

## Manual matrix — Full Keyboard Access

| Run | Size | State | Tab order | Shift-Tab | Focus ring | Shortcut conflict | Result | Notes |
|---|---|---|---|---|---|---|---|---|
| KB-01 | S1 | V1 |  |  |  |  | 未実施 |  |
| KB-02 | S1 | V2/V3 |  |  |  |  | 未実施 |  |
| KB-03 | S1 | V4/V5 |  |  |  |  | 未実施 |  |
| KB-04 | S1 | V7 |  |  |  |  | 未実施 |  |
| KB-05 | S2 | V2/V4 |  |  |  |  | 未実施 |  |
| KB-06 | S3 | V8/V9 |  |  |  |  | 未実施 |  |
| KB-07 | S4* | V2/V4 |  |  |  |  | 未実施 | *可能な作業領域で実施 |

重点操作:

- Tab / Shift-TabでSidebar→Control Bar→Center→Inspector→Bottomへ移動する。
- Focus ringが暗背景、写真背景、選択accentの上で識別できる。
- Sliderは←→で微調整、Shift+←→で粗調整、数値欄から直接入力できる。
- G / E / Space / Return / keypad Enter / D / ⌘1–4 / ⌘⌥S / ⌘⌥I / ⌘⌥F / ⌘⌥0が文字入力中に発火しない。
- Space / Return / keypad EnterはLibraryで写真選択中のみGrid⇄Loupeに使われ、focused buttonと他Workspaceの既定操作を奪わない。
- CropのEnter/Done、Escape/Cancelが常に到達可能である。

## Manual matrix — Display accommodations

各RunはS1、S2、S3、可能ならS4でV1〜V9の代表箇所を確認する。

| Run | Increase Contrast | Reduce Transparency | Reduce Motion | Accent | Sizes | Result | Notes |
|---|---|---|---|---|---|---|---|
| DA-01 | OFF | OFF | OFF | C1 | S1–S4 | 未実施 | Baseline |
| DA-02 | ON | OFF | OFF | C1 | S1–S4 | 未実施 | divider、field、focus、badge |
| DA-03 | OFF | ON | OFF | C1 | S1–S4 | 未実施 | Toolbar、sheet、popover、panel |
| DA-04 | ON | ON | OFF | C1 | S1–S4 | 未実施 | 複合設定 |
| DA-05 | OFF | OFF | ON | C1 | S1–S4 | 未実施 | Accordion、mode transition |
| DA-06 | ON | ON | ON | C1 | S1–S4 | 未実施 | 最厳条件 |
| DA-07 | ON | ON | ON | C2 | S1–S4 | 未実施 | Purple |
| DA-08 | ON | ON | ON | C3 | S1–S4 | 未実施 | Graphite |
| DA-09 | ON | ON | ON | C4 | S1–S4 | 未実施 | 常用accent |

各Runで確認すること:

- 文字、divider、field境界、selection、focus ringが識別可能
- panel、sheet、popoverが背景から分離
- RAW format badgeとwarning/error/successが混同されない
- selected / active / suggested / confirmedを色なしでも区別可能
- Increase Contrastでlayoutが崩れない
- Reduce Transparencyで不自然な透過残りがない
- Reduce MotionでAccordionとmode transitionが即時に切り替わる
- 1100×700で横scroll、文字重なり、切れ、非表示操作がない

## Result notation

- `Pass`: 補助設定下でも操作と意味理解が成立
- `Fail`: 操作不能、読み上げ欠落、色だけに依存、focus不明、layout崩れのいずれか
- `Blocked`: OSまたは検証環境により実行できない。理由を必ず書く
- `N/A`: 該当しない。理由を必ず書く

## Restoration

検証終了後:

1. VoiceOverを元の状態へ戻す。
2. Full Keyboard Accessを元の状態へ戻す。
3. Increase Contrast、Reduce Transparency、Reduce Motionを元の状態へ戻す。
4. accent colorを元の値へ戻す。
5. RAWDeskを終了する。
6. `scripts/run-isolated-ui-qa.sh --cleanup`を実行し、QA app / home /
   support / `local.rawdesk.app.uiqa` preference domainだけを削除する。
   `HOME` / `CFFIXED_USER_HOME` /
   `RAWDESK_SUPPORT_DIRECTORY_OVERRIDE`が親shellへ残っておらず、
   通常の`local.rawdesk.app` preference domainが不変であることを確認する。

## Acceptance

§11.2-9の合格には、全実施行が `Pass` または理由付き `N/A` であることが必要。`Fail` または説明のない `Blocked` が1件でもあれば未合格とする。
