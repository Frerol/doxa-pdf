# Spike A — Tiled rendering of large textbooks and the foreign-annotation layer

- **Issue:** #5 · **Date:** 2026-11-24 · **Result: GO** (see [ADR-0005](../adr/0005-rendering-pipeline-and-foreign-annotations.md))
- **Device:** Galaxy Tab S10 FE, Android 16, 90 Hz · **Build:** Flutter 3.50.1 profile, Impeller/Vulkan · **Engine:** PDFium 160.0.8179.0
- **Prototypes:** `spikes/render_probe/` (desktop) and `spikes/render_lab/` (tablet) on the
  [`spike/render`](https://github.com/Frerol/doxa-pdf/tree/spike/render/spikes) branch (not merged)

## Test material
- `textbook-1000`: 1,000 text pages (46 lines each, two fonts, a vector figure every 5 pages), 1.3 MB, classic xref, flat page tree.
- `textbook-1000-objstm`: the same file re-saved with object streams and an xref stream (1.1 MB).
- `scanned-300`: 300 pages with a full-page 1700×2200 JPEG each (155 MB), standing in for a scanned book.

## Prototype design (Render Lab)
- **One long-lived engine isolate** owns PDFium. Requests carry a **priority** (visible preview > visible tile > nearby preview > nearby tile) and a
  **viewport generation**. On every viewport change the UI bumps the generation, and the engine drops stale tile requests. `Timer.run` between jobs lets new
  messages arrive before the next job is chosen.
- **Previews:** each page rendered 360 px wide, drawn scaled while tiles load.
- **Tiles:** 512×512 physical px at zoom buckets that are powers of two (1×, 2×, 4×, 8×). Rendered with `FPDF_RenderPageBitmapWithMatrix` directly into a
  native buffer in RGBA order (`FPDF_REVERSE_BYTE_ORDER`), sent as `TransferableTypedData`, and decoded with `decodeImageFromPixels`.
- **Cache:** LRU of decoded images, 160 MB budget; visible keys are never evicted. The engine keeps the last 8 `FPDF_PAGE` handles open.
- **View:** one `CustomPainter` (pages, preview, tiles); pan, pinch zoom and fling (`ClampingScrollSimulation`) repaint without rebuilding widgets. Annotations are not rendered (see §3).

## Findings

### 1. PDFium cost per operation (desktop, median)
| | textbook-1000 | …-objstm | scanned-300 |
|---|---|---|---|
| Open | 1.1 ms | 1.4 ms | 0.7 ms |
| Size of **all** pages (`FPDF_GetPageSizeByIndexF`, no page load) | 15 ms | 9 ms | 8 ms |
| Thumbnail 160 px | 0.8 ms | 0.7 ms | 21 ms (JPEG decode) |
| Fit width at 1440 px | 6.9 ms | 6.5 ms | 22 ms |
| Tile 512 px at 2× | 0.6 ms | 0.5 ms | 1.0 ms |
| Text page load | 0.8 ms | 0.7 ms | — |

The first `FPDF_LoadPage` on the flat-tree, classic-xref file took **956 ms on desktop**, but this did **not** reproduce on the tablet (first page painted in 76 ms).
It stays on the watch list for pathological files.

### 2. On the tablet (Render Lab, maintainer testing, ~35 interactions)
| | textbook-1000 | …-objstm | scanned-300 | Budget |
|---|---|---|---|---|
| Engine open | 24 ms | 30 ms | 56 ms | — |
| **First page painted** after the open request | **76 ms** | **52 ms** | **151 ms** | ≤ 500 ms (NFR-PERF-002) ✅ |
| Janky frames (build or raster > 11.1 ms) | 0 | 0 | 0 | ✅ NFR-PERF-003 |
| Build / raster p95 per frame | ~1 / ~2.5 ms | ~1 / ~2.5 ms | ~1 / ~3.9 ms | ✅ |
| Frames with a blank page (no preview yet) | 0 | 0 | 0 | ✅ |
| Tile latency p50 / p95 (request → decoded) | 10–36 / 42–98 ms | 14 / 33–47 ms | 11–13 / 119–141 ms | — |
| Engine render per job p50 / p95 | 2 / 5 ms | 2 / 4 ms | 2 / 31 ms | — |
| Process memory (RSS) | 256–287 MB | 269–287 MB | **355–385 MB** | ≤ 400 MB (NFR-PERF-006) ⚠️ |

The maintainer reported that every file "opened very fast and navigated without problems", with "very light hitches when scrolling very fast, barely noticeable".
No frame exceeded the budget, so the hitches are most likely **visual pop-in**: blurry previews swapped for sharp tiles, or the tile p95 of up to 141 ms on scanned pages.
The fixes are product tuning, listed in the decisions below.

### 3. Foreign annotations: hide Doxa's own in a read-only render instance
Doxa draws its own annotations as vectors in Flutter (instant edits, ADR-0006). Other apps' annotations must still appear, rendered by PDFium.
PDFium cannot render "annotations only", and must never render the **editing** document with `FPDF_ANNOT`, because that rewrites foreign annotations (ADR-0008).

Probe (`hidden_probe.dart`): on a separate, read-only document instance, setting the **Hidden** flag on Doxa-owned annotations **in memory** and rendering
with `FPDF_ANNOT` produces content + foreign annotations only. Clearing the flag restores them. The instance is never saved, so the flag never reaches the file.
Rendering with `FPDF_ANNOT` cost ~3 ms per 200×200 page with two annotations on desktop.

## Decisions (see [ADR-0005](../adr/0005-rendering-pipeline-and-foreign-annotations.md))
1. **Engine isolate with priority + generation-based cancellation**, as prototyped. All PDFium calls stay in that isolate.
2. **Two document instances per open file**: a **render instance** (read-only, `FPDF_ANNOT` on, Doxa-owned annotations hidden in memory) for tiles, previews
   and thumbnails, and an **editing instance** that is never rendered with annotations and is the only one saved.
3. **Tiles 512 px, power-of-two zoom buckets, 360 px previews**, LRU budget sized by device memory (start at 128 MB on a 4 GB device, 160 MB on 8 GB).
4. Tile pixels are rendered directly in RGBA into native memory and transferred with `TransferableTypedData`.
5. Tuning to remove the remaining pop-in, before v0.1:
   - prefetch previews further ahead during flings, using the scroll velocity;
   - keep the previous zoom bucket's tiles on screen until the new ones are ready, instead of falling back to the preview;
   - render previews for scanned pages at lower resolution, or reuse PDFium's embedded thumbnails when present;
   - cap RSS: smaller budget on scanned documents (decoded tiles are larger relative to text) and respond to `onTrimMemory`.
6. Doxa marks the annotations it owns (`/NM` prefix plus a private marker key) so the render instance can recognise them.

## Follow-ups
- Measure on a low-end device (4 GB RAM) and with real-world textbooks from the test corpus (#9).
- `onTrimMemory` handling and a memory-pressure test.
- After a save, reload the render instance lazily. Tiles stay valid, because page content does not change when only annotations change.
