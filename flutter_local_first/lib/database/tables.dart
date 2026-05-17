import 'package:drift/drift.dart';

/// Folder hierarchy: [parentFolderId] is nullable for roots.
@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get parentFolderId => text().nullable().references(Folders, #id)();

  /// Added in schema version 2 — illustrates additive migrations.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();

  TextColumn get title => text()();

  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get folderId =>
      text().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

/// Normalized tags for querying and reactive updates.
@DataClassName('NoteTagRow')
class NoteTags extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();

  TextColumn get tag => text()();

  @override
  Set<Column<Object>>? get primaryKey => {noteId, tag};
}
