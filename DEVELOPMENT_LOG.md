# Development Log

Professional record of engineering evolution and research findings for **agent-hamster-wheel**.

---

## 2026-05-18 — Code review, remediation, instrumentation

### Scope

The active application code lives under `flutter_local_first/` (package `local_first_notes`): Flutter UI over Drift + SQLite with FTS5 for note search.

### Diagnostics

- **`dart analyze`** at the package root resolves packages inconsistently unless `flutter pub get` has populated the Flutter SDK toolchain; **`flutter analyze`** is the authoritative static check for this project.
- After `flutter pub get`, **`flutter analyze` reports no issues**, and **`flutter test` passes.**

### Bugs found and fixes

**1. Search stream binding inconsistent with trimmed query logic**

- **Symptom:** `_NotesTab._bindNoteStream` branched on `q = _search.text.trim()` but called `watchSearchResults(_search.text)`, so the reactive stream occasionally saw a different string than the selection logic implied (mostly redundant with `fts5PrefixQuery`’s internal `trim()`, but misleading and fragile).
- **Fix:** Pass `watchSearchResults(q)` so branching and FTS input share exactly one normalized notion of the user query.
- **File:** `flutter_local_first/lib/app.dart`

**2. Widget smoke test teardown left Drift timers pending**

- **Root cause:** `CustomSelect`/Drift reactive streams cancel with scheduled timers (`StreamQueryStore`); disposing the widget tree before those timers flush triggers Flutter’s `!timersPending` invariant in widget tests.
- **Fix:** Unmount UI (`SizedBox.shrink()`), **`pump` forward time** (`Duration(seconds: 1)` under test binding fake async), **`await db.close()`**, pump again — drains cancel timers cleanly.
- **File:** `flutter_local_first/test/widget_test.dart`

### Refactoring and architecture notes

**`flutter_local_first/lib/data/local_repositories.dart`**

- Introduced **`_ftsNotesMatchSql`** so the FTS5 projection (`SELECT … JOIN fts_notes … ORDER BY bm25`) is defined once.
- Factored **`_hydrateNotesFromFtsRows`** using Drift **`QueryRow`** so `searchNotes` and `watchSearchResults` share the same tag-fetch and domain mapping logic.
- **Reasoning:** DRY eliminates drift risk (SQL divergence between sync and streamed search) and concentrates column-name/read semantics in one place.

### Optimization

- No algorithmic hotspots were identified suitable for measurable micro-optimization in this codebase size; the main gains are **reduced duplication** (smaller executable surface area for FTS mapping) and **clearer reactive invalidation coupling** (`readsFrom` unchanged for watch).
- **Expected performance:** Runtime behavior is equivalent to prior single-query-per-search patterns; benchmarks were not warranted for refactor-only consolidation.

### Test improvements

- Replaced placeholder widget test with **`LocalFirstNotesApp` + `NativeDatabase.memory()`** asserting the shipped empty-notes UI—validates migrations/FTS install path and routing without manual `bootstrap()`.

### Current codebase state

- Flutter package `local_first_notes` builds clean under `flutter analyze`.
- FTS5 repository tests and updated widget test pass locally with `flutter test`.
- Repository root retains prompts and scaffolding; authoritative app source is **`flutter_local_first/`**.

---

_End of session entry._
