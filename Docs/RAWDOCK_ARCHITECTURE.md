# RAWDesk — Architecture

Domain model, module map, storage model, and end-to-end data flows, reconstructed
from source. Every claim carries a `file:line` citation. Where implementation and
documentation disagree, implementation is treated as authoritative and the
conflict is recorded.

---

## 1. Shape of the codebase

Single-target macOS 14+ SwiftUI application. **No third-party dependencies** —
`Package.swift` declares only a link against system `sqlite3` (`:16-18`). The
entire stack is Apple frameworks: SwiftUI, AppKit, CoreImage, ImageIO, Vision,
MapKit, QuickLookThumbnailing, CryptoKit.

| Layer | Path | Files | Lines |
|---|---|---|---|
| Views | `Sources/RAWDesk/Views/` | 30 | ~30,700 |
| Services | `Sources/RAWDesk/Services/` | 31 | ~21,400 |
| Models | `Sources/RAWDesk/Models/` | 33 | ~9,300 |
| ViewModels | `Sources/RAWDesk/ViewModels/` | 3 | ~7,050 |
| App | `Sources/RAWDesk/App/` | 1 | 706 |
| **Total source** | | **98** | **~68,500** |
| Tests | `Tests/RAWDeskTests/` | 3 | ~18,450 |

Two build systems coexist and must be kept in sync by hand: SwiftPM
(`Package.swift`) and XcodeGen (`project.yml` → `RAWDesk.xcodeproj`). Marketing
version `0.1.1`, build `2` (`project.yml:11-12`).

**The app is not sandboxed.** `ENABLE_HARDENED_RUNTIME: NO`, ad-hoc signing
(`CODE_SIGN_IDENTITY: "-"`), and no entitlements file (`project.yml:16-18`). This
is why it can read and write arbitrary user folders. Security-scoped bookmarks
are nonetheless implemented and used (`SecurityScopedBookmarkStore.swift`, used
at `LibraryViewModel.swift:1149`, `:3175` and
`AutoImportSettingsStore.swift:55-61`), so a future sandboxed build is
anticipated.

### Structural observation

`LibraryViewModel` (5,369 lines) is a god object. It owns catalog access,
selection, filtering, import, XMP, stacks, collections, people, map state, undo,
and adjustment editing. `EditingInspectorView` (6,019) and `CatalogStore` (6,012)
are comparably large. These three files plus `PhotoProcessor` are ~20,800 lines —
**30% of the codebase in four files.** Any significant change touches at least
one of them.

---

## 2. Domain model

### 2.1 `PhotoAsset` — the central entity

`Models/PhotoAsset.swift`. An immutable-identity value type. Key fields:

| Field | Type | Note |
|---|---|---|
| `id` | `String` | Primary key. **See §3.1 — this is the riskiest design decision.** |
| `url` / `path` | `URL` / `String` | Always a real filesystem path. No opaque library container. |
| `format` | `FileFormat` | Derived from **extension only** (`FileTypeDetector`) |
| `catalogMissing` | `Bool` | File absent from disk but retained in catalog |
| `loadState` | `ImageLoadState` | Idle / loading / loaded / failed |
| `rawDecodeSource` | `DecodeSource?` | Which decode stage actually succeeded — **load-bearing, see §5.2** |
| `metadata` | `PhotoMetadata?` | EXIF/IPTC read via ImageIO |
| `userState` | `PhotoUserState` | All user-authored data (see §2.2) |
| `xmpSidecarURL` | `URL?` | Detected sibling `.xmp` |

**There is no separate "photo" and "file" entity.** A `PhotoAsset` *is* a file.
There is no version/master hierarchy at the asset level; edit versions live
inside `userState`.

### 2.2 `PhotoUserState` — everything the user authored

`Models/PhotoUserState.swift` (374 lines). Carries rating, pick/reject, favorite,
color label, keywords, note, location override/removal, `PhotoAdjustments`, and
`EditVersion` list. Serialized as JSON and stored in **two** places (§3.3).

### 2.3 `PhotoAdjustments` — the develop stack

`Models/PhotoAdjustments.swift`, 46 public fields covering tone, color,
tone curve, color mixer, point color, color grading, camera calibration, local
masks, spot removal, effects (texture/clarity/dehaze/vignette/grain), detail
(sharpening + luminance/color noise reduction), optics, geometry, and crop.

**All 46 are consumed by `PhotoProcessor`** — verified by grepping each field
name against `Services/PhotoProcessor.swift`; every one resolves. The develop
model is not decorative.

`isNeutral`/`editCount` (`:148-150`) give an O(1) "has this been edited" check
used to short-circuit rendering (`PhotoProcessor.swift:232`).

### 2.4 Supporting domain types

- **Organization:** `CatalogModels.swift` — collections, collection sets, smart
  collections, quick collection, keyword definitions, photo stacks.
- **People:** `PeopleModels.swift` — persons and face observations (Vision-based).
- **Import:** `PhotoImportModels.swift`, `PhotoImportTemplate.swift`,
  `AutoImportModels.swift`.
- **Color:** `SoftProofSettings.swift`, `DevelopmentProfile.swift`,
  `PhotoColorLabelSet.swift`.
- **Geo:** `PhotoLocation.swift`, `GPXTracklog.swift`, `SavedMapLocation.swift`.

---

## 3. Storage model

Everything lives in `~/Library/Application Support/RAWDesk/`, resolved by
`RAWDeskStorageDirectory.resolve` (`:41-55`). Two overrides exist: the
`RAWDESK_SUPPORT_DIRECTORY_OVERRIDE` env var (`:11-24`) and automatic test-process
detection that redirects to a per-PID temp directory (`:25-40`) — the latter is
why the test suite cannot touch a real catalog.

### 3.1 File identity — the foundational risk

`PhotoLibraryScanner.stableID` (`:189-200`) is the key generator for both stores:

1. **Preferred:** `"file-resource|" + fileResourceIdentifier` — Apple's opaque
   per-volume file identifier.
2. **Fallback:** `"path|size|mtimeInterval"` (`legacyStableID`, `:202-205`).

This value is the SQLite primary key (`CatalogStore.swift:3707`).

What is **provable from code alone**: the fallback tier is `path|size|mtime`, so
identity breaks whenever a file is moved or its modification time is rewritten —
which many backup, sync, and metadata tools do routinely. When that happens, the
photo is re-cataloged as a new, unedited asset. There is **no content-hash-based
recovery**, even though `content_hash` and `image_content_hash` columns exist and
are populated.

The primary tier carries an additional, *unverified* concern: `fileResourceIdentifier`
is an opaque OS-supplied value, and whether it survives reboots and volume
remounts across APFS/HFS+/exFAT/network volumes was **not** established here —
attempting to confirm Apple's documented contract was inconclusive, and no test
in the repo exercises it. Treated as inference, not fact. See
`RAWDOCK_OPEN_QUESTIONS.md` Q2, which proposes a one-hour experiment to settle it.

Note the fallback risk alone is sufficient to justify adding content-hash
recovery, independent of how the primary tier behaves.

Full analysis in `RAWDOCK_DATA_SAFETY.md` §6.4. This is the highest-leverage
architectural question in the repository.

### 3.2 SQLite catalog — `CatalogStore.swift` (6,012 lines)

Direct C-API SQLite. No ORM. Serialized through a `DispatchQueue`
(`queue.sync`), WAL journaling, `synchronous = NORMAL`, `foreign_keys = ON`,
5s busy timeout (`:3663-3685`).

**Schema — `PRAGMA user_version = 12`** (`:4227`), 15 tables:

`catalog_roots`, `catalog_photos`, `catalog_photo_keywords`,
`catalog_collection_sets`, `catalog_smart_collections`, `catalog_collections`,
`catalog_collection_members`, `catalog_quick_collection`,
`catalog_keyword_definitions`, `catalog_culling_analysis`, `catalog_people`,
`catalog_face_analysis`, `catalog_faces`, `catalog_photo_stacks`,
`catalog_photo_stack_members`.

`catalog_photos` (`:3706-3741`) stores both the full `state_json` blob **and**
denormalized index columns (rating, pick, favorite, color label, lat/long, capture
date, camera, lens) so smart collections can filter in SQL rather than in memory.
`content_hash` and `image_content_hash` back duplicate detection.

**Migration strategy is additive-only:** `CREATE TABLE IF NOT EXISTS` plus
`tableHasColumn`-guarded `ADD COLUMN` (`:4230-4243`). There are no numbered
migration steps and no down-migrations; `user_version` is set to 12
unconditionally at the end. Consequence: **a newer catalog opened by an older
build is not detected or rejected.** Verified as tested for the forward direction
— the suite migrates real v6 and v7 databases.

**Corruption recovery** (`:3624-3648`): `quick_check` on open; on corruption the
DB is renamed to `.corrupt.<timestamp>` (preserved, never deleted, `:4255-4269`),
a fresh catalog is created, and a warning is set. If that also fails, it degrades
to an **in-memory catalog** whose contents are lost at quit (`:3651-3661`).

### 3.3 JSON stores — and the dual-write problem

| File | Owner |
|---|---|
| `user_state.json` | `UserStateStore.swift` |
| `recent_folders.json` | `RecentFolderStore.swift` |
| `auto_import.json` | `AutoImportSettingsStore.swift` |
| `saved_map_locations.json` | `SavedMapLocationStore.swift` |
| `people_preferences.json` | `PeopleModels.swift:50` |
| color label sets | `PhotoColorLabelSetStore.swift` |

**`user_state.json` duplicates `catalog_photos.state_json`.** Both are written on
every state change (`LibraryViewModel.swift:4220-4227`), and the catalog write is
`try?` — silently dropped on failure. No reconciliation pass exists. This is a
genuine dual-source-of-truth hazard.

`UserStateStore.persistLocked` (`:79-88`) re-encodes and rewrites the **entire**
dictionary on every `set`. O(n) per edit; a scaling cliff on large libraries.

All JSON stores share a corrupt-file pattern: rename to `.corrupt.<ts>`, start
fresh (e.g. `UserStateStore.swift:26-31`).

### 3.4 External drives and offline files — the thinnest area

RAWDesk has **no concept of a volume**. There is no volume identifier, no volume
name, and no mount-state tracking anywhere in the schema or the models —
`catalog_photos` stores only `path` and `root_path` (`CatalogStore.swift:3708-3709`).

Consequently there is **one** offline state, not two: `PhotoAsset.catalogMissing`.
A photo on an unplugged external drive is indistinguishable from a photo the user
deleted. Both surface identically in the "Missing Files" smart collection
(`CatalogModels.swift:64-65`), both dim in the grid
(`ThumbnailCellView.swift:123`), and both offer the same remedies —
*Locate Original…* and *Remove from Catalog…*.

What this means in practice:

- Unplugging a drive marks its entire contents missing. Replugging requires a
  rescan to clear the state; there is no mount notification handler.
- Bulk relink is not available — `locateMissingPhoto` (`LibraryViewModel.swift:2877`)
  is strictly per-photo, via `NSOpenPanel`. Reconnecting a 2,000-photo drive whose
  mount point changed would mean 2,000 dialogs.
- Security-scoped bookmarks are stored for import roots and watched folders, but
  **not** per photo, so they do not help re-resolve moved originals.
- Identity compounds this: on remount, `fileResourceIdentifier` may differ and the
  `path|size|mtime` fallback keys on a path that has changed (§3.1).

No documentation claims removable-volume support, so this is a genuine gap rather
than a broken promise — but it is the weakest part of the storage model for any
photographer working off external drives, which is the common case for this
product's target user.

### 3.5 Image cache — `ImageCache.swift`

Three-tier: thumbnail `NSCache` (4,096 entries / 256 MB), a second 4,096-entry
cache, and a preview cache (32 entries / 512 MB) (`:12-26`), backed by a disk
cache under Application Support with LRU eviction touched via `setAttributes`
(`:70`).

Cache key: `"path|size|mtime|target|scale"` (`:57-60`). **The key does not include
adjustment state** — cached images represent the *unedited* file. Correct for
grid thumbnails; means the cache cannot serve edited previews.

---

## 4. Module map

### Services (`Sources/RAWDesk/Services/`)

| Module | Lines | Responsibility |
|---|---|---|
| `CatalogStore` | 6012 | SQLite persistence, smart collections, stacks, people, duplicates |
| `PhotoProcessor` | 3381 | CoreImage develop pipeline; consumes all 46 adjustments |
| `XMPSidecarService` | 2031 | Read/write Adobe-compatible `.xmp` sidecars |
| `PhotoImportService` | 1327 | Verified copy/move import, templates, dedup |
| `AssistedCullingAnalyzer` | 1344 | Sharpness/exposure scoring for cull suggestions |
| `AuxiliaryMaskGenerator` | 701 | Vision-based masks (sky, subject, background) |
| `SoftProofProcessor` / `SoftProofProfileCatalog` | 531 / 421 | ICC soft-proofing |
| `PeopleAnalyzer` | 473 | Vision face detection and clustering |
| `AutoImportService` | 367 | Watched-folder ingest (**destructive**, see §6.2) |
| `RAWImageLoader` | 299 | Layered RAW decode with silent fallback |
| `ImageExporter` | 278 | The **only** image-writing code in the app |
| `FileContentHasher` | 304 | SHA-256 + metadata-insensitive image-data hash |
| `PhotoLibraryScanner` | 217 | Folder enumeration, identity assignment |
| others | | caching, metadata, GPX, bookmarks, small stores |

### ViewModels

`LibraryViewModel` (5,369) is the application core. `PhotoViewerViewModel` (1,107)
handles single-image viewing; `PeopleViewModel` (576) the people workspace.

### Views

Four top-level destinations — `WorkspaceDestination`: `library`, `develop`,
`people`, `map` (`Models/WorkspaceMode.swift:92-121`). Note that a **second,
overlapping** enum `WorkspaceMode` exists with only `library`/`people`/`map`
(`:135-162`), and a third, `PhotoWorkspaceMode`, with `library`/`develop`
(`:3-28`). Three overlapping navigation enums is a real source of confusion.

Library sub-modes: `grid` / `loupe` (`LibraryDisplayMode`, `:30`). Develop canvas
tools: `crop`, `remove` (heal/clone), `mask`, `guidedUpright`, `pointColor`
(`DevelopCanvasTool`, `:57`). Compare, Survey, and Reference are *layout
planners* over the library (`PhotoComparePlanner` `:196`,
`PhotoSurveyPlanner` `:403`, `PhotoReferencePlanner` `:581`), not separate
destinations.

---

## 5. End-to-end data flows

### 5.1 Import

```
PhotoImportView
  → PhotoImportService.preflight()      discover, hash, detect duplicates
  → PhotoImportService.execute()
      ├ collisionSafeDestination()      never overwrite; numbered suffixes
      ├ verifiedCopy()                  temp → SHA-256 verify → atomic move
      ├ CatalogStore.upsert()           commit catalog record
      └ removeVerifiedMoveSource()      MOVE ONLY: re-verify both, then delete
  → LibraryViewModel refresh
```

Three modes (`PhotoImportModels.swift:3-37`): `addInPlace` (referenced),
`copyToFolder` (managed copy), `moveToFolder` (managed move + **permanent
delete**). Deletion is fully analyzed in `RAWDOCK_DATA_SAFETY.md` §3.

### 5.2 Scan / index

```
PhotoLibraryScanner.scan()
  → FileTypeDetector.isSupported()      extension-based filter
  → inspectAsset()
      ├ stableID()                      identity (§3.1)
      ├ MetadataReader.read()           ImageIO container metadata, no decode
      ├ XMPSidecarService.read()        only if no stored state exists
      └ userStates[id] ?? userStates[legacyID]
  → sorted by capture date desc
```

Metadata is read for **every** file at scan time, deliberately — so
library-wide features (capture-time auto-stacking) do not depend on which
thumbnails the user happened to open (`PhotoLibraryScanner.swift:135-140`).

### 5.3 Render

Two distinct paths, and the distinction matters:

**Grid (fast path):** `RAWImageLoader.loadGridThumbnail` (`:135-143`) →
`tryImageIOEmbeddedOnly`, which sets *both* thumbnail-generation flags to `false`
(`:164-171`) so a RAW mosaic is **never** decoded merely to populate a scrolling
grid. Deliberate and well-commented.

**Loupe / Develop / Export:** `RAWImageLoader.loadResult` (`:77-130`) — a
four-stage fallback chain:

```
CIRAWFilter  →  CIImage  →  ImageIO embedded preview  →  QuickLook
```

`CIRAWFilter` is configured with draft mode off, lens correction on when
supported, and highlight recovery on macOS 16+ (`:193-202`).

**RAWDesk implements no demosaic of its own.** RAW support is entirely whatever
macOS/CoreImage provides; `FileFormat` merely labels extensions. Consequently
the format list is a statement about *recognition*, not verified decode quality.

The fallback is **silent**. The stage that succeeded is recorded in
`PhotoAsset.rawDecodeSource`, but nothing consults it before export — so a
"full-resolution" export can be derived from a 4096 px embedded JPEG. See
`RAWDOCK_DATA_SAFETY.md` §6.2.

### 5.4 Develop

`PhotoProcessor.develop` (`:220-`) builds a CoreImage filter graph from
`PhotoAdjustments`, short-circuiting when `isNeutral` and nothing is being
visualized (`:232`). Adjustments are **never** written to the source file — they
live in `PhotoUserState` and are re-applied on each render. Non-destructive
editing is real and structurally enforced by the fact that the only image-writing
code in the app targets a user-chosen export path.

### 5.5 Export

`ImageExporter.export(asset:adjustments:…)` (`:87-119`) →
`PhotoProcessor.renderFullResolution` → `applyTransform` →
`CGImageDestinationCreateWithURL`.

Export genuinely re-develops from the original at full resolution — it is not a
re-encode of the preview.

Constraints, all confirmed in code:
- **JPEG and PNG only** (`:8-25`). No TIFF, no 16-bit, no wide-gamut output.
- Always tagged `sRGB IEC61966-2.1` (`:134`), and rasterized through the
  non-wide `displayContext` (`RAWImageLoader.swift:290-294`), since
  `renderFullResolution` does not pass `preserveWideGamut`.
- EXIF and IPTC are copied from the source; orientation is normalized to `1`
  (`:133`, `:164`); GPS is copied, replaced, or suppressed per user state
  (`:154-202`).

### 5.6 XMP

Read on scan when no stored state exists (`PhotoLibraryScanner.swift:148-167`).
Written **only** on explicit user command —
`LibraryViewModel.saveMetadataToXMPSidecars()` (`:4198`) is the single call site.
Target is always `basename.xmp`, never the image (`XMPSidecarService.swift:97-99`).

---

## 6. Concurrency

- `PhotoLibraryScanner`, `PhotoImportService`, `AutoImportService`,
  `PeopleAnalyzer` are **actors**.
- `CatalogStore` is a class serialized by an internal `DispatchQueue`, exposed as
  a `shared` singleton.
- `LibraryViewModel` is `@MainActor`.
- Heavy work is dispatched via `Task.detached(priority: .userInitiated)` —
  e.g. export (`ImageExporter.swift:96`).
- `UserStateStore` is `@unchecked Sendable` with a private serial queue.

Cancellation is honored in scanning (`PhotoLibraryScanner.swift:70`), hashing
(`FileContentHasher.swift:13`), and import.

---

## 7. Notable architectural risks

1. **Identity** (§3.1) — persisting a non-persistent OS identifier as a primary key.
2. **Dual state stores** (§3.3) — JSON and SQLite both authoritative, no reconciliation.
3. **Silent RAW fallback** (§5.3) — quality degradation invisible to the export path.
4. **Three overlapping navigation enums** (§4) — `WorkspaceDestination`,
   `WorkspaceMode`, `PhotoWorkspaceMode`.
5. **Four files hold 30% of the code** — change amplification.
6. **Additive-only migrations** (§3.2) — no forward-compatibility guard.
7. **No volume awareness** (§3.4) — an unplugged drive is indistinguishable from
   deleted files, and relink is per-photo only.
