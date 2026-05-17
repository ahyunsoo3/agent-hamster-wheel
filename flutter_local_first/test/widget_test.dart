import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Material shell builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('local-first benchmark'),
        ),
      ),
    );

    expect(find.text('local-first benchmark'), findsOneWidget);
  });
}
