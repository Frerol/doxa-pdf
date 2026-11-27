// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _licenseDirectory = 'assets/pdfium-licenses/';

// Filenames in the PDFium distribution pinned by tools/pdfium.lock.
const _packageNames = {
  'abseil.txt': 'Abseil',
  'agg23.txt': 'Anti-Grain Geometry',
  'dragonbox-Apache2-LLVM.txt': 'Dragonbox',
  'dragonbox-Boost.txt': 'Dragonbox',
  'fast_float.txt': 'fast_float',
  'freetype.txt': 'FreeType',
  'harfbuzz.txt': 'HarfBuzz',
  'highway.txt': 'Highway',
  'icu.txt': 'ICU',
  'lcms.txt': 'Little CMS',
  'libjpeg_turbo.ijg': 'libjpeg-turbo',
  'libjpeg_turbo.md': 'libjpeg-turbo',
  'libopenjpeg.txt': 'OpenJPEG',
  'libpng.txt': 'libpng',
  'llvm-libc.txt': 'LLVM libc',
  'pdfium-LICENSE': 'PDFium',
  'pdfium.txt': 'PDFium',
  'simdutf.txt': 'simdutf',
  'zlib.txt': 'zlib',
};

void registerPdfiumLicenses() {
  LicenseRegistry.addLicense(() async* {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets()) {
      if (!asset.startsWith(_licenseDirectory)) continue;
      final filename = asset.substring(_licenseDirectory.length);
      final package = _packageNames[filename] ?? filename;
      // The pinned FreeType notice uses ISO-8859-1 for its copyright sign.
      final text = filename == 'freetype.txt'
          ? await rootBundle.loadStructuredBinaryData(
              asset,
              (data) async => latin1.decode(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              ),
            )
          : await rootBundle.loadString(asset);
      yield LicenseEntryWithLineBreaks([package], text);
    }
  });
}
