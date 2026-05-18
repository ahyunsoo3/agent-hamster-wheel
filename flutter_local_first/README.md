# local_first_notes

A Flutter reference app demonstrating a local-first architecture using
[Drift](https://drift.simonbinder.eu/) (SQLite) with SQLite FTS5 for
full-text search, a reactive repository layer, and a clean domain model.

## Architecture

```
lib/
  main.dart                  Entry point — delegates to bootstrap()
  bootstrap.dart             Wires AppDatabase → LocalFirstNotesApp
  app.dart                   Root widget; owns database lifecycle via dispose()
  database/
    tables.dart              Drift table definitions (Folders, Notes, NoteTags)
    app_database.dart        Database class, migration strategy, FTS5 installer
    app_database.g.dart      Generated Drift code (do not edit)
  data/
    local_repositories.dart  NotesLocalRepository + FoldersLocalRepository
  domain/
    note.dart                Note value object with sentinel-based copyWith
    folder.dart              Folder value object with sentinel-based copyWith

test/
  domain_copy_with_test.dart  copyWith preserve/clear/replace semantics
  repository_test.dart        CRUD, FTS index maintenance, repair marker
  widget_test.dart            App shell smoke test with in-memory database
```

## Key Design Decisions

### FTS5 External-Content Index

Notes are indexed in a `fts_notes` virtual table (FTS5 external-content,
backed by `notes`). Three triggers — `notes_ai`, `notes_ad`, `notes_au` —
keep the index in sync on insert, delete, and update. Triggers are dropped
and recreated on every database open so stale definitions can never persist
across schema iterations.

### One-Time Repair Marker

A full FTS5 `rebuild` is O(number of notes) and only runs when:

1. Drift reports the database was newly created (`wasCreated`), or
2. Drift reports a schema migration occurred (`hadUpgrade`), or
3. The `fts_rebuild_v1` key is absent from the `app_metadata` table.

After a successful rebuild the marker is written, so subsequent cold starts
skip the rebuild and only pay the cost of the idempotent trigger-recreation
statements.

### Reactive Streams

`watchNotes()` and `watchSearchResults()` both return `Stream<List<Note>>`.
The notes stream uses `rxdart.combineLatest2` to join notes and tags tables
reactively. The search stream uses Drift's `customSelect().watch()` plus
`asyncMap` to hydrate tags on each emission.

### Domain copyWith Semantics

`Note.copyWith` and `Folder.copyWith` use a private `_unset` sentinel so
callers can distinguish three states for nullable fields:

- **Omit** the parameter → keep the existing value.
- **Pass `null`** → explicitly clear the field (e.g. move note out of folder).
- **Pass a value** → replace with the new value.

## Verification

```bash
# Static analysis
flutter analyze

# Full test suite
flutter test

# Code generation (after changing table definitions)
dart run build_runner build --delete-conflicting-outputs
```
