# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state
Doxa PDF is a FOSS PDF reader **for studying** (Android, Windows, Linux). It is in the planning stage: no application code exists yet.
The plan lives in `docs/plan/` and decisions in `docs/adr/`. Read the relevant plan document before proposing features or architecture.

## Product focus
- Core = text markup (highlight/underline/strikeout/squiggly) and pen/ink annotation (pressure, palm rejection, low latency). Prioritize work by the tiers in `docs/plan/01-vision-and-scope.md` §5.
- Acrobat-style editing is "not planned for now", not forbidden. New feature areas need an ADR first.
- Inspired by Xodo's *capabilities* only: never copy names, icons, UI or text from other apps.

## Decided stack (see ADRs)
Flutter + Dart FFI to PDFium (no V8/XFA), monorepo with pub workspaces (`app/`, `packages/doxa_core|doxa_ink|doxa_engine|pdfium_ffi|doxa_platform`), Riverpod, drift. License GPL-3.0-or-later; dependencies must be GPL-3-compatible (no MuPDF/AGPL).

## Conventions
- All docs, code, comments and commits in **English** (the maintainer may chat in Portuguese).
- Requirement IDs (`FR-INK-002`, `NFR-PERF-004`) are stable: reference them in commits/PRs/tests, and never renumber them. Add new IDs at the end of a section.
- Conventional Commits, signed off (`git commit -s`). Branches `feat|fix|docs|chore|spike/<topic>`.
- New source files get `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Annotations are stored in the PDF itself (no sidecar format), with our own appearance streams. Unknown keys of foreign annotations must be preserved.
- All PDFium calls run in the single engine isolate. PDFium is not thread-safe.
- Current target: the Android-only MVP (betas v0.1–v0.4) in `docs/plan/11-mvp.md`. Reference device: Samsung Galaxy Tab + S Pen, minSdk 29. Desktop comes after (Linux first).
