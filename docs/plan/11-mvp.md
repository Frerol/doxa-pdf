# 11 — MVP Definition

Agreed with the maintainer on 2026-11-24 (offline dictionary and the feature review below added the same day). The MVP is **Android-only** and is shipped as a series of **public beta releases on
GitHub** (no stores yet). Each beta is usable on its own, and the MVP is complete at **v0.4**.

## 1. Target

| Item | Decision |
|---|---|
| Platform | Android tablet first, phones supported. Desktop comes after the MVP: **Linux first**, then Windows |
| Reference device | **Samsung Galaxy Tab S10 FE with S Pen, Android 16** ([QA §4](06-quality-assurance.md#4-performance-budgets)) |
| Minimum Android | **Android 10 (API 29)** |
| Typical documents | **Large textbooks** (hundreds of pages, 50 MB+), **scientific articles** (two columns, formulas), **scanned material** (frequent) |
| Distribution | Signed APKs on GitHub Releases (also installable through Obtainium) |
| UI languages | **Portuguese (pt-BR) and English** from the first beta |
| Interop targets | Acrobat Reader, a widely used commercial Android reader, Firefox (pdf.js), Chrome, Okular. Automated in CI with pdf.js, Poppler and MuPDF; manual checks on Acrobat and that Android reader before each beta |

## 2. Interaction model

- **The S Pen always writes** with the current pen (or erases with the eraser end/side button). No mode switch is needed.
- **Fingers read**: scroll, zoom and tap. Finger annotation (text markup, notes, shapes) is chosen from the toolbar.
- **The toolbar is fixed at the top**, below the app bar, and stays visible while annotating.
- Stylus-writes/finger-reads turns on automatically when a stylus is detected. On devices without a stylus, a toolbar toggle lets the finger draw.

## 3. Betas and scope

### v0.1 — Reader
| Area | Included |
|---|---|
| Files | System picker, "Open with" intents, recents (thumbnail + progress), **library folders**, **favorites**, rename/move/delete, **tabs** for several open documents, password-protected PDFs |
| Reading | All four layouts: **continuous vertical, single page, two pages side by side, horizontal**. Zoom, fit width/page, fullscreen. Remember page and zoom per document. Save layout, cover page, tap zones and keep zoom as global defaults. **Right-to-left** page order is per document |
| Navigation | **Outline**, **thumbnails**, go to page, links + back/forward |
| Search & text | **Full-text search** (diacritic-insensitive), text selection + copy, **offline dictionary** for the selected word or short phrase (StarDict dictionaries imported by the user, [ADR-0009](../adr/0009-offline-dictionary.md)) |
| Comfort | Global **night, sepia and custom colour** modes, light/dark theme, pt-BR + en |

### v0.2 — Study core: markup + pen ★ (the point where the maintainer starts studying with Doxa daily)
| Area | Included |
|---|---|
| Text markup | **Highlight, underline, squiggly** (strikeout creation deferred; existing strikeouts are still displayed and editable), color palette, sticky tool, edit/recolor/delete, correct selection order in two-column articles, **text-snapping pen and highlighter** (a freehand stroke over text becomes a text markup) |
| Scanned pages | **Area highlight** (rectangle) and the highlighter pen, until OCR arrives in v0.4 |
| Pen | **Pressure-sensitive** pen, **highlighter pen**, **style presets for every tool**, free colour picker, S Pen side button and eraser mapping |
| Eraser | **Whole-stroke and partial** erasers |
| Selection | **Lasso**: move, resize, recolor, delete |
| Safety | Undo/redo, **autosave into the original file** with atomic write + crash-recovery journal |

### v0.3 — Notes & review
| Area | Included |
|---|---|
| Notes | **Notes attached to highlights**, **sticky notes**, **text boxes** (with font choice), **blank/ruled/grid note pages** inserted between pages |
| Drawing extras | **Shapes** (line, arrow, rectangle, ellipse), **shape recognition** (hold at the end of a stroke), **stamps** (✓ ✗ ? ! and custom text) |
| Review | **Annotations panel** (filter by color/type/page, jump to item), **color labels** ("Definition", "Exam"…), **bookmarks**, **outline editing**, **Markdown export** of highlights and notes |
| Output | **Print** (with annotations) |

### v0.4 — OCR + pages → MVP complete
| Area | Included |
|---|---|
| OCR | On-device **Tesseract** OCR (pt + en models, more downloadable) adds an invisible text layer to scanned pages. Runs per page or for the whole document in the background and can be cancelled. Afterwards those pages support search, selection and text markup |
| Pages | **Page organization**: rotate, delete, reorder, duplicate, insert (blank, image, another PDF), extract, merge, split, crop, edit page labels |
| Hardening | Performance pass on large textbooks, beta feedback fixes, interop sweep |

## 4. Explicitly not in the MVP
Desktop builds (Linux is the next milestone), store publishing, strikeout creation, annotation sync between devices,
forms/signatures, Acrobat-style editing, EPUB, OPDS, KoSync and cloud storage accounts, and the other post-1.0 items in
[requirements](02-requirements.md) (reflow, read-aloud, in-app translation, measurement, redaction, scanning…).

## 5. MVP exit criteria
1. The maintainer studies a full textbook chapter and a scientific article on the reference tablet using only Doxa PDF: highlighting, handwriting, notes, review and export.
2. Ink latency and scrolling meet [NFR-PERF-003/004](02-requirements.md#21-performance-perf) on the reference tablet.
3. A 1000-page, 100 MB+ textbook opens, scrolls and searches within budget.
4. A scanned chapter can be OCR'd, then searched and highlighted.
5. Annotations display correctly in every interop target listed in §1.
6. No known S1 bugs. Zero annotation loss in kill/crash tests.
