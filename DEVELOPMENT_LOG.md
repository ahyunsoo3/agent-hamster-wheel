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

## 2026-05-18 — Follow-up: FTS gate parity, folders loading, tests

### Issue resolution

**3. Notes tab stream source diverged from repository “searchable query” contract**

- **Root cause:** `_bindNoteStream` chose `watchSearchResults` whenever the trimmed text field was non-empty, even when `fts5PrefixQuery` produced an empty MATCH string (whitespace-only / no durable tokens). The repository already treats an empty FTS string as “no search” (`searchNotes` returns `[]`; `watchSearchResults` returns a constant empty stream). The UI then showed “No matches” while the data layer never fell back to the full note list.
- **Fix:** Branch on **`fts5PrefixQuery(_search.text.trim()).isEmpty`** (same effective predicate as the repository) and only then subscribe to **`watchNotes()`**; otherwise **`watchSearchResults`** receives the trimmed query. Empty-state copy now keys off **`trimmedQuery`** for alignment with that stream choice.
- **Files:** `flutter_local_first/lib/app.dart`

**4. Folders tab showed an empty list during initial stream wait**

- **Root cause:** `StreamBuilder` rendered `snap.data ?? []` before the first Drift emission, so users briefly saw an empty list instead of a loading affordance.
- **Fix:** Mirror the notes tab pattern—show a centered **`CircularProgressIndicator`** while **`waiting && !hasData`**.
- **Files:** `flutter_local_first/lib/app.dart`

### Refactoring

- **`flutter_local_first/test/widget_test.dart`:** depend on **`package:flutter/widgets.dart`** instead of Material so the test only pulls in **`SizedBox`** (small compile surface; material components come from the app under test).

### Optimization

- **Strategy:** Subscribing to **`watchNotes()`** when FTS tokenization is empty avoids an extra reactive query whose contract is a permanent empty list, keeping stream topology aligned with user intent (browse all notes).
- **Benchmarks:** Not run; expected gain is minor (one fewer specialized stream in that edge case) but behavior is strictly more correct.

### Tests

- Added **`fts5PrefixQuery` whitespace contract** test in `flutter_local_first/test/repository_test.dart` to lock the UI/repository alignment assumption.

### Current state

- **`flutter analyze`** clean; **`flutter test`** passes (repository + widget suite).

---

_End of session entries._
