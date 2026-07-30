# RAWDesk — Open Questions

Only questions that **cannot be resolved by further inspection of this
repository**. Anything answerable from code has been answered in the other four
documents instead.

Each entry gives the evidence, the options, and a recommended default so work can
continue without blocking.

---

## Q1. Is "RawDock" a rename, or a different product?

**Evidence.** The product is **RAWDesk** in every artifact: `Package.swift:5`,
`project.yml:1`, bundle id `local.rawdesk.app`, all 34 documents, every
screenshot. A case-insensitive search for "rawdock" across the entire repository
returns **zero** hits outside the documents created by this analysis.

**Why unresolvable.** Nothing in the repo records an intended rename.

**Options.** (a) "RawDock" is a typo or informal alias. (b) A planned rename not
yet started. (c) A different product entirely.

**Recommended default: (a).** Everything else in the request matches this
repository exactly. Proceed as RAWDesk; treat the deliverable filenames as the
only place the other spelling appears. **Confirm before any user-visible rename** —
bundle id, Application Support directory name, and the `rawdesk` XMP namespace
would all be affected, and the last one breaks sidecar round-tripping with
already-written files.

---

## Q2. Does `fileResourceIdentifier` persist across reboots on the target volumes?

**This is the single highest-value question in the repository.**

**Evidence.** `PhotoLibraryScanner.stableID` (`:189-200`) prefers
`URLResourceKey.fileResourceIdentifierKey` and uses the result as the **permanent
primary key** of `catalog_photos` (`CatalogStore.swift:3707`) and of
`user_state.json`. Apple documents this key as an opaque per-volume identifier
that callers should not persist. `README.md:668-669` states the intent: *"A stable
file resource identifier is preferred over a path-based identifier, so edits
survive ordinary in-place renames on supported volumes."* — the intent is real
and the benefit (surviving renames) is real.

**Why unresolvable.** Whether the value actually rotates depends on macOS version,
filesystem (APFS vs HFS+ vs exFAT vs SMB/NFS), and external-volume remounts. It
cannot be determined by reading Swift. The repo contains **no test** that
persists an ID across a simulated reboot or remount.

**Blast radius if it does rotate.** Every rating, keyword, edit, and version is
orphaned. Photos reappear as new, unedited assets. There is **no content-hash
recovery path**, even though `content_hash` and `image_content_hash` exist and are
populated.

**Options.**
- (a) Keep as-is; accept the risk.
- (b) Keep it as the *lookup* key but add a content-hash fallback so a rotated ID
  re-matches instead of orphaning.
- (c) Move to content-hash-primary identity (costly: hashing every file on scan).

**Recommended default: (b).** It preserves the rename-survival benefit that
motivated the current design while removing the catastrophic failure mode, and it
reuses hash infrastructure that already exists. **Before choosing, run the
experiment** — catalog a photo on an external APFS volume, reboot, remount, and
check whether the ID still resolves. That is a one-hour test that converts this
open question into a settled fact.

---

## Q3. Should originals go to the Trash instead of being permanently deleted?

**Evidence.** `trashItem` appears **nowhere** in the repository. Both
source-deleting paths use `FileManager.removeItem` — `PhotoImportService.swift:54`
and `AutoImportService.swift:351,353`. Deletion is preceded by dual SHA-256
verification and is therefore *safe against copying errors*, but is
**unrecoverable against user error** (wrong folder chosen, wrong mode selected).

The docs never claim Trash behavior, and the UI accurately says "remove". So this
is a deliberate-looking gap, not a documentation lie — but no document states
*why* permanent deletion was chosen.

**Options.**
- (a) Keep permanent deletion (matches "verified move" semantics; no Trash bloat
  when ingesting a 128 GB card).
- (b) Always route through `trashItem`.
- (c) User preference, defaulting to Trash.

**Recommended default: (c), defaulting to Trash.** The `sourceRemovalHandler`
seam at `PhotoImportService.swift:54` already exists precisely to make this
swappable, so the change is small. Card-ingest bloat is a real concern, which is
why it should be a preference rather than forced — but the safe option should be
the default. **This is an owner decision because it trades disk pressure against
recoverability**, and only the owner knows the target ingest volume.

---

## Q4. Should Auto Import be able to *not* delete the watched folder?

**Evidence.** `AutoImportSettings` (`AutoImportModels.swift:3-52`) has **no mode
field**. `AutoImportService` requests `mode: .copyToFolder` (`:148`) and then
deletes the source unconditionally at `:187`. The UI is honest about this
(`AutoImportSettingsView.swift:382-390`), and `README.md:637-640` documents it.

So the behavior is intentional and disclosed. The question is whether it should
remain the *only* behavior.

**Options.**
- (a) Keep move-only (a watched folder is a staging area; leaving files would
  re-trigger ingest and needs dedupe on every event).
- (b) Add a copy mode with a "processed" marker or subfolder.

**Recommended default: (a), plus a code-clarity fix.** The design rationale is
sound. But `mode: .copyToFolder` at `:148` actively misleads a reader into
thinking the operation is non-destructive — rename the local or add a comment
regardless of which option is chosen. **The owner decision is only whether to add
option (b);** the clarity fix should happen either way.

---

## Q5. Should export be color-managed?

**Evidence.** Display-side color management is genuinely sophisticated: ColorSync
profile enumeration (`SoftProofProfileCatalog.swift:71`), real round trips with
selectable rendering intent, dual gamut warnings, half-float wide-gamut working
space. Export ignores all of it — `ImageExporter.swift:134` always tags
`sRGB IEC61966-2.1`, JPEG/PNG only, 8-bit.

`README.md:584-585` says *"Development and export use an extended-linear working
space and an sRGB output color space"* — so sRGB output is **stated intent**, not
an oversight. But a user who soft-proofs to Adobe RGB and exports gets sRGB with
no warning that the proof did not apply.

**Options.**
- (a) Keep sRGB-only (correct for web delivery, the common case).
- (b) Add an export profile picker honoring the soft-proof selection.
- (c) Keep the default but warn when soft proofing is active and the profile
  differs from sRGB.

**Recommended default: (c) now, (b) later.** (c) is small and closes the
expectation gap immediately. (b) is the real fix but implies TIFF/16-bit support
to be meaningful, which is a larger scope decision — and `README.md:1534` already
classes output as a "Major gap", so the owner may intend to defer.

---

## Q6. Is the People feature meant to reach identity-grade accuracy?

**Evidence.** Face *detection* is real (`VNDetectFaceCaptureQualityRequest`,
`PeopleAnalyzer.swift:383`). Clustering uses
`VNGenerateImageFeaturePrintRequest` on the face crop (`:409`) — a **generic image
feature print**, not Apple's dedicated face-print API. This measures overall
appearance similarity (lighting, pose, background), not facial identity.

`README.md:1616-1617` frames this deliberately: *"a confirmation-first organizer,
not a claim of biometric identity"*, and milestone 5 lists "higher-quality learned
identity suggestions" as future work. So the limitation is known and accepted.

**Why unresolvable.** Whether the current quality is *acceptable* is a product
judgment, not a code fact.

**Options.** (a) Keep as a low-confidence assist. (b) Switch to Apple's face-print
API for materially better identity matching. (c) Defer per milestone 5.

**Recommended default: (b).** The switch is contained to `PeopleAnalyzer`, uses a
purpose-built API, and would improve the feature's core value without changing the
confirmation-first UX. **Note:** this invalidates cached feature prints —
`catalog_face_analysis` would need a version bump and re-analysis.

---

## Q7. Which 2026-07-30 build is the accepted release?

**Evidence.** Three same-day documents name
`ea0c6497…` as the final binary (`Docs/RAWDesk_UI_REDESIGN_IMPLEMENTATION.md:176`,
`RAWDesk_UI_REQUIREMENT_TRACEABILITY.md:35-37`,
`RAWDesk_THUMBNAIL_PERFORMANCE_QA_2026-07-30.md:123-124`) with **342 tests**.
`Docs/RAWDesk_RUNTIME_QA_2026-07-30.md:60-61,128-129` names
`8371b178…` as 「修正後の最終release binary」 with **336 tests**. A third hash
`aae3204a…` covers earlier steps.

A parallel conflict exists on 2026-07-27: the **same** release SHA is credited
with 298 tests (`RELEASE_MANIFEST.md:14`) and 297 (`GOAL_CLOSURE:17`).

**Verified independently:** the current suite has **342 test functions**, matching
the `ea0c6497…` documents.

**Why unresolvable.** The binaries are not in the repo to hash, **and the project
is not a git repository** — there is no history to arbitrate which document is
later.

**Options.** (a) Treat `ea0c6497…` / 342 as authoritative. (b) Re-run the suite
and rebuild to establish a fresh baseline.

**Recommended default: (b), expecting it to confirm (a).** The 342 count matches
the present source, so (a) is very likely right — but since neither binary can be
verified, rebuilding is cheaper than reasoning about it. **Do this before trusting
any QA claim in `Docs/`.**

---

## Q8. Should the authoritative UI spec be brought into the repository?

**Evidence.** All six `Docs/*.md` QA documents trace every P0/P1/P2 requirement ID
and acceptance condition to
`~/Downloads/RAWDesk_UI改善書_v1.0-draft.md`.

**That file exists** (44,848 bytes, 2026-07-29) — but it is in `~/Downloads`,
**outside the repository**. It is a *different* document from the in-repo
`RAWDesk_UI_SPEC_AND_IMPROVEMENT_BRIEF_FOR_CLAUDE_FABLE5.md` (44,930 bytes): the
in-repo file is the **input brief**, and the Downloads file is the **derived
v1.0-draft spec** that cites the brief as its basis (根拠).

**Why this matters.** The requirements source of truth for every UI acceptance
criterion is untracked, sits in a directory users routinely clear, and would not
reach a new engineer who copied the project folder. Compounding it, **the project
is not under version control at all** — no `.git`.

**Options.** (a) Move it into `Docs/`. (b) Leave it and update the references.
(c) Treat the in-repo brief as authoritative and re-derive.

**Recommended default: (a), and initialize git.** This is the cheapest
high-impact fix available: one file copy makes six QA documents self-contained.
**It is an owner decision only because the spec is in Japanese and may be
considered internal** — otherwise it would simply be a bug.

---

## Q9. What is the target library size?

**Evidence.** `Docs/RAWDesk_THUMBNAIL_PERFORMANCE_QA_2026-07-30.md:9-21` records a
real catalog of **4,706 photos** performing well. But two designs scale poorly:
`UserStateStore.persistLocked` (`:79-88`) rewrites the **entire** JSON dictionary
on **every** state change, and saved custom collections *"apply their filter after
loading catalog entries rather than using a large-library FTS/fully-SQL query
planner"* (`README.md:1621-1623`).

**Why unresolvable.** The acceptable ceiling is a product decision.

**Options.** (a) Optimize for ~5k (current, verified). (b) Target 50–100k:
incremental state persistence plus SQL-side filtering. (c) Target 500k+:
significant re-architecture.

**Recommended default: (a) until a concrete target is set.** Both bottlenecks are
known, isolated, and documented — they can be addressed when a target exists.
Optimizing now, without a number, risks complexity for no measured benefit.

---

## Q10. Which RAW formats must actually be supported?

**Evidence.** `FileFormat` lists eight RAW formats, but assignment is
**extension-only** and decoding is entirely delegated to Apple's `CIRAWFilter` —
RAWDesk implements no demosaic. Only **Sony ARW** has end-to-end verification
(`Releases/RAWDesk-v0.1-Sony-ARW-Verified-2026-07-27/`). Canon CR2 has a fixture
but no pipeline evidence. CR3, DNG, NEF, RAF, RW2, ORF have **no verification of
any kind**. The default test suite decodes **no** real RAW file.

`…FABLE5.md:56` names the target user as shooting *"Sony α など"*, and
`README.md:556-557` marks ARW and CR2 as first-class.

**Why unresolvable.** Which cameras must work is a product decision, and
verification depends on hardware and files not in the repo.

**Options.** (a) Sony + Canon first-class, others best-effort (matches current
evidence). (b) Verify all eight with real files. (c) Narrow the advertised list to
what is verified.

**Recommended default: (a), with (c) applied to the UI.** Continue treating ARW
and CR2 as first-class, but surface decode provenance to the user — the app
already tracks `PhotoAsset.rawDecodeSource` and the UI already has an
`ARW · Preview` badge for fallback (`Docs/RAWDesk_UI_REDESIGN_IMPLEMENTATION.md:79`).
Extending that honesty to the **export** path resolves most of the risk without
needing to verify eight formats.

---

## Non-questions — resolved by inspection, recorded to prevent re-litigation

| Question | Answer |
|---|---|
| Can RAWDesk corrupt an original? | **No.** One image-write call, to a user-chosen export path. No in-place writes, no subprocesses. |
| Does it write metadata into originals? | **No.** Sidecars only; the extension is always replaced. |
| Does "remove from catalog" delete files? | **No.** `CatalogStore.swift:2271` is catalog-only. |
| Is `swift test` safe to run? | **Yes.** Isolation is enforced in *production* code (`RAWDeskStorageDirectory.swift:25-40`), not test discipline. |
| Are there mock or stub features? | **No.** Zero TODO/FIXME, zero `.disabled(true)`, zero dead adjustment bindings. |
| Is the develop pipeline real? | **Yes.** All 46 adjustment fields reach `PhotoProcessor`. |
| Does export apply edits? | **Yes.** It re-develops from the original at full resolution. |
