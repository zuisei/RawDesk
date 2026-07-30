# RAWDesk — P0 Adversarial Verification

**Role:** independent second-pass review of `Docs/RAWDOCK_DATA_SAFETY.md`,
`Docs/RAWDOCK_OPEN_QUESTIONS.md`, and `Docs/RAWDesk_RUNTIME_QA_2026-07-30.md`.
**Method:** every prior conclusion treated as an untrusted claim. Verdicts rest on
reading whole functions and control flow, not on checking that cited line numbers
exist. Repository is not a git repository; verification is against the working
tree as of 2026-07-30.

**Runtime testing: declined in full.** See §0. Every verdict below is
*confirmed by source inspection* or weaker. No verdict in this document claims
runtime confirmation.

---

## 0. Why no test was executed

Claim 7 concerns whether test hosting can reach the user's real catalog. That
question was **open at the moment a test would have had to run**. Under the
governing constraint — *do not run a test if there is any unresolved possibility
it will access the real catalog* — the correct action was to settle Claim 7 by
inspection first and not to run anything meanwhile.

Having settled it (§7 — catalog isolation is in place, contrary to the prior
audit's advice), the operative blockers are no longer about the catalog. They are
two **confirmed** non-isolated stores, and they remain disqualifying:

- `ImageCache` resolves its directory from `.cachesDirectory` **without** going
  through `RAWDeskStorageDirectory.resolve`
  (`Sources/RAWDesk/Services/ImageCache.swift:38-46`). No env override and no
  test-process detection redirects it. Any in-process test that touches the
  thumbnail cache writes into the user's **real** `~/Library/Caches/RAWDesk/`.
- `@AppStorage` / window state still resolve to the real preference domain
  (`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:9-13`).

Both are outside the isolation boundary the constraint requires. The constraint
also requires a disposable catalog "whose path is explicitly confirmed before
execution" — no such path was confirmed with the product owner during this task,
which is independently disqualifying.

Every claim in scope was settleable by inspection, so no verdict was lost by
declining. This is the constraint applied, not a coverage gap.

The repository does contain a genuine isolation harness —
`scripts/run-isolated-ui-qa.sh` — which relocates `HOME` / `CFFIXED_USER_HOME`,
the support override, and re-signs the app under `local.rawdesk.app.uiqa`
(`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:14-22`). That is the only mechanism in
the repo that would satisfy the constraint. It was not exercised here because it
drives the full UI app, which is disproportionate to the seven claims and cannot
be confined to a disposable catalog without also launching the real app binary.

---

## 1. Claim — Auto Import copies then permanently deletes the source, regardless of the apparent import mode

### Verdict: **CONFIRMED by source inspection**

### Exact evidence

The request is constructed with the non-destructive mode:

```swift
let request = PhotoImportRequest(
    sourceURLs: safeSources,
    mode: .copyToFolder,
```
— `Sources/RAWDesk/Services/AutoImportService.swift:146-148`

`.copyToFolder` does **not** authorize source removal:

```swift
public var removesVerifiedSources: Bool {
    self == .moveToFolder
}
```
— `Sources/RAWDesk/Models/PhotoImportModels.swift:36-38`

`PhotoImportService` honors that correctly — its entire source-removal block is
gated on the mode:

```swift
if request.mode.removesVerifiedSources,
   let destination {
    for (offset, transfer) in result.transfers.enumerated() {
        …
        let removal = try removeVerifiedMoveSource(
            transfer,
            destination: destination
        )
```
— `Sources/RAWDesk/Services/PhotoImportService.swift:494-506`

Under `.copyToFolder` that condition is false, the block is skipped, and the
import service deletes nothing. `:494` is the **only** deletion gate in the
service: the other `removesVerifiedSources` sites are non-destructive — `:182`,
`:197`, and `Models/PhotoImportModels.swift:281,340` compute duplicate/conflict
counts for preflight and UI, and `:1261` only tallies `retainedSourceCount` on
cancellation.

`AutoImportService` then deletes the sources **in its own loop**, with no mode
check, no settings check, and no user confirmation:

```swift
for transfer in importResult.transfers {
    try Task.checkCancellation()
    handledPaths.insert(transfer.sourceURL.standardizedFileURL.path)
    do {
        try removeVerifiedSource(
            transfer,
            watchedFolderURL: watchedFolderURL,
            destinationFolderURL: destinationFolderURL
        )
        removedSourceCount += 1
    } catch { … }
}
```
— `Sources/RAWDesk/Services/AutoImportService.swift:181-199`

The deletion itself is permanent — `removeItem`, not `trashItem`:

```swift
    try fileManager.removeItem(at: sourceSidecar)
}
try fileManager.removeItem(at: source)
```
— `Sources/RAWDesk/Services/AutoImportService.swift:351,353`

And there is no setting that can disable it: `AutoImportSettings`
(`Sources/RAWDesk/Models/AutoImportModels.swift:6-18`) declares
`enabled, watchedFolderURL, destinationFolderURL, folderOrganization, fileNaming,
customFilenamePrefix, sequenceStart, customFolderTemplate,
customFilenameTemplate, keywords, developmentPreset, analyzePeopleAfterImport,
settleInterval`. A grep for `mode` over that file returns **no match**.

### Relevant call chain

`WatchedFolderMonitor` → `AutoImportService.run` (`:112`) →
`PhotoImportService.preflight` / `.execute` (`:162,166`, non-destructive) →
loop `:181-199` → `AutoImportService.removeVerifiedSource` (`:308-354`) →
`FileManager.removeItem` (`:351,353`).

The claim's phrase "regardless of the apparent import mode" is precise and
correct: the mode is not merely ignored, it is *set to the non-destructive value*
and then overridden by a separate deletion pass.

### Runtime evidence

None. Declined per §0.

### Guards that do exist (and are real)

`removeVerifiedSource` is not reckless. Before deleting it requires
(`:317-334`): source's parent is exactly the watched folder; source ≠ target;
target is a true descendant of the destination; both files exist; and **dual
SHA-256 re-verification** of source *and* target against `transfer.contentHash`.
Sidecars are hash-verified the same way (`:341-344`). Duplicates are retained,
not deleted (`:215-218`). `enabled` defaults to `false`
(`Sources/RAWDesk/Models/AutoImportModels.swift:21`), and only direct children of
the watched folder are eligible (`:139-141`).

Per the standing constraint, hashing does not make this safe. What the hashing
establishes is *copy integrity*. It cannot establish *user intent*, and intent is
the failure mode here.

### Assumptions

- `WatchedFolderMonitor` is the only trigger for `run`. Not exhaustively traced.
- `transfer.contentHash` is computed from the source at copy time — assumed from
  `verifiedCopy` (`Sources/RAWDesk/Services/PhotoImportService.swift:1071-1093`),
  not re-derived here.

### Possible counterexamples

- **If `enabled` is never set true, no deletion occurs.** True but not
  mitigating: enabling Auto Import is the documented purpose of the feature.
- **The UI does disclose the behavior.** `AutoImportSettingsView.swift:382-390`
  and `:107` describe a "Verified move" that "removes the watched-folder source".
  A user who reads the panel is correctly informed. This narrows the claim from
  *undisclosed* to *disclosed-but-not-optional and code-illegible* — it does not
  refute it. The claim as given concerns behavior, not disclosure.

### Defect the prior audit did not record — partial-deletion ordering

The sidecar is deleted **before** the photo (`:351` then `:353`). If `:353` fails,
the sidecar is already gone and the catch handler reports:

> "copied and cataloged, but the watched-folder source was retained"
> — `Sources/RAWDesk/Services/AutoImportService.swift:196`

That message is **false in this window**: the source photo was retained, the
source sidecar was not. Content is not lost (both were hash-verified at the
destination first), so this is a recoverability and truthfulness defect, not data
loss.

Note also the opposite ordering in the manual path — photo first (`:911`), sidecar
second (`:931`) in `PhotoImportService`. The two deletion paths order their two
deletions inversely. Neither is transactional; neither rolls back.

### Divergence from the manual path the prior audit called "same discipline"

`Docs/RAWDOCK_DATA_SAFETY.md:120` states Auto Import has the "same dual-SHA-256
discipline". The hashing is the same. The **post-delete verification is not**:
`PhotoImportService` re-checks that the file actually disappeared and raises
`sourceRemovalFailed` if it survived
(`Sources/RAWDesk/Services/PhotoImportService.swift:911-917`).
`AutoImportService.removeVerifiedSource` has **no post-delete existence check** —
`:353` is the last statement.

Scoped honestly: `FileManager.removeItem` throws on failure, so this is a missing
defense-in-depth check rather than a demonstrated silent-success path. It matters
in the narrow cases where an unlink reports success but the path remains
resolvable — network and FUSE-backed volumes are the realistic candidates — and as
a guard against a future handler substitution at this call site (which is exactly
what recommendation 2 below proposes). In those cases `removedSourceCount` (`:193`)
would over-report. The manual path defends against this; Auto Import does not.

### User-data impact

Permanent, unrecoverable loss of the only copy of a photograph if the copy
target is later lost, plus loss of the user's ability to undo an
incorrectly-configured watched folder. Unattended and unconfirmed at the moment
of deletion. **Highest-severity finding in scope.**

### Minimum safe containment

Do not enable Auto Import. It is off by default
(`Sources/RAWDesk/Models/AutoImportModels.swift:21`); leave it off. No code change
required for containment.

### Recommended permanent fix

1. Add an explicit `sourceHandling` field to `AutoImportSettings` (`.keep` /
   `.trash` / `.delete`), default `.keep`, and gate `:187` on it.
2. Route the removal through the injectable `sourceRemovalHandler` seam rather
   than calling `FileManager.removeItem` directly, so Auto Import inherits
   whatever trashing policy the manual path adopts.
3. Delete photo before sidecar, or delete both through one handler that reports
   partial completion truthfully.
4. Add the post-delete existence check to match `PhotoImportService:911-917`.

### Confidence: **0.97**

Control flow is short, local, and unambiguous. Residual doubt is only about
untraced callers of `run`.

---

## 2. Claim — Manual move import permanently deletes the source rather than moving it through the macOS Trash

### Verdict: **CONFIRMED by source inspection**

### Exact evidence

Default handler is an unlink:

```swift
sourceRemovalHandler: @escaping SourceRemovalHandler = {
    try FileManager.default.removeItem(at: $0)
}
```
— `Sources/RAWDesk/Services/PhotoImportService.swift:54-56`

Production constructs the service **without** overriding it:

```swift
photoImportService = PhotoImportService(
    catalogStore: catalogStore
)
```
— `Sources/RAWDesk/ViewModels/LibraryViewModel.swift:243-245`

A repository-wide grep for `trashItem` returns hits in `Docs/` **only** — zero in
`Sources/`. The only `NSWorkspace` uses in `Sources/` are
`activateFileViewerSelecting` (reveal-in-Finder, non-mutating) at
`Views/RAWLibrarySidebarView.swift:659`, `Views/LibrarySidebarView.swift:876`,
`Views/ThumbnailGridView.swift:197`, `Views/MapWorkspaceView.swift:757`,
`Views/PhotoImportView.swift:1763,1778`. No `recycle`, no
`NSWorkspace.recycle(_:completionHandler:)`.

### Relevant call chain

`PhotoImportView` → `LibraryViewModel` (service built at `:243`) →
`PhotoImportService.execute` → `:504 removeVerifiedMoveSource` →
`:853-947` → `:911 sourceRemovalHandler(source)` /
`:931 sourceRemovalHandler(sidecarPair.source)` → default closure `:55` →
`FileManager.removeItem`.

### Runtime evidence

None. Declined per §0.

### Assumptions

- `LibraryViewModel:243` is the only production construction site. Verified by
  grep over `ViewModels/`, `Views/`, `App/`: the only other hit is
  `AutoImportService(...)` at `:252`, which is *passed* this same instance
  (`photoImportService: photoImportService`, `:254`) — so Auto Import's manual
  path inherits the same permanent-delete handler.

### Possible counterexamples

- **The seam exists and is injectable**, so this is a configuration choice rather
  than a hard-coded behavior. That does not narrow the claim: no shipping code
  supplies a trashing handler, so shipped behavior is permanent deletion.
- **The guards before deletion are strong** — symlink-resolved path comparison,
  descendant check, dual SHA-256 of source and target, sidecar verification, and
  a post-delete existence check (`:911-917`), with failures surfaced as
  `retainedSourceCount` (`:517`) and shown at
  `Views/PhotoImportView.swift:1629-1643`. Per the standing constraint these
  establish copy integrity, not recoverability. A user who selected the wrong
  destination folder gets a perfectly verified, perfectly unrecoverable move.
- **The UI says "remove", not "trash"** — `PhotoImportMode.moveToFolder.detail`
  reads "Copy and verify first, update the catalog, then remove the verified
  sources." (`Sources/RAWDesk/Models/PhotoImportModels.swift:28`). Accurate
  disclosure; the claim is about mechanism, and stands.

### User-data impact

Every Move-mode import is irreversible at the filesystem level. The user's only
recourse is a backup. Severity is lower than §1 because the action is explicit,
per-invocation, and user-initiated.

### Minimum safe containment

Use `Add` or `Copy` mode. `Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:27` records that
QA already restricts itself to `Add` for exactly this reason.

### Recommended permanent fix

Supply a trashing handler at `LibraryViewModel.swift:243`:

```swift
PhotoImportService(
    catalogStore: catalogStore,
    sourceRemovalHandler: { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    }
)
```

Note the post-delete check at `:912` (`!fileManager.fileExists(atPath: source.path)`)
remains correct under trashing — `trashItem` vacates the original path — so no
adjustment is needed there. Prefer `Q3` option (c) from
`Docs/RAWDOCK_OPEN_QUESTIONS.md`: a user preference defaulting to Trash.

### Confidence: **0.98**

---

## 3. Claim — The existing safety audit has identified every application code path capable of creating, modifying, replacing, moving, renaming, truncating, or deleting originals, sidecars, previews, and exported files

### Verdict: **REFUTED**

The audit asserts completeness explicitly — *"No unclassified mutation site
remains."* (`Docs/RAWDOCK_DATA_SAFETY.md:213`) and *"Exactly one image-writing
call exists in the entire codebase"* (`:40-41`). Both statements are false as
written. Completeness cannot be verified by re-running the audit's own greps, so
a deliberately broader primitive set was run and diffed against the §5 table.

**Important scoping of this verdict:** what is refuted is the *enumeration and
its method*. No newly-found site was found to touch an original photograph. The
audit's substantive risk conclusions about originals **survive** this refutation.
The reason to record it as refuted rather than "partially confirmed" is that the
audit's safety argument is explicitly load-bearing on grep completeness
(`:19-20`: *"rests on the **completeness** of the following two greps"*), and that
foundation is demonstrably unsound.

### A systematic blind spot, not a set of isolated misses

The audit greps `\.write(to` and `write(toFile` — single-line patterns. Swift
argument lists wrap. Every wrapped `.write(` call is invisible to that grep. A
grep for `\.write\(` alone finds **11** sites; the audit's §5 table classifies
**6**. The five it never saw:

| Site | Primitive | In §5 table? |
|---|---|---|
| `Sources/RAWDesk/Services/PhotoColorLabelSetStore.swift:51` | `try encoder.encode(normalized).write(` | **No** — file absent from §5 entirely |
| `Sources/RAWDesk/Models/PeopleModels.swift:86` | `try data.write(` | **No** — §5 lists only `:66` |
| `Sources/RAWDesk/Services/RecentFolderStore.swift:107` | `try? data.write(` | **No** — §5 lists only `:121` |
| `Sources/RAWDesk/Services/SavedMapLocationStore.swift:66` | `try encoder.encode(normalized).write(` | **No** — §5 lists only `:43` |
| `Sources/RAWDesk/Services/ImageCache.swift:136` | `).write(` | **No** — §5 lists only `:131` |

### "Exactly one image-writing call" is false

`CGImageDestination` creation sites in `Sources/`:

- `Services/ImageExporter.swift:59` — `CGImageDestinationCreateWithURL` (in §5)
- `Services/AuxiliaryMaskGenerator.swift:551` — `CGImageDestinationCreateWithData` (**not** in §5)
- `Services/SubjectMaskGenerator.swift:196` — `CGImageDestinationCreateWithData` (**not** in §5)

The audit's grep list (`:33`) contains `CGImageDestinationCreateWithURL` only, so
the `…WithData` variants could not appear. **Assessed risk: none** — both write
into a `CFMutableData` in memory, with no file destination. The claim about the
count is nevertheless refuted, and the omission is the same
narrower-grep-than-claim error.

### Every `createDirectory` site is unclassified

Absent from §5: `Services/PhotoImportService.swift:1213`,
`Services/ImageCache.swift:48,170`, `Services/CatalogStore.swift:143`,
`Services/RAWDeskStorageDirectory.swift:19,35,51`,
`Services/SoftProofProfileCatalog.swift:183`, `Models/PeopleModels.swift:41`.

`createDirectory` is a creating primitive and squarely inside the claim's stated
scope ("creating"). **Assessed risk: low** — `createDirectory` cannot replace an
existing regular file (it fails instead), and the one destination-side site is
tightly bounded: `PhotoImportService:1213` uses
`withIntermediateDirectories: false`, then verifies `isDescendant(directory, of: base)`
and removes the directory it just made if the check fails (`:1212-1223`).

### Paths checked for photo-adjacency — clean

The claim covers previews. `ImageCache.decodeSourceURL` builds
`…deletingPathExtension().appendingPathExtension("raw-source")`
(`Services/ImageCache.swift:209-215`, derivation at `:212-214`), which reads like a
sidecar written next to an original. It is not: it derives from
`diskURL(for: key)`, a SHA-256 hex filename inside `diskDirectory` (`:203-206`).
Contained.

Every `appendingPathExtension` site in `Sources/` was checked. All resolve to
either app-support store backups (`CatalogStore:4257`,
`AutoImportSettingsStore:36`, `UserStateStore:28`, `SavedMapLocationStore:40`,
`PeopleModels:63`), the cache dir (`ImageCache:214`), the collision-safe import
destination (`PhotoImportService:1040`), or the XMP sidecar
(`XMPSidecarService:98,106`). **No unlisted primitive writes next to an
original.**

### Relevant call chain

Not applicable — this is a claim about the audit document, not about a runtime
path.

### Runtime evidence

None. Declined per §0.

### Assumptions

- Scope is `Sources/`. `scripts/` was not audited as application code; it
  contains the QA isolation harness and is developer-invoked.
- Format-string and dynamically-constructed paths cannot be found by grep by
  either the audit or this review. Neither the audit's completeness claim nor this
  refutation of it can be settled by grep alone — which is precisely the point.

### Possible counterexamples

- **"The omissions are all benign, so the audit is substantively right."**
  Accepted, and stated above. The claim under review is about completeness of
  identification, and it is false. Recording it as confirmed would license the
  next reviewer to trust a method that provably misses wrapped call sites.
- **`PhotoColorLabelSetStore` is a settings store, arguably out of scope.** The
  claim's scope is originals/sidecars/previews/exports, and a color-label store is
  none of those. Conceded for that one file — but `ImageCache:136` writes
  **preview** data, which is explicitly in scope, and was missed.

### User-data impact

No direct impact. The impact is second-order and real: a future reviewer or
refactorer who trusts §5 as exhaustive will reason from an incomplete map.

### Minimum safe containment

Treat `Docs/RAWDOCK_DATA_SAFETY.md` §5 as indicative, not exhaustive, until
regenerated with multi-line-aware tooling.

### Recommended permanent fix

Regenerate the mutation inventory with a parser rather than line-oriented grep —
`swift-syntax`, or an IndexStore query for references to `FileManager`,
`Data.write`, and `CGImageDestination*`. Add the resulting inventory as a
checked-in fixture and a test that fails when a new mutation site appears
unclassified.

### Confidence: **0.93** that the claim is refuted

The five wrapped-write sites and the two `…WithData` sites are directly
observable. Residual uncertainty is only about whether a reader would consider
settings-store writes in scope — which does not affect the verdict, since
`ImageCache:136` (preview data) is unambiguously in scope.

---

## 4. Claim — Full-resolution RAW export can silently fall back to an embedded or lower-resolution JPEG representation

### Verdict: **CONFIRMED by source inspection**

### Exact evidence

Export enters the full-resolution render with no size target:

```swift
if asset.isRaw {
    source = try RAWImageLoader.load(url: asset.url, targetLongestEdge: nil)
}
```
— `Sources/RAWDesk/Services/PhotoProcessor.swift:194-196`

The loader is an ordered fallback chain, and the asymmetry the claim depends on is
real. Stage 3 (embedded preview) is entered **unconditionally**; stage 4
(QuickLook) is guarded on a non-nil target:

```swift
if let img = tryImageIOEmbedded(url: url, targetLongestEdge: targetLongestEdge) {
    return LoadResult(image: img, source: .embeddedPreview)
} else {
    failures.append("ImageIO embedded preview")
}

if let target = targetLongestEdge,
   let img = tryQuickLook(url: url, target: target) {
```
— `Sources/RAWDesk/Services/RAWImageLoader.swift:110-120`

With `targetLongestEdge == nil`, the embedded preview is capped at 4096 px:

```swift
let maxPixel = targetLongestEdge.map { Int($0.rounded()) } ?? 4096
```
— `Sources/RAWDesk/Services/RAWImageLoader.swift:243`

The decode source is **structurally discarded** before export can see it.
`loadResult` returns a `LoadResult` carrying `source`, but `load` throws it away:

```swift
public static func load(url: URL, targetLongestEdge: CGFloat?, preserveWideGamut: Bool = false) throws -> NSImage {
    try loadResult(url: url, targetLongestEdge: targetLongestEdge, preserveWideGamut: preserveWideGamut).image
}
```
— `Sources/RAWDesk/Services/RAWImageLoader.swift:65-75`

`renderFullResolution` returns `NSImage` (`PhotoProcessor.swift:188-199`), so the
information cannot propagate. A grep for `rawDecodeSource` across `Sources/`
returns ~90 hits — in `ImageLoader`, `ImageCache`, `PhotoViewerViewModel`, and
display views (badges in `MetadataInspectorView:594-595`,
`ThumbnailCellView:685`). **Zero hits in `ImageExporter.swift` and zero in
`PhotoProcessor.swift`.** The export path never consults it.

### Relevant call chain

`ContentView.exportSelected` (`:1785`) → `NSSavePanel` (`:1792`) →
`ImageExporter.export` (`:1812`) → `PhotoProcessor.renderFullResolution`
(`Services/ImageExporter.swift:97`) → `RAWImageLoader.load(targetLongestEdge: nil)`
(`Services/PhotoProcessor.swift:195`) → `loadResult` (`:70`) →
stage 3 `tryImageIOEmbedded` (`Services/RAWImageLoader.swift:110`) →
`kCGImageSourceThumbnailMaxPixelSize: 4096` (`:243,248`).

### Runtime evidence

None. Declined per §0. Note this claim is *reachability-conditional*: it requires
`CIRAWFilter` and `CIImage` to both fail on a given file. Reachability was
confirmed structurally (no guard prevents stage 3 under `nil`), not
observationally — no RAW file was found for which stages 1–2 fail, and finding one
was out of scope.

### Assumptions

- `ContentView.exportSelected` is the only export entry point. `renderFullResolution`
  has exactly one caller (`ImageExporter.swift:97`), which supports this.
- Stage ordering means stages 1–2 failing is the precondition. Not that it is
  common — only that nothing prevents it.

### Possible counterexamples

- **Stages 1–2 may never fail in practice**, making this unreachable. Plausible
  and untested. It would narrow severity, not correctness: the guard asymmetry at
  `:110` vs `:119` is unambiguous, and the release notes
  (`Releases/RAWDesk-v0.1-Sony-ARW-Verified-2026-07-27`) suggest per-camera decode
  variance is a live concern, i.e. exactly the condition under which stage 1 fails
  for an unfamiliar sensor.
- **The user might have been warned at display time** — the Loupe/Develop views do
  badge the decode source (`MetadataInspectorView:594`). So an attentive user *may*
  know. But the export produces no warning of its own, and the badge is a
  different screen at a different time.
- **The comment claims the opposite.** `PhotoProcessor.swift:185-187` states RAW
  uses "the embedded preview only as a compatibility fallback" — accurate as
  written, but it describes a fallback that silently degrades a
  *full-resolution export* to a ≤4096 px baked JPEG with adjustments layered on
  top. The comment discloses the mechanism, not the consequence.

### User-data impact

No file is lost or altered. The user receives an export presented as a
full-resolution develop of their RAW that is in fact a ≤4096 px re-compression of
the camera's embedded JPEG, with edits applied on top of already-baked tone and
color. Silent, and likely to be discovered only after the RAW is gone — which
composes badly with §1 and §2. Delivered work product is wrong; originals are
untouched.

### Minimum safe containment

Before exporting, check the decode-source badge in the metadata inspector
(`MetadataInspectorView.swift:594-595`). If it reads embedded preview, do not
treat the export as a full-resolution deliverable.

### Recommended permanent fix

Have `renderFullResolution` return the decode source alongside the image (it is
already available in `LoadResult`), and in `ImageExporter.export` refuse — or
require explicit confirmation — when a full-resolution export would derive from
`.embeddedPreview`. Independently, pass `targetLongestEdge: nil` through to stage
3 so the 4096 default does not silently cap a "full resolution" request.

### Confidence: **0.95** on the mechanism; **0.6** on real-world reachability

---

## 5. Claim — Persisted photo identity can fall back to path, size, and modification time, allowing identity loss or duplicated catalog records after legitimate file changes

### Verdict: **CONFIRMED by source inspection** for the fallback tier.
**NOT ESTABLISHED** for whether the primary tier rotates.

### Exact evidence

```swift
public static func stableID(
    path: String, size: Int64, modification: Date?, resourceIdentifier: Any? = nil
) -> String {
    if let resourceIdentifier,
       let stableResource = resourceIdentifierString(resourceIdentifier) {
        return "file-resource|\(stableResource)"
    }
    return legacyStableID(path: path, size: size, modification: modification)
}

public static func legacyStableID(path: String, size: Int64, modification: Date?) -> String {
    let mod = modification?.timeIntervalSinceReferenceDate ?? 0
    return "\(path)|\(size)|\(mod)"
}
```
— `Sources/RAWDesk/Services/PhotoLibraryScanner.swift:189-205`

The fallback is a literal concatenation of path, size, and mtime — exactly what
the claim states. This value is the catalog primary key
(`Sources/RAWDesk/Services/CatalogStore.swift:3707`) and the `user_state.json`
key. Any mtime rewrite (common in backup and sync tooling), or any move, yields a
different identity. The photo then re-catalogs as a new, unedited asset and the
prior user state is orphaned.

The fallback is reached whenever `resourceIdentifier` is nil **or**
`resourceIdentifierString` returns nil. Note the latter is hard to trigger — it
returns nil only for an empty `String(describing:)`
(`Sources/RAWDesk/Services/PhotoLibraryScanner.swift:207-215`) — so in practice
the fallback is reached when the caller passes no identifier or the OS supplies
none.

### Relevant call chain

`PhotoLibraryScanner` scan → `stableID` (`:189`) → `legacyStableID` (`:201`) →
primary key of `catalog_photos` (`CatalogStore.swift:3707`) and key of
`user_state.json` (`Services/UserStateStore.swift:79-88`).

Partial mitigation, confirmed present: the scanner attempts the new ID and then
the legacy ID (`PhotoLibraryScanner.swift:143`), so a one-way legacy→resource
migration re-matches. There is **no** content-hash-based recovery, despite
`content_hash` and `image_content_hash` existing in the schema
(`CatalogStore.swift:3736-3737`).

### Runtime evidence

None. Declined per §0.

### Assumptions

- `stableID` is the only identity constructor. `relinkPhoto` also calls it
  (`CatalogStore.swift:2131-2136`), consistent with this.

### Possible counterexamples

- **If `fileResourceIdentifier` is always available on APFS/HFS+, the fallback is
  dead code in practice.** Possible; not established either way. The claim says
  identity *can* fall back, and the code path plainly exists and is reachable by
  the caller passing `resourceIdentifier: nil` (the parameter defaults to `nil`).
- **Whether the primary tier itself rotates across reboot/remount is NOT
  ESTABLISHED.** This review did not attempt it: it is an OS-behavior question
  requiring an external-volume reboot cycle, which the constraints forbid.
  `Docs/RAWDOCK_OPEN_QUESTIONS.md` Q2 already scopes a one-hour experiment; the
  prior audit correctly flagged its own claim here as inference
  (`Docs/RAWDOCK_DATA_SAFETY.md:296-302`). That self-flagging is accurate and is
  to the prior audit's credit.

### User-data impact

Silent orphaning of ratings, keywords, and develop settings — i.e. loss of user
*work*, not of photographs — triggered by ordinary external tooling touching
mtime. Recoverable only by manual re-editing.

### Minimum safe containment

Back up `~/Library/Application Support/RAWDesk/catalog.sqlite` and
`user_state.json` before running any tool that rewrites mtimes over the photo
library.

### Recommended permanent fix

Adopt `Docs/RAWDOCK_OPEN_QUESTIONS.md` Q2 option (b): keep the resource
identifier as the lookup key, add a content-hash fallback so a rotated identifier
or touched mtime degrades to a re-match rather than an orphan. The hash columns
and `FileContentHasher` already exist.

### Confidence: **0.97** (fallback tier) / **not scored** (primary tier — not established)

---

## 6. Claim — Relinking validates only weak file characteristics and can associate an existing catalog record with the wrong photograph or stale metadata

### Verdict: **CONFIRMED by source inspection**

### Exact evidence

`CatalogStore.relinkPhoto` (`Sources/RAWDesk/Services/CatalogStore.swift:2091-…`)
validates, in order:

- record exists (`:2096-2098`)
- `FileTypeDetector.isSupported(url:)` (`:2101-2103`)
- resource values readable (`:2112-2116`)
- `values.isRegularFile == true` (`:2117-2119`)
- **format equality only** (`:2124-2129`):
  ```swift
  guard format == existing.format else {
      throw CatalogStoreError.replacementFormatMismatch(…)
  }
  ```
- path/ID conflict checks against already-cataloged entries
  (`:2139-2147`, throwing `replacementAlreadyCataloged` at `:2141` and `:2146`)

`fileSize` **is** read at `:2131` and `.fileSizeKey` **is** requested at `:2105` —
but the value is used only to construct the replacement asset (`:2167`) and the
new ID (`:2133`). It is **never compared** to `existing.fileSize`. There is no
SHA-256 comparison anywhere in the function, despite `content_hash` /
`image_content_hash` existing in the schema (`:3736-3737`) and `FileContentHasher`
being available. Two different photographs of the same format therefore relink
without objection.

Stale metadata is confirmed — the replacement inherits the old file's EXIF rather
than re-reading it:

```swift
let replacementAsset = PhotoAsset(
    id: replacementID,
    url: url,
    …
    fileSize: size,
    creationDate: values.creationDate,
    modificationDate: modification,
    format: format,
    metadata: existing.metadata,
    userState: existing.userState,
```
— `Sources/RAWDesk/Services/CatalogStore.swift:2161-2174` (`metadata: existing.metadata` at `:2171`)

Note the shape precisely: file-level attributes (`fileSize`, `creationDate`,
`modificationDate`) **are** refreshed from the new file, while
`metadata` — the EXIF payload carrying capture date, camera, lens, and GPS — is
carried over verbatim. `MetadataReader` is not invoked. The result is an asset
whose file attributes describe the new file and whose photographic metadata
describes the old one.

### Relevant call chain

`LibraryViewModel.locateMissingPhoto` (`:2877-2898`) →
`CatalogStore.relinkPhoto` (`:2091`) → `upsert(asset:rootPath:indexedAt:)`
(`:2191-2192`) → success message to the user at
`Sources/RAWDesk/ViewModels/LibraryViewModel.swift:2946`.

### Runtime evidence

None. Declined per §0.

### Assumptions

- `locateMissingPhoto` is the only caller. Not exhaustively traced beyond grep.
- `existing.metadata` is the EXIF payload rather than a lazily-refreshed view.
  Inferred from its direct assignment into `PhotoAsset.metadata` with no reader
  call on the path.

### Possible counterexamples

- **Format equality plus user intent may be adequate** — the user picked the file
  in a panel, so a mismatch is arguably their error. This is the strongest
  counterargument and it does narrow *severity*: the action is explicit. It does
  not refute the claim, because the operation is silent on a mismatch it has
  enough information to detect (size is already in hand at `:2129`), and because
  the reported outcome is affirmatively misleading.
- **The UI's success text is technically true**: *"Existing edits and organization
  metadata were preserved."* (`LibraryViewModel.swift:2946`). Correct about edits;
  it does not disclose that *photographic* metadata was also preserved, which is
  the defect rather than the feature.
- Relink writes catalog rows only. **No file is touched.**

### User-data impact

Catalog↔filesystem divergence. Ratings, keywords, and develop settings silently
transfer onto a different photograph; capture date, camera, lens, and GPS
continue to describe a file that is no longer present. Corrupts the trustworthiness
of the catalog as a record, and any downstream XMP write propagates the stale EXIF
outward to disk. Files themselves are safe.

### Minimum safe containment

When relinking, verify by eye that the chosen file is the same photograph before
confirming. Avoid relinking as a bulk operation.

### Recommended permanent fix

In `relinkPhoto`, before the transaction: compare `size` against
`existing.fileSize` and compare `FileContentHasher.sha256(for: url)` against the
stored `content_hash` when present; on mismatch require explicit confirmation
rather than failing silently or succeeding silently. Re-read EXIF via
`MetadataReader` for the new file instead of assigning `existing.metadata`, and
carry over `existing.userState` only.

### Confidence: **0.96**

---

## 7. Claim — Some Xcode-hosted test configuration can open or migrate the user's real catalog instead of a disposable test catalog

### Verdict: **REFUTED as stated for the catalog in the current working tree.**
The **historical** form of the claim is confirmed by the repository's own Evidence.
The fix is confirmed both by source inspection and by a documented post-fix Xcode
run. A **different**, still-live isolation gap the prior audit missed is
**confirmed**: the thumbnail cache.

This is the claim where the prior audit's evidence is weakest, because it rests on
historical QA records rather than on current code — and, as §8.9 records, it cites
only the first half of those records.

### Exact evidence — current state has two independent guards

**Guard 1 — the shared scheme sets the override, enabled:**

```xml
<EnvironmentVariables>
   <EnvironmentVariable
      key = "RAWDESK_SUPPORT_DIRECTORY_OVERRIDE"
      value = "/tmp/RAWDesk-XcodeTests-Support"
      isEnabled = "YES">
   </EnvironmentVariable>
</EnvironmentVariables>
```
— `RAWDesk.xcodeproj/xcshareddata/xcschemes/RAWDesk.xcscheme:70-76`, inside
`<TestAction>` (`:40`)

Also declared in the generator source, so a regenerated project retains it:
`project.yml:75-78`.

**Guard 2 — test-process detection covers Xcode's own variables:**

```swift
if environment["XCTestConfigurationFilePath"] != nil
    || environment["XCTestBundlePath"] != nil {
    return true
}
```
— `Sources/RAWDesk/Services/RAWDeskStorageDirectory.isTestProcess:66-69`,
with process-name and argument checks as further fallbacks (`:70-79`).

`XCTestConfigurationFilePath` is set by Xcode's test runner, so Guard 2 fires
under Xcode hosting even if the scheme env var were removed. Both guards are
consulted by `resolve` (`:11-24` then `:25-40`) before the real Application
Support path is ever computed (`:41-46`).

Storage sites honoring `resolve`: `CatalogStore:142`,
`AutoImportSettingsStore:20`, `UserStateStore:15`, `RecentFolderStore:39`,
`SavedMapLocationStore:15`, `PhotoColorLabelSetStore:14`, `PeopleModels:40`.
The catalog specifically is covered.

### Exact evidence — the historical incidents were real

- Xcode-hosted runs migrated the real catalog schema 7 → 9 —
  `Evidence/2026-07-26/people/README.md:136-142`
- The same for schema 8 — `Evidence/2026-07-26/map/README.md:99-121`
- A probe caught Xcode's test service opening the real catalog's WAL files —
  `Evidence/2026-07-26/people-background/README.md:39-44`

Migrations are one-way, so those runs irreversibly upgraded the real catalog.

### Exact evidence — the incidents were fixed, and the fix was verified

The same Evidence file the audit cites for the WAL probe records the remediation
sixteen lines later:

> "The shared Xcode scheme was then hardened so its Test action does not inherit
> Run arguments and always sets: `RAWDESK_SUPPORT_DIRECTORY_OVERRIDE=/tmp/RAWDesk-XcodeTests-Support`"
> — `Evidence/2026-07-26/people-background/README.md:45-50`

> "The same setting is declared in `project.yml`; an XcodeGen 2.45.2 regeneration
> probe produced the identical Test action, so regenerating the project does not
> remove the isolation boundary."
> — `Evidence/2026-07-26/people-background/README.md:52-55`

> "The final 232-test Xcode run used the same boundary, left the normal
> catalog/database-WAL timestamps unchanged, and ended with an empty disposable
> catalog plus `quick_check: ok`."
> — `Evidence/2026-07-26/people-background/README.md:57-60`

That last item is **empirical post-fix verification of catalog isolation under
Xcode hosting**, performed by the project's own QA. It is not runtime evidence
obtained by this review, and it is dated 2026-07-26 rather than against the
current tree — but it is direct observation of the exact property in question, and
it corroborates the two guards found by inspection above.

### Why the original leak happened — and why it is now closed

The mechanism is legible from the code. `TEST_HOST` is the real app binary
(`project.yml:70-72`), so under Xcode hosting `ProcessInfo.processName` is
`"RAWDesk"` — which fails both the `contains("xctest")` and `hasSuffix("tests")`
checks at `RAWDeskStorageDirectory.swift:70-73`. A name-based detector therefore
cannot see an Xcode-hosted run at all, which is exactly the reported failure. The
current first branch — `environment["XCTestConfigurationFilePath"]` at `:66-69` —
is set by Xcode in the host process and closes that hole independently of the
scheme. Combined with `shouldUseLaunchSchemeArgsEnv = "NO"`
(`RAWDesk.xcscheme:43`), which stops the Test action from inheriting the Run
action's environment, both reported failure modes are addressed.

**What remains unestablished** is only whether *every* configuration is covered:
a developer's local `xcuserdata` scheme, or a hand-edited scheme with the env var
toggled off, is not governed by `project.yml` or the shared scheme.
`xcuserdata` was not inspected. Guard 2 would still cover such a case, which is
why the verdict is refuted rather than merely narrowed — but the residual is the
reason for a confidence below 1.0 and for retaining the backup advice below.

### Confirmed gap the prior audit did not identify

`ImageCache` does **not** use `RAWDeskStorageDirectory.resolve`:

```swift
let base = (try? FileManager.default.url(
    for: .cachesDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
diskDirectory = base
    .appendingPathComponent("RAWDesk", isDirectory: true)
    .appendingPathComponent("Thumbnails", isDirectory: true)
```
— `Sources/RAWDesk/Services/ImageCache.swift:38-46`

Neither the env override nor `isTestProcess()` redirects this. Any test that
touches the thumbnail cache reads and writes the user's real
`~/Library/Caches/RAWDesk/Thumbnails/`, and `pruneDiskCacheIfNeeded` will
`removeItem` real cache entries over a 1 GiB budget (`:217-248`, budget at `:32`).

This directly contradicts `Docs/RAWDOCK_DATA_SAFETY.md:310-313`, which states the
redirect "is enforced in **production** code, so `swift test` cannot reach the
real catalog or real photos." True for the catalog; **false for the cache**. The
constructor does accept an injectable `directory:` (`:34`), so a test *can*
isolate it — but nothing forces that, and `resolve` is not consulted by default.

Impact is limited: cache contents are regenerable and the directory is separate
from originals. It is a real isolation leak, not a data-loss risk.

### Second confirmed gap, correctly reported by prior QA

`@AppStorage` and macOS window state resolve to the real preference domain
regardless of the override —
`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:9-13`. QA restored one known setting and
explicitly declined to guess at others (`:25-27`), which is the right call.
`scripts/run-isolated-ui-qa.sh` addresses this properly by relocating `HOME` /
`CFFIXED_USER_HOME` and re-signing under `local.rawdesk.app.uiqa` (`:14-22`).

### Relevant call chain

Xcode `TestAction` → env `RAWDESK_SUPPORT_DIRECTORY_OVERRIDE` **and**
`XCTestConfigurationFilePath` → `RAWDeskStorageDirectory.resolve:11-40` →
`CatalogStore:142` (isolated). Separately, and **not** isolated:
`ImageCache.init:38-47` → real `~/Library/Caches/RAWDesk/`.

### Runtime evidence

None obtained by this review — deliberately; this is the claim whose verification
would itself risk the harm (§0). **Pre-existing runtime evidence exists in the
repository** and is quoted above: `Evidence/2026-07-26/people-background/README.md:57-60`
records a 232-test Xcode run that left real-catalog and WAL timestamps unchanged.
That is second-hand and predates the current tree, so it is reported as
corroboration, not as a verdict of this review.

### Assumptions

- `XCTestConfigurationFilePath` is set by current Xcode test hosting. Widely
  relied upon and used as the primary signal here, but **not verified in this
  environment** — verifying it is exactly the test that was declined.
- The shared scheme is the one developers use. A stale local
  `xcuserdata` scheme would not be covered by either `project.yml` or the shared
  scheme; `xcuserdata` was not inspected.

### Possible counterexamples

- **`TEST_HOST` is the real app binary** (`project.yml:70-72`), so the full app
  launches under test. If any storage were resolved before the env is visible, or
  by a path bypassing `resolve`, isolation would leak. `ImageCache` is a confirmed
  instance of the latter.
- **`shouldUseLaunchSchemeArgsEnv = "NO"`** (`RAWDesk.xcscheme:43`) means the
  TestAction's own env block applies rather than the LaunchAction's — which is
  what makes Guard 1 effective for tests. Worth noting it also means the override
  does **not** apply when running the app normally from Xcode, which is correct
  and intended.
- A test that constructs `CatalogStore(directory:)` explicitly bypasses `resolve`
  entirely (`:142` takes the explicit path first, `RAWDeskStorageDirectory:8-10`).
  That is the intended test seam, not a leak.

### User-data impact

Historically: irreversible one-way schema migration of the real catalog —
documented, caught, and remediated. Currently: **no catalog exposure identified**
for the shared scheme. Confirmed exposure of `~/Library/Caches/RAWDesk/`
(regenerable data, plus possible eviction of real cache entries by
`pruneDiskCacheIfNeeded`) and of the real preference domain via `@AppStorage`.

### Minimum safe containment

1. Use the shared `RAWDesk` scheme for Xcode test runs; do not run tests from a
   local scheme whose Test action lacks
   `RAWDESK_SUPPORT_DIRECTORY_OVERRIDE`.
2. Treat `~/Library/Caches/RAWDesk/` and the `local.rawdesk.app` preference
   domain as **non-isolated** in all in-process test contexts. Use
   `scripts/run-isolated-ui-qa.sh` when either matters.
3. Backing up `~/Library/Application Support/RAWDesk/catalog.sqlite` before Xcode
   test runs is now belt-and-braces rather than necessary. Cheap; still advisable
   while the `xcuserdata` residual (above) is unexamined.

### Recommended permanent fix

1. Route `ImageCache`'s default directory through `RAWDeskStorageDirectory.resolve`
   (or a caches-specific equivalent honoring the same override and
   `isTestProcess()`).
2. Add a fail-closed assertion in `CatalogStore.init`: if `isTestProcess()` is
   true and the resolved directory is under the real Application Support path,
   `fatalError` rather than open. This converts a silent, irreversible migration
   into a loud, harmless crash.
3. Add a test asserting `RAWDeskStorageDirectory.resolve(nil)` is outside real
   Application Support — which, run under Xcode, empirically settles what this
   review could not.

### Confidence: **0.95** that the historical incidents occurred and were
remediated as documented; **0.88** that current Xcode runs via the shared scheme
are isolated for the catalog (two independent guards by inspection, plus the
project's own post-fix 232-test run; deducted for `xcuserdata` not inspected and
no first-hand runtime check); **0.95** that the `ImageCache` gap is real.

---

## 8. Contradictions and defects in the existing audit documents

Recorded as required. The existing documents are not renamed or rewritten.

### 8.1 `Docs/RAWDOCK_DATA_SAFETY.md:213` — false completeness claim

*"No unclassified mutation site remains."* Refuted in §3: five wrapped `.write(`
sites, two `CGImageDestinationCreateWithData` sites, and every `createDirectory`
site are absent from the §5 table.

### 8.2 `Docs/RAWDOCK_DATA_SAFETY.md:40-41` — false count

*"**Exactly one** image-writing call exists in the entire codebase."* There are
three `CGImageDestination` creation sites (§3). The two omitted are in-memory and
harmless, but the stated grep (`:33`) covers only the `…WithURL` variant, so the
claim is broader than its own method could support.

### 8.3 `Docs/RAWDOCK_DATA_SAFETY.md:310-313` — overstated isolation

*"enforced in **production** code, so `swift test` cannot reach the real catalog
or real photos."* Correct for the catalog; **incorrect** in general —
`ImageCache.swift:38-46` reaches the real caches directory under any test
context (§7).

### 8.4 `Docs/RAWDOCK_DATA_SAFETY.md:120` — "same discipline" overstates parity

Auto Import's `removeVerifiedSource` shares the dual-SHA-256 checks but **lacks
the post-delete existence check** that `PhotoImportService:911-917` performs, and
deletes sidecar-before-photo where the manual path deletes photo-before-sidecar
(§1). Calling the two paths equivalent obscures both differences.

### 8.5 The two deletion paths are inconsistently ordered

Not asserted anywhere, but worth recording: `AutoImportService:351,353` deletes
sidecar then photo; `PhotoImportService:911,931` deletes photo then sidecar.
Neither is transactional. Auto Import's failure message
(`AutoImportService.swift:196`) claims the source "was retained" in a window where
the sidecar has already been deleted.

### 8.6 Naming split — RAWDesk vs RawDock, unresolved

Five documents are named `RAWDOCK_*` while every artifact in the repository says
**RAWDesk** (`Package.swift:5`, `project.yml:1`, bundle id `local.rawdesk.app`).
`Docs/RAWDOCK_DATA_SAFETY.md:10-13` flags this and treats "RawDock" as an alias on
its own authority. That is an unresolved naming question presented as settled;
only the product owner can settle it. This deliverable follows the requested
`RAWDESK_*` spelling, which matches the code and adds a **third** convention to
`Docs/`.

### 8.7 A QA document treats an un-imported external file as its authoritative spec

`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:3` names
`~/Downloads/RAWDesk_UI改善書_v1.0-draft.md` as 対象仕様 (the governing
specification). That path is **outside the repository**, is named `draft`, and was
**not read during this review** — per the constraint that an external document is
not authoritative unless the product owner explicitly imports and approves it.

This matters beyond bookkeeping: QA results in that document are traceable to a
specification that is not under version control, may have changed since, and
cannot be reviewed by anyone but its holder. Any requirement in it should be
imported into `Docs/` and approved before being treated as binding.

The same document is otherwise the most careful in the set — it declares its
isolation boundary up front, records what it restored, and explicitly declines to
guess at settings whose prior values it had not captured (`:25-27`).

### 8.8 `Docs/RAWDOCK_DATA_SAFETY.md` §6.5 cites half of its own source

This is the most consequential documentation defect found, because it produces
advice that is both wrong and costly.

§6.5 (`:308-336`) cites `Evidence/2026-07-26/people-background/README.md:39-44`
for the WAL-file probe and concludes:

> "Treat Xcode-hosted test runs as capable of touching the real catalog unless
> isolation is re-verified." — `Docs/RAWDOCK_DATA_SAFETY.md:333-336`

Isolation **was** re-verified — and the record of it is in the same file, sixteen
lines below the passage cited: the scheme hardening
(`people-background/README.md:45-50`), the XcodeGen regeneration probe
(`:52-55`), and a 232-test Xcode run that left real-catalog and WAL timestamps
unchanged (`:57-60`). The audit quoted the incident and omitted the resolution.

The audit's heading — *"Test isolation is reliable for SwiftPM, but NOT for
Xcode-hosted runs"* (`:308`) — is therefore incorrect for the current tree, and
its recommendation 8 (*"Fix Xcode test isolation so a stray run cannot migrate the
real catalog"*, `:377-378`) asks for work that is already done. Meanwhile the
isolation gap that **is** real and unfixed — `ImageCache` bypassing
`RAWDeskStorageDirectory.resolve` (§7) — is absent from the audit entirely, and is
contradicted by its claim at `:310-313` (§8.3). The net effect is to direct
attention away from the live defect and toward a closed one.

### 8.9 Where the existing audit was right, and notably so

Recorded for balance: `Docs/RAWDOCK_DATA_SAFETY.md:296-302` flags its own
`fileResourceIdentifier` claim as inference rather than fact and points to a
specific experiment. That self-limitation is accurate and is the correct handling
of an unverifiable claim. Claims 1, 2, 4, 5 (fallback tier), and 6 were all
substantively correct on the mechanism, with exact and checkable citations.

---

## 9. Verdict summary

| # | Claim | Verdict | Confidence |
|---|---|---|---|
| 1 | Auto Import copies then permanently deletes, regardless of mode | **Confirmed** (source) | 0.97 |
| 2 | Manual move deletes permanently, not via Trash | **Confirmed** (source) | 0.98 |
| 3 | Prior audit identified every mutating path | **Refuted** | 0.93 |
| 4 | Full-res RAW export can silently fall back to embedded JPEG | **Confirmed** (source) | 0.95 mechanism / 0.6 reachability |
| 5 | Identity can fall back to path\|size\|mtime | **Confirmed** (fallback tier); primary tier **not established** | 0.97 / n-a |
| 6 | Relink validates weakly; wrong photo or stale metadata | **Confirmed** (source) | 0.96 |
| 7 | Xcode test config can open/migrate the real catalog | **Refuted** for the catalog in the current tree (historical form confirmed); separate **cache** isolation gap confirmed | 0.88–0.95 |

No claim was confirmed by a runtime test run by this review. See §0.

### Blocking risk

**Auto Import must not be enabled** (§1) — unattended, unconfirmed, permanent
deletion of originals, with no setting that can disable it. It is off by default;
keep it off. This is the only finding in scope that destroys photographs, and it
is the one thing here that should gate further development.

**Nothing blocks test execution on catalog grounds** (§7) — contrary to
`Docs/RAWDOCK_DATA_SAFETY.md:333-336`. Two independent guards are in place and the
project's own post-fix 232-test Xcode run verified them. In-process tests do still
write the real `~/Library/Caches/RAWDesk/` and the real preference domain, so use
`scripts/run-isolated-ui-qa.sh` when those matter.

### First three changes

1. **Gate Auto Import's deletion and route it through the existing seam** —
   `Sources/RAWDesk/Services/AutoImportService.swift` (`:181-199`, `:308-354`),
   `Sources/RAWDesk/Models/AutoImportModels.swift` (add `sourceHandling`, default
   `.keep`), `Sources/RAWDesk/Views/AutoImportSettingsView.swift` (expose it).
2. **Default both deletion paths to the Trash** —
   `Sources/RAWDesk/ViewModels/LibraryViewModel.swift:243-245` supplies a
   `trashItem` handler; `Sources/RAWDesk/Services/PhotoImportService.swift:54-56`
   changes the default. Highest safety per line changed in the repository.
3. **Close the confirmed cache isolation gap and make isolation fail loudly** —
   `Sources/RAWDesk/Services/ImageCache.swift:38-46` routes its default directory
   through `RAWDeskStorageDirectory.resolve` (or a caches-specific equivalent
   honoring the same override and `isTestProcess()`);
   `Sources/RAWDesk/Services/CatalogStore.swift:142` gains a fail-closed
   `isTestProcess()` assertion so a future regression crashes instead of migrating;
   `Tests/RAWDeskTests/` gains a test asserting the resolved directory is outside
   real Application Support and outside the real caches directory.

   Note this is a *different* change from the audit's recommendation 8
   (`Docs/RAWDOCK_DATA_SAFETY.md:377-378`), which asks for catalog isolation that
   already exists (§8.8).

Deferred but not forgotten: export decode-source gating (§4),
relink content verification (§6), content-hash identity recovery (§5).
