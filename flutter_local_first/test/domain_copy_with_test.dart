import 'package:flutter_test/flutter_test.dart';

import 'package:local_first_notes/domain/folder.dart';
import 'package:local_first_notes/domain/note.dart';

void main() {
  test('Note.copyWith can clear folderId', () {
    final now = DateTime.utc(2026, 5, 18);
    final note = Note(
      id: 'note-1',
      title: 'Title',
      content: 'Content',
      createdAt: now,
      updatedAt: now,
      tags: const ['tag'],
      folderId: 'folder-1',
    );

    expect(note.copyWith().folderId, 'folder-1');
    expect(note.copyWith(folderId: null).folderId, isNull);
    expect(note.copyWith(folderId: 'folder-2').folderId, 'folder-2');
  });

  test('Folder.copyWith can clear parentFolderId', () {
    const folder = Folder(
      id: 'folder-1',
      name: 'Child',
      parentFolderId: 'root',
      sortOrder: 1,
    );

    expect(folder.copyWith().parentFolderId, 'root');
    expect(folder.copyWith(parentFolderId: null).parentFolderId, isNull);
    expect(
      folder.copyWith(parentFolderId: 'archive').parentFolderId,
      'archive',
    );
  });
}
