# RAWDesk P0 Source-Disposition Safety Result

Date: 2026-07-30

## Outcome

The source-disposition patch is implemented.

- Auto Import now defaults to `keepSource`.
- Existing settings without `sourceHandling` decode as `keepSource`.
- The explicit alternative is `moveSourceToTrash`.
- Manual `moveToFolder` remains as an internal/API case for compatibility, but
  the product wording is now **Copy + Trash**.
- Manual Copy + Trash and optional Auto Import cleanup both use
  `PhotoImportService.moveVerifiedSourcesToTrash`.
- The production source handler uses `FileManager.trashItem`.
- There is no Trash-to-`removeItem` fallback.
- A cleanup failure keeps the imported destination, retains any source that
  was not successfully sent to Trash, and produces an observable warning.
- Auto Import blocks disposition after cancellation, copy/decode/hash/catalog
  failure, or required Auto Import metadata-persistence failure.

## Changed files and important symbols

| File | Important change |
| --- | --- |
| `Sources/RAWDesk/Models/AutoImportModels.swift` | Added `AutoImportSourceHandling`; defaulted and legacy-decoded `AutoImportSettings.sourceHandling` to `keepSource`. |
| `Sources/RAWDesk/Models/PhotoImportModels.swift` | Renamed user-facing Move behavior to Copy + Trash and added `PhotoImportSourceDispositionResult`. |
| `Sources/RAWDesk/Services/PhotoImportService.swift` | Changed the production handler to `trashItem`; centralized final re-verification and Trash disposition in `moveVerifiedSourcesToTrash`; added an injected asset-inspection seam for failure tests. |
| `Sources/RAWDesk/Services/AutoImportService.swift` | Removed its independent source-deletion loop; routed opt-in cleanup through `PhotoImportService`; blocked cleanup when required persistence fails. |
| `Sources/RAWDesk/Views/AutoImportSettingsView.swift` | Added the source-handling picker and explicit retain-versus-Trash safety copy. |
| `Sources/RAWDesk/Views/PhotoImportView.swift` | Replaced simple Move wording and actions with Copy + Trash wording and warning/result states. |
| `Sources/RAWDesk/ViewModels/LibraryViewModel.swift` | Surfaces Auto Import cleanup warnings as a Needs Attention state. |
| `Tests/RAWDeskTests/RAWDeskTests.swift` | Added isolated source-retention, ordering, failure, cancellation, migration, restart, manual Trash, and no-fallback coverage. |
| `README.md` | Updated current import behavior, test coverage, and manual QA wording. Historical pre-patch evidence remains labeled as historical. |
| `Docs/RAWDESK_P0_SOURCE_DISPOSITION_PLAN.md` | Records the verified pre-patch behavior and narrow implementation plan. |
| `Docs/RAWDESK_P0_SOURCE_DISPOSITION_RESULT.md` | Records this result and the mutation inventory. |

The legacy result property `AutoImportRunResult.removedSourceCount` was retained
to avoid an API-wide rename. It now counts sources successfully moved to Trash.

## Safety ordering

For each eligible transfer, the destination is copied through a hidden staging
file and verified with complete SHA-256 before the final destination move.
Destination inspection must then succeed, followed by the catalog transaction.
Auto Import also completes requested metadata persistence before disposition.
Immediately before Trash disposition, the shared path again verifies:

1. source and destination are distinct and in the expected directories;
2. both the source and destination still exist;
3. both complete photo hashes still equal the cataloged transfer hash; and
4. when present, the source and destination XMP sidecars both exist in the
   expected locations and have equal complete hashes.

Only then is the injected production handler called. Cancellation is checked
again immediately before each disposition attempt.

## Tests

All destructive test behavior used generated files under temporary directories
and injected handlers. Unit tests did not call the real macOS Trash.

Targeted checkpoints:

```text
swift test --filter AutoImportTests
Executed 18 tests, 0 failures.

swift test --filter PhotoImportServiceTests
Executed 17 tests, 0 failures.
```

The static no-permanent-delete-fallback test was added after the first targeted
Auto Import checkpoint and is included in the final full run.

Final isolated command shape:

```text
CFFIXED_USER_HOME="$TEST_ROOT/fixed-home" \
RAWDESK_SUPPORT_DIRECTORY_OVERRIDE="$TEST_ROOT/support" \
CLANG_MODULE_CACHE_PATH="$TEST_ROOT/module-cache" \
swift test --scratch-path "$TEST_ROOT/build"
```

Final result:

```text
Executed 354 tests, with 2 tests skipped and 0 failures.
UIStateContractTests: 21 tests, 0 failures.
```

The two existing Sony/Canon real-fixture integration tests were skipped because
`RAWDESK_SONY_ARW_FIXTURE_DIR` was not set. The isolated temporary test root was
deleted after the successful run.

Acceptance coverage includes:

- default and explicit source retention;
- restart persistence and legacy decode to `keepSource`;
- successful opt-in Trash disposition through an injected test double;
- exact call ordering after destination hash and catalog persistence;
- Trash failure with both source photo and destination retained;
- copy, source-change, destination-hash, decode, catalog, requested-metadata,
  and cancellation guards;
- manual Copy + Trash for photo and XMP;
- no `removeItem` fallback in the production disposition path.

## Classified file-mutation inventory

Scope: the import and Auto Import execution services, their settings store, and
the catalog storage boundary used by those services. Line numbers are for this
result's source snapshot.

### `PhotoImportService`

| Location | Call | Target classification | Reason it remains |
| --- | --- | --- | --- |
| `PhotoImportService.swift:63` | `FileManager.trashItem` | Original source photo or associated source XMP | The sole production source-disposition primitive. It is recoverable macOS Trash handling after all safety gates; errors propagate to warnings. |
| `PhotoImportService.swift:1130` | `removeItem(createdSidecarURL)` | Newly created imported-destination sidecar | Rolls back this attempt when the paired copy cannot complete. Never targets the source sidecar. |
| `PhotoImportService.swift:1133` | `removeItem(createdPhotoURL)` | Newly created imported-destination photo | Rolls back this attempt when the copy/sidecar operation fails. Never targets the original. |
| `PhotoImportService.swift:1198` | `removeItem(temporary)` | Hidden `.rawdesk-import-*.tmp` staging file | Removes failed or leftover staging output. |
| `PhotoImportService.swift:1201` | `copyItem(source, temporary)` | Reads original photo/source XMP; writes a temporary staging file | Creates the byte-for-byte staging copy that is hashed before commit. |
| `PhotoImportService.swift:1208` | `moveItem(temporary, destination)` | Temporary file to imported destination | Finalizes the already hash-verified staging file without touching the source. |
| `PhotoImportService.swift:1329` | `createDirectory` | Imported-destination organization directory | Creates only the requested destination hierarchy. |
| `PhotoImportService.swift:1334` | `removeItem(directory)` | Just-created destination directory | Defensive rollback if descendant validation fails. |
| `PhotoImportService.swift:1361` | `removeItem(path)` | Empty RAWDesk-created destination directory | Cleans empty organization directories after failure/cancellation. |
| `PhotoImportService.swift:1396` | `removeItem(created sidecar)` | Uncommitted imported-destination sidecar | Transaction rollback for a pending prepared import. |
| `PhotoImportService.swift:1399` | `removeItem(created photo)` | Uncommitted imported-destination photo | Transaction rollback for a pending prepared import. |
| `PhotoImportService.swift:1406` | `removeItem(url)` | Uncommitted imported-destination photo or sidecar | Removes only the URL recorded as created by the current attempt. |

### Auto Import settings and catalog persistence

| Location | Call | Target classification | Reason it remains |
| --- | --- | --- | --- |
| `AutoImportSettingsStore.swift:39` | `moveItem(settings, corrupt backup)` | Application settings metadata | Preserves an unreadable settings file as a backup; it is not a photo or sidecar. |
| `AutoImportSettingsStore.swift:71` | atomic `Data.write` | Application settings metadata | Persists source-handling and other Auto Import settings. |
| `CatalogStore.swift:3665` | `sqlite3_open_v2(READWRITE | CREATE)` plus SQLite statements | Catalog database/WAL, not an image, preview, cache, or XMP | Provides the durable catalog transaction that must succeed before disposition. |
| `CatalogStore.swift:4260,4266` | `moveItem` | Corrupt catalog database and its WAL/SHM files | Preserves corrupt catalog storage as a backup; never targets an original or imported image. |

`AutoImportService.swift` has no direct `removeItem`, `trashItem`, file-move,
file-replace, file-write, or file-truncation call. No file replacement or file
truncation primitive remains in the affected import services. Catalog writes
occur through SQLite transactions; there is no photo-file write in that layer.

An adjacent but out-of-path sidecar mutation was also checked:
`LibraryViewModel.swift:4221` can explicitly call
`XMPSidecarService.write`, whose `XMPSidecarService.swift:1226` atomic write
targets a user-requested metadata sidecar. The import and Auto Import execution
paths do not call it; import sidecars are copied and hash-verified instead.

## Remaining permanent-delete paths

No production import or Auto Import path permanently deletes an original source
photograph or associated source sidecar.

The remaining `removeItem` calls listed above permanently delete only temporary
staging output, uncommitted destination copies/sidecars, or empty directories
created by the current import attempt. They are rollback/cleanup paths allowed
by the product decision.

Historical audit documents under `Docs/` still describe the pre-patch snapshot
and should not be read as current behavior. This result and the current source
are authoritative for this patch.

## Migration

- Fresh `AutoImportSettings` values use `keepSource`.
- JSON lacking the `sourceHandling` key decodes to `keepSource`.
- Explicit `moveSourceToTrash` values encode and load through a new settings
  store instance, covering relaunch behavior.
- Unknown/corrupt settings continue through the existing corrupt-backup path
  and return default settings, which now also retain sources.

## Known limitations and runtime verification boundary

- The real macOS Trash API was not invoked in automated tests, as required.
  Production compilation and the injected success/failure contract were
  verified, but Finder/Trash behavior, sandbox entitlements, volume-specific
  Trash behavior, and permission prompts still need disposable runtime QA.
- No real photographs, watched folders, external drives, Photos libraries,
  production catalog, or production preferences were accessed.
- The app UI was compiled and its 21 UI state-contract tests passed, but a live
  visual/accessibility pass was not performed.
- The real Sony/Canon fixture tests were not run.
- Default retention leaves a successfully imported file in the watched folder.
  The current monitor can encounter it again after a relaunch and classify it
  as an exact duplicate for review; a durable processed-source marker or
  post-import holding folder is outside this patch.
- A photo and sibling XMP cannot be sent to Trash atomically. The shared path
  moves the XMP first so an XMP failure cannot move the more important source
  photograph. If XMP Trash succeeds and photo Trash then fails, the photo and
  both destination files remain, the XMP remains recoverable in Trash, and a
  warning is reported.
- This directory is not a Git repository, so `git status` and a Git diff could
  not verify overlap or provide a commit-level change boundary. Pre-change
  timestamps/hashes were recorded, edits were confined to the listed files,
  and no commit was created.

## Product-owner decision

No decision is required to ship this narrow patch for runtime QA. A later
product decision is needed only if default-retained watched-folder sources
should be marked as processed, moved to a non-Trash holding folder, or continue
to reappear as reviewable exact duplicates after relaunch.
