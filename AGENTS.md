# AGENTS.md

Instructions for coding agents (e.g. OpenAI Codex) working in this repository. Claude Code reads `CLAUDE.md`; the rules below are the same.

## Project
Doxa PDF is a free (GPL-3.0-or-later) PDF reader **for studying** on Android, Windows and Linux. Its core features are text markup and pen annotation.
Stack: Flutter (pinned in `.fvmrc`) + Dart FFI to PDFium, in a pub-workspace monorepo:

| Path | What | Tests |
|---|---|---|
| `app/` | Flutter app (Android first) | `flutter test` |
| `packages/doxa_core` | Pure Dart domain: models, geometry, commands. **No Flutter imports** (enforced by a test) | `dart test` |
| `packages/doxa_ink` | Pure Dart ink: smoothing, outlines, hit testing | `dart test` |
| `packages/doxa_engine` | PDF engine on top of PDFium (single worker isolate) | `dart test` (needs PDFium) |
| `packages/pdfium_ffi` | Generated PDFium bindings + loader | `dart test` (needs PDFium) |
| `packages/doxa_platform` | Android plugin (pigeon) | `flutter test` |

Read `docs/README.md` for the plan and `docs/adr/` for decisions before changing behaviour or architecture.

## Setup and checks
```sh
fvm install                    # Flutter version from .fvmrc (or use .fvm/flutter_sdk/bin)
tools/fetch_pdfium.sh linux    # pinned PDFium for native tests (third_party/, git-ignored)
fvm flutter pub get            # whole workspace
tools/check.sh                 # format + analyze + every test; must pass before you finish
```
Run a single package's tests from its directory: `dart test` (pure Dart) or `flutter test` (Flutter packages).

## Rules
- **English** for code, comments, docs and commits.
- Every new source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.
- `dart format` and `flutter analyze` must be clean (strict lints in `analysis_options.yaml`).
- Every change ships with tests. Bug fixes get a regression test.
- Import Material from `package:material_ui/material_ui.dart`, **not** `package:flutter/material.dart` (deprecated in Flutter 3.47+).
- Requirement IDs (`FR-INK-002`, `NFR-PERF-004`, …) are stable. Reference them in commits and tests, and never renumber them.
- Dependencies must be GPL-3.0-compatible (MIT, BSD, Apache-2.0, LGPL, MPL-2.0, GPL). Ask before adding any dependency.
- **Never name the commercial PDF reader that inspired Doxa** anywhere (code, docs, commits, issues). Write "a commercial PDF reader" instead.
- Do **not** edit: `packages/pdfium_ffi/lib/src/pdfium_bindings.g.dart` (generated), `tools/pdfium.lock`, ADRs (`docs/adr/`), `LICENSE`, CI secrets or signing config.
- Do **not** merge PRs or push to `main`. Work on a branch `codex/<task-id>-<topic>`, use Conventional Commits signed off with `git commit -s`, and open a PR.
- PDFium rules (ADR-0008): full saves only (never `FPDF_INCREMENTAL`), call `FPDFAnnot_AppendObject` after all other annotation setters, and never render the editing document with `FPDF_ANNOT`.

## Task queue for agents
Low-complexity, well-specified tasks delegated to agents. Each one is pure Dart with unit tests, touches only the listed package, and needs no device.
Do one task per PR. Name it `<type>(<package>): … (T-xx)`. When it is merged, the maintainer ticks it here.

| ID | Status | Package | Task |
|---|---|---|---|
| T-01 | ☐ | doxa_core | PDF date strings |
| T-02 | ☐ | doxa_core | Annotation IDs (UUID v4) |
| T-03 | ☐ | doxa_core | Geometry value types |
| T-04 | ☐ | doxa_core | Page coordinate transforms |
| T-05 | ☐ | doxa_core | Study colour palette and labels |
| T-06 | ☐ | doxa_ink | Pressure curve and width mapping |
| T-07 | ☐ | doxa_ink | Arc-length smoothing |
| T-08 | ☐ | doxa_ink | Resampling and simplification |
| T-09 | ☐ | doxa_ink | Stroke hit testing and partial erase |
| T-10 | ☐ | repo/CI | Dependabot for pub and Gradle |

### T-01 · PDF date strings (doxa_core)
Implement `formatPdfDate(DateTime)` and `parsePdfDate(String) → DateTime?` for the PDF date format `D:YYYYMMDDHHmmSSOHH'mm'` (ISO 32000 §7.9.4),
in `lib/src/pdf_date.dart`, exported from `doxa_core.dart`.
- Formatting always writes UTC as `D:20261124120000Z`.
- Parsing accepts every truncated form the spec allows (`D:2026`, `D:202611`, …), the optional `D:` prefix, `Z`, `+HH'mm'`, `-HH'mm'` and `+HH'mm` (no trailing quote). It returns UTC, or `null` for invalid input; it never throws.
- Tests: round trip, each truncation, offsets, invalid strings (letters, month 13, empty).

### T-02 · Annotation IDs (doxa_core)
`AnnotationId.generate()` returns a random **UUID v4** string (lowercase, 36 chars), using `Random.secure()` and no packages.
`AnnotationId.isValid(String)` checks the format. Used for `/NM` (docs/plan/03-architecture.md §5).
Tests: format and version/variant bits, uniqueness over 10,000 ids, validator accepts and rejects.

### T-03 · Geometry value types (doxa_core)
Immutable `PdfPoint(x, y)`, `PdfRect(left, bottom, right, top)` and `PdfQuad(p1..p4)` in PDF user space (y grows **upwards**), with `==`/`hashCode`.
- `PdfRect`: `normalized()`, `width`, `height`, `union`, `intersect` (nullable), `inflate(d)`, `contains(point)`, `overlaps`.
- `PdfQuad.fromRect(rect)` uses Acrobat order **upper-left, upper-right, lower-left, lower-right**. Also `boundingRect` and `toList()` (8 doubles, `/QuadPoints` order).
- Tests for each method, including degenerate rects.

### T-04 · Page coordinate transforms (doxa_core) — depends on T-03
`PageTransform` maps between **PDF user space** and **view space** (origin top-left, y down, in view pixels) for a page with
`cropBox` (`PdfRect`, possibly with a non-zero origin), `rotation` (0/90/180/270, clockwise as `/Rotate`) and `scale` (pixels per point).
Methods: `toView(PdfPoint) → (double x, double y)`, `toUser(double x, double y) → PdfPoint`, `viewSize`.
- The displayed page is the crop box rotated clockwise by `rotation`. The crop box's top-left corner (after rotation) maps to view (0, 0).
- Tests: round trip for all rotations with a non-zero crop origin; known corner mappings for each rotation; `viewSize` swaps width/height at 90/270.
- Reason: Spike C follow-up, user-drawn ink on rotated/cropped pages (docs/spikes/C-annotation-write.md §2).

### T-05 · Study colour palette (doxa_core)
`StudyColor { int argb; String? label; }` and `StudyPalette` (ordered list, max 12) with `defaults()`. The defaults are 6 colours chosen to read well under
multiply blending: yellow `0xFFFFEB3B`, green `0xFFA5D6A7`, blue `0xFF90CAF9`, pink `0xFFF48FB1`, orange `0xFFFFCC80`, purple `0xFFCE93D8`.
Add `relabel(index, label)`, `move(from, to)`, `toJson()`/`fromJson()` (tolerant of unknown fields). Refs FR-MARK-002, FR-MARK-011.
Tests: defaults, JSON round trip, bounds errors, max size.

### T-06 · Pressure curve and width mapping (doxa_ink)
`PressureCurve` maps raw pressure 0..1 to 0..1 with a `gamma` (0.3–3.0, default 1.0). `PressureCurve.linear` ignores pressure and returns 0.5.
`strokeRadius(double baseWidth, double mappedPressure)` returns `baseWidth / 2 * (0.35 + 1.3 * p)` (the Spike B mapping).
Inputs are clamped, and NaN is treated as 0.5. Refs FR-INK-002.
Tests: endpoints, monotonicity, clamping, NaN, gamma bounds.

### T-07 · Arc-length smoothing (doxa_ink)
Port `_arcSmooth` from the Spike B prototype (`git show spike/ink:spikes/ink_lab/lib/main.dart`, around line 726) as a pure function
`List<InkSample> arcSmooth(List<InkSample> raw, double radius)`, with `InkSample(x, y, pressure, timeUs)` defined in `lib/src/ink_sample.dart`.
Behaviour: resample every `radius / 4` along the polyline, then a triangular moving average over ±4 samples whose window shrinks at both ends,
so the **first and last points are unchanged**. `radius <= 0` or fewer than 3 points returns a copy. Pressure is interpolated and averaged the same way.
Tests: identity cases, endpoints preserved, a straight line stays straight, zig-zag noise amplitude is reduced, no NaN for duplicate points.
Context: smoothing is **off by default** and must never be a One-Euro filter (ADR-0006).

### T-08 · Resampling and simplification (doxa_ink) — depends on T-07's `InkSample`
`resampleByDistance(samples, minStep)` drops samples closer than `minStep` to the last kept one (always keeping the first and last).
`simplify(samples, tolerance)` uses Ramer–Douglas–Peucker on positions and keeps pressure/time of the kept points.
Tests: counts, endpoint preservation, collinear input collapses to 2 points, tolerance 0 keeps everything.

### T-09 · Stroke hit testing and partial erase (doxa_ink) — depends on T-07's `InkSample`
- `double distanceToPolyline(x, y, samples)`.
- `bool hitsStroke(samples, x, y, radius, {double strokeRadius = 0})` is the whole-stroke eraser test.
- `List<List<InkSample>> eraseSegment(samples, x, y, radius)` is the partial eraser. It removes the part within `radius` of the point and returns the remaining pieces in order, splitting segments exactly at the circle boundary and dropping pieces shorter than 2 samples. Refs FR-INK-005.
- Tests: hit/miss near endpoints and mid-segment, single-point strokes, erase in the middle (2 pieces), at an end (1 piece), everything (0 pieces).

### T-10 · Dependabot for pub and Gradle (repo)
Extend `.github/dependabot.yml` with weekly updates for `pub` (directory `/`, the workspace root) and `gradle` (`/app/android`). Group minor/patch updates per
ecosystem and keep GitHub Actions as is. Validate the YAML. No other CI changes; issue #3 covers the rest.

## Not for agents (ask the maintainer)
Architecture or ADR changes, PDFium/FFI changes, platform code (Kotlin, Gradle signing), UI/UX design, release and store work, licensing questions,
and anything that needs the physical tablet (S Pen, performance measurements).
