# Development Log

Professional engineering record for `agent-hamster-wheel`.

## 2026-05-18 — Flutter Local-First Notes Review

### Scope and Baseline

Created this log at the repository root and reviewed the project layout. The active Flutter app is `flutter_local_first`, a Drift-backed local-first notes prototype using SQLite FTS5 for title/content search.

Baseline verification completed before implementation changes:

- `flutter analyze` passed with no issues.
- `flutter test` passed with the existing two tests.

### Issues Found and Fixed

Found an FTS5 maintenance bug in `AppDatabase`: the virtual table and triggers were installed only on fresh database creation. Databases opened after an upgrade or repair path could miss FTS infrastructure, making search behavior depend on database history. The fix moves FTS installation into `MigrationStrategy.beforeOpen`, after migrations and foreign-key setup, so fresh and upgraded databases converge on the same search setup.

Found an FTS5 external-content trigger bug in note update/delete handling. The delete commands omitted the previous indexed `title` and `content` values, which can leave stale terms in the full-text index after a note is edited or deleted. The triggers now pass `old.title` and `old.content` when deleting old index entries.

Found a repair gap for already-opened databases with stale or missing FTS rows. The installer now runs `INSERT INTO fts_notes(fts_notes) VALUES ('rebuild')` to repopulate the FTS index from the canonical `notes` table. App-owned triggers are dropped and recreated on open so older trigger definitions are replaced safely.

### Refactoring and Optimization

Refactored `NotesLocalRepository` by adding `_notesFromSearchRows`, a shared mapper for raw FTS query rows plus tag hydration. Both `searchNotes` and `watchSearchResults` now use the same conversion path, reducing duplicated mapping logic and preventing one-shot and reactive search from drifting apart.

The optimization here is structural rather than benchmark-driven: empty search-result mapping short-circuits in one shared location, duplicate list/tag hydration code was removed, and future field additions now have one mapping path to update.

### Test Coverage

Added repository coverage for FTS update/delete maintenance. The new test inserts a note, confirms the original search term is indexed, updates the note, confirms the old term disappears and the new term appears, then deletes the note and confirms the new term disappears.

### Final Verification

Final verification completed successfully:

- `dart format lib/database/app_database.dart lib/data/local_repositories.dart test/repository_test.dart`
- `flutter analyze`
- `flutter test`
- IDE diagnostics for edited files reported no linter errors.

## 2026-05-18 — Follow-Up Review Pass

### Session Restart

Started a follow-up engineering pass after commit `e308ab1` was pushed. The immediate goal is to re-check the current repository state, look for any remaining issues or refactoring opportunities, document findings before each transition, and push any additional improvements if needed.

### Follow-Up Findings

- Confirmed the branch was clean and aligned with `origin/result-flutter-gpt-5-5` before this follow-up pass, aside from this log update.
- Reviewed `app.dart`, `domain/note.dart`, `domain/folder.dart`, and `widget_test.dart`.
- Found a domain modeling bug: `Note.copyWith` and `Folder.copyWith` cannot explicitly clear nullable fields (`folderId` and `parentFolderId`) because `null` currently means "keep the existing value." Root cause: nullable optional parameters are being used for both absence and an intentional null value.
- Found weak widget coverage: `widget_test.dart` builds a generic `MaterialApp`/`Scaffold` instead of the real `LocalFirstNotesApp`, so it does not catch app-shell regressions in tab setup, repository wiring, or database stream bootstrapping.

### Follow-Up Plan

- Update domain `copyWith` methods to use a private sentinel value for nullable fields, preserving ergonomic calls while allowing explicit clears.
- Replace the generic widget smoke test with a real `LocalFirstNotesApp` smoke test backed by `AppDatabase(NativeDatabase.memory())`.
- Add focused unit coverage for nullable `copyWith` clearing behavior.

### Domain Copy Semantics Fix

- Updated `Note.copyWith` so `folderId` uses a private `_unset` sentinel. This preserves the existing behavior when `folderId` is omitted while allowing callers to pass `folderId: null` to clear a folder assignment.
- Updated `Folder.copyWith` with the same sentinel pattern for `parentFolderId`, allowing a folder to be moved back to the root.
- Technical reasoning: nullable domain fields need three states in `copyWith` calls: omitted, non-null replacement, and explicit null. A private sentinel is the smallest local change that provides those states without adding a broader dependency or new wrapper type.

### Follow-Up Test Improvements

- Added `test/domain_copy_with_test.dart` with focused coverage for preserving, clearing, and replacing `Note.folderId` and `Folder.parentFolderId`.
- Replaced the generic widget smoke test with one that builds `LocalFirstNotesApp` using an in-memory `AppDatabase`, pumps the real app shell, verifies the tabs and empty notes state, then tears down the widget so the app root owns database disposal.
- Architectural reasoning: the widget test now covers the app composition boundary instead of only verifying Flutter's stock `MaterialApp` and `Scaffold` widgets.

### Follow-Up Verification Started

- Started formatting and verification for `domain/note.dart`, `domain/folder.dart`, `widget_test.dart`, and the new `domain_copy_with_test.dart`.
- Formatting completed and `flutter analyze` passed with no issues.
- `flutter test` progressed through the new domain tests, repository test, and app shell test but did not terminate promptly after the widget test, indicating a likely async teardown/open stream issue in the revised widget smoke test rather than a compile or assertion failure.
- Stopped the hanging verification process so the widget-test teardown can be corrected before rerunning the suite.

### App Lifecycle Issue

- Root cause identified: `LocalFirstNotesApp` accepts the app database and creates repositories from it, but the root widget does not close the database when disposed. In tests this can leave Drift resources alive after the real app shell is pumped; in production it also leaves ownership ambiguous.
- Planned fix: add a `dispose` method to `_LocalFirstNotesAppState` that closes `widget.database` after child widgets and stream subscriptions have been disposed.

### App Lifecycle Fix

- Added `dart:async` and `unawaited(widget.database.close())` in `_LocalFirstNotesAppState.dispose`.
- Removed manual database closing from the widget test because ownership now belongs to `LocalFirstNotesApp` for the injected database lifecycle.
- Technical reasoning: repository streams are owned below the app root, while the database is supplied to the app root. Closing the database from the root `dispose` keeps lifecycle ownership local and prevents test processes from waiting on lingering Drift resources.

### Follow-Up Verification Restarted

- Restarted formatting, analyzer, and full test verification after the app lifecycle fix.
- Verification rerun exited with one widget-test failure: Flutter reported pending zero-duration timers created by Drift stream query cancellation after the app widget was unmounted.
- Root cause: the test disposed the real app shell but did not pump another frame/microtask turn to let Drift's stream cleanup timers drain under Flutter's fake async test binding.
- Planned fix: pump once after replacing the app with `SizedBox.shrink()` so cancellation cleanup completes before Flutter verifies pending timers.

### Widget Test Teardown Fix

- Added an extra `tester.pump()` after unmounting `LocalFirstNotesApp` in `widget_test.dart`.
- Technical reasoning: Drift schedules stream-query cleanup through a zero-duration timer when listeners are cancelled. Pumping after unmount drains that cleanup in the fake async test environment and keeps the test focused on app-shell behavior rather than harness timing.

### Final Follow-Up Verification Started

- Restarted `dart format`, `flutter analyze`, and `flutter test` after the widget teardown fix.
- Verification still failed with the same pending Drift cleanup timers, so an immediate pump did not advance fake time far enough to fire the zero-duration timers created during stream cancellation.
- Planned adjustment: pump a small positive duration after unmounting the app to advance the fake clock and execute pending cleanup timers.

### Widget Test Timer Drain Adjustment

- Changed the teardown pump to `tester.pump(const Duration(milliseconds: 1))` after unmounting the app.
- Technical reasoning: advancing fake time by a positive duration gives Drift's stream cleanup timers a chance to execute before Flutter's pending-timer invariant runs.

### Verification After Timer Drain Started

- Restarted formatting, analyzer, and full test verification after the positive-duration teardown pump.
- Verification passed: `dart format` reported no further changes, `flutter analyze` found no issues, and `flutter test` passed all five tests.

## 2026-05-18 — Third Review Pass

### Session Restart

Started a third engineering review pass after commit `bc1ee0a` was pushed. The goals are to confirm the repository is clean, inspect remaining database/repository behavior for correctness and optimization opportunities, document each finding before acting, and push any additional improvements with the finalized log.

### Third-Pass Findings

- Confirmed the branch was aligned with `origin/result-flutter-gpt-5-5` at the start of this pass, with only this log modified.
- Reviewed `local_repositories.dart`, `tables.dart`, `repository_test.dart`, and `app_database.dart`.
- Found a startup performance issue in `AppDatabase._installFts5`: the FTS5 `rebuild` command runs on every database open. Root cause: the prior repair path optimized for correctness by unconditionally repopulating the index from `notes`, but that turns app startup into O(number of notes) work even when the FTS index is already current.
- Planned fix: keep virtual table and trigger installation idempotent on every open, but run the full FTS rebuild only when Drift reports the database was newly created or upgraded.

### FTS Startup Optimization

- Updated `AppDatabase.migration.beforeOpen` to pass `rebuild: details.wasCreated || details.hadUpgrade` into `_installFts5`.
- Updated `_installFts5` to accept a required `rebuild` flag and run the expensive FTS5 `rebuild` command only when that flag is true.
- Kept virtual table creation and trigger recreation on every open because those operations are idempotent and cheap compared with rebuilding the entire search index.
- Expected performance gain: normal app opens now avoid an O(number of notes) FTS index rebuild and only perform constant-size schema/trigger repair work. Fresh installs and migrations still rebuild the index to preserve correctness.

### Third-Pass Verification Started

- Started formatting, static analysis, and test verification after the conditional FTS rebuild change.
- Verification passed: `dart format lib/database/app_database.dart`, `flutter analyze`, and `flutter test` all completed successfully with five passing tests.

### Optimization Correction

- During final diff review, identified a correctness gap in the creation/upgrade-only rebuild condition: a schema-current database with existing notes but missing or stale FTS rows would skip the one-time repair because Drift would report neither creation nor upgrade.
- Revised plan: create a tiny app-owned `app_metadata` table and store an `fts_rebuild_v1` marker after a successful rebuild. The app will rebuild on fresh installs, migrations, or when that marker is absent, then skip rebuilds on later normal opens.
- Technical reasoning: this preserves the startup optimization while still repairing existing databases exactly once for this FTS maintenance version.

### One-Time FTS Repair Marker

- Added `app_metadata` creation inside `_installFts5` and read the `fts_rebuild_v1` marker before deciding whether to run the FTS5 rebuild.
- Updated rebuild logic to run when Drift reports database creation/upgrade or when the marker is absent, then store `fts_rebuild_v1 = complete` after rebuilding.
- Current state: FTS virtual table and trigger repair still run on every open; full index rebuild runs only for fresh installs, migrations, or databases not yet marked as repaired.

### Third-Pass Verification Restarted

- Restarted formatting, static analysis, and test verification after adding the one-time FTS repair marker.
- Verification passed: `dart format lib/database/app_database.dart`, `flutter analyze`, and `flutter test` completed successfully with five passing tests.

## 2026-05-18 — Fourth Review Pass

### Session Restart

Started a fourth engineering review pass after commit `0154325` was pushed. The current branch is expected to include the FTS trigger repair, app lifecycle cleanup, nullable `copyWith` fixes, and one-time FTS rebuild marker. This pass will re-check repository state, inspect the latest database metadata path and related tests, and push any additional corrections only if they are justified.

### Fourth-Pass Findings

- Confirmed the branch was aligned with `origin/result-flutter-gpt-5-5` at the start of this pass, with only this log modified.
- Reviewed `app_database.dart` and `repository_test.dart`.
- Found a test coverage gap in the one-time FTS repair marker path: current tests prove insert/update/delete FTS behavior, but they do not prove that a schema-current database with a missing `fts_rebuild_v1` marker repairs stale or missing FTS rows on the next open.
- Planned fix: add a file-backed repository test that removes the marker and clears FTS rows, closes the database, reopens it, and verifies search works again due to the marker-based rebuild.

### FTS Repair Marker Test

- Added a file-backed repository regression test in `repository_test.dart`.
- The test inserts a searchable note, manually clears `fts_notes`, deletes the `fts_rebuild_v1` marker, verifies search is stale, closes and reopens the database, then verifies search works again.
- Technical reasoning: an in-memory database cannot exercise the reopen path, so the test uses a temporary SQLite file and deletes it after the assertion.

### Fourth-Pass Verification Started

- Started formatting, static analysis, and test verification after adding the file-backed FTS repair marker test.
- Verification passed: `dart format test/repository_test.dart`, `flutter analyze`, and `flutter test` completed successfully with six passing tests.
