# RAWDesk 改善点監査 — 2026-07-31

**方法:** 6観点で並行監査（29エージェント）。うち高severityとパイプライン系23件は、
別のエージェントが実際にsourceを開いて再検証した。**23件すべてが検証を通過**した（棄却0）。

**制約:** 機能追加は提案対象外。既存のものの配置・表現・既定値・正確さ・文言のみ。

**総数:** 58件（検証済 23 / 未検証 35）


---

## 検証済みの指摘


### 画像パイプライン（精度）


#### [高] Histogram is normalised against the alpha channel, so every RGB curve is drawn at a fraction of its true height

**場所:** `Services/HistogramAnalyzer.swift`:61


`let largest = pixels.max() ?? 0` (HistogramAnalyzer.swift:61) scans the interleaved RGBA bin buffer, which includes the alpha bins at offsets 3, 7, 11… `CIAreaHistogram` with `inputScale: 1.0` (line 45) normalises each channel so its bins sum to 1.0. For any opaque image every alpha pixel lands in the last bin, so that bin is exactly 1.0 — and no RGB bin can ever exceed it unless the image is a single flat colour. `largest` is therefore effectively hard-coded to 1.0, and `channel(_:)` (lines 63-68) divides every RGB bin by the total pixel count instead of by the peak bin. I verified this against live CoreImage with the same filter settings and the same RGBA8/premultipliedLast layout that `PhotoProcessor.rasterize` produces (PhotoProcessor.swift:2768): for a 256-level grey ramp at binCount 128, `pixels.max()` = 1.0 while the true RGB peak is 0.0078125. After the sqrt at line 67 the curve is drawn at 8.8% of the panel height. `HistogramShape` then clamps to 0…1, so nothing recovers the scale. The comment at lines 65-67 says the sqrt exists to keep shadow/midtone detail readable when a highlight spike dominates — the bug defeats exactly that intent, because there is no peak-relative scaling left at all.


**なぜ問題か:** The histogram is the single most-used instrument in a Develop module. Rendering it as a flat sliver pinned to the bottom of the box makes it useless for judging exposure, and it is the most immediately visible sign to a professional that the numbers behind this app are not trustworthy. The severity scales with pixel count: the more pixels, the flatter the curve.


**修正方針:** Replace line 61 of Sources/RAWDesk/Services/HistogramAnalyzer.swift so the peak is taken over the colour channels only, keeping ONE shared peak for R/G/B (do not normalise each channel separately — that would destroy relative channel heights and hide colour casts):

    var largest: Float = 0
    var scanIndex = 0
    while scanIndex < pixels.count {
        largest = max(largest, pixels[scanIndex])
        largest = max(largest, pixels[scanIndex + 1])
        largest = max(largest, pixels[scanIndex + 2])
        scanIndex += 4
    }

Leave line 62 (`guard largest > 0 else { return .empty }`) and the `channel(_:)` body at lines 63-69 exactly as they are; the sqrt and the shadow/highlight clipping maths at lines 70-84 already skip alpha and need no change. `pixels.count` is always a multiple of 4 (allocated as `binCount * 4` at line 48), so the +1/+2 indexing is safe.

Add a regression test alongside the existing ones in Tests/RAWDeskTests/RAWDeskTests.swift (near line 9409). A solid-colour image cannot detect this, so the test must use a non-flat image — e.g. a horizontal 0..255 grey ramp — and assert `histogram.red.max()` is approximately 1.0 (accuracy ~0.01). Before the fix that value is ~0.088 at binCount 128.


#### [高] Export develops from an 8-bit, gamut-mapped intermediate; the preview develops from 16-bit extended-linear

**場所:** `Services/PhotoProcessor.swift`:194


`renderFullResolution` calls `RAWImageLoader.load(url:targetLongestEdge: nil)` (PhotoProcessor.swift:194) and takes the default `preserveWideGamut: false` (RAWImageLoader.swift:68). The on-screen path calls `RAWImageLoader.loadResult(... preserveWideGamut: quality == .preview)` — i.e. `true` (ImageLoader.swift:284-285). The flag drives two separate things inside the loader. First, `filter.isGamutMappingEnabled = !preserveWideGamut` (RAWImageLoader.swift:195-196): the export gets CIRAWFilter's gamut mapping, the preview does not. Second, `rasterize` (RAWImageLoader.swift:283-295): `preserveWideGamut` selects `.RGBAh` in `extendedLinearSRGB`, while `false` falls to `displayContext.createCGImage(ciImage, from: extent)` with no format argument — that default is RGBA8 in the context's default sRGB output space. So the RAW decode is quantised to 8 bits and hard-clipped at 0.0 and 1.0 *before* `develop()` runs any adjustment math on it. Anticipating the obvious objection — that the half-float image cannot survive `image.cgImage(forProposedRect:)` at PhotoProcessor.swift:126 — the soft-proof path already performs exactly that RGBAh round trip today: PhotoProcessor.swift:177 → `rasterizeForSoftProof` (2779-2801) → `SoftProofProcessor.apply` reading it back at SoftProofProcessor.swift:122.


**なぜ問題か:** Highlight recovery is where this bites hardest. CIRAWFilter with `isHighlightRecoveryEnabled` (RAWImageLoader.swift:200-202) hands back values above 1.0; the preview keeps them, so pulling Exposure down brings a bright sky back. On export those same values were already flattened to 255, so the exported file shows a dead grey patch where the screen showed recovered detail. Gamut mapping being on for export and off for preview shifts saturated colours independently of that. The final file is 8-bit sRGB either way — this is not about writing a 16-bit file, it is that the export's adjustment math is fed strictly less data than the preview's was, so what you tuned on screen is not what gets written.


**修正方針:** Change PhotoProcessor.swift:194 to:

    source = try RAWImageLoader.load(
        url: asset.url,
        targetLongestEdge: nil,
        preserveWideGamut: true
    )

Nothing else needs to change: `apply(to:adjustments:)` already re-wraps via `CIImage(cgImage:)` (line 130), which picks up the extendedLinearSRGB space off the CGImage, `develop()` already works in that space, and the terminal `rasterize` (2760-2777) still writes `.RGBA8` in `outputColorSpace` (sRGB), so the written file format and the `kCGImagePropertyProfileName: "sRGB IEC61966-2.1"` metadata in ImageExporter are untouched.

Two things to handle deliberately rather than by accident:

1. Gamut mapping. Passing `true` also flips `filter.isGamutMappingEnabled` to `false` for export (RAWImageLoader.swift:195-196), because the loader couples the two behaviours behind one flag. This is what makes export match preview, so it is the desired end state, but verify on a RAW with saturated reds/blues that the result is acceptable and not harshly clipped. If it is not, the correct remedy is to split the loader's parameter into two (`preserveWideGamut` for the rasterize format, `gamutMap` for the filter) rather than to revert line 194 — reverting reinstates the 8-bit intermediate.

2. Memory. Full-resolution RGBAh doubles the intermediate footprint (a 4608x3072 frame goes ~57 MB → ~113 MB; a 100 MP body ~800 MB), and export already runs on a detached task. Confirm the existing export tests (RAWDeskTests.swift:11502, 11578, 11694, 11736, 11759, 12877) still pass and do not regress under the larger buffers.

Worth adding a regression test in the spirit of the existing one at RAWDeskTests.swift ~10540: develop the same asset twice with a strongly clipping adjustment chain (e.g. exposure -2 following a +2 highlight lift) via `renderFullResolution` and via the preview path, and assert the exported pixels recover highlight detail that the 8-bit path cannot. Note that the current test at 12724 only asserts pixel dimensions, so it will not catch a regression here either way.

Not part of this fix, but adjacent and worth a separate look: the non-RAW export branch `loadFullResolutionImage` (PhotoProcessor.swift:201-218) ends in the same RGBA8/sRGB `rasterize`, so 16-bit TIFF and HDR HEIC originals are also flattened to 8 bits before `develop()`.


#### [高] Sharpening, noise reduction, clarity, texture and grain use fixed pixel radii that do not scale with render resolution

**場所:** `Services/PhotoProcessor.swift`:533


Every detail filter in `develop()` takes a radius in absolute source pixels: `CISharpenLuminance` radius `a.sharpeningRadius` (0.5…3 px, PhotoProcessor.swift:532-534), texture `CIUnsharpMask` radius `0.7 + texture/100*1.4` (line 407), clarity `CIUnsharpMask` radius `2.5 + clarity/100*2.5` (line 435), noise-reduction contrast radius `1.5 + noiseReductionContrast/35` (line 491), colour-noise `CIGaussianBlur` radius (line 508), and the grain tile scale `0.38 + size/100*2.15` on a fixed 512×512 tile (line 637). The preview is decoded to a 3840 px longest edge (`private let previewTarget: CGFloat = 3840`, PhotoViewerViewModel.swift:66) while `renderFullResolution` decodes at native size (PhotoProcessor.swift:194). On a 45 MP body that is roughly 8200 px — a 2.1× difference — and `develop()` receives no scale hint at all, so identical pixel radii are applied to both. That the inconsistency is unintentional is provable from the same function: the vignette radius at line 608 is written as `min(developedExtent.width, developedExtent.height) * 0.48`, i.e. deliberately extent-relative, and `applyingOptics` / `applyingGeometry` use `hypot(extent.width, extent.height)` scaling too (e.g. line 683).


**なぜ問題か:** Sharpening judged at Fit or 1:1 on the preview lands roughly half as strong in the exported file, and grain tuned on screen comes out visibly finer. Detail sliders that do not survive the trip to disk are the thing that most reliably makes a photographer stop trusting a develop module — Lightroom's whole 1:1-preview discipline exists to avoid exactly this.


**修正方針:** Do not add a caller-supplied scale argument — `develop()` can derive it, and none of the `apply(to:)` call sites know the source's native size anyway.

1. Add a shared constant on `PhotoProcessor`: `public static let detailReferenceLongestEdge: CGFloat = 3840`, and change `PhotoViewerViewModel.previewTarget` (PhotoViewerViewModel.swift:66) to read from it so the reference and the decode target cannot drift apart.

2. In `develop()` (PhotoProcessor.swift:220), immediately after `let originalExtent = image.extent` (line 245), add:
   `let detailScale = max(1, max(originalExtent.width, originalExtent.height) / Self.detailReferenceLongestEdge)`
   with a comment naming the preview reference. Use `originalExtent` (pre-crop), NOT `developedExtent` — cropping changes framing, not pixel density, so an implementer must not "correct" this later.

3. Multiply the pixel radii, preserving the existing clamp order:
   - line 407: `kCIInputRadiusKey: (0.7 + a.texture / 100 * 1.4) * detailScale`
   - line 435: `kCIInputRadiusKey: (2.5 + a.clarity / 100 * 2.5) * detailScale`
   - line 491: `kCIInputRadiusKey: (1.5 + a.noiseReductionContrast / 35) * detailScale`
   - line 508: `kCIInputRadiusKey: max(0.25, radius) * detailScale` — clamp FIRST, then scale. `radius` at lines 501-505 can go negative via `- a.colorNoiseDetail / 100 * 1.4`; `max(0.25, radius * detailScale)` would silently turn a user-requested near-zero blur into a 0.53 px blur at 2.1x.
   - line 533: `kCIInputRadiusKey: a.sharpeningRadius * detailScale`
   - grain: add a `scale: CGFloat` parameter to `applyingGrain` (declared line 630, called at ~line 614) and use `let grainScale = CGFloat(0.38 + size / 100 * 2.15) * scale` at line 637; the function currently has no way to see `detailScale`.

Deliberate deviation from the claim's `longestEdge / 3840`: the `max(1, ...)` floor. Without it, a source whose native longest edge is under 3840 (preview == native, since neither loader upscales) would have all its radii shrunk below today's values, visibly changing every existing edit on small files while fixing nothing — preview and export are the same pixel size there. With the floor, the factor is exactly 1 for sub-3840 sources and for the 3840 preview itself, so the claim's "slider meaning at preview scale unchanged" holds precisely for sources at or above 3840 and for small sources, and only the full-resolution export of a large source changes.

Documented residuals, none blocking: `CINoiseReduction` (lines 419, 443, 475) and `CIEdges` (line ~540) expose no radius input, so preview/export parity for negative texture, negative clarity, base noise reduction and sharpening masking stays approximate. Separately, `PhotoSurveyWorkspaceView.swift:381` renders adjusted images from a 1600 px preview; the floor leaves those at 1x, i.e. unchanged and still coarser-looking than the 3840 preview — pre-existing, display-only, out of scope for this export-parity fix.

Verification: render the same asset through `PhotoProcessor.apply` on a 3840 preview and through `renderFullResolution`, downsample the full-res result to 3840, and compare; sharpening/clarity/grain structure should now match within resampling error. Existing tests use small synthetic images, so the floor keeps them at 1x and none should change.


#### [中] Clipping indicators under-report: single-channel clipping is divided by three, and they are measured on the downscaled preview

**場所:** `Services/HistogramAnalyzer.swift`:78


Two independent mechanisms both push the reported figure down. (1) `colorTotal` accumulates the R, G and B bins of every bin (HistogramAnalyzer.swift:70-77); since each channel sums to 1.0 under `inputScale: 1.0`, `colorTotal` is 3.0. The shadow and highlight fractions at lines 78-84 then divide the summed first/last bins by 3.0, producing the *mean* clipped fraction across channels rather than the worst one. A sunset where 30% of pixels are blown in red only and clean in green and blue is reported as 10%. (2) The image being measured is the developed preview, decoded at a 3840 px longest edge (PhotoViewerViewModel.swift:66) and handed to `updateHistogram` at PhotoViewerViewModel.swift:937 / 1039 / 1055. Downsampling from native averages each output pixel over several source pixels, so isolated blown pixels are pulled below the top bin and never counted — while the full-resolution export written by `renderFullResolution` (PhotoProcessor.swift:194) still contains them.


**なぜ問題か:** This is a decision instrument driven by preview-resolution data and a diluted statistic. Both errors point the same way — the indicator says the frame is safe when the exported file is clipped. Single-channel highlight clipping in reds and skin tones is precisely the case a portrait or landscape photographer needs the warning for, and it is the case the ÷3 averaging hides best. Lightroom triggers its indicators on any channel, so the discrepancy is directly observable by anyone comparing the two.


**修正方針:** In HistogramAnalyzer.analyze, replace the single `colorTotal` with per-channel totals and report the worst channel. Swap lines 70-84 for:

```swift
var totals: (Float, Float, Float) = (0, 0, 0)
var pixelIndex = 0
while pixelIndex < pixels.count {
    totals.0 += pixels[pixelIndex]
    totals.1 += pixels[pixelIndex + 1]
    totals.2 += pixels[pixelIndex + 2]
    pixelIndex += 4
}
// Worst-channel clipping: a pixel blown in red only is still blown.
func worstChannelFraction(atBin base: Int) -> Float {
    var worst: Float = 0
    for (offset, total) in [(0, totals.0), (1, totals.1), (2, totals.2)] where total > 0 {
        worst = max(worst, pixels[base + offset] / total)
    }
    return worst
}
let shadow = worstChannelFraction(atBin: 0)
let last = (binCount - 1) * 4
let highlight = worstChannelFraction(atBin: last)
```

Dividing by each channel's own accumulated total (rather than hardcoding 1.0) keeps this correct if `inputScale` is ever changed. The two existing tests still pass unchanged: for solid black/white every channel total is 1.0 and its end bin is 1.0, so max == 1.0 > 0.9. Add a regression test with an image that is blown in one channel only — e.g. a solid (1.0, 0.5, 0.5) patch — and assert `highlightClippingFraction` is ~1.0, not ~0.33; today it returns ~0.33.

For the preview-vs-export gap, do not re-measure at full resolution on every adjustment — that would run a full RAW decode per slider move. The proportionate fix is honesty in the readout: in HistogramView.swift:70 change the help text to name the source, e.g. `.help("\(label) (preview): \(String(format: "%.2f", fraction * 100))%")`, and mirror it in the `accessibilityValue` on line 72, so the number is not read as an export-accurate measurement. If an export-accurate figure is actually wanted, compute it once inside the export path off `renderFullResolution`'s output and surface it there, not in the live inspector.


#### [中] Dead rotate/flip state in ImageTransformState carries a latent double-rotation bug into export

**場所:** `Models/ImageTransformState.swift`:25


Rotation and flip exist in two parallel places. The live one is `PhotoAdjustments.rotationDegrees / flipHorizontal / flipVertical` (PhotoAdjustments.swift:50-52), applied inside `develop()` at PhotoProcessor.swift:237-244, and written by `LibraryViewModel.rotateLeft/rotateRight` (LibraryViewModel.swift:4389, 4396) — the only rotation entry points in the UI (ToolbarContent.swift:396, 409; EditingInspectorView.swift:1705, 1715; RAWDeskApp.swift:593, 600). The dead one is `ImageTransformState.rotateRight()` / `rotateLeft()` / `toggleFlipHorizontal()` / `toggleFlipVertical()` (ImageTransformState.swift:25-32), which have zero callers anywhere in Sources, and `PhotoViewerViewModel` zeroes `transform.rotationDegrees / flipHorizontal / flipVertical` at seven separate sites (lines 455-457, 489-491, 526-528, 575-577, 631-633, 689-691, 762-764). `exportSelected` still passes `viewer.transform` into the exporter (ContentView.swift:1811-1815), where `ImageExporter.applyTransform` (ImageExporter.swift:227-277) exists solely to service it. That function is therefore unreachable today — and if the dead mutators were ever wired up it would rotate a second time on top of the rotation `develop()` already baked in, and re-quantise the result through a fresh `bitsPerComponent: 8` CGContext (ImageExporter.swift:252).


**なぜ問題か:** Two sources of truth for orientation, one of which is nailed to zero by seven scattered assignments, is the kind of structure that produces a sideways export the first time someone touches it. It also means a reader auditing the export path has to reason about a rotation stage that never runs, and about an extra 8-bit round trip that is pure noise in the pipeline.


**修正方針:** Collapse orientation to one home in PhotoAdjustments, but do the full sweep — the fields are read in five source files, not one.

1. Sources/RAWDesk/Models/ImageTransformState.swift — delete `rotationDegrees`, `flipHorizontal`, `flipVertical` (lines 5-7), their init params and assignments (12-14, 18-20), and `rotateRight()`/`rotateLeft()`/`toggleFlipHorizontal()`/`toggleFlipVertical()` (25-32). Keep zoom, fitToWindow, zoomIn/zoomOut/actualSize/fit, and `identity`. Update the doc comment on the struct if it mentions orientation.

2. Sources/RAWDesk/Services/ImageExporter.swift — delete `applyTransform` entirely (227-277), drop `let transformed = applyTransform(...)` at line 52 and take the cgImage straight off `image`, and remove the `transform: ImageTransformState` parameter from BOTH overloads (line 43 and line 90) plus the forwarding argument at line 103. Also update the doc comment at line 40 ("with display-only transforms applied").

3. Sources/RAWDesk/Views/ContentView.swift — remove `let transform = viewer.transform` (1806) and the `transform: transform` argument (1814).

4. Sources/RAWDesk/Views/ImagePreviewView.swift — simplify ImageViewportMapper.normalizedPoint: drop the isQuarterTurn/displaySize branch (19-26, `displaySize` becomes `imageSize`), drop the rotation inverse (angle/cosine/sine at 48-58, so centeredX/centeredY feed straight into the scale divide), and drop the flip signs (61-64, horizontalScale/verticalScale become `scale`). In imageView, drop `isQuarter`/`displayBase` (261-265, fitScale computes off imgSize), drop `sx`/`sy` (274-275) so `.scaleEffect(effectiveScale)`, and drop `.rotationEffect` (284). Keep the `transform:` argument at line 505 — the mapper still needs zoom/fitToWindow.

5. Sources/RAWDesk/Views/PhotoCompareWorkspaceView.swift — same simplification in compareImage: drop isQuarterTurn/displaySize (556-565), xScale/yScale (578-583), and the `.rotationEffect` block (596-601). Keep line 704.

6. Sources/RAWDesk/ViewModels/PhotoViewerViewModel.swift — delete the three zeroing lines in each of the seven blocks (455-457, 489-491, 526-528, 575-577, 631-633, 689-691, 762-764) but KEEP the `transform.fit()` immediately after each (458, 492, 529, 578, 634, 692, 765). Delete bottom-up so line numbers stay valid.

7. Tests/RAWDeskTests/RAWDeskTests.swift — delete `testRotateRightWraps` and `testRotateLeftWraps` (~1510-1522); delete `testMappingInvertsQuarterTurn` and `testMappingInvertsFlips` (~824-864, they construct ImageTransformState(rotationDegrees:90) / (flipHorizontal:true, flipVertical:true)); delete the export-rotation test around 11480-11518 that does `transform.rotateRight()` and asserts 80x50 -> 50x80 (that coverage belongs on PhotoAdjustments.rotationDegrees through PhotoProcessor, and if you want to keep it, rewrite it as `adjustments: PhotoAdjustments(rotationDegrees: 90)` with no transform); and strip the now-removed `transform:` argument from the remaining ImageExporter.export call sites at ~11505, 11581, 11697, 11739, 11762, 12880.

8. Optional but worth it: add a regression test asserting that exporting with `PhotoAdjustments(rotationDegrees: 90)` produces exactly one quarter-turn (source 80x50 -> output 50x80), which is what pins the "orientation applied once" invariant after the parallel path is gone.

Do NOT touch PhotoAdjustments, PhotoProcessor.applyingOrientation, AuxiliaryMaskGenerator, or PhotoAdjustmentSync — those are the live path and are correct.


### Develop UI


#### [高] Percent-formatted value fields cannot be typed into — the number shown parses to the slider maximum

**場所:** `Views/RAWDeskDesignSystem.swift`:1491


`RAWSliderRow.commitTextValue` (RAWDeskDesignSystem.swift:1491-1501) strips "%" and "°", parses the remainder as a raw domain value, and clamps it to `range`. But `percentFormat` (EditingInspectorView.swift:4142-4144) and `CropPositionSlider`'s format (EditingInspectorView.swift:5966-5968) display `value * 100`. Format and parse are not inverses. Brush Size (EditingInspectorView.swift:741-752, range 0.005...0.25) displays "4%"; typing "4" back in yields 4.0, clamped to 0.25 — the maximum. Every ×100 field behaves this way: brush Size/Feather/Flow (741-776), mask Horizontal/Vertical/Size/Feather (797-844), the primary-operation duplicates (3333-3448), all six spot-removal geometry sliders (1164-1252), and both crop position sliders (1775-1784). Separately, Brush Size's step of 0.005 over 0.005...0.25 changes the displayed integer percent only every other step, so half the keyboard/drag increments produce no visible readout change.


**なぜ問題か:** The numeric field is the only precise-entry affordance on these sliders. In a professional develop panel you type a value to get exactly that value; here typing the value the field just printed silently jumps the parameter to its extreme, destroying a mask or repair the user was positioning. It is worse than having no field, because it looks authoritative.


**修正方針:** Make the parser derive from the same declaration as the formatter, and keep the change scoped so the unscaled `%`/`°` sliders are untouched.

1. In RAWDeskDesignSystem.swift, add a small testable value type next to `RAWSliderPresentation` (which is already a pure struct tested in UIStateContractTests.swift), e.g.:

```swift
struct RAWSliderValueFormat {
    let format: (Double) -> String
    let parse: (String) -> Double?

    static func raw(_ format: @escaping (Double) -> String) -> RAWSliderValueFormat
    static let scaledPercent = RAWSliderValueFormat(
        format: { "\(Int(($0 * 100).rounded()))%" },
        parse: { RAWSliderValueFormat.number(in: $0).map { $0 / 100 } }
    )
    private static func number(in text: String) -> Double? {
        Double(text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespaces))
    }
}
```

2. Minimal-churn variant if you do not want to touch all 23 call sites at once: add `var parse: (String) -> Double? = nil` to `RAWSliderRow` (line 1335 area) and change line 1495 to `guard let parsed = (parse ?? Self.defaultParse)(textValue) else { ... }`, dropping the inline stripping into `defaultParse`. Then have `percentFormat` (EditingInspectorView.swift:4142) become a paired constant that supplies both closures, and pass the parse through `MaskValueSlider` (6045-6066) and `CropPositionSlider` (5953-5974), which currently forward only `format`. Note `AdjustmentSlider` (5982-6043) also forwards only `format`; give it the same pass-through so future scaled uses cannot regress.

3. Preserve existing tolerance: the parse should still accept a bare number with or without the unit suffix, and should keep clamping to `range` after dividing (line 1499 unchanged). Do not snap to `step` — nothing does today and adding it would change drag/keyboard semantics.

4. Readout granularity: change `percentFormat` to one decimal only for the two 0.005-step sliders, or simpler and more consistent, coarsen both `step: 0.005` sliders to `0.01` — Brush Size (EditingInspectorView.swift:746-748) and spot-removal Size (1220-1222); the claim named only the first. Coarsening keeps the integer-percent readout and makes typed values (which land on 0.01 multiples after `/100`) reachable by drag and arrow keys too. If 0.5% brush granularity is genuinely wanted, keep the step and raise the formatter to `String(format: "%.1f%%", $0 * 100)` for those two sliders instead — do not raise it globally, since the 0.01-step percent sliders would then read "65.0%".

5. Add a unit test over the new value type: `scaledPercent.parse(scaledPercent.format(0.04)) == 0.04` and round-trip at range bounds, plus a case asserting the default (unscaled) format still parses "65%" to 65 so the 0...100 sliders at 1823/3974-4078 are pinned against regression.


#### [高] Slider value fields display a stale number after the first time they are typed into

**場所:** `Views/RAWDeskDesignSystem.swift`:1427


`RAWSliderRow` shows its number through the TextField *placeholder*: `textValue` is initialised to `""` (RAWDeskDesignSystem.swift:1339) and the formatted value is passed as the placeholder string (1427-1431). Both exit paths of `commitTextValue` assign a non-empty string to `textValue` (1496, 1500), and there is no `.onChange(of: value)` anywhere in the row (the only observers are `onHover`, `onSubmit`, and `onChange(of: textFieldFocused)` at 1466-1481). So once a field has been focused and blurred, `textValue` is permanently non-empty and never tracks the slider again.


**なぜ問題か:** Two failures from one root cause. (1) Type 1.20 into Exposure, click away, then drag the Exposure slider: the track and the image update, the number keeps reading +1.20. The user is now reading a lie off the primary instrument. (2) Until first focused, the number renders in placeholder styling — dimmed, no border (the box only appears on hover/focus, 1455-1465) — so it does not read as editable at all; after first focus it renders in primary text colour. The same row draws its value two different ways depending on history, which is exactly the 'editable but does not look it' problem.


**修正方針:** Keep `RAWSliderPresentation` and the placeholder argument at 1427-1431 exactly as they are (narrowing `fieldPlaceholder` to only the em dash would break UIStateContractTests.swift:697-723, which asserts `concrete.fieldPlaceholder == "-0.35"`, and 675-695, which asserts the focused-mixed placeholder is the representative value). Instead make `textValue` the thing that is always populated, so the placeholder can only ever surface when `textValue` is empty — i.e. the mixed case, which is exactly what is wanted.

Three edits in RAWSliderRow:

1. Seed and maintain the text from the value. Add after the existing `.onChange(of: textFieldFocused)` block (i.e. after line 1481), using the two-parameter form to match line 1470 (the single-parameter `{ format($0) }` overload in the proposal is deprecated):

    .onChange(of: value, initial: true) { _, newValue in
        guard !textFieldFocused else { return }
        textValue = isMixed ? "" : format(newValue)
    }

`initial: true` covers the appear-time seed, so no separate `.onAppear` is needed. The `!textFieldFocused` guard keeps a live edit from being overwritten if `value` changes underneath the user.

2. Do the same for the mixed flag — this is the part the proposed fix misses, and without it the identical bug class returns for the em dash. Going from a single selection (textValue = "+12") to a mixed selection flips `isMixed` true while `textValue` is still non-empty, so "—" stays suppressed and the field shows one photo's number for a multi-photo selection:

    .onChange(of: isMixed) { _, mixed in
        guard !textFieldFocused else { return }
        textValue = mixed ? "" : format(value)
    }

3. Fix the parse-failure path in `commitTextValue` (line 1496) so blurring a mixed field after typing garbage does not stamp a concrete number over the em dash permanently:

    guard let parsed = Double(sanitized) else {
        textValue = isMixed ? "" : format(value)
        return
    }

Line 1500 stays as `textValue = format(value)` — committing a real number resolves the mixed state to a concrete one.

The existing focus handler (1470-1481) already empties `textValue` for mixed on focus, so the focused-mixed appearance (empty buffer, representative value dimmed behind it) is unchanged.

Do not fold in the claim's closing design change. Routing the resting value through `textValue` does make the number render in primary rather than placeholder grey across all twelve inspector rows — flag that as a side effect for the author to accept or compensate for (e.g. a `.foregroundStyle(.secondary)` while unfocused/unhovered). The comment at 1451-1454 shows the low at-rest weight was deliberate, so "the hover-reveal box is the only editability hint needed" is a separate design decision, not part of this bug fix.


#### [高] Expanding a section's disclosure triangle silently puts the canvas into a tool mode

**場所:** `Views/RAWDeskDesignSystem.swift`:1079


`RAWInspectorSection`'s header button calls `onActivate?()` whenever the section is being expanded (RAWDeskDesignSystem.swift:1078-1080), and Option-click-to-solo calls it too (1073-1077). `adjustmentGroup` wires `onActivate` to `onActivateTool` for exactly the four sections `interactiveTool(for:)` maps — Masks, Remove, Crop & Geometry, Point Color (EditingInspectorView.swift:5581-5587, 5620-5633). `activateDevelopTool` (ContentView.swift:1562-1588) then calls `viewer.setCropEditing(true)` / `startRemovalTool` / `startMaskTool` / `setPointColorPicking(true)`, snapshots state via `captureToolStartIfNeeded()`, and posts a VoiceOver announcement. Collapsing the section does not undo any of it.


**なぜ問題か:** Clicking a disclosure triangle to *look at* a panel is a read-only gesture in every professional tool. Here, expanding Point Color arms the eyedropper so the next click on the photo creates a swatch; expanding Crop & Geometry drops the image into crop mode with handles and a Done/Cancel bar; Option-clicking to solo a section does the same. The user must then find the mode bar above the canvas and press Cancel to get back to where they were. It also makes the section-expansion state, which is persisted in AppStorage, load-bearing for image state.


**修正方針:** Remove implicit tool activation from the section header entirely, then repair the entry point it was masking.

1. RAWDeskDesignSystem.swift: delete `var onActivate: (() -> Void)?` (line 1062) and both invocations. The header button body (1072-1082) collapses to: if Option is held and `onSolo` exists, call `onSolo()`; else `setExpanded(!isExpanded)`. Removing only the expand branch is not enough — line 1076 keeps the same defect behind Option-click.

2. EditingInspectorView.swift: delete the `onActivate:` argument in `adjustmentGroup` (5581-5587). `interactiveTool(for:)` (5620-5633) then has no callers; delete it too. No other `RAWInspectorSection` call site in the tree passes `onActivate`, so the parameter removal is contained and touches no other inspector.

3. Required companion change, otherwise the fix regresses cancel-restore: the in-body activation buttons bypass `captureToolStartIfNeeded()` and the announcement, so a tool started from them leaves `toolStartAdjustments` empty and `cancelDevelopTool` (ContentView.swift:1619-1640) restores nothing on Escape. The header activation currently hides that for the fresh-expand case. Route those four buttons through the same closure — replace `viewer.setCropEditing(true)` (1509) with `onActivateTool(.crop)`, `viewer.setPointColorPicking(true)` (181, the enable side of the toggle only; keep the direct `setPointColorPicking(false)` for the Cancel side) with `onActivateTool(.pointColor)`, `viewer.setRemovalEditing(true)` (1091) with `onActivateTool(.remove)`, and the brush-enable at 718/3317 with `onActivateTool(.mask)`. Note this hole predates the fix — `@AppStorage` persists expansion, so a user relaunching with Crop already expanded gets no snapshot today — but the fix widens exposure to every entry, so ship them together.

4. Nothing needs to change in the reverse direction: `expandDevelopSection` (ContentView.swift:1591-1606) still reveals the right section when a tool is entered from the tool row, a menu, or a keyboard shortcut, and it writes the same `@AppStorage` keys the inspector reads.

5. There is currently no test coverage for any of this (no hits for `onActivate`/`activateDevelopTool` under Tests/). Add a regression test asserting that toggling a section's expansion state does not change `PhotoViewerViewModel`'s tool flags, or at minimum verify manually that expanding Point Color leaves `viewer.isPointColorPicking == false`.


#### [高] Crop & Geometry has two resets with the same name that reset different things

**場所:** `Views/EditingInspectorView.swift`:1839


The section header's Reset routes through `resetAdjustmentGroup(.geometry)` (EditingInspectorView.swift:5650-5676), which merges `.neutral` for the `.geometry` group — and that group includes `rotationDegrees`, `flipHorizontal`, `flipVertical`, `straighten`, `crop`, and `geometry` (PhotoAdjustmentSync.swift:395-401) — then calls `viewer.finishInteractiveTools()`. The in-body "Reset Crop & Geometry" button (EditingInspectorView.swift:1839-1859) sets only `crop = .fullFrame`, `straighten = 0`, `geometry = .neutral`; it leaves rotation and flips alone and does not exit the crop tool. Its `.disabled` condition (1855-1859) likewise ignores rotation and flips, while the header's `isResetDisabled` uses `sectionIsNeutral` (5635-5648), which does account for them.


**なぜ問題か:** Rotate a photo 90°, then press the labelled "Reset Crop & Geometry" button: nothing visible happens (the button is even enabled, promising otherwise). Press the header Reset three rows above and the rotation goes away too. Two controls, one section, identical name, different behaviour — the user cannot form a rule about what 'reset' means. If the crop tool is live, the in-body button also leaves the canvas editing a crop that no longer exists.


**修正方針:** Delete EditingInspectorView.swift:1839-1859 in full — the entire `Button { ... } label: { Label("Reset Crop & Geometry", systemImage: "crop.rotate") }` chain including its `.rawSecondaryTextAction()`, `.font(...)` and `.disabled(...)` modifiers — leaving the `Toggle("Constrain Crop", ...)` at 1833-1837 as the last element of the section body.

This is a clean excision with no build fallout: the only local it references is `let crop` (1773), which remains used at 1774, 1778 and 1783. No test or other source file references the string "Reset Crop & Geometry" (verified by grep over Sources and Tests), so nothing else needs updating.

No capability is lost. The header Reset already covers every field this section's controls can mutate — `crop`, `straighten`, `geometry` (including `guidedUprightGuides`), `rotationDegrees`, `flipHorizontal`, `flipVertical` — and additionally exits the crop/guided-upright overlay via `finishInteractiveTools()`, which the in-body button never did. One behavioural note for the author: RAWDeskDesignSystem.swift:1130 hides the header Reset entirely when `isResetDisabled`, so after deletion a neutral section shows no reset affordance at all rather than a greyed-out one; that is the existing convention for every other section and is the intended result.

Only if a partial reset is genuinely wanted instead: keep the header as the whole-section reset and rename the in-body label to what it actually does (e.g. "Reset Crop & Perspective"), but deletion is preferred — the in-body `.disabled` condition at 1855-1859 would still under-report section state relative to `sectionIsNeutral`, and it would still leave the crop tool active on click.


### Library / 選別


#### [高] Grid never scrolls to follow the selection

**場所:** `Views/ThumbnailGridView.swift`:60


ThumbnailGridView binds the scroll position to `scrollPositionID` (ThumbnailGridView.swift:60-63), which is owned by `@State private var gridScrollPositionID` in RAWLibraryWorkspaceView (WorkspaceShellViews.swift:316-317). Grepping the whole source tree, that binding is never written by anything except the ScrollView itself — there is no `onChange(of: library.selectionID)` anywhere that drives it. So the grid only ever *reports* its scroll offset; it is never *driven*. Meanwhile the filmstrip does exactly the right thing (ContentView.swift:2397-2411 scrolls the selection to `.center` on every selectionID change), so the two panes showing the same list disagree about where you are.


**なぜ問題か:** Arrow-key navigation is the spine of culling. Hold Down through a 1,200-photo shoot and the selection walks off the bottom of the grid within one screen; the grid sits still while the filmstrip races ahead. The same happens when the selection is changed from the filmstrip, from Develop, or by a filter change. The user has to hunt for their own selection with the scrollbar, which is the single most disruptive thing a photo grid can do.


**修正方針:** Keep `.scrollPosition(id:)` (it is what restores the offset on grid re-entry) and gate the programmatic assignment on visibility, using geometry already in scope. Package.swift pins `.macOS(.v14)`, so the macOS 15 visibility APIs (`onScrollTargetVisibilityChange`) are off the table; compute visibility arithmetically instead.

In ThumbnailGridView.body, inside the existing `GeometryReader { geo in ... }` (ThumbnailGridView.swift:37-64), the row grid already derives `columns = max(1, Int(geo.size.width / (cellSize + 12)))` at :39-42, cell height is `cellSize + 22` (:144) and row spacing is `RAWDeskTokens.Spacing.xSmall` (:51). Add to the ScrollView, alongside the existing `.scrollPosition` modifier:

    .onChange(of: library.selectionID) { _, newID in
        guard let newID,
              let targetIndex = visible.firstIndex(where: { $0.id == newID })
        else { return }
        let rowHeight = cellSize + 22 + RAWDeskTokens.Spacing.xSmall
        let rowsPerPage = max(1, Int(geo.size.height / rowHeight))
        let targetRow = targetIndex / columns
        let topRow = scrollPositionID
            .flatMap { id in visible.firstIndex(where: { $0.id == id }) }
            .map { $0 / columns } ?? 0
        guard targetRow < topRow || targetRow >= topRow + rowsPerPage else { return }
        // Keep one row of lead-in above the target so stepping down scrolls by
        // a row rather than slamming the cell to the top edge.
        let desiredTopRow = targetRow < topRow
            ? targetRow
            : max(0, targetRow - (rowsPerPage - 1))
        let desiredIndex = min(visible.count - 1, desiredTopRow * columns)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            scrollPositionID = visible[desiredIndex].id
        }
    }

Notes for the implementation:
- `columns` is currently a `let` inside the ScrollView's builder closure (:39-42). Hoist it to just inside the `GeometryReader` closure so the `.onChange` can read it, or recompute the same expression in the handler — do not duplicate the divisor `cellSize + 12` in two places without a shared helper.
- Leave `anchor: .top` at :62 as is. Because the assignment now targets a *row-aligned* item rather than the selected cell, `.top` produces the correct "scroll by a row" motion and the read-back semantics used for restore stay unchanged. Do not change it to `.center`.
- Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to match DevelopFilmstripView's treatment (ContentView.swift:2403-2410).
- Also wire the second call site: ContentView.swift:204 `ThumbnailGridView(library: library)` takes the defaulted `.constant(nil)` binding, so it gets neither restore nor follow. Give its parent a `@State private var gridScrollPositionID: PhotoAsset.ID?` and pass it, or accept that this grid stays unwired and say so.
- Alternative, if you prefer to mirror DevelopFilmstripView exactly: replace `.scrollPosition` with `ScrollViewReader` + `proxy.scrollTo(id, anchor: .center)` in an `onChange` plus an `onAppear`, add explicit `.id(asset.id)` on the cell (as the filmstrip does at ContentView.swift:2388), and delete the `scrollPositionID` parameter and `gridScrollPositionID` state. No test constructs `ThumbnailGridView(`, so the initializer change is safe. If you take this route, do not leave both mechanisms on the same ScrollView, and note it trades restore-last-offset for always-recentre-on-selection.


#### [高] Every single click in the grid is delayed by the double-click interval

**場所:** `Views/ThumbnailGridView.swift`:146


Cell selection is wired as `.gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)))` (ThumbnailGridView.swift:146-160). In an ExclusiveGesture the second gesture is only evaluated after the first *fails*, and a two-count TapGesture cannot fail until the system double-click interval has elapsed. Selection therefore never commits on mouse-up; it commits ~0.5 s later (up to 1 s, per the user's Mouse settings). The filmstrip has no such delay — it uses a plain `.onTapGesture` (ContentView.swift:2479-2492), so identical clicks in the two panes feel different.


**なぜ問題か:** Click-then-key is the core culling loop: click a frame, press X or 5. With a half-second selection lag the keystroke lands on the previous photo, which silently mis-rates it. Even when the user waits, a grid that responds half a second after the click reads as broken on every single click, which is the most-repeated interaction in the app.


**修正方針:** In /Users/0xt4/t4dano/Adobe/Sources/RAWDesk/Views/ThumbnailGridView.swift, replace the `.gesture(...)` block at lines 146-160 with two independent tap modifiers, keeping the same position in the modifier chain (after `.contentShape(Rectangle())` at 145, before `.contextMenu` at 161 and `.draggable` at 164):

```swift
.onTapGesture(count: 2) {
    library.select(asset.id)   // plain, no extending/range
    onOpenLoupe(asset.id)
}
.onTapGesture {
    selectThumbnail(asset.id)  // modifier-aware
}
```

Why this removes the delay: two separate `.onTapGesture` modifiers are independent recognizers rather than an ExclusiveGesture, so the count-1 recognizer succeeds on its own at mouse-up and never waits for the count-2 recognizer to fail. Selection commits on the first mouse-up, matching the filmstrip at ContentView.swift:2479.

Why the double-tap handler uses plain `library.select(asset.id)` rather than `selectThumbnail`: on a double-click the single-tap handler may also have fired for the first click, so the double-tap handler must be idempotent. `select(extending:)` toggles (LibraryViewModel.swift:3825-3830), so reusing `selectThumbnail` would make Command+double-click toggle twice. The plain call is idempotent on every path actually reachable here — non-extending assigns `selectedIDs = [id]`; `PhotoSurveyPlanner.adding` does `included.insert(id)` (WorkspaceMode.swift:442-443); `PhotoComparePlanner.settingCandidate` and `setReferenceActivePhoto` just set a candidate/active id. Keep the select call in the double handler (do not rely on the single handler having fired) — it is free given idempotency.

Notes for the reviewer: `.onTapGesture` is default-priority just like `.gesture`, and the modifiers stay above `.contextMenu` and `.draggable`, so right-click menu and drag precedence are unchanged. Secondary benefit: `selectThumbnail`'s `NSEvent.modifierFlags` read now happens synchronously on mouse-up instead of after the recognition delay, so Command/Shift-click no longer degrades to a plain click when the modifier is released quickly.


#### [高] `library.filtered` re-filters and re-sorts the whole catalogue about seven times per render pass

**場所:** `ViewModels/LibraryViewModel.swift`:312


`filtered` is an uncached computed property that allocates a filtered copy of `assets`, sorts it, and rebuilds stack ordering on every access (LibraryViewModel.swift:312-341). Every sort case bottoms out in `localizedStandardCompare` (LibrarySort.swift:40-56), an ICU collation call. One render of Library-grid-with-filmstrip touches it at ThumbnailGridView.swift:24, WorkspaceShellViews.swift:340, WorkspaceShellViews.swift:963 and again on :964, ContentView.swift:2310, :2372 and :2385 — seven full filter-plus-sort passes, and it is re-entered on every published change (each rating keystroke, each selection move, each search character).


**なぜ問題か:** At 1,000 photos that is roughly 10,000 ICU comparisons per pass, seven passes per frame, on the main actor. Rating a photo, typing in the search field, or arrowing through the shoot each pay the full cost, which is exactly the workload where a professional catalogue must stay fluid. The status bar even pays for it twice on two consecutive lines to print one count.


**修正方針:** Prefer a lazy dirty-flag cache over a @Published stored property — it preserves exact current semantics, avoids a second objectWillChange firing from inside another property's didSet, and does not require every mutation site to be a published setter (two of the real inputs are private non-@Published state).

In LibraryViewModel:
1. Add `private var filteredCache: [PhotoAsset]?` and `private func invalidateFiltered() { filteredCache = nil }`.
2. Rename the existing body of `filtered` (LibraryViewModel.swift:312-341) to `private func computeFiltered() -> [PhotoAsset]`, unchanged, and make the public accessor:
   `public var filtered: [PhotoAsset] { if let filteredCache { return filteredCache }; let value = computeFiltered(); filteredCache = value; return value }`
3. Call `invalidateFiltered()` from a `didSet` on every input actually read by computeFiltered — the claim's list is incomplete. Full set:
   - `assets` (line 26)
   - `filter` (line 44 — already has a didSet; add the call there)
   - `sort` (line 69) and `sortAscending` (line 74) — both already have didSet blocks
   - `catalogCollection` (line 86)
   - `activePhotoCollection` (line 89) — MISSING from the claim; it decides whether `sort.sorted` runs at all (line 334)
   - `photoStacks` (line 150)
   - `cullingReviewFilter` (line 161)
   - `cullingCriteria` (line 152) — feeds cullingDecision(for:) at line 1263
   - `cullingAnalysisByID` (line 206, private non-@Published) — add didSet or call invalidateFiltered() at each assignment: lines 1603, 1760, 1806
   - `duplicateOrderByID` (line 200, private non-@Published) — add didSet or call invalidateFiltered() at each assignment: lines 2051, 2063 (inside the loop; invalidate once after the loop instead), 2077
   Since the class is @MainActor, no locking is needed. A `didSet` on each stored property is the least error-prone form; for the two private dictionaries a `didSet { invalidateFiltered() }` also works and catches future mutation sites.
4. Add a regression test that mutates each of the above and asserts `filtered` reflects the change (particularly: toggling `cullingCriteria` while `catalogCollection == .assistedCulling`, and re-running the duplicate scan while `catalogCollection == .exactDuplicates`) — these are exactly the paths the claim's dependency list would have broken.

Optional follow-ups, independent of the above:
- The two count-only reads (WorkspaceShellViews.swift:963-964) also compute `library.filtered.count` twice in one expression; collapse to a single `let count = library.filtered.count` at the top of the body regardless of caching, and consider a `filteredCount` that skips `sort.sorted` entirely (the count is order-independent, since applyPhotoStacks emits one representative per collapsed stack regardless of input order).
- ContentView.swift:2372 and :2385 should bind `let visible = library.filtered` once at the top of DevelopFilmstripView.body, alongside the existing status construction at :2302, mirroring ThumbnailGridView.swift:24.
- MapSidebarView (ContextualWorkspaceSidebars.swift:184-194) reads `availableAssets` — itself a computed property over `filtered` — twice per body; bind once.


#### [高] Filmstrip cells are taller than the filmstrip can ever be, so every cell is clipped

**場所:** `Views/ContentView.swift`:2474


The filmstrip cell is pinned to `width: 116, height: 134` (ContentView.swift:2474-2477, cellWidth 116 + 18). The container spends 28 pt on the "Filmstrip" header row (ContentView.swift:2365-2368), ~1 pt on the Divider (:2370) and 8 pt on the LazyHStack's vertical padding (:2395). At the default library filmstrip height of 128 (RAWDeskDesignSystem.swift:158) that leaves 91 pt for a 134 pt cell; even dragged to the maximum 156 (:160) it leaves 119 pt. Develop is the same arithmetic (136 default / 168 max, :153-155). There is no height at which the cell fits, and a horizontal ScrollView clips rather than scrolls vertically.


**なぜ問題か:** The clipped 15-43 pt is the bottom of the cell: the filename label and the lower badge row (rating, colour label, stack position). The filmstrip is where you navigate while developing, and it is permanently showing amputated cells no matter how the user resizes it — the most visible "not refined" symptom in the whole shell.


**修正方針:** Derive the cell box from the space the ScrollView actually receives, and quantize the decode size so resizing does not thrash the thumbnail cache.

1. In `DevelopFilmstripView` (ContentView.swift:2295), delete `private let cellWidth: CGFloat = 116` (:2299).

2. Wrap the non-empty branch (ContentView.swift:2381-2411) in a `GeometryReader` placed *inside* the VStack, so `proxy.size.height` is exactly the leftover after the header and divider — do not measure the whole view and subtract the chrome by hand:

```swift
} else {
    GeometryReader { geo in
        let cellHeight = max(56, geo.size.height - RAWDeskTokens.Spacing.xSmall * 2)
        let cellWidth  = max(40, cellHeight - labelAllowance)   // labelAllowance = 18
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: RAWDeskTokens.Spacing.small) {
                    ForEach(library.filtered) { asset in
                        filmstripCell(asset, width: cellWidth, height: cellHeight)
                            .id(asset.id)
                    }
                }
                .padding(.horizontal, RAWDeskTokens.Spacing.small)
                .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            }
            .onAppear { scrollToSelection(proxy: proxy, animated: false) }
            .onChange(of: library.selectionID) { _, _ in
                scrollToSelection(proxy: proxy, animated: !reduceMotion)
            }
        }
    }
}
```

Keep 18 as the label allowance: `ThumbnailCellView` is `padding(4)` + square + `spacing(4)` + an 11 pt `Text` (ThumbnailCellView.swift:80, 112-122; `metadataSize = 11`, RAWDeskDesignSystem.swift:182), i.e. needed height = width + 4 + lineHeight ≈ width + 18. Define it as a named constant rather than a bare `+ 18`.

3. Change `filmstripCell` (ContentView.swift:2420) to take `width`/`height` parameters and replace the hard-coded frame at :2474-2477 with `.frame(width: width, height: height)`.

4. Critical detail the original proposal misses — do **not** pass `pixelSize: cellWidth * 2` from a continuously derived width. `ThumbnailCellView.loadID` is `"\(asset.id)|\(Int(pixelSize.rounded()))|..."` and drives `.task(id: loadID)` (ThumbnailCellView.swift:68-70, 125-127), so a per-point-derived pixelSize re-decodes every visible thumbnail on every frame of a divider drag. Quantize, e.g. `pixelSize: (cellWidth * 2 / 32).rounded(.up) * 32`, or simply pin it to the largest strip (`RAWDeskTokens.Size.developFilmstripMaximum * 2`) so the value never changes while dragging.

5. Apply the same derivation to `PhotoCompareFilmstripView` (PhotoCompareWorkspaceView.swift:721-790), `PhotoSurveyFilmstripView` (PhotoSurveyWorkspaceView.swift:409-478) and `PhotoReferenceFilmstripView` (PhotoReferenceWorkspaceView.swift:~926-968), which have the same fixed `112 x 134` cell in a 128 pt strip.

6. Optionally remove the "Filmstrip" header row (ContentView.swift:2313-2370). This is no longer required for correctness once the cell is derived, but at the 128 pt default it is the difference between a 73 pt and a 102 pt thumbnail — worth doing for legibility, and it also removes the empty-state asymmetry where the header shows but the strip is empty.

Verification: after the change, at every value in both `libraryFilmstripRange` and `developFilmstripRange` the cell's rendered height must equal `stripHeight - chrome - 8` and the filename `Text` must be fully visible; a snapshot or `sizeThatFits` assertion at 112/128/156 and 120/136/168 would lock this in, since no existing test covers strip geometry.


#### [高] Hover Pick / Reject / Rating controls are dead in every filmstrip

**場所:** `Views/ThumbnailCellView.swift`:399


`onQuickPick`, `onQuickReject` and `onQuickRating` default to empty closures (ThumbnailCellView.swift:56-58), but `quickActionLayer` renders whenever the cell is hovered and the file is present (:399), with tooltips "Pick photo (P)" and "Reject photo (X)" (:412, :424). Only ThumbnailGridView supplies real handlers (ThumbnailGridView.swift:125-142). DevelopFilmstripView (ContentView.swift:2423-2473), PhotoReferenceFilmstripView (PhotoReferenceWorkspaceView.swift:926), PhotoSurveyWorkspaceView.swift:422, PhotoCompareWorkspaceView.swift:734 and MapWorkspaceView.swift:663 all omit them, so hovering any filmstrip cell pops up three buttons that do nothing at all.


**なぜ問題か:** A control that appears on hover, shows a keyboard-shortcut tooltip, and then silently discards the click is worse than no control: the user believes the photo was rejected and moves on. On a 116 pt filmstrip cell the three 28 pt buttons plus padding also blanket almost the whole thumbnail while you are trying to look at it.


**修正方針:** The gating half of the proposed fix is right; the layout half needs correcting before it is implemented.

1. Gate the overlay on wiring (do this).
   - `ThumbnailCellView.swift:56-58`: change to `var onQuickPick: (() -> Void)? = nil`, `var onQuickReject: (() -> Void)? = nil`, `var onQuickRating: ((Int) -> Void)? = nil`.
   - `:399`: change the condition to `if isHovering, !asset.catalogMissing, let onQuickPick, let onQuickReject, let onQuickRating {` and use the unwrapped locals for `Button(action:)` and `onQuickRating(rating)` at :403, :415, :440. Binding all three together keeps the cluster visually intact; if a partially-wired host is ever wanted, unwrap each independently and wrap each control in its own `if let`.
   - `ThumbnailGridView.swift:125-142` needs no change — trailing closures still bind to optional closure parameters.
   - No other call site needs touching; the five unwired sites lose the overlay by taking the `nil` default.

2. Do NOT simply delete the `.padding(.bottom, ...)` at :470. It exists to keep the cluster off `reviewStateLayer`, whose Picked/Rejected/Edited/rating/color-label badge rows occupy the bottom of the same ZStack (:279-395). Removing it makes the quick actions sit directly on top of those badges in the grid, where the feature actually works. What is wrong is the constant, not the offset: `Size.primaryButtonHeight` (34) is a toolbar-button token with no relationship to the badge strip. Replace the magic number by measuring: give `reviewStateLayer`'s inner `VStack` a `.background(GeometryReader { ... })` writing its height into a `@State private var reviewStripHeight: CGFloat = 0` via a preference key, then use `.padding(.bottom, reviewStripHeight + RAWDeskTokens.Spacing.xSmall)`. If that is more machinery than wanted, at minimum introduce a named token (e.g. `Size.thumbnailBadgeStripHeight`) so the offset stops borrowing an unrelated constant.

3. For the small-cell suppression, do NOT gate on the `pixelSize` property. It is not a consistent proxy for rendered point size across hosts: `ThumbnailGridView` passes `library.thumbnailPixelSize` while the cell renders at `thumbnailPixelSize / 1.6`; the filmstrips pass `cellWidth * 2`; `MapWorkspaceView.swift:663` passes a hard-coded `220` into a `124×142` frame. Measure the real geometry instead — wrap the ZStack's `.overlay`/background in a `GeometryReader` and require roughly `proxy.size.width >= 108` (the 100pt cluster plus breathing room) and `proxy.size.height >= reviewStripHeight + 44 + Spacing.xSmall` before showing `quickActionLayer`. This also protects the grid at its 128px slider floor, where the cluster is currently wider than the cell.

4. Add a regression test alongside the existing view tests asserting that a `ThumbnailCellView` constructed without the quick-action arguments has `onQuickPick == nil` (or an equivalent snapshot/hit-test), so a future host cannot reintroduce a dead overlay by omission. Update `Docs/RAWDesk_UI_REQUIREMENT_TRACEABILITY.md:81` (L-09) to state that the quick actions are grid-only, or wire the filmstrips, rather than leaving the row citing the layer's mere existence.


### 全体構造・文言


#### [高] Four descendant views overwrite the window title that ContentView deliberately reserves for the catalog name

**場所:** `Views/RAWLibrarySidebarView.swift`:155


ContentView.swift:457 sets `.navigationTitle(library.displayTitle)` and carries an explicit comment (ContentView.swift:454-456) that repeating the module name in the title "said the same word twice and spent the title on the one thing already on screen; the catalog or folder name is what the title should carry." Four descendants in the live (non-legacy) hierarchy set the module name anyway: RAWLibrarySidebarView.swift:155 `.navigationTitle("Library")`, ContextualWorkspaceSidebars.swift:150 `.navigationTitle("People")`, ContextualWorkspaceSidebars.swift:330 `.navigationTitle("Map")`, and PeopleWorkspaceView.swift:759 `.navigationTitle("People Details")`. All four are reached from the redesigned path (ContentView.swift:797, :800, :804, :881). Separately, LibraryViewModel.swift:447-449 makes `displayTitle` itself return "People" in People mode, so even the intended title repeats the picker. Only DevelopSidebarView was cleaned up (ContentView.swift:2239-2241).


**なぜ問題か:** The title bar is the one place that can tell a photographer which catalog, collection, or folder they are in — the module is already named, in bold, by the picker directly beneath it. Naming the module twice while never naming the shoot is the exact defect the codebase already documents as fixed, so the app contradicts its own stated standard in three of four modules.


**修正方針:** Delete four modifiers, keeping ContentView.swift:457 as the sole title owner:
1. RAWLibrarySidebarView.swift:155 — remove `.navigationTitle("Library")` (leave `.listStyle(.sidebar)`, `.rawPanelScrollBackground()` and the four `.animation` modifiers that follow at 156-179 intact).
2. ContextualWorkspaceSidebars.swift:150 — remove `.navigationTitle("People")` from `PeopleSidebarView`.
3. ContextualWorkspaceSidebars.swift:330 — remove `.navigationTitle("Map")` from `MapSidebarView`.
4. PeopleWorkspaceView.swift:759 — remove `.navigationTitle("People Details")`. Note this modifier lives in `PeopleInspectorView`, not `PeopleWorkspaceView`; leave the `.onAppear`/`.onChange` at 760-763 attached. This is the one site with a defensible reading, because ContentView:264 renders `PeopleInspectorView` in the legacy `NavigationSplitView`'s `detail:` column, where a detail-column title is the conventional macOS window-title source. Deleting it changes legacy behavior too, and that is intended: :457 is applied to `primaryWorkspace`, which wraps both the legacy and redesigned branches, so the legacy window title falls back to `displayTitle` rather than going blank. Do not stop at :759 thinking it is a legitimate column title.

Match the existing convention when removing: DevelopSidebarView (ContentView:2239-2241) left a short comment where its title used to be. Doing the same at each of the four sites keeps the next reader from re-adding them.

LibraryViewModel.swift: in `displayTitle` (starts at :437), delete only the `if workspaceMode == .people { return "People" }` early return at :444-446. Keep the `Reference View` / `Compare` / `Survey` early returns — those are transient states that the module picker does not name, so they are not the same defect. People mode then falls through `activePhotoCollection?.name ?? activeSavedCollection?.name ?? catalogCollection?.name ?? rootURL?.lastPathComponent ?? importDisplayTitle ?? "RAWDesk"`, so the chain always terminates. Blast radius is small and verified: the only consumers are ContentView.swift:457 and CaptureTimeAutoStackView.swift:44 (which interpolates it into "Uses every unstacked photo in ...", a Library-mode sheet, so it is unaffected in practice and reads better without the People special case). The only test touching `displayTitle` is Tests/RAWDeskTests/RAWDeskTests.swift:15606, which asserts `"Last Import"` and does not exercise People mode — no test update needed.


#### [高] The toolbar's "More" menu re-lists controls that are already on the same toolbar

**場所:** `Views/ToolbarContent.swift`:278


The ellipsis Menu at ToolbarContent.swift:278-305 contains `workspaceModeActions` (:338-352 — "Library", "Develop", "People", "Map"), which is exactly the principal `RAWWorkspaceSwitcher` sitting a few centimetres to its left at :249-253; and `panelActions` (:438-469 — "Show/Hide Sidebar", "Show/Hide Inspector"), which are exactly the two icon buttons at :198-224 and :307-333 in the same toolbar. Every remaining item (`photoViewActions`, :355-435) duplicates menu-bar commands: Rotate Left/Right (RAWDeskApp.swift:591-604), Zoom In/Out, Fit to Window, Actual Size (RAWDeskApp.swift:561-575), Compare/Survey/Reference (RAWDeskApp.swift:508-545). The menu's own label is the non-committal "More" with help text "More workspace and photo actions" (:293-298).


**なぜ問題か:** A professional toolbar is a short list of things you reach for constantly. This one offers the same four module buttons twice within one bar and the same two panel toggles twice within one bar, which teaches the user that the visible controls are not authoritative and that the real controls are hidden behind an unnamed ellipsis. The menu-bar duplicates additionally mean the shortcuts (⌘[ , ⌘] , ⌘0 …) never appear next to the actions in the ellipsis menu, so the menu actively hides the faster path.


**修正方針:** Narrow the fix to the genuinely duplicated items and keep the Menu:

1. Delete the `workspaceModeActions` invocation at ToolbarContent.swift:279 and the computed property at :337-352 (the `@ViewBuilder` line through the closing brace). The principal `RAWWorkspaceSwitcher` (:249-253) is permanently resident per TB-01 and the same four destinations are ⌘1-⌘4 in the menu bar.

2. In `panelActions` (:437-469), delete only the Sidebar button (:439-445) and the Inspector button (:446-452). Keep the Filmstrip button (:453-461) and Hide/Restore All Panels (:462-468) — neither is on the toolbar. Keep the `panelActions` invocation at :283.

3. Keep `photoViewActions` (:354-435) and its invocation at :281 — TB-05 explicitly requires these in the overflow menu and names this property as its evidence.

4. Keep the Menu at :278-305 and the legacy Toggle (:285-291); MIG-02 cites the toolbar toggle as its evidence.

5. Collapse the divider structure now that the first block is gone: the body becomes `photoViewActions / Divider() / panelActions / Divider() / Toggle(...)`, i.e. remove the leading `Divider()` at :280 and shift the remaining items up. Verify no orphan leading divider renders at the top of the menu.

6. Optionally relabel the menu from the non-committal "More" (:293-296, help text :298) to something that names what is inside it now — e.g. "Photo and Panel Actions" / "View Actions" — since after step 1 the menu no longer contains workspace switching but the help string still says "More workspace and photo actions".

Follow-up, not part of this fix: align the overflow titles and disable predicates with the menu-bar equivalents ("Survey Selected Photos" vs "Survey Photos", "Open Reference View" vs "Open in Reference View"; zoom disabled on `selectionID == nil` in the menu vs `surveyState != nil` in the menu bar; Rotate disabled in the menu but not in the menu bar).

After editing, update Docs/RAWDesk_UI_REQUIREMENT_TRACEABILITY.md only if a cited artefact name changes; with this narrowed fix TB-01, TB-05 and MIG-02 all keep their evidence intact.


#### [高] A developer rollback switch, "Use Legacy Layout", ships in the toolbar and keeps ~200 lines of a second, unreachable UI alive

**場所:** `Views/ToolbarContent.swift`:285


ToolbarContent.swift:285-291 puts `Toggle("Use Legacy Layout", isOn: $useLegacyLayout)` into the user-facing toolbar menu, with the help string "Temporary rollback switch for this redesign phase". The label names an internal build state ("legacy"), and the help text addresses the development team, not a photographer. It is backed by `@AppStorage("rawdesk.ui.useLegacyLayout")` (ContentView.swift:68-69) and gates a whole parallel layout at ContentView.swift:445-451, whose exclusive supporting code is `legacyPrimaryWorkspace` (:485-525), `workspaceContent` (:116-210), and `workspaceDetail` (:261-290).


**なぜ問題か:** Lightroom Classic does not offer to switch back to last year's window layout. Shipping the toggle means every user can silently land in a second, less-finished UI with different panels and no way to tell which one they are in — and it forces two layouts to be maintained and tested forever. It is the single clearest signal in the chrome that the app is mid-refactor rather than finished.


**修正方針:** Delete the rollback switch and the whole legacy branch it guards, in this order:

1. ToolbarContent.swift — remove the trailing `Divider()` at :280 (the one immediately before the toggle; keep the two earlier ones) together with the `Toggle`/`.help` at :285-291, and remove `@Binding var useLegacyLayout: Bool` at :174.

2. ContentView.swift — remove the `useLegacyLayout: $useLegacyLayout,` argument at :472 and the `@AppStorage("rawdesk.ui.useLegacyLayout") private var useLegacyLayout = false` at :68-69.

3. ContentView.swift:445-452 — collapse `primaryWorkspace` to `redesignedPrimaryWorkspace` with no `Group`/`if`, keeping the `.navigationTitle` / `.toolbar` / `.searchable` modifiers and the explanatory comment at :453-456 attached to it.

4. Delete these now-unreferenced members (verify with a grep after each): `legacyPrimaryWorkspace` (ContentView.swift:485-525), `workspaceContent` (:116-210), `developWorkspaceContent` (:212-259), `workspaceDetail` (:261-290), `private struct WorkspaceLoadingView` (:1834-1845), `private struct WorkspaceEmptyView` (:1847-1878).

5. Delete `PhotoInspectorView` and its `private enum InspectorMode` — Sources/RAWDesk/Views/PhotoInspectorView.swift lines 1-48 — but keep the file, since `AssistedCullingInspectorView` (from :51) is still live.

6. Delete the whole file Sources/RAWDesk/Views/LibrarySidebarView.swift (2,388 lines; sole call site was ContentView.swift:510). SwiftPM globs the directory so Package.swift needs no change, but RAWDesk.xcodeproj/project.pbxproj references it explicitly at lines 48, 121, 296, and 530 — remove all four or the Xcode build breaks.

Notes for the implementer:
- Tests/RAWDeskTests/UIStateContractTests.swift enumerates Sources/RAWDesk/Views via contentsOfDirectory (:270-274) and only applies per-file assertions inside `if file.lastPathComponent == "…"` guards; none names LibrarySidebarView.swift or ContentView.swift's legacy members, so deletion does not break the contract suite. The ToolbarContent.swift guard only requires `RAWWorkspaceSwitcher(`, which survives.
- The `rawdesk.ui.useLegacyLayout` UserDefaults key is left behind on existing installs. Harmless (nothing reads it once the property is gone), and `configureInitialLayout` does not touch it — no migration needed.
- Docs assert this switch as a shipped deliverable and must be updated in the same change: Docs/RAWDOCK_IMPLEMENTATION_STATUS.md:124-126 (its "Legacy layout / Deprecated" row, whose `ToolbarContent.swift:250` citation is already stale) and Docs/RAWDesk_UI_REQUIREMENT_TRACEABILITY.md:212, where requirement MIG-02 ("1 phase分のLegacy rollback") is marked PASS-SOURCE precisely because this toggle exists. Removing the toggle retires a tracked requirement, so confirm with the user that the redesign phase is over before deleting rather than silently flipping MIG-02 to unmet.


#### [高] Menu commands bound to unmodified c, n and backslash bypass the app's own text-field guard

**場所:** `App/RAWDeskApp.swift`:515


Four commands take bare or near-bare keys as menu key equivalents: RAWDeskApp.swift:515 `.keyboardShortcut("c", modifiers: [])` (Compare), :528 `.keyboardShortcut("n", modifiers: [])` (Survey), :541 `.keyboardShortcut("r", modifiers: [.shift])` (Reference), :577 `.keyboardShortcut("\\", modifiers: [])` (Toggle Original). AppKit dispatches main-menu key equivalents before the key window's first responder sees the keystroke, so these do not pass through KeyboardHandler's `isEditingText` guard (KeyboardHandler.swift:51-53, :161-186) — that guard only protects the keys KeyboardHandler itself consumes, and c, n, r and backslash are not in its switch (KeyboardHandler.swift:95-147). The project already documents this exact defect class for its own keys: "or bare photo shortcuts such as P, U, F, X, and 0...9 will consume characters typed into sheet text fields" (KeyboardHandler.swift:43-46). The affected fields are ordinary main-window inputs, not sheets: "Person name" (PeopleWorkspaceView.swift:811), "Collection name" (LibrarySidebarView.swift:987), "Keyword name" (LibrarySidebarView.swift:1988), and the map search field (MapWorkspaceView.swift:188).


**なぜ問題か:** Typing a person's name that contains a c or an n, with two or more photos selected, drops the user into Compare or Survey mid-word and loses the keystroke. Naming things — people, collections, keywords — is core cataloguing work, and the app's own comment shows the team already considers this unacceptable for its other bare keys. One keypress in the Person name field confirms it.


**修正方針:** Keep the published shortcuts; move them behind the existing guards instead of remapping to ⌥⌘.

1. In Sources/RAWDesk/App/RAWDeskApp.swift, delete the `.keyboardShortcut` modifiers on lines 515, 528, 541 and 577. Keep the Buttons and their `.disabled(...)` conditions so the commands stay in the View menu; if the printed equivalent matters, bake it into the title (e.g. "Compare Photos  C").

2. In Sources/RAWDesk/Views/KeyboardHandler.swift, add four closures plus their gate booleans to the struct (alongside `canToggleLoupe` at line 19): `onToggleCompare`/`canToggleCompare`, `onToggleSurvey`/`canToggleSurvey`, `onToggleReference`/`canToggleReference`, `onToggleOriginal`/`canToggleOriginal`. Wire them in the `keyboardHandler` factory at Sources/RAWDesk/Views/ContentView.swift:293 to `library.toggleCompare()` / `toggleSurvey()` / `toggleReferenceView()` / `viewer.toggleOriginal()`, with gates mirroring the menu exactly: `library.compareState != nil || library.canStartCompare`, `library.surveyState != nil || library.canStartSurvey`, `library.referenceState != nil || library.canStartReference`, and `library.surveyState == nil` for Toggle Original.

3. Add cases to the `charactersIgnoringModifiers` switch after line 145 (before `default: break`), which sits below the `isEditingText`/`isAdjustingValue` early-returns at lines 51-56 — that is the entire point of the move. Case semantics matter: use `case "c"`, `case "n"`, `case "R"`, `case "\\"` — lowercase-only for c and n, uppercase-only for R. Do not use the `"f", "F"` both-cases style used elsewhere in that switch: line 65 already returns the event early when command/control/option are held, so shift is the only reachable modifier, and `"c"` therefore means unshifted while `"R"` means shift-held, reproducing the current menu semantics precisely. Adding `"C"`/`"N"` would newly bind ⇧C/⇧N, and adding `"r"` would newly bind bare r. Each case should check its gate boolean and `return nil` only when it actually acts, otherwise `break` so the event falls through.

4. Constrain the new cases to the library window: `.background(keyboardHandler)` is on ContentView's root (ContentView.swift:1250) and `addLocalMonitorForEvents` is app-wide, so sheets and the Settings window would otherwise reach these actions. Add `eventWindow === self.window` to the new cases, the way the loupe-toggle path already does at line 81.

5. Extend KeyboardHandlerTests to cover the new keys under a text-editing first responder (the suite already backs traceability item K-06), and update the README shortcut table only if the printed equivalents change.


### デザインシステム


#### [高] "Selected" surface is painted with seven different opacities of the same accent

**場所:** `Views/EditingInspectorView.swift`:673


The selected state of a row/pill/card is drawn everywhere as `ColorToken.selection` at an ad-hoc opacity, and no two authors picked the same number. Within the Masks section alone, the mask row is `selection.opacity(0.18)` (EditingInspectorView.swift:673, and again at 1129) while the mask-operation row stacked directly beneath it is `selection.opacity(0.16)` (EditingInspectorView.swift:3247, 3847). Elsewhere: 0.20 on the Tone Curve region segments (EditingInspectorView.swift:5804), 0.16 on the Compare candidate pane chip (PhotoCompareWorkspaceView.swift:328) and Reference active chip (PhotoReferenceWorkspaceView.swift:479), 0.13 on the colour-label filter button (PhotoColorLabelView.swift:120, ColorLabelSetEditorView.swift:107), 0.12 on the import-method card (PhotoImportView.swift:740) and the welcome drop zone (WorkspaceShellViews.swift:150), 0.10 on the Soft Proof card (SoftProofControlsView.swift:324), 0.08 on the sync-group row (PhotoSyncSettingsView.swift:108). The resting (unselected) companion fill is equally ad-hoc: `textSecondary.opacity(0.08)` (EditingInspectorView.swift:674), `0.07` (EditingInspectorView.swift:3248), `0.05` (SoftProofControlsView.swift:325), and `Color.clear` (EditingInspectorView.swift:5805). RAWDeskTokens.ColorToken (RAWDeskDesignSystem.swift:5-127) defines `selection` but nothing for the selected surface derived from it, so every call site invents one.


**なぜ問題か:** Selection is the single most-read state in a cataloguing app, and the app currently signals it at seven different intensities. The 0.18/0.16 pair inside the Masks panel is visible simultaneously on one screen: two lists of the same kind of thing, selected, at two different brightnesses. A photographer reads that as noise, or worse as a meaningful distinction that does not exist. Lightroom Classic uses exactly one selected-surface value.


**修正方針:** Add two derived tokens to RAWDeskTokens.ColorToken in Sources/RAWDesk/Views/RAWDeskDesignSystem.swift, immediately after `selection` (line 47), following the file's convention of a doc comment stating the rationale:

    /// The wash behind a selected row, pill, or segment. Derived from
    /// `selection` so the selected state is the same weight everywhere;
    /// call sites must not invent their own alpha.
    static let selectedSurface = selection.opacity(0.16)
    /// The unselected companion to `selectedSurface`, for controls whose
    /// resting state is a filled row rather than a transparent one.
    static let restingSurface = textSecondary.opacity(0.07)

Then replace, in this order:

A. Selected/resting PAIRS where both halves are low-alpha washes — swap both:
 - EditingInspectorView.swift:673/674 (0.18 / textSecondary 0.08) — mask row
 - EditingInspectorView.swift:1129/1130 (0.18 / textSecondary 0.08) — spot-removal row
 - EditingInspectorView.swift:3247/3248 (0.16 / textSecondary 0.07) — mask primary operation
 - EditingInspectorView.swift:3847/3848 (0.16 / textSecondary 0.06) — mask range operation
 - SoftProofControlsView.swift:324/325 (0.10 / textSecondary 0.05). Note this card also carries `selection.opacity(0.30)` as a strokeBorder just below (~line 333); leave that stroke alone, it is a border not a surface.

B. Selected-only sites whose resting state is `Color.clear` — swap the selected half, keep `Color.clear`:
 - EditingInspectorView.swift:5804 (0.2) — tone-curve region segments
 - PhotoColorLabelView.swift:120 (0.13)
 - ColorLabelSetEditorView.swift:107 (0.13)
 - PhotoSyncSettingsView.swift:108 (0.08)

C. The site the claim missed — EditingInspectorView.swift:2403-2406, the auto-sync summary card, currently `selection.opacity(library.isAutoSyncEnabled ? 0.16 : 0.08)`. Rewrite as a ternary over the two tokens:
    library.isAutoSyncEnabled
        ? RAWDeskTokens.ColorToken.selectedSurface
        : RAWDeskTokens.ColorToken.restingSurface
(or keep `Color.clear` for the off state if a resting wash on a summary card is unwanted — but do not leave the inline `opacity(ternary)` form, it hides the literal from any future grep).

D. Sites to change ONLY if you accept the semantic merge, otherwise leave with a comment:
 - PhotoCompareWorkspaceView.swift:328 (`roleBackground`) and PhotoReferenceWorkspaceView.swift:479 (`badgeBackground` for `.active`) are role tints, not selection: their companion branch is opaque `controlElevated`, not a wash. Both are already 0.16, so swapping the literal for `selectedSurface` is a no-op visually and is worth doing for greppability; do NOT touch the `controlElevated` branches.
 - PhotoImportView.swift:740 (0.12, resting `controlElevated.opacity(0.55)`) is a card, not a row — 0.12→0.16 is a real visible change on a large surface. Acceptable, but call it out.

E. Do NOT change:
 - WorkspaceShellViews.swift:150 — this is `isDropTargeted`, a drag-hover state whose resting branch is opaque `panel`. It is not a selected surface; either leave it at 0.12 or introduce a separate `dropTargetSurface` token. Merging it into `selectedSurface` conflates hover with selection.
 - EditingInspectorView.swift:1688 (0.55 stroke), ThumbnailCellView.swift:636 (0.9 solid badge), AutoImportSettingsView.swift:57 (icon tile), and — also decorative, and not named in the claim — PhotoSyncSettingsView.swift:35 (icon tile 0.12), MetadataInspectorView.swift:736 (keyword capsule 0.12), PhotoImportView.swift:1913 (XMP badge capsule 0.12), ImagePreviewView.swift:791/857/874 (canvas overlay drawing). A naive grep-and-replace of `selection.opacity(0.12)` would wrongly catch four of these.

Finally: Tests/RAWDeskTests/UIStateContractTests.swift enumerates the ColorToken roster around lines 169-254 and enforces the "no raw color literal" rules around lines 395-420. Adding the two tokens does not break those, but adding roster assertions for `selectedSurface`/`restingSurface` there keeps the contract test honest, and a follow-up assertion that no Views file contains the fragment `ColorToken.selection.opacity(0.1` would prevent the drift from reappearing.


#### [高] RAWStateBadge is bypassed by hand-rolled capsule badges, including inside the same view

**場所:** `Views/PhotoImportView.swift`:1908


`RAWStateBadge` (RAWDeskDesignSystem.swift:589-615) is the app's badge: `Typography.badge` (10pt medium), `Spacing.xSmall` horizontal and vertical padding, `RoundedRectangle(cornerRadius: Radius.control)`. It is used 15+ times. But six places re-implement a badge by hand with a `Capsule()` and different metrics. PhotoImportView is the clearest case: the import-method card uses the real component (PhotoImportView.swift:704), while a file row in the same sheet hand-rolls the XMP marker as `Typography.badge` + xSmall padding + `selection.opacity(0.12)` + `Capsule()` (PhotoImportView.swift:1908-1916) — a badge that differs from the component beside it only in corner shape and tint. The others use a heavier font as well: the Compare role chip (PhotoCompareWorkspaceView.swift:361-370) and the Reference role chip (PhotoReferenceWorkspaceView.swift:569-582) are `Typography.sectionHeader` (12pt semibold) with `Spacing.small`/`xSmall` padding in a Capsule; the grid's "N selected" overlay is the same 12pt semibold Capsule (ThumbnailGridView.swift:67-75); the canvas preview badge is `Typography.badge` with `Spacing.small`/`xSmall` padding in a Capsule (ImagePreviewView.swift:522-530).


**なぜ問題か:** Status badges are the app's status vocabulary — they appear on thumbnails, on the canvas, in the inspector, and in Import. Right now the same class of object is a 6pt-radius rectangle with 10pt text in some places and a pill with 12pt semibold text in others, and both idioms appear within a single sheet and within a single workspace header. This is the most literal instance of "a different designer's work from the component beside it".


**修正方針:** Adopt the component, but extend it first so the swap is faithful rather than a restyle.

Step 1 — extend `RAWStateBadge` (Sources/RAWDesk/Views/RAWDeskDesignSystem.swift:557-615):
- Add a soft/tinted variant. Either a new case `case accentSoft` on `RAWBadgeTone` (foreground `ColorToken.selection`, background `ColorToken.selection.opacity(0.16)`), or a `var prominence: RAWBadgeProminence = .solid` on `RAWStateBadge` where `.soft` renders `tone.background.opacity(0.16)` with `tone.background` as the foreground. This is required — without it four of the five call sites change from tint to solid fill.
- Add a size knob for the header-scale chips, e.g. `var emphasis: RAWBadgeEmphasis = .compact` (`Typography.badge` + xSmall/xSmall) vs `.prominent` (`Typography.sectionHeader` + `Spacing.small`/`xSmall`), so the pane-header chips and the grid overlay keep their current weight. If the design intent is genuinely to shrink them to 10pt, say so explicitly in the commit — it is a visible change to three surfaces, not a no-op cleanup.

Step 2 — replace the five call sites (all lose only the Capsule corner shape once the above exists):
- PhotoImportView.swift:1908-1916 → `RAWStateBadge(text: "XMP", tone: .accent, prominence: .soft)` (drops the `Text`/`.font`/two `.padding`/`.background` chain; keeps the 0.12→0.16 tint, a negligible shift).
- PhotoCompareWorkspaceView.swift:362-370 → `RAWStateBadge(text: role.name, systemImage: role.systemImage, tone: role == .candidate ? .accent : .neutral, prominence: role == .candidate ? .soft : .solid, emphasis: .prominent)`; then delete the now-unused `roleBackground` (line 326) and keep `roleColor` (line 320) only if the border at line 347 still needs it — it does, so keep it.
- PhotoReferenceWorkspaceView.swift:569-582 → same shape, `tone: role == .active ? .accent : .neutral`, `emphasis: .prominent`; the label text is conditional (`"Active · Before"` when `viewer.isShowingOriginal`) so pass the computed string, not `role.name`. `ReferencePhotoRole.badgeBackground` (473-481) becomes dead — remove it; `emphasisColor` is still used at 521/634/655, keep it.
- ThumbnailGridView.swift:67-75 → `RAWStateBadge(text: "\(library.selectedIDs.count) selected", emphasis: .prominent)` (neutral is an exact color match today), keeping the outer `.padding(Spacing.small)` that insets it from the corner.
- ImagePreviewView.swift:522-530 `previewBadge(_:systemImage:)` → have the helper return `RAWStateBadge(text: text, systemImage: systemImage)`; keep the helper so the 9 call sites at 129-152 are untouched. This one is already an exact neutral match apart from horizontal padding (small→xSmall) and corner shape.

Step 3 — leave `Capsule()` at ImagePreviewView.swift:1044 (on-image guide marker) and MetadataInspectorView.swift:737 (interactive keyword chip with an embedded remove button) alone, and note both as deliberate exclusions.

Verify with a build plus the existing token tests under Tests/RAWDeskTests (no test currently references `RAWStateBadge` or `RAWBadgeTone`, so nothing should break; consider adding one asserting the two new variants' colors).


### People の負荷


#### [高] Every People scan re-evaluates the app root view and the Library sidebar once per analyzed photo

**場所:** `Views/ContentView.swift`:14


ContentView owns the People view model as `@StateObject private var people = PeopleViewModel()` (ContentView.swift:14), and LibrarySidebarView takes `@ObservedObject var people: PeopleViewModel` (LibrarySidebarView.swift:88) solely to compute a badge number (`displayedPeopleCount`, LibrarySidebarView.swift:112-116). PeopleViewModel publishes `scanProgress` (PeopleViewModel.swift:10-11), which is written once per photo by `setProgress` (PeopleViewModel.swift:516-522) in response to PeopleAnalyzer's per-candidate progress callback (PeopleAnalyzer.swift:53-61). SwiftUI invalidates a view on any `objectWillChange` from an observed object, not only on the properties it reads. So while a People scan runs, the root ContentView body and the LibrarySidebarView body are re-evaluated once per analyzed photo -- and LibrarySidebarView's body recomputes `collectionTree` recursively (LibrarySidebarView.swift:118) and re-groups and re-sorts saved locations (LibrarySidebarView.swift:95-110) each time.


**なぜ問題か:** This is the clearest case of People imposing cost on non-People UI. The Library sidebar has no People content beyond one integer, yet it re-renders on People's scan cadence. For a 5,000-photo scan that is 5,000 sidebar body evaluations, each rebuilding the collection tree, while the user may be doing something else entirely.


**修正方針:** Fix the source of the churn first; the sidebar cleanup is secondary and legacy-only.

1. PRIMARY — coalesce progress publishes in `PeopleViewModel.setProgress` (Sources/RAWDesk/ViewModels/PeopleViewModel.swift:516-522). Keep the generation guard, then only assign `scanProgress` when the update is worth a render: add `private var lastProgressPublish: ContinuousClock.Instant?` (or `CFAbsoluteTime`) and publish when the elapsed time since the last publish exceeds ~100 ms, OR when `progress.completed == progress.total`, OR when `progress.total == 0`. Reset `lastProgressPublish = nil` in `beginScan` (line ~226, alongside `scanProgress = PeopleScanProgress()`) and wherever `scanProgress = nil` is set (lines 325, 343, 364, 375) so the terminal state always lands. This caps root-body invalidation at ~10/s instead of once per candidate, and it helps the default layout, which the audit's proposed fix does not. No tests assert progress cadence.

2. SECONDARY (only if you also want the legacy sidebar clean) — make the notification correct before removing the dependency. In `PeopleViewModel.performCatalogChange` (line 523-533), after a successful `try reloadCatalogState()`, post `NotificationCenter.default.post(name: .rawDeskPeopleAnalysisDidChange, object: nil)`. `PeopleAnalysisLifecycleModifier` (ContentView.swift:2545-2551) already routes that to `people.refreshFromCatalog()` + `library.refreshCatalogOverview()`, so `library.catalogSummary.peopleCount` becomes unconditionally correct. Check for a re-entrancy loop first: `refreshFromCatalog()` must not itself post the notification, or the two will ping-pong. Only after that is in place: replace `displayedPeopleCount` (LibrarySidebarView.swift:112-116) with `library.catalogSummary.peopleCount`, delete `@ObservedObject var people` (line 88), delete `people.startIfNeeded()` (line 489 — redundant, `library.showPeople()` sets `workspaceMode = .people` and ContentView.swift:1218-1221 calls it on that change; `startIfNeeded` is idempotent via its `hasStarted` guard), and drop the `people:` argument at ContentView.swift:510-512.

Do NOT do step 2's sidebar edits without the `performCatalogChange` notification post — that is the regression the audit's fix as written would introduce.


#### [高] People refresh does a full synchronous catalog load and O(n^2) face clustering on the main actor

**場所:** `ViewModels/PeopleViewModel.swift`:535


`reloadCatalogState()` (PeopleViewModel.swift:535-549) runs on `@MainActor` (class annotation, line 4) with no `await`. It calls `catalogStore.catalogPeople()`, `catalogStore.peopleAnalysisCandidates(...)` and `catalogStore.entries(for: .allPhotos)` -- all three are `try queue.sync` blocking calls (CatalogStore.swift:1285, 565). `entries(for: .allPhotos)` materialises the entire catalog into `assetsByID` for the sole purpose of resolving display filenames (`filename(for:)`, PeopleViewModel.swift:148-150). It then calls `rebuildSnapshot()` (551-558), which runs `PeopleAnalyzer.makeSnapshot` -> `suggestedClusters` (PeopleAnalyzer.swift:216-274): that NSKeyedUnarchivers a `VNFeaturePrintObservation` per face (PeopleAnalyzer.swift:276-287) and computes pairwise distances against every member of every existing cluster -- also on the main actor. `rebuildSnapshot()` additionally re-runs on every `groupingSensitivity` change via `didSet` (PeopleViewModel.swift:26-28). This path is reached from ContentView.swift:2545-2551 whenever `.rawDeskPeopleAnalysisDidChange` is posted, which LibraryViewModel does after import (LibraryViewModel.swift:834-838 and 1113-1118).


**なぜ問題か:** The main thread is the UI thread. A whole-catalog SQLite read plus per-face unarchiving and quadratic distance computation stalls the entire app, including the Library grid and Develop, not just the People workspace. Materialising every catalog entry to look up filenames makes the cost look gratuitous rather than inherent to the feature.


**修正方針:** Three changes, in increasing order of cost. The first two are independent of any concurrency work.

1) Delete the redundant full-catalog read (PeopleViewModel.swift:543-547). Do NOT follow the audit's suggestion of a filename-only lookup — `asset(for:)` (line 144) feeds `FaceCropThumbnailView` (PeopleWorkspaceView.swift:553, 669, 788, 943) and needs the full `PhotoAsset`. Instead drop `try catalogStore.entries(for: .allPhotos)` entirely and build the map from the `candidates` already fetched on line 537, since `CatalogPeopleAnalysisCandidate` carries `entry: CatalogEntry` (PeopleModels.swift:232) and the candidate query returns the identical `missing = 0` row set:

    let candidates = try catalogStore.peopleAnalysisCandidates(
        engineVersion: PeopleAnalyzer.currentEngineVersion
    )
    faces = candidates.flatMap { $0.cachedFaces ?? [] }
    assetsByID = Dictionary(
        candidates.map { ($0.entry.id, $0.entry.asset) },
        uniquingKeysWith: { first, _ in first }
    )

`catalog_face_analysis.photo_id` is `TEXT PRIMARY KEY` (CatalogStore.swift:3877) so the LEFT JOIN cannot fan out and keys are in fact unique today; use `uniquingKeysWith` anyway so a future schema change degrades instead of trapping. This removes one of the three blocking queries with no API additions and no behaviour change. Apply the same simplification to `beginScan` (247-256), which likewise fetches `entries(for: .allPhotos)` purely to populate `assetsByID` in `finishScan` (289-294).

2) Break the self-triggered reload round-trip. `finishScan` posts `.rawDeskPeopleAnalysisDidChange` (line 329) after it has already assigned `people`, `faces`, `assetsByID` and rebuilt the snapshot; ContentView.swift:2550 answers that post by calling `people.refreshFromCatalog()`, i.e. a complete synchronous reload plus reclustering of data the view model just computed. Either post the notification with `object: self` and have the ContentView handler skip notifications whose object is the `PeopleViewModel` instance, or set a `suppressNextExternalRefresh` flag in `finishScan` that `refreshFromCatalog()` consumes and clears. This eliminates the worst-case main-thread stall (right after an import, when the catalog is largest and freshly grown) without touching concurrency.

3) Move the remaining work off the main actor. Make `reloadCatalogState()` async and hoist the two catalog reads plus `PeopleAnalyzer.makeSnapshot` into a single `Task.detached(priority: .utility)`, mirroring `beginScan` (247-256). `CatalogStore` is `final class ... @unchecked Sendable` (CatalogStore.swift:113) and `makeSnapshot`/`suggestedClusters` are `nonisolated static` (PeopleAnalyzer.swift:135, 216), so both are safely callable from the detached context; only the assignments to `people`/`faces`/`assetsByID`/`snapshot` and the selection-restoration half of `rebuildSnapshot()` (560-574) stay on the main actor. Three call sites constrain this and must be handled:
   - `performCatalogChange` (524-533) calls `reloadCatalogState()` synchronously immediately after a catalog mutation (rename, assign, merge, unassign, ignore, delete). It must become async and await the reload, otherwise the UI renders pre-mutation state after every People edit.
   - `finishScan`'s `refreshAfterScan` branch (306-319) calls it from a sync context and must await it too.
   - `refreshFromCatalog()` (380-391) can now be re-entered while a reload is in flight (notification storms during import). Add a `reloadGeneration: UUID` token in the same shape as the existing `scanGeneration` (line 38) and discard results whose generation no longer matches, so a slow older reload cannot clobber a newer snapshot.
   Also add a similar guard around the `groupingSensitivity` `didSet` (24-29) if `rebuildSnapshot()` becomes async, so rapid slider drags coalesce rather than queueing one detached clustering pass per intermediate value.


#### [高] CatalogStore carries roughly 860 lines of People code across six disjoint regions of a 6,012-line file

**場所:** `Services/CatalogStore.swift`:1281


People logic is not localised in CatalogStore; it is spread over six separate stretches: error cases and their user-facing strings (32-36 and 94-103); `peopleAnalysisCandidates` (1281-1374); the person/face CRUD API -- `recordPeopleFaceAnalysis`, `clearPeopleFaceAnalysis`, `catalogFaces`, `catalogPeople`, `createPerson`, `renamePerson`, `assignFaces`, `unassignFaces`, `ignoreFaces`, `restoreIgnoredFaces`, `mergePeople`, `deletePerson` (1377-1737); three summary counts (2439-2456); private helpers `loadCatalogFaces`, `ensurePersonExists`, `ensureFacesExist`, `assignFacesUnchecked`, `updateFaces`, `normalizedPersonName`, `reconciledFaces`, `normalizedFaceBounds`, `intersectionOverUnion` (3323-3620); and schema plus indexes (3864-3910, 4171-4189).


**なぜ問題か:** This is the single largest obstacle to removing the feature and the answer to 'how invasive would removal be'. Roughly one line in seven of the catalog store exists for People. The regions are interleaved with unrelated catalog code, so removal is six separate careful excisions rather than one delete, and each touches a file the whole app depends on.


**修正方針:** The diagnosis stands; the fix as written does not compile. Corrections:

**Only three of the six regions are cross-file movable.**
- Region 1 (32-36) is enum cases. Swift extensions cannot add cases to an enum, so `CatalogStoreError`'s People cases must stay in the main file. Only the strings can move, and only by having the main `errorDescription` switch delegate to a `peopleErrorDescription` computed property.
- Region 4 (2439-2456) is argument-position expressions inside a `CatalogOverview(...)` call inside a function body — not a declaration. Hoist to a `peopleOverviewCounts() -> (people: Int, faces: Int, unconfirmed: Int)` helper; the call site still names People.
- Region 6 (3864-3910, 4171-4189) are `try execute(...)` statements inside `migrate()`, which spans 3694 to ~4228 (confirmed: the nearest preceding `func` to both ranges is `private func migrate()` at 3694, and the next is `tableHasColumn` at 4230). Hoist to `migratePeopleSchema()` and `createPeopleIndexes()` called from `migrate()`.

**The three movable regions (2, 3, 5 — ~753 lines) still will not build in a separate file** until the shared SQLite plumbing is widened from `private` to `internal`/`package`. Swift `private` and `fileprivate` members are invisible to extensions declared in a different file. Every one of these is currently `private`: `queue` (119), `scalarInt` (5767), `requireDatabase` (5807), `prepare` (5834), `stepDone` (5853), `ensureNoStepError` (5864), the six `bind` overloads (5874-5938), `bindNull` (5950), `text` (5957), and `execute` (5816) plus `scalarInt64` (5757) if the hoisted schema helpers move too. Widening this much of the private surface is the actual cost of the extraction and should be weighed against the benefit — a `// MARK: - People` band that physically colocates the six regions inside the existing file achieves most of the boundary visibility at zero access-control cost.

**The removal branch is incomplete.** Deleting the six store ranges, three tables, three indexes and the `CatalogOverview` fields leaves six dangling consumers: Sources/RAWDesk/Services/PeopleAnalyzer.swift, Sources/RAWDesk/ViewModels/PeopleViewModel.swift, Sources/RAWDesk/Views/PeopleWorkspaceView.swift, Sources/RAWDesk/Views/ContextualWorkspaceSidebars.swift, Tests/RAWDeskTests/PeopleTests.swift, Tests/RAWDeskTests/RAWDeskTests.swift. Also, removing the `CREATE TABLE IF NOT EXISTS` statements from `migrate()` does not drop the tables from databases that already exist — add an explicit `DROP TABLE` migration step if reclaiming that space matters.

**Model line numbers corrected.** The `CatalogOverview` People fields are not one 107-138 range but three: declarations at CatalogModels.swift:107-109, init parameters at 122-124, init assignments at 136-138.


---

## 未検証の指摘（中・低）


### Develop UI


#### [中] Six sections carry a second, redundant whole-section reset at the bottom, each worded differently

**場所:** `Views/EditingInspectorView.swift`:5566


`adjustmentGroup` gives every mapped group a header Reset (EditingInspectorView.swift:5566-5576 with the mapping at 5602-5617), so Light, Color, Tone Curve, Color Mixer, Point Color, Color Grading, Calibration, Masks, Remove, Optics, Crop & Geometry, Effects and Detail all already have one. Six sections then add a second whole-section reset at the bottom of their body, under six different names: "Reset Tone Curve" (5904-5911), "Reset All" (Color Mixer, 169-172), "Reset All" (Color Grading, 469-472), "Reset Calibration" (542-548), "Reset Optics" (1490-1504), "Reset Crop & Geometry" (1839-1859). Color Mixer and Color Grading also pair theirs with a scoped "Reset <channel>" / "Reset <region>" (160-165, 458-465), so "Reset All" there means 'all of this section', while the header Reset means the same thing again.


**修正方針:** Delete the six bottom-of-body whole-section resets and let the header Reset be the only one. Keep the genuinely scoped ones — "Reset <channel>" in Color Mixer, "Reset <region>" in Color Grading, "Reset Point", "Reset Mask" — since those reset a sub-object, not the section, and move them to the row of the object they act on.


#### [中] The Masks section buries the mask's adjustments under all of its construction UI, in one flat non-collapsible stack

**場所:** `Views/EditingInspectorView.swift`:874


For a selected mask the panel renders, in order: kind header and Invert (689-707), Show Mask Overlay (709-714), up to five geometry sliders (716-859), the entire Primary Tool Operations block with its own list and nested editor (874, 3150-3528), the entire Range Operations block with its own list and nested editor (876, 3714-4140), and only then the mask's actual adjustments — Light (6 sliders, 880-935), Color (4, 939-978), a nested Point Color block with its own swatch list, four sliders and a Range disclosure (980, 3531-3712), Effects (3, 984-1012), Detail (2, 1016-1037). That is roughly twenty sliders plus two nested operation editors in one flat run. The Light/Color/Effects/Detail sub-groups are plain `Typography.badge` text labels (881, 940, 985, 1017), so none of them collapses — even though the identical content at global scope lives in collapsible `RAWInspectorSection`s (71, 86, 1862, 1900).


**修正方針:** Reorder the selected-mask editor so the adjustments come first: kind header, Invert, Show Mask Overlay, then Light/Color/Effects/Detail, and move the construction blocks (geometry sliders, Primary Tool Operations, Range Operations, local Point Color) below them. Then wrap the Light/Color/Effects/Detail runs and the two operation blocks in `DisclosureGroup`, which this file already uses for the Point Color Range block at 315-354 and 3654-3693 — reuse of an existing control, not a new one — with Light expanded and the rest collapsed by default.


#### [中] Mask primary operations and range operations use different words and mirrored layouts for identical data

**場所:** `Views/EditingInspectorView.swift`:3273


The two operation editors inside Masks model the same thing — an ordered, invertible, combinable sub-selection — and present it four different ways. (1) The enable checkbox is `Toggle("Enabled")` for a primary operation (3273-3281) and `Toggle("On")` for a range operation (3872-3880). (2) The combination picker is `Picker("Combination")` at 3297-3310 and `Picker("Combine")` at 3895-3908; neither uses `.labelsHidden()`, unlike Color Grading's segmented picker at 392-400, so both render a visible label the other section suppresses. (3) The list rows are mirror images: a primary-operation row puts the combination glyph *leading*, before the kind glyph, and prefixes the combination name into the title — "Add Subject" (3225-3241) — while a range-operation row puts the kind glyph leading, the combination glyph *trailing*, and shows a bare name (3830-3841). (4) The add menu button is "Add Tool" (3182) in one and "Add Operation" (3774) in the other.


**修正方針:** Pick one vocabulary and apply it to both: `Toggle("Enabled")`, `Picker("Combine")` with `.labelsHidden()` (the picker's segments already say Add/Subtract/Intersect), and one row layout — combination glyph leading, kind glyph second, bare operation name, status glyphs trailing. Rename both menu buttons to "Add" since the enclosing header already says which list is being added to.


#### [中] Tool buttons turn into disabled status labels, and the tool row cannot toggle a tool off

**場所:** `Views/EditingInspectorView.swift`:1508


"Edit Crop on Photo" relabels itself "Crop Tool Active" and sets `.disabled(viewer.isCropEditing)` (1508-1520); "Edit Repairs on Photo" does the same, becoming "Repair Tool Active" (1088-1109). Both then look like buttons, sit in a button's chrome, and do nothing. Two other buttons in the same panel handle the identical situation the opposite way and stay live toggles: "Draw Guides on Photo" ⇄ "Done Drawing Guides" (1548-1570) and "Paint Mask on Photo" ⇄ "Done Painting Mask" (716-739). The tool row at the top of the inspector (2210-2227) renders `RAWToolRailButton` with `isSelected` and `.isSelected` accessibility traits, but `activateDevelopTool` returns early when the requested tool is already current (ContentView.swift:1568-1570), so clicking the highlighted tool is inert too.


**修正方針:** Make the two dead buttons behave like the two live ones: keep them enabled and toggle, with the active label reading "Done Cropping" / "Done Repairing" and calling the same finish path as the mode bar. Do the same for the tool row: drop the early return in `activateDevelopTool` when `currentDevelopTool == tool` and finish the tool instead, so a selected tool button deselects.


#### [中] Adding a mask operation costs three clicks through a nested submenu for a mode that is one click to change afterwards

**場所:** `Views/EditingInspectorView.swift`:3162


Both add menus in Masks are two levels deep, keyed on combination mode first: "Add Tool" opens a menu of `MaskCombinationMode` cases, each of which opens a submenu of `LocalMaskKind` cases (3162-3183); "Add Operation" does the same over the three range kinds (3727-3772). So creating a subtract-brush is menu, hover, click, click. Immediately below, once the operation exists, its combination is a one-click segmented picker (3297-3310, 3895-3908) — the mode the submenu made you commit to up front is the cheapest thing in the editor to change.


**修正方針:** Flatten both menus to the kind list only, creating the operation with the additive default, and let the segmented picker directly below change the mode. This removes a menu tier rather than adding anything.


#### [中] The mask overlay toggle exists twice with two labels and two different notions of 'on'

**場所:** `Views/EditingInspectorView.swift`:709


The inspector shows `Toggle("Show Mask Overlay")` bound to `maskOverlayBinding(maskID:)`, whose getter is `viewer.visualizedLocalMaskID == maskID` (709-714, 4713-4722). The canvas tool mode bar shows `Toggle("Show Overlay")` bound to a different closure whose getter is `viewer.visualizedLocalMaskID != nil` and whose setter writes `viewer.selectedLocalMaskID` (WorkspaceShellViews.swift:1414-1418, 1458-1467). Both are visible at the same time whenever the mask tool is live. They are also styled inconsistently against the panel's own rule: `.switch` is used for global/preview state — Soft Proof (2131), Auto Sync (2375), the section enable switch (RAWDeskDesignSystem.swift:1112) — and `.checkbox` for per-object state, yet "Visualize Range" (357-364), which is exactly a per-swatch preview overlay of the same family as "Show Mask Overlay", is a `.switch`.


**修正方針:** Keep one overlay control. Since the mode bar is only present while the tool is live and the inspector one is always available, drop the mode bar duplicate and leave the per-mask checkbox as the single control; if the mode bar copy is kept, bind it to the same `maskOverlayBinding` and use the same label. Change "Visualize Range" to `.toggleStyle(.checkbox)` so per-object preview toggles are uniformly checkboxes.


#### [低] Unipolar sliders print a leading + sign, inconsistently, sometimes on adjacent rows

**場所:** `Views/EditingInspectorView.swift`:1904


`AdjustmentSlider`'s default format is `"%+.0f"` (5998-6000), so any 0...100 slider that does not pass an explicit format prints a plus sign. In Detail, "Amount" (1904-1908, range 0...100, default format) reads "+40" while "Detail" directly below it (1918-1924, same range) explicitly passes `"%.0f"` and reads "40"; the same split repeats for Noise Reduction "Luminance" (1939-1943) versus "Luminance Detail"/"Luminance Contrast" (1945-1957), and "Color" (1961-1965) versus its two sub-parameters (1966-1980). Elsewhere the plus survives on Purple/Green Defringe (1479-1488), all three Grain sliders (1878-1896), Color Grading Saturation (426-434) and the mask's Noise Reduction (1029-1037). `RAWSliderRow`'s own default is a third variant, `"%+.2f"` (RAWDeskDesignSystem.swift:1335-1337).


**修正方針:** Choose the sign convention from the range rather than per call site: in `RAWSliderRow`, use `"%+"` formatting only when `range.lowerBound < resetValue`, otherwise unsigned. Then delete the six explicit `"%.0f"` overrides in Detail, which exist only to work around the default.


#### [低] Boolean and enum rows show one photo's state under multi-selection while numeric rows show a mixed marker

**場所:** `Views/EditingInspectorView.swift`:5302


Numeric rows have a defined mixed-selection presentation: `mixedDoubleBinding` computes mixedness across `library.selectedIDs` (2475-2523) and `RAWSliderPresentation` renders an em dash with no track fill (RAWDeskDesignSystem.swift:1186-1208). No boolean or enum row does. `maskInversionBinding` (5302-5318), `geometryBoolBinding` used by Constrain Crop (2726-2749), and `effectsEnabledBinding` (2446-2473) all return a plain `Binding<Bool>` reading `library.selectedAsset` only. The same applies to the Remove "Mode" picker (1146-1159) and both combination pickers. ToneCurveEditor makes the divergence visible in one section: its in-body reset is enabled when `isMixed` (5911) while the header Reset for the same section keys off `sectionIsNeutral`, which inspects only the primary asset (5635-5648).


**修正方針:** Reuse the existing mixed machinery rather than inventing a new one: add a `mixedBoolBinding` alongside `mixedDoubleBinding` using the same `PhotoAdjustmentMixedValuePlanner.valuesAreMixed` already called by `adjustmentValuesAreMixed` (2525-2542), and render the mixed state with the checkbox's native `.indeterminate`-style dash. Failing that, disable the boolean rows under a mixed selection so they do not assert something false.


#### [低] Two resets in the fixed header are accent-coloured, contradicting the panel's own stated rule

**場所:** `Views/EditingInspectorView.swift`:2175


`rawSecondaryTextAction` exists specifically so reset-style actions are quiet secondary text — its doc comment says the accent treatment 'scattered what looked like hyperlinks down the panel' (RAWDeskDesignSystem.swift:386-396) — and `RAWInspectorSection`'s Reset follows it with `textSecondary` (1130-1139). Every in-body reset in the Develop panel uses `rawSecondaryTextAction`. The two resets in the fixed header do not: "Reset All" (EditingInspectorView.swift:2175-2186) and the Profile "Reset" (2264-2273) both hand-roll `.buttonStyle(.plain)` plus `.foregroundStyle(RAWDeskTokens.ColorToken.selection)`.


**修正方針:** Replace both `.buttonStyle(.plain)` + accent `.foregroundStyle` pairs with `.rawSecondaryTextAction()`. Nothing else changes; both already carry `.disabled` and `.help`.


#### [低] Tone Curve is the only section whose slider and value field are not the panel's own slider row

**場所:** `Views/EditingInspectorView.swift`:5870


Every other control in Develop goes through `RAWSliderRow` — 84pt label column, custom origin-tick track, 14pt knob, borderless value field that boxes on hover, double-click to reset (RAWDeskDesignSystem.swift:1328-1502). `ToneCurveEditor` instead uses a bare `Slider` with `.controlSize(.small)` and `.tint(...)` (5870-5894) and a `.rawNumericField(width: 58)` value field, which is `.roundedBorder` (RAWDeskDesignSystem.swift:413-421), stacked above rather than beside the track (5814-5868). So this one section has a stock macOS track with no origin tick, a permanently boxed 58pt field instead of a borderless 48pt one, no double-click reset, and a label above the control instead of in the label column.


**修正方針:** Replace the hand-built label/field/slider stack at 5814-5902 with a single `AdjustmentSlider` titled with `selectedRegion.name`, range 0...1, step 0.01, `resetValue` 0.5, and a percent format, passing the existing `isMixed` through. This deletes about ninety lines and picks up the origin tick, hover-boxed field and double-click reset for free.


### Library / 選別


#### [中] "N selected" is on screen four times at once; photo count and filter state twice

**場所:** `Views/WorkspaceShellViews.swift`:875


In Library grid with the filmstrip open, the selection count is printed by the control bar (WorkspaceShellViews.swift:875-889), by a floating capsule over the top-right of the grid (ThumbnailGridView.swift:66-77), by the filmstrip header (ContentView.swift:2320-2330) and by the status bar (WorkspaceShellViews.swift:977-981). The filtered photo count appears in the filmstrip header (ContentView.swift:2355-2357) and the status bar (WorkspaceShellViews.swift:962-965); the filter badge appears in the control bar chip (:813-853), the filmstrip header (ContentView.swift:2344-2354) and the status bar (:966-972). The filmstrip header also shows "Auto Sync ON/OFF" (ContentView.swift:2331-2343), a Develop-only concept, inside the Library grid.


**修正方針:** Keep exactly one readout, in the status bar (WorkspaceShellViews.swift:961-982), which is already the app's place for counts. Delete the grid overlay (ThumbnailGridView.swift:65-78), the control-bar `selectionSummary` (WorkspaceShellViews.swift:874-889 and its two call sites at :624 and :637/:645), and the entire filmstrip header row (ContentView.swift:2313-2370) along with the now-unused `DevelopFilmstripStatus` (ContentView.swift:2255-2293); surface Auto Sync where Auto Sync is set, in Develop.


#### [中] Thumbnail cells spell out flag states in words, against the app's own stated rule

**場所:** `Views/ThumbnailCellView.swift`:284


The cell badge rows render `Label("Picked", …)`, `Label("Rejected", …)` and `Label("Edited", …)` with visible text (ThumbnailCellView.swift:284-322), and the colour label prints its swatch *and* its name (:338-354). The inspector's review controls solved this exact problem and documented the rule at RAWDeskDesignSystem.swift:1658-1661 — "Flags are glyphs, never glyph-plus-word … the help text and accessibility label carry the words" — and the cell already sets those accessibility labels (ThumbnailCellView.swift:289, 296, 300, 322, 334, 351), so the words are pure duplication. Separately the scrim gradient (:383-392) is drawn unconditionally, so a photo with no rating, flag, label or keyword still gets a black band across its bottom edge containing nothing.


**修正方針:** Apply `.labelStyle(.iconOnly)` to the Picked / Rejected / Edited labels and drop the colour-label name `Text` (:346-349), leaving the swatch. Collapse the two HStacks into one row now that it fits, and render `reviewStateLayer` (including its gradient) only when at least one badge is actually present.


#### [中] Grid column arithmetic under-counts columns and leaves dead space in every cell

**場所:** `Views/ThumbnailGridView.swift`:39


Columns are computed as `Int(geo.size.width / (cellSize + 12))` (ThumbnailGridView.swift:39-42). The 12 does not correspond to anything: the real inter-item and row spacing is `Spacing.xSmall` = 4 (:47, :51) and the grid is inset by `Spacing.small` = 8 on each side (:58), which the formula ignores entirely. At a 1000 pt-wide grid with the Medium preset (cellSize 160) it yields 5 columns where 6 fit. Because the columns are `.flexible()` while the cell height is pinned to `cellSize + 22` (:144), the surplus width is not used by the image — the square thumbnail is height-bound, so each cell gets ~34 pt of empty margin.


**修正方針:** Compute against the real content width and the real spacing: `let content = geo.size.width - 2 * Spacing.small; let columns = max(1, Int((content + Spacing.xSmall) / (cellSize + Spacing.xSmall)))`. Also raise the 22 pt label allowance at :144 to match the actual label row (xSmall spacing 4 + an 11 pt metadata line + 8 pt padding ≈ 25), which currently squeezes the square by ~3 pt.


#### [中] Dragging the thumbnail-size slider blanks every visible cell to a spinner

**場所:** `Views/ThumbnailCellView.swift`:657


`load()` clears the displayed image and drops to `.loading` before doing any work (ThumbnailCellView.swift:657-660), and `loadID` includes the pixel size (:69), so any size change restarts the `.task` (:125-127). The status-bar slider is bound live to `library.thumbnailPixelSize` with `step: 32` over 128…512 (WorkspaceShellViews.swift:1003-1013) — twelve distinct values in one drag — and each value is a different `ImageCache.key` (ImageCache.swift:59-62), so nothing is cached and every step re-decodes from disk through a 3-wide gate (ImageLoader.swift:117).


**修正方針:** Do not discard what is already on screen: leave `image` in place and skip the `.loading` state when a rendered image already exists, replacing it only when the new decode succeeds (`if let displayedImage { self.image = displayedImage }`). The cell then rescales the existing bitmap during the drag and sharpens when the decode lands — which is also how the filmstrip should behave.


#### [中] Library sidebar spends eleven fixed rows on canned queries before Collections or Folders

**場所:** `Views/RAWLibrarySidebarView.swift`:216


The Catalog section renders every `CatalogSmartCollection` case except two (RAWLibrarySidebarView.swift:216-220), i.e. eleven always-present rows (CatalogModels.swift:4-16): All Photographs, Recently Added, Quick Collection, Edited, Five Stars, Picked, Rejected, With Keywords, With Location, Without Location, Missing Files. Four of them restate the Filter menu one control bar away — Picked / Rejected duplicate `LibraryFilter.flaggedOnly` / `.rejectedOnly` and Five Stars duplicates Minimum Rating (WorkspaceShellViews.swift:758-783) — and With Location / Without Location are Map-module queries. Counts are hidden when zero (RAWLibrarySidebarView.swift:233), so empty rows still occupy full height with nothing to say. Below this sit Collections, Folders (RAWLibrarySidebarView.swift:303-343) and a Services block whose three disclosure rows are each two lines tall (:700-734).


**修正方針:** Trim Catalog to All Photographs, Recently Added, Quick Collection and Missing Files; the rating and flag queries are already one click away in the Filter menu, and the location queries belong to the Map sidebar. Collapse the Services rows to single-line labels with the status text moved into `.help` (RAWLibrarySidebarView.swift:709-720), and move "Include subfolders when opening" (:417-420) out of the Auto Import disclosure into Folders, where opening a folder actually happens.


#### [中] One flag state, two names and two shortcuts; the heart has neither

**場所:** `Models/FilterState.swift`:22


`PhotoUserState.flagged` is called "Picked" by the pick status (PhotoUserState.swift:14), by the sidebar collection (CatalogModels.swift:27), by the cell badge (ThumbnailCellView.swift:286) and by the inspector (RAWDeskDesignSystem.swift:1667), but "Flagged" by the filter menu (FilterState.swift:22). It also has two keyboard shortcuts that behave differently: P sets `.picked` and F toggles the same field while additionally clearing `rejected` (KeyboardHandler.swift:127-128 → LibraryViewModel.swift:3943-3961). Meanwhile `favorite` is a third, parallel flag axis with its own heart badge on every cell (ThumbnailCellView.swift:298-301), its own filter (FilterState.swift:8) and its own inspector toggle (MetadataInspectorView.swift:343-361) — and no shortcut and no sidebar entry at all.


**修正方針:** Rename `LibraryFilter.flaggedOnly`'s display name to "Picked" (FilterState.swift:22) so one state has one name everywhere. Retire F as a second name for pick (KeyboardHandler.swift:127) — P / X / U already cover set-pick, set-reject and clear — and either reassign F to Favorite or drop the heart badge from the cell so the badge row shows only the axis the keyboard can reach.


#### [低] Arrow keys ignore the grid's geometry: Down does the same thing as Right

**場所:** `Views/KeyboardHandler.swift`:88


The key monitor maps left and up to `onPrev` and right and down to `onNext` (KeyboardHandler.swift:88-93), which resolve to `selectPrevious()` / `selectNext()`, a one-step move through `filtered` (LibraryViewModel.swift:3862-3909). In the filmstrip that is right; in a multi-column grid it means the vertical arrows move by a single photo rather than by a row, and the column count computed at ThumbnailGridView.swift:39-42 is never consulted.


**修正方針:** Publish the grid's current column count from ThumbnailGridView (it is already computed inside the GeometryReader) onto the view model, and in the Library-grid case have the vertical arrows step by that many photos, clamped to the ends of `filtered`. Leave Loupe, Develop and the filmstrip on the existing one-step behaviour, where it is correct.


### 全体構造・文言


#### [中] The Map module is reachable five ways under three different names and two conflicting shortcuts

**場所:** `App/RAWDeskApp.swift`:166


`library.showMap()` (LibraryViewModel.swift:4871) is invoked from RAWDeskApp.swift:142 as "Show Location on Map" (Metadata menu) and from RAWDeskApp.swift:166-172 as "Show Map" with ⌥⌘3 (Map menu). A third command, "Map Workspace" with ⌘4 (RAWDeskApp.swift:443-454), reaches the same destination via the UI-command notification. A fourth entry sits in the toolbar ellipsis menu as "Map" (ToolbarContent.swift:349-351), and a fifth is the module picker itself (ToolbarContent.swift:249-253). ⌥⌘3 for Map also sits directly against ⌘3 for People (RAWDeskApp.swift:437-440), so the digit 3 means People in one modifier family and Map in the other.


**修正方針:** Keep only ⌘4 / "Map" as the module command. Delete the ⌥⌘3 shortcut and the "Show Map" button at RAWDeskApp.swift:166-173 (the Map menu's remaining tracklog and saved-location items still justify the menu). Delete "Show Location on Map" at RAWDeskApp.swift:142-145. Delete the "Map" item at ToolbarContent.swift:349-351 along with the rest of `workspaceModeActions`.


#### [中] Compare, Survey and Reference carry four different sets of names across four surfaces

**場所:** `Views/WorkspaceShellViews.swift`:857


The same three `library.toggleCompare()` / `toggleSurvey()` / `toggleReferenceView()` actions are labelled four ways. Library control bar buttons (WorkspaceShellViews.swift:857-868): "Compare", "Survey", "Reference". The narrow-window fallback of the same bar (WorkspaceShellViews.swift:893-904): "Compare Photos", "Survey Selected Photos", "Open Reference View". Toolbar ellipsis menu (ToolbarContent.swift:357-389): "Compare Photos"/"Finish Comparing", "Survey Selected Photos"/"Finish Survey", "Open Reference View"/"Finish Reference View". Menu bar (RAWDeskApp.swift:508-545): "Compare Photos"/"Finish Comparing", "Survey Photos"/"Finish Surveying", "Open in Reference View"/"Finish Reference View". The Survey exit alone is "Finish Survey" in the toolbar and "Finish Surveying" in the menu bar; Reference entry is "Open Reference View" in three places and "Open in Reference View" in the fourth. The same bar even renames its own ellipsis menu across fit variants — `Menu("View Actions", …)` at :631 versus an unlabelled menu whose accessibility label is "More library controls" at :801-809.


**修正方針:** Pick one pair per mode — "Compare Photos"/"Finish Comparing", "Survey Photos"/"Finish Surveying", "Open in Reference View"/"Finish Reference View" (the menu-bar set) — and use it verbatim at WorkspaceShellViews.swift:857, :861, :865, :893, :897, :901 and, if any toolbar copy survives, ToolbarContent.swift:358-388. Give the compact menu at WorkspaceShellViews.swift:801-809 the same "View Actions" title used at :631.


#### [中] Photo count, selection count and the filter badge are reported up to three times on one screen

**場所:** `Views/WorkspaceShellViews.swift`:977


In Library grid with the filmstrip open, three bars each report the same state. The control bar's `selectionSummary` (WorkspaceShellViews.swift:875-889, used at :624, :637, :645) prints "N selected" / "1 selected". The status bar directly beneath the grid prints the photo count and "Filter applied" (WorkspaceShellViews.swift:962-972) and then "N selected" / "1 selected" again (:977-981). The filmstrip header between them prints "N selected" (ContentView.swift:2272-2275, :2320-2330), a "Filtered" badge (:2344-2354), and "N photos" (:2290-2291, :2355-2357). Net result: the selection count appears three times, the photo count twice, and the filter state twice — under two different words, "Filter applied" (WorkspaceShellViews.swift:968) versus "Filtered" (ContentView.swift:2346), which is also the word the filter menu button uses for its own active state (WorkspaceShellViews.swift:717).


**修正方針:** Make the status bar the single owner of catalog-wide state. Delete `selectionSummary` from the control bar (remove the calls at WorkspaceShellViews.swift:624, :637, :645; the property at :874-889 then becomes dead). In the filmstrip header, delete the selection text (ContentView.swift:2320-2330), the filter badge (:2344-2354) and the photo count (:2355-2357), keeping only the Auto Sync state, which no other bar reports. Standardise on one word for the filter state — use "Filtered" at WorkspaceShellViews.swift:968 to match :717.


#### [中] Versions appears twice in the Develop module, with two different names for the same button

**場所:** `Views/ContentView.swift`:2155


The Develop left sidebar has a "Versions" section with a "Create Version" button and a list of versions (ContentView.swift:2154-2202). The Develop right inspector has a "Versions" group with a "Save Current Version" button and the same list (EditingInspectorView.swift:1985-2072). Both call `library.createVersion(for:)`, both are on screen at once in Develop (ContentView.swift:791-794 and :911-919), and both list `asset.userState.versions.reversed()`. The inspector copy is strictly richer: it shows the saved count, a delete button per version, and the version's soft-proof profile (EditingInspectorView.swift:2039-2046, :2057-2071).


**修正方針:** Delete the sidebar's Versions section (ContentView.swift:2154-2202) and keep the inspector copy, which sits next to the adjustments that produce a version. Rename its button from "Save Current Version" (EditingInspectorView.swift:2006) to "Create Version" to match the vocabulary already used by `library.createVersion`.


#### [中] The Develop canvas control bar spends a full-height bar on one button, and reports soft proofing twice within four rows

**場所:** `Views/WorkspaceShellViews.swift`:1470


`RAWDevelopCanvasControlBar` (WorkspaceShellViews.swift:1470-1517) occupies a full `workspaceControlBar`-height strip plus a hairline divider directly above the photograph, and its entire content is one borderless button and a `Spacer` (:1474-1490). The only other thing that can appear there is a soft-proof badge reading "Soft Proof: sRGB · Perceptual" (:1492-1503) — while `RAWPhotoCanvasStatusBar`, four rows below the same image, shows a second soft-proof badge reading just "Proof" (:1548-1554), and the inspector header carries the actual "Soft Proof" toggle (EditingInspectorView.swift:2118-2133). The status bar also duplicates the Navigator's zoom presets: "Fit" and "100%" at WorkspaceShellViews.swift:1525-1530 are the same two buttons as ContentView.swift:1999-2004, both visible in Develop.


**修正方針:** Delete `RAWDevelopCanvasControlBar` (WorkspaceShellViews.swift:1470-1517) and its use at :1330, letting the canvas start immediately below the toolbar. Move the before/after button into the status bar alongside Fit and 100% (:1524-1537), which already has unused horizontal space. Delete the redundant soft-proof badge, keeping the status bar's compact one at :1548-1554 but giving it the full profile text from :1494-1499 so no information is lost. Remove the duplicate zoom presets from the Navigator (ContentView.swift:1995-2006, and `zoomPreset` at :1944-1976).


#### [中] The before/after comparison is called four different things

**場所:** `Views/WorkspaceShellViews.swift`:1480


One action, `viewer.toggleOriginal()`, is labelled: "Before / After" when off and "Show Edit" when on (WorkspaceShellViews.swift:1478-1486); "Toggle Original" in the menu bar (RAWDeskApp.swift:576); and its resulting state is badged "Original" in both the Develop status bar (WorkspaceShellViews.swift:1543) and the Library loupe overlay (WorkspaceShellViews.swift:500). The button's help text — "Hold or press backslash to compare with the original" (WorkspaceShellViews.swift:1488) — introduces yet a fifth phrasing and is the only place the ⧵ shortcut is stated, since the menu item at RAWDeskApp.swift:576-578 shows it but under a different name. A toggle whose two states are named "Before / After" and "Show Edit" is also mismatched in kind: one names a mode, the other names an action.


**修正方針:** Use one noun everywhere: "Original". Make the button a stable `Label("Original", systemImage: "eye")` at WorkspaceShellViews.swift:1478-1486 that shows selected state rather than swapping its title, rename the menu item at RAWDeskApp.swift:576 from "Toggle Original" to "Show Original", and leave the badges at WorkspaceShellViews.swift:500 and :1543 as "Original". Shorten the help to "Hold ⧵ to compare with the original".


#### [中] The healing tool has four names, and the tool row's "Color" caption collides with the Color section beneath it

**場所:** `Models/WorkspaceMode.swift`:74


`DevelopCanvasTool.remove` is titled "Heal / Clone" (WorkspaceMode.swift:74), captioned "Heal" in the inspector tool row (WorkspaceMode.swift:86, rendered as the visible caption at RAWDeskDesignSystem.swift:993 while `name` becomes the tooltip at :1040), headed "Remove" as an inspector section (EditingInspectorView.swift:1064), and produces objects named "Heal 1" (ContentView.swift:1723). The tool mode bar shows the full "Heal / Clone" (WorkspaceShellViews.swift:1404) while the tool button two panels away shows "Heal". Separately, `pointColor.shortName` is "Color" (WorkspaceMode.swift:89), so the tool row's rightmost caption reads "Color" while a section headed "Color" (EditingInspectorView.swift:86) sits a few rows below it in the same panel, and a "Color" slider (EditingInspectorView.swift:1963) sits inside Detail.


**修正方針:** Settle on "Remove" for the tool: set `name` to "Remove" (WorkspaceMode.swift:74) and `shortName` to "Remove" (WorkspaceMode.swift:86), matching the section header at EditingInspectorView.swift:1064 and the persisted key `rawdesk.develop.section.remove` (ContentView.swift:1600); rename the created spot from "Heal 1" to "Remove 1" at ContentView.swift:1723. Change `pointColor.shortName` from "Color" to "Point" (WorkspaceMode.swift:89) so no tool caption repeats an adjustment-group name.


#### [低] The same two empty states are written in two capitalisations within the same module

**場所:** `Views/WorkspaceShellViews.swift`:511


The loading state is title case in Library — "Loading Photos" (WorkspaceShellViews.swift:511 and :521) — and sentence case with an ellipsis in Develop — "Loading photos…" (WorkspaceShellViews.swift:1337). The no-selection state is title case in the Develop inspector and Library inspector — "No Photo Selected" (EditingInspectorView.swift:2100, WorkspaceShellViews.swift:1059) — and sentence case in the Develop sidebar, twice on the same screen — "No photo selected" (ContentView.swift:2028, :2101). In Develop the two conventions are visible simultaneously: the sidebar says "No photo selected" while the inspector on the opposite edge says "No Photo Selected".


**修正方針:** Use title case without an ellipsis for all `RAWEmptyState` titles, and reserve sentence case for body text. Change WorkspaceShellViews.swift:1337 to "Loading Photos", and ContentView.swift:2028 and :2101 to "No Photo Selected". If the legacy path survives, ContentView.swift:130 and :218 need the same change.


### デザインシステム


#### [中] The Develop inspector uses two different numeric-value field idioms, twelve rows apart

**場所:** `Views/EditingInspectorView.swift`:5832


`RAWSliderRow` draws its value as unstyled text that only acquires a box on hover or focus: `.textFieldStyle(.plain)`, 48pt wide, background applied only when `isFieldHovering || textFieldFocused` (RAWDeskDesignSystem.swift:1427-1465). The comment at RAWDeskDesignSystem.swift:1451-1454 states the rationale explicitly: "Twelve permanently boxed fields put more visual weight beside the photo than the numbers deserve; the box appears when the field is actually a target." The Tone Curve editor, which scrolls into view directly under the Light and Color sliders in the same panel, uses `.rawNumericField(width: 58)` (EditingInspectorView.swift:5832) — the shared modifier at RAWDeskDesignSystem.swift:413-421, which is `.textFieldStyle(.roundedBorder)` and therefore permanently boxed, and 58pt rather than 48pt.


**修正方針:** Give the Tone Curve output field the same treatment as a slider row's field: 48pt wide, `.textFieldStyle(.plain)`, monospaced, trailing-aligned, with `ColorToken.controlElevated` at `Radius.control` appearing only on hover or focus. Extract that presentation out of `RAWSliderRow` into a single modifier (e.g. rename/reshape `rawNumericField` to be the unboxed-until-targeted form) so both call sites share it and the widths cannot drift again.


#### [中] On-canvas drag handles have three different sizes, stroke weights, and hit targets

**場所:** `Views/ImagePreviewView.swift`:912


The three direct-manipulation handles a user drags on the image are specified independently, with no token behind any of them. Heal/spot handle: 16pt circle, 2pt stroke, drop shadow, 34pt hit target (ImagePreviewView.swift:908-918). Guided Upright endpoint: 11pt circle, 1.5pt stroke, drop shadow, 30pt hit target (ImagePreviewView.swift:1110-1121). Crop handle: 10pt circle, 1pt stroke, no shadow, 28pt hit target (ImagePreviewView.swift:1332-1337). RAWDeskTokens.Size (RAWDeskDesignSystem.swift:141-169) has `iconTarget = 28` and nothing for canvas handles, so all nine numbers are literals.


**修正方針:** Add one handle spec to RAWDeskTokens.Size (e.g. `canvasHandle: CGFloat = 12`, `canvasHandleTarget: CGFloat = 30`) plus a small shared modifier carrying the 1.5pt stroke and the shadow already used at ImagePreviewView.swift:1116-1119, then apply it at all three sites. One dot size, one rim, one target across Crop, Remove, and Guided Upright.


#### [中] RAWInspectorSection renders edge-to-edge in Develop and inset in Library — same component, two rhythms

**場所:** `Views/WorkspaceShellViews.swift`:1113


`RAWInspectorSection` already owns its own layout: `Spacing.medium` horizontal padding, a 30pt header row, a `ColorToken.panel` background, and a full-width bottom hairline (RAWDeskDesignSystem.swift:1141-1166). The Develop inspector stacks them with no outer padding and zero spacing, so they tile edge-to-edge and each hairline spans the panel (EditingInspectorView.swift:61-71). The Library inspector wraps the identical component in `VStack(spacing: RAWDeskTokens.Spacing.large)` and then `.padding(RAWDeskTokens.Spacing.medium)` (WorkspaceShellViews.swift:1072-1119), so the sections float 12pt in from both edges, sit 16pt apart, and their hairlines stop short of the panel edge — a divider that separates nothing. The Library inspector also nests `MetadataInspectorView` inside a `RAWInspectorSection(title: "Metadata")` (WorkspaceShellViews.swift:1099-1112), and that view then draws its own sub-headers — "Organization" (MetadataInspectorView.swift:330), "Image", "Camera", "Exposure", "Location" (MetadataInspectorView.swift:495-512) — in the very same `Typography.sectionHeader`, separated by stock `Divider()` (MetadataInspectorView.swift:316-319) rather than the `ColorToken.divider` hairline the component uses.


**修正方針:** In WorkspaceShellViews.swift:1072-1119, drop the outer `.padding(RAWDeskTokens.Spacing.medium)` and the `spacing: .large` so `RAWInspectorSection` tiles edge-to-edge exactly as in Develop; apply the 12pt inset only to `identityHeader`, `RAWReviewControls`, and `actions`, which are not sections. In MetadataInspectorView.swift, demote the nested sub-headers to `Typography.metadata` in `ColorToken.textSecondary` so they sit visibly below the enclosing section title, and replace the structural `Divider()` at lines 316 and 318 with the token hairline (`Rectangle().fill(ColorToken.divider).frame(height: 1)`) used everywhere else in the chrome.


#### [中] A colour label is drawn three different ways, contradicting the design system's own stated rule

**場所:** `Views/RAWDeskDesignSystem.swift`:1737


RAWDeskDesignSystem.swift:1630-1634 states the rule: "One vocabulary for rating, flagging, and colour labelling ... a colour label is always a swatch." Three incompatible swatches exist. (1) `RAWReviewControls` draws a `RoundedRectangle(cornerRadius: Radius.control)` at 9 or 11pt and marks the active label with an outer `textPrimary` ring inset by -2pt (RAWDeskDesignSystem.swift:1737-1758). (2) `ColorLabelSwatch` draws a `Circle` with a faint rim and marks selection with a checkmark glyph inside it (PhotoColorLabelView.swift:54-94), used by the sidebar filter row (PhotoColorLabelView.swift:106) and the label-set editor (ColorLabelSetEditorView.swift:183). (3) The thumbnail badge row draws a bare 8pt `Circle` with no rim, followed by the label's name as text (ThumbnailCellView.swift:338-354). Three shapes, three selection idioms, and the 8pt circle is the only one whose size is a bare literal.


**修正方針:** Make `ColorLabelSwatch` (PhotoColorLabelView.swift:54) the single swatch. Have `RAWReviewControls.colorLabelSwatches` (RAWDeskDesignSystem.swift:1725-1783) render `ColorLabelSwatch(label:isSelected:size:)` instead of its own RoundedRectangle-plus-ring, keeping its existing tap-to-clear behaviour. In ThumbnailCellView.swift:338-354, replace the bare 8pt `Circle` with `ColorLabelSwatch(label:size:)` at the badge scale so the grid uses the same mark; the trailing name text can stay if it is wanted as information, but the mark itself should match.


### People の負荷


#### [中] Removal seam map: what deletes cleanly, what needs surgery, and what removal would not remove

**場所:** `Services/PeopleAnalyzer.swift`:6


People spans 21 files. Clean seams (whole-file or whole-type deletes, ~2,802 source lines + 984 test lines): Services/PeopleAnalyzer.swift (473 lines), Models/PeopleModels.swift (385), ViewModels/PeopleViewModel.swift (576), Views/PeopleWorkspaceView.swift (1,198, including PeopleInspectorView at 712 and FaceCropThumbnailView at 1067), `PeopleSidebarView` occupying ContextualWorkspaceSidebars.swift:3-172 of 361, and Tests/RAWDeskTests/PeopleTests.swift (984). Surgical seams (in-file excision, ~1,000 lines across 16 shared files): CatalogStore.swift (~860 lines, six regions -- see the separate finding); ContentView.swift (the `@StateObject` at 14, four `@AppStorage` keys at 48-56, ~19 `case .people:` arms, and PeopleAnalysisLifecycleModifier at 2521-2554 attached unconditionally at 1243-1248); LibraryViewModel.swift (112-113, 182, 225-255, 834-838, 911-917, 943-957, 1048-1126, 4879-4881); the import result fields in PhotoImportModels.swift:442-536 threading into PhotoImportView.swift:821-857/1047-1079 and AutoImportService.swift:294-330; AutoImportModels.swift:44-79/201-312; AutoImportSettingsView.swift:394-402; ToolbarContent.swift:117/182-183/266/346-347/481-482; WorkspaceMode.swift:112/121/130/139/154/162/170; RAWDeskApp.swift:430-434/710-711; LibrarySidebarView.swift:88/112-116/486-516; CatalogModels.swift:107-138. Two facts that bound the decision: (a) every automatic People path defaults to off -- `automaticAnalysisEnabled: Bool = false` (PeopleModels.swift:11), `analyzePeopleAfterImport: Bool = false` (AutoImportModels.swift:63), `@State private var analyzePeopleAfterImport = false` (PhotoImportView.swift:23) -- so an unused People feature does not burn CPU in the background; its residual cost is structural, not computational. (b) Removing People would not remove face detection from the app: AssistedCullingAnalyzer runs its own `VNDetectFaceLandmarksRequest` (AssistedCullingAnalyzer.swift:943) over its own `AssistedCullingFaceAnalysis` type (159) for eye-open and eye-sharpness culling signals, with zero references to PeopleAnalyzer, CatalogFace, CatalogPerson or the People tables.


**修正方針:** Present this map as the decision input. If People stays, harvest the low-cost wins independently of the removal question (the LibrarySidebarView decoupling, the main-actor work, the two unread summary counts, the sidebar placement). If People goes, execute in this order: delete the six clean-seam files/types, then LibraryViewModel and ContentView, then the import-path fields, then the six CatalogStore regions last, leaving the three tables in `migrate()` as inert until a later schema pass so no existing catalog breaks.


#### [中] Two of the three People summary counts are computed on every catalog refresh but never read by the UI

**場所:** `Services/CatalogStore.swift`:2442


`CatalogOverview` carries `peopleCount`, `faceCount` and `unconfirmedFaceCount` (CatalogModels.swift:107-109), and `summary()` runs a separate `SELECT COUNT(*)` for each (CatalogStore.swift:2439-2456). Only `peopleCount` is read anywhere in `Sources/` -- LibrarySidebarView.swift:114. `faceCount` and `unconfirmedFaceCount` are read only by tests (RAWDeskTests.swift:7660 and 15682). The People workspace's own unconfirmed-face badge comes from PeopleViewModel's in-memory snapshot (PeopleViewModel.swift:134-138, used at PeopleWorkspaceView.swift:119), not from this field. The summary is refreshed by `LibraryViewModel.refreshCatalogOverview()` (LibraryViewModel.swift:5314) and again on every `.rawDeskPeopleAnalysisDidChange` (ContentView.swift:2551).


**修正方針:** Delete the `faceCount` and `unconfirmedFaceCount` queries at CatalogStore.swift:2442-2456 and the corresponding fields at CatalogModels.swift:108-109, 123-124, 137-138. Update the two test assertions (RAWDeskTests.swift:7660, 15682) to read face counts via `catalog.catalogFaces(...)` instead. Keep `peopleCount`, which the sidebar badge uses.


#### [中] People schema, preference file I/O and analyzer instances are constructed unconditionally at startup

**場所:** `Services/CatalogStore.swift`:3866


Four unconditional costs exist even for a user who never opens People. (1) `migrate()` creates `catalog_people`, `catalog_face_analysis` and `catalog_faces` (CatalogStore.swift:3866-3910, the last with a `feature_print BLOB NOT NULL` column) plus three indexes (4173-4188) on every catalog open. (2) Constructing `PeopleViewModel` calls `preferencesStore.load()` (PeopleViewModel.swift:57-59), and `PeopleAnalysisPreferencesStore.init` does a `FileManager.createDirectory` while `load()` does a synchronous `Data(contentsOf:)` (PeopleModels.swift:38-73) -- this happens at ContentView construction because of the `@StateObject` at ContentView.swift:14, in every workspace. (3) `LibraryViewModel.init` builds a `PeopleAnalyzer` unconditionally (LibraryViewModel.swift:236-242) and (4) so does `AutoImportService.init` (AutoImportService.swift:39-43). Additionally, `PeopleAnalysisLifecycleModifier` (ContentView.swift:2521-2554) is attached unconditionally at ContentView.swift:1243-1248, installing four observers -- onAppear, a `catalogSummary[.allPhotos]` onChange, a scenePhase onChange, and a NotificationCenter subscription -- in every workspace.


**修正方針:** Make the ownership lazy rather than the behaviour different: move the `people` view model and `PeopleAnalysisLifecycleModifier` into the `case .people:` branch that already exists (ContentView.swift:799-800, 880-883, 920-923) so they are constructed on first entry to the People workspace rather than at app launch. Note that the scenePhase observer at ContentView.swift:2537-2543 also calls `library.flushPendingPersistence()`, which is not People work -- lift that one call out into its own modifier before moving the rest, or persistence breaks.


#### [中] An interactive or automatic People scan stats every photo in the catalog before doing any face work

**場所:** `Services/PeopleAnalyzer.swift`:37


`PeopleAnalyzer.scan` opens with `try catalogStore.refreshMissingStatus(photoIDs: photoIDs)` (PeopleAnalyzer.swift:37-39), which queries every matching row and stats each file on disk (CatalogStore.swift:2027-2060). Both import paths scope this correctly -- LibraryViewModel.swift:1093-1097 and AutoImportService.swift:299-303 pass the imported photo IDs. But `PeopleViewModel.beginScan` calls `analyzer.scan(forceReanalysis:)` with no `photoIDs` (PeopleViewModel.swift:238-239), so `photoIDs` is `nil` and the filter is dropped, stat-ing the whole catalog. This is the path taken by `startIfNeeded()` on first entry to the People workspace (PeopleViewModel.swift:152-157) and by every automatic scan (159-168).


**修正方針:** Move the `refreshMissingStatus` call from the top of `scan` (line 37-39) into the per-candidate loop it duplicates, or scope it to the candidate set after `peopleAnalysisCandidates` returns. The per-candidate snapshot check at lines 63-75 already handles the missing-file case and calls `clearPeopleFaceAnalysis` for it.


#### [中] Post-import People analysis is implemented twice with duplicated user-facing strings

**場所:** `ViewModels/LibraryViewModel.swift`:1089


`addingPeopleAnalysis` exists in two places with near-identical bodies and byte-identical user-facing copy: LibraryViewModel.swift:1089-1126 (manual import) and AutoImportService.swift:294-330 (watched-folder import). Both build the same photo ID set, call `peopleAnalyzer.scan(photoIDs:)`, assign the same four result fields, and emit the same three strings -- for example "The import completed safely; local People analysis was stopped." appears at LibraryViewModel.swift:1121 and AutoImportService.swift:325. Around them, four `PhotoImportResult` fields (PhotoImportModels.swift:490-536) and a `analyzingPeople` progress phase (442, 451) thread into PhotoImportView.swift:821-857 and 1047-1079, AutoImportModels.swift:44-79/201-312, and AutoImportSettingsView.swift:394-402.


**修正方針:** Collapse the two implementations into one. `AutoImportService` already holds a `PeopleAnalyzer` (AutoImportService.swift:24) -- give `PeopleAnalyzer` a single `func applying(to: PhotoImportResult, photoIDs:progress:) async -> PhotoImportResult` that owns the four field assignments and the three strings, and have both call sites use it. This is a consolidation, not a behaviour change: the resulting messages should be identical to today's.


#### [低] "People" is listed as a row inside the sidebar's "Folders" section

**場所:** `Views/LibrarySidebarView.swift`:486


`Section("Folders")` at LibrarySidebarView.swift:486 contains, in order: a People button that switches workspace (487-516), a Map button that switches workspace (518-532), "Import Photos..." (534-543), "Open Folder..." (545-551), and a "Recursive scan" toggle (553-554). Not one of the five is a folder. Meanwhile the workspace switcher already offers Library / Develop / People / Map in the toolbar (ToolbarContent.swift:117, 346-347) and in the menu bar (RAWDeskApp.swift:430-434), so People and Map are reachable by three routes and the sidebar route is the one filed under the wrong heading.


**修正方針:** Remove the People and Map buttons from this section (LibrarySidebarView.swift:487-532); both destinations already exist in the toolbar segmented control (ToolbarContent.swift:481-482) and the View menu (RAWDeskApp.swift:430-434). Rename the remaining section from "Folders" to "Import" to match its actual contents (Import Photos..., Open Folder..., Recursive scan). This also removes the last reason for LibrarySidebarView to hold a PeopleViewModel.
