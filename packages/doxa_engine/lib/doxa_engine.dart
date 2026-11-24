// SPDX-License-Identifier: GPL-3.0-or-later

/// The `PdfEngine` interface and its PDFium implementation, which runs in a
/// dedicated worker isolate because PDFium is not thread-safe.
/// See docs/plan/04-pdf-engine.md.
library;

export 'src/engine_check.dart';
