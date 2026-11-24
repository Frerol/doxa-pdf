# 01 — Vision & Scope

## 1. Vision

The best free place to **study a PDF**: read comfortably, mark up the important passages in seconds,
and write on the page with a pen that feels like paper. It should work the same on an Android tablet
with a stylus, a Windows 2-in-1 and a Linux desktop. Notes are always stored as standard PDF annotations
that the user owns.

Doxa PDF is **a study tool first**. When choosing what to build next, ask:
*"Does this help someone read, understand, mark up or review a document?"* Features that pass this test go first.
Broader PDF editing is not excluded. It simply waits until the study experience is excellent.

## 2. Problem statement

- The most capable free PDF apps for studying are proprietary. They are often ad-supported or freemium,
  they collect telemetry, and features can disappear or become paid at any time.
- Open-source readers focus on viewing. Where they do have pen input, it tends to lag, ignore
  pressure, or lack palm rejection, which makes them unusable for real handwriting.
- Students switch between devices (tablet in class, laptop at home). They need the same tool and an
  annotation format that survives the trip: plain PDF.

## 3. Product inspiration and originality

The feature set is inspired by popular all-in-one PDF readers, Xodo PDF Reader in particular.
Doxa PDF is an **original implementation**:

- No code, icons, artwork, names or trademarks of other products are used.
- The UI follows Material 3 and platform conventions, not a copy of another app's look.
- "Feature parity" refers to *capabilities* (for example, "highlight text"), never to visual or textual copies.

## 4. Target users & personas

| Persona | Context | Key needs |
|---|---|---|
| **University student** (primary) | Android tablet + stylus in class, laptop at home | Fast highlighting, handwriting on slides, color-coded markup, review before exams |
| **Exam candidate / self-learner** | Phone on the go, desktop for long sessions | Resume reading position, night mode, bookmarks, annotation summary |
| **Researcher** | Linux/Windows desktop, many papers open | Tabs, outline, search, highlights exported as Markdown notes |
| **Teacher** | Windows 2-in-1 or tablet | Ink on slides while presenting, blank pages for worked examples |
| **Privacy-conscious user** | Any platform | Offline, no tracking, auditable source, F-Droid/Flathub availability |

## 5. Feature priorities

**Tier 1, the core.** These define the product and get the most engineering and polish:
1. **Text markup**: highlight, underline, strikeout, squiggly. Precise text selection, a one-tap color palette, and a "sticky tool" mode for highlighting many passages in a row.
2. **Pen annotation**: pressure-sensitive ink, highlighter pen, eraser (whole stroke and partial), lasso select/move/recolor, stylus-only mode with palm rejection, very low latency.
3. **Comfortable reading**: smooth scroll and zoom, layouts, night/sepia modes, remembered position, outline, search.

**Tier 2, study support:**
- Sticky notes, notes attached to highlights, text boxes, simple shapes/arrows.
- Blank or ruled/grid **note pages** inserted into the document for handwritten work.
- Annotation review panel (filter by color/type/author/page), bookmarks, export of highlights and notes to Markdown.
- Tabs, recents, favorites, "Open with" integration.

**Promoted to the MVP:** OCR. Scanned study material is common, and OCR makes it searchable and highlightable.

**Tier 3, document utilities (after v1.0 unless cheap):**
- Page organization: rotate, delete, reorder, extract, merge, split.
- AcroForm filling, handwritten signatures.
- Images → PDF, camera scanning.

## 6. Scope

### In scope for v1.0
The MVP comes first: Android-only public betas v0.1–v0.4 ([11 — MVP](11-mvp.md)). It covers Tiers 1 and 2 plus **OCR**,
because scanned study material is common. v1.0 then brings the same feature set to Linux and Windows, plus localization (at least English and Brazilian
Portuguese), accessibility, and distribution through GitHub Releases, F-Droid, Google Play, Flathub and a
Windows installer/winget.

### Planned after v1.0 (see [roadmap](08-roadmap.md))
- Page organization, form filling, signatures, images → PDF, camera scanning.
- Sync of annotations between devices through user-owned storage (folder sync, WebDAV/Nextcloud).
- Study extras: read-aloud (TTS), focus/reading-ruler mode, flashcards generated from highlights.
- iOS and macOS builds (Flutter allows it; not a v1 commitment).

### Not planned for now (may enter scope later)
These are not part of the current plan, but nothing here is ruled out forever. Each can be revisited
through an ADR once the study core is solid. The architecture keeps the door open: the engine sits behind an interface,
and PDFium already exposes page-object editing APIs.
- Acrobat-style content editing (editing or reflowing existing text, moving images, editing page objects).
- Real-time multi-user collaboration.
- Conversion to and from Office formats.
- XFA dynamic forms.

### Permanent non-goals
- Telemetry, ads, in-app purchases, mandatory accounts.

## 7. Success criteria

- **Ink latency**: the stroke follows the stylus with no visible lag on a mid-range Android tablet (see [budgets](06-quality-assurance.md#4-performance-budgets)).
- **Markup speed**: highlighting a sentence takes one gesture plus at most one tap.
- **Interoperability**: highlights and ink made in Doxa PDF render correctly in Acrobat Reader, pdf.js, Okular and Chrome's viewer, and annotations made in those apps show up in Doxa PDF.
- **No data loss**: annotations survive crashes and app kills (autosave and journaling).
- v1.0 ships on all three platforms through at least one official channel each.
- A contributor can build every target from a clean checkout by following the docs.
