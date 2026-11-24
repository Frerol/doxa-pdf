// SPDX-License-Identifier: GPL-3.0-or-later

/// The `PdfEngine` interface and its PDFium implementation, which runs in a
/// dedicated worker isolate because PDFium is not thread-safe.
/// See docs/plan/04-pdf-engine.md.
library;

/// Name of this package, used by smoke tests until real APIs land.
const String packageName = 'doxa_engine';
