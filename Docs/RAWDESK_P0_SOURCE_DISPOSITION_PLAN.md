# RAWDesk P0 Source-Disposition Safety Plan

Date: 2026-07-30

## Verified pre-patch behavior

- `AutoImportService.run` executes a `.copyToFolder` import and then independently
  calls `FileManager.removeItem` for the original photo and sibling XMP.
- Manual `.moveToFolder` import reaches the injectable
  `PhotoImportService.SourceRemovalHandler`, whose production default also calls
  `FileManager.removeItem`.
- `PhotoImportTransfer` receipts are appended only after destination inspection,
  verified copy, and successful `CatalogStore.upsert`.
- The working directory is not a Git repository. `git status` therefore cannot
  detect overlapping uncommitted edits. Pre-change hashes and timestamps were
  recorded, and edits will be limited to the symbols listed below.

## Narrow implementation

1. Add persisted `AutoImportSourceHandling` values `keepSource` and
   `moveSourceToTrash`; default and legacy decoding use `keepSource`.
2. Make `PhotoImportService` the single source-disposition owner:
   - production handler uses `FileManager.trashItem`;
   - re-verify source, destination, and sibling XMP hashes immediately before
     disposition;
   - never fall back to `removeItem`;
   - return warning/retention counts when Trash fails.
3. Route both manual `.moveToFolder` and Auto Import
   `.moveSourceToTrash` through that shared path. Auto Import does not invoke the
   handler for `keepSource`, cancelled imports, failed catalog persistence, or
   failed post-import metadata persistence.
4. Update manual and Auto Import UI copy to distinguish:
   - copy and retain source;
   - copy, verify, register, then move source to Trash.
5. Preserve permanent deletion only for RAWDesk-created temporary files,
   uncommitted destination copies, empty import directories, caches, and other
   non-original rollback artifacts.

## Tests and isolation

- Use only generated files under temporary directories.
- Inject source-disposition handlers; unit tests never invoke the real macOS
  Trash.
- Cover default/explicit retention, successful Trash disposition and ordering,
  Trash failure, hash/copy/catalog/metadata-persistence/cancellation guards,
  legacy migration and restart persistence, manual Move, and no-delete fallback.
- Run targeted import tests first, then the full Swift test suite with an
  isolated SwiftPM scratch directory, `CFFIXED_USER_HOME`, and
  `RAWDESK_SUPPORT_DIRECTORY_OVERRIDE`.

## Out of scope

RAW export fallback, relinking, photo identity, cache isolation, preference
isolation, color management, and unrelated UI work remain unchanged.
