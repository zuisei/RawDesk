# RAWDesk — Data Safety Audit

**Scope:** every code path capable of modifying, moving, replacing, or deleting an
original photograph or its associated metadata.
**Method:** exhaustive grep of all filesystem-mutation and image-write primitives
across `Sources/`, then manual trace of every hit to a verdict. No path was
accepted as safe by inference.
**Date:** 2026-07-30. **Commit state:** working tree, not a git repository.

> Naming note: the deliverable is specified as "RawDock". The product in this
> repository is **RAWDesk** everywhere (`Package.swift:5`, `project.yml:1`,
> bundle id `local.rawdesk.app`). No artifact in the repo uses "RawDock". Treated
> as an alias for the same product; filenames follow the requested spelling.

---

## 1. Method — how the surface was bounded

The safety claim in this document rests on the **completeness** of the following
two greps, not on spot checks. Both were run over all of `Sources/`.

**Filesystem mutation primitives:**

```
removeItem | moveItem | trashItem | replaceItem | copyItem
.write(to | write(toFile | createFile(
```

**In-place / out-of-band write primitives** (the paths that could corrupt an
original *without* a `FileManager` call):

```
CGImageDestinationCreateWithURL | FileHandle(forWriting | forUpdating
setAttributes | recycle | setUbiquitous | exiftool | Process( | posix_spawn
NSSavePanel | unlinkItem | link(at | symlink | truncate | O_WRONLY | O_TRUNC | fopen
```

Results that materially bound the risk surface:

- **Exactly one** image-writing call exists in the entire codebase:
  `ImageExporter.swift:59` (`CGImageDestinationCreateWithURL`).
- **Zero** subprocess spawns. No `exiftool`, no shell-outs. Nothing outside the
  Swift/Apple-framework sandbox touches photo bytes.
- **Zero** `FileHandle(forWritingAtPath:)` / `forUpdating` uses. `FileHandle` is
  used only for **reading**, in `FileContentHasher.swift:9`.
- **`trashItem` appears nowhere in the repository.** This is load-bearing —
  see §3.

Every remaining `removeItem`/`moveItem` hit is classified in §5.

---

## 2. Summary verdict

| Question | Answer |
|---|---|
| Can RAWDesk overwrite an original photo in place? | **No** — no code path writes to an existing photo's URL. |
| Can RAWDesk modify bytes inside an original? | **No** — no in-place write primitive is used anywhere. |
| Can RAWDesk delete an original? | **Yes — two paths**, both hash-verified first. |
| Do deletions go to the Trash? | **No. All deletions are permanent and unrecoverable.** |
| Can RAWDesk create files next to originals? | **Yes** — `.xmp` sidecars, user-initiated only. |
| Can "remove from catalog" delete a file? | **No** — catalog-only (`CatalogStore.swift:2271`). |

**Bottom line:** originals are structurally well protected against *corruption*.
The residual risk is concentrated entirely in **deletion**, and specifically in
the absence of a Trash safety net.

---

## 3. The two paths that delete originals

Both are *verified moves*: copy → hash-verify → catalog → delete source. Both use
permanent deletion.

### 3.1 Manual Move-mode import — **confirmed current behavior**

Chain: `PhotoImportView` → `PhotoImportService.execute` →
`removeVerifiedMoveSource` → `sourceRemovalHandler`.

Safeguards, in the order they execute (`PhotoImportService.swift:853-947`):

1. Source and target paths resolved through symlinks and standardized (`:857-865`).
2. Guard: source ≠ target, target is a true descendant of the chosen
   destination, and **both files still exist** (`:867-876`).
3. **Dual SHA-256 re-verification immediately before deletion** — both the
   source *and* the already-written target are re-hashed and compared against
   the hash recorded at copy time (`:878-885`). A source that changed on disk
   mid-import cannot be deleted.
4. Sidecar, if present, is verified the same way (`:887-908`).
5. Deletion, then a **post-delete existence check** that raises if the file
   survived (`:912-917`).
6. Failure at any step ⇒ source **retained** and surfaced to the user as
   `retainedSourceCount` (`:513-520`, shown at `PhotoImportView.swift:1629-1643`).

The copy that precedes it is equally careful — `verifiedCopy`
(`PhotoImportService.swift:1071-1093`) copies to a hidden temp file, hashes it,
and only then does an atomic `moveItem` into place. Destination collisions never
overwrite: `collisionSafeDestination` (`:1023-1069`) walks up to 10,000 numbered
suffixes and only reuses an existing file when its SHA-256 matches exactly.

**Assessment: this is the most rigorously engineered part of the codebase.**

**Residual risk — permanent deletion.** The default removal handler is:

```swift
sourceRemovalHandler: @escaping SourceRemovalHandler = {
    try FileManager.default.removeItem(at: $0)
}
```
— `PhotoImportService.swift:54-56`

`removeItem` is an **unlink, not a Trash move**. The production call site
(`LibraryViewModel.swift:243-245`) constructs the service **without** overriding
the handler, so production uses permanent deletion. The seam exists and is used
by tests, but no shipping code supplies a trashing handler.

### 3.2 Auto Import — **confirmed current behavior, and the highest-risk path**

`AutoImportService.swift:308-354`. Same dual-SHA-256 discipline (`:327-334`),
same permanent `removeItem` (`:351`, `:353`).

Three properties make this materially riskier than §3.1:

1. **It is unattended.** Triggered by `WatchedFolderMonitor`, not by a user
   action. There is no confirmation at the moment of deletion.
2. **Deletion is not optional.** `AutoImportSettings`
   (`AutoImportModels.swift:3-52`) has **no mode field**. There is no setting
   that turns the deletion off.
3. **The mode flag is bypassed, not honored.** The request is built with
   `mode: .copyToFolder` — the *non-destructive* mode
   (`AutoImportService.swift:148`) — and the service then deletes the source
   itself in its own loop at `:187`, entirely outside
   `PhotoImportMode.removesVerifiedSources`.

**This is a developer-facing trap, not a user-facing one.** The UI discloses the
behavior accurately and prominently — "Verified move", and *"…commits the catalog
record, and only then removes the watched-folder source"*
(`AutoImportSettingsView.swift:382-390`, `:107`). A user who reads the panel is
correctly informed.

But a developer reading `AutoImportService.swift:148` in isolation would
reasonably conclude auto-import is non-destructive. It is not. Anyone refactoring
import modes must know that `.copyToFolder` here does **not** mean the source
survives.

Mitigating factor: `enabled` defaults to `false`
(`AutoImportModels.swift:21`), and only files **directly** in the watched folder
are eligible — not subdirectories (`AutoImportService.swift:140`).

---

## 4. Paths that write near, but never into, originals

### 4.1 XMP sidecars — **confirmed, user-initiated only**

`XMPSidecarService.write` targets
`existingURL ?? canonicalSidecarURL(for: photoURL)` (`:696`), where
`canonicalSidecarURL` is `photoURL.deletingPathExtension() + ".xmp"` (`:97-99`).
**It can never resolve to the photo itself** — the extension is always replaced.
The write is atomic (`:1226`).

There is exactly **one** call site: `LibraryViewModel.saveMetadataToXMPSidecars()`
(`:4198-4212`), invoked by explicit user command. **XMP is never written
automatically** — not on edit, not on rating, not on import.

Residual risks:
- **Third-party sidecar collision.** RAWDesk writes to the same
  `basename.xmp` Adobe products use. It parses and preserves an existing packet
  (`preservedExistingPacket`, `:1231`) rather than clobbering it, which is the
  correct behavior — but any *unparsed* field in a foreign sidecar is at risk on
  rewrite. Not traced field-by-field; treat as **unverified**.
- **Silent payload truncation.** If RAWDesk's own state exceeds an internal size
  limit, the exact payload is dropped and only Adobe-compatible global fields are
  written. This is surfaced as a warning (`:1206-1209`), not an error, and
  `wroteExactRAWDeskPayload: false` is returned. Edits saved to XMP under this
  condition **will not round-trip exactly**.
- The sidecar is written into the **original's directory**, which may be a
  read-only volume or a card. Failure is reported, not silent.

### 4.2 Export — **confirmed safe by construction, with a correctness caveat**

`ImageExporter.export` writes to a URL chosen through `NSSavePanel`
(`ContentView.swift:1792`). The destination is user-selected and unrelated to the
source; AppKit provides the standard overwrite warning. The source is opened
read-only for metadata copying (`ImageExporter.swift:136-145`).

**Not a data-loss risk. Is a data-*fidelity* risk** — see §6.2.

---

## 5. Complete classification of remaining mutation sites

Every hit from the §1 greps, none omitted.

| Site | Operation | Verdict |
|---|---|---|
| `PhotoImportService.swift:55` | `removeItem` — default source-removal handler | **Deletes originals** (§3.1) |
| `AutoImportService.swift:351,353` | `removeItem` — source + sidecar | **Deletes originals** (§3.2) |
| `PhotoImportService.swift:1085,1092` | `copyItem`→temp, `moveItem`→final | Safe — writes only new files |
| `PhotoImportService.swift:1014,1017,1280,1283,1290` | `removeItem` rollback | Safe — deletes only files RAWDesk just created |
| `PhotoImportService.swift:1082` | `removeItem` temp cleanup | Safe — own temp file |
| `PhotoImportService.swift:1218,1245` | `removeItem` directory | Safe — only dirs RAWDesk created, only if empty (`:1240-1242`) |
| `XMPSidecarService.swift:1226` | `write(to:.atomic)` | Sidecar only (§4.1) |
| `ImageExporter.swift:59` | `CGImageDestinationCreateWithURL` | User-chosen destination (§4.2) |
| `CatalogStore.swift:4260,4266` | `moveItem` DB + WAL/SHM | Safe — **preserves** corrupt DB as `.corrupt.<ts>` (§6.1) |
| `UserStateStore.swift:29` | `moveItem` | Safe — backs up own corrupt JSON |
| `UserStateStore.swift:84`, `RecentFolderStore.swift:121`, `AutoImportSettingsStore.swift:71` | `write(to:.atomic)` | Safe — own app-support stores |
| `AutoImportSettingsStore.swift:39`, `SavedMapLocationStore.swift:43`, `PeopleModels.swift:66` | `moveItem` | Safe — corrupt-store backups |
| `ImageCache.swift:131,169,245` | `write`, `removeItem` | Safe — cache dir under Application Support |
| `ImageCache.swift:70` | `setAttributes` | Safe — cache dir attributes only |
| `SoftProofProfileCatalog.swift:211` | `copyItem` | Safe — imports an ICC profile into app storage |

**No unclassified mutation site remains.**

---

## 6. Failure modes and divergence risks

These do not destroy photographs, but they can destroy *work* or desynchronize
the catalog from the filesystem.

### 6.1 Catalog corruption recovery — safe, but silently lossy for the session

`openWithRecovery` (`CatalogStore.swift:3624-3648`): on `SQLITE_CORRUPT`/
`SQLITE_NOTADB` the database is **renamed, not deleted** (`:4255-4269`), a fresh
one is created, and the user is warned. Good design.

**But** if reopening also fails, it falls through to
`openMemoryFallback` (`:3651-3661`) — an **in-memory catalog**. The session then
appears to work normally while **every rating, keyword, and edit made in that
session is discarded at quit**. A `startupWarning` is set; whether the UI
surfaces it prominently enough is **unverified**.

### 6.2 Export can silently downgrade a RAW to its embedded preview

`renderFullResolution` (`PhotoProcessor.swift:188-199`) calls
`RAWImageLoader.load(targetLongestEdge: nil)`. That loader is a **silent
fallback chain** (`RAWImageLoader.swift:77-130`):
`CIRAWFilter → CIImage → ImageIO embedded preview → QuickLook`.

With `targetLongestEdge: nil`, QuickLook is correctly skipped (`:119`). But
**stage 3 is not**: if `CIRAWFilter` and `CIImage` both fail, export silently
proceeds from the **camera's embedded JPEG preview**, capped at **4096 px**
(`:243`), with adjustments applied on top of an already-baked JPEG.

The user receives a file presented as a full-resolution develop of their RAW.
There is no error, and no warning in the export path. The decode source *is*
tracked on the asset (`PhotoAsset.rawDecodeSource`), so the information exists —
it is simply not consulted before export.

**Classification: unsafe-by-omission.** Not photo loss; silent output-quality
loss. This is the strongest correctness defect found outside the deletion paths.

### 6.3 Relink does not verify identity and preserves stale metadata

`CatalogStore.relinkPhoto` (`:2091-2200`), reached from
`LibraryViewModel.locateMissingPhoto` (`:2877-2898`).

Validation performed: file is supported, is a regular file, and its **format
matches** (`:2121-2127`). Plus conflict checks against already-cataloged paths.

Validation **not** performed: no size check, no SHA-256 comparison — despite
`content_hash` and `image_content_hash` being present in the schema
(`:3736-3737`) and computed elsewhere. A user may relink a missing photo to **an
entirely different image of the same format**, silently transferring all ratings,
keywords, and edits onto it.

Worse, the replacement asset is constructed with `metadata: existing.metadata`
(`:2169`) — the **old file's EXIF is retained** and not re-read from the new
file. Capture date, camera, lens, and GPS can therefore describe a file that is
no longer there. The UI reports success: *"Existing edits and organization
metadata were preserved."* (`LibraryViewModel.swift:2946`) — technically true,
and misleading.

**Classification: unsafe.** Primary cause of catalog↔filesystem divergence.

### 6.4 File identity is fragile — the deepest architectural risk

`PhotoLibraryScanner.stableID` (`:189-200`):

```swift
if let resourceIdentifier, let stableResource = resourceIdentifierString(...) {
    return "file-resource|\(stableResource)"
}
return legacyStableID(path: path, size: size, modification: modification)
```

This value is the **primary key** of `catalog_photos` (`CatalogStore.swift:3707`)
and the key of `user_state.json`. Both tiers are questionable as *persistent* keys:

- **Fallback tier — `path|size|mtime` — provably fragile.** Any tool that
  rewrites mtime (many backup and sync tools do) changes the identity. Moving a
  file changes it. The photo then re-catalogs as a new, unedited asset and its
  user state is orphaned. **This needs no external assumption — it follows from
  `PhotoLibraryScanner.swift:202-205` directly.**
- **Primary tier — `fileResourceIdentifier` — unverified.** An opaque OS-supplied
  value, stored permanently as the primary key. Whether it survives reboots and
  volume remounts across different filesystems was **not established** — an
  attempt to confirm Apple's documented contract was inconclusive, and no test in
  this repo exercises it. If it does rotate, every photo's user state is orphaned.
  *Flagged as inference, not fact.* See `RAWDOCK_OPEN_QUESTIONS.md` Q2 for a
  one-hour experiment that settles it.

There is a partial mitigation: the scanner tries the new ID and then the legacy
ID (`:143`), so a one-way migration works. There is **no** content-hash-based
identity recovery, even though both hash columns exist.

### 6.5 Test isolation is reliable for SwiftPM, but NOT for Xcode-hosted runs

`RAWDeskStorageDirectory.resolve` detects a test process and redirects storage to
a per-PID temp directory (`:25-40`). This is enforced in **production** code, so
`swift test` cannot reach the real catalog or real photos. Independently verified:
no test file references `testraw/`, and the two tests that open a real RAW file
are env-gated and read-only.

**However, the project's own QA record documents two ways this isolation leaks:**

1. **Xcode-hosted test runs did not inherit the override, and migrated the user's
   real catalog** from schema 7 to 9 —
   `Evidence/2026-07-26/people/README.md:136-142`. The same happened for schema 8
   (`Evidence/2026-07-26/map/README.md:99-121`), and a probe found Xcode's test
   service opening the real catalog's WAL files
   (`Evidence/2026-07-26/people-background/README.md:39-44`). Migrations are
   **one-way** — there is no down-migration — so a stray Xcode test run
   irreversibly upgrades the real catalog. The runs were caught and the databases
   retained, but `people/README.md:167-169` notes the affected test was never
   re-run against the normal catalog afterwards.
2. **`RAWDESK_SUPPORT_DIRECTORY_OVERRIDE` does not isolate everything.** SwiftUI
   `@AppStorage` and macOS window state still use the real preference domain
   (`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:9-13`). QA restored one known setting
   and explicitly declined to guess at others (`:25-27`).

**Practical guidance:** run `swift test` from the command line. Treat
Xcode-hosted test runs as capable of touching the real catalog unless isolation is
re-verified. Back up `~/Library/Application Support/RAWDesk/catalog.sqlite` before
running tests from Xcode.

### 6.6 Dual source of truth for user state

Per-photo state is written to **both** `user_state.json`
(`UserStateStore.swift:79-88`) and `catalog_photos.state_json`
(`CatalogStore.swift:3717`) — see `LibraryViewModel.swift:4220-4227`, which
writes both in sequence. The catalog write is `try?` — **silently discarded on
failure**, leaving the JSON store ahead of the database.

There is no reconciliation pass between the two stores. Which one wins after a
divergence is **unverified**.

Secondary concern: `persistLocked` re-encodes and rewrites the **entire**
dictionary on **every single** state change. For a large library this is O(n)
per keystroke-level edit — a performance cliff and a wider window for a
torn write (mitigated by `.atomic`).

---

## 7. Prioritized recommendations

1. **Route both deletion paths through `trashItem`.** The `sourceRemovalHandler`
   seam already exists at `PhotoImportService.swift:54`; supplying a trashing
   handler at `LibraryViewModel.swift:243` is a small change that converts every
   irreversible deletion into a recoverable one. Highest safety-per-line-changed
   in the repo.
2. **Gate export on `rawDecodeSource`.** Refuse, or loudly warn, when a
   "full-resolution" export would derive from `.embeddedPreview` (§6.2).
3. **Verify content on relink** (§6.3). Compare size and SHA-256; re-read EXIF
   from the new file rather than inheriting stale metadata.
4. **Give Auto Import an explicit `mode`**, or rename the local variable and
   comment `AutoImportService.swift:148` to make the unconditional deletion
   legible in code (§3.2).
5. **Adopt content-hash-based identity recovery** so a rotated
   `fileResourceIdentifier` or a touched mtime degrades to a re-match instead of
   orphaning user state (§6.4).
6. **Make the in-memory-catalog fallback obtrusive** — a persistent banner, or
   refuse to accept edits — so a session's work is not silently discarded (§6.1).
7. **Collapse the dual state stores**, or add an explicit reconciliation with a
   documented winner (§6.6).
8. **Fix Xcode test isolation** so a stray run cannot migrate the real catalog
   (§6.5), and back up the catalog before running tests from Xcode until then.
