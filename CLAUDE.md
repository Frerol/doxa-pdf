# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state
Doxa PDF is a FOSS PDF reader **for studying** (Android, Windows, Linux), currently in milestone M0 (scaffold + spikes).
The plan lives in `docs/plan/` and decisions in `docs/adr/`. Read the relevant plan document before proposing features or architecture.

## Commands
- Toolchain is user-local: Flutter via FVM (pinned in `.fvmrc`; use `fvm flutter`/`fvm dart` or `.fvm/flutter_sdk/bin`), `JAVA_HOME=~/.local/share/jdk/17`, `ANDROID_HOME=~/Android/Sdk`.
- `tools/fetch_pdfium.sh [linux|android]`: fetch pinned PDFium into `third_party/pdfium/` (needed before Android builds and native tests). Bindings: `cd packages/pdfium_ffi && dart run tool/ffigen.dart` (ffigen 23 Dart config; never edit `pdfium_bindings.g.dart`).
- `tools/check.sh`: format + analyze + all tests with coverage. Pure Dart packages use `dart test`, Flutter ones `flutter test`, run from the package dir.
  CI (`.github/workflows/ci.yml`) also runs Markdown link checks, the pub license check (`python3 tools/check_dependency_licenses.py pub`), the Android debug APK build with a Gradle license check, and a bindings-up-to-date check.
- Test PDFs: `test_corpus/` (provenance and licenses in `test_corpus/MANIFEST`); `tools/fetch_corpus.sh` downloads the large ones into git-ignored `test_corpus/external/`.
- `cd app && fvm flutter build apk --debug`: Android build.

## Product focus
- Core = text markup (highlight/underline/strikeout/squiggly) and pen/ink annotation (pressure, palm rejection, low latency). Prioritize work by the tiers in `docs/plan/01-vision-and-scope.md` §5.
- Acrobat-style editing is "not planned for now", not forbidden. New feature areas need an ADR first.
- Never name the commercial reader that inspired Doxa anywhere in the repo (docs, code, commits, issues); say "a commercial PDF reader". Never copy names, icons, colours or texts from other apps.

## Decided stack (see ADRs)
Flutter + Dart FFI to PDFium (no V8/XFA), monorepo with pub workspaces (`app/`, `packages/doxa_core|doxa_dict|doxa_ink|doxa_engine|pdfium_ffi|doxa_platform`), Riverpod, drift. License GPL-3.0-or-later; dependencies must be GPL-3-compatible (no MuPDF/AGPL).

## Conventions
- All docs, code, comments and commits in **English** (the maintainer may chat in Portuguese).
- Requirement IDs (`FR-INK-002`, `NFR-PERF-004`) are stable: reference them in commits/PRs/tests, and never renumber them. Add new IDs at the end of a section.
- Conventional Commits, signed off (`git commit -s`). Branches `feat|fix|docs|chore|spike/<topic>`.
- New source files get `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Flutter 3.50: import `package:material_ui/material_ui.dart`, not the deprecated `package:flutter/material.dart`. Use `GlobalMaterialLocalizations.delegates` from material_ui (the gen-l10n delegate list is incompatible).
- `doxa_core` and `doxa_dict` must stay pure Dart (enforced by their `dependency_rule_test.dart`).
- Annotations are stored in the PDF itself (no sidecar format), with our own appearance streams. Unknown keys of foreign annotations must be preserved.
- All PDFium calls run in the single engine isolate. PDFium is not thread-safe.
- Rendering (ADR-0005): one engine isolate with priority + generation cancellation; 360 px previews + 512 px tiles at power-of-two zoom buckets; two PDFium instances per file (read-only render instance with Doxa annots hidden in memory and `FPDF_ANNOT` on; editing instance never rendered with annots).
- Saving (ADR-0008): PDFium full save → temp → verify → atomic replace; never `FPDF_INCREMENTAL`; markup without `/AP`; ink AP via `FPDFAnnot_AppendObject` called after all setters (`SetBorder` deletes the AP); never render the editing doc with `FPDF_ANNOT`.
- UI should strongly resemble the leading commercial mobile PDF readers in layout/flows, with an original identity (`docs/plan/05-ux-design.md` §8).
- Ink (ADR-0006): pure Flutter, raw `Listener`, live stroke as vectors, committed ink in tiles (never replay all vectors per frame), no smoothing by default (never One-Euro), pan/zoom via repaint not rebuild. S Pen side button = `kPrimaryStylusButton`.
- Current target: the Android-only MVP (betas v0.1–v0.4) in `docs/plan/11-mvp.md`. Reference device: Samsung Galaxy Tab S10 FE + S Pen (Android 16), minSdk 29. Desktop comes after (Linux first).

## Agents
`AGENTS.md` holds the same rules for other coding agents and a **task queue (T-xx)** the maintainer delegates to them. Don't pick up those tasks unless asked. When a change affects the rules, update both files.
