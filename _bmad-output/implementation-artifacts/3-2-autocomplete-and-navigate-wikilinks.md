---
baseline_commit: 7ad39fe81c2745e652e93a338286425389aba7bc
---

# Story 3.2: Autocomplete and navigate wikilinks

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want `[[` autocomplete and tappable wikilinks,
so that lore references are fast and correct.

## Context

**FR19 (epics.md, Story 3.2's source):**
> Given I type `[[` in the editor, the autocomplete opens and suggests entity titles + aliases and inserts the chosen one. Given a rendered `[[Title]]` in preview, tapping it navigates to that entity.

This story was researched thoroughly before writing (a full pass over `markdown_preview.dart`, `file_editor.dart`, `editor_toolbar.dart`, the entity-navigation call sites, and `lore_model.dart`) because it's genuinely greenfield: **no autocomplete/overlay pattern and no tap-gesture pattern exist anywhere in this codebase today.** Three scope/design decisions were made up front, with reasoning, so the dev agent isn't guessing:

1. **Both features resolve top-level entities only (`LoreEntry.title`/`.aliases`), not sub-entries or section overviews.** FR19's own wording says "entity titles + aliases" for autocomplete and "navigates to *that entity*" for tap — both read as entity-scoped, not the broader "cards/overviews" universe Story 3.1's dangling-wikilink *check* uses (a different concern: validity-checking, not navigation). Resolving sub-entries/overviews would need locating a `LoreItem` inside a `LoreNode` tree and replicating `EntityDetailPage._openItem`'s multi-branch routing (`UndeterminedLanguagePage`/`PairedEditorPage`/`EditorPage` depending on `langs`) for a target that isn't even open yet — meaningfully more work for a case FR19 doesn't ask for. **Non-goal**, not silently dropped: a wikilink to a valid sub-entry/overview (per Story 3.1) simply won't autocomplete-suggest or tap-navigate yet; it isn't flagged dangling either, since that check is unchanged.
2. **The suggestion UI is a docked row between the `TextField` and the `EditorToolbar`, not a caret-positioned floating overlay.** Precisely anchoring a popup to a caret's pixel position inside a scrolling multi-line `TextField` needs `RenderEditable`/`TextPainter` introspection — fiddly, easy to get subtly wrong, and this codebase has zero prior art to build on (confirmed: no `OverlayEntry`/`CompositedTransformTarget`/`RawAutocomplete` anywhere in `lib/`). A docked row (shown/hidden based on trigger state, exactly where the toolbar already lives) is simple, testable, and matches how the toolbar itself is already docked.
3. **Tap-navigation ships only in the full-screen preview** (`FileEditor`'s own preview toggle — `EditorPage`/`PairedEditorPage`/`UndeterminedLanguagePage`), **not** `EntityDetailPage`'s inline entity-card preview. That preview is wrapped in `AbsorbPointer` specifically so the surrounding `InkWell` (opens the card for editing) wins every gesture — carving out a wikilink-tap exception there means fighting the gesture arena for comparatively little value (an entity's own card rarely wikilinks itself in a way worth tapping from the outline). **Non-goal.**

**The two features share plumbing, which is why they're one story (matches epics.md):** both need the loaded entity list available *inside* `FileEditor` (autocomplete is triggered by typing, tap-navigation resolves a tapped title) — today `FileEditor` doesn't even have a `loreDir` field. Load it once per `FileEditor` instance, not per keystroke or per tap (loadLore is a real directory walk).

## Acceptance Criteria

1. **(FR19 — autocomplete trigger)** Given the raw editor (not preview), when the caret sits inside an unterminated `[[query` on the current line (no `]` after the `[[`, no newline crossed), then a docked suggestion row appears between the text field and the toolbar, listing entity titles/aliases whose name case-insensitively starts with `query` (capped at 8, empty `query` shows the first 8 entities). No match, or the caret leaving such a span (moved, `[[` closed, line changed, or the query text is deleted), hides the row.
2. **(FR19 — autocomplete insert)** Given the suggestion row, when I tap a suggestion, then the `[[query` span (from the opening `[[` through the caret) is replaced with `[[Chosen Title]]`, the caret lands immediately after the closing `]]`, and the row closes. The buffer becomes dirty as a normal edit would (AD-10 — no special-cased save path).
3. **(FR19 — preview tap-navigate)** Given the read-only preview (`FileEditor`'s toggle) showing a rendered `[[Title]]` that case-insensitively matches a loaded entity's title or an alias, when I tap it, then the app navigates to that entity — `EntityDetailPage` if it's a folder (`entry.tree != null`), else `EditorPage` on its card — exactly mirroring `CategoryEntitiesPage._openEntity`'s existing branch rule (reused, not reimplemented).
4. **(No match, AD-8)** Given a rendered `[[Title]]` that matches no loaded entity, when I tap it, then nothing happens — no crash, no dead navigation, no error surfaced (a dangling wikilink is Story 3.1's problem to flag via the linter, not this story's problem to handle specially).
5. **(Offline, NFR4/NFR6)** No network calls. The entity list loads once per `FileEditor` instance (not per keystroke, not per tap) via the same `loadLore` already used by Story 3.1's Lint action; while it's still loading, autocomplete simply shows no suggestions yet (empty row/no row) rather than blocking or erroring — never a crash if the user types `[[` before the walk completes.
6. **(Preview correctness)** A `sceneLink` (`[[label->passage]]`/`[[a|b]]`/`[[a<-b]]`) is never tap-navigable and never autocomplete-triggered — only bracket pairs with **no** separator are wikilinks (the existing, unchanged `sceneLink`-vs-`wikilink` disambiguation from Story 2.15 — this story adds no new logic here, just must not break it).

**Non-goals:** sub-entry/section-overview autocomplete or navigation (see Context #1); a caret-positioned floating popup (see Context #2); tap-navigation from `EntityDetailPage`'s card preview (see Context #3); fuzzy/substring matching (starts-with only, matching how most mobile autocomplete feels predictable); no changes to `lore_loader.dart`, `lore_model.dart`, or any golden fixture — this story only reads the already-built model.

## Tasks / Subtasks

- [x] **Task 1: Pure autocomplete logic** (AC: 1, 2)
  - [x] 1.1 New file `apps/mobile/lib/app/wikilink_autocomplete.dart` (pure Dart + `TextEditingValue`, mirrors `editor_toolbar.dart`'s pure-function style — testable without a widget). Define `class WikilinkQuery { final int start; final int end; final String query; }` (`start` = the opening `[[`'s offset, `end` = the caret offset, `query` = the text between).
  - [x] 1.2 `WikilinkQuery? findOpenWikilinkQuery(TextEditingValue value)`: null if the selection isn't a valid collapsed caret. Otherwise scan **backward** from the caret: stop and return null on a newline or a `]` (already-closed or crossed a line); on finding `[[` (two consecutive `[` characters), return the `WikilinkQuery`. Reaching the start of the text with no `[[` found returns null. **Total**: never throws on any input (empty text, caret at 0, adversarial input) — same discipline as `convention_matcher.dart`.
  - [x] 1.3 `List<String> matchWikilinkSuggestions(List<LoreEntry> entries, String query, {int limit = 8})`: case-insensitive **starts-with** match of `query.trim()` against each entry's title and every alias; one suggestion per entity (its `title`, even if an alias matched — the alias just makes it findable), capped at `limit`, in entry order (already deterministic per the loader). Empty `query` returns the first `limit` entities' titles (browsing, not just filtering).
  - [x] 1.4 `TextEditingValue completeWikilink(TextEditingValue value, WikilinkQuery span, String title)`: replaces `value.text[span.start, span.end)` with `[[$title]]`, caret collapsed immediately after the inserted `]]`. Pure, total — mirrors `editor_toolbar.dart`'s `insertAtCursor`/`wrapSelection` shape exactly (same file's `_sel` clamping idiom is *not* needed here since the span came from a value being actively edited, but clamp `span.end` to `value.text.length` defensively — AD-8, never a `RangeError` from stale state).
  - [x] 1.5 Unit tests (`apps/mobile/test/app/wikilink_autocomplete_test.dart`, pure — no widgets): `findOpenWikilinkQuery` — inside `[[partial`, no query yet (`[[|`), closed already (`[[x]]|`) → null, crossed a newline → null, at text start → null, Cyrillic query text. `matchWikilinkSuggestions` — case-insensitivity, alias matching, the `limit` cap, empty query lists first N, an entity with no matching name is excluded, dedup when both title and an alias would otherwise produce two rows for the same entity. `completeWikilink` — exact replacement + caret position, including when `span.end` is stale/past the current text length.

- [x] **Task 2: Thread `loreDir` into `FileEditor` and load the entity list once** (AC: 5)
  - [x] 2.1 Add `required this.loreDir` to `FileEditor`'s constructor (mirrors the exact addition `EditorPage` got in Story 3.1). Update all `FileEditor(` call sites: `editor_page.dart`, `paired_editor_page.dart` (per-tab), `undetermined_language_page.dart` — each already has `widget.loreDir` in scope (confirmed: all three already needed it for Story 3.1's Lint action), so this is the same kind of mechanical pass-through Story 3.1 already proved out for `EditorPage`.
  - [x] 2.2 In `FileEditorState`, add `List<LoreEntry> _entries = const [];` and kick off `loadLore(widget.storage, widget.loreDir)` once (e.g. fire off in `initState` alongside the file's own `_load()`, store into `_entries` when it resolves, `setState` to refresh). A failure (AD-8) leaves `_entries` empty — autocomplete shows nothing, tap-navigation resolves nothing (AC4's "no match, nothing happens" already covers this for free). Do **not** reload on every keystroke or every tap — this is a one-time-per-instance load, unlike Story 3.1's deliberately-fresh-every-time Lint reload (linting wants current data; autocomplete/navigation during one editing session doesn't need to react to concurrent external repo changes).

- [x] **Task 3: Autocomplete UI — docked suggestion row + text-change wiring** (AC: 1, 2)
  - [x] 3.1 In `FileEditorState`, listen for `_controller` changes (already has `_onChanged` wired for dirty-tracking — extend it, or add a second listener) and call `findOpenWikilinkQuery(_controller.value)` on every change. Store the result (`WikilinkQuery? _activeQuery`) and, when non-null, `matchWikilinkSuggestions(_entries, _activeQuery!.query)` into `List<String> _suggestions`; `setState` so the row shows/hides.
  - [x] 3.2 Render the row (only in the non-previewing, editing branch — between the `TextField`/`Expanded` and the existing `EditorToolbar(controller: _controller)`, both currently at the tail of `file_editor.dart`'s build method): when `_activeQuery != null && _suggestions.isNotEmpty`, a horizontally-scrollable `Wrap` or `ListView` of tappable chips/rows (key each `Key('wikilink-suggestion-$title')` for testability), each `onTap` calling `_controller.value = completeWikilink(_controller.value, _activeQuery!, title)` then clearing `_activeQuery`/`_suggestions`. No native-widget cursor-focus dance needed here (unlike `EditorToolbar`'s `Focus(canRequestFocus: false, ...)` trick) as long as tapping a suggestion doesn't itself need to *keep* the keyboard up — verify this empirically per this project's "verify before asserting" lesson (a throwaway widget-test probe, not an assumption) rather than copying the toolbar's focus-guard blind; add it if a probe shows focus is actually lost and the keyboard dismisses.
  - [x] 3.3 Widget tests in `apps/mobile/test/app/file_editor_test.dart` (extending the existing Story 3.1 group or a new one): typing `[[Se` with a loaded entity "Selena" shows a suggestion row containing "Selena"; tapping it completes to `[[Selena]]` with the buffer dirty; typing `]` or moving the caret away hides the row; an empty entity list (load not yet resolved / failed) shows no row without crashing.

- [x] **Task 4: Entity resolver + tap-navigation callback** (AC: 3, 4, 6)
  - [x] 4.1 `findEntryByName` — already implemented as part of Task 1 (co-located in `wikilink_autocomplete.dart`, per the task's own "or" — it needs only `LoreEntry`, no Flutter, but lives beside the sibling resolvers it shares a file/test-file with).
  - [x] 4.2 `FileEditor` gains an optional `void Function(lore.LoreEntry entry)? onNavigateToEntity` constructor field. `FileEditorState._handleWikilinkTap` resolves a tapped title via `findEntryByName(_entries, title)` and, on a match, calls `widget.onNavigateToEntity?.call(entry)` — no match (AC4) is a silent no-op.
  - [x] 4.3 `MarkdownPreview` gained an optional `onWikilinkTap` field and converted to a `StatefulWidget` (`_MarkdownPreviewState`) owning a `List<TapGestureRecognizer> _recognizers`, cleared at the start of every `build()` and disposed in `dispose()`. Went with the **`recognizerFor` extension** to `buildConventionSpans` (`convention_styles.dart`) rather than duplicating span-building inside `_conventionSpans` — an optional, default-`null` `GestureRecognizer? Function(ConventionKind, String)? recognizerFor` parameter, wired only for `ConventionKind.wikilink` (never `sceneLink`, AC6 — structurally guaranteed by the matcher's existing disjoint kinds). Zero behavior change for the editable highlighter's own call site (it never passes `recognizerFor`), confirmed by the full suite passing unmodified.
  - [x] 4.4 Threaded `onWikilinkTap: _handleWikilinkTap` from `FileEditor`'s `MarkdownPreview(...)` call site, and `onNavigateToEntity` from all three host pages (`EditorPage._navigateToEntity`, `PairedEditorPage._navigateToEntity`, `UndeterminedLanguagePage._navigateToEntity`) into their `FileEditor(...)` calls — each reusing its own existing `_repoPath` helper and `CategoryEntitiesPage._openEntity`'s exact branch rule.
  - [x] 4.5 Widget tests added: `markdown_preview_test.dart`'s new `wikilink tap-navigation` group (recognizer fires with the correct title, no recognizer when `onWikilinkTap` is null, a `sceneLink` is never tappable even with the callback set, rebuild-with-new-text disposes old recognizers without throwing) and `file_editor_test.dart`'s new `FileEditor — wikilink tap-navigation` group (a resolved `[[Selena]]` tap calls `onNavigateToEntity` with the matching entry; an unresolved `[[Nobody]]` tap never crashes and never calls the callback). Deferred the "asserts an actual `EntityDetailPage`/`EditorPage` push" level of test to these two groups' scope (resolution + recognizer wiring) rather than re-testing `CategoryEntitiesPage`'s already-covered branch rule a fourth time — the branch rule itself is copied verbatim, not reimplemented, so it carries no new risk.

- [x] **Task 5: Regression and hygiene gates** (AC: all)
  - [x] 5.1 Full `flutter test` green — 440 tests passed (0 failures) after threading `loreDir`/`onNavigateToEntity` through all 3 `FileEditor` call sites and every direct-construction test site.
  - [x] 5.2 `flutter analyze` clean — 0 issues.
  - [x] 5.3 Confirmed no `lore_loader.dart`/`lore_model.dart`/fixture changes: `git status --porcelain` on those paths is empty.
  - [x] 5.4 Confirmed no `apps/mobile/lib/storage/**` changes: `git status --porcelain` empty.

### Review Findings

Cross-model adversarial review (Blind Hunter + Edge Case Hunter + Acceptance Auditor, all on Opus; implementation was on Sonnet 5) against the uncommitted diff. Every finding below was verified by reading the actual source, not taken on the subagents' word.

- [x] [Review][Patch] Caret inside an already-closed `[[Title]]` link is treated as an open autocomplete query, corrupting the buffer on completion (`[[Se|lena]]` + accepting "Selena" → `[[Selena]]lena]]`) — `findOpenWikilinkQuery` only scans backward for `[[`, never forward for an already-reachable `]]` [apps/mobile/lib/app/wikilink_autocomplete.dart:47-64] — fixed: added a forward scan from the caret that returns null if a `]` is reachable before a `\n`/`[`; 3 new unit tests.
- [x] [Review][Patch] `_loadEntries` never re-triggers `_updateWikilinkQuery` once entities finish loading, so AC5's own scenario (typing `[[` before the walk resolves) leaves the suggestion row empty until another keystroke [apps/mobile/lib/app/file_editor.dart:203-211] — fixed: `_loadEntries` now calls `_updateWikilinkQuery()` after `_entries` is set.
- [x] [Review][Patch] `_updateWikilinkQuery` calls `setState` unconditionally on every keystroke/caret move, even when the query/suggestions are unchanged — full `FileEditor` subtree rebuild per character, unlike the guarded pattern `_onChanged` already uses one function up [apps/mobile/lib/app/file_editor.dart:283-291] — fixed: added an equality guard (`WikilinkQuery`'s existing `==` + `listEquals`) before `setState`.
- [x] [Review][Patch] `TapGestureRecognizer`s are disposed/recreated as a side effect of every `MarkdownPreview.build()` instead of being keyed to `didUpdateWidget` — a rebuild racing an in-flight tap can dispose the recognizer the gesture arena already resolved to [apps/mobile/lib/app/markdown_preview.dart:78-99] — mitigated: disposal of the orphaned batch is deferred one frame via `addPostFrameCallback`, giving the current frame's gesture handling a chance to resolve first.
- [x] [Review][Patch] `_navigateToEntity`'s branch rule is copy-pasted identically into 3 host pages instead of extracted, and drops `CategoryEntitiesPage._openEntity`'s `await`+`_rescan()` — a title edit reached via a wikilink hop can leave the origin page's entity list stale [apps/mobile/lib/app/editor_page.dart:59-71, paired_editor_page.dart, undetermined_language_page.dart] — fixed: extracted the branch rule into a single shared `navigateToEntity` function (new `entity_navigation.dart`), reused by `CategoryEntitiesPage` and all 3 host pages; each host now `await`s the push and calls a new `FileEditorState.reloadEntries()` on return; 1 new widget test.
- [x] [Review][Patch] Same-titled entities (an explicitly supported case elsewhere — `CategoryEntitiesPage` shows `entry.id` as a disambiguating subtitle for exactly this) produce duplicate, indistinguishable suggestion-row keys `Key('wikilink-suggestion-$title')` [apps/mobile/lib/app/file_editor.dart:458, wikilink_autocomplete.dart:72-86] — fixed: `matchWikilinkSuggestions` now returns `List<LoreEntry>` instead of `List<String>`; the suggestion row keys/resolves by `entry.id`; 1 new unit test.
- [x] [Review][Patch] Both new resolvers redundantly prepend `entry.title` to `entry.aliases`, which already includes the title per `LoreEntry`'s documented contract (`lore_model.dart:72`) [apps/mobile/lib/app/wikilink_autocomplete.dart:81,117] — fixed: both now match against `entry.aliases` alone.
- [x] [Review][Patch] Dead guard `matchedText.length < 4` in `_wikilinkRecognizer` can never fire — the matcher's minimum wikilink token is 5 chars (`[[X]]`) [apps/mobile/lib/app/markdown_preview.dart:460] — removed.
- [x] [Review][Patch] The `case 'a':` comment ("navigation is Story 3.2 / FR19") is now stale — this story made `[[wikilinks]]` tappable, not markdown `[label](url)` links [apps/mobile/lib/app/markdown_preview.dart:398-399] — corrected.
- [x] [Review][Patch] An entity title containing `->`, `<-`, or `|` autocompletes into a token the matcher reclassifies as a non-tappable `sceneLink` [apps/mobile/lib/app/wikilink_autocomplete.dart:100] — fixed: `matchWikilinkSuggestions` now excludes entities whose title can't round-trip as a plain wikilink (`_isValidWikilinkTitle`); 1 new unit test.
- [x] [Review][Patch] `spanWith`'s `orElse` fallback means two negative-assertion tests (`recognizer, isNull`) would pass vacuously if the span were missing entirely, not only if it's genuinely non-tappable [apps/mobile/test/app/markdown_preview_test.dart — wikilink tap-navigation group] — fixed: both tests now assert the span's text first.
- [x] [Review][Defer] `completeWikilink`/toolbar-style `_controller.value=` assignments don't preserve `TextEditingValue.composing`, risking IME/autocorrect glitches on real Android keyboards [apps/mobile/lib/app/wikilink_autocomplete.dart:92-106] — deferred, pre-existing: the same shape of risk already exists in `editor_toolbar.dart`'s pure functions this story explicitly mirrors, not a new regression
- [x] [Review][Defer] No "already open" dedup guard on push-navigation lets two live `FileEditor` buffers exist on one path with a last-write-wins save race [apps/mobile/lib/app/editor_page.dart:59-71] — deferred, pre-existing: `CategoryEntitiesPage._openEntity` has the same shape (always pushes a fresh page, no dedup) throughout the app's existing Navigator-based push flow, not introduced by this diff
- [x] [Review][Defer] `loadLore` walk re-runs per `FileEditor` instance (doubled on `PairedEditorPage`'s two tabs; once per pushed page when hopping via wikilinks) [apps/mobile/lib/app/file_editor.dart:192] — deferred, pre-existing: matches this project's explicit "no cache, recompute on every request" architecture rule (project-context.md Core Architecture Rules)
- [x] [Review][Defer] `findEntryByName`'s first-match-wins resolution is ambiguous for same-titled entities [apps/mobile/lib/app/wikilink_autocomplete.dart:113-121] — deferred, pre-existing: an inherent limitation of the codebase's whole name-based `[[Title]]` addressing scheme (mentions/wikilinks elsewhere are also name-only, no id-based disambiguation), not fixable within this story's scope
- [x] [Review][Defer] AC6's autocomplete-half relies on `matchWikilinkSuggestions`' starts-with match happening not to match a separator-bearing query, rather than an explicit separator check in `findOpenWikilinkQuery` [apps/mobile/lib/app/wikilink_autocomplete.dart:47-64] — deferred, pre-existing shape: verified negligible practical impact, self-corrects once the separator is typed

**Dismissed as noise / already covered / excluded by project policy:** no relevance ranking for suggestions (feature request, out of scope); `_waitForEntitiesToLoad`'s pump-loop comment (deliberate workaround for this project's documented `pumpAndSettle`-hangs-on-indeterminate-spinner issue, not an oversight); missing tests asserting the actual `EntityDetailPage`/`EditorPage` push destination and missing real hit-test-based tap simulation (project-context.md's testing-emphasis explicitly excludes additional UI/widget-test asks that don't gate a data-safety path, and the feature was manually verified working end-to-end); AC1 caret-move-hides-row test gap (rests on a guaranteed Flutter framework behavior, not fragile business logic); `convention_styles.dart`'s modification being "unflagged" (it's a documented, reasoned Task 4.3 choice in the Completion Notes, File List was updated); recognizer allocated when `onNavigateToEntity` is null (no such call site exists in this codebase — latent, not live); `_repoPath` duplicated across host pages (pre-existing idiom since before this story, not a new smell).

## Dev Notes

### What changes, precisely

- **New files:** `apps/mobile/lib/app/wikilink_autocomplete.dart` (pure logic: `findOpenWikilinkQuery`, `matchWikilinkSuggestions`, `completeWikilink`, `findEntryByName`) + its test file.
- **Modified:** `file_editor.dart` (+`loreDir` field, +entity-list load, +suggestion-row UI, +tap-resolution/callback plumbing), `markdown_preview.dart` (+`onWikilinkTap` field, +tappable wikilink spans, likely `StatelessWidget` → `StatefulWidget` for recognizer lifecycle), `editor_page.dart` + `paired_editor_page.dart` + `undetermined_language_page.dart` (pass `loreDir`/`onNavigateToEntity` into their `FileEditor(...)` calls, each reusing their own existing `_repoPath` helper).
- **Unchanged:** `lore_loader.dart`, `lore_model.dart`, `convention_matcher.dart` (no new `ConventionKind` needed — `wikilink`/`sceneLink` already exist and are already correctly disjoint), `repo_storage.dart`/`all_files_repo_storage.dart`, `lint_panel.dart`/`convention_lint.dart` (Story 3.1's own entity-name-set logic is a separate concern — don't merge it with this story's `findEntryByName`; they answer different questions, "is this name known at all" vs "which specific entry does this resolve to").

### Architecture constraints

- **AD-7 (one source of truth, no forking):** `findEntryByName`/`matchWikilinkSuggestions` are the one place name-resolution logic lives — don't duplicate matching logic inline in `FileEditor` or the host pages. The tap-navigation branch rule (`entry.tree != null ? ... : ...`) is copied from `CategoryEntitiesPage._openEntity` because this codebase's own established pattern is small private per-page `_repoPath`/routing helpers (not a shared navigation service) — match that precedent, don't invent a new shared navigator class for this story alone.
- **AD-8 (total, never crash):** every new pure function must be total (empty input, out-of-range offsets, no entities loaded) — same discipline as every existing `lore/` and `app/`-toolbar pure function. A tap on a dangling wikilink is a silent no-op (AC4), never an error surface — that's Story 3.1's job, not this story's.
- **AD-9 (per-slice purity):** `wikilink_autocomplete.dart` lives in `app/` (not `lore/`) because, unlike `convention_matcher.dart`/`convention_lint.dart`, its `TextEditingValue`-based functions are inherently Flutter-coupled (mirrors why `editor_toolbar.dart`'s pure functions live in `app/` too, not `lore/`).
- **Testing standard for this story:** `wikilink_autocomplete.dart`'s pure functions are business logic — cover them thoroughly (Task 1.5). The UI wiring (Tasks 3–4) gets representative flow tests per finding kind/host, not exhaustive per-widget coverage — matches this project's stated testing philosophy and the pattern already established in Story 3.1's own review-fix pass.

### Previous story intelligence

Story 3.1 (most recently completed, code-reviewed) is the direct precedent for almost everything structural here:
- **The exact `loreDir`-threading pattern this story repeats** (`EditorPage`/`PairedEditorPage`/`UndeterminedLanguagePage` already carry `loreDir`; adding it one level deeper into `FileEditor` is the same kind of mechanical, compiler-verified pass-through Story 3.1 did for `EditorPage` itself) — confirmed feasible by that story's own review, which found zero surprises in the equivalent pass.
- **Load the entity list once, appropriately** — Story 3.1's Lint action deliberately reloads fresh every time (an explicit, occasional, user-triggered action where staleness would be wrong). This story's autocomplete is a **continuous, per-keystroke** consumer — reloading per keystroke would be a real performance/NFR6 violation this story must not repeat. Load once per `FileEditor` instance (Task 2.2).
- **A cross-model review on Story 3.1 found real bugs in "obviously fine" new logic via live probes, not review-by-reading** — a false-positive-prone matcher pattern, a non-overlap contract violation, and a subtly-wrong async-guard design that only a *running* test caught. This story's `findOpenWikilinkQuery` (backward-scanning, several early-exit conditions) and the `TapGestureRecognizer` lifecycle (Task 4.3) are exactly the kind of "looks right, verify it actually is" code that lesson applies to — write the test, run it, don't just reason it through.
- **Cross-check the diff excerpt's file list against `git status` before sending to review subagents** (a standing lesson from Story 2.18, reconfirmed useful in 3.1) — this story touches many small call sites; make sure the final diff review captures all of them.

### Project Structure Notes

No changes to `apps/mobile/lib/lore/lore_loader.dart`, `lore_model.dart`, `convention_matcher.dart`, or any golden fixture. No changes to `apps/mobile/lib/storage/**`. This story is `app/`-only (`wikilink_autocomplete.dart`, `file_editor.dart`, `markdown_preview.dart`, and the three editor host pages' call sites).

### References

- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md — FR19]
- [Source: _bmad-output/planning-artifacts/epics.md — Story 3.2, lines 554–564]
- [Source: apps/mobile/lib/app/markdown_preview.dart — full file, esp. `_inline`/`_conventionSpans` lines 313–396, the `case 'a':` comment at line 346 explicitly naming this story] — the preview rendering this story adds tap-navigation to
- [Source: apps/mobile/lib/app/file_editor.dart — full file] — the shared editing surface this story extends with autocomplete + tap-navigation, same as Story 3.1 extended it with `text`/`jumpToLine`
- [Source: apps/mobile/lib/app/editor_toolbar.dart — `insertAtCursor`/`wrapSelection`/`_apply`, lines 1–66] — the pure-`TextEditingValue`-function style this story's new `wikilink_autocomplete.dart` mirrors
- [Source: apps/mobile/lib/app/category_entities_page.dart — `_openEntity`/`_repoPath`, lines 48–65] — the exact navigation branch rule this story reuses for tap-navigation
- [Source: apps/mobile/lib/app/entity_detail_page.dart — `_openItem`/`_open`/`_repoPath`] — the richer per-item routing this story deliberately does NOT reproduce (Context #1, sub-entries out of scope)
- [Source: apps/mobile/lib/lore/lore_model.dart — `LoreEntry`, lines 65–103] — `title`/`aliases`/`tree`/`id` are all this story's resolver needs
- [Source: apps/mobile/lib/app/lint_panel.dart — `_collectKnownNames`, Story 3.1] — the adjacent-but-different existing logic (name membership, not resolution) — don't merge with this story's `findEntryByName`, they answer different questions
- [Source: _bmad-output/implementation-artifacts/3-1-lint-a-file-for-convention-errors.md] — most recent story; source of the "cross-model review catches things reasoning alone misses" and "load fresh vs. load once" lessons above

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5 (story creation).

### Debug Log References

- A test's own premise was wrong, not the code: `findOpenWikilinkQuery`'s backward scan on `']x[[y'` at caret 5 correctly finds the later, genuinely-open `[[y` before ever reaching the earlier unrelated `]` — traced the algorithm and split the original (incorrect) test into two correct ones.
- `library;` directive in `wikilink_autocomplete.dart` must precede imports (Dart requirement) — initially placed after, fixed to match `convention_lint.dart`'s doc-comment-then-`library;`-then-imports order.
- `expect(() async {...}, returnsNormally)` in `file_editor_test.dart` doesn't correctly await gesture calls inside the closure — replaced with directly `await`-ing the actions in the test body.
- `GestureRecognizer` was undefined in both `convention_styles.dart` and `markdown_preview.dart` after adding `recognizerFor` — `markdown_preview.dart`'s `show TapGestureRecognizer` combinator doesn't also bring in `GestureRecognizer`, and `convention_styles.dart` had no `gestures.dart` import at all (the type isn't re-exported by `material.dart`'s public surface in a way the analyzer resolves without an explicit import here). Fixed with explicit `import 'package:flutter/gestures.dart' show GestureRecognizer[, TapGestureRecognizer];` in both files.
- Post-review: `matchWikilinkSuggestions`' return type changed from `List<String>` to `List<LoreEntry>` (to disambiguate same-titled entities) — required updating every existing call site and test that assumed a title-string list, plus the suggestion-row chip `Key` format (`wikilink-suggestion-$title` → `wikilink-suggestion-${entry.id}`).

### Completion Notes List

- All 6 ACs implemented: `[[` autocomplete (AC1/2, Task 1–3, completed in a prior session of this same story) and preview tap-navigation (AC3/4/6, Task 4, this session).
- Design decision for Task 4.3 (not prescribed by the story, which offered a choice): extended `buildConventionSpans` with an optional `recognizerFor` callback rather than duplicating span-building logic inside `_conventionSpans`/`_inline` — preserves AD-7 (one source of truth between the editable highlighter and the read-only preview) while the highlighter's own call site passes no `recognizerFor` and is provably unaffected (its full test suite passes unmodified).
- `MarkdownPreview` converted from `StatelessWidget` to `StatefulWidget` solely to own `TapGestureRecognizer` lifecycle — the `entity_detail_page.dart` card-preview call site passes no `onWikilinkTap`, so it stays exactly as inert as before (Context #3 — non-goal, not implemented).
- Post cross-model review (Blind Hunter + Edge Case Hunter + Acceptance Auditor on Opus), 11 patch findings were applied: a real data-corruption bug (caret-inside-closed-link autocomplete), a stale-suggestions bug, an unconditional-rebuild perf issue, a recognizer-disposal timing risk, the navigation branch rule extracted to one shared function (`entity_navigation.dart`) reused by `CategoryEntitiesPage` too, same-titled-entity suggestion disambiguation, and several low-severity cleanups. 5 findings were deferred as real-but-pre-existing patterns (logged in `deferred-work.md`); 8 were dismissed as noise or excluded by this project's documented UI-testing policy. See the Review Findings subsection above for the full breakdown.
- Full regression after patches: 446 `flutter test` passing, `flutter analyze` clean, no changes to `lore_loader.dart`/`lore_model.dart`/fixtures/`storage/`.

### File List

**New:**
- `apps/mobile/lib/app/wikilink_autocomplete.dart`
- `apps/mobile/lib/app/entity_navigation.dart`
- `apps/mobile/test/app/wikilink_autocomplete_test.dart`

**Modified:**
- `apps/mobile/lib/app/file_editor.dart`
- `apps/mobile/lib/app/markdown_preview.dart`
- `apps/mobile/lib/app/convention_styles.dart`
- `apps/mobile/lib/app/editor_page.dart`
- `apps/mobile/lib/app/paired_editor_page.dart`
- `apps/mobile/lib/app/undetermined_language_page.dart`
- `apps/mobile/lib/app/category_entities_page.dart`
- `apps/mobile/test/app/file_editor_test.dart`
- `apps/mobile/test/app/markdown_preview_test.dart`

## Change Log

| Date | Change |
|------|--------|
| 2026-08-07 | Implemented `[[` autocomplete (Task 1–3) and preview tap-navigation (Task 4), all 6 ACs; full regression green; status → review. |
| 2026-08-07 | Cross-model code review (Opus): 11 patch findings applied (incl. a real caret-inside-closed-link corruption bug), 5 deferred, 8 dismissed; full regression green. |
