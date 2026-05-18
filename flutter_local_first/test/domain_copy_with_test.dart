import 'package:flutter_test/flutter_test.dart';

import 'package:local_first_notes/domain/folder.dart';
import 'package:local_first_notes/domain/note.dart';

void main() {
  final now = DateTime.utc(2026, 5, 17);

  group('Note.copyWith', () {
    final base = Note(
      id: 'n1',
      title: 'Title',
      content: 'Body',
      createdAt: now,
      updatedAt: now,
      tags: const ['a'],
      folderId: 'f1',
    );

    test('preserves folderId when omitted', () {
      expect(base.copyWith(title: 'New').folderId, 'f1');
    });

    test('clears folderId when explicitly null', () {
      expect(base.copyWith(folderId: null).folderId, isNull);
    });

    test('replaces folderId with a new value', () {
      expect(base.copyWith(folderId: 'f2').folderId, 'f2');
    });
  });

  group('Folder.copyWith', () {
    const base = Folder(id: 'f1', name: 'Root', parentFolderId: 'p1');

    test('preserves parentFolderId when omitted', () {
      expect(base.copyWith(name: 'New').parentFolderId, 'p1');
    });

    test('clears parentFolderId when explicitly null', () {
      expect(base.copyWith(parentFolderId: null).parentFolderId, isNull);
    });

    test('replaces parentFolderId with a new value', () {
      expect(base.copyWith(parentFolderId: 'p2').parentFolderId, 'p2');
    });
  });
}
