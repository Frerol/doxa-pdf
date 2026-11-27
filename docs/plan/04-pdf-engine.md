# 04 — PDF Engine

## 1. Why PDFium

See [ADR-0002](../adr/0002-pdfium-as-pdf-engine.md). In short: high rendering fidelity (it powers Chrome's viewer),
a permissive license (BSD-3-Clause / Apache-2.0) that is compatible with GPL-3.0, prebuilt binaries for every target,
and a C API covering rendering, text, annotations, forms, page objects and saving.

## 2. Getting the binaries

| Source | Use |
|---|---|
| [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) | Default for development and GitHub/Play/Windows/Flathub builds. Pin an exact release and verify its SHA-256 in `tools/fetch_pdfium`. |
| Built from source (`gn`/`ninja`, V8/XFA disabled) | Required for **F-Droid**, which rejects prebuilt binaries. A reproducible build script lives in `tools/build_pdfium/`. |

- Build flavour: **no V8 (no JavaScript), no XFA**. This shrinks the binary, reduces attack surface and fits NFR-SEC-002.
- `pdfium_ffi` loads `libpdfium.so` (Android/Linux) or `pdfium.dll` (Windows) bundled with the app. It never uses a system copy.
- Bindings are generated with `ffigen` from the pinned headers. A CI check fails if the generated bindings drift from the headers.

### Prior art (decided in M0)
[`pdfrx`](https://pub.dev/packages/pdfrx) (MIT) already wraps PDFium for Flutter on all target platforms. M0 chose between:
**(a)** depending on pdfrx for viewing and adding our own FFI for editing, or **(b)** owning the full binding layer.
**Decided: (b)**, with pdfrx as reference code, because annotations-off rendering, tile scheduling and write access are core to the product. `packages/pdfium_ffi` holds the bindings, and Spikes A, C and D were built on them.

## 3. Capability map

| Need | PDFium API | Gap / plan |
|---|---|---|
| Open, password | `FPDF_LoadDocument` (paths, including `/proc/self/fd/<fd>` for SAF URIs on Android) and `FPDF_LoadMemDocument64` | `FPDF_LoadCustomDocument` (read callbacks) if a provider gives no seekable descriptor |
| Render tiles | `FPDF_RenderPageBitmapWithMatrix` + clip on the render instance, with `FPDF_ANNOT`; from M2, Doxa's own annotations are hidden in memory there (ADR-0005) | Progressive render for heavy pages (`FPDF_RenderPageBitmap_Start`) |
| Foreign annotations layer | `FPDF_FFLDraw` / rendering with annotations | Exact approach decided in M0 → ADR-0005 |
| Text, selection, search | `FPDFText_*` (chars, boxes, `FPDFText_FindStart`) | Diacritic-insensitive search done in Dart over extracted text with an index map |
| Outline, links, page labels | `FPDFBookmark_*`, `FPDFLink_*`, `FPDF_GetPageLabel` | — |
| Read/write annotations | `FPDFPage_CreateAnnot`, `FPDFAnnot_AppendAttachmentPoints`, `FPDFAnnot_AddInkStroke`, `FPDFAnnot_SetStringValue`, `FPDFAnnot_SetColor`, `FPDFPage_RemoveAnnot` | `FPDFAnnot_SetAP` cannot attach resources (no Multiply). Ink AP via `FPDFAnnot_AppendObject`, called last. Markup without AP (§4) |
| Private keys (`/DoxaPressure`, `/NM`) | `FPDFAnnot_SetStringValue`; arrays not directly supported | Encode pressure as a compact string (base64 of quantized samples) |
| Save | `FPDF_SaveAsCopy` **full save** (flags 0), streamed to a temp file | `FPDF_INCREMENTAL` is unusable: it rewrites loaded objects and corrupts xref-stream files ([Spike C](../spikes/C-annotation-write.md)). Own incremental writer post-MVP |
| Insert note pages (M3) | `FPDFPage_New` + page objects for ruling/grid | — |
| Page organization (alpha 4) | `FPDF_ImportPages`, `FPDFPage_SetRotation`, `FPDFPage_Delete`, `FPDF_MovePages` | — |
| Forms (later) | `FPDFDOC_InitFormFillEnvironment`, `FORM_*` | — |
| OCR text layer (alpha 4) | Invisible text objects (`FPDFPageObj_CreateTextObj`, render mode 3) fitted to each word box | Tesseract4Android runs in a Kotlin worker ([ADR-0007](../adr/0007-ocr-integration.md), [Spike D](../spikes/D-ocr.md)) |
| Encryption / compression (later) | Not supported for writing | Add qpdf (Apache-2.0) behind the same engine interface |
| Content editing (future) | `FPDFPage_*`/`FPDFPageObj_*`/`FPDFText_*` object APIs | Feasible for objects; text reflow is hard. Revisit via ADR |

## 4. Writing annotations

> **Updated by [Spike C](../spikes/C-annotation-write.md) / [ADR-0008](../adr/0008-annotation-save-strategy.md):** in the MVP, text markup is written **without** `/AP`, ink gets an AP built from page objects (`FPDFAnnot_AppendObject`, after all dictionary setters), and saves are full saves. The hand-written appearance-stream writer described below is the target for the post-MVP incremental writer.

Each Doxa-created annotation carries the ownership marker of [ADR-0005](../adr/0005-rendering-pipeline-and-foreign-annotations.md) §5:
an `/NM` of `doxa:` plus a UUID v4, and the private key `/DoxaVersion` with the text value `1` (`DoxaMarker` in `doxa_core`). Both
must be present: the prefix alone, which another app could copy, does not make an annotation Doxa's. The version goes up when what Doxa
writes changes, for example the `/DoxaPressure` encoding (one base64url character per quantised pressure, a comma between strokes).
Doxa's ink also carries `/DoxaTool` (`pen` or `highlighter`); without it, ink counts as drawn by the pen. Doxa's text markup keeps the
text it covers in `/DoxaText` (FR-MARK-010), because `/Contents` is the note that other readers show and that holds the user's note (FR-NOTE-002).

Each Doxa-created annotation includes:
- The standard keys: `/Subtype`, `/Rect`, `/C`, `/CA`, `/NM`, `/M`, `/CreationDate`, `/T` (author), `/Contents`, `/F` (Print).
- Geometry: `/QuadPoints` for markup and `/InkList` for ink.
- **`/AP /N` appearance stream** generated by `doxa_engine/appearance/` (content-stream writer):
  - Highlight: filled quads with `/BM /Multiply` in an ExtGState, opacity from `/CA`.
  - Underline/StrikeOut/Squiggly: stroked lines placed relative to each quad's baseline and orientation.
  - Ink: the variable-width outline as a filled path (pen) or a flat-tipped stroke (highlighter, multiply).
- Correct behaviour on **rotated pages** (`/Rotate`) and pages with a non-zero `/CropBox` origin. Both are well-known sources of misplaced annotations, and the test corpus must cover them.

Interop is verified by rendering the saved output with pdf.js, MuPDF and Poppler in CI and comparing against goldens ([QA §3](06-quality-assurance.md#3-pdf-test-corpus--interoperability)).

## 5. Engine interface

Implemented in `packages/doxa_engine` (issue #46). Annotation reading, editing and saving arrive in M2.

```dart
abstract interface class PdfEngine {
  Future<OpenResult> open(DocumentSource source, {String? password});    // DocumentOpened | PasswordRequired | WrongPassword | OpenFailed
  Future<void> close(DocumentHandle document);

  Future<PageDetails> pageDetails(DocumentHandle document, int pageIndex); // crop box + rotation → PageTransform
  Future<List<OutlineNode>> outline(DocumentHandle document);
  Future<List<PageLink>> pageLinks(DocumentHandle document, int pageIndex);

  Future<RenderResult> render(RenderRequest request, {CancelToken? cancel}); // RGBA bitmap | RenderSkipped
  void setGeneration(DocumentHandle document, int generation);            // drops stale queued renders

  Future<PageText> pageText(DocumentHandle document, int pageIndex);       // chars + boxes, cached
  Stream<SearchHit> search(DocumentHandle document, SearchQuery query);    // page by page; cancel the subscription to stop

  Future<void> dispose();
}
```

- `PdfiumEngine` runs every PDFium call in one engine isolate. Commands and replies are typed classes; a priority queue runs one job per
  event-loop turn (visible previews, visible tiles, near previews, near tiles, search pages, thumbnails, background), so cancellations
  and new generations apply before the next job. Every failure becomes a typed reply, so one bad document never stops the engine.
- Each document has a render instance (rendered with `FPDF_ANNOT`) and an editing instance loaded on demand (ADR-0005).
- Text boxes and destinations are in PDF user space; `PageDetails.transform()` maps them to the view.
- `FakePdfEngine` (`package:doxa_engine/testing.dart`) lets UI and controller tests run without native code.
