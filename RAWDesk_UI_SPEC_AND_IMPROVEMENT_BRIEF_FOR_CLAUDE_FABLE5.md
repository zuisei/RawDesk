# RAWDesk UI仕様・改善ブリーフ

Claude / Fable 5 に渡すための現行仕様整理と、UI改善提案の依頼書

- 対象アプリ: RAWDesk
- 現行バージョン: 0.1.1（build 2）
- 対象OS: macOS 14以降
- 現行実装: Swift / SwiftUI + AppKit
- 現行画面の確認日: 2026-07-29
- リポジトリ: `.`

---

## 0. Claude / Fable 5 への依頼

以下の現行製品仕様、実画面、制約を読んだうえで、RAWDeskのUI改善書を作成してください。

最初の回答では、いきなりコードを書かず、次を提出してください。

1. 現行UIの問題を、情報設計・操作導線・視覚階層・アクセシビリティに分けて診断する
2. 改善後の画面構造と、Library / Develop / Import / People / Mapの役割を定義する
3. 主要画面のワイヤーフレームまたは画面構成図を提示する
4. カラー、文字、余白、パネル、ボタン、アイコン、状態表示のデザインシステムを定義する
5. P0 / P1 / P2の実装優先度と、既存機能を壊さず段階移行する手順を示す
6. 各画面の受け入れ条件と、キーボード・VoiceOverを含むQA項目を示す

目標は「Lightroomをそのままコピーすること」ではありません。プロ向け写真編集ソフトとして理解しやすい慣習は利用しつつ、Adobeのロゴ、独自アイコン、固有の見た目、ブランド表現は模倣しないでください。RAWDesk自身の、落ち着いたmacOSネイティブの“ローカル暗室”として再設計してください。

また、見た目の改善のために既存のデータ保護、RAW処理、カタログ、編集状態、XMP互換性を削除・簡略化してはいけません。

---

## 1. RAWDeskは何のアプリか

RAWDeskは、Mac内の写真を整理し、RAW現像し、書き出すためのmacOSネイティブ写真管理アプリです。

中心となる価値は次の3つです。

1. **ローカルファースト**
   - 写真、顔解析、編集、カタログをMac上で処理する
   - 写真や顔データをクラウドへアップロードしない
   - アカウントやクラウド同期を前提としない

2. **非破壊RAW現像**
   - 元画像の画素を直接書き換えず、調整値をカタログとアプリ内状態へ保存する
   - 必要に応じて、隣接するXMPサイドカーへ明示的にメタデータを書き出す
   - 編集結果はJPEGまたはPNGとして別ファイルに書き出す

3. **写真の管理から選別・現像までを一つのアプリで完結**
   - フォルダ参照、取り込み、重複確認
   - カタログ、コレクション、キーワード、評価、フラグ
   - 比較、サーベイ、参照表示、アシスト選別
   - People、Map、GPS/GPX
   - RAW現像、部分補正、ソフトプルーフ、書き出し

主な対象ユーザーは、Sony αなどのカメラでRAW撮影し、写真をクラウドへ預けず、自分のMacで整理・選別・現像したい個人写真家または上級者です。

---

## 2. 製品の絶対条件

UIを改善しても、次の条件は変えてはいけません。

### 2.1 原本保護

- Addや通常のフォルダ参照では、元画像を移動、削除、改名、再圧縮、上書きしない
- Copyは、コピー先の完全性を確認してからカタログへ登録する
- MoveとAuto Importだけが、ユーザーの明示した範囲で元ファイルを削除できる
- Moveはコピー先のハッシュ、カタログ登録、元ファイルの再確認後にだけ削除する
- 同名ファイルを黙って上書きしない
- Missing Photosの「カタログから削除」は、実ファイルを削除しない
- XMP書き込みは明示操作であり、壊れたXMPを勝手に上書きしない

### 2.2 ローカル処理とプライバシー

- 顔解析、被写体解析、選別支援はオンデバイスで処理する
- Peopleの推定結果を本人確認済みの「身元」として扱わない
- 人名の確定はユーザーの明示操作だけで行う
- Keychain、Chrome、ブラウザの保存情報、ログイン情報を必要としない
- UI改善のために外部アカウント、クラウド認証、ブラウザ連携を追加しない

### 2.3 非破壊編集

- 現像値、マスク、修復、クロップ、回転、バージョンは原本とは別に保存する
- Undo / Redo、編集コピー、選択的同期、Auto Syncの意味を維持する
- プレビュー、サムネイル、書き出しで同じ編集状態を参照する
- Visualize Rangeやマスクオーバーレイなど、確認用表示を出力画像へ焼き込まない

### 2.4 macOSネイティブ

- SwiftUI / AppKitのネイティブ操作感を維持する
- WebView、Electron、ブラウザUIへ置き換えない
- メニューバー、標準ショートカット、コンテキストメニュー、ドラッグ＆ドロップ、フォーカス操作を活かす
- 最小ウインドウサイズの現行条件である1100 × 700でも破綻させない

---

## 3. 現在実装されている機能

以下は、現行ソースとREADMEに存在する機能です。改善案では、これらを「ユーザーが探しやすい場所」へ再配置してください。

### 3.1 取り込み

- ファイルまたはフォルダを開いて、その場で参照する
- ImportのAdd / Copy / Move
- サブフォルダを含める
- 完全一致重複をSHA-256で事前確認する
- Copy / Move時のコピー先指定
- 撮影日、カメラ、元フォルダ、連番を利用するフォルダ・ファイル名テンプレート
- 同名衝突を安全に回避する
- 既存XMPを写真と一緒に扱う
- 取り込み後のローカルPeople解析を任意で実行する
- Watched FolderによるAuto Import
- 安定書き込み確認後の自動取り込み
- Auto Importのプリセット、キーワード、命名、日付フォルダ整理

### 3.2 Library / Catalog

- SQLiteカタログ
- All Photographs、Recently Added、Edited、Five Stars
- Picked、Rejected、With Keywords、With Location、Without Location
- Assisted Culling、Duplicates、Missing Files
- Quick Collection
- 通常コレクション
- スマートコレクション
- ネストしたコレクションセット
- 検索、形式、評価、キーワード、カラーラベルによる絞り込み
- 評価0〜5
- Pick / Unflag / Reject
- Red / Yellow / Green / Blue / Purpleのカラーラベル
- キーワード階層、同義語、書き出しルール
- 手動スタックと撮影時刻によるAuto Stack
- 欠落ファイルの再リンク、カタログからの削除
- 画像データの完全一致重複グループ
- ローカル解析によるAssisted Culling

### 3.3 閲覧・選別

- Grid / Loupe相当の閲覧
- 複数選択
- Select / CandidateのCompare
- 複数写真を並べるSurvey
- 静止Referenceと編集対象Activeを並べるReference View
- フィルムストリップ
- Before / After
- 拡大、縮小、Fit、Actual Size
- 回転、左右反転、上下反転

### 3.4 Develop

グローバル調整:

- ProfileとAmount
- Exposure、Contrast、Highlights、Shadows、Whites、Blacks
- Temperature、Tint、Vibrance、Saturation
- 5点RGB Tone Curve
- 8色HSL Color Mixer
- Point Color
- Shadows / Midtones / Highlights / GlobalのColor Grading
- RGB Calibration
- Texture、Clarity、Dehaze、Vignette
- Grain Amount / Size / Roughness
- Sharpening、Luminance Noise Reduction、Color Noise Reduction

ローカル調整:

- Subject、Object、Sky
- Brush、Radial、Linear
- Color Range、Luminance Range
- 埋め込み深度がある写真のDepth Range
- Add / Subtract / Intersect
- マスクごとのLight / Color / Effects / Detail調整
- マスク内Point Color
- Heal / Clone

レンズ・形状:

- macOS RAWデコーダが提供するレンズ補正
- 手動Distortion、Vignette
- 色収差の自動解析と手動補正
- Purple / Green Defringe
- Crop、Aspect Ratio、Straighten
- Vertical / Horizontal Perspective
- Scale、Offset、Constrain Crop
- 2〜4本ガイドのGuided Upright

編集管理:

- Clean、Vivid、Portrait、Dramatic、Matteプリセット
- Undo / Redo
- Reset
- Copy / Paste Edit Settings
- 14セクション単位の選択的Sync
- 変更した個別項目だけを反映するAuto Sync
- 名前付きVersion

### 3.5 色管理と出力

- RGB Histogram
- Shadow / Highlight Clipping表示
- Soft Proofing
- sRGB、Display P3、Adobe RGB、Generic CMYK
- MacにあるICCプロファイルの検索
- ICC / ICMの追加
- Perceptual / Relative Colorimetric
- 出力色域、モニター色域、重複領域の警告
- Simulate Paper & Ink
- Proof Version
- JPEG / PNGのフル解像度書き出し
- プライベートSaved Locationに該当する位置情報の書き出し除外

### 3.6 People

- Visionによるローカル顔検出
- Suggested Matches
- Conservative / Balanced / Broadのグループ感度
- 新しい人名の確定
- 既存人物への割り当て
- Rename / Merge / Remove
- Unassign / Not a Face / Restore
- バックグラウンド解析
- Import後の任意解析

### 3.7 Map

- EXIF GPS表示
- カタログ内だけの手動位置変更
- Standard / Hybrid / Satellite
- 場所検索
- クリックによる位置割り当て
- 複数写真への同一位置割り当て
- GPX読み込みと撮影時刻マッチ
- カメラ時刻オフセット
- Saved Locationと半径
- Private Location
- Map用フィルムストリップと位置Inspector

---

## 4. 対応ファイル形式

### 標準画像

- JPEG: `.jpg`, `.jpeg`
- PNG: `.png`
- HEIC: `.heic`
- TIFF: `.tif`, `.tiff`

### RAW

- Sony ARW: `.arw` — 第一優先対応
- Canon CR2: `.cr2` — 第一優先対応
- Canon CR3: `.cr3`
- Adobe DNG: `.dng`
- Nikon NEF: `.nef`
- Fujifilm RAF: `.raf`
- Panasonic RW2: `.rw2`
- Olympus ORF: `.orf`

### Sony αのRAWに関する必須表示

Sony αのRAWはARWとして認識する。現行テストフォルダには実物の`ETH01641.ARW`がある。

デコードは次のフォールバックを使う。

1. macOSのCIRAWFilterによるRAWデコード
2. Core Imageの一般デコード
3. RAW内の埋め込みJPEG
4. Quick Look Thumbnailing
5. すべて失敗した場合は非致命的なUnsupported表示

UIでは、ARWを単に「表示できた / できない」で終わらせず、必要な場合は次を区別できるようにする。

- RAWとして現像可能
- 埋め込みプレビューで表示中
- このMacのRAWデコーダがカメラ機種へ未対応
- ファイルが破損または読み込み不能

ただし、通常利用中に技術情報を常時表示して画面を騒がしくしない。ステータスバッジ、Info Inspector、エラー詳細の段階表示にする。

---

## 5. 現行画面の構造

現行アプリは、大きく次の構造を持つ。

```text
┌────────────────────────────────────────────────────────────────┐
│ Open / Import | Library Develop People Map | contextual tools  │
├───────────────┬──────────────────────────────┬─────────────────┤
│ Left sidebar  │ Main photo / workspace       │ Right inspector │
│ sources       │                              │ edit / info     │
│ collections   ├──────────────────────────────┤ histogram       │
│ presets etc.  │ grid or filmstrip            │ adjustments     │
└───────────────┴──────────────────────────────┴─────────────────┘
```

グローバルWorkspaceは次の4つ。

- Library
- Develop
- People
- Map

現行コード上では、LibraryとDevelopは同じ写真ワークスペースの表示モードで、PeopleとMapは別のワークスペースとして管理されている。改善後は、内部実装が同じでも、ユーザーからは4つの役割が明確に分かれて見える必要がある。

---

## 6. 現行UI監査

この監査は、現行Releaseアプリを隔離したQA用Application Support領域で起動し、1296 × 768で撮影した画面を根拠にしている。

### Step 1: 写真未登録のLibrary

![現行の空Library](Evidence/2026-07-29/ui-brief-current/01-empty-library.png)

絶対パス:
`Evidence/2026-07-29/ui-brief-current/01-empty-library.png`

状態: **Needs improvement**

良い点:

- 中央の「Open a Photo Folder」は次の行動が分かる
- Dark UIと3ペイン構造は写真アプリとして方向性が合っている
- OpenとImportがツールバーにある

問題:

- 写真がないのに、左の大きなカタログ一覧と右の無効な編集Inspectorが画面を占有している
- 最初に見る情報量が多く、入口より機能一覧のほうが目立つ
- Open FolderとImport Photosの違いを初見で理解しにくい
- 最近開いたフォルダやドラッグ＆ドロップの入口が弱い
- 無効な右Inspectorが「何か操作が足りない」ように見える

改善方向:

- 初期状態では中央を主役にし、左右ペインは閉じるか簡略表示する
- 「フォルダをそのまま開く」と「安全に取り込む」を2つの明確なCTAにする
- Recent FoldersとDrop Zoneを中央へ追加する
- 原本を変更しないことを短い説明で示す

### Step 2: 写真を読み込んだLibrary

![現行のLibrary](Evidence/2026-07-29/ui-brief-current/02-library-with-photos.png)

絶対パス:
`Evidence/2026-07-29/ui-brief-current/02-library-with-photos.png`

状態: **Needs major structural improvement**

良い点:

- Sony ARW、Canon CR2、JPEGを同じカタログで扱えている
- 選択写真、サムネイル、カタログ、Inspectorが一画面にある
- フィルターや評価、比較機能へ到達できる

問題:

- Libraryなのに、右側へDevelopの全編集項目が常時表示され、Workspaceの意味が弱い
- 写真プレビューとグリッドが上下に常時分割され、写真3枚でも大きな空白が残る
- グリッド、Loupe、Filmstripの役割が混ざっている
- 左SidebarがCatalog、Collections、Folders、Import、Auto Importなどを一度に見せすぎている
- 上部ツールバーのアイコンが多く、重要度とグループが分からない
- 小さなアイコンと文字、弱いコントラストが多い
- 選択写真の状態、現在の表示モード、次の主要操作が視覚的に競合する

改善方向:

- Libraryは「Grid」と「Loupe」を明示的に切り替える
- Gridでは中央全体をサムネイルへ使い、常設の大きなプレビューを外す
- Loupeでは写真を主役にし、下部はコンパクトなFilmstripへする
- 右側はInfo / Quick Reviewを基本とし、全現像項目はDevelopへ移す
- 左SidebarはCatalog、Collections、Folders、Servicesを折りたたみ可能にする
- Compare / Survey / Referenceは「表示モード」グループへまとめる

### Step 3: Develop

![現行のDevelop](Evidence/2026-07-29/ui-brief-current/03-develop.png)

絶対パス:
`Evidence/2026-07-29/ui-brief-current/03-develop.png`

状態: **Functional foundation, needs hierarchy and polish**

良い点:

- 左にNavigator / Presets / History / Versions、中央に写真、右にHistogramと調整という構造は理解しやすい
- 下部Filmstripがあり、写真を移動しながら現像できる
- 右Inspectorに実装済みの高度な現像機能が集まっている
- Lightroom系アプリを使った人には大枠が分かりやすい

問題:

- 1296 × 768では左右ペインとFilmstripに押され、写真の表示面積が小さい
- 右Inspectorが非常に長く、すべてのセクションが同じ強さで並ぶ
- 文字、数値、Disclosure、Sliderが小さく、暗部で読みづらい
- Presets、History、Reset、Versionsなどの操作が複数箇所に重複して見える
- Histogramや頻繁に使うLightを固定しにくい
- マスク、修復、クロップなど「写真上で操作するツール」の入口が、一般スライダーに埋もれやすい
- パネルを一括で隠して写真だけ確認する導線が弱い

改善方向:

- 写真上で使うTool Railと、数値調整を行うInspectorを分ける
- Histogramを固定し、その下のInspectorはAccordion + Solo Modeにする
- 初期展開はProfile、Light、Colorだけにし、その他は閉じる
- 左SidebarはNavigator、Presets、Snapshots/Versions、Historyへ整理する
- Undo / Redo / Resetは一か所に統合する
- Tab系のショートカットと明確なボタンで左右パネルを隠せるようにする
- Filmstripの高さを固定範囲で縮小できるようにする

### Step 4: Import

![現行のImport](Evidence/2026-07-29/ui-brief-current/04-import.png)

絶対パス:
`Evidence/2026-07-29/ui-brief-current/04-import.png`

状態: **Functional, needs clearer decision hierarchy**

良い点:

- Add / Copy / Moveの安全な取り込み方式が実装されている
- Skip Exact DuplicatesとローカルPeople解析を選べる
- 実行前のPreflightを前提にしている
- 元ファイルを保護する製品思想に合っている

問題:

- Source、Method、オプション、結果が縦一列に並び、重要な判断と詳細設定の差が弱い
- Add / Copy / Moveの意味と危険度の違いが、ラベルだけでは伝わりにくい
- Moveが元ファイルの削除を伴う条件を、実行直前に十分目立たせる必要がある
- 空状態の大きな領域と、下部ボタンの役割が弱くつながっている
- 背景が透けた大型オーバーレイで、モーダル内の階層が弱く見える
- Preflight後に「何枚が新規、重複、非対応、失敗か」を一目で判断する表示が必要

改善方向:

- Source / Review / Destination & Handlingの3領域に分ける
- Add / Copy / Moveに1行説明と安全性アイコンを付ける
- Move選択時は警告色を乱用せず、削除条件を明文化する
- 中央に取り込み対象の一覧またはサムネイルを表示する
- 下部固定バーへ、対象数、重複数、必要容量、実行ボタンをまとめる
- Import中、People解析中、完了、部分失敗を同じ場所で段階表示する

### 未撮影画面の監査範囲

People、Map、Compare、Survey、Reference、Soft Proof、Syncの実装はソースとREADMEで確認しているが、この文書作成時には現行画面の追加スクリーンショット監査を行っていない。これらの最終デザイン判断は、実画面を開いて追加確認してから確定すること。

---

## 7. 現行UIの主要な根本問題

### 7.1 機能量ではなく、情報設計がボトルネック

RAWDeskは未機能だから使いにくいのではない。機能が増えた結果、内部機能一覧をそのまま画面へ露出し、ユーザーの作業順序が見えにくくなっている。

改善の中心は、新機能追加ではなく次の整理である。

- 今どの仕事をしているか
- その仕事で必要な機能は何か
- 頻繁に使う機能と詳細機能の差
- 写真そのものとUIのどちらが主役か
- 次に実行される操作と、その安全性

### 7.2 LibraryとDevelopの役割が重なっている

Libraryの目的は、探す、比較する、選ぶ、整理すること。Developの目的は、一枚または複数枚を現像すること。

現行Libraryに全Develop Inspectorが見えるため、初心者には「どこで何をするか」が曖昧で、上級者には中央の作業面積が不足する。

### 7.3 すべてが常時表示される

Sidebar、Inspector、Grid、Preview、Filmstrip、Toolbarが同時に見える。機能への到達性は高い一方、選択した作業へ集中しづらい。

必要なのは機能削除ではなく、次の段階表示である。

- Primary: 今の作業に必須
- Secondary: 頻繁に使う
- Advanced: 必要な時だけ開く
- Diagnostic: エラーや技術情報の詳細

### 7.4 密度と可読性

小さい文字、狭い行間、弱いコントラスト、細いDisclosure、密集したアイコンによって、プロ向けの高密度UIというより、縮小されたUIに見える箇所がある。

「高密度」と「小さくて読みづらい」は分ける必要がある。

### 7.5 一つの操作が複数箇所にある

Preset、History、Reset、比較系、Zoom、Rotateなどが複数の場所に見え、ユーザーが操作位置を覚えにくい。メニューやショートカットに同じ操作があること自体は問題ではないが、画面上の主な置き場所は一つに定める。

---

## 8. 改善後のデザインコンセプト

コンセプト: **Professional Local Darkroom**

見た目の目標:

- 写真が最も強く見える
- 暗いが、文字と操作は明瞭
- 余白は贅沢ではなく、機能グループを理解するために使う
- macOSらしい正確さと静けさ
- 高度な機能は隠さず、必要な瞬間だけ前へ出す
- クラウドサービス感より、デスクトップ制作ツール感

避けるもの:

- Adobe製品の完全な外観コピー
- 半透明の多用
- すべてをカード化するWebダッシュボード風UI
- 大きな角丸、巨大な見出し、モバイル風の過度な余白
- 絵文字、独自記号、意味不明なアイコン
- 写真より目立つ装飾

---

## 9. 改善後の情報アーキテクチャ

### 9.1 三層構造

```text
Global
  └─ Library / Develop / People / Map

Workspace
  ├─ Left: sources, organization, presets, history
  ├─ Center: grid, photo, people groups, map
  ├─ Right: selected item’s contextual inspector
  └─ Bottom: filmstrip or fixed action/status bar

Context
  ├─ Photo review
  ├─ On-photo tools
  ├─ Edit panels
  ├─ Import preflight
  └─ Progress, warnings, errors
```

### 9.2 Global Toolbar

常設:

- Sidebar toggle
- Open
- Import
- Workspace selector: Library / Develop / People / Map
- Search
- Inspector toggle

条件付き:

- Export
- Workspace固有の表示モード
- Soft Proofの状態
- Background taskの進捗

OverflowまたはMenuへ移す候補:

- Rotate Left / Right
- Zoom In / Out / Fit
- Compare / Survey / Referenceの一部
- 低頻度の管理操作

ルール:

- 1296px幅で、ツールバーがアイコンの列に見えないこと
- 重要な操作にはラベルまたは明確なTooltipを付ける
- 似た操作をDividerだけで分けず、機能グループとしてまとめる
- Workspaceが変わったら、中央以外の操作もその仕事へ切り替わる

---

## 10. 画面別の改善仕様

### 10.1 Empty / Welcome

目的: 写真作業を始める。

中央:

- RAWDeskの短い説明
- Primary: Open Photo Folder
- Secondary: Import Photos
- Drop photos or folders here
- Recent Folders
- 「元画像は変更されません」という短い安全説明

左右:

- 初回は閉じる
- Recentがある場合だけ、左Sidebarを任意表示
- 選択写真がない右Inspectorは出さない

受け入れ条件:

- 初見でOpenとImportの違いが分かる
- 3秒以内に開始操作を見つけられる
- 無効な編集機能を大量に見せない

### 10.2 Library — Grid

目的: 写真を探す、選ぶ、整理する。

左Sidebar:

- Catalog
- Collections
- Folders
- Services: Duplicates / Assisted Culling / Auto Import
- 各Sectionは折りたたみ可能
- 件数は右寄せし、本文より弱く表示

中央:

- 利用可能領域全体をGridへ使う
- Thumbnail Sizeを段階調整できる
- 選択、評価、Flag、Color Label、RAW形式、Edited、Missingを一貫した位置へ表示
- バッジは写真を覆いすぎない
- HoverでQuick Actionsを出せるが、常時アイコンを並べない
- 0件、フィルター結果0件、読み込み中、Missingだけ、解析中を別状態として表示

上部のLibrary Control Bar:

- Grid / Loupe
- Sort
- Filter
- Thumbnail Size
- Compare / Survey / Reference
- Active Filterの解除

右Inspector:

- 初期は閉じるか、Info / Quick Review
- Quick Review: Rating、Flag、Color、Keyword、Quick Collection
- Info: filename、format、camera、lens、date、dimensions、location
- 全Develop調整は表示しない
- 「Developで編集」CTAを置く

受け入れ条件:

- 1296 × 768でGridが主役に見える
- 右Inspectorを閉じても主要な選別ができる
- 全Develop項目がLibraryへ常時露出しない
- 写真3枚でも不自然な巨大空白を作らない

### 10.3 Library — Loupe

目的: 一枚を大きく確認し、選別する。

- 中央は写真
- 下部は高さ120〜156pxのFilmstrip
- Rating、Flag、ColorをFilmstripまたは下部固定バーから操作
- Info InspectorとHistogramを任意表示
- Editへ進む操作を明確にする
- Original表示中は状態を中央上部へ明示する

### 10.4 Develop

目的: 一枚の写真へ集中して非破壊現像する。

左Sidebar:

- Navigator
- Presets
- Versions / Snapshots
- History
- Folder / Collection navigationは最下部か切替式
- Sectionの開閉状態を保存

中央Canvas:

- 写真を最大化
- 背景は中立な暗灰色
- Zoom / Fit / 1:1をCanvas下部の小さなBarへ集約
- Before / After、Soft Proof、Clipping状態をCanvas上部に明示
- Crop、Mask、Heal、Guided Uprightなど写真上操作中は、モード名とDone / Cancelを固定表示
- マスクオーバーレイ色と可視性を常に認識できる

On-photo Tool Rail:

- Crop
- Heal / Clone
- Mask
- Guided Upright
- Point Color sampling
- 必要ならRotate

右Inspector:

固定:

- Histogram
- Profile

Accordion:

- Light
- Color
- Tone Curve
- Color Mixer
- Point Color
- Color Grading
- Calibration
- Masks
- Remove
- Optics
- Crop & Geometry
- Effects
- Detail
- Versions

ルール:

- 初期展開はProfile、Light、Color
- Option-clickなどでSolo Modeを利用できる
- Resetは各Section Header内
- Section全体の有効 / 無効が意味を持つ場合は明示
- 数値入力、Slider、Resetの位置を全Sectionで統一
- Slider名と値は視線移動を少なくする
- 高度な説明はHelp / Infoへ逃がし、常時本文にしない

下部:

- Filmstrip
- 高さを120〜168pxで調整可能
- 非表示可能
- 選択数、Auto Sync状態、Filter状態を端へ表示

受け入れ条件:

- 1296 × 768でも写真がUIの主役である
- Lightへ1クリック以内、Maskへ1クリック以内
- Histogramを保ったまま、Inspectorの長さを管理できる
- 同じReset / Preset / History操作が画面上で重複しない
- パネルを一時的に隠して写真だけ確認できる

### 10.5 Import

目的: 何が、どこへ、どの方法で入るかを実行前に理解する。

推奨構造:

```text
┌──────────────────────────────────────────────────────────────┐
│ Import Photos                                   Close         │
├───────────────┬───────────────────────────┬──────────────────┤
│ Source        │ Review                    │ File Handling    │
│ files/folder  │ thumbnails/list           │ Add/Copy/Move    │
│ subfolders    │ new/duplicate/unsupported │ destination      │
│               │ per-item status           │ naming/people    │
├───────────────┴───────────────────────────┴──────────────────┤
│ 120 total · 113 new · 5 duplicates · 2 unsupported  Import  │
└──────────────────────────────────────────────────────────────┘
```

File Handling:

- Add — 現在の場所を参照。コピーも削除もしない
- Copy — 検証したコピーを作成。元ファイルは残す
- Move — 検証後、選択元を削除する可能性がある

Move選択時:

- 移動元と移動先を明示
- 「検証成功後に元ファイルを削除する」ことを表示
- 既に同じ場所でカタログ済みのファイルは削除されないことを表示
- 最終CTAを「Move and Import」のように具体化する

Preflight Summary:

- New
- Exact Duplicates
- Unsupported
- Unavailable
- Estimated Copy Size
- XMP companions
- Naming conflicts
- Warnings

Footer:

- 左: status / error summary
- 中央: Cancel
- 右: Analyze Again / Import
- Primary CTAは常に一つ
- 実行不能理由を、Disabledだけでなく近くへ説明

完了:

- Imported、Copied、Moved、Retained、Reused、Skipped、Failedを表示
- 部分失敗でも成功分を隠さない
- Show Last Import
- Reveal Problems

### 10.6 People

目的: ローカル解析結果を確認し、人名を明示的に整理する。

左:

- Named People
- Suggested Matches
- Needs Review
- Ignored / Not a Face
- Background Analysis status

中央:

- PersonまたはSuggestionのGroup Grid
- 顔サムネイルと写真数
- SuggestionとConfirmedを色だけでなくLabelでも区別

右:

- Source Photo
- Detection / quality evidence
- Assign to Person
- Create New Person
- Unassign / Not a Face

必須表示:

- Local-only analysis
- Suggestion is not identity
- 名前確定はユーザー操作のみ

### 10.7 Map

目的: 写真の位置を確認・整理する。

左:

- With Location
- Without Location
- Saved Locations
- GPX
- Map Style

中央:

- Mapを最大化
- 検索
- Fit to Results
- Selected Photo focus
- GPX preview
- Saved Location radius

右:

- 選択写真
- Latitude / Longitude / Altitude
- Embedded / Manual / RemovedのSource
- Use Camera GPS
- Remove Location
- Private Location export effect

下部:

- Location-aware Filmstrip

### 10.8 Compare / Survey / Reference

共通:

- 通常Libraryから明確に切り替わったことを示す
- Done / Exitを常時見える位置へ置く
- 評価、Flag、Color操作を各写真の同じ位置へ置く
- フィルムストリップ上でSelect / Candidate / Active / Referenceを明示
- 写真ロールを色だけで区別しない

Compare:

- SelectとCandidateを固定Labelで表示
- Swap / Promoteを近接配置
- Zoom / Pan Sync状態を表示

Survey:

- Activeを枠とLabelで表示
- Remove from SurveyとRemove from Catalogを混同させない

Reference:

- ReferenceとActiveを固定Labelで表示
- Activeだけ編集されることを明示
- Left/RightとTop/Bottomの切り替え

### 10.9 Soft Proof

- On / Off状態をCanvas上に明示
- Profile、Intent、Paper & Inkを一つのPopoverまたはInspectorへ整理
- Gamut warningのRed / Blue / Purple凡例を常時見える位置へ置く
- Warning表示は書き出しへ焼き込まれないことをHelpへ記載
- Proof Version保存を主要操作にする

---

## 11. Design System

### 11.1 Color

基本はmacOSのSemantic Colorを優先し、固定色は写真表示環境に必要な範囲だけ使う。

推奨基準:

| Role | Example |
| --- | --- |
| Canvas | `#121315` |
| Main chrome | `#1A1C1F` |
| Panel | `#202328` |
| Elevated control | `#2A2E34` |
| Primary text | `#F1F3F5` |
| Secondary text | `#A9B0BA` |
| Divider | white 10–14% |
| Selection | macOS accent color |
| Warning | system orange |
| Destructive | system red |
| Success | system green |

ルール:

- 写真の周囲は無彩色にする
- Accent Colorは選択、Focus、Primary Actionへ限定する
- 評価やColor Label以外で色を増やさない
- Disabled状態を透明度だけに頼らず、操作不能理由を示す
- 本文テキストは背景とのコントラスト4.5:1以上を目標にする
- UI境界と重要アイコンは3:1以上を目標にする

### 11.2 Typography

SF Pro / macOS system fontを利用する。

| Role | Size / Weight |
| --- | --- |
| Window / modal title | 18–20, Semibold |
| Workspace title | 14–15, Semibold |
| Panel section header | 11–12, Semibold |
| Body / control label | 12–13, Regular |
| Metadata | 11–12, Regular |
| Numeric value | 11–12, Monospaced Digit where useful |
| Badge | 10–11, Medium |

ルール:

- 9pt相当の常用テキストを避ける
- 大文字だけのSection Headerを乱用しない
- Secondary textを小さくしすぎず、色とWeightで階層化する
- Slider値は桁が変わっても揺れない

### 11.3 Spacing

4 / 8 / 12 / 16 / 24の間隔体系を使う。

- Control内: 4–8
- 同一グループ: 8
- Field間: 12
- Section内側: 12–16
- Section間: 16–24
- Modal外周: 20–24

### 11.4 Size

- Global toolbar: 44–52px
- Left sidebar: 220–280px
- Right inspector: 300–380px
- Develop filmstrip: 120–168px
- Library filmstrip: 112–156px
- Icon button target: 最低28 × 28px
- Primary button: 高さ32–36px
- Slider track周辺の操作Target: 高さ28px以上
- Inspector row: 28–32px

### 11.5 Shape

- 通常Control: 6px前後
- Panel / Popover内の小グループ: 8px前後
- Modal: 10–12px前後
- すべてをカード化しない
- Dividerと余白を優先し、不要な枠を増やさない

---

## 12. 共通コンポーネント

再設計では、画面ごとに似たUIを別実装せず、次を共通化する。

- WorkspaceSwitcher
- GlobalToolbar
- SidebarSection
- InspectorSection
- InspectorRow
- SliderRow
- NumericField
- ToolRailButton
- PhotoCanvasStatusBar
- ThumbnailCell
- FilmstripCell
- ReviewControls
- FormatBadge
- EditStatusBadge
- MissingStatus
- LocalOnlyBadge
- ProgressBanner
- InlineError
- EmptyState
- PreflightSummary
- PrimaryFooterBar

各コンポーネントに必要な状態:

- Default
- Hover
- Pressed
- Selected
- Focused
- Disabled
- Loading
- Error
- Mixed value
- Multi-selection

---

## 13. Interaction Rules

### 13.1 Panel

- 左右SidebarとFilmstripを個別に開閉できる
- 開閉状態と幅を再起動後も復元する
- InspectorのAccordion状態をWorkspaceごとに保存する
- Solo Modeを用意する
- 一時的に写真だけを見る操作を用意する

### 13.2 Selection

- 選択中の写真をGrid、Filmstrip、Inspectorで一致させる
- 複数選択時は「1 selected」ではなく件数を表示する
- 複数写真で値が異なる場合はMixedを表示する
- Active Photoと選択集合を区別する

### 13.3 Feedback

- RAW decode、thumbnail generation、catalog scan、export、import、People analysisに進捗表示を用意する
- 長い処理はUIを全面停止させない
- Cancel可能な処理はCancelを表示する
- エラーは「何が失敗し、何が成功し、原本がどうなったか」を示す
- Toastだけで重要なエラーを終わらせない

### 13.4 Destructive / Sensitive

- Move、Auto Importの元ファイル削除、Catalog record removalを明確に区別する
- 実ファイル削除を伴う場合だけDestructive表現を使う
- 「Remove from Survey」「Remove from Collection」「Remove from Catalog」「Delete Source」を同じ言葉にしない
- PeopleはSuggest / Confirm / Unassignを明確に区別する
- Private Locationの書き出し効果を明示する

### 13.5 Keyboard

既存Shortcutを維持する。

主要例:

- Import: ⇧⌘I
- Open Folder: ⌘O
- Save XMP: ⌘S
- Export: ⌘E
- Compare: C
- Survey: N
- Reference: ⇧R
- Soft Proof: S
- Original: `\`
- Undo / Redo: ⌘Z / ⇧⌘Z
- Rating: 0–5
- Label: 6–9
- Pick / Unflag / Reject: P / U / X
- Next / Previous: → / ←

追加を検討:

- Sidebar / Inspector / Filmstripの表示切替
- 全パネル一時非表示
- Grid / Loupe切替

追加時は、既存Shortcutや文字入力中の操作と衝突しないこと。

---

## 14. Accessibility

必須:

- すべてのIcon-only ButtonにAccessibility LabelとTooltip
- Tab / Shift-Tabで予測可能な順にFocus移動
- Focus Ringを暗い背景でも見えるようにする
- Workspace、Selection、Active Photo、Tool ModeをVoiceOverへ通知
- Rating、Flag、Colorを色だけで表現しない
- Red / Blue / PurpleのGamut Warningに文字の凡例を付ける
- Error、Warning、SuccessをIcon + Labelで区別する
- Sliderをキーボードで調整できる
- 数値を直接入力できる
- Reduce Motionへ配慮する
- Animationは状態理解に必要な短いものだけにする

検証:

- VoiceOver
- Full Keyboard Access
- Increase Contrast
- Reduce Transparency
- Different accent colors
- 1100 × 700
- 1296 × 768
- 1440 × 900
- 1728 × 1117以上

---

## 15. Window Sizeとレスポンシブ挙動

### 1440px以上

- Left + Center + Rightを表示可能
- Filmstrip表示可能
- Toolbarの主要操作をラベル付きで表示

### 1100〜1439px

- Centerを優先
- Right Inspectorを自動的に狭くするか、初期Collapsed
- Toolbarの低頻度操作をOverflowへ
- Library Gridでは右Inspectorを初期非表示
- Developでは左Sidebarを縮小またはCollapsedにできる

### 最小1100 × 700

- 横スクロールを発生させない
- 主要CTAを切らない
- Import Footerを常に表示
- Developの写真上操作に必要なDone / Cancelを隠さない
- Inspectorの数値FieldとSliderを重ねない

---

## 16. 優先順位

### P0 — 情報設計と主要導線

1. LibraryとDevelopの役割を分離
2. LibraryのGrid / Loupeを明示切替
3. Libraryから全Develop Inspectorを外す
4. Empty Stateで左右の無効ペインを隠す
5. Develop InspectorをAccordion + Solo Modeへ整理
6. Toolbarの常設操作を削減し、Workspace固有操作へ分ける
7. ImportのAdd / Copy / MoveとPreflightを再構成
8. Sidebar / Inspector / Filmstripの表示状態を制御可能にする

### P1 — 視覚品質と操作の一貫性

1. Typography、Contrast、Spacing、Target Size
2. Slider Row、Section Header、Button、Badgeの共通化
3. Progress、Error、Unsupported、Missingの状態設計
4. Multi-selectionとMixed Value
5. On-photo Tool Rail
6. Compare / Survey / Referenceの共通レイアウト
7. Keyboard FocusとTooltip

### P2 — 高度機能の仕上げ

1. People / Mapの全画面監査と統一
2. Soft Proofの状態表示
3. Sync / Auto Syncの安全な可視化
4. Auto Importの監視状態
5. 非常に大きいLibraryでの表示密度と検索状態
6. VoiceOverの完全監査

---

## 17. 実装移行方針

見た目を一度に全面置換せず、次の順で移行する。

### Phase 1: Shell

- GlobalToolbar
- WorkspaceSwitcher
- Sidebar / Inspector toggle
- Window size behavior
- Design token

### Phase 2: Library

- Grid / Loupe
- Library-specific Inspector
- Filter / Sort Bar
- Empty / Loading / Zero Results

### Phase 3: Develop

- Tool Rail
- InspectorSection共通化
- Solo Mode
- Canvas Status Bar
- Filmstrip behavior

### Phase 4: Import

- 3領域構成
- Preflight Summary
- Move safety disclosure
- Progress / Result

### Phase 5: Specialized workspaces

- Compare
- Survey
- Reference
- People
- Map
- Soft Proof
- Sync

各Phaseで、既存ViewModel、Catalog、RAW pipeline、Import safety logicを温存する。最初にViewの構造とPresentation Stateを整理し、処理ロジックを書き換えない。

---

## 18. 受け入れ条件

### Product comprehension

- 初見ユーザーが、RAWDeskを「ローカル写真管理 + 非破壊RAW現像」と説明できる
- Open FolderとImportの違いをUIだけで理解できる
- LibraryとDevelopの役割を説明なしで区別できる

### Core workflow

- OpenまたはImportしたSony ARWを選び、Developへ移動し、Exposureを調整し、Beforeを確認し、JPEGへExportできる
- 主要な一連の操作で、原本が変更されないことが分かる
- ARWがRAWデコードか埋め込みプレビューか、必要な時だけ確認できる

### Layout

- 1100 × 700から大型画面まで横方向に破綻しない
- 1296 × 768で写真またはGridが中央の主役になる
- 無効なInspectorが空状態を占有しない
- Toolbarが機能アイコンの羅列に見えない

### Consistency

- 同じSection Header、Slider、Numeric Field、Resetが全Inspectorで同じ構造
- Rating、Flag、Color、Selectionの表現がGrid、Filmstrip、Compare、Surveyで一致
- 操作の主な置き場所が画面上で重複しない

### Safety

- Add / Copy / Moveの違いが実行前に明示される
- Moveの元ファイル削除条件が分かる
- Remove from Catalogがファイル削除ではないと分かる
- People解析がローカルで、Suggestionであることが分かる
- Keychain、Chrome、外部アカウントへのアクセスを追加しない

### Accessibility

- Icon-only controlはすべて読めるLabelを持つ
- Keyboardだけで主要Workflowを完了できる
- Focus位置が常に見える
- 通常文字のコントラスト目標を満たす
- 色だけに依存した状態がない

---

## 19. 現時点で未実装または限定的なもの

UIで存在するように見せたり、実装済みと誤認させたりしないこと。

- Adobeのカメラ別Profileデータベース
- Adobe相当のレンズProfileデータベース
- DCP / XMP Profile import
- 学習型RAW Denoise
- Raw Details
- Super Resolution
- Generative Remove / 高度なContent-aware fill
- Panorama merge
- HDR merge
- Copy as DNG
- カメラ・カードの専用取り込みオーケストレーション
- Tethering
- Print / Book
- Plugin ecosystem
- Cloud sync
- Mobile / Web client
- Collaboration
- 完全なIPTC Editor
- AdobeのローカルマスクやAI重編集との完全互換
- Adobe級の人物同定品質
- Developer ID / App Store向け署名、Notarization済みの配布

また、フルRAWデコード対応はMacに搭載されたRAWデコーダに依存する。未対応カメラでは埋め込みJPEGへフォールバックする場合がある。

---

## 20. Claude / Fable 5の提出形式

改善書は次の順で提出してください。

1. Executive Summary
2. 現行UIの問題一覧
3. 改善後のInformation Architecture
4. 主要画面のBefore / After構成
5. Library詳細
6. Develop詳細
7. Import詳細
8. People / Map / Compare / Survey / Reference
9. Design Token
10. 共通Component一覧
11. Keyboard / Accessibility
12. P0 / P1 / P2 Roadmap
13. 受け入れ条件
14. 実装前に確認が必要な点

各提案には次を付けること。

- 解決する問題
- 対象ユーザー
- 変更される画面
- 変更されない既存挙動
- Edge Case
- Accessibility
- 実装優先度

提案だけの曖昧な言葉は避ける。

悪い例:

- もっとモダンにする
- 直感的にする
- Lightroomっぽくする

良い例:

- Libraryの右InspectorをInfo / Quick Reviewへ限定し、Develop調整を非表示にする
- 1296px幅では右Inspectorを初期Collapsedにし、Gridへ最低720pxを確保する
- Import FooterへNew / Duplicate / Unsupportedの件数とPrimary CTAを固定する

---

## 21. 根拠と確認範囲

この文書の製品仕様は、現行の次の資料を基にしている。

- `README.md`
- `Sources/RAWDesk/`
- `Resources/Info.plist`
- `project.yml`
- 2026-07-29に現行Releaseアプリから撮影した4画面
- `testraw/ETH01641.ARW`
- `testraw/IMG_0002.CR2`
- `testraw/ETH01535.JPG`

今回、4つの画面は現物確認した。READMEに記録された過去のビルド・テスト結果は参照したが、このUI文書作成のために全テストスイートを再実行したわけではない。People、Map、Compare、Survey、Referenceなどは、最終UI案を確定する前に追加の現物監査が必要である。

原本写真、通常利用中のカタログ、Keychain、Chromeには変更を加えていない。
