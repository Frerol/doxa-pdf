<p align="center">
  <img src="assets/brand/banner.png" alt="Doxa PDF: the free PDF reader for studying" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Frerol/doxa-pdf/actions/workflows/ci.yml"><img src="https://github.com/Frerol/doxa-pdf/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-7048E8" alt="License: GPL-3.0-or-later"></a>
  <img src="https://img.shields.io/badge/platforms-Android%20%C2%B7%20Linux%20%C2%B7%20Windows-2BAE66" alt="Platforms: Android, Linux, Windows">
  <img src="https://img.shields.io/badge/status-M1%20alpha%201%20reader-F08C00" alt="Status: M1, alpha 1 reader">
</p>

# Doxa PDF

**Doxa PDF** is a free and open-source PDF reader for **studying**, on **Android, Windows and Linux**.
It is built around two things: **marking up text** (highlight, underline, strikeout) and **writing on
the page with a pen** (low-latency, pressure-sensitive ink with palm rejection). Everything is stored as
standard PDF annotations, so your notes open in any reader. It runs offline, has no telemetry, no ads and no paywall.

> **Status: M1, building the alpha 1 reader.** M0 is done: the monorepo, PDFium bindings, CI and the rendering, ink, annotation-writing and OCR
> spikes ([reports](docs/README.md#spike-reports-m0)). Now comes the **Android MVP**, shipped as public alphas, then betas, on the way to 1.0.0 ([MVP](docs/plan/11-mvp.md)). The engineering plan lives in [`docs/`](docs/README.md).

## Goals

- **Built for studying**: fast, comfortable reading; text markup in seconds; pen input that feels like paper.
- **One codebase, three platforms**: Flutter UI with [PDFium](https://pdfium.googlesource.com/pdfium/) as the rendering engine.
- **Your notes stay yours**: standard PDF annotations, offline by default, export to Markdown, no account.
- **Free forever**: licensed under GPL-3.0-or-later.

## Planned feature set (1.x)

| Area | Highlights |
|---|---|
| Read | Continuous/single/two-page/horizontal layouts, smooth zoom, tabs, outline, thumbnails, full-text search, offline dictionary, night/sepia/custom colours, resume where you stopped |
| Mark up text | Highlight, underline, strikeout, squiggly with a quick color palette; notes attached to highlights |
| Pen | Pressure-sensitive ink, highlighter pen, stroke and pixel eraser, lasso select/move, stylus-only mode with palm rejection, undo/redo |
| Notes | Sticky notes, text boxes, shapes, stamps, blank note pages inserted between pages |
| Scans & pages | On-device OCR for scanned pages, page organization (rotate, reorder, insert, merge, split), printing |
| Review | Annotation panel filtered by color/type/page, jump to annotation, export to Markdown |
| Platform | File associations, "Open with", recents and favorites, light/dark themes, i18n, accessibility |

Form filling, signatures, EPUB, OPDS, KoSync and cloud accounts come after the Android, Linux and Windows releases.
See the [requirements](docs/plan/02-requirements.md) and [roadmap](docs/plan/08-roadmap.md).

## Documentation

- [Engineering plan index](docs/README.md)
- [Architecture Decision Records](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## Support

[Support Doxa on Ko-fi](https://ko-fi.com/P2S82BD7LL)

## License

Doxa PDF is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE).

Doxa PDF is an independent project. It is not affiliated with or endorsed by any commercial PDF product or vendor.
