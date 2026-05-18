import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:local_first_notes/data/local_repositories.dart';
import 'package:local_first_notes/database/app_database.dart';
import 'package:local_first_notes/domain/folder.dart';
import 'package:local_first_notes/domain/note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CRUD + FTS5 search runs off main isolate contract', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final notes = NotesLocalRepository(db);
    final id = const Uuid().v4();
    final now = DateTime.utc(2026, 5, 17);

    await notes.upsertNote(
      Note(
        id: id,
        title: 'Hello FTS',
        content: '# Markdown\nworks with plain UTF-8 text.',
        createdAt: now,
        updatedAt: now,
        tags: const ['spec', 'dart'],
        folderId: null,
      ),
    );

    final found = await notes.searchNotes('hello');
    expect(found, hasLength(1));
    expect(found.single.title, 'Hello FTS');

    final hits = await notes.searchNotes('markdown');
    expect(hits, hasLength(1));

    await db.close();
  });

  test('FTS5 update and delete maintain index correctly', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final notes = NotesLocalRepository(db);
    final id = const Uuid().v4();
    final now = DateTime.utc(2026, 5, 17);

    await notes.upsertNote(
      Note(
        id: id,
        title: 'Original title',
        content: 'Original content',
        createdAt: now,
        updatedAt: now,
        tags: const [],
        folderId: null,
      ),
    );

    expect(await notes.searchNotes('original'), hasLength(1));

    // Update the note — old terms should leave the index, new terms should appear.
    await notes.upsertNote(
      Note(
        id: id,
        title: 'Revised title',
        content: 'Revised content',
        createdAt: now,
        updatedAt: now.add(const Duration(seconds: 1)),
        tags: const [],
        folderId: null,
      ),
    );

    expect(await notes.searchNotes('original'), isEmpty);
    expect(await notes.searchNotes('revised'), hasLength(1));

    // Delete the note — all terms should leave the index.
    await notes.deleteNote(id);
    expect(await notes.searchNotes('revised'), isEmpty);

    await db.close();
  });

  test(
    'FoldersLocalRepository getFolderById returns null for unknown id',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final folders = FoldersLocalRepository(db);

      expect(await folders.getFolderById('no-such-id'), isNull);

      await db.close();
    },
  );

  test('FoldersLocalRepository upsert and getFolderById round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final folders = FoldersLocalRepository(db);

    const folder = Folder(id: 'f1', name: 'Work', sortOrder: 2);
    await folders.upsertFolder(folder);

    final retrieved = await folders.getFolderById('f1');
    expect(retrieved, isNotNull);
    expect(retrieved, equals(folder));

    // Update via upsert and confirm the change is reflected.
    await folders.upsertFolder(folder.copyWith(name: 'Work — updated'));
    final updated = await folders.getFolderById('f1');
    expect(updated?.name, 'Work — updated');

    await db.close();
  });

  test('FTS5 repair marker triggers rebuild on next open', () async {
    final tmpDir = await Directory.systemTemp.createTemp('fts_repair_test_');
    final dbPath = p.join(tmpDir.path, 'repair_test.sqlite');
    AppDatabase? db;

    try {
      db = AppDatabase(NativeDatabase(File(dbPath)));
      final notes = NotesLocalRepository(db);
      final id = const Uuid().v4();
      final now = DateTime.utc(2026, 5, 17);

      await notes.upsertNote(
        Note(
          id: id,
          title: 'Searchable note',
          content: 'Some searchable content',
          createdAt: now,
          updatedAt: now,
          tags: const [],
          folderId: null,
        ),
      );

      expect(await notes.searchNotes('searchable'), hasLength(1));

      // Simulate a stale FTS state: clear the FTS table and remove the marker.
      await db.customStatement('DELETE FROM fts_notes;');
      await db.customStatement(
        "DELETE FROM app_metadata WHERE key = 'fts_rebuild_v1';",
      );

      // After clearing, search should return nothing.
      expect(await notes.searchNotes('searchable'), isEmpty);

      await db.close();
      db = null;

      // Reopen — the missing marker should trigger an FTS rebuild.
      db = AppDatabase(NativeDatabase(File(dbPath)));
      final notes2 = NotesLocalRepository(db);
      expect(await notes2.searchNotes('searchable'), hasLength(1));
    } finally {
      await db?.close();
      await tmpDir.delete(recursive: true);
    }
  });
}
