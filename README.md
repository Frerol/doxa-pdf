# Doxa PDF

**Doxa PDF** is a free and open-source PDF reader for **studying**, on **Android, Windows and Linux**.
It is built around two things: **marking up text** (highlight, underline, strikeout) and **writing on
the page with a pen** (low-latency, pressure-sensitive ink with palm rejection). Everything is stored as
standard PDF annotations, so your notes open in any reader. It runs offline, has no telemetry, no ads and no paywall.

> **Status: planning.** No application code exists yet. The engineering plan lives in [`docs/`](docs/README.md).

## Goals

- **Built for studying**: fast, comfortable reading; text markup in seconds; pen input that feels like paper.
- **One codebase, three platforms**: Flutter UI with [PDFium](https://pdfium.googlesource.com/pdfium/) as the rendering engine.
- **Your notes stay yours**: standard PDF annotations, offline by default, export to Markdown, no account.
- **Free forever**: licensed under GPL-3.0-or-later.

## Planned feature set (v1.0)

| Area | Highlights |
|---|---|
| Read | Continuous/single/two-page layouts, smooth zoom, tabs, outline, thumbnails, full-text search, night/sepia modes, resume where you stopped |
| Mark up text | Highlight, underline, strikeout, squiggly with a quick color palette; notes attached to highlights |
| Pen | Pressure-sensitive ink, highlighter pen, stroke and pixel eraser, lasso select/move, stylus-only mode with palm rejection, undo/redo |
| Notes | Sticky notes, text boxes, shapes, blank note pages inserted between pages |
| Review | Annotation panel filtered by color/type/page, jump to annotation, export to Markdown |
| Platform | File associations, "Open with", recents and favorites, light/dark themes, i18n, accessibility |

Page organization (merge, split, reorder) and form filling are secondary features planned after the core study experience.
See the [requirements](docs/plan/02-requirements.md) and [roadmap](docs/plan/08-roadmap.md).

## Documentation

- [Engineering plan index](docs/README.md)
- [Architecture Decision Records](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

Doxa PDF is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE).

Doxa PDF is an independent project. It is not affiliated with or endorsed by any commercial PDF product or vendor.
