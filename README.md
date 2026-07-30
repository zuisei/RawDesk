# RAWDesk

RAWDesk is a macOS-native, local-first photo organizer and
non-destructive RAW editor. It can reference folders in place or safely
copy selected photos into a destination, monitor a dedicated camera
drop folder for verified automatic ingest, develop RAW and standard
image files through a color-managed Core Image pipeline, store edits
without touching cataloged originals, and export full-resolution JPEG
or PNG files.

The project now covers the core review-and-develop loop of a desktop
photo editor. It is not yet feature-equivalent to the complete Adobe
Lightroom product; the largest remaining gaps are listed explicitly
under [Known gaps versus Lightroom](#known-gaps-versus-lightroom).

## Architecture

- **macOS-native**: Swift + SwiftUI App lifecycle, with AppKit interop
  (`NSOpenPanel`, `NSSavePanel`, `NSImage`) where appropriate.
- **No web tech**: no Electron, no Tauri, no WebView, no JS.
- **Frameworks used**:
  - SwiftUI for the UI shell, panels, toolbar, commands.
  - AppKit for native dialogs and image rendering bridges.
  - Core Image (`CIImage`, `CIRAWFilter`, `CIContext`) for RAW decoding,
    color-managed development, histograms, and full-resolution export.
  - Core Graphics and ColorSync profiles for output-profile conversion
    and tagged monitor-ready Soft Proof previews.
  - Vision for private, on-device foreground-subject selection,
    reviewable Assisted Culling signals, and People face suggestions.
  - MapKit and Core Location for the native map workspace, local place
    search, GPS display, and non-destructive coordinate assignment.
  - Image I/O (`CGImageSource`) for thumbnails and metadata.
  - Quick Look Thumbnailing (`QLThumbnailGenerator`) as final fallback.
  - UniformTypeIdentifiers for export type identification.
  - CryptoKit for stable disk-cache keys and streaming SHA-256 import
    verification.
  - SQLite3 for the persistent photo catalog.
  - Foundation, Combine, Swift Concurrency.
- **MVVM** with isolated services. Views never decode images or parse
  metadata directly.
- **Non-destructive state**: adjustments and named edit versions are
  mirrored in app-local JSON and a WAL-mode SQLite catalog, with
  optional sibling XMP sidecars for interchange; source image files
  are never rewritten.
- **Two-level cache**: bounded in-memory cache plus a persistent
  SHA-256-keyed JPEG thumbnail cache.
- **Deployment target**: macOS 14.

## Development controls

- RGB histogram with shadow and highlight clipping indicators.
- A Profile browser separate from presets, with Camera Default plus
  RAWDesk Color, Neutral, Vivid, Landscape, Portrait, Modern Cool,
  Cinematic Teal, Vintage Warm, Monochrome, and Monochrome Punch.
  Profiles are grouped as Foundation, Creative, and Black & White,
  expose a 0–200% Amount control, establish the rendering foundation
  before creative edits, and never rewrite the other slider values.
- Light: exposure, contrast, highlights, shadows, whites, blacks.
- Color: temperature, tint, vibrance, saturation.
- Direct five-point RGB tone curve with draggable black, shadow,
  midtone, highlight, and white points.
- Eight-channel HSL color mixer for red, orange, yellow, green, aqua,
  blue, purple, and magenta.
- Point Color with a direct on-photo eyedropper, up to eight persistent
  swatches, hue/saturation/luminance shifts, Variance, independent hue,
  saturation, and luminance ranges, and a preview-only Visualize Range
  mode that is never baked into export.
- Three-way color grading for shadows, midtones, and highlights, plus
  a global wheel, blending, and tonal balance.
- Calibration with Shadows Tint plus independent Hue and Saturation
  controls for the red, green, and blue primaries. It is applied before
  creative color edits and participates in persistence, versions,
  Undo/Redo, copy/paste, thumbnails, and export.
- Local masks: on-device automatic subject selection, automatic sky
  selection, click-targeted foreground-object selection, direct brush
  painting, radial gradients, and linear gradients. Sky selection
  prefers an embedded camera semantic matte and otherwise uses a
  conservative local estimate without uploading the photo. Each mask supports
  invert, exposure, contrast, highlights, shadows, whites, blacks,
  temperature, tint, hue, saturation, texture, clarity, dehaze,
  sharpness, noise reduction, and up to eight independent Point Color
  samples. Subject, Object, Sky, Brush, Radial, and Linear tools can be
  combined inside the same mask through up to 16 ordered Add, Subtract,
  and Intersect primary operations, each with enable/disable, inversion,
  reordering, and its own geometry or brush strokes. Masks can also be refined by persistent
  color ranges sampled directly from the photo and by luminance ranges
  with adjustable minimum, maximum, and feather. Files containing
  embedded depth or disparity can also use a near-to-far Depth Range
  with adjustable Near, Far, and Feather. Up to 16 additional ordered range
  operations per mask support Add, Subtract, Intersect, enable/disable,
  inversion, reordering, and a preview-only red mask overlay that is
  never included in export.
- Direct heal and clone repairs with movable source/target handles,
  radius, feather, and opacity controls.
- Optics: Apple RAW lens correction when the decoder supports the
  embedded/system profile, plus manual distortion, edge-vignette,
  red/cyan and blue/yellow registration, and edge-aware purple/green
  defringe controls. Auto CA Analysis scans a bounded color-managed
  preview for high-contrast radial edges, estimates per-photo lateral
  red/blue registration and purple/green fringing, stores its confidence
  and evidence count non-destructively, and leaves the manual controls
  available as additive fine tuning.
- Effects: texture, clarity, dehaze, vignette, and deterministic film
  grain with amount, size, and roughness.
- Detail: luminance sharpening with radius, detail, and edge masking;
  luminance noise reduction with detail and contrast; and
  luminance-preserving color-noise reduction with detail and
  smoothness.
- Crop and geometry: a direct on-photo crop overlay with rule-of-thirds
  guides, draggable corners and repositioning, common aspect-ratio
  presets, straighten, vertical/horizontal perspective, aspect, scale,
  X/Y offset, and an optional Constrain Crop auto-fill. Guided Upright
  accepts two to four draggable, aspect-correct architectural guides,
  infers horizontal/vertical intent, and solves level plus perspective
  from a stable pre-geometry full-frame preview into the same
  non-destructive geometry pipeline.
- Per-photo 90° rotation and horizontal/vertical flips, persisted and
  applied consistently to previews, thumbnails, versions, and export.
- Built-in Clean, Vivid, Portrait, Dramatic, and Matte presets.
- Before/after viewing, reset, coalesced Undo/Redo, and edit
  copy/paste.
- Selective multi-photo edit synchronization opened with **⇧⌘S**:
  choose any of 14 development sections with All, Modified, and None
  presets, or enable the clearly highlighted Auto Sync switch. Manual
  sync preserves every unchecked target section; Auto Sync propagates
  only the exact leaf control that changed, so adjusting Exposure does
  not overwrite another photo's Contrast, Color Mixer, Crop, masks, or
  other independent work.
- Color-managed Soft Proofing opened with **S** or the printer toolbar
  button: start with built-in sRGB, Display P3, Adobe RGB (1998), or
  Generic CMYK, then search installed ColorSync RGB/CMYK profiles or add
  an `.icc`/`.icm` file. Added profiles are validated, fingerprinted, and
  kept as a private stable copy. Perceptual and Relative Colorimetric
  intents are available. Destination-gamut warning is red, the current
  monitor-ICC warning is blue, and overlap is purple; all warning paint
  is display-only while the clean proof feeds the histogram and pointer
  RGB/Lab readout. Printer/output profiles also support Simulate Paper &
  Ink. Adjusted previews stay extended-linear and half-float through the
  output-profile conversion instead of being clipped to an 8-bit sRGB
  intermediate; RAW previews retain the same wide working boundary. A
  named Proof Version persists the edits, exact ICC profile, intent,
  both warnings, and paper/ink setting for later restore.
- A Lightroom-style Select/Candidate Compare workspace opened with
  **C**: keep one Select fixed while moving the Candidate through the
  compact auto-centering filtered filmstrip, swap or promote either
  image, synchronize zoom/pan, and apply flags or 0–5 ratings directly
  to each side.
- A Lightroom-style Survey workspace opened with **N**: tile two or
  more selected photos in a responsive mosaic, move the clearly marked
  Active photo with the arrow keys, add from the compact filmstrip,
  remove individual photos in place, and apply per-photo flags,
  0–5 ratings, or color labels without mutating the rest of the
  selection. Survey can move directly into Compare or finish with only
  the Active photo selected.
- A Lightroom-style Reference View opened with **⇧R**: keep one
  Reference photo static while the Active photo remains editable, swap
  the two roles, move Active through a role-marked auto-centering
  filmstrip, switch between left/right and top/bottom layouts, and lock
  the Reference across workspace changes. The toolbar reports
  whole-image Active-minus-Reference RGB histogram-center deltas, the
  Active side supports Before plus the normal repair, mask, and color
  sampling tools, and either preview reports the pointer's
  color-managed sRGB 0–255 and CIE Lab D65 values. The readout follows
  fit, zoom, pan, rotation, and flips; choosing Crop exits cleanly to
  the full Crop workspace.
- Named edit versions that can be restored or deleted.
- Full-resolution adjusted export with EXIF/GPS/IPTC/TIFF metadata
  retained where the destination format supports it. RAWDesk keyword
  hierarchy leaves are deduplicated into the standard IPTC Keywords
  field while unrelated embedded IPTC fields remain intact.

Edits also appear in grid thumbnails. Preview rendering is serialized
to keep rapid slider movements responsive instead of accumulating
stale work.

## Import workflow and duplicate safety

**⇧⌘I**, the toolbar, and the Library sidebar open a native modal Import
Photos panel. It accepts individual files, folders, or several sources
and performs a complete preflight before enabling Import:

- **Add** references supported photos where they already live, without
  copying or rewriting them.
- **Copy** places originals in a selected destination, carries a sibling
  `.xmp`, and then catalogs the verified destination. Copied photos can
  stay in one folder, use the built-in `YYYY/YYYY-MM-DD` organization,
  or render a safe nested folder template from capture date, camera,
  source folder, and sequence tokens. Names can stay original, use a
  filesystem-safe custom prefix plus a deterministic sequence, or use
  the same token renderer while preserving the original extension.
- **Copy + Trash** uses the same collision-safe, fully verified destination
  transfer, commits the destination to the catalog, rechecks the source,
  destination, and any sibling XMP, and only then moves the selected
  source pair to the macOS Trash. A failed safety check or Trash operation
  keeps the affected source and reports it explicitly; there is no
  permanent-delete fallback. A photo already cataloged at its selected
  source path is never sent to Trash by this workflow.
- Include Subfolders and Skip Exact Duplicates are explicit controls.
- New, exact duplicate, unsupported, and unavailable counts are shown
  before any catalog or destination change.
- Duplicate decisions use a streaming SHA-256 of the complete file, not
  filename, timestamp, or a partial sample. Existing catalog photos are
  hashed lazily only when their byte size makes them candidates; a
  cached hash is retained only while recorded file facts still match.

Copy and Copy + Trash use a hidden staging file in the destination folder,
verify its SHA-256 against the checked source, and only then perform the
final same-volume destination move. A different file with the same name is never
overwritten: `photo.jpg` becomes `photo 2.jpg`, and an orphan sidecar
also reserves its matching basename. An identical file already in the
destination can be reused safely. If companion copying or a
pre-catalog step fails, newly created files are rolled back, and any
newly created date folders are removed once empty. A file that blocks a
required folder name is reported and never replaced. Token templates
support `{original}`, `{camera}`, `{make}`, `{folder}`, `{sequence}`,
zero-padded sequence forms such as `{sequence:0000}`, and deterministic
`{date:...}` / `{time:...}` patterns. Live examples and validation keep
unknown tokens, absolute paths, empty or traversal components, excess
depth, path separators in filenames, and destination-escaping symlinks
from reaching the filesystem. The import
result lists imported, copied, moved, safety-retained, reused,
template-named, organized, skipped, unsupported, warning, and failure
counts, and successful items open as **Last Import**. An explicit,
default-off **Analyze people locally after import** option can then run
the on-device People analyzer only for the successfully imported photo
IDs. It reports analyzed, cached, face-suggestion, and unavailable
counts without assigning a name, uploading a crop, or modifying the
photo or XMP. A People-analysis failure is reported as a warning and
never rolls back an already verified import.
Expandable exact-duplicate groups retain the full SHA-256, selected
source, catalog/selection match, and Finder actions after the import
finishes, so skipped files remain directly reviewable.

### Watched-folder Auto Import

**File > Auto Import** and the sidebar expose a persistent, native
watched-folder workflow comparable to Lightroom Classic Auto Import.
The watched and destination folders must be separate and non-nested.
RAWDesk observes supported photos directly inside the watched folder;
subfolders, hidden files, standalone sidecars, and unsupported files
are ignored.

A filesystem event is only a prompt to enumerate again. Each photo and
its sibling XMP must keep the same size and modification time throughout
a configurable 0.5–30 second settling window before RAWDesk hashes
anything. Stable candidates then use the normal complete-SHA-256
preflight, collision-safe staging copy, destination verification, XMP
companionship, and atomic catalog transaction. Auto Import keeps the
watched-folder source by default. An explicit **Copy, Verify, then Trash
Source** setting may move the photo and verified sidecar to the macOS
Trash only after a successful source-to-catalog receipt. A changed,
failed, canceled, or exact-duplicate source stays in the watched folder;
exact duplicates produce a visible Needs Attention state.

Auto Import can organize by capture date or the same safe folder-token
templates, apply deterministic sequence or token-rendered filenames,
add normalized hierarchical keywords, and apply a built-in development
preset. A persistent, default-off **Analyze people locally** setting
runs the same targeted, on-device People analysis after verified ingest
and before any optional source cleanup. It creates review suggestions only; names still
require explicit confirmation. Its settings, next sequence number, and
security-scoped folder bookmarks persist in
`auto_import_settings.json`; monitoring resumes on relaunch. Import
activity never replaces the user's current edit view. The latest
successful batch is available explicitly as **Last Auto Import**.

## Catalog, keywords, and smart collections

Opening a folder or completing an import indexes referenced photos in a
persistent SQLite catalog. The catalog records roots, paths, file facts,
guarded whole-file and image-data hashes, searchable camera metadata,
exact RAWDesk state, and a normalized keyword index. WAL journaling and
atomic transactions keep normal writes recoverable; a catalog that fails
SQLite's integrity check is moved to a timestamped backup and recreated
instead of crashing the app.
Image I/O container metadata is read during the initial background scan,
so capture time, camera, lens, and exposure fields are available to
catalog-wide tools before any individual thumbnail is opened.

The sidebar provides one persistent Quick Collection, named regular
collections, nested collection sets, saved smart collections, and live
catalog views for All Photographs, Recently Added, Edited, Five Stars,
Picked, Rejected, With Keywords, Assisted Culling, Duplicates, and
Missing Files. Opening Duplicates examines every nonmissing photo and
hashes its decoded source raster, so the same exact image data is
grouped even when filename, EXIF, IPTC, XMP, color-profile metadata,
catalog edits, or container byte size differ. A file that Image I/O
cannot decode can still use the guarded complete-file SHA-256 fallback
when another catalog file has the same byte size. Cached signatures are
reused only while current size and modification facts match;
**Analyze Again** forces every candidate to be read again. Results
distinguish image-data and whole-file-fallback groups, show
deterministic Original/Duplicate badges, group and file counts,
additional-copy count, and the actual reviewable bytes without
automatically deleting anything. The context menu can reveal either
file in Finder or copy the matching image-data or full-file digest.

Quick Collection membership is stored once per catalog in stable append
order. Pressing **B** toggles the current photo or the whole
multi-selection; thumbnail context menus provide the same Add/Remove
action, the sidebar shows a live count, and member thumbnails carry a
compact **QUICK** badge. Missing members remain visible so they can be
relinked, and relinking transfers membership to the repaired catalog
photo. Removing a member, clearing Quick Collection, or deleting a
catalog record never deletes the source photo.

Regular collections persist explicit user order and let one photo
belong to multiple collections without copying or moving it. Photos can
be added or removed with sidebar and thumbnail menus, by dragging onto
a collection, or by pressing **B** when that collection is the target.
The collection view supports direct drag-before order plus
begin/up/down/end commands. One regular collection can replace Quick
Collection as the target without changing Quick membership.

Collection sets organize regular collections, smart collections, and
nested sets. Their hierarchy is cycle-checked and depth-guarded;
rename, move, recursive duplicate, and recursive delete operate only on
catalog organization. Quick Collection can be saved atomically as a
regular collection with optional clear-after-save. Missing members
remain available for relink, and relinking transfers regular
membership to the repaired catalog ID. Removing membership, deleting a
collection, or deleting a whole set subtree never deletes catalog
photos or source files.

Missing-file status is refreshed when a catalog collection is opened.
Any active combination of text search, format, minimum rating, keyword,
and color labels can be saved as a named smart collection; its
membership is re-evaluated against the current catalog rather than
stored as a fixed list. Smart collections can be placed in the same
nested set hierarchy.

Five stable Lightroom-compatible colors—Red, Yellow, Green, Blue, and
Purple—plus an explicit unlabeled state are persisted in the catalog
and compatibility JSON. **Metadata > Color Label Set** opens a native
preset editor that can create, duplicate, rename, activate, and delete
reusable sets with a distinct workflow name for every color. Assigning
a color captures the active name on each photo and writes that exact
value to `xmp:Label`; editing or switching a preset never silently
rewrites previously assigned photos or sidecars.

Labels can be assigned to one photo or a multi-selection from the
inspector, native **Photo** menu, or thumbnail context menu. A narrow
semantic-color strip keeps the color visible without tinting the
photograph itself. The sidebar, toolbar, menus, inspector, smart
collection suggestions, accessibility descriptions, and Assisted
Culling batch action all use the active set's names. Multiple label
colors, including Unlabeled, combine with every other filter and show
live catalog counts. Keys **6–9** assign Red through Blue; holding Shift
assigns the active name and advances to the next photo. Purple and None
remain available through the native controls.

Photos from the same source folder can be grouped into persistent
catalog stacks without moving or rewriting an image or XMP sidecar. The
active photo becomes the manual stack's top photo; saved stacks can be
expanded, collapsed, reordered, split, removed from, or completely
released through the native **Photo** menu and thumbnail context menu.
Collapsed state and member order survive relaunch, while relink and
catalog-removal workflows safely update or dissolve affected stacks.
**Photo > Auto Stack by Capture Time…** previews the result before
making any change. Its 0-second to 1-hour control groups contiguous
capture intervals independently inside each actual folder, uses every
unstacked photo in the current folder or collection rather than only
the selection, and reports photos excluded for existing membership,
missing capture times, or unavailable files. Acceptance creates every
previewed stack in one transaction; existing stacks are never silently
replaced.

The **Assisted Culling** collection analyzes supported catalog photos
locally through Apple image decoding and Vision. It records subject and
global focus, eye focus and eye-open state when faces permit it,
exposure clipping, likely misfires, document/receipt signals, and a
small visual fingerprint used only for suggested stacks. No photo is
uploaded, rewritten, moved, or automatically deleted. Select, Reject,
and Review decisions remain live as the user changes the enabled
criteria and thresholds. The grid shows the decision, review reason,
score summary, manual-override state, and suggested-stack number; the
header can filter each decision class immediately. Result counts and
actions stay ahead of an adaptive, persistently collapsible
**Criteria** section. Its controls expose subject and eye-focus
thresholds, detected-eye requirements, eyes-open and **Can't Tell**
handling, stack interval, and visual similarity. Stack controls
recompute suggestions immediately from the already-cached evidence,
without rerunning image analysis. Per-face disclosures show the
available eye-focus and eye-open scores and state. Entering Assisted
Culling also replaces the unrelated Edit inspector with a dedicated
**Culling Details** inspector: the selected result, explanation, manual
override controls, focus/exposure/misfire/document evidence, clipping
measurements, suggested visual group, and per-face evidence remain
reviewable beside the photo.

Computed culling evidence is cached only while the catalog's current
file size, modification date, and analysis-engine version still match.
**Analyze Again** bypasses the cache, while a changed or unavailable
file is excluded instead of trusting stale evidence. A context menu can
manually mark Select or Reject and return to the calculated result.
Optional batch actions atomically map Select/Reject results to
Pick/Rejected flags, Green/Red color labels, or star ratings, leave
Review photos unchanged, and explicitly report that neither images nor
XMP sidecars were modified.
Auto Stack is a reviewable suggestion based on capture time and local
visual similarity; it remains provisional until the user chooses
**Create Stacks**, which persists every still-valid suggestion
atomically and places the best culling-ranked photo on top.

Keywords can be added or removed from one photo or a multi-selection.
Entering `Places > Japan > Tokyo` creates a real hierarchy shown as an
expandable keyword tree; filtering a parent includes its descendants.
Whitespace is normalized and duplicate paths are folded case- and
diacritic-insensitively. Search covers every hierarchy segment plus
filename, note, camera make/model, and lens. Leaf names are exchanged
through the standard Dublin Core `dc:subject` RDF bag, while complete
paths round-trip through Lightroom's `lr:hierarchicalSubject`. External
keyword changes are preserved until the user explicitly edits them.

Every keyword-tree node has catalog-wide **Rename**, **Move or Merge**,
and **Delete Hierarchy** actions. Before committing, the management
panel previews the exact number of affected photos, assignments,
hierarchy paths, missing-file records, duplicate assignments that will
merge, and saved smart collections whose filters will follow the
change. Descendant paths are preserved, prefix matching stops at real
hierarchy boundaries, and moves into the source branch or beyond the
16-level limit are rejected. All affected photo states and smart
collection references change in one SQLite transaction; the JSON
compatibility mirror is rewritten once after success. These operations
never write image files or XMP sidecars.

The same context menu exposes per-keyword synonyms and export rules:
include/exclude the keyword, include its synonyms, and optionally
include containing hierarchy keywords. Definitions are case- and
diacritic-insensitive, persist in the catalog, and move, merge, or
delete atomically with their hierarchy. Conservative merge rules keep
an existing exclusion from becoming an accidental export. The resolved
flat values are written to IPTC Keywords during image export; assignment
paths and XMP sidecars remain unchanged.

Missing catalog photos expose **Locate Original…** and
**Remove from Catalog…** actions. Relinking validates that the selected
replacement is a supported image of the same format, migrates stable
identity when necessary, preserves edits and organization metadata,
and reconnects a sibling XMP at the new location. Removing a catalog
record never deletes or modifies an image file.

## Map, GPS, GPX, and saved locations

The toolbar and Library sidebar expose a native Map workspace that
plots the effective locations of catalog photos without rewriting
their source files. Embedded EXIF GPS is read on scan. A catalog-only
manual coordinate can override it, be removed to reveal the embedded
value again, or explicitly suppress the embedded value. The built-in
**With Location** and **Without Location** collections update
immediately.

The workspace supports Standard, Hybrid, and Satellite map styles,
local place search, fit-to-results, selected-photo focus, direct
click-to-assign, zoom and pan, a location-aware filmstrip, and a
dedicated inspector for exact coordinates, altitude, source, and
removal. Multiple photos can be assigned the same searched or clicked
coordinate in one operation.

GPX tracklogs can be previewed on the map and matched to photo capture
times with an explicit camera-time offset, maximum match gap,
selected/all-visible scope, interpolation, and replace-existing
control. The preview reports the exact photos that will change before
an atomic catalog update. Saved Locations persist a name, folder,
radius, visibility, and optional private flag; their folders remain
expandable in the sidebar and their visible radii are rendered on the
map.

Private Saved Locations affect export only. If a photo's effective
coordinate falls within a private radius, JPEG/PNG export strips GPS
and IPTC sublocation, city, state/province, and country fields while
leaving the catalog coordinate and original file untouched.

## People and private face organization

The toolbar and Library sidebar expose a native People workspace for
reviewing faces across the catalog. Face detection, capture-quality
measurement, and visual-similarity comparison run locally through
Vision; photos, crops, and feature data are never uploaded. A completed
zero-face analysis is cached against the photo's current file facts so
ordinary navigation does not repeatedly analyze the same image.

Automatic results are deliberately presented as **Suggested Matches**,
not identities. RAWDesk never applies or changes a person's name until
the user confirms it. Conservative, Balanced, and Broad grouping
sensitivities alter only the review suggestions. The inspector shows
the source photo, detection and capture-quality evidence, and every
face in the selected group.

A suggested group can be named as a new person or assigned to an
existing person. Named people can be renamed, merged, removed, searched,
and opened back at the exact source photo in Library. Individual faces
can be unassigned, marked **Not a Face**, or restored for review.
Reviewed assignments survive reanalysis when the same face overlaps the
previous detection and persist across a full app restart. All People
decisions stay in the schema-v12 catalog; source photos and sibling XMP
files remain untouched. Manual Import and watched-folder Auto Import
can optionally analyze only their newly imported photo IDs after the
safe transfer is complete. The control is off by default, the progress
is visible, and a completed zero-face result is cached just like a
People-workspace scan. The People header also offers a persistent,
default-off **Background People Analysis** switch. When enabled, RAWDesk
checks uncached or file-fact-changed catalog photos at launch, when the
app becomes active, and after the catalog grows. It uses the same
serialized local analyzer as Import, shows live progress, can be paused
without losing completed cache entries, and reports per-photo failures
inline for a later retry instead of interrupting the user with a modal.

## XMP sidecar interoperability

RAWDesk can read and write external sibling `.xmp` sidecars without
modifying the source image. It uses Adobe's standard XMP, Camera Raw,
Dublin Core, and RDF namespaces for compatible global development and
organization fields, including:

- exposure, contrast, highlights, shadows, whites, and blacks;
- white balance, temperature, tint, vibrance, and saturation;
- the tone curve, eight-channel HSL, color grading, calibration,
  effects, detail, optics, geometry, and crop;
- rating and three-state Pick status: Picked, Unflagged, or Rejected;
- the assigned active color-set name through `xmp:Label`, with canonical
  Red, Yellow, Green, Blue, and Purple as the default set;
- manual GPS latitude, longitude, altitude, and explicit location
  removal through standard EXIF GPS fields plus RAWDesk's exact private
  state;
- keyword leaves through `dc:subject` and complete Lightroom hierarchy
  paths through `lr:hierarchicalSubject`.

RAWDesk's complete edit graph—including profiles, masks, local Point
Color, repairs, and versions—is also stored in a private `rawdesk`
namespace so it can round-trip exactly between RAWDesk installations.
Externally changed keywords or color labels are preserved until the
user explicitly edits them in RAWDesk; copyright and properties from
namespaces RAWDesk does not understand are also preserved when the
sidecar is updated. An external custom label is matched
case/diacritic-insensitively against the active set. An unmatched name
is retained as reviewable metadata instead of being replaced with a
guessed color.

On folder scan, a sidecar is imported automatically only when the photo
has no app-local state. Once app-local state exists, it remains
authoritative until **Metadata > Read Metadata from XMP Sidecar** is
chosen. Explicit reads merge externally changed compatible fields
without erasing RAWDesk-only edits. **⌘S** writes each selected photo's
sidecar atomically; malformed existing XMP is reported and never overwritten.
RAWDesk deliberately uses an external sidecar even for DNG, JPEG, and
other formats so the original always remains untouched.

## Supported image formats

Standard:
- JPEG (`.jpg`, `.jpeg`)
- PNG (`.png`)
- HEIC (`.heic`)
- TIFF (`.tif`, `.tiff`)

RAW (extension is detected case-insensitively):
- **Sony ARW** *(first-class)*
- **Canon CR2** *(first-class)*
- Adobe DNG
- Canon CR3
- Nikon NEF
- Fuji RAF
- Panasonic RW2
- Olympus ORF

## RAW loading strategy

RAWDesk uses a **layered fallback pipeline** so that a single bad file
or unsupported sensor format never crashes the app:

1. `CIRAWFilter(imageURL:)` — Core Image's RAW pipeline. For thumbnails
   the loader sets `scaleFactor` so that the longest edge matches the
   requested pixel size, avoiding full-resolution decodes. Supported
   embedded or system lens correction is enabled here.
2. `CIImage(contentsOf:)` — generic Core Image fallback.
3. `CGImageSourceCreateThumbnailAtIndex` — extracts the embedded JPEG
   preview that virtually all ARW/CR2 files contain. This is the most
   reliable RAW path on stock macOS.
4. `QLThumbnailGenerator` — Quick Look Thumbnailing, with a 5-second
   safety timeout.
5. If all stages fail, the asset is marked `.unsupported` with a clear,
   non-fatal error UI.

For non-RAW formats the same fallback is used starting at the Image I/O
thumbnail layer. Development and export use an extended-linear working
space and an sRGB output color space.

## Sony ARW notes

- Detected by the `.arw` extension (case-insensitive).
- Routed through `CIRAWFilter` first; failures fall through to the
  embedded preview extracted via Image I/O — most ARW files embed a
  full-resolution JPEG which is what users typically see in viewers.
- `ARW` badge displayed on grid cells. `Sony ARW Only` filter available.

## Canon CR2 notes

- Detected by the `.cr2` extension (case-insensitive).
- Same layered pipeline as ARW. CR2 files reliably embed a JPEG
  preview that Image I/O can read even when full RAW demosaicing is not
  supported by the local OS.
- `CR2` badge displayed on grid cells. `Canon CR2 Only` filter available.

## Known RAW limitations

- macOS RAW support evolves with each OS release; very new sensor models
  may not decode through `CIRAWFilter`. RAWDesk falls back to the
  embedded preview but cannot demosaic unsupported sensors itself.
- Standard global Camera Raw fields can be exchanged through XMP, but
  Adobe local-mask/AI heavy-edit records, embedded DNG/JPEG metadata
  writes, and DCP/XMP profile import are not implemented. Temperature
  remains relative to the macOS decoder output, so identical numeric
  settings do not claim pixel-for-pixel Adobe rendering.
- Global development controls, tone curve, HSL mixer, Point Color,
  color grading, local masks, heal/clone, optics, geometry, and
  advanced manual detail controls are implemented. Learned RAW denoise,
  Raw Details, and Super Resolution are not.
- Canon CR2 decoding, editing, before/after viewing, persistence, and
  full-resolution export have been validated with real files. Sony ARW
  behavior remains dependent on the camera model supported by the
  installed macOS RAW stack.

## Import and source-safety model

- Folders can still be opened or imported with **Add** and referenced in
  place via `NSOpenPanel`.
- **Copy** creates verified destination files but never moves, renames,
  deletes, or rewrites the selected sources.
- Source disposition is limited to two explicitly selected workflows:
  manual **Copy + Trash** and Auto Import's optional **Copy, Verify, then
  Trash Source** setting.
- Manual **Copy + Trash** operates only on the selected import sources. It
  rejects unsafe destination relationships, copies through verified
  staging, commits the destination to the catalog, then re-verifies the
  complete source/destination photo and XMP hashes before moving the
  verified sources to the macOS Trash. A failed verification or Trash
  operation retains the source photo and destination and reports a
  warning. It never falls back to permanent deletion.
- **Auto Import** operates only on the selected watched folder and
  retains source photos by default. Optional Trash disposition uses the
  same verified path as manual import and runs only after destination
  verification and catalog persistence. Failed, changed, canceled,
  unsupported, and exact-duplicate sources remain in place.
- Recent folders are remembered (with security-scoped bookmarks where
  available) under Application Support.
- Opened, added, and manually copied source image files are **never**
  modified, moved, renamed, deleted, or rewritten. Manually moved
  sources are removed only through the explicit verified workflow above.
- Optional sibling `.xmp` files are the only external metadata RAWDesk
  writes beside an opened/added source. Import copying only duplicates
  an existing sidecar; it never edits that source sidecar. Metadata
  saving is always explicit, and malformed existing sidecars are left
  unchanged.

The app persists app-local user state — rating, Pick/Reject status,
favorite, color label, keywords, note, global and local adjustments,
and named versions — at:

```
~/Library/Application Support/RAWDesk/catalog.sqlite
~/Library/Application Support/RAWDesk/user_state.json
~/Library/Application Support/RAWDesk/recent_folders.json
~/Library/Application Support/RAWDesk/auto_import_settings.json
~/Library/Caches/RAWDesk/Thumbnails/
```

The SQLite catalog is the cross-folder library and can restore exact
per-photo state when the compatibility JSON mirror lacks an entry.
Corrupted JSON or SQLite data is detected and replaced with a
timestamped backup; the app continues instead of crashing. A stable
file resource identifier is preferred over a path-based identifier, so
edits survive ordinary in-place renames on supported volumes.

## Keyboard shortcuts

| Action            | Shortcut          |
|-------------------|-------------------|
| Import Photos…    | ⇧⌘I               |
| Open Folder       | ⌘O                |
| Save XMP Sidecar  | ⌘S                |
| Export…           | ⌘E                |
| Zoom In           | ⌘=                |
| Zoom Out          | ⌘−                |
| Fit to Window     | ⌘0                |
| Actual Size       | ⌘1                |
| Compare Photos    | C                 |
| Survey Photos     | N                 |
| Reference View    | ⇧R                |
| Soft Proofing     | S                 |
| Rotate Right      | ⌘]                |
| Rotate Left       | ⌘[                |
| Toggle Flag       | F                 |
| Pick / Unflag / Reject | P / U / X     |
| Set Rating 0–5    | 0 1 2 3 4 5       |
| Red / Yellow / Green / Blue label | 6 / 7 / 8 / 9 |
| Label and advance | ⇧6 / ⇧7 / ⇧8 / ⇧9 |
| Next / Previous   | → / ←             |
| Focus Search      | ⌘F                |
| Show Original     | \                  |
| Undo / Redo Edit  | ⌘Z / ⇧⌘Z          |
| Copy Edit Settings | ⇧⌘C              |
| Paste Edit Settings | ⇧⌘V             |
| Synchronize Edit Settings | ⇧⌘S       |

## Build & run

Requires Xcode 15+ / Swift 5.9+, macOS 14+.

### Quick: SwiftPM only

```sh
swift build
swift test
swift run RAWDesk
```

### Xcode (recommended for development)

A native Xcode project is generated from [`project.yml`](project.yml)
via [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen      # one-time
xcodegen generate
open RAWDesk.xcodeproj
```

The `RAWDesk` scheme is set up with:

- a real macOS **app target** (proper Info.plist, icon, ad-hoc signing)
- the `RAWDeskTests` unit-test target wired up via `TEST_HOST`
- ⌘R to run, ⌘U to test, ⌘B to build — all standard Xcode shortcuts

`xcodegen` rewrites the `.xcodeproj` from `project.yml`, so re-run
`xcodegen generate` after adding new source files. Source file
membership is folder-based (`Sources/RAWDesk`) — no manual editing of
the project required.

### Real .app bundle (without Xcode)

The above runs the binary directly, but it does not appear in the Dock
as a proper macOS application. To produce a real `.app` bundle (with
`Info.plist`, app icon, ad-hoc codesigning, and Launch Services
registration), run:

```sh
./scripts/build-app.sh
open build/RAWDesk.app
```

Drag `build/RAWDesk.app` into `/Applications` if you want it permanently
installed. Re-run the script after any source change to refresh the
binary inside the bundle.

For UI QA that must not change the normal RAWDesk catalog or app
preferences, launch a QA-only bundle copy:

```sh
./scripts/run-isolated-ui-qa.sh --reset
```

Relaunch without `--reset` to verify persistence, then remove only the
QA bundle, data, and preference domain:

```sh
./scripts/run-isolated-ui-qa.sh
./scripts/run-isolated-ui-qa.sh --cleanup
```

## Manual QA checklist

1. Build the Release app with `./scripts/build-app.sh`, then launch
   `build/RAWDesk.app`.
2. Open a mixed image folder with **⌘O** and confirm JPEG, PNG, HEIC,
   TIFF, and supported RAW thumbnails render.
3. Confirm ARW and CR2 files show the correct format badge and a corrupt
   file produces a non-fatal error placeholder.
4. Select an EXIF-bearing photo and confirm file, camera, exposure, and
   dimension metadata populate; missing fields should show `—`.
5. Browse all Foundation, Creative, and Black & White profiles. Change
   Profile Amount from 0% through 200%, verify the other sliders do not
   move, apply a preset on top, then quit and reopen to confirm the
   profile, Amount, and preset values coexist and persist.
6. Move each Light and Color slider and confirm the preview, histogram,
   clipping percentages, edited badge, and thumbnail all update.
7. Drag every point on the Tone Curve, then adjust hue, saturation, and
   luminance on several Color Mixer channels; verify Reset and Undo.
8. Open Point Color, sample several colors directly from the photo,
   change Hue/Saturation/Luminance Shift and Variance, refine all three
   Range controls, and toggle Visualize Range. Quit and reopen to verify
   the swatches and settings persist; confirm Visualize Range itself
   stays off and is not included in an export.
9. Grade shadows, midtones, highlights, and global color separately;
   exercise Blending and Balance, then reset one wheel and the entire
   grade. Open Calibration, test Shadows Tint and Hue/Saturation for
   each RGB primary, verify broad color-family targeting, then reset it.
10. Create subject and sky masks, use Select Object and click one
   foreground object, invert it, paint a brush mask, and add radial and
   linear gradients. Exercise every Light, Color, Effects, and Detail
   control and verify each affects only the selected area. Inside one
   mask, combine Subject, Object, Sky, Brush, Radial, and Linear tools
   with Add, Subtract, and Intersect; disable, invert, and reorder them,
   and paint directly into a Brush operation. Sample a local Point Color
   and confirm its shifts remain inside the combined mask. Add Color
   Range, Luminance Range, and—on a file with auxiliary depth—Depth
   Range operations using Add, Subtract, and Intersect; adjust every
   range control, invert/disable/reorder operations, and inspect the red
   mask overlay. Confirm a file without auxiliary depth shows a
   non-destructive explanation instead of adding a false depth map.
   Quit and reopen to verify masks and operations persist while the
   overlay stays off.
11. Add Heal and Clone repairs, move both handles on the photo, and
   verify radius, feather, opacity, Undo, and deletion.
12. Apply manual distortion, vignette, channel registration, and
    purple/green defringe. Confirm RAW files show the built-in lens
    correction status message.
13. Apply each preset, then use **⌘Z** and **⇧⌘Z** to confirm Undo and
    Redo restore the exact previous render.
14. Press `\` to show the original, then press it again to return to the
    edit.
15. Open **Edit Crop on Photo**, resize all four corners, move the crop
    rectangle, and click Done. Then apply 1:1, 4:3, 3:2, and 16:9
    presets, change Straighten and perspective, toggle Constrain Crop,
    and reset Crop & Geometry. Open **Draw Guides on Photo**, draw two
    to four lines along architectural edges, drag their endpoints,
    correct an inferred Horizontal/Vertical label if needed, delete one
    guide, and confirm level/perspective update and survive relaunch.
16. Exercise Texture and Grain Amount/Size/Roughness at 100% zoom;
    verify Grain stays stable between renders and subordinate controls
    disable at Amount 0.
17. Rotate and flip a photo, quit and reopen the folder, and confirm its
    orientation persists in both the preview and thumbnail.
18. Save a named version, make another edit, restore the version, and
    delete it.
19. Copy edit settings with **⇧⌘C**, select one or more other photos,
    paste with **⇧⌘V**, and verify all selected photos update.
20. Command-click and Shift-click thumbnails, then bulk-apply rating,
    Pick/Reject status, favorite, each color label, preset, and pasted
    edit settings. Verify the narrow label strip does not tint the
    photograph, and exercise **6–9** plus **⇧6–⇧9** advance behavior.
21. Search by filename, keyword, camera, lens, and note; exercise every
    filter, minimum rating, every single/multiple color-label filter
    including Unlabeled, sort field, sort direction, and thumbnail-size
    control.
22. Add flat and hierarchical keywords to one photo and a
    multi-selection using paths such as `Places > Japan > Tokyo`.
    Confirm chips use readable breadcrumbs, the sidebar expands through
    every hierarchy level, parent filtering includes descendants,
    case/diacritic-insensitive matching works, and With Keywords updates
    immediately. Right-click a parent node and exercise Rename, Move or
    Merge, and Delete Hierarchy. Confirm the impact preview includes
    descendants and missing-file records, duplicate destinations merge,
    saved smart collections follow the new path, and neither the image
    nor sibling XMP changes. Add synonyms and exercise all three export
    flags, then export a JPEG and verify the resolved, deduplicated IPTC
    keyword list while unrelated IPTC fields remain intact.
23. Combine search, format, minimum-rating, keyword, and multiple
    color-label filters, save them as a named smart collection, then
    quit and relaunch. Confirm the collection and its live result
    return; remove a matching keyword or label and confirm that photo
    leaves the collection.
24. Exercise All Photographs, Recently Added, Edited, Five Stars,
    Picked, Rejected, With Keywords, and Missing Files across at least
    two folders. Move only a disposable copy, refresh Missing Files,
    use **Locate Original…** to reconnect it at the new location, and
    relaunch to verify its edits and hierarchy remain. Move the copy
    once more and test **Remove from Catalog…**; confirm the image file
    itself remains untouched.
25. Import a disposable original A, a renamed B with the same JPEG image
    data but different embedded metadata, byte size, and whole-file
    SHA-256, plus a C with different pixels while **Skip Exact
    Duplicates** is off. Open **Duplicates** and confirm only A/B appear
    as one **ORIGINAL/DUPLICATE** group, with two files, one additional
    copy, one image-data group, zero fallback groups, and the actual
    reviewable-byte count for the non-anchor member. Click **Analyze
    Again**, copy the Image Data SHA-256 from each context menu, and
    confirm those match even though the complete source SHA-256 values
    do not. Confirm C is excluded, no file is deleted, and all three
    source hashes remain unchanged.
26. In a disposable catalog, import a sharp near-identical pair, a
    clipped/blank frame, and a document-like image. Open
    **Assisted Culling** and confirm Select/Reject/Review badges,
    review reasons, score details, and a suggested stack. Exercise all
    four review filters, change enabled criteria and focus thresholds,
    expand/collapse the adaptive Criteria panel, exercise the
    detected-eye and Can't Tell options, and confirm that changing the
    stack interval/similarity controls updates suggestions without an
    analysis pass. Confirm the right inspector changes from Edit to
    Culling Details and inspect its result, score bars, local-analysis
    note, and per-face evidence where available,
    manually override one result and return it to the calculated
    result, then apply flag, Green/Red color-label, and rating mappings.
    Click
    **Analyze Again**, leave and reopen the collection to exercise the
    guarded cache, and confirm every source digest and sibling-XMP
    state is unchanged.
27. In a disposable same-folder sequence, manually group two photos
    and verify the active photo is on top. Exercise the count button,
    move, split, remove, unstack, expand/collapse-all, and relaunch
    persistence. Then release every stack, choose **Photo > Auto Stack
    by Capture Time…**, and verify the live result at 0 seconds, an exact
    boundary, and 1 hour. Confirm the dialog ignores the thumbnail
    selection, reports existing/missing-time/unavailable exclusions,
    never crosses a real folder boundary, and creates only the
    previewed stacks after the default action. Recheck source digests
    and sibling-XMP absence.
28. Open **Metadata > Color Label Set**, create a preset with custom
    names, save and activate it, then assign a custom-named color to a
    multi-selection. Confirm the inspector, menus, sidebar, toolbar,
    smart-collection suggestion, and Culling batch action use the new
    names while thumbnail strips retain the correct colors. Quit and
    reopen, confirm the active preset and assigned metadata names
    persist, save XMP, and verify its exact `xmp:Label` value. Rename
    the preset and confirm existing photos and sidecars are not silently
    rewritten; clear one label explicitly and confirm its value is
    removed.
29. Set rating, Pick/Reject status, favorite, color label, keywords,
    note, edits, and a version; quit and reopen the folder; confirm each
    value persists.
30. Place a valid Adobe-namespaced `.xmp` beside a photo with no
    app-local state. Open the folder and verify compatible fields import
    once. Change one control and a keyword, save with **⌘S**, and confirm
    existing custom properties remain. Relaunch to confirm app-local
    state wins, then change only one standard XMP field externally and
    use **Read XMP** to verify only that field is merged. Repeat with an
    external `dc:subject`, `lr:hierarchicalSubject`, or `xmp:Label`
    change and verify RAWDesk preserves it unless the user explicitly
    edits the corresponding field. Repeat with an unknown custom XMP
    label name and confirm it is retained without guessing a color.
31. Rename an edited file in place, rescan, and confirm its app-local
    state follows the file where stable resource identifiers are
    available.
32. Export an edited RAW as JPEG and PNG. Confirm output pixel
    dimensions reflect the full-resolution source and crop rather than
    the preview size, orientation is normalized, and metadata remains.
33. Confirm the original files retain their byte sizes and contents
    with Finder Info or `shasum`.
34. Quit and reopen; confirm warmed thumbnails load from the disk cache.
35. Open **Import Photos…** with **⇧⌘I**. Select a folder containing one
    new supported photo, a byte-identical copy with a different name,
    an unsupported file, and a sibling XMP. Confirm the preflight counts
    each class correctly. Test Add, then test Copy into a destination
    already containing a different file with the same name. Confirm the
    copied photo receives a collision-safe name, its XMP follows it, the
    result reports the skipped duplicate, source SHA-256 values stay
    unchanged, and the successful photos appear under Last Import.
    Repeat with **By Capture Date** and **Custom Name + Sequence**;
    confirm the `YYYY/YYYY-MM-DD` path, sanitized name, sequence start,
    catalog root, and XMP basename are correct.
    Turn on **Analyze people locally after import** for a disposable
    portrait. Confirm progress begins only after the safe import,
    People reports the imported photo as analyzed and exposes a
    suggestion without a name, and the source photo/XMP hashes stay
    unchanged. Repeat with a no-face photo and confirm the cached
    zero-face result is reported without treating the import as failed.
    Expand **Review Exact Duplicate Groups**, confirm both paths and
    the full SHA-256 remain available after completion, and reveal each
    side safely in Finder.
36. Open **File > Auto Import > Auto Import Settings…**. Choose an empty
    watched folder and a separate destination, enable **By Capture
    Date**, **Custom Name + Sequence**, a development preset, and two
    keywords. Enable Auto Import, then copy a valid photo and sibling
    XMP into the watched folder. Confirm the sidebar first reports that
    the write is settling, then that the verified import completed.
    Repeat with **Analyze people locally** enabled and a disposable
    portrait; confirm a local suggestion is created only for that
    imported photo and Named remains zero.
    Confirm the source pair disappears only after matching destination
    SHA-256 values exist, the catalog has the XMP rating plus configured
    keywords/preset, and Last Auto Import opens without interrupting the
    current view automatically. Drop a byte-identical renamed copy and
    confirm it remains in the watched folder with Needs Attention.
    Quit/relaunch, add a different photo, and verify monitoring resumes
    with the next sequence number.
37. Open a disposable four-photo folder containing one embedded-GPS
    photo, two timestamped photos without GPS, one later untagged
    photo, and a matching GPX tracklog. Confirm **With Location** starts
    at one and **Without Location** at three. Open Map, import the GPX,
    preview all visible photos, and verify exactly two timestamp
    matches before applying. Confirm the resulting three pins, route,
    counts, and inspector values. Save a visible 5 km private location
    in a named folder, quit/relaunch, and verify its folder, radius,
    lock, GPX route, and all locations persist. Export a photo inside
    the radius and verify GPS plus IPTC sublocation/city/state/country
    are absent while the catalog coordinate remains.
38. Open a disposable three-photo folder containing two copies of the
    same portrait and one no-face image. Enter People and confirm the
    local scan produces one **Suggested Match** with two faces across
    two photos while Named remains zero. Name the group, open one face
    back in Library, then use **Analyze Again** and confirm the name and
    both assignments survive. Quit the app fully and relaunch before
    opening People; confirm the sidebar already reports one person and
    the named two-face group returns. Exercise rename, assignment to an
    existing person, merge, unassign, **Not a Face**, and restore on
    disposable records. Confirm all source SHA-256 values are unchanged
    and no XMP is created.
39. Open Import with a disposable JPEG and sibling XMP, select
    **Copy + Trash**, and choose a separate destination containing a different
    file at the rendered destination name. Choose **Custom Template**
    with `{date:yyyy}/{camera}` and **Token Template** with
    `{date:yyyyMMdd}-{original}-{sequence:000}`, starting at 7. Confirm
    both live examples and the safety explanation remain visible before
    committing. Run the import and verify the existing collision is
    unchanged, the result reports one copied/verified original moved to Trash,
    template-named photo, and organized folder, the source photo/XMP
    pair is absent, the collision-safe destination photo/XMP pair has
    the original complete SHA-256 values, and Last Import catalogs that
    destination. Fully quit/relaunch and confirm the catalog entry is
    present and not missing.
40. Open **Auto Import Settings…**, leave **Copy and Keep Source** selected,
    select **Custom Template** and
    **Token Template**, and confirm token insertion, live examples,
    shared sequence control, validation, and disabled saving for an
    unsafe or unknown token. Save valid templates in a disposable
    watched-folder setup, ingest a photo/XMP pair, and verify the rendered
    destination, retained source pair, advanced next sequence, and restart
    persistence. With a second disposable pair, explicitly select **Copy,
    Verify, then Trash Source** and verify the source pair is sent to the
    macOS Trash only after import and catalog registration complete.
41. In People, turn on **Background People Analysis**, return to
    Library, and add one cached photo plus one new disposable portrait.
    Confirm the background progress appears without changing workspace,
    only the new photo is analyzed, Named remains zero, and the portrait
    becomes reviewable in People. Pause an in-progress disposable scan
    and confirm it stops without removing completed results. Quit and
    relaunch with the setting on, confirm it resumes automatically and
    reuses the guarded cache, then turn it off and verify the off state
    survives another relaunch.
42. In Library with at least three visible photos, select one and press
    **C**. Confirm the Select and Candidate panes, blue/orange filmstrip
    roles, active Candidate selection, compact horizontal layout, and
    automatic Candidate centering. Use the arrow keys and
    Candidate previous/next controls; confirm navigation wraps and
    never duplicates the fixed Select. Pan or zoom one pane with
    **Sync Zoom** on, then turn it off and confirm the panes can be
    inspected independently. Exercise Fit and 1:1, Swap, and
    **Make Select**. Apply Pick, Unflag, Reject, and 0–5 ratings on each
    side and confirm only that photo changes. Click a third thumbnail
    to make it the Candidate. Reduce the active filter to one visible
    photo and confirm Compare exits cleanly, then clear the filter and
    press **C** or **Done Comparing** to leave Compare explicitly.
43. Select at least three visible photos—or use **⌘A** to select all
    visible photos—and press **N**. Confirm the responsive Survey
    mosaic, blue Active-photo border, compact
    filmstrip roles, and automatic Active-photo centering. Use the
    arrow keys and Previous/Next buttons to wrap through only the
    surveyed photos. Click an unselected filmstrip thumbnail to add it
    and make it Active, then remove individual tiles with **×**. Apply
    Pick, Unflag, Reject, 0–5 ratings, and color labels from different
    tiles and confirm each action changes only that photo. Switch
    directly to Compare and back to Survey, exercise **Keep Active**,
    and reduce the filter below two surveyed photos to confirm Survey
    exits cleanly while preserving a valid selection.
44. Select two photos and press **⇧R**. Confirm the teal static
    Reference and orange editable Active panes, compact role-marked
    filmstrip, RGB **Tone Δ**, and Active-photo position. Use the arrow
    keys to wrap while skipping the Reference, click the Reference
    thumbnail to swap roles, toggle Active Before with `\`, and edit
    Active from the inspector. Move the pointer across both photos and
    confirm the sRGB and Lab readout appears only over image content;
    repeat after 1:1 zoom, pan, rotation, and a flip. Switch between
    left/right and top/bottom, lock the Reference, leave and reopen
    Reference View, and confirm the same Reference returns even when
    filtered out. Start Crop and confirm Reference View exits while the
    Crop overlay remains active.
45. In the Library grid select three photos, making the intended source
    the active photo. Press **⇧⌘S**, choose **None**, enable only
    **Light**, and synchronize. Confirm Exposure/Contrast copy to both
    targets while their Color, Crop, masks, and ratings remain intact.
    Reopen the sheet and verify **Modified** selects only non-default
    source sections. Enable **Auto Sync**, change only Exposure, and
    confirm the exact value reaches all three photos without replacing
    their different Contrast values. Undo on one target to confirm its
    own history, then collapse selection to one photo and confirm Auto
    Sync switches off.
46. Press **S** or the printer toolbar button and confirm the white
    proof background, active **PROOF** badge, and inspector proof card.
    Open the anchored profile browser, search installed ColorSync
    profiles, select an installed printer profile, then add an
    `.icc`/`.icm` profile and confirm the private copy remains usable
    after its source file moves. While the search field is active, type
    `s` and confirm it enters text instead of toggling proofing. Exercise
    Perceptual and Relative intent and confirm the clean histogram and
    pointer RGB/Lab values never include warning paint. Enable
    Destination Gamut Warning for red, Monitor Gamut Warning for blue,
    and both for purple overlap. Move the window between monitors and
    confirm the displayed monitor name and warning result refresh. For
    a printer/output profile, toggle Simulate Paper & Ink; confirm it is
    unavailable for non-output RGB profiles. Save a named Proof Version,
    change its profile and edits, select the saved version, and confirm
    adjustments plus ICC, intent, both warnings, and paper/ink state
    return after relaunch. Repeat while Reference View is active and
    while Auto Sync edits the Active photo.
47. Open three disposable photos, press **B** on the first, and confirm
    the Quick Collection count and **QUICK** thumbnail badge appear.
    Multi-select the other two and use the context menu to add them.
    Open Quick Collection, remove its active photo with **B**, relaunch,
    and confirm the remaining order and membership persist. Clear Quick
    Collection from its sidebar context menu and confirm all three source
    files and catalog photos still exist.
48. Create a collection set, a nested child set, and a regular
    collection containing the active photo. Confirm the hierarchy,
    count, **COLLECTION** badge, and `Collection Order · User` view.
    Add a second photo, reorder the two members by drag and context
    commands, and confirm the order survives relaunch. Set the regular
    collection as the target, press **B** on a different photo, and
    confirm only the target grows while Quick Collection is unchanged.
    Save Quick Collection as another regular collection with
    clear-after-save enabled. Relaunch and verify both collections,
    their parent sets, counts, order, and target remain. Delete the
    copied collection and then its parent set; confirm every catalog
    photo and source file still exists.

## Current verification

- `swift test`: 289 tests, 0 failures. The final run is recorded at
  `/tmp/RAWDesk-RegularCollections-FullSwiftTests-20260726-192548.log`.
- SwiftPM and native Xcode Debug builds pass. The shared Xcode Test
  action now uses a fixed disposable Application Support boundary and
  does not inherit Run-action arguments. Direct SwiftPM tests also
  detect their test host and use a per-process temporary support
  directory. The final isolated Xcode-hosted run passed all 289 tests
  on arm64 macOS. Its log is
  `/tmp/RAWDesk-RegularCollections-FullNativeTests-20260726-192820.log`
  and its
  result bundle is
  `/tmp/RAWDesk-RegularCollections-FullNativeTests-20260726-192820.xcresult`.
  Both final suites left the normal catalog database, WAL, and SHM
  bytes and timestamps unchanged; the before/after manifests are
  `/tmp/RAWDesk-RegularCollections-NormalCatalog-BeforeSwift-20260726-192548.txt`,
  `/tmp/RAWDesk-RegularCollections-NormalCatalog-AfterSwift-20260726-192745.txt`,
  `/tmp/RAWDesk-RegularCollections-NormalCatalog-BeforeNative-20260726-192820.txt`,
  and
  `/tmp/RAWDesk-RegularCollections-NormalCatalog-AfterNative-20260726-192906.txt`.
- Compare has seven pure transition-planner tests plus an integration
  test covering start, Candidate selection, Candidate-only rating,
  swap, and graceful filtered-list reconciliation. Two storage-boundary
  tests cover both SwiftPM and Xcode test-host detection.
- Survey has six transition-planner tests, two responsive-layout tests,
  and an integration test covering **⌘A** visible-photo selection,
  Active/photo ordering, per-photo metadata isolation, filmstrip
  addition/removal, Compare switching, and filtered-list reconciliation.
- Reference View has six pure transition-planner tests, two RGB
  histogram-delta tests, and an isolated library integration test
  covering initial roles, Active-only metadata editing, layout, role
  navigation, locked-reference reuse, and direct Compare/Reference
  switching. Two color-conversion tests and four viewport-mapping tests
  cover the per-cursor sRGB/Lab readout, including letterboxing, 90°
  rotation, flips, zoom, and pan.
- Selective Sync and Auto Sync have three pure planner tests plus an
  isolated three-photo library integration test. They cover
  All/Modified-style panel selection, leaf-level delta propagation,
  preservation of target-specific settings, target Undo, and safe
  switch-off when multi-selection ends.
- Soft Proofing has twelve focused processor/viewer/catalog tests
  covering legacy settings, installed ICC discovery, validated private
  import and fingerprint protection, disposable support-directory
  resolution, profile and paper/ink eligibility,
  CMYK conversion and orientation, independent red/blue/purple warning
  paint, in-gamut monitor behavior, clean histogram/sampling input,
  adjusted wide-gamut handoff, half-float RAW preview preservation,
  missing-profile fallback, and safe enable/disable. The user-state
  round-trip also covers complete named Proof Version persistence.
- Quick Collection has a catalog-store integration test and a
  library-view-model integration test covering migration through
  schema v12,
  stable append order, multi-selection toggle semantics, missing-photo
  retention, relink transfer, catalog-removal cleanup, restart
  persistence, clear, and source-byte invariance.
  Regular-collection integration coverage adds nested and recursively
  duplicated sets, regular and smart collection nesting, cycle/depth
  rejection, explicit target selection, B-key routing, stable user
  order, drag-equivalent membership moves, Quick-to-regular conversion,
  relink transfer, non-destructive recursive deletion, restart
  persistence, and SQLite integrity.
- The latest universal x86_64/arm64 Release `.app` builds, passes
  strict deep ad-hoc signature verification and its Designated
  Requirement, and has a valid `Info.plist`.
- The accepted Release build, containing Reference View,
  Selective Sync/Auto Sync, installed/imported ICC Soft Proofing,
  independent destination/monitor gamut warnings, and metadata-insensitive
  exact image-data duplicate review plus Quick, regular, smart, and
  nested-set collection organization,
  was produced from a fresh DerivedData directory at
  `/tmp/RAWDesk-RegularCollections-UniversalReleaseDerived-20260726-192906`.
  Its executable contains both `x86_64` and `arm64`, satisfies its
  Designated Requirement, and has SHA-256
  `0fb5e28b445c2bd418a554b05cc89f0a6484f59d7d61a508b05e5f4266b2c82a`.
  Build output is in
  `/tmp/RAWDesk-RegularCollections-UniversalReleaseBuild-20260726-192906.log`;
  signature, requirement, bundle, version, architecture, and hash
  verification is recorded at
  `/tmp/RAWDesk-RegularCollections-UniversalReleaseVerification-20260726-192906.txt`.
  The exact product passed isolated Release UI and restart QA, then
  replaced `build/RAWDesk.app`; the accepted executable is byte-identical
  to the candidate and its matching dSYM contains the same x86_64 and
  arm64 UUIDs.
- Disposable Survey Release UI, **⌘A** selection, tiled-layout,
  catalog, source-integrity, screenshot, and artifact evidence is
  documented in `Evidence/2026-07-26/survey/README.md`.
- Disposable Compare UI, transition, metadata-isolation, catalog,
  source-integrity, and screenshot evidence is documented in
  `Evidence/2026-07-26/compare/README.md`.
- Selective Sync/Auto Sync behavior, tests, isolation, and staged
  Universal Release evidence is documented in
  `Evidence/2026-07-26/sync/README.md`.
- Soft Proofing behavior, wide-gamut boundary, tests, isolation, named
  Proof Version persistence, and its verified Release checkpoint are
  documented in `Evidence/2026-07-26/soft-proof/README.md`.
- Exact image-data duplicate behavior, real metadata-only JPEG
  regression coverage, catalog isolation, and its Release checkpoint
  are documented in
  `Evidence/2026-07-26/image-data-duplicates/README.md`.
- Quick Collection behavior, migration/relink/removal coverage, and its
  earlier automated checkpoint are documented in
  `Evidence/2026-07-26/quick-collection/README.md`.
- The completed isolated Release pass for Soft Proofing, exact
  image-data duplicates, Quick Collection, named regular collections,
  nested sets, target-B routing, user order, Quick conversion, and
  restart persistence is documented in
  `Evidence/2026-07-26/regular-collections/README.md`.
- Disposable UI, catalog, file-integrity, and screenshot evidence for
  background analysis is documented in
  `Evidence/2026-07-26/people-background/README.md`. Historical Move,
  token-template, XMP, collision, and targeted Import People evidence
  is documented in
  `Evidence/2026-07-26/import-templates-move/README.md`.
- A real Canon `IMG_0055.CR2` was developed and exported as a
  2912 × 4368 JPEG while preserving the source pixel count, portrait
  orientation, and camera metadata.
- The same real file was used to verify histogram updates, original/edit
  comparison, direct tone-curve dragging, HSL channel controls, 1:1
  crop, direct crop-resize/reposition/commit, Undo/Redo, version
  save/delete, persisted rotation/flip, advanced Detail, optics,
  color grading, grain, constrained perspective, restart persistence,
  and full reset. The same file now also verifies direct Point Color
  sampling (including corrected top-to-bottom preview coordinates),
  all four Point Color adjustments, all three range controls,
  Visualize Range, restart persistence, and cleanup back to Original.
- Automated pixel tests verify color-range and luminance-range
  targeting, Add expansion, Subtract removal, Intersect restriction,
  ordered graph composition, legacy-state decoding, and that the mask
  overlay is an explicit preview-only render mode. They also verify
  click-label coordinate handling and that local Hue stays confined to
  the raster mask. A real Canon RAW smoke test exercises all expanded
  local Light, Color, Effects, and Detail controls together.
- Primary-tool graph tests verify ordered Add, Subtract, and Intersect
  composition across raster tools, operation normalization and legacy
  decoding. A separate pixel test verifies Point Color is now evaluated
  inside the combined local mask rather than globally.
- The Release UI on `IMG_0055.CR2` created a Radial mask, added
  Subtract Linear and Add Radial primary operations, reordered Add
  ahead of Subtract, sampled a local Aqua Point Color, and changed its
  Hue Shift to +2. Quit/relaunch restored the operation order, local
  swatch, and value exactly; Reset All followed by another relaunch
  returned to Original with Reset All disabled.
- Calibration model and pixel tests verify value clamping,
  persistence, edit counting, RGB-primary targeting, and
  shadow-weighted tint behavior.
- Profile model and pixel tests verify 0–200% Amount clamping,
  legacy-state defaults, JSON round trips, pixel-neutral 0% rendering,
  scalable Vivid saturation, and true neutral-channel Monochrome
  output. The Release UI on `IMG_0054.CR2` verified all three profile
  groups, Cinematic Teal at 110%, unchanged Light sliders, coexistence
  with the Clean preset, quit/relaunch restoration, and full reset to
  Camera Default.
- The Release app was exercised directly on `IMG_0055.CR2`: a radial
  mask was intersected with a sampled Color Range, followed by an
  inverted Subtract Luminance Range; operation reordering, expanded
  local Light/Color/Effects/Detail adjustments, and Calibration were
  all changed in the UI. The exact graph, values, and operation order
  survived a quit/relaunch, while the preview-only overlay correctly
  returned off.
- A real Canon `IMG_0054.CR2` portrait was used to verify on-device
  subject selection, subject-only adjustment, inverse background-only
  adjustment, restart persistence without re-analysis, and full reset.
  The same file also passes a direct Vision smoke test in which a click
  on one foreground person generates a single-instance object mask,
  persists through JSON, and changes the developed image. The Release
  UI was also used to click that person, visually confirm the red
  foreground-only overlay, quit/relaunch without re-analysis, and
  restore the object mask with its local exposure while leaving the
  picker and overlay transient state off.
- The same `IMG_0054.CR2` was used in the Release UI to generate
  `Sky 1`. The persisted grayscale mask selected the sky while
  excluding Tokyo Tower, the adjacent building, person, trees, and
  ground. The red overlay was preview-only, local exposure and mask
  data survived quit/relaunch, and the overlay returned off. Adding a
  Depth Range to this CR2 correctly reported that no embedded depth or
  disparity map exists and did not add a fabricated operation.
- An automated end-to-end auxiliary-depth test creates a JPEG carrying
  a real Image I/O `AVDepthData` payload, reads it through the same
  service used by the UI, and verifies the normalized near-to-far map.
  Separate tests cover missing depth, invalid samples, Depth Range
  compositing, Sky persistence, bitmap row orientation, and sky
  segmentation boundaries.
- Sixteen XMP service tests cover canonical/uppercase sidecar discovery,
  exact RAWDesk plus Adobe-field round trips, Lightroom-style
  attribute and tone-curve input, Dublin Core leaves and Lightroom
  hierarchical keyword read/write, selective external-keyword
  preservation, copyright and unknown namespace preservation,
  canonical color-label read/write/clear, external label conflict
  preservation, unknown custom-label preservation, selective
  external-field merge, malformed packet protection, scan-time
  precedence, and legacy Pick-state decoding. A
  Rejected-filter test covers the third Pick state.
- Release QA used a byte-identical copy of Canon `IMG_0055.CR2` with a
  valid Adobe-namespaced sidecar. The initial scan imported Rating 4,
  Rejected, Exposure +0.85, Contrast +12, and Highlights -20. Saving an
  Exposure change to +1.10 preserved an existing keyword and custom
  namespace. After relaunch, app-local +1.10 remained authoritative;
  explicitly reading an external Exposure-only change to +1.75 changed
  only Exposure while Contrast and Highlights stayed intact. The XMP
  remained valid XML after every write.
- The original Canon file and QA copy retained the same SHA-256
  (`05a37b94b197a5045f906e26e2372679b49e72007c405558f0692339b6820d93`);
  no sidecar was created beside the original.
- Catalog tests cover exact-state and metadata recovery after reopen,
  keyword-index replacement, hierarchy normalization/tree rollups,
  catalog-wide hierarchy rename, move/merge, branch deletion,
  boundary-safe prefix matching, missing-file participation,
  smart-collection filter migration, depth-limit rejection, and
  atomic JSON-mirror batching. Keyword-definition tests cover synonym
  normalization, export exclusion, parent inclusion, conservative
  merge, hierarchy migration/deletion, persistence, and end-to-end
  IPTC output. Catalog coverage also includes missing-file tracking,
  same-format relink validation, identity and state migration, catalog
  removal, built-in collection counts, corrupt-database
  backup/recreation, and saved-collection persistence/deletion.
  `LibraryViewModel` integration tests cover
  folder indexing, keyword updates, named and built-in keyword
  collections, multi-selection color-label assignment and filtering,
  color-label smart-collection persistence, relinking, and cleanup of
  both SQLite and the JSON compatibility store. Schema coverage also
  verifies v6-to-v7 label-column backfill, v7-to-v8 location-column
  backfill, dedicated indexes, live location counts, and legacy JSON
  defaults.
- Photo-stack tests cover schema migration, transactional creation,
  persistent order and collapse state, same-folder enforcement,
  duplicate-membership rejection, relink/removal cleanup, splitting,
  singleton dissolution, explicit culling acceptance, and source-byte
  invariance. Capture-time tests additionally cover contiguous
  interval boundaries, exact-time behavior at 0 seconds, the 1-hour
  limit, deterministic ordering, folder separation, existing-stack and
  missing-time exclusions, selection/filter independence, atomic
  acceptance, and persistence across a new view-model/catalog session.
- Import tests cover the known SHA-256 digest, guarded hash persistence,
  lazy backfill of same-size catalog candidates, same-size/different-
  content rejection, selection-level duplicate detection, recursive
  discovery, unsupported files, duplicate skipping, Add cataloging,
  Copy byte verification, XMP companionship, collision-safe naming,
  capture-date folders, custom sequence naming, conflicting-folder
  protection, durable post-import duplicate grouping, source
  invariance, and the Last Import view-model handoff. Copy + Trash coverage
  verifies successful photo/XMP Trash disposition only after destination and
  catalog verification, photo-disposition failure retention, verified
  orphan-XMP retention when sidecar cleanup fails, unsafe nested
  destination rejection before any mutation, and protection for an
  already-cataloged source even when duplicate skipping is disabled.
  Token-template coverage verifies deterministic date, camera,
  source-folder, original-name, escaped-brace, and padded-sequence
  rendering; collision-safe photo/XMP transfer; rejection before
  mutation for malformed or unsafe templates; and refusal to traverse
  a destination symlink. Import-time People coverage verifies that only
  the successful imported IDs are analyzed, cache guards are respected,
  suggestions are created without a name, and the original bytes remain
  unchanged.
- Auto Import tests cover normalized/persistent settings, non-nested
  folder validation, photo-and-XMP settling, write-change reset,
  one-shot dispatch, direct-child-only discovery, hidden/subfolder/
  unsupported exclusion, successful transfer receipts, default and
  explicit source retention, injected Trash disposition and failure,
  pre-disposition failure guards, XMP companionship, date/sequence handling, keyword
  and preset application, catalog persistence, and exact-duplicate
  retention without a retry loop. It also covers backward-compatible
  decoding of pre-template settings, valid and invalid template
  round-trips, end-to-end token rendering, and next-sequence handling
  before optional Trash disposition. It also verifies default-off decoding
  of legacy People settings, enabled-setting round trips, targeted local
  analysis after safe ingest, People progress reporting, and
  failure isolation so an analyzer error cannot reverse a completed
  transfer.
- Background People tests verify default-off and corrupt-setting
  recovery, persistent opt-in across a new view model, automatic launch
  scanning, guarded cache reuse, catalog-growth rescans that analyze
  only the new photo, pause/cancellation, and non-modal retry status for
  unavailable photos.
- Catalog-wide duplicate tests cover decoded image-data hashing,
  metadata-only copies with different names, container bytes, and file
  sizes, different-pixel rejection, equal-size whole-file fallback,
  guarded-cache reuse, stale file-fact invalidation, schema migration,
  deterministic Original selection, group/file/additional-copy counts,
  actual per-member reviewable bytes, forced rehash, collection badges,
  and source-byte invariance.
- Assisted Culling tests cover deterministic Select/Reject/Review
  reasons, bounded subject/eye/exposure/misfire/document scores, an
  actual on-device Vision analysis, file-fact and engine-version cache
  guards, manual-decision persistence across stale computed evidence,
  time-and-similarity stack suggestions, live threshold recomputation
  from cached evidence, Auto Stack clearing, forced reanalysis, atomic
  flag/rating/color-label mappings, filter reconciliation, and
  source-byte invariance.
- Earlier whole-file-only Release Exact Duplicates QA imported an exact
  A/B JPEG pair plus a same-size but different-content C file with
  duplicate skipping off.
  The collection showed exactly one group, two files, one additional
  copy, and 1.5 MB reviewable with visible **GROUP 1 · FIRST/MATCH**
  badges. **Verify Again** preserved the result, while **Copy Full
  SHA-256** produced
  `d543ad392d79523401fe11b99834f768aabc1ae7817c1b512ddd4226da61aa2c`,
  matching A and B; C remained excluded. All three source digests and
  the original Canon digest were unchanged. The
  [Release screenshot](Evidence/2026-07-25/exact-duplicates-release.jpeg)
  is retained as durable visual evidence. After QA, the schema-v4 live
  catalog was restored to 111 photos, zero missing files, zero guarded
  hashes, zero duplicate groups, and SQLite `quick_check` equal to
  `ok`.
- Release Assisted Culling QA used an isolated schema-v5 catalog with
  four deterministic JPEGs: a near-identical sharp pair, an all-black
  frame, and a document-like frame. The live screen reported two
  Selects, two Rejects, zero Review, and one suggested stack. Disabling
  Exposure/Misfire rejection and enabling Documents immediately
  changed the result to two Selects, one Reject, and one Review; the
  document was rejected specifically as a document/receipt. All four
  decision filters, manual Select and **Use Calculated Result**, atomic
  Pick/Rejected and 5★/1★ mappings, **Analyze Again**, and cached reopen
  were exercised in the Release app. The full culling timestamps
  changed only for the forced pass and remained stable for the cached
  reopen. The four fixture SHA-256 values, the original Canon digest,
  and sibling-XMP absence remained unchanged. The
  [Release screenshot](Evidence/2026-07-25/assisted-culling-release.jpeg)
  is retained as durable functional evidence from that pass; the
  subsequent adaptive Criteria layout, accessibility labels, per-face
  disclosures, dedicated Culling Details inspector, and live stack
  controls are covered by the final build/tests rather than that
  earlier screenshot. A later automated screenshot attempt was not
  accepted as new evidence because the Mac UI connection closed and a
  second Debug app with the same bundle identifier made the target
  ambiguous. The user's live catalog was restored at schema v5 with
  111 photos, zero missing files, zero culling rows, zero guarded
  hashes, zero keyword definitions or assignments, zero smart
  collections, and SQLite `quick_check` equal to `ok`. The
  [UI audit](Evidence/2026-07-25/ui-audit/README.md) records the
  evidence boundary, flow health, strengths, risks, and accessibility
  limits.
- Release Import QA used two byte-identical JPEG sources plus one
  unsupported text file. Preflight reported one new photo, one exact
  duplicate, and one unsupported file. Copy with **By Capture Date**
  and **Custom Name + Sequence** starting at 7 produced
  `2026/2026-07-25/QA-0007.jpg`; the copy matched the source's complete
  SHA-256. Last Import reported one imported, one copied and verified,
  one template-named, one date-folder-organized, and one duplicate
  skipped. Expanding **Review Exact Duplicate Groups** retained the
  full digest and both source paths after completion.
- Historical pre-patch Release Auto Import QA used an isolated schema-v7 catalog, watched
  folder, destination, and Application Support directory. The Release
  UI saved **By Capture Date**, `Studio Capture` sequence naming, a
  two-second settle interval, Vivid, `Auto Imported`, and
  `Client > Tethered`. Two EXIF JPEG/XMP pairs became
  `Studio Capture-0001` and `0002`; their destination photo and XMP
  SHA-256 values exactly matched the watched sources. Under the earlier
  behavior, source pairs were permanently removed; XMP ratings 4 and 3
  survived, and each catalog row added the
  configured keywords plus Vivid's 28 Vibrance. A byte-identical renamed
  JPEG stayed in the watched folder with a visible Needs Attention
  message. Full quit/relaunch restored the enabled watcher and next
  sequence. The final rebuilt Release then ingested a third,
  independently hashed EXIF JPEG as `0003`, retained only the deliberate
  duplicate, advanced the stored sequence to 4, and left SQLite
  `quick_check` equal to `ok`. Durable screenshots and exact evidence
  boundaries are in
  [`Evidence/2026-07-26/auto-import`](Evidence/2026-07-26/auto-import).
- Release Map QA used an isolated schema-v8 catalog with four
  timestamped JPEGs and a three-point Tokyo GPX tracklog. The Release
  UI started with one embedded location and three untagged photos,
  previewed exactly two GPX matches, and committed three tagged plus
  one untagged photo. A visible, private 5 km Saved Location in the
  `Release QA` folder and the GPX route survived a full quit/relaunch.
  Exporting an in-radius photo removed GPS and IPTC sublocation, city,
  state/province, and country metadata while the catalog retained its
  coordinate. The isolated database stayed at schema 8 with one
  embedded, two manual, and one absent location and SQLite
  `quick_check` equal to `ok`. Durable screenshots, exported fixtures,
  and exact evidence boundaries are in
  [`Evidence/2026-07-26/map`](Evidence/2026-07-26/map).
- Release People QA used an isolated schema-v9 catalog with two
  byte-identical portrait JPEGs derived from a real Canon CR2 and one
  no-face JPEG. The on-device scan recorded three completed analyses,
  two faces, and one reviewable two-photo suggestion without assigning
  a name. After explicit naming, **Show Photo in Library** opened the
  Canon EOS 5D source, **Analyze Again** preserved both reviewed
  assignments, and a full quit/relaunch restored the sidebar count and
  named person before another scan. The final database contained one
  person, two assigned faces across two photos, zero ignored or
  unassigned faces, and SQLite `quick_check` equal to `ok`. Source
  SHA-256 values stayed unchanged and no XMP was created. Durable
  screenshots and exact evidence boundaries are in
  [`Evidence/2026-07-26/people`](Evidence/2026-07-26/people).
- The same disposable Release photo verified a three-level hierarchy,
  all four keyword-tree management actions, two synonym definitions,
  the live IPTC preview, definition persistence, catalog-wide parent
  rename, descendant migration, and guarded branch deletion. The
  definition and assignment moved together in SQLite and no XMP was
  created. After removing all QA records, the live schema-v4 catalog
  returned to 111 photos, zero missing files, zero keyword assignments,
  zero keyword definitions, zero guarded content hashes, zero smart
  collections, and SQLite `quick_check` equal to `ok`.
- Release QA indexed 111 Canon CR2 files, added a keyword to
  `IMG_0055.CR2`, found it through cross-field search, saved that search
  as a smart collection, and restored both the collection and its
  result after a full quit/relaunch. Removing the keyword updated the
  live collection and count to zero; the temporary collection was then
  deleted. SQLite `quick_check` returned `ok`, the source SHA-256 stayed
  unchanged, and no sidecar was created beside the original.
- A second Release QA pass added `Places > Japan > Tokyo` and
  `People > QA` to a byte-identical Canon copy. The sidebar rendered
  expandable People and Places/Japan/Tokyo levels. Its valid XMP stored
  only `Tokyo` and `QA` in `dc:subject` and the complete paths in
  `lr:hierarchicalSubject`. After the CR2 and XMP were moved together,
  Missing Files detected the old path, **Locate Original…** reconnected
  the new path, and a full quit/relaunch restored both hierarchies.
  Moving the copy again exposed the guarded catalog-removal workflow;
  removing its record left the file untouched. QA files and Recent
  history were then removed, leaving 111 catalog photos, zero missing
  files, zero keywords, and SQLite `quick_check` equal to `ok`.
- Both real-RAW QA photos were reset through the UI and relaunched one
  final time; each returned to Original with Reset All disabled and no
  residual profiles, local masks, or Calibration values in persisted
  state.

## Known gaps versus Lightroom

These are product gaps, not hidden claims of parity:

| Area | RAWDesk today | Parity status |
| --- | --- | --- |
| Core development | Full-resolution non-destructive RAW pipeline, profiles, global color/tone/detail, crop, geometry, repairs, versions including restorable ICC proof state, selective 14-section multi-photo synchronization, leaf-level Auto Sync, installed/imported ICC wide-gamut Soft Proofing with separate output/monitor warnings, and metadata-preserving export | Strong core; missing Adobe camera/lens databases, calibrated printer/media preset management, and learned enhancement features |
| Local editing | Subject, object, sky, brush, radial, linear, color, luminance, and embedded-depth masks with ordered Add/Subtract/Intersect | Broad manual workflow; semantic quality and Adobe AI interoperability remain behind |
| Library and catalog | SQLite catalog; one persistent Quick Collection; named, user-ordered regular collections; nested collection sets containing regular, smart, and child sets; target-B routing; Quick conversion; hierarchy-aware keywords; persistent named color-label-set presets with multi-filter/live collections; side-by-side Select/Candidate Compare with synchronized zoom/pan and in-place flags/ratings; responsive multi-photo Survey with an Active photo and per-tile review controls; editable Active/static Reference viewing with role swap, two layouts, lock, Before, whole-image RGB tone deltas, and per-cursor sRGB/Lab readouts; catalog-wide metadata-insensitive exact image-data duplicate groups with guarded whole-file fallback; guarded on-device Assisted Culling; reviewable on-device People suggestions with explicit naming/merge/unassign/ignore; opt-in targeted analysis after manual or watched-folder import; resumable background analysis for new or changed catalog photos; persistent manual/confirmed stacks; capture-time auto stacking; watched-folder ingest; missing-file relink/removal; and a GPS/GPX/Saved Locations map workspace with private-location export controls | Strong local review core; missing collection publication/sync and output collection types, Adobe-model identity quality, perceptual near-duplicate clustering, collection-aware culling/import actions, and very-large-library query/clustering infrastructure |
| Import | Safe Add/Copy/Copy + Trash, source-retaining Auto Import with optional verified Trash disposition, complete SHA-256 duplicate detection, verified staging, XMP companionship, validated date/camera/source-folder/sequence token templates, keywords, and develop presets | Production-safe core; missing Copy as DNG and camera/card orchestration |
| Metadata and interchange | Adobe-compatible global XMP including active-set names in `xmp:Label`, exact private RAWDesk state, hierarchical keywords, resolved IPTC keyword export | Partial; label-set names and external custom labels round-trip, but additional custom colors/shortcut remapping and a complete IPTC or Adobe heavy-edit/local-mask interchange layer remain |
| Output and ecosystem | JPEG/PNG export and a native local-first app | Major gap: tethering, print/book, plugins, cloud/mobile/web, and collaboration |
| Distribution | Reproducible universal x86_64/arm64 Release app with strict ad-hoc signature verification | Local QA only; Developer ID/App Store signing, hardened runtime, notarization, and production entitlements remain |

- Sky quality is strongest when a file contains an authored semantic
  sky matte; the RAW fallback is a conservative local estimate rather
  than a learned semantic model. Depth Range is available only when the
  source contains embedded depth or disparity and never invents depth
  for ordinary RAW files.
- Heal and clone are implemented, but there is no learned
  content-aware fill, reflection removal, or generative remove.
- The built-in Profile browser and Amount control are implemented, but
  there are no camera-model-specific matching tables and no Adobe
  DCP/XMP profile import. Camera Default continues to use the rendering
  supplied by the installed macOS RAW decoder.
- Soft Proofing performs real profile round trips for built-in and
  validated installed/imported RGB or CMYK ICC profiles, preserves
  adjusted and RAW preview data through a half-float working boundary,
  uses the active screen's ICC profile, provides separate
  destination/monitor warnings, and stores complete proof state in named
  versions. It does not install or edit system profiles, calibrate a
  monitor or printer, or model paper stock beyond the selected output
  profile's media behavior. The warnings deliberately report documented
  round-trip tolerances rather than claiming Adobe's profile library or
  exact warning algorithm.
- Automatic Apple RAW lens correction, deterministic per-photo
  chromatic-aberration analysis, manual channel registration, defringe,
  manual perspective, and two-to-four-line Guided Upright are
  implemented; there is no bundled Adobe-style lens-profile database
  or panorama/HDR merge.
- Noise reduction is a conventional Core Image filter; there is no
  learned RAW denoise, Raw Details, or Super Resolution.
- XMP interchange covers compatible global development fields plus
  RAWDesk's exact private payload. It does not claim Adobe local-mask
  or AI heavy-edit interchange, ACR heavy-edit sidecars, embedded
  DNG/JPEG XMP development-metadata writes, camera-profile import, a
  complete IPTC editor, cross-application keyword-definition
  interchange, or a full catalog-level metadata conflict workflow.
- The SQLite catalog, hierarchical keywords, built-in collections,
  missing-file detection/relink/removal, and saved live filter
  collections are implemented, as are preflighted Add/Copy/Copy + Trash import,
  exact-content duplicate detection, verified copies, guarded
  post-catalog Trash disposition, and XMP companionship. Catalog-wide
  keyword rename, hierarchy move/merge,
  and branch deletion are transactional and keep saved keyword filters
  aligned. A catalog-wide Duplicates collection groups guarded exact
  decoded image-data SHA-256 matches independent of filename and
  container metadata, retains a complete-file fallback for equal-size
  files that Image I/O cannot decode, calculates actual reviewable
  bytes, and supports forced reanalysis without automatic deletion.
  This intentionally does not call visually similar re-encodings or
  burst neighbors exact matches; perceptual review remains a separate
  clustering problem. A single persistent Quick Collection supports
  B-key and multi-selection toggling, stable order, relink, and
  non-destructive clearing. Named regular collections add stable user
  order, missing-member relink, and non-destructive membership changes.
  Nested collection sets organize regular and smart collections with
  cycle/depth guards, recursive duplication, and recursive
  organization-only deletion. One regular collection can become the
  explicit B-key target, and Quick Collection can be atomically saved
  as a regular collection. Collection publication/sync, output
  collection types, and collection-aware culling/import actions remain
  unimplemented. A first on-device
  Assisted Culling implementation now exposes reviewable focus, eye,
  exposure, misfire, document, and stack evidence with manual overrides
  and atomic batch actions. It does not yet match Adobe's learned model
  quality, run during Import, or map results to albums. Atomic Select→Green and
  Reject→Red color-label mapping is implemented. Persistent
  Lightroom-style manual and user-confirmed culling stacks are now
  implemented, together with previewed capture-time auto stacking.
  A persistent watched-folder Auto Import now settles photo/XMP writes,
  performs verified background ingest, and resumes across relaunch.
  The Map workspace now covers embedded and manual GPS, direct
  assignment, GPX matching, saved-radius organization, and private
  metadata-stripping export. The People workspace now adds on-device
  face detection and crops, reviewable similarity suggestions, explicit
  naming and merging, per-face unassign/ignore/restore actions, and
  restart-safe catalog persistence without touching source or XMP
  files. Manual and watched-folder imports can now opt into targeted
  on-device analysis after safe ingest, with visible progress and
  failure isolation. Persistent background analysis now checks new or
  changed catalog photos while RAWDesk is active, reuses guarded
  zero-face and face caches, serializes against import scans, and can be
  paused from the People UI. It is a confirmation-first organizer, not
  a claim of biometric identity: Adobe-scale learned identity quality,
  People keyword/XMP interchange, power-aware very-large-library
  batching, and huge-library clustering remain.
  Copy as DNG and camera/card orchestration also remain.
  Saved custom collections currently apply their filter after loading
  catalog entries rather than using a large-library FTS/fully-SQL
  query planner.
- There is no tethering, print/book output, plugins, cloud sync,
  mobile/web client, or collaborative sharing.
- Full-fidelity RAW support remains bounded by the installed macOS RAW
  decoder; there is no bundled third-party camera SDK.
- The local `.app` uses ad-hoc signing. Distribution still needs a
  Developer ID/App Store signing pipeline, hardened runtime,
  notarization, and production sandbox entitlements.

## Next implementation milestones

1. Assisted Culling phase two: import-time analysis, collection and
   album mappings, collection-aware import/culling actions,
   quality calibration against a diverse real-photo corpus, and a
   complete keyboard/VoiceOver audit without hidden deletion.
2. Camera-matching tables, Adobe DCP/XMP profile import, selectable
   lens profiles, calibrated printer/media proof presets, black-point
   compensation controls, and print-workflow validation.
3. Panorama and HDR merge with reviewable alignment, ghost handling,
   full-resolution output, and non-destructive source grouping.
4. Learned RAW denoise, Raw Details, Super Resolution, and
   content-aware/generative removal.
5. People phase two: higher-quality learned identity suggestions,
   People metadata interchange, power-aware very-large-library
   clustering, and optional album mappings. Also add Copy as DNG,
   camera/card ingest, general background indexing, and FTS/query
   optimization.
6. Broader Adobe interchange for heavy edits and embedded metadata,
   metadata-conflict workflow, and production signing/distribution.

## Project layout

```
Sources/RAWDesk/
  App/         RAWDeskApp.swift
  Models/      PhotoAsset, PhotoMetadata, PhotoUserState,
               CatalogModels, PhotoImportModels, PhotoImportTemplate,
               AutoImportModels,
               PhotoColorLabelSet, PhotoLocation, SavedMapLocation,
               GPXTracklog, PeopleModels,
               PhotoAdjustments, NormalizedCrop, DevelopmentPreset,
               DevelopmentProfile, AdvancedColorAdjustments,
               PointColorAdjustment, PhotoAdjustmentSync,
               SoftProofSettings,
               OpticsAndGeometryAdjustments, LocalAdjustments,
               SpotRemoval, EditVersion, LibrarySort, FileFormat,
               FilterState, ImageTransformState, ImageLoadState,
               WorkspaceMode
  Services/    PhotoLibraryScanner, ImageLoader, RAWImageLoader,
               ThumbnailGenerator, MetadataReader, UserStateStore,
               RecentFolderStore, SecurityScopedBookmarkStore,
               CatalogStore, PhotoImportService, AutoImportService,
               AutoImportSettingsStore, WatchedFolderMonitor,
               PhotoColorLabelSetStore, FileContentHasher,
               XMPSidecarService, GPXTracklogParser,
               SavedMapLocationStore, AssistedCullingAnalyzer,
               CaptureTimeAutoStackPlanner, PeopleAnalyzer,
               PhotoProcessor, SubjectMaskGenerator,
               AuxiliaryMaskGenerator, HistogramAnalyzer,
               SoftProofProcessor, ImageColorSampler, ImageExporter,
               ImageCache
  ViewModels/  LibraryViewModel, PhotoViewerViewModel, PeopleViewModel
  Views/       ContentView, LibrarySidebarView, ThumbnailGridView,
               ThumbnailCellView, ImagePreviewView,
               PhotoCompareWorkspaceView, PhotoSurveyWorkspaceView,
               PhotoReferenceWorkspaceView,
               PhotoSyncSettingsView, SoftProofControlsView,
               PhotoInspectorView,
               EditingInspectorView, HistogramView,
               MetadataInspectorView, PhotoImportView,
               AutoImportSettingsView, ColorLabelSetEditorView,
               CaptureTimeAutoStackView, MapWorkspaceView,
               PhotoMapCanvas, GPXTracklogView,
               SavedMapLocationEditorView, PeopleWorkspaceView,
               ToolbarContent, KeyboardHandler,
               ErrorPlaceholderView
  Utilities/   FileTypeDetector, Formatters
Tests/RAWDeskTests/
  RAWDeskTests.swift, PeopleTests.swift
```
