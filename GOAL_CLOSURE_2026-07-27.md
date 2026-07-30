# RAWDesk 旧ゴール終了記録

作成日: 2026-07-27  
対象ゴール: `adobe lightroomと同等かそれ以上にしといて / UIもね`

## 終了状態

- ゴール状態: 一時停止
- 累計トークン: **20,347,429**
- 累計実行時間: **92,231秒（25時間37分11秒）**
- 完了判定: Lightroom完全同等を達成したという意味では完了にしない
- 終了理由: 現在版を実用可能な完成地点として固定し、次の目的を別の具体的なゴールとして再定義するため
- ゴール削除: 現在利用できるゴール操作には削除がないため、この記録と一時停止状態を終了境界とする

## 終了時の検証

- `swift test`: **297 tests / 0 failures**
- Releaseアプリ: `build/Release/RAWDesk.app`
- アプリ容量: 約40MB
- Release実行ファイルSHA-256:
  `a87854d486fa613de195965e1998550c0bfdac8f2750670007253be2c984a228`
- Swiftソース: 94ファイル
- テストソース: 2ファイル
- Guided Upright Release QA:
  `Evidence/2026-07-27/guided-upright/`
- Automatic Chromatic Aberration Release QA:
  `Evidence/2026-07-27/auto-ca/`

## 製品定義

RAWDeskは、macOSネイティブ、ローカル完結、非破壊編集を中心とする
写真整理・RAW現像アプリである。写真を外部サービスへ送らず、
参照中の原本を書き換えず、編集状態をローカルJSON、SQLiteカタログ、
任意のXMPサイドカーへ保持する。

## 実装済み仕様

### RAW現像

- JPEG、PNG、HEIC、TIFF
- Sony ARW、Canon CR2/CR3、DNG、Nikon NEF、Fuji RAF、
  Panasonic RW2、Olympus ORF
- Exposure、Contrast、Highlights、Shadows、Whites、Blacks
- Temperature、Tint、Vibrance、Saturation
- 5点RGBトーンカーブ
- 8色HSLカラーミキサー
- Point Colorと写真上のスポイト
- 3ウェイ＋Globalカラーグレーディング
- RGBプライマリ・キャリブレーション
- Camera Defaultと複数のクリエイティブ／白黒プロファイル
- Texture、Clarity、Dehaze、Vignette、Film Grain
- シャープ、マスキング、輝度・カラーノイズリダクション

### マスクと修復

- 被写体、空、クリック対象物のオンデバイス選択
- Brush、Radial、Linear
- Color Range、Luminance Range、埋め込みDepth Range
- Add、Subtract、Intersectの順序付き合成
- マスク単位の露出、色、ディテール、Point Color
- Heal／Clone、移動可能な修復元、半径、ぼかし、不透明度

### 光学・切り抜き・幾何補正

- Apple RAWレンズ補正
- 手動歪曲、周辺光量、赤／シアン・青／黄の位置補正
- 紫／緑フリンジ補正
- 写真解析によるAutomatic Chromatic Aberration
- Crop、アスペクト比、Straighten
- Vertical、Horizontal、Aspect、Scale、X/Y Offset
- Constrain Crop
- 2〜4本のガイドによるGuided Upright
- 90度回転、水平／垂直反転

### 編集ワークフロー

- Before／After
- Reset
- 連続操作をまとめるUndo／Redo
- Copy／Paste edits
- 14セクション選択式の複数写真Sync
- 変更した個別パラメーターだけを伝播するAuto Sync
- 名前付き編集バージョン
- グリッドサムネイルへの現像反映
- フル解像度JPEG／PNG書き出し
- EXIF、GPS、IPTC、TIFF、キーワードの可能な範囲での保持

### カラーマネジメント

- Core Imageの拡張リニア／half-float処理境界
- sRGB、Display P3、Adobe RGB、Generic CMYK
- 検証済みICC/ICMプロファイルのローカル追加
- Perceptual／Relative Colorimetric
- 出力色域警告、モニター色域警告、重複警告
- Simulate Paper & Ink
- 設定を復元できるProof Version

### カタログと写真管理

- WALモードSQLiteカタログ
- フォルダ参照
- Add／Copy／Moveインポート
- SHA-256完全ファイル検証
- 衝突回避、ステージング、検証後確定
- XMP同伴コピー／移動
- 監視フォルダAuto Import
- Quick Collection
- 通常コレクション、スマートコレクション、Collection Set
- 階層キーワード、同義語、親キーワード書き出し
- カラーラベルセット
- 完全一致画像データの重複グループ
- 欠損写真の再リンク、カタログからの非破壊削除
- 手動スタック、Assisted Cullingスタック、撮影時刻Auto Stack
- Adobe互換フィールド＋RAWDesk完全状態のXMPサイドカー

### レビューと整理

- Select／Candidate Compare
- 複数写真Survey
- 固定Reference＋編集可能ActiveのReference View
- 同期ズーム／パン
- RGBヒストグラム差分
- 写真上のsRGB／CIE Lab読取
- オンデバイスAssisted Culling
- Focus、Eye、Exposure、Misfire、Document、Stack根拠の表示
- 手動判断と一括Flag／Rating／Color Label
- オンデバイスPeople顔検出、候補、命名、統合、解除、無視
- Library／Map／Peopleワークスペース
- GPS表示・編集、GPX照合、保存地点、位置情報を除外した書き出し

### UI

- SwiftUI＋AppKitのmacOSネイティブUI
- Library／Map／People切替
- Sidebar／Preview／Inspectorの3ペイン構成
- フィルムストリップとサムネイルグリッド
- 複数選択
- RGBヒストグラムとクリッピング表示
- 写真上で操作するCrop、Guided Upright、Repair、Mask、Color Sample
- Compare、Survey、Reference専用レイアウト
- ネイティブメニュー、ツールバー、キーボードショートカット
- 処理進捗、警告、復元可能な永続状態

## 未実装または意図的に次へ送る仕様

- HDR Photo Merge
- Panorama Merge
- 学習型RAW Denoise、Raw Details、Super Resolution
- 生成AI／Content-Aware Remove
- Adobe DCPカメラプロファイル
- Adobe相当のレンズプロファイルデータベース
- Copy as DNG
- テザー撮影
- Print／Book
- クラウド同期、モバイル、Web、共同編集
- プラグイン基盤
- Adobeローカルマスクの完全互換
- Developer ID署名、Hardened Runtime、Notarization、App Store配布

## 次のゴール候補

> RAWDeskを、高速・ローカル完結・安全な写真管理・高品質な現像・
> 洗練されたmacOS UIを持つ、日常利用できるプロ向け写真アプリとして
> 完成させる。

推奨する次の評価基準:

1. 10万枚規模のカタログで実用速度を維持する。
2. 一般的なRAWで安定した高品質現像を提供する。
3. 主要操作を迷わず実行でき、処理状態と失敗理由が常に見える。
4. 原本を変更せず、クラッシュ後もカタログと編集状態を復元できる。
5. 必要になった機能だけを、実使用の不満に基づいて追加する。

