import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_first_notes/app.dart';
import 'package:local_first_notes/database/app_database.dart';

void main() {
  testWidgets('LocalFirstNotesApp shell builds', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    try {
      await tester.pumpWidget(LocalFirstNotesApp(database: db));
      await tester.pump();

      expect(find.text('Notes & folders'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Folders'), findsOneWidget);
      expect(find.text('No notes yet'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
