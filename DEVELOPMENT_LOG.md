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

## 2026-05-18 — Empty-state parity & FTS splitter reuse

### Issue resolution

**5. Notes tab empty copy keyed off trimmed text rather than FTS activation**

- **Root cause:** When `fts5PrefixQuery` yielded no searchable tokens, the UI already fell back to `watchNotes()` (issue **#3**), but the placeholder string still tested `trimmedQuery.isEmpty`. Any non-empty trimmed field with an empty FTS predicate could still show **“No matches”** despite browsing the full list—contradicting the active stream semantics.
- **Fix:** Drive copy from the same FTS predicate computed in **`build`**: **`ftsQuery.isNotEmpty ? 'No matches' : 'No notes yet'`** (aligned with `_bindNoteStream`’s `ftsQuery.isEmpty` branch).
- **Files:** `flutter_local_first/lib/app.dart`

### Refactoring

**`flutter_local_first/lib/data/local_repositories.dart`**

- **`_ftsWhitespaceSplitter`**: `RegExp(r'\s+')` instantiated once module-wide for `fts5PrefixQuery`.
- Keeps tokenizer behavior identical while documenting intent next to FTS helpers.

### Optimization

- **Strategy:** Eliminate **`RegExp` construction on every **`fts5PrefixQuery` invocation** (search field **`onChanged`**, **`build`** recomputation). Saves compile work on hot keyboard paths without changing SQL semantics.
- **Benchmarks:** Not measured; expectation is negligible wall-time savings but deterministic less allocation churn.

### Current state

- **`flutter analyze`** clean; **`flutter test`** passes.

---

## 2026-05-18 — Session: widget/repo lifecycle, stream helper, FTS escape hoist

### Issue resolution

**6. Injected database or repository changes could leave stale repository instances**

- **Root cause:** `LocalFirstNotesApp` and `_NotesTab` constructed `NotesLocalRepository` / stream subscriptions only in `initState`. Replacing `database` or passing a new repository reference on rebuild (tests, benchmarks, or tooling) would keep listening through the old repos while the UI subtree updated—risking wrong data or leaked subscriptions tied to the wrong executor.
- **Fix:** `LocalFirstNotesApp.didUpdateWidget` rebuilds `_notes` and `_folders` when `widget.database` identity changes; `_NotesTab.didUpdateWidget` recomputes `_noteStream` when `widget.notes` identity changes. Repository fields were changed from `late final` to assignable `late` so rebinding is legal.
- **Files:** `flutter_local_first/lib/app.dart`

**Research note:** Instantiating multiple `AppDatabase` subclasses in one isolate triggers Drift’s debug warning about multiple databases; widget tests that swap DBs without closing the prior instance would add noise. Hot-swapping is documented here for harness authors; closing the previous database before opening another avoids the warning.

### Refactoring

- **`_notesStreamForSearchField`** (top-level in `app.dart`): centralizes trimmed query handling and **`fts5PrefixQuery`** non-empty check so **`initState`**, **`didUpdateWidget`**, **`onChanged`**, and future call sites share one definition of “browse all notes” vs “FTS stream.”
- **Reasoning:** Matches repository semantics (`watchSearchResults` only when FTS yields tokens) in a single place and reduces drift between stream wiring and empty-state copy (`ftsQuery` still computed in **`build`** for messaging only).

### Optimization

- **`_escapeFts5PrefixToken`** moved to module level in **`local_repositories.dart`** (replacing per-call nested **`escapeToken`**). Avoids allocating a new closure on every **`fts5PrefixQuery`** invocation on search **`onChanged`** / **`build`** paths; semantics unchanged.

### Current codebase state

- Flutter package **`local_first_notes`**: **`flutter analyze`** reports no issues; **`flutter test`** (repository + widget) passes.
- Root **`DEVELOPMENT_LOG.md`** records engineering decisions through this session.

---

## 2026-05-18 — Session: shared FTS tokenization and cheaper UI search gating

### Issue resolution

No new user-visible defects were identified in this pass; **`flutter analyze`** and **`flutter test`** were clean prior to changes. This session removes redundant MATCH-string work on UI-driven paths and locks tokenization to one implementation.

### Refactoring

**`flutter_local_first/lib/data/local_repositories.dart`**

- **`_ftsTokens`**: centralizes trim → split → filter pipeline used by both predicate checks and MATCH construction.
- **`fts5HasSearchableTokens`**: public API aligned with “non-empty **`fts5PrefixQuery`**” for stream selection and empty-state copy without building escaped tokens.
- **`fts5PrefixQuery`**: now delegates to **`_ftsTokens`** only.

**`flutter_local_first/lib/app.dart`**

- **`_notesStreamForSearchField`** and notes empty-state messaging use **`fts5HasSearchableTokens`** instead of **`fts5PrefixQuery(...).isNotEmpty`**.

**Reasoning:** One tokenizer eliminates drift between “is search active?” and SQL MATCH generation; call sites that only need a boolean no longer pay escape/`join` allocations.

### Optimization

- **Strategy:** Skip **`_escapeFts5PrefixToken`** and **`join`** on every **`build`** and stream-bind when only deciding **`watchNotes`** vs **`watchSearchResults`** (repository still builds the MATCH string internally when searching).
- **Benchmarks:** Not run; expected gain is lower allocation churn on keystrokes and frames, same SQL semantics.

### Tests

- **`repository_test.dart`:** asserts **`fts5HasSearchableTokens`** agrees with **`fts5PrefixQuery.isNotEmpty`** on representative inputs.

### Current codebase state

- **`flutter analyze`** clean; **`flutter test`** passes (4 tests).

---

## 2026-05-18 — Session: upgrade-time FTS parity, folders tab composition

### Issue resolution

**7. Migrated databases could ship without FTS5 while fresh installs had full-text search**

- **Root cause:** `MigrationStrategy.onUpgrade` only applied the v1→v2 column add (`folders.sortOrder`). `_installFts5` ran only from `onCreate`, so any existing file DB that reached the current schema solely through `onUpgrade` would never create `fts_notes` or the keep-in-sync triggers. Search would return no rows or behave inconsistently versus a new install.
- **Fix:** After version-specific migrator steps, invoke **`await _installFts5(this)`**. All DDL uses `IF NOT EXISTS`, so repeat calls on later upgrades are harmless.
- **Files:** `flutter_local_first/lib/database/app_database.dart`

### Refactoring

**`flutter_local_first/lib/app.dart`**

- **`_FoldersTab`**: `StatelessWidget` that owns the folders **`StreamBuilder`**, list layout, and loading gate—parallel to **`_NotesTab`** owning notes UX.
- **Reasoning:** `LocalFirstNotesApp.build` stays focused on shell/navigation; tab bodies scale independently without an oversized scaffold method.

### Optimization

- **Strategy:** Centralized, idempotent FTS provisioning on upgrade removes the need for ad hoc repair migrations or duplicate bootstrap logic elsewhere.
- **Benchmarks:** Not measured; cost is negligible DDL guarded by `IF NOT EXISTS` at upgrade time.

### Verification

- **`dart format`** on touched Dart files; **`flutter analyze`** — no issues; **`flutter test`** — 4 tests passing.

### Repository state after this session

- Authoritative app package: **`flutter_local_first/`** (`local_first_notes`). Root log documents engineering decisions through **issue #7** and widget/migration refactors above.

---

## 2026-05-18 — Session: codebase audit, repository clarity, regression coverage

### Actions completed

1. Ran **`flutter pub get`**, **`flutter analyze`**, and **`flutter test`** at `flutter_local_first/` — baseline clean (no analyzer issues; 4 passing tests prior to edits).
2. Read through **`app.dart`**, **`local_repositories.dart`**, **`app_database.dart`**, **`bootstrap.dart`**, and test suites for reactive wiring, FTS5 contracts, migrations, and widget teardown hygiene.
3. Applied a small readability tweak and expanded repository tests (see below).
4. Re-ran **`flutter test`** / **`flutter analyze`** after edits — still clean; same number of **`test`** declarations (coverage extended inside the CRUD integration test).

### Issue resolution

No new functional defects surfaced in application code versus the narratives already documented for issues **#1–#7** above. FTS upgrade parity, UI stream selection against **`fts5HasSearchableTokens`**, **`didUpdateWidget` rebinding**, and widget-test **`db.close`** sequencing remain coherent on review.

### Refactoring / maintainability

**`flutter_local_first/lib/data/local_repositories.dart` — `NotesLocalRepository.getNoteById`**

- **Change:** Rename the **`NoteTags` query result** to **`tagRows`**, derive **`tags`** as a sorted list variable, then call **`_noteFromRow`**.
- **Reasoning:** Disambiguates Drift **`NoteTagRow`** rows from decoded tag strings (`tags` naming collision with domain “tags”). Behavior and **`List.unmodifiable`** wrapping via **`_noteFromRow`** are unchanged.

### Tests

**`flutter_local_first/test/repository_test.dart`**

- After **`searchNotes`** assertions, **`getNoteById`** is exercised: confirms round-trip **`id`**, **lexicographically sorted tags** aligned with **`_tagsByNoteId`**, and **`UnsupportedError`** if callers attempt to **`add`** on the exposed **`Note.tags`** list (guards the unmodifiable contract).

### Optimization

No additional hot paths identified; keystroke optimizations from prior sessions (shared **`_ftsTokens`**, hoisted **`_escapeFts5PrefixToken`**, **`fts5HasSearchableTokens`** gating) remain the relevant strategy.

### Current state

- Package **`local_first_notes`**: **`flutter analyze`** reports no issues; **`flutter test`** passes (repository + widget).
- **`DEVELOPMENT_LOG.md`**: consolidated session appended; root remains the engineering record for **agent-hamster-wheel**.

---

## 2026-05-18 — Session: folders stream lifecycle, folders repository coverage

### Actions completed

1. **`flutter pub get`**, **`flutter analyze`**, and **`flutter test`** on **`flutter_local_first/`** — clean baseline (working tree aligned with **`origin/result-flutter-composer-2-0`** before edits below).
2. Reviewed **`app.dart`** tab widgets against **`StreamBuilder`** / Drift **`watch`** usage parity with **`_NotesTab`**.
3. Converted **`_FoldersTab`** to **`StatefulWidget`**, cached **`watchFolders()`** in state, **`didUpdateWidget`** when **`folders`** repository identity changes (mirrors **`_NotesTab` / `_NotesTabState`** injection pattern).
4. Added **`FoldersLocalRepository`** integration test (**name sort order**, empty-first emission contract).
5. **`dart format`**, **`flutter analyze`**, **`flutter test`** — 5 **`test`** cases passing (prior session had **4** at the counters; one new **`test`** block added).

### Issue resolution — **8. Folder list stream reconstructed on every rebuild**

- **Symptom / risk:** **`_FoldersTab`** (previously **`StatelessWidget`**) passed **`folders.watchFolders()`** directly into **`StreamBuilder`** from **`build`**. Parent rebuilds (tab controller, theme, etc.) yielded a fresh **`Stream` instance** whenever Drift rebuilds that pipeline. **`StreamBuilder`** treats a changed **`stream` argument as a new subscription**, so listeners could churn every frame subtree rebuild—wasted work and a risk of UI flicker or missed emissions during rapid teardown/resubscribe.
- **Fix:** Preserve a single **`late Stream<List<Folder>> _folderStream`**, initialized in **`initState`**, swapped in **`didUpdateWidget`** when **`widget.folders`** is not **`identical`** to the old widget’s repository (same contract as notes when **`AppDatabase`** is hot-swapped in tests).
- **File:** **`flutter_local_first/lib/app.dart`**

### Refactoring / architecture

- **`_FoldersTab` / `_FoldersTabState`** now mirror **`_NotesTab`**: ephemeral **`build`** avoids owning long-lived async resources; **`State`** holds the **`watch`** subscription target.
- **Reasoning:** One stable stream identity per logical subscription keeps reactive SQL invalidation deterministic and aligns both tabs under the same maintenance story.

### Tests

- **`flutter_local_first/test/repository_test.dart`:** **`Folders repository streams rows ordered by name`** — inserts **`Beta`** then **`Alpha`**, asserts first snapshot after writes is **`['Alpha','Beta']`**, validating **`orderBy([(t) => OrderingTerm.asc(t.name)])`** and **`watch`** wiring without the UI layer.

### Optimization

- **Strategy:** Stable **`watchFolders()`** reference eliminates redundant **`StreamBuilder` cancel/resubscribe** cycles on benign rebuilds; Drift retains one listener until the repo or subtree intentionally changes.
- **Benchmarks:** Not run; expectation is fewer native query listener churn events when **`MaterialApp` / scaffold** subtree rebuilds.

### Current state

- **`flutter analyze`** reports no issues; **`flutter test`** passes (repository + widget).
- Engineering record updated through **issue #8**.

---

## 2026-05-18 — Session: verification, FTS hydration DRY mapping

### Actions completed

1. Ran **`flutter pub get`**, **`flutter analyze`**, and **`flutter test`** under **`flutter_local_first/`** — baseline clean before edits (no analyzer findings; 5 tests passing).
2. Reviewed **`app.dart`** (tab streams, FTS gating), **`local_repositories.dart`** (combineLatest, FTS watch/read paths), **`app_database.dart`** (migrations + FTS install), **`bootstrap.dart`**, and tests for parity with prior issue narratives (**#1–#8**).
3. Refactored FTS result hydration to reuse the same domain mapper as table-backed reads (see below).
4. Re-ran **`flutter analyze`** / **`flutter test`** after the change — still clean.

### Issue resolution

No new runtime or analyzer defects were observed relative to the fixes already documented above. This pass did not alter user-visible behavior.

### Refactoring

**`flutter_local_first/lib/data/local_repositories.dart` — `_hydrateNotesFromFtsRows`**

- **Change:** Build a Drift **`NoteRow`** from each **`QueryRow`** and return **`_noteFromRow(row, tags)`** instead of constructing **`Note`** inline with duplicated field reads.
- **Reasoning:** **`_noteFromRow`** is the single place that defines **`List.unmodifiable`** tags and maps persistence columns to **`Note`**; FTS search and **`watchNotes`** could otherwise drift (e.g., future columns or tag semantics) if only one path were updated.

### Optimization

- **Trade-off:** Each FTS hit allocates a short-lived **`NoteRow`** where the previous code inlined **`Note`** construction — negligible versus SQLite and hydration I/O; the win is **lower long-term defect rate** from one mapping path, not raw throughput.
- **Benchmarks:** Not run; expectations unchanged for interactive search.

### Current state

- Package **`local_first_notes`**: **`flutter analyze`** reports no issues; **`flutter test`** passes (repository + widget).
- **`DEVELOPMENT_LOG.md`**: session appended; prior issues **#1–#8** remain the canonical bug history.

---

## 2026-05-18 — Session: folders empty state, searchNotes dependency parity

### Actions completed

1. Ran **`flutter pub get`**, **`flutter analyze`**, and **`flutter test`** on **`flutter_local_first/`** — clean baseline (5 tests passing) before edits.
2. Compared **`_FoldersTab`** and **`_NotesTab`** empty UX: folders used a zero-item **`ListView`** with no copy when the DB had no rows.
3. Implemented empty-folder messaging, aligned **`searchNotes`** `readsFrom` with hydration, extended the widget test, and re-ran **`flutter analyze`** / **`flutter test`** — all green.

### Issue resolution — **9. Folders tab showed a blank list for an empty database**

- **Root cause:** After the loading spinner, **`StreamBuilder`** always built **`ListView.builder`** with **`itemCount: 0`**, so users saw an empty scroll surface with no explanation, unlike the notes tab’s **“No notes yet”** affordance.
- **Fix:** When the first resolved list is empty, show **`Center(Text('No folders yet'))`** (same pattern as notes: loading gate first, then empty vs populated).
- **Files:** **`flutter_local_first/lib/app.dart`**

### Refactoring / API accuracy

**`flutter_local_first/lib/data/local_repositories.dart` — `NotesLocalRepository.searchNotes`**

- **Change:** `customSelect` **`readsFrom`** now includes **`_db.noteTags`** in addition to **`_db.notes`**, matching **`watchSearchResults`** and the fact that **`_hydrateNotesFromFtsRows`** always loads tags.
- **Reasoning:** Declares the full table dependency set for Drift’s query metadata and keeps one-shot search consistent with streamed search for future analyzer/runtime features that interpret `readsFrom`.

### Optimization

- No throughput-oriented change; empty-state branch is **`O(1)`** UI work on top of the same stream emissions.
- **Benchmarks:** Not run.

### Tests

- **`flutter_local_first/test/widget_test.dart`:** renamed scenario to **`LocalFirstNotesApp shows empty state on notes and folders tabs`**; after the notes assertion, taps **`Folders`** and expects **`No folders yet`**. Uses **`package:flutter/material.dart`** so tab taps resolve against **`TabBar`** / **`Material`** semantics from the harness.

### Current state

- **`flutter analyze`**: no issues; **`flutter test`**: 5 tests passing.
- Engineering record updated through **issue #9**.

---

_This log is the running record for **agent-hamster-wheel**; append new dated sections per session._
