import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_first_notes/app.dart';
import 'package:local_first_notes/database/app_database.dart';

void main() {
  testWidgets('LocalFirstNotesApp shell builds and shows empty state', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());

    try {
      await tester.pumpWidget(LocalFirstNotesApp(database: db));
      await tester.pump();

      // App shell renders the tab bar.
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Folders'), findsOneWidget);

      // Empty notes tab shows the placeholder text.
      expect(find.text('No notes yet'), findsOneWidget);
    } finally {
      // Unmount the app so LocalFirstNotesApp.dispose closes the database,
      // then drain Drift's zero-duration stream cleanup timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
