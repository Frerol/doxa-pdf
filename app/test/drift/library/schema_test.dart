// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/features/library/library_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  // Changing a table without bumping schemaVersion and saving the schema
  // (`dart run drift_dev make-migrations`) would ship a database that
  // existing installs cannot migrate to.
  test('the current schema matches the last saved schema version', () async {
    final schema = await verifier.schemaAt(1);
    final db = LibraryDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
  });
}
