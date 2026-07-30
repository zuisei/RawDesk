# Archived — People (face recognition)

これらのファイルは RAWDesk から**除去された** People / 顔認識機能の実装である。
参考と復元のために残してあるだけで、**ビルド対象ではない**。`Sources/` の外に
あるため SwiftPM のターゲットに含まれず、コンパイルもリンクもされない。

**除去日:** 2026-07-31

## なぜ除去したか

写真の選別と現像に集中するため。監査で判明した具体的な負荷は次のとおり:

- `CatalogStore.swift` の6箇所に分散した約860行
- スキャン中、解析した写真1枚ごとにアプリのルートビューと Library sidebar を
  再評価していた
- People の refresh がメインアクター上で catalog の全同期ロードと
  O(n²) の顔クラスタリングを行っていた
- 3つある集計のうち2つは毎回計算されるがUIから読まれていなかった
- 未使用でもスキーマ・設定ファイルI/O・analyzer インスタンスが起動時に
  無条件で構築されていた
- 取り込み後の People 解析が2箇所に重複実装され、ユーザー向け文言も重複していた

## ファイル

| ファイル | 元の場所 |
|---|---|
| `PeopleAnalyzer.swift` | `Sources/RAWDesk/Services/` |
| `PeopleModels.swift` | `Sources/RAWDesk/Models/` |
| `PeopleViewModel.swift` | `Sources/RAWDesk/ViewModels/` |
| `PeopleWorkspaceView.swift` | `Sources/RAWDesk/Views/` |

## カタログ互換性 — 重要

**`CatalogStore` の People 用テーブル定義とマイグレーションは意図的に残してある。**

マイグレーションは一方向で、ダウングレード経路がない。以前のバージョンが書いた
カタログには People のテーブルが存在するため、スキーマ定義やマイグレーションの
段階を削除・番号変更すると、既存カタログが開けなくなるか破損する。

したがって残っているのは**スキーマだけ**で、それを読み書きするコードは無い。
テーブルは空のまま無害に存在する。

## 復元するには

この4ファイルを上表の元の場所へ戻し、除去コミットを参照して呼び出し側を
復旧する。git 履歴に完全な差分がある:

```bash
git log --oneline -- Archive/People
```

除去は単一のコミットにまとめてあるので、`git show <commit>` で
「何が消されたか」がそのまま読める。
