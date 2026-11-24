# ADR-0005 — Rendering pipeline and the foreign-annotation layer

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
The reader must stay at 60–90 fps on 1,000-page textbooks and scanned books (NFR-PERF-002/003/006). Spike B showed that committed ink must live in raster tiles.
Spike C showed that the document instance used for editing must never be rendered with `FPDF_ANNOT`, because PDFium then rewrites foreign annotations.
Annotations made by other apps still have to be visible. [Spike A](../spikes/A-rendering.md) prototyped the pipeline on the reference tablet.

## Decision
1. A single **engine isolate** owns PDFium. Render requests carry a priority and a viewport generation, and stale requests are dropped.
2. The view shows a **low-resolution preview per page** (360 px) and **512 px tiles at power-of-two zoom buckets**, kept in an LRU image cache sized by device memory.
3. Each open file has **two PDFium document instances**:
   - **render instance**: read-only. Annotations owned by Doxa get the Hidden flag **in memory only**, and pages are rendered with `FPDF_ANNOT`, so tiles contain page content plus foreign annotations. It is never saved;
   - **editing instance**: holds Doxa's changes and is the only one saved (ADR-0008). It is never rendered with `FPDF_ANNOT`.
4. Doxa's own annotations are drawn by Flutter on top of the tiles (live layer for the stroke in progress, rasterized ink layer for committed ink, ADR-0006).
5. Doxa recognises its own annotations by a marker it writes (`/NM` prefix plus a private key).

## Consequences
- Measured on the tablet: first page in 52–151 ms, zero janky frames, zero blank frames while scrolling and zooming.
- Two instances roughly double PDFium's per-document memory. That is acceptable, since PDFium loads lazily. RSS still needs tuning for scanned books (385 MB peak versus the 400 MB budget).
- Editing a foreign annotation (rare) requires reloading that page in the render instance and invalidating its tiles.
- Saving changes the file on disk. The render instance reopens lazily, and existing tiles stay valid because page content is unchanged.

## Alternatives considered
- **Render everything, including Doxa's annotations, into tiles:** every edit would need a tile re-render and visible flashes (NFR-PERF-005). Rejected.
- **Render page content without annotations and skip foreign annotations:** loses other apps' notes (FR-ANNO-002). Rejected.
- **Single instance, toggling `FPDF_ANNOT` per render:** rendering with annotations mutates foreign annotations in the instance that gets saved (ADR-0008). Rejected.
- **Re-implement foreign annotation rendering in Flutter:** large effort, and it duplicates PDFium's appearance handling. Rejected.
