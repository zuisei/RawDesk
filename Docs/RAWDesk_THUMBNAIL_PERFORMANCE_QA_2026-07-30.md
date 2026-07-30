# RAWDesk RAW Thumbnail Performance QA — 2026-07-30

対象: RAWDesk 0.1.1 (build 2), macOS 14+  
発端: 4,706 photosのLibrary Gridで、可視範囲のRAW thumbnailが
一斉にspinnerのまま待機する実画面

## 実データ診断

通常catalogはread-only queryで次の状態だった。

| 項目 | 実測 |
|---|---:|
| Catalog photos | 4,706 |
| Unique paths | 4,706 |
| RAW | 2,331 |
| Sony ARW | 2,102 |
| Canon CR2 | 225 |
| DNG | 4 |
| Missing | 0 |
| Persistent thumbnails | 255 |
| Persistent thumbnail size | 4.2 MB |

重複pathやmissing fileが原因ではない。主因はthumbnail loaderにあった。

1. RAWのdisk thumbnailが存在しても、decoder source metadataが
   process memoryにない場合は画像を返さず、起動ごとにRAWを再decodeしていた。
2. Grid thumbnailでもembedded camera previewより先に
   `CIRAWFilter` / `CIImage`を試していた。
3. 同時実行gateは3本の単純FIFOで、画面外になってcancelされたwaiterを
   queueから除去せず、permitをresume後まで予約しなかった。
4. thumbnail成功ごとにLibrary全体へ`@Published assets`更新を送り、
   4,706件のfilter / sortとView invalidationを誘発していた。
5. 既存の10,000-photo performance testはin-memory filter / sortだけで、
   RAW source I/O、disk cache再起動、first viewportを検証していなかった。

## 修正

- RAW disk cache hitはdecoder metadataがなくても即時表示する。
- decoder sourceを`.raw-source` companionへ永続化し、判明済みの場合は
  再起動後も再検査しない。
- Gridはembedded camera thumbnailだけを先に取得する。
  embedded thumbnailがない場合だけ従来のfull RAW pipelineへfallbackする。
- Loupe / Develop / exportは従来どおりfull RAW pipelineを使う。
- Preview / Loupe waiterをthumbnailより優先する。
- cancelされた画面外waiterをqueueから除去する。
- permitをresume前に予約し、設定した同時実行上限を超えないようにする。
- 通常のGrid成功はLibrary全体へload-state mutationを送らない。
  decoder / failureなどユーザーに意味のある結果だけを伝播する。

主な実装:

- `Sources/RAWDesk/Services/ImageLoader.swift`
- `Sources/RAWDesk/Services/ImageCache.swift`
- `Sources/RAWDesk/Services/RAWImageLoader.swift`
- `Sources/RAWDesk/Views/ThumbnailCellView.swift`

## 自動検証

最終全試験:

```sh
RAWDESK_SUPPORT_DIRECTORY_OVERRIDE=/tmp/rawdesk-thumbnail-opt-full-20260730 \
  RAWDESK_SONY_ARW_FIXTURE_DIR=testraw \
  swift test
```

結果:

- 342 tests / 0 failures
- 全suite: 4.235 seconds
- 4,706-photo modelのwarm first viewport 24 RAW cells:
  0.056 seconds、source decode 0
- Sony ARW + Canon CR2 embedded fast path:
  PASS、原本hash不変
- queued thumbnail cancel:
  PASS、permit消費なし
- Preview priority:
  PASS、先に待っていたthumbnailよりPreviewが先に実行
- legacy thumbnail cache:
  PASS、decoder metadataなしでもsource fileを開かず復元
- decoder source companion:
  PASS、cache instance再生成後も復元

既存Sony end-to-end試験ではGrid thumbnailとfull RAW previewを分離し、
full-resolution Develop / JPEG export / original hash / XMP不在も
引き続き確認している。

## 隔離Release runtime

`scripts/run-isolated-ui-qa.sh`でbundle id、HOME、Application Support、
preferences、cacheを通常版から分離した。

- Cold isolated Add import後、Sony ARW / JPEG / Canon CR2の3枚すべてが
  spinnerではなく画像としてGridへ表示された。
- 同じisolated catalog / cacheを再起動し、最初のAX capture時点で
  3枚すべてが画像表示されていた。
- Sony ARWをLoupeへ切り替え、full previewを確認した。
- Infoは`RAW (CIRAWFilter)`、4608 × 3072、SONY ILCE-7M4を表示した。
- QA終了後はisolated app / support / preference domainを削除した。

通常版の実4,706-photo catalogも最終Releaseで起動した。

- folder refresh完了後、最初のviewportにあるJPEG / Sony ARWが
  spinnerではなくすべて画像表示された。
- 5 pages scroll後の未表示領域でも、可視範囲のJPEG / Sony ARWが
  すべて画像表示された。
- 安定後のprocess CPUは0.0%、RSSは約354 MBだった。
- persistent thumbnailは255から299へ増え、未cache領域のfast pathが
  新しいthumbnailを正常に保存した。
- catalogは4,706 photos / 2,331 RAW / missing 0を維持した。
- 通常preference plistのSHA-256とmtime、fixture 3点のSHA-256は
  起動前後で不変だった。

証拠:

- `Evidence/2026-07-30/performance/01-fast-grid-cold-release.jpg`
- `Evidence/2026-07-30/performance/02-fast-grid-warm-restart-release.jpg`
- `Evidence/2026-07-30/performance/03-normal-4706-fast-grid-release.jpg`
- `Evidence/2026-07-30/performance/04-normal-4706-scroll-fast-grid-release.jpg`

## Release / Safety

- Release binary SHA-256:
  `ea0c64972a3df1dd4c767ea0cd86eceb14e31466bc2ac1ccaf14628b8a38b52f`
- `codesign --verify --deep --strict`: PASS
- Keychain / Chrome / external account API追加なし
- Entitlement追加なし
- Import runtimeはAddのみ。Copy / Moveなし
- 元画像bytes、XMP、通常catalog、通常preferencesを隔離QAから変更しない
