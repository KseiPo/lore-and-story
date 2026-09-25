---
baseline_commit: 9c8facc4a58abdfcd0aa30b155c820de43435e42
---

# Story 5.6: Drop the language suffix when promoting an entity to a folder

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want Promote to folder to name the new folder and its card without a language suffix,
so that entity folders always get clean names (`frank/frank.md`) however the flat card was named.

## Context

**Decision (KseiPo, 2026-09-24): folders never carry a language suffix.** When a
card is converted into a folder, with or without a language suffix, the suffix is
omitted from the result.

**What happens today.** Story 2.17's `_promoteEntity`
(`apps/mobile/lib/app/category_entities_page.dart`) derives the slug by stripping
only a trailing `.md`:

```dart
final slug =
    fileName.endsWith('.md') ? fileName.substring(0, fileName.length - 3) : fileName;
final newFolderId = dirId.isEmpty ? slug : '$dirId/$slug';
final newCardId = '$newFolderId/$slug.md';
```

So `characters/frank.ru.md` promotes to `characters/frank.ru/frank.ru.md`. Story
2.17 recorded this in its own spec as an accepted non-goal ("an unusual but
harmless result"), and this story reverses it. The case is not hypothetical: every
simple entity the app's own **New entity** button creates is `<slug>.ru.md` (Story
2.10, AC3), so an app-created entity promoted by the app always gets a
suffixed folder today.

**Why the card inside must lose the suffix too, not just the folder.** The loader
recognizes a folder as an entity folder only when it contains a card named exactly
`index.md` or `<folder-name>.md` (`lore_loader.dart`, `_walkCategory`:
`for (final candidate in ['index.md', '${item.name}.md'])`). A folder `frank/`
holding only `frank.ru.md` would **not** be an entity folder. The loader would
treat `frank/` as a sub-category and turn the card and every future sub-entry
into separate loose entities (verified empirically on 2026-09-24 with a throwaway
loader probe while writing `docs/agent-writing-rules.md`). Entity-folder cards are
language-neutral by design: the loader never pairs them (`_buildNode` skips any
`base == cardBase` file, so a `selena/selena.en.md` next to `selena/selena.md` is
invisible), and Story 2.18 excludes folder cards from language assignment for the
same reason. The target is therefore always `<slug>/<slug>.md`.

**What "the suffix" means.** Use the loader's own language-suffix semantics:
`\.(ru|en)\.md$`, case-insensitive (`lore_loader.dart`'s private `_langRe`). The
stripped name is exactly the loader's `base` for that file, so `frank.RU.md` →
`frank` and the unusual `frank.ru.en.md` → `frank.ru` (only the final language
suffix, as the loader itself computes). A name without a language suffix keeps
today's `.md`-only strip.

**Collisions get likelier, so the guard gets one more check.** Before this story
the target folder was `frank.ru/`, which almost never pre-existed. Now it is
`frank/`, which can: for example, `frank.ru.md` and `frank.en.md` both exist at
category level, where the app lists them as two separate entities, and one of them
was already promoted. The existing pre-flight guard refuses only when
`<slug>/<slug>.md` exists (Story 2.17 review decision: an existing *folder* alone
must not block). This story keeps that decision and also refuses when
`<slug>/index.md` exists. `index.md` is the loader's other card name and wins over
`<folder>.md`, so moving a second card into such a folder would demote the moved
card to a stray root overview.

**Out of scope:**
- Migrating folders that an earlier promotion already named with a suffix
  (`frank.ru/frank.ru.md`). The loader reads those correctly as entity folders; the
  author renames them by hand if wanted.
- Pairing or moving a same-slug sibling (`frank.en.md` left next to the new
  `frank/`). Cards never pair, so there is nowhere correct to put it automatically.
- Any change to the New entity button's own `<slug>.ru.md` naming (Story 2.10).
  KseiPo's decision covers folders; simple-entity cards may keep a suffix.

## Acceptance Criteria

1. **(Suffix dropped)** Given a simple entity whose file name ends in a language
   suffix (`<slug>.ru.md` or `<slug>.en.md`, matched case-insensitively like the
   loader's `_langRe`), when I promote it, then the app creates `<slug>/` and moves
   the card to `<slug>/<slug>.md`. The suffix is dropped from both the folder and the
   card name, and the card's content is unchanged apart from Story 5.1's
   relative-image-path rewrite. *(extends FR26)*
2. **(No-suffix path unchanged)** Given a simple entity without a language suffix
   (`<slug>.md`), when I promote it, then the behavior is byte-for-byte what it is
   today: `ensureDir('<slug>')`, `movePath('<slug>.md', '<slug>/<slug>.md')`, and no
   extra write when there are no images to rewrite.
3. **(Collision guard, AD-8)** Given a card already exists in the target folder
   (`<slug>/<slug>.md` **or** `<slug>/index.md`), when I promote, then the app shows
   the existing "A folder with this name already exists." error and never calls
   `ensureDir` or `movePath`; the source file stays untouched. An existing
   *empty* or card-less target folder still does **not** block promotion (Story 2.17
   review decision, unchanged).
4. **(Loader recognizes the result, AD-10)** Given a successful promotion of a
   suffixed card, when the entity list rescans, then the entity shows as a folder
   entity. Tapping it opens the detail-tree outline (`EntityDetailPage`), not the
   plain editor, which proves the new card name is the one the loader looks for.
5. **(Still one atomic move, AD-4)** Given the promotion, when it runs, then the
   card is relocated by a single `RepoStorage.movePath`, never a read-write-delete.
   Story 5.1's rewrite (when needed) remains a separate `writeAtomic` **after** the
   move succeeds.
6. **(Confirm dialog names the destination)** Given the promote confirmation
   dialog, when it opens, then it names the card's destination (e.g.
   `characters/frank/frank.md`), since the card can now be renamed as well as moved.
   The old line "The card itself is unchanged — just moved." is no longer accurate
   (it hasn't been since Story 5.1's rewrite either) and is replaced.
7. **(Docs)** Given the rule is now "folders never carry a language suffix", when
   this story ships, then ARCHITECTURE.md §3.2, project-context.md (entity
   resolution) and `docs/agent-writing-rules.md` (§2.2, §2.5, §3, §4) state it, and
   none of them still describes a suffixed folder as the promotion result.
8. **(Reserved folder name, AD-8)** Given the suffix-free folder name would be
   `media` (e.g. `characters/media.ru.md`), when I promote, then the app refuses
   with `"media" is reserved and cannot be used as a folder name.` and never calls
   `ensureDir` or `movePath`. The walk skips every `media/` folder
   (`lore_loader.dart`'s `_isSkippedWalkDir`), so the promoted entity would
   silently vanish. Dropping the suffix creates this path: `media.ru.md` used to
   promote to a visible `media.ru/`. Same wording and guard shape as the existing
   category and group reserved-name guards (`home_page.dart`,
   `entity_detail_page.dart`).

## Tasks / Subtasks

- [ ] **Task 1: Pure promotion-target helper in `lore/`** (AC: 1, 2)
  - [ ] 1.1 New file `apps/mobile/lib/lore/promotion.dart`: a pure, total function
        `({String folderId, String cardId}) promotionTargetOf(String entryId)`. It
        takes a loreDir-relative simple-entity id (e.g. `characters/frank.ru.md`)
        and returns the loreDir-relative folder and card ids
        (`characters/frank`, `characters/frank/frank.md`). Rules: split the id into
        dir + file name at the last `/`; strip a trailing language suffix with
        `RegExp(r'\.(ru|en)\.md$', caseSensitive: false)` when it matches, otherwise
        strip a plain trailing `.md` (today's rule); join. Mirror `lore_loader.dart`'s
        own `_langRe` exactly and say so in a comment ("keep in sync"), the same
        duplication-with-a-comment precedent as `_kAiPromptConfigFileName`.
        **Do not import or edit `lore_loader.dart`** (contract gate below).
  - [ ] 1.2 Library doc comment: name KseiPo's 2026-09-24 decision (folders never
        carry a language suffix), explain why the card name must match the folder
        (the loader's `<folder>.md` card rule), and state that the stripped name is
        exactly the loader's `base`.
  - [ ] 1.3 Export it from the `lore/lore.dart` barrel, beside
        `image_path_rewriter.dart`.
  - [ ] 1.4 Unit tests `apps/mobile/test/lore/promotion_test.dart`:
        - `characters/frank.md` → `characters/frank` / `characters/frank/frank.md`
        - `.ru.md` and `.en.md` both drop the suffix
        - an upper/mixed-case suffix (`frank.RU.md`, `frank.En.md`) drops it too
        - `frank.ru.en.md` → `frank.ru` (only the final suffix)
        - a file at the lore root (`frank.ru.md`, no dir) → `frank` / `frank/frank.md`
        - a nested category (`characters/secondary/carrie.en.md`)
        - a name that only looks suffix-like (`frank.russian.md`, `ru.md`) keeps
          today's `.md`-only strip

- [ ] **Task 2: Use it in `_promoteEntity`, harden the guard, reword the dialog** (AC: 1–6, 8)
  - [ ] 2.1 In `apps/mobile/lib/app/category_entities_page.dart`, replace the inline
        `lastSlash`/`dirId`/`fileName`/`slug`/`newFolderId`/`newCardId` derivation
        with `promotionTargetOf(entry.id)`. Compute it **before** showing the
        confirm dialog (AC6 needs the destination). Keep `_repoPath(...)` for the
        repo-relative storage paths exactly as today.
  - [ ] 2.2 Extend the pre-flight guard: refuse (same snackbar text, same early
        return, before `ensureDir`) when `exists(newCardPath)` **or**
        `exists('<newFolderPath>/index.md')`. Keep the Story 2.17 review decision:
        an existing folder with no card is **not** a collision.
  - [ ] 2.2b AC8: before the collision guard (and before `ensureDir`), if the
        target folder's own name (the last segment of `folderId`) is exactly
        `media`, show `"media" is reserved and cannot be used as a folder name.` and
        return. Compare exactly and case-sensitively, like `_isSkippedWalkDir`
        (`name == 'media'`). Simplest placement: right after computing the target,
        before even opening the confirm dialog, so the author isn't asked to
        confirm an impossible promotion.
  - [ ] 2.3 `_showPromoteConfirmDialog`: pass the loreDir-relative destination
        card id and replace "The card itself is unchanged — just moved." with a
        line naming it, e.g. `Its card moves to characters/frank/frank.md.` Keep
        the title (`Promote to folder?`) and the `promote-entity-confirm` key
        unchanged; existing tests find the dialog by both.
  - [ ] 2.4 Change nothing else in `_promoteEntity`: the `_promotingIds`
        re-entrancy guard, the `entry.tree != null` defensive return, the Story
        5.1 rewrite (computed from `entry.text` up front, written only after a
        successful move, a rewrite-write failure never surfacing as a promotion
        failure), both catch clauses (`on RepoStorageException` + `catch (_)`), and
        the `_rescan()` after success.
  - [ ] 2.5 Update `_promoteEntity`'s doc comment: `<slug>.md` → `<slug>/<slug>.md`
        now reads "a card named `<slug>.md` or `<slug>.<lang>.md` → `<slug>/<slug>.md`",
        and mention the added `index.md` collision check.

- [ ] **Task 3: Widget tests in `apps/mobile/test/app/promote_entity_test.dart`** (AC: 1–6, 8)
  - [ ] 3.1 Generalize the `_repo()` helper to take the simple entity's file name
        (default `frank.md`, so every existing test is untouched). Optionally also
        take a pre-existing `index.md` card in the target folder.
  - [ ] 3.2 `frank.ru.md` promotes: `moveCalls == [('characters/frank.ru.md',
        'characters/frank/frank.md')]`, `ensureDirCalls == ['characters/frank']`,
        the content is preserved, and `writeCalls` is empty (no images).
  - [ ] 3.3 `frank.en.md` promotes the same way (one test, or parameterize 3.2 over
        both suffixes).
  - [ ] 3.4 AC4 end-to-end: after promoting `frank.ru.md`, tap the row and expect
        `EntityDetailPage`, not `EditorPage`. This is the test that proves the
        loader accepts the new name, so don't skip it (mirror the existing Story
        2.17 test of the same shape).
  - [ ] 3.5 AC3: `frank.ru.md` with an existing `frank/frank.md`, and separately
        with an existing `frank/index.md`, shows "A folder with this name already
        exists." with `ensureDirCalls` and `moveCalls` both empty.
  - [ ] 3.5b AC8: `characters/media.ru.md` shows the reserved-name snackbar,
        with `ensureDirCalls` and `moveCalls` empty and the source untouched.
  - [ ] 3.6 AC1 + Story 5.1 together: a suffixed card with one relative image
        (`![Frank](media/frank.jpg)`) promotes to `characters/frank/frank.md`
        containing `../media/frank.jpg`.
  - [ ] 3.7 Don't add a test that only asserts the dialog's new wording renders
        (a UI presence test; project testing emphasis). The destination
        *computation* is already covered by Task 1.4 and 3.2.
  - [ ] 3.8 Every existing promote test (Story 2.17 + 5.1 groups) stays green
        unchanged.

- [ ] **Task 4: Docs** (AC: 7)
  - [ ] 4.1 `ARCHITECTURE.md` §3.2, after "growing one into the other is just
        `mkdir` + move": add that folder and card names never carry a language
        suffix, so promotion turns `mira.md` or `mira.ru.md` into
        `mira/mira.md` (decided 2026-09-24).
  - [ ] 4.2 `_bmad-output/project-context.md`, "Entity resolution" bullets: add one
        bullet with the same rule (entity-folder names and their cards are
        suffix-free; promotion drops a suffix).
  - [ ] 4.3 `docs/agent-writing-rules.md`:
        - §2.2: add "Folder names never carry a language suffix."
        - §2.5 step 1: drop any suffix (`frank.ru.md` and `frank.md` both → `frank/frank.md`).
        - §2.5 closing paragraph: replace "If the card has a language suffix
          (`frank.ru.md`), ask the author how to name the folder." with the new
          rule plus the collision cases (a `frank/` card already exists, or both
          `frank.ru.md` and `frank.en.md` exist) → ask the author.
        - §3: narrow "Cards take no suffix" to entity-folder cards and
          section/quest overviews; a simple entity may carry one.
        - §4: leave the New-entity-button note.
        - Bump the "Last synced" footer date.
  - [ ] 4.4 Leave the PRD (`prds/…/prd.md` FR26) alone; epics.md's FR26 already
        carries the 2026-09-24 note.

- [ ] **Task 5: Gates** (AC: all)
  - [ ] 5.1 `flutter analyze` clean and `flutter test` green, run from
        `apps/mobile` via PowerShell with
        `$env:PATH = "C:\programs\flutter\bin;" + $env:PATH`. Record before/after
        counts.
  - [ ] 5.2 `npm test` 4/4 at the repo root.
  - [ ] 5.3 Contract gate: `git status --porcelain lib/lore.js test/fixtures/
        scripts/ apps/mobile/lib/lore/lore_loader.dart
        apps/mobile/lib/lore/lore_model.dart` is **empty**. No loader, model or
        fixture change; the loader already recognizes `<slug>/<slug>.md`.

## Dev Notes

### Current state of the code this story touches (read before editing)

- **`apps/mobile/lib/app/category_entities_page.dart` — `_promoteEntity(LoreEntry entry)`**
  (Story 2.17, extended by 5.1):
  1. Returns early for a folder entity (`entry.tree != null`) or an id already
     in `_promotingIds`.
  2. Awaits `_showPromoteConfirmDialog(context, entry.title)`, adds the id to
     `_promotingIds`, and derives the paths inline (the snippet in Context).
  3. Computes `rewrittenText = rewriteRelativeImagePaths(entry.text)` up front.
  4. Inside `try`:
     - if `exists(newCardPath)`, shows "A folder with this name already exists."
       and returns;
     - otherwise calls `ensureDir(newFolderPath)`, then
       `movePath(cardPath, newCardPath)`;
     - if the text changed, calls `writeAtomic(newCardPath, rewrittenText)` in its
       own swallow-all `try`.
  5. `on RepoStorageException` and `catch (_)` both show "Failed to promote this
     entity." and return.
  6. On success, `_rescan()`. A `finally` clears `_promotingIds`.
- **`_showPromoteConfirmDialog(BuildContext, String title)`**: an `AlertDialog`
  titled `Promote to folder?` with the content line quoted in AC6, and Cancel /
  Promote (`Key('promote-entity-confirm')`) actions.
- **`apps/mobile/test/app/promote_entity_test.dart`**: two groups (Story 2.17,
  Story 5.1). `_repo({withExistingCard, withOrphanedFolder, failMove})` seeds
  `characters/frank.md`. `_pumpReady` pumps `LoreStoryApp` with fakes, and
  `_navigateToCategory` taps the category. Tests assert on
  `storage.moveCalls` / `ensureDirCalls` / `writeCalls` / `read(...)`. A
  `_SlowMoveStorage` gates `movePath` for the re-entrancy test.
- **`apps/mobile/test/fakes.dart` — `FakeRepoStorage`**:
  - `ensureDir` registers the new dir in its parent's listing, and `movePath`
    re-parents the moved file (copy-on-write), so a post-promotion rescan really
    sees `characters/frank/` with `frank.md` inside. That is what makes the AC4
    end-to-end test meaningful.
  - `exists` is true for a seeded dir listing or seeded file content, so seed
    `characters/frank/index.md` in `fileContents` for the AC3 index case.
  - `movePath` throws if the destination's parent dir was never registered,
    mirroring a real rename.

### What must be preserved

Single-rename atomicity (AD-4). No overwrite: the pre-flight guard runs before
`ensureDir`, and `movePath` itself never refuses (its contract says the caller
guards). The order ensureDir → movePath → optional rewrite write. The rewrite can
never fail a promotion (Story 5.1 AC3). The re-entrancy guard and button disabling
(Story 2.17 review fixes), the rescan-on-success (AD-10), and the error surface
(AD-8 at the call site: both catch clauses stay). The existing test suite passes
without edits beyond the `_repo()` generalization in Task 3.1.

### Architecture guardrails

- **AD-3 / AD-9**: the new helper is pure Dart in `lore/` (no Flutter, no `dart:io`),
  and all I/O stays behind `RepoStorage` (`exists`/`ensureDir`/`movePath`/
  `writeAtomic`). No port change.
- **AD-4**: one `movePath` for the card. The only write is Story 5.1's conditional
  rewrite.
- **AD-8**: total. The helper never throws (pure string ops); the call site keeps
  both catch clauses.
- **AD-10**: model rebuilt by rescan, never patched.
- **AD-12**: the helper is exported through the `lore/` barrel; `app/` imports the
  barrel (already does: `import '../lore/lore.dart';`).
- **Contract gate**: `lore_loader.dart` / `lore_model.dart` / fixtures / JS reference
  untouched. This story changes *where the app writes*, not what the loader reads.

### Why a new `lore/` helper instead of an inline edit

The naming rule is business logic with edge cases: case-insensitivity, only the
final suffix stripped, names that merely look suffix-like, and root-level ids. The
project's testing emphasis says business logic gets thorough unit tests, and a pure
function is the cheapest way to pin them all without pumping widgets. This follows
Story 5.1's precedent (`rewriteRelativeImagePaths` in
`lore/image_path_rewriter.dart`, used by the same `_promoteEntity`). Keep it small:
one function, no class.

### Testing standards

Business logic is covered by pure unit tests (Task 1.4). Data-safety and wiring
are covered by widget tests asserting on the fake's call logs and resulting file
content (Task 3). No UI presence/absence tests (project-context "Testing
emphasis"; also see Task 3.7).

### Previous story intelligence

- **5.1 (the direct predecessor on this code path):**
  - Put pure logic in `lore/` with its own unit tests and verified the promoted
    result end to end by rendering, not string-diffing.
  - Kept `entry.text` as the rewrite source (no extra read).
  - Its review was clean (0 findings). Follow the same shape.
- **2.17:**
  - The guard decision (a card collision blocks; a folder alone doesn't), the
    `_promotingIds` guard, and the copy-on-write fake came out of its review.
    Don't regress them.
  - Its spec's non-goal about `frank.ru.md` → `frank.ru/frank.ru.md` is exactly
    what this story reverses; cite it in the Completion Notes.
- **5.4 (most recent story):**
  - Verify claims empirically rather than by inspection.
  - Record full-suite before/after counts.
  - Reviews are run cross-model (Opus-implemented → review on Sonnet/Fable).

### Git intelligence

- HEAD `9c8facc` added `docs/agent-writing-rules.md` (which this story updates)
  and fixed project-context.md's monologue line.
- Story 5.5 (linter false positive on emphasized labels) is being developed in
  parallel on its own branch. It touches `convention_matcher.dart`,
  `convention_lint.dart`, epics.md and sprint-status.yaml, not this story's files.
  It will also edit `docs/agent-writing-rules.md` §5.1/§10, disjoint from this
  story's §2.2/§2.5/§3.
- Workflow ([[git-story-workflow]]):
  - branch `story/5-6-drop-the-language-suffix-when-promoting-an-entity-to-a-folder`
    off `main`;
  - commit with a `Co-Authored-By` trailer for the implementing model;
  - `git merge --ff-only` into `main`;
  - never push.

### Library / version policy

No new dependencies. No web research needed (pure Dart string handling, no API
surface).

### Project Structure Notes

- New: `apps/mobile/lib/lore/promotion.dart`,
  `apps/mobile/test/lore/promotion_test.dart`.
- Modified: `apps/mobile/lib/lore/lore.dart` (export),
  `apps/mobile/lib/app/category_entities_page.dart`,
  `apps/mobile/test/app/promote_entity_test.dart`, `ARCHITECTURE.md`,
  `_bmad-output/project-context.md`, `docs/agent-writing-rules.md`, this story file,
  `sprint-status.yaml`.
- No conflicts with the unified structure: `lore/` holds pure rules, `app/` the UI
  call site.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 5.6; FR26 (with the 2026-09-24 note)]
- [Source: _bmad-output/implementation-artifacts/2-17-promote-a-simple-entity-to-an-entity-folder.md — Non-goals (the `frank.ru/frank.ru.md` result this story reverses), Review Findings (guard + re-entrancy decisions)]
- [Source: _bmad-output/implementation-artifacts/5-1-preserve-image-paths-when-promoting-an-entity-to-a-folder.md — rewrite ordering and the pure-`lore/`-helper precedent]
- [Source: apps/mobile/lib/app/category_entities_page.dart — `_promoteEntity`, `_showPromoteConfirmDialog`]
- [Source: apps/mobile/lib/lore/lore_loader.dart — `_langRe`, `_walkCategory` card candidates (`index.md`, `<folder>.md`), `_buildNode` card skip]
- [Source: apps/mobile/test/app/promote_entity_test.dart; apps/mobile/test/fakes.dart — `ensureDir`/`movePath`/`_addSibling`/`exists`]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md — AD-3, AD-4, AD-8, AD-9, AD-10, AD-12]
- [Source: _bmad-output/project-context.md — Entity resolution; Testing emphasis]
- [Source: docs/agent-writing-rules.md — §2.2, §2.5, §3, §4]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

## Change Log

- 2026-09-24: Story created from KseiPo's 2026-09-24 decision (folders never carry a language suffix). Ultimate context engine analysis completed; comprehensive developer guide created.
