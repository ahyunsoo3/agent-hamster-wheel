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

## 2026-05-18 — Fifth Review Pass

### Session Restart

Started a fifth engineering review pass after commit `37d9bf4` was pushed. The repository is expected to include the FTS repair marker regression test. This pass will check the current state, review the latest test additions for robustness and cleanup behavior, and only make further changes if they reduce risk or clarify maintenance.

### Fifth-Pass Findings

- Confirmed the branch was aligned with `origin/result-flutter-gpt-5-5` at the start of this pass, with only this log modified.
- Reviewed `repository_test.dart`, focusing on the file-backed FTS repair marker regression test added in the previous pass.
- Found a test robustness issue: the temporary directory and open database are cleaned up only on the success path. Root cause: the test uses direct cleanup at the end of the body instead of `try/finally`, so a failing assertion could leave a SQLite file or open database resource behind.
- Planned fix: wrap the file-backed test body in `try/finally`, track the current `AppDatabase`, close it defensively, and delete the temporary directory even when assertions fail.

### Test Resource Cleanup Fix

- Updated the file-backed FTS repair marker test to track the active `AppDatabase` as nullable state and wrap the test body in `try/finally`.
- The test now closes any active database and deletes the temporary directory in the `finally` block, including assertion failure paths.
- Technical reasoning: file-backed tests should not leak temporary SQLite files or native database handles when they fail, because leaks can obscure the original failure or affect later tests on the same worker.

### Fifth-Pass Verification Started

- Started formatting, static analysis, and test verification after hardening the file-backed test cleanup path.
- Verification passed: `dart format test/repository_test.dart`, `flutter analyze`, and `flutter test` completed successfully with six passing tests.

## 2026-05-18 — Sixth Review Pass

### Session Restart

Started a sixth engineering review pass after commit `fee4f62` was pushed. The repository is expected to include hardened file-backed test cleanup, one-time FTS rebuild repair, app lifecycle cleanup, and nullable domain copy fixes. This pass will re-check the current branch state and perform a focused sweep for remaining correctness, refactoring, or optimization opportunities.

### Sixth-Pass Findings

- Confirmed the branch was aligned with `origin/result-flutter-gpt-5-5` at the start of this pass, with only this log modified.
- Reviewed `app.dart`, `domain/note.dart`, `domain/folder.dart`, `domain_copy_with_test.dart`, and `widget_test.dart`.
- Found a test robustness issue in `widget_test.dart`: the test relies on the success path reaching the explicit `SizedBox.shrink()` unmount so `LocalFirstNotesApp.dispose` closes the in-memory database. Root cause: the unmount and fake-time drain are not in a `finally` block, so an assertion failure before teardown could leave app/database resources active.
- Planned fix: wrap the widget smoke test assertions in `try/finally` and always unmount the app plus pump fake time to drain Drift stream cleanup timers.

### Widget Test Cleanup Fix

- Updated `widget_test.dart` so the real app shell is pumped and asserted inside a `try` block.
- Moved the `SizedBox.shrink()` unmount and positive-duration pump into `finally`, ensuring `LocalFirstNotesApp.dispose` runs and Drift cleanup timers drain even if an assertion fails.
- Technical reasoning: the widget test owns the injected in-memory database through the app root, so teardown must be failure-safe to avoid resource leaks and pending fake-async timers.

### Sixth-Pass Verification Started

- Started formatting, static analysis, and test verification after hardening widget-test cleanup.
- Verification passed: `dart format test/widget_test.dart`, `flutter analyze`, and `flutter test` completed successfully with six passing tests.

## 2026-05-18 — Seventh Review Pass

### Session Restart

Started a seventh engineering review pass after commit `54c7ad7` was pushed. The repository is expected to include FTS repair, one-time rebuild optimization, app lifecycle cleanup, nullable copy semantics, and hardened test teardown. This pass will re-check branch state, scan project configuration and generated-code boundaries, and either document no further action or make any narrowly justified improvement.

### Seventh-Pass Findings

- Confirmed the branch was aligned with `origin/result-flutter-gpt-5-5` at the start of this pass, with only this log modified.
- Reviewed `pubspec.yaml`, `analysis_options.yaml`, generated Drift code references in `app_database.g.dart`, and project Markdown inventory.
- Confirmed generated Drift code reflects the hand-written table schema, including `Folders.sortOrder`; no generated-code mismatch was found.
- Identified `flutter_local_first/README.md` as likely stale relative to the repaired FTS lifecycle and test coverage, so the next step is to review it for documentation drift.

### Documentation Issue

- Reviewed `flutter_local_first/README.md` and found it still contains the default Flutter starter text.
- Root cause: the project evolved into a Drift-backed local-first notes reference app, but the README was never updated from the generated template.
- Planned fix: replace the template README with a concise project-specific overview, architecture notes, FTS repair behavior, and verification commands.

### README Refactor

- Replaced the default Flutter README with a project-specific overview for the local-first notes reference app.
- Documented the major source directories, repository/data-layer responsibilities, FTS5 repair strategy, and standard verification commands.
- Architectural reasoning: the README now matches the app's actual purpose and gives future contributors enough context to understand why the database open path performs both cheap trigger repair and conditional full-index rebuilds.

### Seventh-Pass Verification Started

- Started final verification after the README refactor, including standard Flutter analyzer and test commands.
- Verification passed: `flutter analyze` completed with no issues and `flutter test` completed successfully with six passing tests.

## 2026-05-18 — Eighth Review Pass

### Session Restart

Started an eighth engineering review pass after commit `a7c7958` was pushed. The repository is expected to include repaired FTS lifecycle behavior, optimized one-time rebuilds, hardened tests, app-specific README documentation, and the accumulated development log. This pass will verify the branch state and run the standard quality gates before deciding whether any further implementation changes are justified.

### Eighth-Pass Verification Started

- Started repository state verification and the standard Flutter quality gates: branch status, `flutter analyze`, and `flutter test`.
- Branch status showed the branch aligned with `origin/result-flutter-gpt-5-5`, with only this log modified for the current pass.
- `flutter analyze` completed with no issues.
- `flutter test` completed successfully with six passing tests.

### Eighth-Pass Conclusion

- No new code, refactoring, or optimization issue was found during this pass.
- Current state: the implementation remains verified, and this pass only adds the professional log record required for traceability.

## 2026-05-18 — Ninth Review Pass

### Session Restart

Started a ninth engineering review pass after commit `3a22fa0` was pushed. The current task is to re-verify the already-clean implementation, record the result in this log, and avoid unnecessary code churn unless a concrete issue appears.

### Ninth-Pass Verification Started

- Started branch status verification plus the standard `flutter analyze` and `flutter test` quality gates.
- Branch status showed the branch aligned with `origin/result-flutter-gpt-5-5`, with only this log modified for the current pass.
- `flutter analyze` completed with no issues.
- `flutter test` completed successfully with six passing tests.

### Ninth-Pass Conclusion

- No new bugs, refactoring needs, or optimization opportunities were identified in this pass.
- Current state: the codebase remains verified and no implementation files were changed.

## 2026-05-18 — Tenth Review Pass

### Session Restart

Started a tenth engineering review pass after commit `d3b5816` was pushed. The current objective is to re-check repository state, rerun the standard verification gates, and record whether any new issue, refactoring opportunity, or optimization is present.

### Tenth-Pass Verification Started

- Started branch status verification plus the standard `flutter analyze` and `flutter test` quality gates.
- Branch status showed the branch aligned with `origin/result-flutter-gpt-5-5`, with only this log modified for the current pass.
- `flutter analyze` completed with no issues.
- `flutter test` completed successfully with six passing tests.

### Tenth-Pass Conclusion

- No new bugs, refactoring needs, or optimization opportunities were identified.
- Current state: the implementation remains verified, with no implementation-file changes required in this pass.

## 2026-05-18 — Eleventh Review Pass

### Session Restart

Started an eleventh engineering review pass. A full re-read of all implementation and test files revealed that the codebase had regressed to an earlier state, with multiple fixes from prior passes missing. The branch contained only the original single-test repository file and the bare-bones widget smoke test, and the implementation files were missing several layers of correctness improvements.

### Regression Findings

A comprehensive file-by-file review identified the following regressions against the quality bar established across passes 1–10:

- **`domain/note.dart`** — `Note.copyWith` reverted to a naive `??` for `folderId`. The sentinel-based fix allowing callers to explicitly pass `folderId: null` to clear a folder assignment was absent.
- **`domain/folder.dart`** — `Folder.copyWith` had the same regression for `parentFolderId`, losing the ability to explicitly move a folder back to the root.
- **`app.dart`** — The `dart:async` import and `unawaited(widget.database.close())` call in `_LocalFirstNotesAppState.dispose` were missing, leaving database lifecycle ownership ambiguous and leaking resources in tests.
- **`app_database.dart`** — The FTS5 installation had reverted to a simple `CREATE VIRTUAL TABLE IF NOT EXISTS` path with no `beforeOpen` hook, losing: trigger recreation on every open, the `app_metadata` table, the one-time `fts_rebuild_v1` repair marker optimization, and the correct FTS5 delete trigger form (`old.title`/`old.content`).
- **`test/repository_test.dart`** — Only the original single CRUD test remained. The FTS update/delete index-maintenance test and the file-backed FTS repair marker regression test were both absent.
- **`test/widget_test.dart`** — Reverted to a generic `MaterialApp`/`Scaffold` smoke test rather than the real `LocalFirstNotesApp` test with in-memory database and failure-safe `finally` teardown.
- **`test/domain_copy_with_test.dart`** — The focused domain copy-semantics unit tests were absent.

### Fixes Applied

All regressions were corrected in a single pass:

1. **`Note.copyWith` and `Folder.copyWith` sentinel fix** — Introduced a private `_unset` sentinel constant in both domain files. `folderId` and `parentFolderId` now default to `_unset` in `copyWith` and use `identical` to distinguish "omitted" from an explicit `null`. This restores all three states (preserve, replace, clear) needed for safe domain mutation.

2. **`app.dart` database lifecycle** — Re-added the `dart:async` import and `_LocalFirstNotesAppState.dispose` override calling `unawaited(widget.database.close())`. The app root now owns the injected database lifetime and closes it on unmount, preventing resource leaks and test-harness hangs.

3. **`app_database.dart` FTS5 repair** — Fully restored the multi-layer FTS5 maintenance strategy:
   - `beforeOpen` now calls `_installFts5` with a `rebuild` flag derived from `details.wasCreated || details.hadUpgrade`.
   - `_installFts5` creates `app_metadata`, creates the FTS5 virtual table, drops and recreates all three triggers (insert/delete/update) on every open so stale trigger definitions are replaced.
   - FTS5 delete triggers now pass `old.title` and `old.content` to remove the correct index entries on update and delete.
   - A full `INSERT INTO fts_notes(fts_notes) VALUES ('rebuild')` runs only when Drift reports creation/upgrade or when the `fts_rebuild_v1` marker is absent from `app_metadata`, then stores the marker to skip future redundant rebuilds.

4. **`test/repository_test.dart` coverage restored** — Re-added two tests: an FTS update/delete index-maintenance test that verifies old terms leave the index on update and that all terms leave on delete; and a file-backed regression test that clears FTS rows and the repair marker, reopens the database, and verifies the one-time rebuild restores search.

5. **`test/widget_test.dart` real app shell test** — Replaced the generic smoke test with one that builds `LocalFirstNotesApp` using an in-memory `AppDatabase`, verifies the tab bar and empty notes state, and wraps teardown in `finally` to unmount the app and drain Drift's stream cleanup timers with a positive-duration pump.

6. **`test/domain_copy_with_test.dart` restored** — Re-added focused unit tests for all three `copyWith` behaviors (preserve, clear, replace) for both `Note.folderId` and `Folder.parentFolderId`.

### Eleventh-Pass Verification

- `dart format` applied to all six edited files; six files changed.
- `flutter analyze` completed with no issues.
- `flutter test` completed successfully with all ten tests passing across `domain_copy_with_test.dart` (6), `repository_test.dart` (3), and `widget_test.dart` (1).

## 2026-05-18 — Twelfth Review Pass

### Session Restart

Started a twelfth engineering review pass. All implementation files were re-read and verified to be in the correct state from the prior session (eleventh pass), with all fixes intact. The standard quality gates confirmed ten tests passing and no analyzer issues before any changes were made.

### Issues Found

No correctness bugs or runtime regressions were identified in this pass. The following structural and quality issues were found and addressed:

### Refactoring: FTS Row-Mapping Deduplication

- **Finding:** `NotesLocalRepository.searchNotes` and `watchSearchResults` both contained identical row-to-`Note` construction logic: extracting note IDs from the result set, querying tags for those IDs, building a `_tagsByNoteId` map, and constructing `Note` objects field-by-field. Any future addition to the `Note` domain model would require the same change in two places.
- **Fix:** Extracted a private top-level function `_notesFromSearchRows(List<QueryRow> rows, List<NoteTagRow> tagRows)` that handles the shared mapping path. Both `searchNotes` and `watchSearchResults` now delegate to this function after fetching their respective tag rows.
- **Architectural reasoning:** A single mapping path ensures the one-shot and reactive search results are structurally identical and eliminates the risk of the two paths drifting apart when domain fields change.

### Optimization: Linter Rule Enforcement

- **Finding:** `analysis_options.yaml` had `prefer_single_quotes` and `avoid_print` commented out as examples, leaving two coding conventions that the codebase already followed unenforced by the static analyzer.
- **Fix:** Enabled `avoid_print: true` and `prefer_single_quotes: true` in the `linter.rules` section. One double-quoted string literal in `repository_test.dart` (line 112) was found to violate `prefer_single_quotes` and was corrected to a single-quoted string.
- **Architectural reasoning:** Enforcing these rules at the analyzer level makes them machine-verified rather than documentation-only, preventing silent violations in future contributions.

### Documentation: README Restored

- **Finding:** `flutter_local_first/README.md` had regressed to the default Flutter template text, losing the project-specific architecture notes introduced in a prior pass.
- **Fix:** Replaced the template with a comprehensive project-specific README documenting the source layout, FTS5 design decisions (external-content index, trigger recreation strategy, one-time repair marker), reactive stream architecture, and the `copyWith` sentinel pattern for nullable domain fields.

### Twelfth-Pass Verification

- `dart format lib/data/local_repositories.dart test/repository_test.dart` applied; one file changed.
- `flutter analyze` completed with no issues.
- `flutter test` completed successfully with all ten tests passing.

## 2026-05-18 — Thirteenth Review Pass

### Session Restart

Started a thirteenth engineering review pass. Full re-read of all source files confirmed the codebase is in the correct state from the prior session. Standard quality gates verified: `flutter analyze` found no issues, and all ten tests pass (6 domain copy-with, 3 repository, 1 widget).

### Issues Found

#### Bug: `fts5PrefixQuery` incorrectly double-escapes single quotes

- **File:** `lib/data/local_repositories.dart`, function `fts5PrefixQuery`.
- **Root cause:** The `escapeToken` closure applies two substitutions to the raw token: `"` → `""` and `'` → `''`. The first is correct — inside an FTS5 double-quoted phrase, a literal `"` must be written as `""`. However, `'` → `''` is a SQL string-literal escape sequence, not an FTS5 escape sequence. Inside an FTS5 double-quoted phrase (i.e., between `"` and `"*`), there is no valid escape for single quotes — apostrophes are treated as ordinary characters by the FTS5 tokenizer. Doubling them produces `''` inside the phrase, which FTS5 tries to match as the literal string `''` rather than as a single apostrophe. This causes any search containing an apostrophe (e.g., `"it's"`, `"don't"`) to fail to find notes that contain those terms.
- **Fix:** Remove the `s.replaceAll("'", "''")` line from `escapeToken`. The FTS5 query string is passed as a bound parameter (`Variable.withString`), so no SQL-level escaping is needed at all. Only the FTS5 phrase quoting (surrounding with `"..."*` and doubling internal double-quotes) is required.

#### Issue: `_bindNoteStream` creates a new stream on every keystroke when mode is unchanged

- **File:** `lib/app.dart`, `_NotesTabState._bindNoteStream`.
- **Root cause:** Every call to `_bindNoteStream()` — triggered on every character typed or deleted — unconditionally reassigns `_noteStream` by calling either `watchNotes()` or `watchSearchResults()`. When the user is typing in the search field and the query is non-empty, each keystroke creates a new Drift `customSelect().watch()` stream. The `StreamBuilder` detects a new stream reference and resets to `ConnectionState.waiting`, briefly flashing a loading spinner before the first event arrives. The same unnecessary stream recreation happens when clearing the field one character at a time: `watchNotes()` is called repeatedly instead of once when the query first becomes empty.
- **Fix:** Track the current search mode (`_isSearching`) and only rebind when the mode transitions between empty and non-empty, or when the query string changes while in search mode. This ensures each distinct query gets exactly one stream, and the browse/search mode toggle only creates new streams at the boundary.

#### Dead code: `openLazyDatabaseFile` is unused

- **File:** `lib/database/app_database.dart`, top-level function `openLazyDatabaseFile`.
- **Root cause:** The function was added as a test/tooling helper for file-backed database access, but the actual file-backed test (`FTS5 repair marker triggers rebuild on next open`) creates its executor directly with `NativeDatabase(File(dbPath))`. The function is not referenced anywhere in the codebase.
- **Fix:** Remove the function and its associated `dart:io` and `path` imports if they are no longer needed. (`dart:io` is still needed for the `File` type in the test, but `app_database.dart` no longer needs it directly.)

### Bug Fix: `fts5PrefixQuery` single-quote escaping

- Removed `s.replaceAll("'", "''")` from the `escapeToken` closure in `fts5PrefixQuery`. Single quotes are ordinary characters inside FTS5 double-quoted phrases and require no escaping. The `''` sequence is a SQL string-literal escape that is entirely inapplicable here because the FTS5 query is always passed as a bound `Variable.withString` parameter, not interpolated into raw SQL. The bug would cause any search query containing an apostrophe (e.g., `"don't"`, `"it's"`) to produce an FTS5 phrase that can never match any note.
- Simplified `fts5PrefixQuery` to a single-expression map chain, removing the intermediate `escapeToken` local-function closure.
- Removed an unnecessary `\"` escape in the string literal (`\"*` → `"*`) flagged by the `unnecessary_string_escapes` lint.

### Fix: `_bindNoteStream` unnecessary stream recreation on every keystroke

- Added `_activeQuery` state to `_NotesTabState` tracking the query string the current `_noteStream` was built for.
- `_bindNoteStream` now short-circuits when `q == _activeQuery`, preventing a new Drift watch stream from being created on every keystroke when the effective query string has not changed.
- As an additional correctness improvement, `watchSearchResults` now receives the trimmed query `q` rather than the raw `_search.text`, so leading/trailing whitespace in the search field cannot produce a different stream than the empty browse stream.
- Technical reasoning: the previous implementation caused `StreamBuilder` to reset to `ConnectionState.waiting` on every character typed or deleted, potentially flashing a loading spinner and discarding already-loaded results unnecessarily.

### Dead Code Removal: `openLazyDatabaseFile`

- Removed the `openLazyDatabaseFile` top-level function from `app_database.dart`. The function was never called; the file-backed FTS repair marker test creates its database directly with `NativeDatabase(File(dbPath))`.
- Removed the now-unused `import 'dart:io'` and `import 'package:path/path.dart' as p'` imports. Separately, removed the also-unused `import 'package:drift/native.dart'` that was uncovered by the analyzer after the function removal.

### Test Coverage: `fts_query_test.dart`

- Added `test/fts_query_test.dart` with 9 tests covering `fts5PrefixQuery` unit behaviour and an end-to-end FTS5 apostrophe-search scenario.
- Unit tests cover: empty string, whitespace-only string, single-word phrase wrapping, multi-word AND joining, internal-whitespace collapsing, double-quote escaping, apostrophe preservation (the fixed bug), and multi-word apostrophe queries.
- The end-to-end test inserts a note with `"Don't forget this"` as the title and `"It's important"` as the content, then verifies that `searchNotes("don't")` and `searchNotes("it's")` each return the note — directly proving the apostrophe bug is fixed.

### Thirteenth-Pass Verification

- `dart format` applied to all changed files; three files changed.
- `flutter analyze` reported two issues during the first pass (unnecessary string escape and unused import), both fixed before committing.
- `flutter analyze` on the second pass reported no issues.
- `flutter test` completed successfully with all 19 tests passing: 6 domain copy-with, 3 repository, 9 fts_query (8 unit + 1 end-to-end), and 1 widget.

## 2026-05-18 — Fourteenth Review Pass

### Session Restart

Started a fourteenth engineering review pass. All source files were re-read and the standard quality gates confirmed the codebase is clean: `flutter analyze` found no issues and all 19 tests pass.

### Issues Found

#### Bug: `pubspec.yaml` lists `path` as a production dependency

- **File:** `pubspec.yaml`, `dependencies` section.
- **Root cause:** `path: ^1.9.1` was listed under `dependencies` rather than `dev_dependencies`. The `path` package is only imported in `test/repository_test.dart` for constructing temporary SQLite file paths during the FTS repair marker regression test. No file under `lib/` imports `package:path`. Shipping `path` as a runtime dependency unnecessarily inflates the app's dependency graph.
- **Fix:** Move `path: ^1.9.1` from `dependencies` to `dev_dependencies`.

#### Issue: `_NotesTabState.build` reads `_search.text` for the empty-state message

- **File:** `lib/app.dart`, `_NotesTabState.build`.
- **Root cause:** The build method reads `final q = _search.text` and then evaluates `q.trim().isEmpty` to decide whether to show `'No notes yet'` or `'No matches'`. Since `_activeQuery` was introduced in the prior pass as the authoritative trimmed query string that controls which stream is active, reading `_search.text.trim()` during build is redundant. In cases where `_search.text` has leading/trailing spaces, `_search.text.trim()` and `_activeQuery` could produce different results, causing the UI message to disagree with the stream that is actually active.
- **Fix:** Replace `final q = _search.text` with a read of `_activeQuery` in the build method's empty-state decision. This ensures the displayed message always matches the stream that was started.

#### Optimization: `_installFts5` makes 8 sequential single-statement round-trips

- **File:** `lib/database/app_database.dart`, `_installFts5`.
- **Root cause:** The FTS5 installation path issues each DDL statement as an individual `customStatement` call. In SQLite, each call outside an explicit transaction is wrapped in its own implicit transaction, resulting in 8 separate write transactions and associated fsync overhead on real storage.
- **Fix:** Wrap the trigger DROP and CREATE statements (6 of the 8 calls) in an explicit `db.transaction(...)` block, reducing them to a single transaction commit. The `CREATE TABLE IF NOT EXISTS app_metadata` and `CREATE VIRTUAL TABLE IF NOT EXISTS fts_notes` calls are placed before the transaction since SQLite cannot DDL virtual tables inside a transaction on all platforms.
- **Expected gain:** On a real device's storage, startup DDL cost is reduced from up to 8 transaction commits to at most 3 (one for app_metadata, one for fts_notes, one for all trigger drops and recreations). The FTS rebuild statement, when it runs, remains outside the trigger transaction since it is already a virtual-table content operation.

### Fix: `path` moved to `dev_dependencies`

- Moved `path: ^1.9.1` from `dependencies` to `dev_dependencies` in `pubspec.yaml`. The `path` package is only imported in `test/repository_test.dart` for constructing temporary SQLite file paths; no production source file under `lib/` imports it. Placing it in `dependencies` meant it was shipped as a runtime dependency in app bundles unnecessarily.
- Ran `dart pub get` to apply the change; 1 dependency changed.

### Fix: `_NotesTabState.build` uses `_activeQuery` for empty-state message

- Replaced `final q = _search.text` and `q.trim().isEmpty` with `_activeQuery.isEmpty` in the `StreamBuilder` builder of `_NotesTabState.build`.
- `_activeQuery` is the authoritative trimmed query string that controls which stream is active. Reading `_search.text.trim()` during build was a redundant secondary read from the `TextEditingController` that could disagree with `_activeQuery` if the field had leading/trailing whitespace. The empty-state message now always matches the stream.

### Optimization: `_installFts5` trigger DDL wrapped in a single transaction

- Wrapped the 3 DROP and 3 CREATE trigger statements in `_installFts5` in a single `db.transaction(...)` call.
- Previous behaviour: each of the 6 DDL statements was committed as a separate implicit SQLite transaction (up to 6 fsync calls on WAL-mode storage).
- New behaviour: all 6 trigger DDL statements are committed atomically in one transaction (1 fsync for trigger setup). The `CREATE TABLE IF NOT EXISTS app_metadata` and `CREATE VIRTUAL TABLE IF NOT EXISTS fts_notes` calls remain outside the transaction because SQLite restricts virtual-table DDL in certain transaction contexts. The FTS5 rebuild statement, when it runs, also remains outside since it is a virtual-table content operation.
- Expected gain: on a cold device with real persistent storage, the FTS startup overhead is reduced from up to 8 transaction commits to at most 3.

### Fourteenth-Pass Verification

- `dart format lib/app.dart lib/database/app_database.dart` — no formatting changes required.
- `flutter analyze` — no issues found.
- `flutter test` — all 19 tests passed.
