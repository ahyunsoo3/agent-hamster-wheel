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
