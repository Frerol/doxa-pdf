<p align="center">
  <img src="assets/brand/banner.png" alt="Doxa PDF: the free PDF reader for studying" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Frerol/doxa-pdf/actions/workflows/ci.yml"><img src="https://github.com/Frerol/doxa-pdf/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-7048E8" alt="License: GPL-3.0-or-later"></a>
  <img src="https://img.shields.io/badge/platforms-Android%20%C2%B7%20Linux%20%C2%B7%20Windows-2BAE66" alt="Platforms: Android, Linux, Windows">
  <img src="https://img.shields.io/badge/status-M2%20alpha%202%20markup%20%2B%20pen-F08C00" alt="Status: M2, alpha 2 markup and pen">
</p>

# Doxa PDF

**Doxa PDF** is a free and open-source PDF reader for **studying**, on **Android, Windows and Linux**.
It is built around two things: **marking up text** (highlight, underline, strikeout) and **writing on
the page with a pen** (low-latency, pressure-sensitive ink with palm rejection). Everything is stored as
standard PDF annotations, so your notes open in any reader. It runs offline, has no telemetry, no ads and no paywall.

> **Status: M2, building alpha 2 (text markup and pen).** The first public alpha, [`1.0.0-alpha.1`](https://github.com/Frerol/doxa-pdf/releases/tag/v1.0.0-alpha.1),
> is a reader: tabs, outline, thumbnails, search, offline dictionary and page colours. The **Android MVP** continues as public alphas, then betas, on the way to 1.0.0
> ([MVP](docs/plan/11-mvp.md)). The engineering plan lives in [`docs/`](docs/README.md).

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

## Install on Android

Alphas, betas and release candidates are published as signed APKs on [GitHub Releases](https://github.com/Frerol/doxa-pdf/releases),
one per processor type (ABI). Most phones and tablets need `arm64-v8a`. Each release lists the SHA-256 of every file in `SHA256SUMS`.

Every APK is signed with the same certificate. Its SHA-256 fingerprint, for apps such as AppVerifier, is:

```
0D:13:29:80:C6:02:1A:7E:BA:42:48:65:A1:CB:EA:3D:C1:98:CB:38:01:E7:57:DA:D5:DB:E5:09:1B:71:BB:96
```

### With Obtainium (updates included)

[Obtainium](https://github.com/ImranR98/Obtainium) installs apps from their release pages and keeps them up to date.

1. In Obtainium, tap **Add app** and enter `https://github.com/Frerol/doxa-pdf`.
2. Turn on **Include prereleases**: until 1.0.0, every Doxa release is a pre-release.
3. In **Filter APKs by regular expression**, enter the filter for your device:

   | Device | Filter |
   |---|---|
   | Most phones and tablets (`arm64-v8a`) | `^doxa-pdf-.+-arm64-v8a\.apk$` |
   | Older 32-bit ARM devices (`armeabi-v7a`) | `^doxa-pdf-.+-armeabi-v7a\.apk$` |
   | Emulators and x86 devices (`x86_64`) | `^doxa-pdf-.+-x86_64\.apk$` |

4. Tap **Add**, then **Install**.

### By hand

Download the APK for your device from the [latest release](https://github.com/Frerol/doxa-pdf/releases) and open it. Android asks
you to allow installs from your browser or file manager the first time. Install later versions the same way, over the old one: your
library and settings are kept.

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
