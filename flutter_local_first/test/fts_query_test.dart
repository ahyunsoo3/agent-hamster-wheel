import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:local_first_notes/data/local_repositories.dart';
import 'package:local_first_notes/database/app_database.dart';
import 'package:local_first_notes/domain/note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // fts5PrefixQuery — unit tests for the query-builder function.
  // ---------------------------------------------------------------------------

  group('fts5PrefixQuery', () {
    test('empty string returns empty', () {
      expect(fts5PrefixQuery(''), isEmpty);
    });

    test('whitespace-only string returns empty', () {
      expect(fts5PrefixQuery('   '), isEmpty);
    });

    test('single word is wrapped in double-quoted prefix phrase', () {
      expect(fts5PrefixQuery('hello'), '"hello"*');
    });

    test('two words are joined with AND', () {
      expect(fts5PrefixQuery('foo bar'), '"foo"* AND "bar"*');
    });

    test('extra internal whitespace is collapsed', () {
      expect(fts5PrefixQuery('foo  bar'), '"foo"* AND "bar"*');
    });

    test('double-quote inside token is escaped as "" in FTS5 phrase', () {
      // 'say "hi"' whitespace-splits into two tokens: [say] and ["hi"].
      // The ["hi"] token has its internal double-quotes doubled, producing
      // the FTS5 phrase """hi"""* (outer quotes + ""hi"" + outer quote + *).
      expect(fts5PrefixQuery('say "hi"'), '"say"* AND """hi"""*');
    });

    test('apostrophe is preserved verbatim — NOT doubled', () {
      // A single quote must not be doubled; doubling is a SQL string-literal
      // escape that corrupts the FTS5 phrase when the query is a bound param.
      final result = fts5PrefixQuery("it's");
      expect(result, '"it\'s"*');
      expect(result, isNot(contains("''")));
    });

    test('apostrophe in multi-word query is preserved in each token', () {
      final result = fts5PrefixQuery("don't stop");
      expect(result, '"don\'t"* AND "stop"*');
    });
  });

  // ---------------------------------------------------------------------------
  // End-to-end: FTS5 correctly finds notes containing apostrophes.
  // ---------------------------------------------------------------------------

  group('FTS5 apostrophe search', () {
    test(
      'searching for a term with an apostrophe finds matching note',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final notes = NotesLocalRepository(db);
        final id = const Uuid().v4();
        final now = DateTime.utc(2026, 5, 17);

        await notes.upsertNote(
          Note(
            id: id,
            title: "Don't forget this",
            content: "It's important",
            createdAt: now,
            updatedAt: now,
            tags: const [],
            folderId: null,
          ),
        );

        // The FTS5 tokenizer treats apostrophes as part of the token.
        // With the bugfix, searching "don't" or "it's" should find the note.
        final byTitle = await notes.searchNotes("don't");
        expect(byTitle, hasLength(1));
        expect(byTitle.single.id, id);

        final byContent = await notes.searchNotes("it's");
        expect(byContent, hasLength(1));
        expect(byContent.single.id, id);

        await db.close();
      },
    );
  });
}
