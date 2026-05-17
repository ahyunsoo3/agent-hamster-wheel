import 'package:flutter/material.dart';

import 'app.dart';
import 'database/app_database.dart';

/// Production entry uses persistent storage via [drift_flutter].
///
/// Tests may inject an in-memory [AppDatabase] by passing [database].
void bootstrap({AppDatabase? database}) {
  WidgetsFlutterBinding.ensureInitialized();
  final db = database ?? AppDatabase();
  runApp(LocalFirstNotesApp(database: db));
}
