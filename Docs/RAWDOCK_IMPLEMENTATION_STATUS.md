# RAWDesk — Implementation Status

Each workflow is classified against **code evidence**, not documentation claims.

**Classification key**

| Term | Meaning |
|---|---|
| **Functional** | Traced end to end: UI → service → persistence/output. |
| **Partial** | Core works; a specific, named part is missing or weaker than it appears. |
| **Mock-only** | Presents a result not backed by real computation. |
| **Absent** | Not implemented. |
| **Deprecated** | Superseded but still present. |
| **Unsafe** | Works, but can lose data or produce silently wrong output. |
| **Unclear** | Could not be resolved by inspection. |

**Headline:** this codebase contains **zero** TODO/FIXME markers, **zero**
`.disabled(true)`, **zero** commented-out code, and **zero** dead adjustment
bindings across 68,500 lines. There is **no mock-only feature** in the product.
The risks here are not unfinished stubs — they are *silent correctness and
data-safety gaps in code that works*.

---

## 1. Feature matrix

### Import and ingest

| Workflow | Status | Evidence |
|---|---|---|
| Add (reference in place) | **Functional** | `PhotoImportModels.swift:3-37`; 26 import tests |
| Copy to folder (verified) | **Functional** | `PhotoImportService.swift:1071-1093` temp→SHA-256→atomic move |
| Move to folder | **Functional but Unsafe** | `:853-947`. Rigorous dual-hash gating; **permanent delete, no Trash** (`:54-56`) |
| Collision handling | **Functional** | `:1023-1069` — never overwrites; 10,000 numbered suffixes; exact-hash reuse |
| Rollback on failure | **Functional** | `:1277-1286`; test `RAWDeskTests.swift:5790` |
| Duplicate detection | **Functional** | Two-tier: file SHA-256 + metadata-insensitive image-data hash (`FileContentHasher.swift`) |
| Filename/folder templates | **Functional** | `PhotoImportTemplate.swift`; validated tokens |
| Auto Import (watched folder) | **Functional but Unsafe** | `AutoImportService.swift`. Verified, but **unconditionally deletes** the source (`:187`) with no opt-out; disabled by default |
| Copy as DNG | **Absent** | Documented as a gap (`README.md:1631`) |
| Camera/card orchestration | **Absent** | Documented as a gap |

### Catalog and organization

| Workflow | Status | Evidence |
|---|---|---|
| SQLite catalog | **Functional** | `CatalogStore.swift`, 15 tables, `user_version = 12` |
| Migrations | **Partial** | Additive-only (`:4230-4243`). Real v6→v12 and v7→v12 tests exist. **No forward-compat guard**: a newer catalog opened by an older build is not detected |
| Corruption recovery | **Functional** | `:3624-3648` — corrupt DB preserved as `.corrupt.<ts>`, never deleted |
| In-memory fallback | **Unsafe** | `:3651-3661` — session's work silently discarded at quit; warning set but prominence unverified |
| Collections / sets / smart collections | **Functional** | `CatalogModels.swift`; `deletePhotoCollection` has **0 test coverage** |
| Keywords (hierarchical) | **Functional** | Transactional rename/move/merge |
| Photo stacks | **Functional** | Manual + capture-time auto (`CaptureTimeAutoStackPlanner.swift`); `removePhotosFromStacks` has **0 test coverage** |
| Missing-file detection | **Functional** | `catalogMissing`, "Missing Files" smart collection; tests physically delete files |
| Relink | **Unsafe** | `CatalogStore.swift:2091-2200` — verifies **extension only**; no size/hash check; **retains stale EXIF** (`:2169`) |
| Remove from catalog | **Functional** | `:2271` catalog-only. Confirmation dialog states "No image file will be deleted" — accurate |
| Large-library query planning | **Partial** | Saved filters apply **after** loading entries, not in SQL (`README.md`) |

### Rendering and develop

| Workflow | Status | Evidence |
|---|---|---|
| Grid thumbnails (fast path) | **Functional** | `RAWImageLoader.swift:135-186` — never decodes a RAW mosaic for the grid |
| RAW decode | **Functional (delegated)** | Apple `CIRAWFilter`; **RAWDesk implements no demosaic** |
| RAW fallback chain | **Unsafe** | `:77-130` — silent degradation to embedded preview/QuickLook |
| Develop pipeline | **Functional** | All 46 `PhotoAdjustments` fields consumed by `PhotoProcessor` |
| Tone/color/HSL/curves | **Functional** | All 24 color-mixer controls reach a 3D LUT via `ColorMixerChannel.allCases` |
| Local masks | **Functional** | All 15 `LocalToneAdjustments` fields consumed (`PhotoProcessor.swift:1020-1210`); Vision-backed subject masks |
| Spot removal / heal / clone | **Functional** | `:1609` |
| Optics / geometry / guided upright | **Functional** | Guided-upright guides solved into `geometry` + `straighten` (indirect by design) |
| Detail (sharpen / NR) | **Functional** | Every secondary parameter is a real CIFilter input — verified individually |
| Effects | **Functional** | Gated by a real `effectsEnabled` flag |
| Presets / profiles | **Functional** | `DevelopmentPreset`, `DevelopmentProfile` |
| Edit versions | **Functional but Unsafe** | `EditVersion.swift`; **deletion has no confirmation** — one click, irreversible (`EditingInspectorView.swift:2059`) |
| Multi-photo sync | **Functional** | `PhotoAdjustmentSync.swift` |
| Undo / redo | **Functional** | Per-asset stacks in `LibraryViewModel` |
| Learned denoise / Super Resolution / generative fill | **Absent** | Documented gaps |
| Panorama / HDR merge | **Absent** | Documented gap |

### Color management

| Workflow | Status | Evidence |
|---|---|---|
| ICC profile discovery | **Functional** | ColorSync enumeration (`SoftProofProfileCatalog.swift:71`) |
| Soft proofing | **Functional** | Real round trips, rendering intent, dual gamut warnings (`SoftProofProcessor.swift`) |
| Wide-gamut preview | **Functional** | Half-float working space (`RAWImageLoader.swift:54-62`) |
| **Color-managed export** | **Absent** | `ImageExporter.swift:134` always tags sRGB; `renderFullResolution` never requests wide gamut. **Soft-proof settings do not affect exports.** |
| Monitor calibration | **Absent** | Documented non-goal |

### Metadata and interchange

| Workflow | Status | Evidence |
|---|---|---|
| EXIF/IPTC read | **Functional** | `MetadataReader.swift`, at scan time for every file |
| XMP sidecar read | **Functional** | On scan, only when no stored state exists |
| XMP sidecar write | **Functional** | Manual only (`LibraryViewModel.swift:4198`); atomic; preserves foreign packets. **No confirmation before overwriting an existing sidecar** |
| XMP payload completeness | **Partial** | Oversized payloads silently drop to Adobe-compatible globals with a warning (`XMPSidecarService.swift:1206-1209`) |
| Writing metadata into originals | **Absent by design** | Correct and verified |

### Export

| Workflow | Status | Evidence |
|---|---|---|
| JPEG / PNG export | **Functional** | Genuinely re-develops from the original at full resolution |
| EXIF/IPTC/GPS propagation | **Functional** | With location override/suppression (`ImageExporter.swift:154-202`) |
| TIFF / 16-bit / wide gamut | **Absent** | `:8-25` |
| Export from embedded preview | **Unsafe** | Silent ~4096 px downgrade if RAW decode fails |

### People, map, culling

| Workflow | Status | Evidence |
|---|---|---|
| Face detection | **Functional** | `VNDetectFaceCaptureQualityRequest` (`PeopleAnalyzer.swift:383`) |
| Face **identity** clustering | **Partial** | Uses a **generic image feature print** of the face crop (`:409`), not Apple's face-print API. Clusters by appearance, not identity — materially weaker. Doc correctly disclaims biometric identity |
| Naming / merge / unassign | **Functional** | Confirmation-first; never writes to source or XMP |
| Map, GPS, GPX, saved locations | **Functional** | MapKit; non-destructive coordinate assignment |
| Private location export | **Functional** | `suppressLocationMetadata` (`ImageExporter.swift:185-198`) |
| Assisted Culling | **Functional** | Real on-device scoring; no automatic deletion |

### UI and shell

| Workflow | Status | Evidence |
|---|---|---|
| Redesigned layout (default) | **Functional** | `ContentView.swift:528` |
| Legacy layout | **Deprecated** | `@AppStorage("rawdesk.ui.useLegacyLayout") = false`; toolbar calls it a "temporary rollback switch" (`ToolbarContent.swift:250`) |
| — double-click to open loupe (legacy) | **Absent in legacy** | `onOpenLoupe` default no-op never overridden by `ContentView` |
| — expand-to-activate tool (legacy) | **Absent in legacy** | `onActivateTool` no-op; tools still reachable via explicit buttons |
| Keyboard shortcuts | **Functional** | All 14 `KeyboardHandler` closures do real work; three guard layers prevent hijacking |
| Menu commands (~60) | **Functional** | `RAWDeskApp.swift:21-666` |
| Compare / Survey / Reference | **Functional** | Pure, tested planners |
| Dead views | **Deprecated** | `RAWWorkspaceModeHeader` (`RAWDeskDesignSystem.swift:873`), `Tag` (`MetadataInspectorView.swift:754`) — zero references |

### Persistence, caching, sync

| Workflow | Status | Evidence |
|---|---|---|
| SQLite persistence | **Functional** | WAL, foreign keys, serialized queue |
| JSON `user_state.json` | **Functional but Unsafe** | Duplicates catalog state; SQLite write is `try?`; no reconciliation |
| Write amplification | **Partial** | Entire dictionary rewritten on every change (`UserStateStore.swift:79-88`) |
| Two-level image cache | **Functional** | Memory + SHA-256-named disk cache with LRU |
| Cloud sync / multi-device | **Absent** | No networking code anywhere |
| Security-scoped bookmarks | **Functional** | Used for recents and auto-import folders |

### Tests

| Aspect | Status | Evidence |
|---|---|---|
| Fixture safety — **SwiftPM** | **Functional** | 342 tests; `swift test` cannot touch real photos or the real catalog — enforced in *production* code (`RAWDeskStorageDirectory.swift:25-40`); no test references `testraw/` |
| Fixture safety — **Xcode-hosted** | **Unsafe** | The override did not propagate; runs **irreversibly migrated the real catalog** 7→9 and 8 (`Evidence/2026-07-26/people/README.md:136-142`, `map/README.md:99-121`). `@AppStorage`/window state always use the real domain |
| Catalog / import / XMP coverage | **Functional** | Real SQLite files, real disk I/O, real migrations, destructive move-mode covered |
| Processor tests (62) | **Partial** | *Directional* only — assert a knob moves brightness the right **way**, never by the right **amount** |
| Design-token tests | **Mock-only** | ~215 lines asserting literals equal themselves (`UIStateContractTests.swift:8` vs `RAWDeskDesignSystem.swift:81`) — verified |
| Timing-as-structure assertions | **Unclear** | 3 sites assert wall-clock `< 2s` to prove a structural property; a fast machine passes regardless |
| RAW decode correctness | **Absent** | Zero by default. The 2 real-RAW tests are env-gated and check dimensions/metadata, not pixels |
| SwiftUI view rendering | **Absent** | No test instantiates a view. One real source-linter test greps view files for design-token violations |

---

## 2. Verification status by format

| Format | Recognized | Verified end to end |
|---|---|---|
| Sony ARW | Yes | **Yes** — release QA with a real file, hash-checked |
| Canon CR2 | Yes | No — fixture exists, no pipeline evidence |
| JPEG / PNG | Yes | Yes — via synthesized real files in tests |
| CR3, DNG, NEF, RAF, RW2, ORF | Yes | **No evidence of any kind** |
| HEIC, TIFF | Yes | No direct evidence |

---

## 3. Contradictions between documentation and implementation

The documentation is **unusually accurate**; spot-checks repeatedly confirmed
non-obvious claims. The genuine divergences are narrow:

1. **Auto Import mode.** `README.md` correctly calls it a "verified move-based
   Auto Import", and the settings UI is explicit. But the *code* requests
   `mode: .copyToFolder` (`AutoImportService.swift:148`) and deletes separately
   at `:187`. Docs and UI are right; **the code reads as if it were
   non-destructive.** A developer-facing contradiction, not a user-facing one.
2. **Color management scope.** The README's architecture section leads with
   "color-managed Core Image pipeline" — true for *display and proofing*, but
   export is unconditionally sRGB 8-bit. The gaps section is candid about output
   limitations; the summary is not.
3. **"Verified" release status.** The release is named
   `RAWDesk-v0.1-Sony-ARW-Verified` — correctly scoped to Sony ARW. Risk is in
   *reading* it as general RAW verification.
4. **Three navigation enums** (`WorkspaceMode`, `PhotoWorkspaceMode`,
   `WorkspaceDestination`) — all three are live and none is documented as
   subordinate to the others.

**No claim was found where documentation asserts a feature that does not exist.**

### Contradictions *within* the QA record

These do not affect what the product does, but they undermine the QA trail:

5. **Two "final" binaries on 2026-07-30.** Three documents name `ea0c6497…`
   with **342 tests**; `Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:60-61` names
   `8371b178…` with **336 tests**. The current suite has **342 test functions**,
   favoring the first — but neither binary can be hashed, and **the project is
   not a git repository**, so there is no history to arbitrate. See
   `RAWDOCK_OPEN_QUESTIONS.md` Q7.
6. **Same 2026-07-27 release credited with both 297 and 298 tests** —
   `GOAL_CLOSURE_2026-07-27.md:17` vs `RELEASE_MANIFEST.md:14`, identical release
   SHA.
7. **README is stale relative to `Docs/`.** Its "Current verification" section is
   pinned to 2026-07-26 (289 tests), predating the 07-27 freeze and the 07-30 UI
   redesign. It states no version number, while `Docs/` says 0.1.1 (build 2). It
   also *understates* Sony ARW support (`README.md:618-620` calls ARW
   decoder-dependent, while the 07-27 release records a passing real-α7 IV
   end-to-end run) and lists only two test files where three exist.
8. **The authoritative UI spec is outside the repository.** All six `Docs/` QA
   files trace their requirement IDs to
   `~/Downloads/RAWDesk_UI改善書_v1.0-draft.md`. That file **exists**
   but is untracked and distinct from the in-repo brief. See Q8.
9. **Much of the UI acceptance matrix is explicitly open.** Accessibility
   (`RAWDesk_ACCESSIBILITY_QA_MATRIX.md` — every VoiceOver/keyboard/display row
   reads 未実施) and first-use usability (`RAWDesk_FIRST_USE_USABILITY_TEST.md:5`
   — 状態: 未実施) are unperformed, and the traceability doc warns that
   `PASS-SOURCE` is not a substitute for observation and that prior-release
   screenshots must not be used as current evidence. **The QA record is candid
   about its own gaps** — a point in its favor.

---

## 4. Prioritized attention list

| # | Item | Class | Doc |
|---|---|---|---|
| 1 | No deletion uses the Trash | Unsafe | Safety §3 |
| 2 | Auto Import deletes unconditionally, mode flag bypassed | Unsafe | Safety §3.2 |
| 3 | Export can silently come from a 4096 px embedded preview | Unsafe | Safety §6.2 |
| 4 | Relink verifies extension only; retains stale EXIF | Unsafe | Safety §6.3 |
| 5 | File identity built on a non-persistent OS identifier | Unsafe | Safety §6.4 |
| 6 | Dual state stores, SQLite write is `try?` | Unsafe | Safety §6.6 |
| 6b | **Xcode-hosted test runs can irreversibly migrate the real catalog** (one-way; no down-migration). Back up `catalog.sqlite` before running tests from Xcode; prefer `swift test` | Unsafe | Safety §6.5 |
| 7 | In-memory catalog fallback silently discards a session | Unsafe | Safety §6.1 |
| 8 | Edit-version deletion has no confirmation | Unsafe | UI audit |
| 9 | Export ignores all color management | Partial | Spec §4.3 |
| 10 | Face clustering uses a generic feature print | Partial | Spec §4.6 |
| 11 | No RAW decode correctness coverage | Absent | Tests |
| 12 | Only Sony ARW verified of eight RAW formats | Partial | §2 |
