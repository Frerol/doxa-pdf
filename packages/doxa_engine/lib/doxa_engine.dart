// SPDX-License-Identifier: GPL-3.0-or-later

/// The `PdfEngine` interface and its PDFium implementation, which runs in a
/// dedicated worker isolate because PDFium is not thread-safe.
/// See docs/plan/04-pdf-engine.md and ADR-0005.
library;

export 'src/api/pdf_engine.dart';
export 'src/api/types.dart';
export 'src/engine/pdfium_engine.dart' show PdfiumEngine;
export 'src/text/text_search.dart' show lineRects;
