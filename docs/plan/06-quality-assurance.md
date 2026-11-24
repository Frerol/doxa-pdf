# 06 — Quality Assurance

## 1. Test pyramid

| Level | Scope | Tooling | Runs |
|---|---|---|---|
| Unit | `doxa_core`, `doxa_ink` (geometry, smoothing, commands, undo, serialization) | `dart test` | Every push |
| Engine integration | `doxa_engine` against real PDFium: open, render, text, write annotations, save, reopen | `dart test` with native lib, Linux CI | Every push |
| Widget | Toolbars, panels, reader gestures with `FakePdfEngine` | `flutter test` | Every push |
| Golden | Reader rendering, annotation layer, themes | `flutter test` goldens (Linux reference) | Every push |
| Integration / E2E | Open → highlight → ink → save → reopen on device | `integration_test` (Android emulator, Linux, Windows) | PRs to `main`, nightly |
| Interop | Saved files rendered by pdf.js, MuPDF, Poppler; validated with `qpdf --check` | Scripted in CI (Linux) | Every PR touching the engine |
| Fuzzing | Hostile PDFs against our FFI layer | libFuzzer/AFL corpus harness for PDFium calls | Nightly |
| Manual | Stylus feel, latency, palm rejection on real hardware | Release checklist | Each release candidate |

## 2. Definition of Done

A change is done when:
- It meets its requirement IDs, and tests reference those IDs.
- `dart format`, `flutter analyze` and all tests pass in CI.
- New UI strings are in ARB files (en + pt-BR).
- Docs and ADRs are updated if behaviour or architecture changed.
- A bug fix includes a regression test.

## 3. PDF test corpus & interoperability

- MVP interop targets: **Acrobat Reader, Xodo, Firefox (pdf.js), Chrome, Okular**. pdf.js, Poppler and MuPDF are automated. Acrobat and Xodo (Android) are checked manually before each beta.
- Large-document fixtures: openly licensed textbooks (500–1000+ pages, 100 MB+), two-column scientific articles, and scanned chapters (for OCR).
- `test_corpus/` (in repo): small, license-cleared PDFs covering rotated pages, odd CropBoxes, multi-column text, RTL/CJK text,
  scanned pages without text, encrypted files, large page counts, and annotations created by Acrobat, Okular, Xournal++ and pdf.js.
- A larger corpus is fetched on demand (`tools/fetch_corpus`) from openly licensed sources. A license manifest is required for every file.
- **Round-trip tests**: create every annotation type, save, reopen in Doxa and in pdf.js/MuPDF/Poppler, then compare renders to goldens within a tolerance.
- **Foreign-annotation preservation**: load a file with annotations from other tools, edit one, save, and diff the other annotations' dictionaries, which must be unchanged.

## 4. Performance budgets

Reference hardware:
- **Android tablet: the maintainer's Samsung Galaxy Tab with S Pen** (record the exact model and Android version here). This is the primary device for the MVP.
- **Android phone**, low-mid range (4 GB RAM).
- **Windows** laptop, 4-core, integrated GPU, 8 GB RAM, ideally a pen-capable 2-in-1.
- **Linux** laptop of the same class, tested on both Wayland and X11.

Budgets are defined in [requirements §2.1](02-requirements.md#21-performance-perf). They are checked by:
- Flutter `integration_test` performance timelines (frame build/raster times) on scripted scroll/zoom/draw scenarios, tracked over time.
- An **ink latency harness**: a debug overlay plotting the time between input event and frame presentation. Plus a manual high-speed-camera test before each release.
- A regression of more than 10% against `main` on a budgeted metric fails the nightly perf job.

## 5. Bug triage

| Severity | Definition | Target |
|---|---|---|
| S1 | Data loss, file corruption, crash on open of common files, security issue | Fix before any release; hotfix release |
| S2 | Core study flow broken (markup/ink/save) on one platform | Fix in next release |
| S3 | Degraded but workable | Planned |
| S4 | Cosmetic | Opportunistic |
