import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_first_notes/app.dart';
import 'package:local_first_notes/database/app_database.dart';

void main() {
  testWidgets('LocalFirstNotesApp shows empty-notes state', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final db = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(LocalFirstNotesApp(database: db));
    await tester.pumpAndSettle();

    expect(find.text('Notes & folders'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await db.close();
    await tester.pump(const Duration(seconds: 1));
  });
}
