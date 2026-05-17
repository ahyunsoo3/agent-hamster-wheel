import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart';

import '../database/app_database.dart';
import '../domain/folder.dart';
import '../domain/note.dart';

/// Maps persistence rows to strictly typed domain models.
Folder _folderFromRow(FolderRow row) => Folder(
      id: row.id,
      name: row.name,
      parentFolderId: row.parentFolderId,
      sortOrder: row.sortOrder,
    );

Note _noteFromRow(NoteRow row, List<String> tags) => Note(
      id: row.id,
      title: row.title,
      content: row.content,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      tags: List.unmodifiable(tags),
      folderId: row.folderId,
    );

Map<String, List<String>> _tagsByNoteId(List<NoteTagRow> tagRows) {
  final map = <String, List<String>>{};
  for (final row in tagRows) {
    map.putIfAbsent(row.noteId, () => []).add(row.tag);
  }
  for (final entry in map.entries) {
    entry.value.sort();
  }
  return map;
}

/// Escapes a user token for safe FTS5 prefix search (`token*`).
String fts5PrefixQuery(String raw) {
  final tokens = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return '';

  String escapeToken(String t) {
    var s = t.replaceAll('"', '""');
    s = s.replaceAll("'", "''");
    return '"$s"*';
  }

  return tokens.map(escapeToken).join(' AND ');
}

/// Local-first persistence API: async I/O only, reactive streams for lists.
class NotesLocalRepository {
  NotesLocalRepository(this._db);

  final AppDatabase _db;

  Stream<List<Note>> watchNotes() {
    final notes$ = (_db.select(_db.notes)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();

    final tags$ = _db.select(_db.noteTags).watch();

    return Rx.combineLatest2<List<NoteRow>, List<NoteTagRow>, List<Note>>(
      notes$,
      tags$,
      (noteRows, tagRows) {
        final byNote = _tagsByNoteId(tagRows);
        return noteRows
            .map((r) => _noteFromRow(r, List<String>.from(byNote[r.id] ?? const [])))
            .toList(growable: false);
      },
    );
  }

  /// FTS5 over native `fts_notes` — matches [Note.title] and [Note.content].
  Future<List<Note>> searchNotes(String query) async {
    final fts = fts5PrefixQuery(query);
    if (fts.isEmpty) return [];

    final rows = await _db.customSelect(
      '''
SELECT
  n.id AS id,
  n.title AS title,
  n.content AS content,
  n.created_at AS created_at,
  n.updated_at AS updated_at,
  n.folder_id AS folder_id
FROM notes AS n
INNER JOIN fts_notes ON fts_notes.rowid = n.rowid
WHERE fts_notes MATCH ?
ORDER BY bm25(fts_notes)
''',
      variables: [Variable.withString(fts)],
      readsFrom: {_db.notes},
    ).get();

    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r.read<String>('id')).toList();
    final tagRows = await (_db.select(_db.noteTags)
          ..where((t) => t.noteId.isIn(ids)))
        .get();
    final byNote = _tagsByNoteId(tagRows);

    return rows.map((r) {
      final id = r.read<String>('id');
      return Note(
        id: id,
        title: r.read<String>('title'),
        content: r.read<String>('content'),
        createdAt: r.read<DateTime>('created_at'),
        updatedAt: r.read<DateTime>('updated_at'),
        tags: List.unmodifiable(List<String>.from(byNote[id] ?? const [])),
        folderId: r.readNullable<String>('folder_id'),
      );
    }).toList(growable: false);
  }

  /// Reacts to note / FTS-backed rows changing (insert/update/delete).
  Stream<List<Note>> watchSearchResults(String query) {
    final fts = fts5PrefixQuery(query);
    if (fts.isEmpty) {
      return Stream<List<Note>>.value(const []);
    }

    return _db
        .customSelect(
          '''
SELECT
  n.id AS id,
  n.title AS title,
  n.content AS content,
  n.created_at AS created_at,
  n.updated_at AS updated_at,
  n.folder_id AS folder_id
FROM notes AS n
INNER JOIN fts_notes ON fts_notes.rowid = n.rowid
WHERE fts_notes MATCH ?
ORDER BY bm25(fts_notes)
''',
          variables: [Variable.withString(fts)],
          readsFrom: {_db.notes, _db.noteTags},
        )
        .watch()
        .asyncMap((rows) async {
          if (rows.isEmpty) return const <Note>[];

          final ids = rows.map((r) => r.read<String>('id')).toList();
          final tagRows = await (_db.select(_db.noteTags)
                ..where((t) => t.noteId.isIn(ids)))
              .get();
          final byNote = _tagsByNoteId(tagRows);

          return rows.map((r) {
            final id = r.read<String>('id');
            return Note(
              id: id,
              title: r.read<String>('title'),
              content: r.read<String>('content'),
              createdAt: r.read<DateTime>('created_at'),
              updatedAt: r.read<DateTime>('updated_at'),
              tags: List.unmodifiable(List<String>.from(byNote[id] ?? const [])),
              folderId: r.readNullable<String>('folder_id'),
            );
          }).toList(growable: false);
        });
  }

  Future<Note?> getNoteById(String id) async {
    final row = await (_db.select(_db.notes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;

    final tags = await (_db.select(_db.noteTags)
          ..where((t) => t.noteId.equals(id)))
        .get();
    return _noteFromRow(row, tags.map((e) => e.tag).toList()..sort());
  }

  Future<void> upsertNote(Note note) async {
    await _db.transaction(() async {
      await _db.into(_db.notes).insertOnConflictUpdate(
            NotesCompanion.insert(
              id: note.id,
              title: note.title,
              content: note.content,
              createdAt: note.createdAt,
              updatedAt: note.updatedAt,
              folderId: Value(note.folderId),
            ),
          );

      await (_db.delete(_db.noteTags)
            ..where((t) => t.noteId.equals(note.id)))
          .go();

      await _db.batch((b) {
        for (final tag in note.tags.toSet()) {
          b.insert(
            _db.noteTags,
            NoteTagsCompanion.insert(noteId: note.id, tag: tag),
          );
        }
      });
    });
  }

  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((t) => t.id.equals(id))).go();
  }
}

class FoldersLocalRepository {
  FoldersLocalRepository(this._db);

  final AppDatabase _db;

  Stream<List<Folder>> watchFolders() {
    return (_db.select(_db.folders)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map(_folderFromRow).toList(growable: false));
  }

  Future<void> upsertFolder(Folder folder) async {
    await _db.into(_db.folders).insertOnConflictUpdate(
          FoldersCompanion.insert(
            id: folder.id,
            name: folder.name,
            parentFolderId: Value(folder.parentFolderId),
            sortOrder: Value(folder.sortOrder),
          ),
        );
  }

  Future<void> deleteFolder(String id) async {
    await (_db.delete(_db.folders)..where((t) => t.id.equals(id))).go();
  }
}
