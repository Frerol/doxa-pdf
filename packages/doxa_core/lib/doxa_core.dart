// SPDX-License-Identifier: GPL-3.0-or-later

/// Pure Dart domain layer of Doxa PDF: annotation models, geometry,
/// commands and undo/redo.
///
/// This package must not depend on Flutter, so it can be tested with plain
/// `dart test`. See docs/plan/03-architecture.md §2.
library;

export 'src/annotation.dart';
export 'src/annotation_command.dart';
export 'src/annotation_history.dart';
export 'src/annotation_id.dart';
export 'src/annotation_json.dart' show AnnotationJson;
export 'src/geometry.dart';
export 'src/page_transform.dart';
export 'src/pdf_date.dart';
export 'src/study_palette.dart';

/// Name of this package, used by smoke tests until real APIs land.
const String packageName = 'doxa_core';
