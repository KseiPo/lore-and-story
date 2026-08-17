---
baseline_commit: 125a625
---

# Story 5.1: Preserve image paths when promoting an entity to a folder

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want image references inside a promoted card to keep pointing at the right file,
so that promoting an entity to hold events doesn't silently break its illustrations.

## Context

**Two shipped stories interact badly, and neither's review caught it.** Story 2.17
(`_promoteEntity`, `apps/mobile/lib/app/category_entities_page.dart:147-201`) moves
`<slug>.md` → `<slug>/<slug>.md` via `RepoStorage.movePath` — a pure filesystem
rename, deliberately with **no content rewriting**, to keep the card's bytes
byte-exact (AD-4). Story 2.16 (`_resolveImage`,
`apps/mobile/lib/app/markdown_preview.dart:519-542`) resolves an `![alt](src)`
image path **relative to the file's current directory, recomputed fresh on every
render** — there is no stored absolute path to fall back on. Moving the card one
directory level deeper without adjusting `src` silently breaks any relative
reference that resolved correctly before the move: `media/frank.jpg` (which lived
at `characters/media/frank.jpg` when the card was at `characters/frank.md`) now
resolves to the nonexistent `characters/frank/media/frank.jpg`. The image just
degrades to its alt-text placeholder — Story 2.16's own AD-8 "never crash" handling
(`_image`, `markdown_preview.dart:486-496`) makes this failure invisible instead of
surfacing it. `apps/mobile/test/app/promote_entity_test.dart` has zero coverage of
this interaction.

**The fix is a one-directional compensation, not a general path resolver.**
Promotion always adds exactly one directory level (`<slug>.md` → `<slug>/<slug>.md`),
so for every **relative** local image `src`, prepending `../` exactly compensates —
regardless of the src's own shape (`media/x.jpg` → `../media/x.jpg`; an
already-`../`-relative src like `../shared/logo.png` → `../../shared/logo.png`;
a subfolder-relative src like `media/portraits/x.jpg` →
`../media/portraits/x.jpg`). No `.`/`..` segment resolution is needed on the write
side — that logic already exists, purely for *reading*, in `_resolveImage`.

**Surgical, not a re-serialize — this is the load-bearing constraint.** Writes to
the user's story repo must be byte-exact except the intended change (AD-4; also
stated project-wide: "Writes to the user's story repo are SURGICAL — byte-exact
except the intended change"). Do **not** round-trip the card through
`package:markdown`'s AST and reprint it — that would reformat everything, not just
the image `src`s. The rewrite must be a targeted substring replace of just the
`src` inside each recognized `![alt](src)` (optionally `![alt](src "title")`),
leaving every other byte — including any image markup a simple scan doesn't
recognize — untouched.

**Reuse `entry.text`, don't re-read the file.** `LoreEntry.text`
(`apps/mobile/lib/lore/lore_model.dart:84`) is already the card's raw, freshly-
loaded content — `_promoteEntity(LoreEntry entry)` already has it in hand. No new
`storage.read` call is needed or wanted.

**Also confirmed by tracing, not assumed:** Story 2.18's rename
(`undetermined_language_page.dart:178`'s `widget.storage.movePath(oldPath, newPath)`,
e.g. `frank.md` → `frank.ru.md`) is a **same-directory** rename — it does not
change the resolving directory for any relative image reference, so it is
genuinely unaffected by this bug class. Verify this during implementation (Task 4)
rather than re-deriving it from scratch; no code change is expected there.

## Acceptance Criteria

1. **(Core fix)** Given a card being promoted contains one or more relative local
   image references (`![alt](src)`, not `http(s)://`), **when** promotion runs,
   **then** those references are rewritten so they still resolve to the same image
   file after the move (e.g. `media/frank.jpg` → `../media/frank.jpg`) — verified by
   actually rendering the promoted card's preview and confirming the image loads,
   not just by string-diffing the rewritten markdown.
2. **(No false positives)** Given a card with no image references, or only
   already-correct/absolute/network (`http(s)://`) references, **when** promotion
   runs, **then** the file content is unchanged apart from the rewritten relative
   paths — network and absolute (leading `/`, or a Windows drive letter like `C:\`)
   references are left untouched, and a card with nothing to rewrite ends up
   byte-for-byte identical to today (no extra write call at all).
3. **(Never breaks the move)** Given a card whose image markup is malformed or
   unparseable, **when** promotion runs, **then** the move still completes (a
   rewrite failure never blocks promotion) and any reference that couldn't be
   safely rewritten is left as-is rather than corrupted. *(AD-8/NFR7)*
4. **(Regression coverage)** Given the existing Story 2.17 promotion tests, **when**
   this story ships, **then** they stay green, and new tests cover: a card with one
   image reference promotes and still resolves; a card with multiple image
   references (including one already `../`-relative, and one pointing into a
   subfolder) promotes correctly; a card with no images promotes unchanged (today's
   behavior preserved byte-for-byte).

**Non-goals** (explicitly out of scope):
- Reference-style images (`![alt][ref]`) — not rewritten; left untouched like any
  other markup the scan doesn't recognize (AC3 covers this as "unparseable").
- Rewriting anything inside a promoted entity's **sub-entries** — promotion
  (Story 2.17) only ever moves the one card file; sub-entries don't exist yet at
  promotion time (a simple entity has none).
- Story 2.18's bare-`.md` language-assignment rename — confirmed unaffected
  (Context, above); Task 4 only verifies this, it does not change that code path.
- A general `.`/`..`-aware path resolver on the write side — the fix only ever
  needs to compensate for exactly one added directory level (`../` prepend), not
  resolve arbitrary relative paths.

## Tasks / Subtasks

- [x] **Task 1: Add a pure, total image-path rewriter** (AC: 1, 2, 3)
  - [x] 1.1 New file `apps/mobile/lib/lore/image_path_rewriter.dart` — pure Dart,
    no Flutter/`dart:io` imports (AD-9; matches `convention_matcher.dart`'s own
    `library;` + doc-comment shape). Export
    `String rewriteRelativeImagePaths(String content)`.
  - [x] 1.2 Scan `content` for markdown image syntax `![alt](src)` /
    `![alt](src "title")` with a targeted regex (alt text: no `]`/newline; src: no
    unescaped whitespace/parens) — do **not** parse via `package:markdown` and
    reprint (see Context: surgical/byte-exact, AD-4). For each match, splice only
    the `src` substring in place (use `RegExpMatch.start(1)`/`.end(1)` on the src
    capture group to get exact offsets; copy everything else through unchanged) —
    build the result with a `StringBuffer`, never a full re-render.
  - [x] 1.3 A `src` needs rewriting unless it's a network URL
    (`http://`/`https://`, case-insensitive) or filesystem-absolute (leading `/`,
    or matches `^[A-Za-z]:[\\/]` for a Windows drive letter) — those are left
    byte-identical. Every other `src` gets `../` prepended verbatim (no `.`/`..`
    segment resolution needed — see Context). Handle the optional CommonMark
    `<src>` angle-bracket wrapper by rewriting the inner path and re-wrapping.
  - [x] 1.4 Wrap the whole function body in `try`/`catch` returning `content`
    unchanged on any exception (AD-8, belt-and-suspenders on top of 1.2's targeted
    matching already being total by construction — mirrors
    `convention_matcher.dart`'s "never throws" doc-comment pattern).
  - [x] 1.5 Add `export 'image_path_rewriter.dart';` to the `lore/` barrel
    (`apps/mobile/lib/lore/lore.dart:9-14`), alphabetically among the existing
    exports.
  - [x] 1.6 New `apps/mobile/test/lore/image_path_rewriter_test.dart` (pure unit
    tests, no widget pump needed): a single relative `src` gets `../` prepended;
    an already-`../`-relative `src` gets a second `../` prepended; a
    subfolder-relative `src` (`media/portraits/x.jpg`) is rewritten correctly; an
    `http(s)://` src is untouched; a leading-`/`-absolute and a `C:\`-style src are
    untouched; content with no images returns unchanged (assert `identical` or
    plain `==`); malformed markup (e.g. an unterminated `![alt](media/x.jpg` with
    no closing paren) returns unchanged, never throws; multiple images in one
    document are each rewritten independently and everything between/around them
    (headings, prose, non-image brackets) is byte-for-byte preserved.
    *(Impl note: rather than splicing at the src capture group's own offsets —
    `Match`/`RegExpMatch` in Dart's `dart:core` has no `start(group)`/`end(group)`,
    only whole-match `start`/`end` — the regex captures alt and the whole
    src(+title) tail as two groups, and each match is replaced whole via
    `match.start`/`match.end`, reassembled from the (possibly rewritten) parts.
    Same surgical/byte-exact result, just built differently than originally
    sketched.)*

- [x] **Task 2: Wire the rewrite into promotion** (AC: 1, 2, 3)
  - [x] 2.1 In `_promoteEntity` (`apps/mobile/lib/app/category_entities_page.dart:147-201`),
    compute `final rewrittenText = rewriteRelativeImagePaths(entry.text);` up
    front — reuse the already-loaded `entry.text` (`LoreEntry.text`,
    `lib/lore/lore_model.dart:84`); do **not** add a new `storage.read(cardPath)`
    call.
  - [x] 2.2 Leave the existing `exists` pre-flight check, `ensureDir`, and
    `movePath` call (lines 171-195) exactly as they are — the move itself must
    stay a pure rename for the byte-exact/no-rewrite case (AC2) and must complete
    even when the rewrite can't (AC3).
  - [x] 2.3 Immediately after `movePath` succeeds, only if
    `rewrittenText != entry.text`: call
    `await widget.storage.writeAtomic(newCardPath, rewrittenText);` inside its own
    `try`/`catch` that **swallows any failure silently** — the move already
    succeeded at that point, so a write failure here must never surface as "Failed
    to promote this entity." (matches AC3's "rewrite failure never blocks
    promotion" — this covers a write-time failure, not just an unparseable-markup
    case, which Task 1 already handles by leaving content unchanged).
  - [x] 2.4 Do not touch the `RepoStorageException`/generic `catch` blocks that
    already wrap the exists/ensureDir/movePath sequence (lines 181-195) — those
    stay scoped to the move itself, per 2.2.

- [x] **Task 3: Tests in `apps/mobile/test/app/promote_entity_test.dart`** (AC: 4)
  - [x] 3.1 **Full end-to-end image-loads assertion (AC1's explicit requirement).**
    Extend the existing "after a successful promotion, tapping the row opens the
    detail-tree outline" test (lines 260-277) or add a sibling test: seed
    `characters/frank.md` = `'# Frank\n\n![Frank](media/frank.jpg)\n'` and
    `fileBytes: {'characters/media/frank.jpg': validPngFixture}` (import
    `validPngFixture` from `test/app/test_image_fixtures.dart`, the existing
    shared 1×1 PNG fixture already used by `markdown_preview_test.dart` and
    `entity_detail_page_test.dart`). Promote, then tap the row to open
    `EntityDetailPage` (its card preview already wires
    `MarkdownPreview(text: entry.text, storage:, filePath:)`,
    `entity_detail_page.dart:284-294`), `pumpAndSettle()`, and assert
    `find.byType(Image)` finds one widget — proving the image resolves post-move,
    not just that the markdown string changed.
  - [x] 3.2 A card with multiple image references — one plain relative
    (`media/x.jpg`), one already `../`-relative, one subfolder-relative
    (`media/sub/y.jpg`) — promotes correctly: assert on
    `await storage.read('characters/frank/frank.md')` that each `src` gained
    exactly one `../` and nothing else in the file changed.
  - [x] 3.3 A card with **no** image references promotes with content unchanged
    byte-for-byte (existing `_repo()` fixture, `'# Frank\n'`, already covers this
    — additionally assert `storage.writeCalls` stays **empty** for this case,
    proving no extra write happens when there's nothing to rewrite).
  - [x] 3.4 A card with malformed/unparseable image markup (e.g.
    `'# Frank\n\n![broken](media/x.jpg\n'`, no closing paren) still promotes
    successfully (move completes, no exception, no error snackbar) with the file
    content otherwise unchanged.
  - [x] 3.5 Run the full existing `promote_entity_test.dart` suite — all current
    tests (collision guard, orphaned-folder retry, move-failure rollback,
    double-tap guard, detail-tree navigation) must stay green unmodified.
    *(Also added a fifth new test beyond the plan: network/absolute references
    are left untouched with no extra write — direct AC2 coverage.)*

- [x] **Task 4: Verify Story 2.18 is unaffected (investigation, not a fix)** (AC: none — closes the epic's open question)
  - [x] 4.1 Confirm `apps/mobile/lib/app/undetermined_language_page.dart:178`'s
    `movePath(oldPath, newPath)` (e.g. `frank.md` → `frank.ru.md`) is always a
    same-directory rename — grep/read the surrounding function to confirm neither
    `oldPath` nor `newPath` ever differs in directory. If confirmed (expected), no
    code change is needed there; record the finding in this story's Completion
    Notes so the epic's open question is closed, not silently dropped.
    **Confirmed:** both `oldPath`/`newPath` are `_repoPath(...)` applied to
    `orig.file`/`newFile` (lines 166-168); `newFile` is derived from `orig.file`
    by replacing only its trailing `.md` suffix with `.$lang.md`
    (`'${orig.file.substring(0, orig.file.length - 3)}.$lang.md'`) — no path
    segment before the filename is ever touched, so the resolving directory is
    identical before and after. Story 2.18 is genuinely unaffected; no code
    change made.

- [x] **Task 5: Final verification**
  - [x] 5.1 `flutter test` — full suite green (Flutter at `C:\programs\flutter\bin`,
    not on PATH — invoke via PowerShell with a PATH prefix). Result: 751 tests
    passed, 0 failures.
  - [x] 5.2 `flutter analyze` clean. Result: "No issues found!"

## Dev Notes

- **Architecture fit:** AD-4 (every write atomic + byte-exact — the rewrite is a
  targeted splice, never a re-serialize) and AD-8 (parsing/rewriting total, never
  throws — a rewrite failure degrades to "leave unchanged," never blocks the move)
  are the two binding decisions here. AD-3 (`RepoStorage` is the only filesystem
  seam) is already satisfied — this story adds one more `writeAtomic` call, no new
  I/O path. AD-9 (model purity per-slice) governs Task 1: the rewriter is pure
  Dart in `lore/`, no Flutter/`dart:io`, exactly like `convention_matcher.dart`.
- **Do not reinvent `_resolveImage`'s `.`/`..` walk** (`markdown_preview.dart:519-542`)
  — that logic is for *reading* (resolving a src against a directory at render
  time) and is unrelated to this story's *writing* concern (compensating for one
  added directory level). The two are deliberately asymmetric: reading needs full
  segment resolution because it must handle whatever a human wrote; writing only
  ever needs a single `../` prepend because promotion's directory-depth delta is
  always exactly +1.
- **`entry.text` is already fresh** — `_promoteEntity` receives the tapped
  `LoreEntry` from the category list's tap-time snapshot, which already carries
  the card's raw text (`lore_model.dart:84`). Do not add a new `storage.read`
  call; that would be redundant I/O and a second place that could fail
  independently of the `movePath` the rest of the function already guards.
- **Testing standards:** cover business logic well (the pure rewriter, Task 1.6)
  and the data-safety path (promotion must never corrupt or lose content, Tasks
  3.2-3.4) — this project's stated testing emphasis. The AC1 rendering assertion
  (Task 3.1) is the one place a "does it actually work" UI-level check is
  warranted, because AC1 explicitly requires it ("not just string-diffing") —
  don't skip it as "just a UI test."

### Project Structure Notes

- New files: `apps/mobile/lib/lore/image_path_rewriter.dart`,
  `apps/mobile/test/lore/image_path_rewriter_test.dart`.
- Modified files: `apps/mobile/lib/lore/lore.dart` (barrel export),
  `apps/mobile/lib/app/category_entities_page.dart` (`_promoteEntity`),
  `apps/mobile/test/app/promote_entity_test.dart` (new + extended tests).
- No new files touched outside `lore/`/`app/`/their tests — fits the existing
  slice boundaries exactly (AD-12); no conflicts with the unified project
  structure.

### References

- [Source: apps/mobile/lib/app/category_entities_page.dart#L147-201] — `_promoteEntity`, the function this story extends.
- [Source: apps/mobile/lib/app/markdown_preview.dart#L486-542] — `_image`/`_resolveImage`, the read-side resolution this story's write-side fix must stay compatible with.
- [Source: apps/mobile/lib/lore/lore_model.dart#L65-103] — `LoreEntry`, specifically `.text` (L84) and `.id` (L67).
- [Source: apps/mobile/lib/lore/convention_matcher.dart#L1-12] — the pure, total, `library;`-doc-commented shape to mirror for the new rewriter file.
- [Source: apps/mobile/lib/lore/lore.dart] — the `lore/` barrel to extend.
- [Source: apps/mobile/lib/storage/repo_storage.dart#L91-125] — `read`/`writeAtomic`/`movePath` contracts (byte-exact, total-except-missing-file, atomic-rename).
- [Source: apps/mobile/test/app/promote_entity_test.dart] — existing promotion test suite (AC4: must stay green) and its `_repo()`/`_pumpReady`/`_navigateToCategory` helpers to reuse.
- [Source: apps/mobile/test/app/markdown_preview_test.dart#L130-154] — the `pumpPreviewWithStorage` + `validPngFixture` pattern for asserting an image actually loads.
- [Source: apps/mobile/test/app/test_image_fixtures.dart] — shared `validPngFixture` (1×1 PNG) to reuse, not re-embed.
- [Source: apps/mobile/lib/app/entity_detail_page.dart#L276-294] — the card preview (`MarkdownPreview` with `storage`/`filePath`) Task 3.1's end-to-end test navigates to.
- [Source: apps/mobile/lib/app/undetermined_language_page.dart#L178] — Story 2.18's same-directory rename, to verify (Task 4) not fix.
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-3, AD-4, AD-8, AD-9] — the architecture decisions this story must comply with.
- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.1] — the epic-level acceptance criteria this story file expands on.

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

- `flutter test test/lore/image_path_rewriter_test.dart` — red before Task 1's implementation existed (compile error: `Method not found: 'rewriteRelativeImagePaths'`), green after (12/12).
- `flutter test test/app/promote_entity_test.dart` — red on the two new image-rewrite assertions before Task 2's wiring (string-diff mismatch: `media/frank.jpg` vs. expected `../media/frank.jpg`), green after (13/13, all prior tests unmodified and still passing).
- `flutter test` (full suite) — 751 passed, 0 failures.
- `flutter analyze` — "No issues found!"

### Completion Notes List

- Implemented `rewriteRelativeImagePaths` (`lib/lore/image_path_rewriter.dart`) as planned, with one deviation from the sketched approach: Dart's `Match`/`RegExpMatch` has no `start(group)`/`end(group)` API (only whole-match `start`/`end`) — confirmed by reading the SDK source (`dart-sdk/lib/core/pattern.dart`, `regexp.dart`) after the originally-planned per-group-offset splice failed to compile. Reworked to capture alt text and the whole src(+title) tail as two groups, rewrite the tail as a string, and replace each whole match via `match.start`/`match.end` — same surgical, byte-exact-except-image-srcs result, different construction. Documented inline (file doc comment) and in Task 1.6's note.
- `_promoteEntity` (`category_entities_page.dart`) now computes the rewrite from the already-loaded `entry.text` before the move, and only issues an extra `writeAtomic` after `movePath` succeeds and only when content actually changed — the no-image case stays a pure move with zero extra writes, matching AC2 exactly (verified: `storage.writeCalls` stays empty for that case).
- Story 2.18 (`undetermined_language_page.dart:178`) confirmed unaffected by tracing `oldPath`/`newPath` construction — see Task 4.1's note. No code change made there.
- All 4 acceptance criteria verified by test: AC1 via a full end-to-end render assertion (promote → navigate to `EntityDetailPage` → `find.byType(Image)` finds one widget, not just a string diff), AC2 via both the "no images → no extra write" and "network/absolute untouched → no extra write" tests, AC3 via the malformed-markup test (move still completes, content left as-is), AC4 via the multi-image rewrite test plus the full existing regression suite staying green.

### File List

- `apps/mobile/lib/lore/image_path_rewriter.dart` (new)
- `apps/mobile/lib/lore/lore.dart` (modified — barrel export)
- `apps/mobile/lib/app/category_entities_page.dart` (modified — `_promoteEntity`)
- `apps/mobile/test/lore/image_path_rewriter_test.dart` (new)
- `apps/mobile/test/app/promote_entity_test.dart` (modified — new test group + one assertion added to an existing test)

## Change Log

- 2026-08-17 — Implemented Story 5.1: added a pure `rewriteRelativeImagePaths` helper and wired it into entity promotion so relative local image references keep resolving after a card moves one directory level deeper. Verified Story 2.18's rename is unaffected (same-directory, no fix needed). Full suite green, `flutter analyze` clean.
- 2026-08-17 — Code review (medium effort, 8 angles: correctness, reuse, simplification, efficiency, altitude, conventions): zero findings. Marked done.
