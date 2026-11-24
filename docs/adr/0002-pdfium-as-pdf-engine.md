# ADR-0002 — PDFium as the PDF engine

- **Status:** Accepted
- **Date:** 2026-11-24

## Context
We need accurate rendering, text extraction, annotation read/write and incremental saving on all targets, under a license compatible with our own.

## Decision
Use **PDFium** (BSD-3-Clause/Apache-2.0), built **without V8 and XFA**, accessed through our own Dart FFI bindings behind the `PdfEngine` interface.
Prebuilt binaries from bblanchon/pdfium-binaries are used for most channels; PDFium is built from source for F-Droid.

## Consequences
- High-fidelity rendering (Chrome's engine), active upstream, permissive license.
- PDFium writes annotations but does not generate rich appearance streams for every type, so Doxa writes its own (see docs/plan/04).
- No write support for encryption, compression or linearization. qpdf may be added later behind the same interface.
- No digital signing; a later feature will need its own implementation.

## Alternatives considered
- **MuPDF**: excellent engine, but AGPL-3.0 would force the whole app to AGPL. A commercial license is not an option for a FOSS project.
- **Poppler**: GPL, strong on Linux, weaker on Android/Windows and in annotation writing.
- **pdf.js in a WebView**: weak for low-latency ink and native integration.
