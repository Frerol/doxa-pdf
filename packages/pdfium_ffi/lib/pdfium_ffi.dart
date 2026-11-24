// SPDX-License-Identifier: GPL-3.0-or-later

/// Low-level Dart FFI bindings to PDFium, generated with ffigen from the
/// headers pinned in `tools/pdfium.lock`, plus native library loading.
///
/// Only `doxa_engine` may use this package (docs/plan/03-architecture.md §2).
/// PDFium is not thread-safe: all calls must come from a single isolate.
library;

export 'src/pdfium_bindings.g.dart';
export 'src/pdfium_library.dart';
