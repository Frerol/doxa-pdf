<img src="../assets/brand/doxa-glyph.svg" alt="" width="72" align="right">

# Doxa PDF — Engineering Plan

This folder holds the software engineering plan for Doxa PDF. Treat it as a living document:
change it through pull requests like code, and record decisions that are significant or hard to
reverse as [ADRs](adr/).

| # | Document | Answers |
|---|---|---|
| 01 | [Vision & Scope](plan/01-vision-and-scope.md) | Why the project exists, who it serves, and what is in or out |
| 02 | [Requirements](plan/02-requirements.md) | What the app must do (functional) and how well (non-functional) |
| 03 | [Architecture](plan/03-architecture.md) | How the system is structured: layers, modules, data flow |
| 04 | [PDF Engine](plan/04-pdf-engine.md) | How PDFium is integrated, and how its gaps are covered |
| 05 | [UX Design](plan/05-ux-design.md) | Screens, interaction model, adaptive layouts, accessibility |
| 06 | [Quality Assurance](plan/06-quality-assurance.md) | Testing strategy, test corpus, performance budgets |
| 07 | [Build, Release & Distribution](plan/07-build-release.md) | CI/CD, packaging, stores, versioning |
| 08 | [Roadmap](plan/08-roadmap.md) | Milestones, their scope and exit criteria |
| 09 | [Risks](plan/09-risks.md) | Known risks and how to mitigate them |
| 10 | [Governance](plan/10-governance.md) | Workflow, conventions, licensing hygiene, community |
| 11 | [MVP Definition](plan/11-mvp.md) | What the Android MVP betas (v0.1–v0.4) contain, and when the MVP is done |

## Architecture Decision Records

| ADR | Title | Status |
|---|---|---|
| [0001](adr/0001-flutter-as-ui-framework.md) | Flutter as the cross-platform UI framework | Accepted |
| [0002](adr/0002-pdfium-as-pdf-engine.md) | PDFium as the PDF engine | Accepted |
| [0003](adr/0003-gpl-3-license.md) | GPL-3.0-or-later as the project license | Accepted |
| [0004](adr/0004-monorepo-with-pub-workspaces.md) | Monorepo with Dart pub workspaces | Accepted |
| [0005](adr/0005-rendering-pipeline-and-foreign-annotations.md) | Rendering pipeline and the foreign-annotation layer | Accepted |
| [0006](adr/0006-ink-rendering-in-flutter.md) | Ink rendering in pure Flutter (no native front-buffer path) | Accepted |
| [0007](adr/0007-ocr-integration.md) | On-device OCR with Tesseract4Android | Proposed |
| [0008](adr/0008-annotation-save-strategy.md) | Annotation save strategy (full save, AP-less markup, object-based ink AP) | Accepted |
| [0009](adr/0009-offline-dictionary.md) | Built-in offline dictionary (StarDict, user-imported) | Accepted |

New ADRs start from [the template](adr/0000-template.md).

## Spike reports (M0)

| Spike | Report | Result |
|---|---|---|
| A: Tiled rendering & foreign annotations | [A-rendering.md](spikes/A-rendering.md) | GO, two instances (render / edit) |
| B: S Pen ink latency | [B-ink.md](spikes/B-ink.md) | GO, pure Flutter |
| C: Writing annotations & interop | [C-annotation-write.md](spikes/C-annotation-write.md) | GO, full save instead of incremental |
| D: On-device OCR | [D-ocr.md](spikes/D-ocr.md) | GO, Tesseract4Android, ≤ 2.6 s per page |
