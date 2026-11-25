# ADR-0009 — Built-in offline dictionary

- **Status:** Proposed
- **Date:** 2026-11-24

## Context
Students reading textbooks and articles, often in a second language, need to check the meaning of a word without leaving the page.
The maintainer added dictionary lookup to the MVP, in **v0.1 Reader** ([11 — MVP](../plan/11-mvp.md)), as a **built-in, offline** feature
(FR-TEXT-008..010), not only a hand-off to another app.

Forces:
- Offline by default and no network access ([NFR-SEC-001](../plan/02-requirements.md#25-security--privacy-sec)). No accounts, no online APIs.
- Dictionary data has its own licenses and sizes (tens to hundreds of MB), so it should not be bundled with the APK.
- Lookups must not block the UI or the PDFium engine isolate (ADR-0005).
- Dependencies must be GPL-3.0-compatible, and new dependencies need the maintainer's approval.

## Decision
1. **Format: StarDict.** Doxa reads StarDict dictionaries (`.ifo` + `.idx` + `.dict` or dictzip `.dict.dz`, optional `.syn`).
   It is the de-facto open format of offline readers and dictionary apps, and free dictionaries (Wiktionary-derived, FreeDict and others) are
   widely available in it. Other formats can be added later behind the same interface.
2. **User-imported, never bundled.** The user imports a dictionary (file, folder or `.zip`) through the system picker. Doxa copies it into app
   storage, validates it, and lists it in settings, where it can be enabled, disabled, reordered and removed. Docs point to free sources.
3. **A new pure Dart package, `packages/doxa_dict`**: parsing, index, lookup and normalization, with no Flutter imports and no new dependencies
   (dictzip chunks are inflated with `dart:io`'s zlib). It is tested with small generated fixtures.
4. **Lookup** runs off the UI isolate and never on the engine isolate. It binary-searches the `.idx` headwords (StarDict ordering) and
   reads definitions on demand. Normalization: trim surrounding punctuation, try the exact form, then case-folded and diacritic-folded
   forms, then `.syn` synonyms, then close headwords as suggestions.
5. **UI:** "Dictionary" in the text-selection actions (a single word or a short phrase). A popup on tablets (a bottom sheet on phones)
   shows the results grouped by dictionary in the user's order, with "Copy" and "Look up in another app" (FR-TEXT-006).
6. **Definitions are displayed, never executed.** Plain-text types (`m`, `t`, `y`) are shown as text. HTML (`h`) and XDXF (`x`) are reduced to a
   safe subset (paragraphs, bold, italic, lists, line breaks). No scripts, no remote resources, no network.

## Consequences
- v0.1 grows by one feature slice (package + import + settings + popup). It builds on text selection (FR-TEXT-004), which v0.1 already has.
- A new package joins the workspace; `CLAUDE.md`/`AGENTS.md` list it once it exists.
- Users must find and import a dictionary before the first lookup. An empty state explains how.
- Embedded images, audio and resource folders (`res/`) are ignored in the MVP.
- New risk: StarDict files in the wild vary (encodings, broken indexes, huge files). Mitigated by validation on import and fuzz-style tests (R16).

## Alternatives considered
- **Hand off to an external dictionary app only** (Android `PROCESS_TEXT`/define action): cheapest, but leaves the page and depends on what is installed. Kept as a secondary action.
- **Online dictionary APIs:** violate offline-by-default and privacy goals.
- **Own SQLite format with a converter:** fast lookups, but users would have to convert every dictionary first.
- **MDict, DSL or vendor e-reader formats:** less open, some encrypted variants, fewer free dictionaries. Can be revisited later.
- **Bundling a default dictionary:** increases APK size and mixes data licenses into the app; can be offered later as an optional download.
