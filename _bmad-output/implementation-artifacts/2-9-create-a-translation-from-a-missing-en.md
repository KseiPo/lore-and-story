---
baseline_commit: a34d8f0
---

# Story 2.9: Create a translation from a missing EN

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to start an EN translation when it's missing,
so that I can fill the gap on the phone.

## Acceptance Criteria

1. **AC1 (FR13 — "needs translation" badge):** Given a sub-entry that exists as a lone `.ru.md` with **no** `.en.md` (a `LoreItem` whose `langs` has `ru` but not `en`), when the entity detail tree renders it, then its row shows a **"needs translation" badge** (a distinct, labelled marker). A full RU/EN pair, or an item that isn't a translation candidate (e.g. a single non-language `orig` file, or a lone `.en.md`), shows **no** badge.
2. **AC2 (open with an empty EN tab):** Given such a translation-candidate item, when I open it, then it opens the **RU/EN paired editor** (Story 2.8) with the **RU tab populated and selected by default** and an **EN tab that starts empty** — because `<base>.en.md` does not exist yet, this is a normal empty create surface, **not** a load-error. (A lone `.ru.md` no longer opens the plain single-file editor.)
3. **AC3 (create on save — a create, never a merge; AD-6/AD-4):** Given I edit the empty EN tab and save, when the write happens, then `<base>.en.md` is **created** at the RU file's own directory (its path derived by swapping the `.ru.md` suffix for `.en.md`, forward-slash normalized) via `RepoStorage.writeAtomic` — atomic, byte-exact, explicit UTF-8. It is a **create of a new individual file**: the RU file is never touched and the two languages are never merged into one file. An **unedited** empty EN tab creates **nothing** (save stays disabled until the buffer is dirty). After the create, returning to the detail tree re-walks and the item now shows as a full pair (no badge).
4. **AC4 (reuse — AD-7; single-file editor unchanged):** Given the create surface, when it is built, then it is the **same** `FileEditor`/`PairedEditorPage` from Story 2.8 **extended**, not a new editor: `FileEditor` gains a **create-if-missing** mode (a missing file opens as an empty ready buffer whose first save creates it), and `PairedEditorPage` **synthesizes** the EN variant for a translation candidate. The single-file `EditorPage`'s existing behavior — a genuinely missing file still opens as an **error** state — is **unchanged** (create-mode is opt-in).
5. **AC5 (no regression; contract untouched):** All Story 2.8 pair/editor/detail/browse/conflicts/widget tests stay green (the paired-save/never-merge, tab-switch, pop/background, and the single-file error-on-missing behavior all preserved). **No loader/model/storage change** — "needs translation" and the EN path are **derived in the UI** from the existing `LoreItem.langs` (Story 2.1a); `writeAtomic` already creates a new file. Fixtures 4/4, `npm test` 4/4; `flutter analyze` clean; `flutter test` green with new create-translation tests.

## Tasks / Subtasks

- [x] **Task 1 — `FileEditor` create-if-missing mode (AC: 2, 3, 4)**
  - [x] Add `final bool createIfMissing;` (default `false`) to `FileEditor` (`apps/mobile/lib/app/file_editor.dart`). In `_load`, when `createIfMissing` is true, **check `storage.exists(widget.path)` first**: if the file is **absent**, go straight to the ready state with an **empty** buffer (`_original = ''`, not dirty) — this is the create surface, not an error; if the file **exists** (a race, or it was created meanwhile), read it normally. When `createIfMissing` is false, `_load` is **unchanged** (a missing file → error state, as today).
  - [x] Saving is unchanged: `writeAtomic(widget.path, text)` creates the file (temp-in-same-dir + rename creates the target; the parent dir is the RU file's existing dir). The existing dirty guard means an **untouched** empty buffer is not savable, so no empty file is created until the author types (AC3).
  - [x] Nicety: when `createIfMissing` and the buffer loaded empty, default to the **editing** surface (not preview) — there is nothing to preview in an empty new file, and the author is here to type. (Set the initial `_previewing` accordingly for that case only; a populated file still opens preview-first per Story 2.7.)
  - [x] Do not change any host-facing getters or the save/dirty/pop contract — `EditorPage` and the existing `PairedEditorPage` tabs keep working exactly as in Story 2.8.
- [x] **Task 2 — `PairedEditorPage` synthesizes the EN create tab (AC: 2, 3, 4)**
  - [x] In `apps/mobile/lib/app/paired_editor_page.dart`, when building `_variants`: if the item is a **translation candidate** (`langs` has `ru` but not `en`), append a **synthetic EN variant** — `lang: 'en'`, `label: 'EN'`, `repoPath` = the RU variant's repo path with its `.ru.md` suffix swapped for `.en.md` (case-insensitive, matching the loader's `_langRe`; forward-slash normalized), and `createIfMissing: true`. Order stays original/RU first, EN last; **RU is still the default tab**. A real 2-variant pair is unchanged (no synthetic tab).
  - [x] Thread a per-variant `createIfMissing` flag into each tab's `FileEditor`. Mark the synthetic EN tab visibly as **new / needs translation** (a small hint on the `Tab` label, distinct from the dirty marker) so the author knows this tab will create the file.
  - [x] Everything else from Story 2.8 is reused as-is: per-tab dirty/save (each writes only its own file — the new EN write is a **create**, never a merge), tab-switch keep-alive, back-out/background save-or-ask across tabs, the all-tabs dirty indicator.
- [x] **Task 3 — Badge + routing in the detail tree (AC: 1, 2, 5)**
  - [x] In `apps/mobile/lib/app/entity_detail_page.dart`, define a translation-candidate predicate: `langs.containsKey('ru') && !langs.containsKey('en')`. In `_itemRow`, when true, render a **"needs translation" badge** on the row (e.g. a `Chip`/`Badge`/labelled icon; keep it accessible with a tooltip/semantics label).
  - [x] Extend `_openItem` routing: open the `PairedEditorPage` when the item is a real pair (`langs.length >= 2`, Story 2.8) **or** a translation candidate (`ru` && !`en`, this story); otherwise the plain `EditorPage` (a single non-language file, or a lone `.en.md`). Preserve `_repoPath` and the rescan-on-return (so a freshly-created `.en.md` shows as a full pair without backing out).
- [x] **Task 4 — Tests (AC: 1–5)**
  - [x] **Create-on-save (the data-safety core)** (`test/app/paired_editor_page_test.dart`, `FakeRepoStorage` seeding **only** `x.ru.md`): opening the item shows RU (default) + an **empty** EN tab (no error); editing the EN tab and saving writes **only** `x.en.md` (`writeCalls == [('…/x.en.md', <text>)]`) — a **create**, with `x.ru.md` untouched and **no merged/base path** ever written; an **unedited** EN tab saves nothing (save disabled). *(Per the project testing-emphasis, focus tests on this create/never-merge business logic; keep UI-badge assertions light.)*
  - [x] **Routing** (`entity_detail_page_test.dart`): a lone-`.ru.md` sub-entry opens the `PairedEditorPage` (tabs, empty EN) — not the plain editor; a real pair still opens the paired editor; a single non-language file still opens the plain editor. One light assertion that the "needs translation" badge renders for the candidate row.
  - [x] **Regression:** the full Story 2.8 suite stays green (single-file error-on-missing unchanged; paired save/never-merge/pop/background intact). Contract gate: `flutter analyze` clean; `flutter test` green; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/ apps/mobile/lib/storage/` **empty**.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). The Auditor reproduced every gate (analyze clean, 245/245, `npm test` 4/4, contract/`lore/`/`storage/` git-clean) and found **all 5 ACs genuinely met**, with the create/never-merge tests proven by exact-list assertions. Blind confirmed the core is sound — AD-6 never-merge, the EN-path derivation (the "clobber RU" scenario **cannot occur** via the loader — regex identical + `$`-anchored + loader guarantees `.ru.md`), no accidental empty create, failed-create-doesn't-navigate, no single-file regression. Two trivial patches; two documented defers.

**Patch:**

- [x] [Review][Patch] **Low (data-safety net) — guard the synthetic-EN derivation against a same-path clobber.** `paired_editor_page.dart` derives the EN path with `langs['ru']!.file.replaceFirst(RegExp(r'\.ru\.md$', …), '.en.md')`. `replaceFirst` returns the string **unchanged** on no match, so if a `ru`-keyed file ever didn't end in `.ru.md` (loader/UI regex drift, or a directly-constructed `LoreItem`), the "EN" tab would point at the **RU path** and saving it would overwrite the RU file. Unreachable today (the loader guarantees `.ru.md`), but a catastrophic outcome behind a one-line guard: only append the synthetic EN variant when `enFile != ruFile` (the suffix actually matched). [apps/mobile/lib/app/paired_editor_page.dart initState] (edge+blind)
- [x] [Review][Patch] **Low — the "needs translation" badge uses a non-unique `Key`.** `entity_detail_page.dart` gives every candidate row's `Chip` the literal `Key('needs-translation-badge')`, so `find.byKey(...)` (the new test) is ambiguous once an entity has 2+ lone-`.ru.md` sub-entries. The badge needs no stable identity in production — drop the explicit `Key` and have the test find it by its label. [apps/mobile/lib/app/entity_detail_page.dart _itemRow / entity_detail_page_test.dart] (blind)

**Deferred:**

- [x] [Review][Defer] **Create-mode save can clobber a concurrently-synced `.en.md` (TOCTOU).** `_load` checks `exists` once; if the syncer lands a real `.en.md` between the check and the save, the create-tab's `writeAtomic` overwrites it (and, unlike editing an existing file, there's no on-disk baseline the author saw first). Consistent with the app's deliberate **no-optimistic-locking** design (AD-5 — the external syncer owns propagation; a real collision produces a `*.sync-conflict-*` copy that Story 2.4 surfaces), so the remote content isn't truly lost. Create-mode widens the window; accepted for v0.1, noted. [apps/mobile/lib/app/file_editor.dart _load] (edge+blind)
- [x] [Review][Defer] **The EN tab's "will create" hint is stale after a successful create.** The `Icons.translate` hint is fixed from `_Variant.createIfMissing` and keeps showing for the session after the file is created; it self-corrects on the next rescan/reopen (the model then has `en`). Cosmetic. [apps/mobile/lib/app/paired_editor_page.dart TabBar] (blind)

**Dismissed (2):** a long item title visually competing with the trailing badge on narrow phones — `Text` wraps in a `ListTile`, cosmetic; no "are you sure" before a first-time create — that's AC3's explicit design (create on save), risk-accepted.

## Dev Notes

### What this story is — the empty-EN create tab, on top of Story 2.8

Story 2.8 built the RU/EN paired editor (`PairedEditorPage` over per-language `FileEditor`s, each saving only its own file, never merging). This story handles the **missing EN**: a lone `.ru.md` is a deliberate "needs translation" signal (project-context, §3.3), not a defect. Two small extensions + a badge:

1. **`FileEditor` create-if-missing** — a missing file opens as an **empty** ready buffer instead of an error; the first save **creates** it (`writeAtomic` = temp+rename creates the target).
2. **`PairedEditorPage` synthesizes the EN tab** — for a translation candidate, it adds an EN tab pointed at the derived `.en.md` path with `createIfMissing: true`. RU stays the default tab.
3. **Detail-tree badge + routing** — a translation-candidate row shows "needs translation" and opens the paired editor (not the plain one).

The AI-assisted translation (context pack → generated draft) is **Epic 4 / FR21** — out of scope here. This is the manual "type the translation, it creates the file" path.

### What defines a "translation candidate" (and why not the others)

From the loader (`lore_loader.dart`, `_langRe = \.(ru|en)\.md$`): a `.ru.md` → `langs['ru']`, a `.en.md` → `langs['en']`, any other file → `langs['orig']`. So:

- **`ru` present, `en` absent → translation candidate** (this story: badge + empty EN create tab). FR13 is specifically "create the missing **EN**."
- A **full pair** (`ru` + `en`) → Story 2.8, no badge.
- **`orig` only** (a non-bilingual file like `hobby.md`) → **not** a candidate — it doesn't follow the `.ru`/`.en` convention; plain single-file editor, no badge.
- **`en` only** (a lone `.en.md`) → **not** a candidate for *this* story (FR13 is RU→EN); plain editor, no badge. (Treating a lone `.en.md` as an error is an anti-pattern — project-context.)

Predicate: `langs.containsKey('ru') && !langs.containsKey('en')`.

### Deriving the EN path — a create at the RU file's own directory

The EN file to create sits beside the RU file: take the RU variant's path (`langs['ru'].file`, loreDir-relative) and swap the `.ru.md` suffix for `.en.md` (case-insensitive), then join `loreDir` as `_repoPath` already does. E.g. `events/scene.ru.md` → `events/scene.en.md`. `writeAtomic` writes a temp file in that **existing** directory and renames — so the create needs no `mkdir` (the RU file's dir already exists). This is a **create of a new individual file** (AD-4/AD-6): the RU file is never read/written by the EN tab, and nothing is ever merged.

### Total / safety carried over

- `FileEditor`'s create-mode uses `storage.exists` to distinguish "expected-absent (create surface)" from a genuine read failure — so create-mode can't mask a real I/O error, and non-create-mode still shows the error state (AC4, AD-8).
- The Story 2.8 save-failure hardening applies unchanged: if the `.en.md` create write fails, `save()` returns false and the paired editor does **not** navigate away — the typed translation is preserved (AD-10).
- An untouched empty EN tab is not dirty → not savable → **no empty `.en.md` is created** by accident.

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/app/file_editor.dart`** (MODIFY) — add `createIfMissing` (default false) + the `exists`-guarded empty-buffer load; the initial-`_previewing` nicety for an empty new file. Everything else (save/dirty/pop/lossy/conflict/highlighting/preview, the getters, `save()`-returns-bool from the 2.8 review) is untouched.
- **`apps/mobile/lib/app/paired_editor_page.dart`** (MODIFY) — synthesize the EN variant for a translation candidate; thread `createIfMissing` per tab; mark the new EN tab. The `_Variant`, tab/keep-alive, active-tab AppBar, and cross-tab pop/background logic from 2.8 are reused as-is.
- **`apps/mobile/lib/app/entity_detail_page.dart`** (MODIFY) — the "needs translation" badge on a candidate row; `_openItem` routes candidates (and real pairs) to `PairedEditorPage`. `_repoPath`/`_rescan` preserved.

**Do NOT modify** (verify git-clean): `apps/mobile/lib/lore/**` (no model/loader change — candidacy + EN path are derived in the UI), `apps/mobile/lib/storage/**` (`exists`/`writeAtomic` already suffice — no new port method), `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

### Architecture guardrails

- **AD-6 — RU/EN pairs are a view; saves target the individual file.** The EN create writes only the derived `.en.md`; the RU file is never touched; nothing is merged. [ARCHITECTURE-SPINE.md#AD-6]
- **AD-4 / NFR1 — atomic byte-exact write (and create).** The new `.en.md` is written via the same `writeAtomic` (temp+rename), which creates the file atomically; explicit UTF-8. No new writer. [#AD-4]
- **AD-7 spirit — one editor, extended not forked.** Create-mode is a flag on the existing `FileEditor`; the EN tab is a synthesized variant of the existing `PairedEditorPage`. No new editor implementation. [#AD-7]
- **AD-8 / NFR7 — total.** `exists`-guarded create-load never turns an expected-absent file into an error, and never masks a real failure; the single-file error-on-missing path is unchanged. [#AD-8]
- **AD-10 — never strand a dirty buffer.** The 2.8 save-failure guard applies: a failed `.en.md` create keeps the screen with the typed text. [#AD-10]
- **AD-2 — contract untouched.** No loader/model/fixtures change; candidacy and the EN path are UI-derived from the existing `langs`. Fixtures 4/4, `npm test` 4/4. [#AD-2]

### Previous story intelligence

- **2.8 (done):** `FileEditor` (public `FileEditorState`, `save()` returns `Future<bool>` after the review) + `PairedEditorPage` (variant list ordered ru/orig/en, RU default, `_KeepAlive` tabs, cross-tab pop/background, all-tabs dirty indicator). This story extends both. The `_openItem` routing in `entity_detail_page` already branches `langs.length >= 2` → paired; add the translation-candidate branch beside it.
- **2.7 (done):** editors open **preview-first**; an empty new EN file has nothing to preview, so open its tab in edit mode (the create nicety). Tests use the shared `enterEditMode` helper.
- **project testing-emphasis (see `project-context.md` → Developer workflow):** cover the **business logic** — here, the create-on-save / never-merge correctness — and **don't over-invest in UI/widget tests**; a light badge assertion is enough. [[testing-emphasis]]
- **Cross-model review ([[cross-model-code-review]])** finds a real issue every story — expect probing on: the EN path derivation (wrong dir, backslash, wrong suffix case), a create write that fails still navigating away (should be guarded by 2.8's `save()`-bool), an accidental empty-file create, and any regression to the single-file error-on-missing behavior. Cover the first two with tests.
- **Toolchain:** Flutter `C:\programs\flutter\bin` (not on PATH — prefix it); `flutter analyze` + `flutter test`; `npm test` for the JS cross-check.

### Git intelligence

Baseline `a34d8f0` (Story 2.8 merged). `FileEditor`/`PairedEditorPage`/`entity_detail_page` are the three files this story touches; the model already provides `langs`. Branch per story, ff-merge to main, never push, model `Co-Authored-By` trailer ([[git-story-workflow]]).

### Library / version policy

**No new dependencies.** Create-if-missing is `storage.exists` + the existing `writeAtomic`; the EN tab is a synthesized `PairedEditorPage` variant; the badge is a Material `Chip`/`Badge`. All existing infra.

### Testing standards

- **Create-on-save → widget tests** in `test/app/`: empty EN tab, edit + save creates only `.en.md` (create, not merge; RU untouched); unedited EN creates nothing. This is the data-safety core — cover it well.
- **Routing → widget test**: lone-`.ru.md` → paired editor with empty EN; badge renders (light).
- **Regression → the whole Story 2.8 suite** stays green (single-file error-on-missing unchanged).
- **Contract gate:** fixtures 4/4, `npm test` 4/4, `git status --porcelain … apps/mobile/lib/lore/ apps/mobile/lib/storage/` empty. `app/`-only.

### Project Structure Notes

- Modified UI only: `file_editor.dart` (create-mode), `paired_editor_page.dart` (synthetic EN tab), `entity_detail_page.dart` (badge + routing).
- Tests: additions to `paired_editor_page_test.dart` and `entity_detail_page_test.dart`.
- No `lore/` or `storage/` change — `app/`-only, consistent with the slice split; candidacy and the EN path are view-derived.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.9] — user story + ACs (FR13 "needs translation" badge; create EN on save, a create not a merge)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR13] (needs-translation badge when `.en.md` absent; editing the empty EN tab creates the file)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-6] (pairs are a view; saves/creates target the individual file), #AD-4 (atomic byte-exact write/create), #AD-10 (never strand a dirty buffer), #AD-8 (total), #AD-2 (contract untouched)
- [Source: apps/mobile/lib/lore/lore_model.dart] — `LoreItem.langs` (keys ru/en/orig); a `ru`-without-`en` item is the translation candidate; `LoreLang.file` is the RU path the EN path derives from
- [Source: apps/mobile/lib/lore/lore_loader.dart] — `_langRe = \.(ru|en)\.md$` (how `.ru`/`.en` are keyed; the suffix to swap for the EN path)
- [Source: apps/mobile/lib/app/file_editor.dart] — the per-file editor gaining create-if-missing (Story 2.8)
- [Source: apps/mobile/lib/app/paired_editor_page.dart] — the paired editor gaining the synthesized EN tab (Story 2.8)
- [Source: apps/mobile/lib/app/entity_detail_page.dart] — `_itemRow`/`_openItem` (badge + route the candidate to the paired editor)
- [Source: _bmad-output/implementation-artifacts/2-8-edit-ru-en-pairs-safely.md] — the paired editor / `FileEditor` this extends; the `save()`-returns-bool pop-safety hardening to preserve
- [Source: _bmad-output/project-context.md] — "a missing `.en.md` is a deliberate 'needs translation' signal, not a defect"; write individual files, never merge; testing-emphasis (cover business logic, defer UI tests)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- Baseline before work: `flutter test` 241 passing, analyze clean.
- `flutter analyze` → **No issues found.**
- `flutter test` → **245 passing** (241 → +4: 3 create-translation + 1 routing/badge). Focused on the create-on-save/never-merge business logic per the project testing-emphasis; UI-badge coverage kept to one light assertion.
- **Contract gate (AC5):** `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/ apps/mobile/lib/storage/` **empty** — no model/loader/storage change; candidacy and the EN path are UI-derived, and `writeAtomic`/`exists` already sufficed.

### Completion Notes List

- **`FileEditor` create-if-missing (extend, don't fork).** Added an opt-in `createIfMissing` flag (default false). In `_load`, when true it calls `storage.exists(path)` first: an **absent** file → ready with an empty buffer (and `_previewing = false` so the empty new file opens in edit mode, nothing to preview); an **existing** file reads normally; a genuine read failure still errors (`exists` distinguishes expected-absent from a real I/O problem — AD-8). Saving is unchanged — `writeAtomic` creates the file (temp+rename). The single-file `EditorPage`'s missing-file → error behavior is untouched (create-mode is opt-in), and every host-facing getter / the `save()`-returns-bool pop-safety contract is unchanged.
- **`PairedEditorPage` synthesizes the EN create tab.** When the item is a translation candidate (`langs` has `ru` but not `en`), it appends a synthetic EN variant whose path is the RU file with its `.ru.md` suffix swapped for `.en.md` (case-insensitive, same directory, forward-slash normalized), with `createIfMissing: true`. RU stays the default tab; the EN tab carries a `Icons.translate` "needs translation / will create" hint. All the Story 2.8 machinery (per-tab dirty/save, keep-alive, cross-tab pop/background, all-tabs dirty indicator) is reused as-is — the EN write is a **create of its own file, never a merge** (AD-6).
- **Detail-tree badge + routing.** `entity_detail_page` gained a `_needsTranslation(item)` predicate (`ru && !en`); `_itemRow` shows a keyed, tooltip'd "Needs translation" `Chip` for such rows, and `_openItem` routes them (and real pairs) to `PairedEditorPage`, else the plain `EditorPage`. Rescan-on-return preserved, so a freshly-created `.en.md` shows as a full pair on the way back.
- **Verified (data-safety core):** the empty EN tab opens without a load error; editing it and saving writes **only** `events/scene.en.md` (a create; `.ru.md` untouched; no merged/base path); an unedited EN tab creates nothing (save disabled, background writes nothing). The AI-assisted translation path is deliberately out of scope (Epic 4 / FR21).
- **No new files, no new deps, no model/loader/storage change** — three UI files extended, `app/`-only.

### File List

**Modified:**
- `apps/mobile/lib/app/file_editor.dart` (add `createIfMissing` + the `exists`-guarded empty-buffer load; empty-new opens in edit mode)
- `apps/mobile/lib/app/paired_editor_page.dart` (synthesize the EN create tab for a translation candidate; thread `createIfMissing`; EN-tab "needs translation" hint)
- `apps/mobile/lib/app/entity_detail_page.dart` (`_needsTranslation` predicate; "Needs translation" row badge; route candidates to `PairedEditorPage`)
- `apps/mobile/test/app/paired_editor_page_test.dart` (create-on-save: empty EN, create-only-.en.md/never-merge, unedited-creates-nothing)
- `apps/mobile/test/app/entity_detail_page_test.dart` (lone-RU → badge + paired-editor routing)

**Deliberately NOT modified (verified git-clean):** `apps/mobile/lib/lore/**` (candidacy + EN path are UI-derived), `apps/mobile/lib/storage/**` (`exists`/`writeAtomic` sufficed — no new port method), `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-26 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers), 2 patches. Both Low: (P1, data-safety net) guard the synthetic-EN path derivation — only append the EN create tab when `enFile != ruFile`, so a no-match `replaceFirst` can never point the "EN" tab at the RU file and clobber it on save (unreachable via the loader, but cheap insurance against drift); (P2) dropped the non-unique `Key('needs-translation-badge')` on the row Chip (ambiguous with 2+ candidates) — the test now finds the badge by its label. Review confirmed the core sound (AD-6 never-merge, EN-path derivation, no accidental create, failed-create-doesn't-navigate, no single-file regression); 2 findings deferred (create-mode TOCTOU vs the syncer — accepted per AD-5/conflict-copies; stale "will create" hint — cosmetic, self-corrects on reopen); 2 dismissed. Tests 245 (unchanged); analyze clean; `npm test` 4/4; contract git-clean. |
| 2026-07-26 | Implemented Story 2.9: create a translation from a missing EN (FR13). Extended Story 2.8's editor: `FileEditor` gained an opt-in `createIfMissing` mode (an `exists`-guarded missing file opens as an empty edit surface; first save creates it via `writeAtomic`), and `PairedEditorPage` now synthesizes an empty EN tab for a lone-`.ru.md` translation candidate (EN path = RU path with `.ru.md`→`.en.md`, same dir), RU still default, EN tab hinted "needs translation". `entity_detail_page` shows a "Needs translation" row badge and routes candidates to the paired editor. Saving the EN tab creates `<base>.en.md` only — a create, never a merge (AD-6); the single-file error-on-missing behavior is unchanged. No new files/deps; no loader/model/storage change (UI-derived). Tests 241 → 245 (+4, focused on the create/never-merge business logic per testing-emphasis); analyze clean; `npm test` 4/4; `lore/`+`storage/`+contract git-clean. |
