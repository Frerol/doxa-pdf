# 09 — Risks

Likelihood (L) and impact (I) use the scale Low/Med/High. Review this register at the end of every milestone.

| ID | Risk | L | I | Mitigation | Owner/When |
|---|---|---|---|---|---|
| R1 | **Ink latency** in Flutter misses the budget on Android (no front-buffer rendering in Flutter) | Med | High | Spike B measures early. Fallback: native overlay with `androidx.graphics` front-buffered renderer + motion prediction | M0 |
| R2 | **Stylus support gaps on desktop**: Flutter Windows/Linux embedders may not expose pen pressure/tilt/eraser reliably | High | High | Spike B on real hardware. Fallbacks: contribute upstream fixes, or a small platform plugin that reads Windows Pointer/WM_POINTER and GTK tablet events | M0 |
| R3 | **PDFium crashes** on hostile files take down the whole app (in-process native code) | Med | Med | Fuzzing, timely PDFium updates, journaling so no annotations are lost. Evaluate out-of-process engine (Android service / desktop subprocess) | M0 → M4 |
| R4 | **Annotation interop bugs** (rotation, CropBox, appearance streams) make notes look wrong in other readers | Med | High | Own appearance writer, corpus covering edge cases, automated cross-renderer tests | M0, ongoing |
| R5 | **F-Droid** requires building PDFium from source; the build is heavy and fragile | High | Med | Spike D; reproducible build script; ask F-Droid maintainers early; ship other channels in parallel | M0 |
| R6 | **Android storage (SAF)** makes atomic in-place saves hard (content URIs, cloud providers) | Med | High | Write temp → verify → copy with `"wt"` mode; detect providers without write support → "Save a copy"; journal guarantees recovery | M2 |
| R7 | **Foreign annotation layer** approach (draw own types in Flutter, others in PDFium) proves complex | Med | Med | Spike A; fallback: bake all annotations into tiles and accept a re-render after edits for foreign types only | M0 |
| R8 | **Scope creep** toward a general PDF editor before the study core is excellent | Med | Med | Tier model in Vision §5; every new area needs an ADR; milestone exit criteria | Ongoing |
| R9 | **Bus factor of one** (single maintainer) | High | High | Excellent docs, good-first-issues, CI that enforces quality, clear governance | Ongoing |
| R10 | **Trademark / look-alike concerns** with commercial apps that inspired the feature set | Low | Med | Original name, icon and UI. No copied assets or text. "Inspired by" only in docs, never in store listings | Ongoing |
| R11 | **Code signing costs** (Windows SmartScreen, Play account fee) | Med | Low | SignPath OSS program; budget for the Play developer fee; MSIX via winget | M4 |
| R12 | Flutter platform breaking changes / pinned version drift | Low | Med | FVM pin, upgrade once per milestone in a dedicated PR | Ongoing |
