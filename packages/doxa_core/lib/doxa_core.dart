// SPDX-License-Identifier: GPL-3.0-or-later

/// Pure Dart domain layer of Doxa PDF: annotation models, geometry,
/// commands and undo/redo.
///
/// This package must not depend on Flutter, so it can be tested with plain
/// `dart test`. See docs/plan/03-architecture.md §2.
library;

export 'src/annotation_id.dart';
export 'src/geometry.dart';
export 'src/pdf_date.dart';

/// Name of this package, used by smoke tests until real APIs land.
const String packageName = 'doxa_core';
