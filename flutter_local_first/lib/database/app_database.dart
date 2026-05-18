import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Folders, Notes, NoteTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openExecutor());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Blueprint: additive schema change from v1 → v2.
      if (from < 2) {
        await m.addColumn(folders, folders.sortOrder);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await _installFts5(
        this,
        rebuild: details.wasCreated || details.hadUpgrade,
      );
    },
  );

  /// FTS5 external-content index + triggers keep title/content searchable on the IO thread.
  static Future<void> _installFts5(
    GeneratedDatabase db, {
    required bool rebuild,
  }) async {
    await db.customStatement('''
CREATE VIRTUAL TABLE IF NOT EXISTS fts_notes USING fts5(
  title,
  content,
  content='notes',
  content_rowid='rowid'
);
''');

    await db.customStatement('''
CREATE TABLE IF NOT EXISTS app_metadata(
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
);
''');

    final rebuildRows = await db
        .customSelect(
          "SELECT value FROM app_metadata WHERE key = 'fts_rebuild_v1';",
        )
        .get();

    if (rebuild || rebuildRows.isEmpty) {
      await db.customStatement(
        "INSERT INTO fts_notes(fts_notes) VALUES ('rebuild');",
      );
      await db.customStatement('''
INSERT OR REPLACE INTO app_metadata(key, value)
VALUES ('fts_rebuild_v1', 'complete');
''');
    }

    for (final trigger in ['notes_ai', 'notes_ad', 'notes_au']) {
      await db.customStatement('DROP TRIGGER IF EXISTS $trigger;');
    }

    await db.customStatement('''
CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO fts_notes(rowid, title, content)
  VALUES (new.rowid, new.title, new.content);
END;
''');

    await db.customStatement('''
CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO fts_notes(fts_notes, rowid, title, content)
  VALUES ('delete', old.rowid, old.title, old.content);
END;
''');

    await db.customStatement('''
CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
  INSERT INTO fts_notes(fts_notes, rowid, title, content)
  VALUES ('delete', old.rowid, old.title, old.content);
  INSERT INTO fts_notes(rowid, title, content)
  VALUES (new.rowid, new.title, new.content);
END;
''');
  }

  static QueryExecutor _openExecutor() {
    return driftDatabase(
      name: 'local_first_notes',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}

/// Opens a file-backed executor (tests / tooling).
LazyDatabase openLazyDatabaseFile(String fileName) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, fileName));
    return NativeDatabase.createInBackground(file);
  });
}
