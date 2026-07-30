# RAWDesk 最新Release Runtime QA — 2026-07-30

対象仕様: `~/Downloads/RAWDesk_UI改善書_v1.0-draft.md`  
対象画面サイズ: 1296 × 768、1100 × 700  
実画像: `testraw/ETH01641.ARW`、`ETH01535.JPG`、`IMG_0002.CR2`

## 安全境界

- 初回captureでは
  `RAWDESK_SUPPORT_DIRECTORY_OVERRIDE=/tmp/rawdesk-ui-qa-20260730`を指定し、
  通常のApplication Supportを使わずに起動した。ただし、この変数だけでは
  SwiftUI `@AppStorage`とmacOS window stateが通常のRAWDesk preference
  domainを使うことが監査で判明した。
- 最終再確認では`scripts/run-isolated-ui-qa.sh --reset`を使用する。
  このscriptはrelease appを一時QA directoryへ複製し、bundle identifierを
  `local.rawdesk.app.uiqa`へ変更して再署名する。さらに`HOME` /
  `CFFIXED_USER_HOME`とApplication Support overrideも一時directoryへ向ける。
  これにより通常の`local.rawdesk.app` preference domain、catalog、cache、
  user state、window stateをQAから分離する。再起動復元時は`--reset`なしで
  同じscriptを使い、終了後は`--cleanup`だけを実行する。
- 隔離scriptのsmoke testではQA appが`local.rawdesk.app.uiqa`へ
  window frameとpane初期値を書き、通常の`local.rawdesk.app.plist`は
  SHA-256と更新日時の両方が不変だった。`--cleanup`後はQA app /
  support / preference domainがすべて消えた。
- 初回captureで確実に変更した通常設定
  `rawdesk.ui.libraryDisplayMode`は、QA前に観察した`grid`へ復元した。
  事前値を記録していない他の通常設定は推測で削除・上書きしていない。
- Importは`Add`だけを実行した。Copy / Moveは選択状態と安全説明だけを確認し、
  ファイル転送や削除は実行していない。
- Keychain、Chrome、外部アカウント、macOSシステム設定には触れていない。
- QA後にRAWDeskを終了し、fixture 3点のSHA-256が開始前と同一で、
  XMP / XMLが追加されていないことを確認した。

## Runtime確認

| Step | 画面 / 状態 | 結果 | 証拠 |
|---:|---|---|---|
| 1 | Welcome / Empty | PASS | `Evidence/2026-07-30/ui-spec-runtime/01-welcome-current-release.png` |
| 2 | Import source空 / 3領域 / Footer | PASS | `02-import-empty-current-release.png` |
| 3 | Sony ARW + JPEG + CR2 preflight | PASS | `03-import-preflight-current-release.png` |
| 4 | Preflight detail popover | VISUAL PASS / AX FIXED IN SOURCE | `04-import-preflight-popover-current-release.png` |
| 5 | Move安全説明 / destinationなし / CTA disabled | PASS | `05-import-move-safety-current-release.png` |
| 6 | Add完了結果 3 imported / 0 failed | PASS | `06-import-result-current-release.png` |
| 7 | Library Grid / 3-pane | PASS | `07-library-grid-current-release.png` |
| 8 | Sony ARW selected / active photo | PASS | `08-library-sony-selected-current-release.jpg` |
| 9 | Info: `RAW (CIRAWFilter)` / `SONY ILCE-7M4` | PASS | `09-library-sony-info-current-release.jpg` |
| 10 | Library Loupe / Filmstrip | PASS | `10-library-loupe-current-release.jpg` |
| 11 | Develop / Tool Rail / Inspector / Filmstrip | PASS | `11-develop-current-release.jpg` |
| 12 | Soft Proof ON / profile常設表示 | PASS | `12-develop-soft-proof-current-release.jpg` |
| 13 | People / local-only説明 / empty state | PASS | `13-people-current-release.jpg` |
| 14 | Map / catalog-only位置編集説明 | PASS | `14-map-current-release.jpg` |
| 15 | Compare / Select-Candidate role / Done | PASS | `15-library-compare-current-release.jpg` |
| 16 | Import方式の単一AX selected / Preflight全detail AX value | PASS | `16-import-preflight-ax-fixed-current-release.jpg` |
| 17 | Survey / Active・Selected role / Done / Filmstrip role | PASS | `17-library-survey-current-release.jpg` |
| 18 | Reference / Active role / editable・static / Done / Filmstrip role | PASS | `18-library-reference-current-release.jpg` |
| 19 | 隔離catalog再起動 / 3 photos / Loupe / Catalog section collapse復元 | PASS | `19-restart-persistence-current-release.jpg` |

Step 1–15は視覚QAを行ったrelease binary
`aae3204a4f4d7fb0968b8266698c137b3719caae4caf288212565ce68f7149a9`
の証拠である。Step 16–19は修正後の最終release binary
`8371b178924988cb22026a4fec0ac0e5afe10f6a2f4a2baa7e476197b13cdc67`
を1100×700で確認した証拠である。全画面でopaqueなchrome / panel背景、固定Toolbar、
240pt Sidebar、300pt Inspector、単一Primary CTA、非色依存のrole labelを
確認した。

仕様書が根拠とした4枚のReferenceと、同じ1296×768の現行画面を
同一画像で比較・再点検した。

- `compare-01-welcome-reference-current-1296x768.jpg`
- `compare-02-library-reference-current-1296x768.jpg`
- `compare-03-develop-reference-current-1296x768.jpg`
- `compare-04-import-reference-current-1296x768.jpg`

Welcomeは無効paneと初回用でない機能一覧を撤去し、目的、Drop、
Open / Import差、安全文を一つの読順にまとめた。Libraryは常設previewと
Develop inspectorを撤去した。DevelopはTool Railと固定Histogram /
Profile、Accordion、Filmstripを明確に分離した。Importは透過縦一列から
opaqueな3領域と固定Footerへ置き換わっている。比較画像上でcrop、
重なり、主要CTA欠落、壊れた余白は認めなかった。

## Runtimeで見つかった問題と修正

### Import方式の選択状態

視覚上はAdd / Copy / Moveのうち1つだけが選択されていたが、
Accessibility treeではAddとCopyが同時に`selected`と報告された。
選択円とSafe badgeを装飾要素としてAXから除外し、各Buttonへ
`isSelected` traitの追加 / 除去と`Selected` / `Not selected` valueを
明示した。

### Preflight detail

Popover本文は視覚表示されていたが、Accessibility treeが本文の各値を
公開していなかった。Popover rootへ`Preflight Details` labelと、
Unavailable / copy size / XMP / naming conflict / warning全文をまとめた
valueを追加した。

最終releaseではAddだけが`selected`、Copy / Moveは`Not selected`となり、
Popover rootが
`Unavailable 0. Estimated copy size No copy. XMP companions 0.
Naming conflicts No destination naming for Add. Warnings 0.`
を公開することをAccessibility treeで確認した。

### Catalogの再起動復元

隔離catalogへAddした3枚はSQLiteに残っていたが、最初の再起動では
Welcomeへ戻った。原因はAdd importがopened-folder workspaceを作らない一方、
起動復元がRecent Folderだけを入口にしていたことだった。Recent Folderがなくても
catalogに写真があればAll Photographsを開くfallbackを追加した。

修正後は同じ隔離catalogを再起動し、3 photos、Sony ARW選択、Loupe、
Catalog sectionのcollapseがすべて復元された。

修正位置:

- `Sources/RAWDesk/Views/PhotoImportView.swift`
- `Sources/RAWDesk/Models/PhotoImportModels.swift`
- `Sources/RAWDesk/ViewModels/LibraryViewModel.swift`
- `Tests/RAWDeskTests/UIStateContractTests.swift`
- `Tests/RAWDeskTests/RAWDeskTests.swift`

修正後の自動検証:

- 336 tests / 0 failures
- Sony実ARW統合試験: PASS、skipなし
- UI state-contract tests: 21 / 21 PASS
- catalog-only workspace restore regression test: PASS
- 最終release SHA-256:
  `8371b178924988cb22026a4fec0ac0e5afe10f6a2f4a2baa7e476197b13cdc67`
- `codesign --verify --deep --strict`: PASS
- entitlements: なし

## 最終実行結果と残る受け入れ

08:54 JSTに画面ロックで止まった5項目は、解除後の09:32 JSTまでにすべて
再実施してPASSとなった。QA終了後は`scripts/run-isolated-ui-qa.sh --cleanup`
を実行した。

終了時の安全状態:

- RAWDesk process: なし
- 既知の`/tmp/rawdesk-*` QA directory: なし
- `local.rawdesk.app.uiqa` preference domain: なし
- 通常設定の`rawdesk.ui.libraryDisplayMode`: `grid`
- 通常設定plist SHA-256:
  `ef9bcaa5defd6f39041a86e54d70464a066fdbab17f103bef01c5e11eb461255`
  （更新日時 2026-07-30 08:44:32 JST）
- Release SHA-256:
  `8371b178924988cb22026a4fec0ac0e5afe10f6a2f4a2baa7e476197b13cdc67`
  / strict codesign verification PASS
- fixture 3点: 記録済みSHA-256と一致、XMP / XMLなし
- Keychain、Chrome、外部アカウント、macOSシステム設定: 未操作

本spot checkで保留だった修正版AX、Survey / Reference、catalog再起動は
完了した。要件表に残る個別の狭幅・keyboard・loading / error状態の
手動行は、合格へ読み替えず`PENDING-RUNTIME`のまま管理する。
初見ユーザー3名以上の理解度試験と、macOS accessibility設定を実際に
切り替える手動マトリクスは、このruntime spot checkとは別の外部受け入れ作業である。
