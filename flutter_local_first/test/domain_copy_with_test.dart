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

  group('Note equality', () {
    final a = Note(
      id: 'n1',
      title: 'Title',
      content: 'Body',
      createdAt: now,
      updatedAt: now,
      tags: const ['a', 'b'],
      folderId: 'f1',
    );

    test('identical instances are equal', () {
      // ignore: unrelated_type_equality_checks — intentional self-check
      expect(a == a, isTrue);
    });

    test('structurally identical instances are equal', () {
      final b = Note(
        id: 'n1',
        title: 'Title',
        content: 'Body',
        createdAt: now,
        updatedAt: now,
        tags: const ['a', 'b'],
        folderId: 'f1',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different id produces inequality', () {
      expect(a, isNot(equals(a.copyWith(id: 'n2'))));
    });

    test('different tag list produces inequality', () {
      expect(a, isNot(equals(a.copyWith(tags: const ['a']))));
    });

    test('different tag order produces inequality', () {
      // Tags are stored in the order provided; order matters for equality.
      final reversed = a.copyWith(tags: const ['b', 'a']);
      expect(a, isNot(equals(reversed)));
    });

    test('null folderId vs non-null produces inequality', () {
      expect(a, isNot(equals(a.copyWith(folderId: null))));
    });
  });

  group('Folder equality', () {
    const a = Folder(
      id: 'f1',
      name: 'Work',
      parentFolderId: 'p1',
      sortOrder: 3,
    );

    test('identical instances are equal', () {
      // ignore: unrelated_type_equality_checks — intentional self-check
      expect(a == a, isTrue);
    });

    test('structurally identical instances are equal', () {
      const b = Folder(
        id: 'f1',
        name: 'Work',
        parentFolderId: 'p1',
        sortOrder: 3,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different sortOrder produces inequality', () {
      expect(a, isNot(equals(a.copyWith(sortOrder: 99))));
    });

    test('null parentFolderId vs non-null produces inequality', () {
      expect(a, isNot(equals(a.copyWith(parentFolderId: null))));
    });
  });
}
