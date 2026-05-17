import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:local_first_notes/data/local_repositories.dart';
import 'package:local_first_notes/database/app_database.dart';
import 'package:local_first_notes/domain/note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fts5PrefixQuery treats whitespace-only input as empty', () {
    expect(fts5PrefixQuery(''), '');
    expect(fts5PrefixQuery('   '), '');
    expect(fts5PrefixQuery('\t\n'), '');
    expect(fts5PrefixQuery('  hello '), isNotEmpty);
  });

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
}
