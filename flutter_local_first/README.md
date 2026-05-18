# Local-First Notes

Flutter reference app for a local-first notes data layer backed by Drift,
SQLite, and FTS5.

## Architecture

- `lib/database/` defines Drift tables, migrations, and SQLite FTS5 setup.
- `lib/data/local_repositories.dart` exposes repository APIs for notes, folders,
  tags, full-text search, and reactive lists.
- `lib/domain/` contains persistence-independent `Note` and `Folder` models.
- `lib/app.dart` wires the repositories into a small Material shell for manual
  testing and benchmark smoke checks.

## Search Index Maintenance

Notes are indexed through an external-content FTS5 table. Database open performs
cheap, idempotent repair of the virtual table and triggers. A full FTS rebuild
runs only for fresh databases, schema upgrades, or databases missing the
`fts_rebuild_v1` metadata marker.

This keeps normal startup bounded while still repairing older or stale search
indexes.

## Verification

Run the standard checks from this directory:

```sh
flutter analyze
flutter test
```
