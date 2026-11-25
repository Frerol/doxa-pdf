# 02 — Requirements

Each requirement has a stable ID. Reference IDs in issues, PRs and tests (for example `Implements FR-INK-003`).
**Priority** uses MoSCoW (M = Must, S = Should, C = Could). **MS** is the target milestone from the
[roadmap](08-roadmap.md). Platforms: **A** = Android, **W** = Windows, **L** = Linux. Every requirement applies to all three unless noted; the MVP (M1–M4) is
Android-only and desktop specifics land in M5 (Linux) and M6 (Windows). See [11 — MVP](11-mvp.md).

## 1. Functional requirements

### 1.1 Document opening & files (FILE)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-FILE-001 | Open PDF files through the system file picker (SAF on Android, native dialogs on desktop). | M | M1 |
| FR-FILE-002 | Register as a PDF handler: "Open with" / intents (A), file associations (W, L via `.desktop` MIME). | M | M1 |
| FR-FILE-003 | Open password-protected PDFs, prompting for the password. | M | M1 |
| FR-FILE-004 | Recent files list with thumbnail, last page and progress; remove entries from the list. | M | M1 |
| FR-FILE-005 | Favorites/pinned documents. | M | M1 |
| FR-FILE-006 | Built-in browser for user-chosen folders ("library folders") with sorting and search by name. | M | M1 |
| FR-FILE-007 | Open several documents as tabs (desktop and tablets); a document switcher on phones. | M | M1 |
| FR-FILE-008 | Detect when the file was changed or removed externally and offer to reload. | M | M3 |
| FR-FILE-009 | Open from drag-and-drop (W, L) and from the command line (`doxa-pdf file.pdf`). | S | M5 |
| FR-FILE-010 | Handle files that cannot be written back (read-only, content URIs without write permission) by offering "Save a copy". | M | M2 |
| FR-FILE-011 | Rename, move and delete documents from the library and recents (through SAF on Android), with confirmation for deletion. | M | M1 |
| FR-FILE-012 | Filter the library by file type and open the folder that contains the current document. | C | post-1.0 |
| FR-FILE-013 | Home-screen widget with recent documents (A). | C | post-1.0 |

### 1.2 Reading (VIEW)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-VIEW-001 | Render pages accurately (text, vector, images, fonts, transparency) using PDFium. | M | M1 |
| FR-VIEW-002 | Continuous vertical scroll; single-page (paged) mode; horizontal paging. | M | M1 |
| FR-VIEW-003 | Two-page (facing) layout, with an optional cover page. | M | M1 |
| FR-VIEW-004 | Pinch/ctrl+wheel zoom, double-tap smart zoom, fit width/page, zoom presets. | M | M1 |
| FR-VIEW-005 | Night mode (inverted, image-aware where possible) and sepia mode; follows the app theme or is set per document. | M | M1 |
| FR-VIEW-006 | Remember page, zoom and layout per document and restore them on reopen. | M | M1 |
| FR-VIEW-007 | Outline (table of contents) panel with navigation. | M | M1 |
| FR-VIEW-008 | Page thumbnails panel/grid with navigation. | M | M1 |
| FR-VIEW-009 | Go to page; page slider/scrubber with a page label preview. | M | M1 |
| FR-VIEW-010 | Follow internal links and confirm before opening external URIs. | M | M1 |
| FR-VIEW-011 | Navigation history (back/forward after link jumps). | M | M1 |
| FR-VIEW-012 | Fullscreen/immersive reading mode with auto-hiding toolbars. | M | M1 |
| FR-VIEW-013 | Keep screen on while reading (A, setting). | M | M1 |
| FR-VIEW-014 | Respect PDF page labels (roman numerals and so on) in all page UIs. | M | M1 |
| FR-VIEW-015 | Reading ruler/focus mode that dims everything except the current lines. | C | post-1.0 |
| FR-VIEW-016 | Custom colour mode: the user picks the page background and text colours, alongside night and sepia (same pipeline as FR-VIEW-005). | M | M1 |
| FR-VIEW-017 | Tap zones in paged layouts: tapping near the left/right (or top/bottom) edge turns the page; can be turned off. | M | M1 |
| FR-VIEW-018 | Keep the zoom level and horizontal offset when turning pages in paged layouts (setting). | M | M1 |
| FR-VIEW-019 | Right-to-left page progression for paged and two-page layouts (per document, for RTL books). | M | M1 |
| FR-VIEW-020 | Reflow reading mode: page text re-laid out in one column with adjustable font size. | C | post-1.0 |
| FR-VIEW-021 | Show and hide optional content layers (OCG). | C | post-1.0 |
| FR-VIEW-022 | Capture a rectangular page region as an image (copy or share). | C | post-1.0 |

### 1.3 Search & text (TEXT)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-TEXT-001 | Full-text search with result count, next/previous, and highlighting of all hits on visible pages. | M | M1 |
| FR-TEXT-002 | Search options: match case, whole word; diacritics-insensitive by default ("acao" finds "ação"). | M | M1 |
| FR-TEXT-003 | Results list with context snippets, grouped by page. | M | M3 |
| FR-TEXT-004 | Text selection with handles (touch) and drag (mouse); copy to clipboard. | M | M1 |
| FR-TEXT-005 | Selection follows reading order across columns and continues across a page boundary. | M | M2 |
| FR-TEXT-006 | Selection context actions: highlight, underline, strikeout, copy, search, share, define/translate via OS. | M | M2 |
| FR-TEXT-007 | Clear feedback when a page has no text layer (scanned) and markup is unavailable; later points to OCR. | M | M2 |
| FR-TEXT-008 | Look up the selected word or short phrase in built-in **offline dictionaries**: a popup shows the definitions of every enabled dictionary, with no network access ([ADR-0009](../adr/0009-offline-dictionary.md)). | M | M1 |
| FR-TEXT-009 | Import dictionaries in StarDict format (`.ifo` + `.idx`/`.idx.gz` + `.dict`/`.dict.dz`, optional `.syn`) from a file, folder or `.zip`; list, enable/disable, reorder and remove them. | M | M1 |
| FR-TEXT-010 | Lookup tolerates real text: trims surrounding punctuation, falls back to case- and diacritic-insensitive matches, follows synonym entries, and suggests close headwords when nothing matches. | S | M1 |
| FR-TEXT-011 | In-app translation of the selection or the whole document. Needs an ADR (online service vs. free offline models; never a proprietary SDK). Until then, FR-TEXT-006 hands off to an OS translator. | C | post-1.0 |

### 1.4 Text markup (MARK), Tier 1
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-MARK-001 | Create Highlight, Underline and Squiggly annotations from a text selection (StrikeOut creation: FR-MARK-012; existing StrikeOuts are always displayed and editable). | M | M2 |
| FR-MARK-002 | Quick palette with at least 6 user-configurable colors; recently used color is the default. | M | M2 |
| FR-MARK-003 | "Sticky tool" mode: once the highlighter is chosen, each drag over text creates a highlight right away, with no confirmation step. | M | M2 |
| FR-MARK-004 | Highlight by dragging freely over text with finger, mouse or stylus (the tool snaps to glyphs). | M | M2 |
| FR-MARK-005 | Tap a markup to change its color or type, add or edit a note, copy its text, or delete it. | M | M2 |
| FR-MARK-006 | Extend or shrink an existing highlight with handles. | M | M3 |
| FR-MARK-007 | Merge overlapping highlights of the same color into one annotation. | M | M3 |
| FR-MARK-008 | Opacity setting per markup tool (default for highlight is around 40% under multiply blend). | M | M2 |
| FR-MARK-009 | Rectangular "area highlight" for figures or scanned pages without text. | M | M2 |
| FR-MARK-010 | Store the selected text in the annotation (`/Contents` or a private key) for review and export. | M | M2 |
| FR-MARK-011 | Color labels: name palette colors (e.g. "Definition", "Exam"); labels are used for filtering and in exports. | M | M3 |
| FR-MARK-012 | Create StrikeOut annotations from a text selection. | S | M7 |
| FR-MARK-013 | Text-snapping pen and highlighter: a freehand stroke drawn over text (stylus or finger) is converted into a real text markup (highlight, underline or strikeout) on the glyphs it covers; strokes elsewhere stay ink. Can be toggled per tool. | M | M2 |

### 1.5 Pen & ink (INK), Tier 1
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-INK-001 | Freehand pen that creates Ink annotations with smooth, curve-fitted strokes. | M | M2 |
| FR-INK-002 | Pressure sensitivity (stylus pressure → width), with a toggle and a sensitivity curve setting. | M | M2 |
| FR-INK-003 | Low latency: render the live stroke on an overlay layer and commit it to the PDF afterwards (see [NFR-PERF-004](#21-performance-perf)). | M | M2 |
| FR-INK-004 | Highlighter pen: semi-transparent, flat-tipped, multiply blend, optional straight-line snap. | M | M2 |
| FR-INK-005 | Eraser: stroke eraser (deletes whole strokes) and partial/pixel eraser (splits strokes). | M | M2 |
| FR-INK-006 | Stylus-only mode: the pen draws, fingers scroll and zoom (palm rejection). Auto-enabled when a stylus is detected. | M | M2 |
| FR-INK-007 | Stylus button/eraser end mapping (side button → eraser or lasso; eraser tip → eraser). | M | M2 |
| FR-INK-008 | Lasso selection of strokes and annotations: move, resize, recolor, delete, copy/paste. | M | M2 |
| FR-INK-009 | Pen presets: at least 3 favorite pen configurations (color, width, type) one tap away. | M | M2 |
| FR-INK-010 | Shape recognition: hold at the end of a stroke to snap it to a line, rectangle, ellipse or arrow. | M | M3 |
| FR-INK-011 | Group strokes drawn within a short window into one Ink annotation to keep files lean. | M | M2 |
| FR-INK-012 | A stroke belongs to the page it starts on and is clipped to it; the view never scrolls or zooms while a stroke is in progress. | M | M2 |
| FR-INK-013 | Zoomed-in writing area ("magnifier box" that auto-advances) for neat handwriting. | C | post-1.0 |
| FR-INK-014 | Convert handwriting to typed text (offline, with a free recognition model; needs an ADR). | C | post-1.0 |

### 1.6 Notes & shapes (NOTE), Tier 2
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-NOTE-001 | Sticky notes (Text annotations) with an icon on the page and an editor popup. | M | M3 |
| FR-NOTE-002 | Notes attached to markups (Popup/`/Contents`), shown in the review panel. | M | M2 |
| FR-NOTE-003 | Free text boxes with font size, color and background options. | M | M3 |
| FR-NOTE-004 | Shapes: line, arrow, rectangle, ellipse, with stroke and fill options. | M | M3 |
| FR-NOTE-005 | Insert blank, ruled, grid or dotted **note pages** after the current page, sized like it. | M | M3 |
| FR-NOTE-006 | Stamps (✓, ✗, ?, !, "Important", "Review"), plus custom text stamps. | M | M3 |
| FR-NOTE-007 | Font choice for text boxes (bundled free fonts plus system fonts), with a fallback when a font is missing. | M | M3 |
| FR-NOTE-008 | Image annotations: insert a picture or camera photo on a page. | C | post-1.0 |
| FR-NOTE-009 | Sound annotations (record and play audio) and file attachment annotations. | C | post-1.0 |
| FR-NOTE-010 | Create and edit links (to a page or a URL). | C | post-1.0 |
| FR-NOTE-011 | Measurement tools: ruler, distance, perimeter and area with a calibrated scale. | C | post-1.0 |

### 1.7 Annotation management (ANNO)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-ANNO-001 | Undo/redo for all annotation operations, per document, at least 100 steps. | M | M2 |
| FR-ANNO-002 | Read, render and edit annotations created by other apps (no data loss for unknown keys). | M | M2 |
| FR-ANNO-003 | Review panel listing all annotations with type, color, page, text excerpt and note; filter and sort. | M | M3 |
| FR-ANNO-004 | Show/hide all annotations (view toggle, file unchanged). | M | M3 |
| FR-ANNO-005 | Export highlights and notes to Markdown (grouped by page/outline section, with page links) and plain text. | M | M3 |
| FR-ANNO-006 | Author name setting stored in `/T` (default empty or the OS user name, user confirms). | M | M2 |
| FR-ANNO-007 | Flatten annotations into page content when exporting a copy. | C | post-1.0 |
| FR-ANNO-008 | Lock an annotation against accidental edits. | M | M3 |
| FR-ANNO-009 | Style presets for every annotation tool (not only pens) and a free colour picker with favourite colours, in addition to the study palette. | M | M2 |
| FR-ANNO-010 | Delete or flatten all (or the filtered) annotations at once, and export the annotation summary as a PDF. | C | post-1.0 |

### 1.8 Saving & data safety (SAVE)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-SAVE-001 | Autosave annotations to the original file (configurable: autosave, or ask on close). | M | M2 |
| FR-SAVE-002 | Save atomically: write a temp file and replace the original only after a successful write, on every platform. | M | M2 |
| FR-SAVE-003 | Journal of unsaved operations, used for crash recovery on next launch. | M | M2 |
| FR-SAVE-004 | Use incremental save when possible (fast, keeps existing signatures valid). Needs Doxa's own incremental writer, because PDFium's incremental save is unusable ([ADR-0008](../adr/0008-annotation-save-strategy.md)). | S | post-1.0 |
| FR-SAVE-005 | "Save a copy as…" and share/export. | M | M2 |
| FR-SAVE-006 | Optional backup of the original before the first modification. | M | M3 |
| FR-SAVE-007 | Print through the OS print service (Android print framework), with annotations, page range and copies. | M | M3 |

### 1.9 Bookmarks & progress (BOOK)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-BOOK-001 | User bookmarks on pages, with a name, listed in a panel. Stored in the app database and optionally written as outline entries. | M | M3 |
| FR-BOOK-002 | Reading progress per document (percentage, last read date), shown in recents. | M | M1 |
| FR-BOOK-003 | Edit the document outline: add, rename, move and delete entries (written to the PDF). PDFium has no outline write API, so this needs an ADR (R19). | M | M3 |

### 1.10 Settings & personalization (SET)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-SET-001 | Theme: system/light/dark; accent color (Material You dynamic color on Android 12+). | M | M1 |
| FR-SET-002 | Language selection, defaulting to the system language. | M | M1 |
| FR-SET-003 | Default tool behaviors (sticky tool, autosave, stylus-only auto-detect, pressure curve). | M | M2 |
| FR-SET-004 | Customizable keyboard shortcuts (desktop). | C | M7 |
| FR-SET-005 | Reset settings, plus import/export of settings and pen presets. | C | M7 |
| FR-SET-006 | Customizable annotation toolbar: choose and order favourite tools, one or two rows. | C | post-1.0 |

### 1.11 Tier 3, post-1.0 document utilities (UTIL)
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-UTIL-001 | OCR scanned pages to add an invisible text layer (Tesseract), enabling search and markup. | M | M4 |
| FR-UTIL-002 | Page organization: rotate, delete, reorder, duplicate, insert (blank page, image or pages of another PDF), extract, merge, split, crop, and edit page labels. Annotations move with their pages. Page-label writing has no PDFium API (R19). | M | M4 |
| FR-UTIL-003 | Fill AcroForm fields; save filled values. | C | post-1.0 |
| FR-UTIL-004 | Handwritten signature saved for reuse and placed as a stamp. | C | post-1.0 |
| FR-UTIL-005 | Images → PDF; camera document scan with edge detection (A). | C | post-1.0 |
| FR-UTIL-006 | Sync annotations through a user-chosen folder/WebDAV, with conflict handling. | C | post-1.0 |
| FR-UTIL-007 | Read-aloud (OS TTS) following the text, with language and speech-rate settings. | C | post-1.0 |
| FR-UTIL-008 | Create fillable form fields. | C | post-1.0 |
| FR-UTIL-009 | New PDF: blank, from a web page, or combined from several documents and images. | C | post-1.0 |
| FR-UTIL-010 | Redaction: permanently remove selected text, images and areas (not just cover them). | C | post-1.0 |
| FR-UTIL-011 | Save a compressed copy or a password-protected copy. | C | post-1.0 |

### 1.12 E-books, catalogs & cloud (LIB), post-1.0
Planned after the Android, Linux and Windows apps are complete. Each area starts with an ADR; the order is decided then.
| ID | Requirement | Pri | MS |
|---|---|---|---|
| FR-LIB-001 | Open and read reflowable **EPUB** 2/3: pagination or scroll, font size and theme, table of contents, remembered position. Needs a GPL-compatible EPUB engine (ADR). | S | post-1.0 |
| FR-LIB-002 | EPUB **text highlights** (palette colours) and **comments** attached to them, shown in the review panel and exported to Markdown. EPUB has no standard annotation layer, so the storage format needs an ADR (the PDF rule "annotations live in the file" does not apply directly). | S | post-1.0 |
| FR-LIB-003 | **OPDS** catalogs (1.2 and 2.0): add catalogs by URL, browse and search, HTTP authentication, and download PDF/EPUB files into a library folder. | C | post-1.0 |
| FR-LIB-004 | **KoSync**: sync reading progress with a user-configured KOReader sync server (register, log in, push and pull progress per document, matched by the protocol's document hash). Implemented from the protocol, without copying AGPL code. | C | post-1.0 |
| FR-LIB-005 | **Cloud storage** accounts (Google Drive, OneDrive, Dropbox): browse, open and save annotations back, with conflict detection; through public REST APIs, never proprietary SDKs. | C | post-1.0 |

## 2. Non-functional requirements

### 2.1 Performance (PERF)
Reference devices are defined in [QA §4](06-quality-assurance.md#4-performance-budgets).
| ID | Requirement |
|---|---|
| NFR-PERF-001 | Cold start to the home screen in ≤ 1.5 s (A mid-range), ≤ 1 s (desktop). |
| NFR-PERF-002 | First page visible ≤ 500 ms after opening a typical 300-page textbook (a "fast first paint" placeholder within 100 ms). |
| NFR-PERF-003 | Scroll and zoom hold 60 fps (120 fps where supported) with no jank frames > 32 ms in standard scenarios. |
| NFR-PERF-004 | Ink: live stroke latency (input event → pixels) ≤ 25 ms on the reference tablet, using Android's low-latency/front-buffer path where available. |
| NFR-PERF-005 | Committing a stroke or highlight must not block input; the page re-render after commit has no visible flash. |
| NFR-PERF-006 | Memory: ≤ 400 MB for a 1000-page document on Android; tile cache bounded and trimmed on memory pressure. |
| NFR-PERF-007 | Search over a 1000-page text document streams first results within 1 s and stays cancellable. |
| NFR-PERF-008 | Saving annotations on a 100 MB file takes ≤ 2 s with incremental save. |
| NFR-PERF-009 | OCR runs in the background without affecting reading/ink performance, is cancellable, and processes a typical text page in ≤ 5 s on the reference tablet (to be validated in M0 Spike D). |

### 2.2 Reliability & data integrity (REL)
| ID | Requirement |
|---|---|
| NFR-REL-001 | No user-visible data loss: a crash or app kill loses at most the in-progress stroke. |
| NFR-REL-002 | Malformed or hostile PDFs are reported as "cannot open" instead of crashing. Engine errors are caught at the FFI boundary; native crashes are reduced through fuzzing and an up-to-date PDFium, and a crash never loses journaled annotations. Running the engine out of process is evaluated in M0 (see [risks](09-risks.md)). |
| NFR-REL-003 | Never write a partially saved file over the original (see FR-SAVE-002). |
| NFR-REL-004 | Output stays valid PDF that other readers open: validated in CI with qpdf `--check` and render comparisons. |

### 2.3 Compatibility (COMP)
| ID | Requirement |
|---|---|
| NFR-COMP-001 | Android 10 (API 29)+; arm64-v8a, armeabi-v7a, x86_64. |
| NFR-COMP-002 | Windows 10 1809+ x64 (arm64 is a stretch goal). |
| NFR-COMP-003 | Linux x86_64 (arm64 stretch) on X11 and Wayland; tested on Ubuntu LTS, Fedora and Arch. |
| NFR-COMP-004 | Stylus: Android MotionEvent stylus/pressure/tilt/buttons; Windows Ink (pointer events with pressure); Linux libinput tablets through GTK. |
| NFR-COMP-005 | PDF 1.0–2.0 reading; annotations written per ISO 32000 with appearance streams. |

### 2.4 Usability & accessibility (UX)
| ID | Requirement |
|---|---|
| NFR-UX-001 | Adaptive layouts for phone, tablet and desktop (compact/medium/expanded size classes). |
| NFR-UX-002 | All features reachable by keyboard on desktop; documented shortcuts. |
| NFR-UX-003 | Screen reader labels for all controls (TalkBack, Narrator, Orca); page text exposed for reading where feasible. |
| NFR-UX-004 | Minimum touch target 48 dp; contrast meets WCAG 2.1 AA; respects OS text scale. |
| NFR-UX-005 | Localization through ARB files; English and pt-BR complete at v1.0; RTL-ready layouts. |

### 2.5 Security & privacy (SEC)
| ID | Requirement |
|---|---|
| NFR-SEC-001 | No telemetry, analytics or network access by default. The only network use is user-initiated: opening links, plus future sync, catalogs (OPDS) and cloud accounts. |
| NFR-SEC-002 | JavaScript in PDFs is disabled. Launch actions and embedded files never execute automatically. |
| NFR-SEC-003 | Keep PDFium current (tracked by Dependabot or a custom workflow); security patches released within 14 days of an upstream fix. |
| NFR-SEC-004 | Request only the minimum permissions: Android uses SAF with no broad storage permission (except an optional "All files" flavor outside Play). |
| NFR-SEC-005 | Opt-in, user-reviewed crash reports only (for example, a local crash log the user can attach to an issue). |

### 2.6 Maintainability (MAINT)
| ID | Requirement |
|---|---|
| NFR-MAINT-001 | `flutter analyze` clean with the project lint set; formatted by `dart format`. |
| NFR-MAINT-002 | Test coverage ≥ 80% for `doxa_core` and the engine's Dart layer; every bug fix gets a regression test. |
| NFR-MAINT-003 | Reproducible builds: pinned Flutter version (FVM), pinned PDFium build, lockfiles committed. |
| NFR-MAINT-004 | The engine boundary is an interface, so PDFium can be swapped or extended without touching the UI. |
