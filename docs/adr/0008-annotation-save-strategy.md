# ADR-0008 — Annotation save strategy

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
The plan assumed incremental saves through PDFium (FR-SAVE-004) and Doxa-generated appearance streams for every annotation type
([PDF engine §4](../plan/04-pdf-engine.md#4-writing-annotations)). [Spike C](../spikes/C-annotation-write.md) found that:
- PDFium's incremental save rewrites every loaded object (+15.5 MB per save after reading 30 pages of a 155 MB file), and produces a malformed xref stream for PDFs that use xref streams;
- `FPDFAnnot_SetAP` cannot attach resources, so a text-string AP cannot use the Multiply blend a highlight needs;
- PDFium only generates markup APs while rendering with `FPDF_ANNOT`, which also rewrites foreign annotations (adds a private key, changes `/Rect`);
- the full save is valid, fast (272 ms for 155 MB on the reference tablet), and leaves foreign annotations byte-identical;
- every tested reader, including a commercial Android reader, draws AP-less highlight/underline/squiggly correctly.

## Decision
For the MVP:
1. **Full save only:** stream `FPDF_SaveAsCopy(flags = 0)` to a temp file, verify it (reopen), then replace the original atomically.
   On Android, write back through SAF with `"wt"`, read it back and compare SHA-256. Fall back to "Save a copy" if the provider cannot write.
2. **Text markup is written without `/AP`** (`/QuadPoints`, `/C`, `/CA`, `/NM`, `/T`, `/M`, `/Contents`, `/F` print).
3. **Ink AP is built from page objects** with `FPDFAnnot_AppendObject`, called after every dictionary setter.
4. The document instance used for editing and saving is **never rendered with `FPDF_ANNOT`**.

After the MVP, an own incremental-update writer in Dart replaces the full save for unencrypted files. It will write exact annotation
dictionaries and APs, including Multiply highlights, appended as a true incremental update.

## Consequences
- Saves are correct and fast enough (NFR-PERF-008) with a single code path on all platforms.
- Every save rewrites the file. This invalidates existing digital signatures, so signed PDFs must warn the user or force "Save a copy" until the incremental writer exists. FR-SAVE-004 moves to post-MVP.
- AP-less markup is legal in PDF 1.7 but not PDF 2.0, and depends on the reader generating an appearance (all tested readers do). The future writer removes this dependency.
- The atomic-replace logic needs the extra disk space of one file copy.

## Alternatives considered
- **PDFium incremental save:** file growth and malformed xref streams. Rejected.
- **Let PDFium generate markup APs by rendering before saving:** modifies foreign annotations (FR-ANNO-002). Rejected.
- **Text-string AP via `FPDFAnnot_SetAP`:** no Multiply, so text is hidden. Rejected.
- **Patched PDFium build** (expose single-annotation AP generation, fix the xref-stream bug): possible together with the F-Droid source build (R5), but it is a fork to maintain. Kept as a fallback.
- **qpdf for writing:** cannot append incremental updates, and adds a C++ dependency on Android.
