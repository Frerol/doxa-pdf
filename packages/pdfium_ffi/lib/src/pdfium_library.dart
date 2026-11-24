// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'pdfium_bindings.g.dart';

/// Environment variable that overrides the PDFium library path.
const pdfiumLibraryEnv = 'DOXA_PDFIUM_LIBRARY';

/// Thrown when the PDFium shared library cannot be found or loaded.
class PdfiumLibraryNotFound implements Exception {
  PdfiumLibraryNotFound(this.attempts, [this.cause]);

  /// Library names or paths that were tried, in order.
  final List<String> attempts;

  /// The last loading error, if any.
  final Object? cause;

  @override
  String toString() =>
      'PdfiumLibraryNotFound: could not load PDFium (tried: '
      '${attempts.join(', ')}). On a development machine, run '
      'tools/fetch_pdfium.sh first or set \$$pdfiumLibraryEnv.'
      '${cause == null ? '' : '\nLast error: $cause'}';
}

/// Opens the bundled PDFium library and returns its bindings.
///
/// Resolution order:
/// 1. [path], when given;
/// 2. the `DOXA_PDFIUM_LIBRARY` environment variable;
/// 3. on Linux, `third_party/pdfium/linux-x64/lib/libpdfium.so` found by
///    walking up from the current directory (development and tests);
/// 4. the platform's default name (`libpdfium.so` on Android, where the APK
///    bundles it, and on Linux; `pdfium.dll` on Windows).
///
/// Never uses a system-wide copy on purpose: the app ships its pinned build
/// (docs/plan/04-pdf-engine.md §2), but the default name may resolve to one if
/// nothing else matched.
PdfiumBindings openPdfium({String? path}) {
  final candidates = <String>[
    ?path,
    ?Platform.environment[pdfiumLibraryEnv],
    if (Platform.isLinux) ?_findInWorkspace(),
    _defaultLibraryName(),
  ];
  Object? lastError;
  for (final candidate in candidates) {
    try {
      return PdfiumBindings(DynamicLibrary.open(candidate));
    } on ArgumentError catch (e) {
      lastError = e;
    }
  }
  throw PdfiumLibraryNotFound(candidates, lastError);
}

String _defaultLibraryName() {
  if (Platform.isAndroid || Platform.isLinux) return 'libpdfium.so';
  if (Platform.isWindows) return 'pdfium.dll';
  throw UnsupportedError(
    'PDFium is not set up for ${Platform.operatingSystem} yet.',
  );
}

String? _findInWorkspace() {
  var dir = Directory.current.absolute;
  while (true) {
    final lib = File(
      '${dir.path}/third_party/pdfium/linux-x64/lib/libpdfium.so',
    );
    if (lib.existsSync()) return lib.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
