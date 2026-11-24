# 08 — Roadmap

> **Draft.** Milestone boundaries and the **MVP definition are still to be agreed** in a dedicated planning session.
> Until then, the milestones below are a proposal derived from the requirement priorities.

Milestones are defined by **scope and exit criteria**, not dates. Each milestone ends with a tagged release that users can install.

## M0 — Foundations & technical spikes
Goal: prove the risky parts before building features.
- Repository, CI skeleton, lints, FVM pin, pub workspace, ADRs 0001–0004.
- `pdfium_ffi` bindings and binary fetching on Android, Windows and Linux.
- **Spike A (rendering):** engine isolate + tiles + annotations-off rendering. Decide the foreign-annotation layer (→ ADR-0005).
- **Spike B (ink):** pressure, tilt, buttons and stylus detection on all three platforms in Flutter, plus a latency measurement. Decide whether the Android native front-buffer path is needed (→ ADR-0006).
- **Spike C (write):** create a highlight and an ink annotation with our own appearance streams, save incrementally, verify in pdf.js/Acrobat/Okular.
- **Spike D (F-Droid):** build PDFium from source reproducibly.

Exit: a spike report for each with go/no-go; ADRs recorded; [risks](09-risks.md) updated.

## M1 — Reader (v0.1)
FILE-001..004, 009 · VIEW-001..002, 004..012 · TEXT-001..002, 004 · BOOK-002 · SET-001.
Exit: open and read real textbooks on all three platforms within the performance budgets.

## M2 — Study core: markup + pen (v0.2) ★
MARK-001..005, 008, 010 · INK-001..007, 009, 011, 012 · TEXT-005..007 · NOTE-002 · ANNO-001, 002, 006 · SAVE-001..005 · FILE-010 · SET-003.
Exit: a student can highlight and handwrite through a whole chapter on a tablet with a stylus, without data loss.
Annotations interoperate with Acrobat, pdf.js and Okular.

## M3 — Study support (v0.3)
FILE-005..008 · VIEW-003, 013, 014 · TEXT-003 · MARK-006, 007, 009 · INK-008, 010 · NOTE-001, 003..006 · ANNO-003..005, 008 · BOOK-001 · SAVE-006.
Exit: review panel + Markdown export, note pages and tabs complete the study workflow.

## M4 — Hardening & 1.0
SET-002, 004, 005 · i18n completion (en, pt-BR) · accessibility audit · performance tuning · store listings (Play, F-Droid, Flathub, winget) · code signing.
Exit: [success criteria](01-vision-and-scope.md#7-success-criteria) met → **v1.0.0**.

## Post-1.0 candidates (order to be decided with the community)
1. OCR for scanned material (FR-UTIL-001), the highest study value.
2. Annotation sync via user-owned storage (FR-UTIL-006).
3. Page organization (FR-UTIL-002).
4. Forms & signatures, images → PDF, camera scanning (FR-UTIL-003..005).
5. Study extras: read-aloud, reading ruler, flashcards from highlights.
6. Broader editing (content editing, encryption/compression via qpdf), each starting with an ADR.
7. iOS/macOS builds.
