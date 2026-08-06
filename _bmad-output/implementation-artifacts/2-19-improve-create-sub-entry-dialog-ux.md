---
baseline_commit: a102a4f792d9a8deb4390e83f7eb7230b0b3d587
---

# Story 2.19: Improve the create-sub-entry dialog UX

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the create-sub-entry dialog to offer existing groups as selectable options and allow creating at the entity root,
so that I can quickly add content without remembering exact folder names.

## Context

Story 2.11 built the create-sub-entry dialog (`apps/mobile/lib/app/entity_detail_page.dart`): a `TextField`-based `Group`/`Title` dialog behind the FAB on `EntityDetailPage`. Today an empty group is treated as an **error** ("Names produce invalid filenames") — the author is forced to type a group name even when they just want a loose sub-entry sitting directly in the entity folder. And the group field offers no memory of groups the entity already has — the author must recall exact existing folder names (`events`, not `Event`/`events `) or risk silently creating a near-duplicate section.

This is a pure UX refinement of Story 2.11's dialog. **The underlying create pipeline is unchanged**: slugify → (ensureDir) → clobber guard → `writeAtomic` → push `EditorPage` → rescan. Two changes only:
1. An empty group field now means "create at the entity root" instead of erroring.
2. The dialog shows the entity's existing top-level group names as tappable suggestions that fill the field.

**This story changes the meaning of one existing Story 2.11 test.** `create_sub_entry_test.dart`'s `'empty group → error, no write'` test currently asserts that a blank/whitespace-only group is rejected — that is exactly the behavior AC1 replaces. Update that test to assert the new root-creation behavior (see Task 3) rather than treating it as a regression to preserve.

## Acceptance Criteria

1. **(AC1 — optional group, root creation)** Given the create-sub-entry dialog, when I leave the group field empty (or whitespace-only — `_slugify` already trims, so both slugify to `''`) and enter a title, then the sub-entry is created directly in the entity folder root (`<entity-folder>/<slug>.ru.md`), `ensureDir` is **not** called, and the clobber guard checks the entity root (`<entity-folder>/<slug>.{md,ru.md,en.md}`) instead of a group subfolder. *(FR25)*
2. **(AC2 — existing-group suggestions)** Given the entity has existing top-level groups (`entry.tree.children`, e.g. `events`, `quests`), when I open the create-sub-entry dialog, then those group names render as tappable suggestion chips above the group field. Tapping one fills the group field with that name — it does **not** submit the dialog. If the entity has no children yet, no chips render (empty tree → empty suggestion row, not an empty/broken layout). *(FR25 UX)*
3. **(AC3 — new group still works, unchanged)** Given I type a group name that doesn't match any existing chip, when I confirm, then the behavior is Story 2.11's unchanged path: `ensureDir` creates the folder, the file is written inside it. Typing after tapping a chip (to override the filled value) also works — the chip only pre-fills, it never locks the field. *(FR25)*
4. **(AC4 — AD-8/NFR7, no new error surface)** All of Story 2.11's existing error handling is unchanged: empty **title** still errors ("Names produce invalid filenames"), `media` as a group name is still rejected as reserved (root case: N/A, since root has no group name to reserve — the reserved check only applies when the group is non-empty), a clobber still errors ("A sub-entry with this name already exists."), and a write failure still errors ("Failed to create the sub-entry.") without stranding the screen. *(AD-8)*
5. **(AC5 — no regression)** All other existing create-sub-entry and create-entity tests stay green (only the one test named in Context is intentionally rewritten, not broken). `flutter analyze` clean. *(NFR)*

**Non-goals:** nested/multi-level group suggestions (only `entry.tree.children` — the entity's immediate sections — are suggested; the group field has only ever held a single path segment, `groupFolder = '$entityFolder/$groupSlug'`, so a nested suggestion like `quests/relationship-quest-1` would not fit the existing single-segment model and is out of scope). No changes to `RepoStorage`, the loader, or the model — this is `entity_detail_page.dart`-only.

## Tasks / Subtasks

- [x] **Task 1: Pass existing group names into the dialog** (AC: 2)
  - [x] 1.1 In `_createSubEntry` (`entity_detail_page.dart`), compute `final existingGroups = _entry?.tree?.children.map((n) => n.name).toList() ?? const <String>[];` before calling the dialog (top-level sections only — see Non-goals). Pass it to `_showCreateSubEntryDialog(context, existingGroups)`.
  - [x] 1.2 Update `_showCreateSubEntryDialog`'s signature to `Future<_SubEntryResult?> _showCreateSubEntryDialog(BuildContext context, List<String> existingGroups)`.

- [x] **Task 2: Render group suggestions as tappable chips** (AC: 2, 3)
  - [x] 2.1 Above the existing `sub-entry-group-field` `TextField`, when `existingGroups.isNotEmpty`, render a `Wrap(spacing: 8, runSpacing: 4, children: [for (final g in existingGroups) ActionChip(key: Key('sub-entry-group-chip-$g'), label: Text(g), onPressed: () => groupController.text = g)])`. `groupController.text = g` is sufficient to update the `TextField` — no `setState`/`StatefulBuilder` needed (the field already listens to its controller). When `existingGroups` is empty, render nothing extra (skip the `Wrap`, not an empty one) — keep the dialog's existing plain-`TextField`-first layout for entities with no sections yet.
  - [x] 2.2 Update the group field's `hintText` to make the "empty = root" affordance discoverable, e.g. `'e.g. events — leave empty for entity root'`.

- [x] **Task 3: Make an empty group mean "entity root", not an error** (AC: 1, 3, 4)
  - [x] 3.1 In `_createSubEntry`: remove `groupSlug.isEmpty` from the "Names produce invalid filenames" check — only `entrySlug.isEmpty` should trigger it now (a title is still always required; a group is not).
  - [x] 3.2 Compute `final targetFolder = groupSlug.isEmpty ? entityFolder : '$entityFolder/$groupSlug';` (replacing the current unconditional `groupFolder`) and build `filePath` from `targetFolder` instead of `groupFolder`.
  - [x] 3.3 Only call `await widget.storage.ensureDir(_repoPath(targetFolder));` when `groupSlug.isNotEmpty` (AC1: "`ensureDir` is not called" for the root case — the entity folder itself already exists, nothing to create).
  - [x] 3.4 The clobber guard's three `exists` checks (`.ru.md`, `.md`, `.en.md`) already use the folder variable being renamed — no logic change needed there beyond the rename from `groupFolder` to `targetFolder`, since it naturally now checks the entity root when `targetFolder == entityFolder`.
  - [x] 3.5 The `groupSlug == 'media'` reserved-name check stays exactly as-is: it's already a no-op when `groupSlug` is `''` (root case can never equal `'media'`), so no guard change is needed — verify this with a test (Task 4) rather than adding a redundant `if (groupSlug.isNotEmpty && ...)` wrapper.

- [x] **Task 4: Update and add tests** (AC: 1–5)
  - [x] 4.1 In `apps/mobile/test/app/create_sub_entry_test.dart`, replace `'empty group → error, no write'` with a test asserting the new AC1 behavior: leave the group field blank, enter a title, confirm — expect `storage.ensureDirCalls` **empty**, `storage.writeCalls` = `[('characters/selena/<slug>.ru.md', '# <Title>\n')]` (entity root, not `characters/selena/events/...`), and navigation to `EditorPage` succeeds (no error snackbar). Also add the whitespace-only case (`'   '`) asserting identical root-creation behavior (not the old error), since AC1 explicitly covers both.
  - [x] 4.2 Add a clobber-at-root test: seed `FakeRepoStorage` with a file already at `characters/selena/<slug>.ru.md` (or `.md`/`.en.md`), leave group blank, confirm — expect the existing `'A sub-entry with this name already exists.'` snackbar and no write.
  - [x] 4.3 Add a suggestion-chip test using `_folderEntry()` (already has an `events` child in its tree): open the dialog, assert a chip labeled `events` is present (`find.byKey(const Key('sub-entry-group-chip-events'))` or `find.text('events')` scoped to the chip), tap it, then assert the group `TextField`'s displayed text is `'events'` (`find.widgetWithText(TextField, 'events')` or read `groupController` indirectly via the field's rendered text). Confirm the dialog still creates in `characters/selena/events/...` after the tap (proves the chip actually drives the same field the submit path reads).
  - [x] 4.4 Add a no-suggestions test: build a `LoreEntry` whose `tree.children` is empty (entity folder with no sections yet) and assert no `ActionChip` is present, and the dialog still opens/functions normally.
  - [x] 4.5 Regression check: run the full `create_sub_entry_test.dart` file plus the full suite — every other existing test (new-group creation, existing-group creation, empty-title error, hyphen-only-slug error, media-reserved error, duplicate-exists error, write-failure error, cancel) must still pass unchanged, since Task 3 only touches the group-empty branch.
  - [x] 4.6 `flutter analyze` clean; record before/after `flutter test` counts in Dev Agent Record.

### Review Findings

- [x] [Review][Patch] A suggestion chip can write to a different folder than the one it names, and an existing group whose name doesn't survive `_slugify` (non-Latin script, e.g. Cyrillic; mixed case; spaces) silently routes to the entity root instead — violates AC2's stated purpose ("prevent silently creating a near-duplicate section"). `LoreNode.name` is the raw on-disk folder name, but the submit path always re-slugified it (`_slugify(result.group)`), so a chip labelled `Events` writes to `events` (a new, near-duplicate folder) and a chip labelled `События` slugifies to `''` and silently creates at the root with no warning. Confirmed independently by all three review layers, including live probes. [entity_detail_page.dart:148] [lore_loader.dart:429] — **Fixed**: match the (trimmed) group text against `existingGroups` first; an exact match uses that raw folder name directly, bypassing `_slugify` entirely, so a chip (or typing an existing group's exact name) always writes to the folder it actually names. Added a dedicated regression test with a `Side Quests` group.
- [x] [Review][Patch] Typed group text that isn't blank but slugifies to nothing (e.g. `!!!`, `---`) now silently falls back to entity-root creation instead of erroring — exceeds AC1's stated scope (AC1 covers a field "left empty," not mistyped input). Same root cause as the finding above. [entity_detail_page.dart:148-160] — **Fixed**: as part of the same change, the "invalid filenames" error now fires whenever the trimmed group text is non-empty but produces no usable slug and doesn't match an existing group — only a genuinely blank/whitespace-only field means root. Added a dedicated regression test.
- [x] [Review][Patch] The dialog's `AlertDialog` has no `scrollable: true`; the new unbounded chip `Wrap` can overflow the fixed-height content area, especially with the soft keyboard raised (the group field is `autofocus: true`) — can clip the Title field or the Create button out of view. Confirmed materially worse after this story's change via layout measurement. [entity_detail_page.dart:411] — **Fixed**: added `scrollable: true` to the `AlertDialog`.
- [x] [Review][Patch] A chip tap sets `groupController.text = g` directly, which leaves the field's text selection at an undefined/collapsed(-1) cursor position per Flutter's own documented guidance for this exact pattern — the group field is focused (`autofocus: true`) when a chip is tapped. [entity_detail_page.dart:425] — **Fixed**: chip tap now sets `groupController.value = TextEditingValue(text: g, selection: TextSelection.collapsed(offset: g.length))`.
- [x] [Review][Patch] The "leave empty for entity root" explanation — the sole discoverability mechanism for AC1's headline behavior — was placed in `hintText`, which does not wrap in `InputDecoration` and would be clipped in the dialog. [entity_detail_page.dart:437] — **Fixed**: moved to `helperText` (which wraps), `hintText` shortened back to `'e.g. events'`.
- [x] [Review][Patch] Task 4.2's root-clobber test covered only `.ru.md`, not the `.md`/`.en.md` branches of the same clobber guard — both newly reachable at the entity root by this story. [create_sub_entry_test.dart] — **Fixed**: parameterized the root-clobber test over all three suffixes.
- [x] [Review][Patch] The chip-selection test asserted `find.widgetWithText(TextField, 'events')` (unscoped — passes if *any* `TextField` anywhere contains that text) instead of scoping to `Key('sub-entry-group-field')`, and never asserted that tapping a chip alone does not submit the dialog (AC2). [create_sub_entry_test.dart] — **Fixed**: scoped the assertion to `find.descendant(of: find.byKey(...), matching: ...)` and added `expect(storage.writeCalls, isEmpty)` immediately after the chip tap.
- [x] [Review][Defer] Creating a sub-entry at the entity root titled exactly the entity's own folder name, or titled "index", gets absorbed by the loader (`_buildNode`, `base == dirName || base == 'index'`) as the entity's overview card instead of appearing as a listed item — or, when the title matches the entity's own card name exactly, is silently skipped from the model entirely (`continue`, matching neither overview nor `flat` children). [lore_loader.dart:382] [entity_detail_page.dart:173] — deferred: verified this is a pre-existing hazard in `_createSubEntry`'s design, already reachable at every existing group-subfolder level since Story 2.11 (a sub-entry named after its own group folder has always been absorbed the same way) — this story only makes it reachable at one more location (the entity root). A narrow root-only fix would be an inconsistent half-fix; a proper fix needs to touch the general "reserved name" hazard across every creation path, which is out of this UX-polish story's scope.
- [x] [Review][Defer] The clobber guard only checks file-suffix collisions (`.ru.md`/`.md`/`.en.md`), never directory-name collisions — a root-level sub-entry can be created with the same name as an existing section folder (e.g. title "Events" while a group named "events" already exists), producing an item and a section header with the same displayed name. [entity_detail_page.dart:183-185] — deferred: same reasoning as above — this is a pre-existing gap in the clobber guard's design (already reachable for a sub-entry vs. a *nested* subfolder within an existing group), not newly invented by this story; a proper fix belongs with the reserved-name fix above, not a root-only patch.
- [x] [Review][Defer] The two `TextEditingController`s in `_showCreateSubEntryDialog` are never disposed. [entity_detail_page.dart:407-408] — deferred, pre-existing since Story 2.11; this story edited the function but not this aspect of it.
- [x] [Review][Defer] `FakeRepoStorage.writeAtomic` doesn't register the newly-written file into its parent's `dirEntries` listing (unlike `movePath`, which does via `_addSibling`), so a post-create rescan in a test can never observe the created file — this is the ceiling on what any test in this suite (old or new) can verify about the loader-level consequences of a create. [test/fakes.dart] — deferred, pre-existing test-double limitation, not part of this story's diff.
- [x] [Review][Defer] The chip row has no `Semantics`/label explaining its relationship to the group field for screen-reader users. [entity_detail_page.dart:417-428] — deferred, consistent with Story 2.13's precedent (no established a11y-labeling pattern exists elsewhere in the app to hold this story to a higher bar; revisit if accessibility becomes a tracked requirement).

## Dev Notes

### What changes, precisely

Everything lives in `apps/mobile/lib/app/entity_detail_page.dart`, in and around `_createSubEntry` (currently lines 140–208) and `_showCreateSubEntryDialog` (currently lines 379–428). No other file needs a production-code change — this story does not touch `storage/`, `lore/`, or any other `app/` page.

Current logic (Story 2.11, to be replaced per Task 3):
```dart
final groupSlug = _slugify(result.group);
final entrySlug = _slugify(result.title);
if (groupSlug.isEmpty || entrySlug.isEmpty) { ... error ...; return; }
...
final groupFolder = '$entityFolder/$groupSlug';
final filePath = '$groupFolder/$entrySlug.ru.md';
...
await widget.storage.ensureDir(_repoPath(groupFolder));
if (await widget.storage.exists(_repoPath(filePath)) || ...) { ... }
```

Target logic (Story 2.19):
```dart
final groupSlug = _slugify(result.group);
final entrySlug = _slugify(result.title);
if (entrySlug.isEmpty) { ... error ...; return; }   // group emptiness is no longer an error
if (groupSlug == 'media') { ... reserved ...; return; }
...
final targetFolder = groupSlug.isEmpty ? entityFolder : '$entityFolder/$groupSlug';
final filePath = '$targetFolder/$entrySlug.ru.md';
...
if (groupSlug.isNotEmpty) {
  await widget.storage.ensureDir(_repoPath(targetFolder));
}
if (await widget.storage.exists(_repoPath(filePath)) || ...) { ... }  // now checks targetFolder
```

### Architecture constraints

- **AD-8 (never crash, never strand):** unchanged from Story 2.11 — every failure path already shows a snackbar and returns; this story adds no new failure path (root creation reuses the same `try`/`on RepoStorageException`/`catch` shape).
- **No `RepoStorage` port changes.** `ensureDir`/`exists`/`writeAtomic` are all already used exactly as needed; this story only changes *which path* they're called with (and whether `ensureDir` is called at all).
- **Testing standard for this project** (from project-context, applies directly here): a UI component's mere presence/absence (e.g. "is the chip rendered") is not itself a strong reason for a test, but this story's chips **drive a data-safety-relevant field** (the path a file gets written to) — so the chip-tap test in Task 4.3 is justified because it proves the chip writes to the *same* controller the submit path reads, not because the chip merely exists.

### Previous story intelligence

Story 2.18 (just completed, code-reviewed and merged) reinforced patterns directly relevant here:
- **Read the actual downstream consumer before trusting a "should work" comment.** Story 2.18's code review caught a real bug because a symmetric-looking code path (`PairedEditorPage`'s RU vs EN create-tab logic) turned out to be asymmetric. This story has a similar shape risk: verify in Task 4 that the root-creation path (`groupSlug.isEmpty`) is exercised by an actual test, not just "obviously correct by inspection" — the old test being *replaced* (not just deleted) is the guard against silently losing coverage here.
- **`mounted` checks after every `await`** — already present throughout `_createSubEntry`; Task 3's edits don't add new `await` boundaries, so no new guards are needed, but don't remove any existing ones while restructuring.
- **FakeRepoStorage test conventions**: `ensureDirCalls`, `writeCalls` are plain lists asserted by equality/emptiness (see `create_sub_entry_test.dart`'s existing tests) — Task 4's new tests should follow the exact same assertion style already established in that file, not introduce a new one.

### Project Structure Notes

No new files. `apps/mobile/lib/app/entity_detail_page.dart` (modified) and `apps/mobile/test/app/create_sub_entry_test.dart` (modified) are the only two files this story touches.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.19, lines 512–535]
- [Source: apps/mobile/lib/app/entity_detail_page.dart — `_createSubEntry`/`_showCreateSubEntryDialog`/`_slugify`, lines 140–428] — the exact code this story modifies
- [Source: apps/mobile/test/app/create_sub_entry_test.dart — full file] — the existing Story 2.11 test suite; one test's expected behavior is superseded by AC1 (see Context)
- [Source: apps/mobile/lib/lore/lore_model.dart — `LoreEntry.tree`, `LoreNode.children`/`.name`, lines 65–131] — the shape `existingGroups` is derived from
- [Source: _bmad-output/implementation-artifacts/2-18-assign-language-to-bare-md-file.md] — most recent story; established the "read the real downstream consumer, don't trust an inspection-only claim" lesson referenced above

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5 (story creation and implementation).

### Debug Log References

- Baseline before work (branch tip `a102a4f`, main after Story 2.18's merge): `flutter test` 348 passing, `flutter analyze` clean.
- Implemented Tasks 1–3 as one combined edit (`_createSubEntry` and `_showCreateSubEntryDialog` are tightly coupled — the dialog's new `existingGroups` parameter and the root-creation branch both live in the same call site) rather than strictly one task at a time; verified with `flutter analyze` after the production-code change before writing tests, consistent with the story's exact plan (no deviation in the actual logic, just batched the edit).
- Confirmed via direct code reading that setting the controller (no `setState`/`StatefulBuilder`) is sufficient to make a chip tap visibly update the `TextField` — `TextEditingController` is a `ValueNotifier` the field already listens to. `flutter analyze` and the chip-tap test both confirm this held.
- `flutter test` → **353 passing** (348 → +5: net of 6 new tests in `create_sub_entry_test.dart` minus the 1 old test whose expected behavior AC1 explicitly supersedes, per the story's own Context section).
- `flutter analyze` → **No issues found**.
- No `lore/` model, loader, `storage/`, or JS-core/fixture changes — confirmed via `git status --porcelain` on those paths (empty), exactly as scoped (`entity_detail_page.dart`-only story).
- **Code review (2026-08-06, cross-model — implemented on Sonnet 5, reviewed on Opus via Blind Hunter / Edge Case Hunter / Acceptance Auditor):** the review's headline finding, confirmed independently by all three layers with live probes, was that a suggestion chip could write to a *different* folder than the one it named — the submit path always re-slugified `result.group`, but a chip's label is the raw on-disk folder name (`LoreNode.name`), so a chip like `Events` produced a near-duplicate `events/` folder and a chip like `События` (Cyrillic) slugified to `''` and silently fell back to the entity root with no warning. This directly undermined AC2's stated purpose. Fixed by matching the trimmed group text against `existingGroups` first and using that raw name unslugified on an exact match — which also closed a second, related gap: typed-but-unslugifiable group text (e.g. `!!!`) had been silently falling back to root instead of erroring, exceeding AC1's scope. Also fixed: `AlertDialog` missing `scrollable: true` (chip row could overflow with the keyboard up), chip tap leaving an undefined text-cursor position, hint text that would be clipped (moved the "leave empty for root" explanation to `helperText`, which wraps), and two test-coverage gaps (root-clobber test only covered `.ru.md`; the chip test's field assertion was unscoped and didn't check the chip doesn't auto-submit). Two related hazards were investigated and deferred, not patched: a root-created sub-entry titled after the entity's own folder name (or "index") gets absorbed by the loader as the overview card or silently dropped, and the clobber guard never checks directory-name collisions — both verified to be pre-existing hazards in `_createSubEntry`'s design already reachable at every group-subfolder level since Story 2.11, not newly invented by this story; a proper fix needs to touch every creation path, out of scope for this UX-polish story. `flutter test` 353 → **357 passing**; `flutter analyze` clean; contract and `storage/` isolation gates re-confirmed clean.

### Completion Notes List

- Replaced the `groupSlug.isEmpty || entrySlug.isEmpty` guard with `entrySlug.isEmpty` only — an empty (or whitespace-only, since `_slugify` trims) group field is no longer an error; it now means "create at the entity root."
- Introduced `targetFolder = groupSlug.isEmpty ? entityFolder : '$entityFolder/$groupSlug'`, replacing the old unconditional `groupFolder`. `filePath` and all three clobber-guard `exists` checks now read from `targetFolder`, so the root case is checked/guarded the same way the group case always was — no new branch in the clobber logic itself. `ensureDir` is now called only when `groupSlug.isNotEmpty` (AC1: root creation never calls it, since the entity folder already exists).
- Added `existingGroups` (derived from `_entry?.tree?.children.map((n) => n.name)`, top-level sections only) as a new parameter to `_showCreateSubEntryDialog`, rendered as a `Wrap` of `ActionChip`s (keyed `sub-entry-group-chip-<name>`) above the group field when non-empty. Each chip's `onPressed` fills the field with that group's exact raw name.
- Updated the group field's hint text so the new root-creation affordance is discoverable without reading documentation.
- `create_sub_entry_test.dart`: replaced the now-superseded `'empty group → error, no write'` test with two tests (empty and whitespace-only group, both asserting root creation) per the story's own Context note that this was an intentional behavior change, not a regression. Added a clobber-at-root test, a chip-tap test, a chip-override-by-typing test, and a no-chips-when-no-sections test.
- No `RepoStorage`/`lore`/model changes; no new dependencies; `flutter analyze` clean; `flutter test` 348 → 353 (+5 net).
- **Post-review:** matched a chip/typed group against `existingGroups` before slugifying, so an exact match always writes to that folder's real name (closes both the near-duplicate-folder bug and the silent-root-fallback-for-non-Latin-names bug); tightened the invalid-filename guard so typed-but-unslugifiable text still errors instead of falling back to root; added `scrollable: true` to the dialog; switched the chip's fill to `controller.value` with an explicit selection; moved the root-creation hint to `helperText`. `create_sub_entry_test.dart`: added a mixed-case-group chip test, a typed-invalid-group test, parameterized the root-clobber test across all three file suffixes, and tightened the chip test's assertions (scoped field lookup, explicit no-submit-on-tap check). `flutter test` 353 → 357 (+4 net).

### File List

- MODIFIED: apps/mobile/lib/app/entity_detail_page.dart
- MODIFIED: apps/mobile/test/app/create_sub_entry_test.dart
- MODIFIED: _bmad-output/implementation-artifacts/sprint-status.yaml

## Change Log

- 2026-08-06: Code review (cross-model: implemented on Sonnet 5, reviewed on Opus — Blind Hunter, Edge Case Hunter, Acceptance Auditor). Headline finding, confirmed by all three layers independently: a suggestion chip could write to a different folder than the one it named — the submit path always re-slugified the group text, but a chip's label is the raw on-disk folder name, so a chip like `Events` created a near-duplicate `events/` folder and a non-Latin chip like `События` silently fell back to root creation with no warning. Fixed by matching the group text against known groups before slugifying, using the exact raw name on a match. This also closed a related gap where typed-but-unslugifiable group text silently fell back to root instead of erroring. Also fixed: missing `scrollable: true` on the dialog (chip row could overflow with the keyboard up), an undefined text-cursor position after a chip tap, hint text that would be clipped, and two test-coverage gaps. Two related loader-absorption hazards were investigated and deferred (pre-existing since Story 2.11, not newly introduced, and out of this story's UX-polish scope to fix generally). `flutter analyze` clean; `flutter test` 353 → 357.
- 2026-08-06: Implemented Story 2.19 — the create-sub-entry dialog now treats an empty group field as "create at the entity root" instead of an error, and shows the entity's existing top-level groups as tappable suggestion chips that pre-fill the group field. Pure UX refinement of Story 2.11's dialog; the underlying create pipeline (slugify → optional ensureDir → clobber guard → writeAtomic → push editor → rescan) is otherwise unchanged. Updated one existing Story 2.11 test whose expected behavior AC1 explicitly supersedes (empty group used to error; now it succeeds at the entity root) — an intentional behavior change flagged in the story's own Context section, not a regression. No `lore/`/`storage/`/model changes; no new dependencies. `flutter analyze` clean; `flutter test` 348 → 353.
