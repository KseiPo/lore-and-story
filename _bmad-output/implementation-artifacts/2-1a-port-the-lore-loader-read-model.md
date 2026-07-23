---
baseline_commit: eef3327
---

# Story 2.1a: Port the lore loader (read-model)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the app to parse my lore folder into the entity model,
so that everything I've written is available to browse.

## Acceptance Criteria

1. **AC1 (NFR2 — fixture conformance):** Given my `loreDir`, when the loader parses it, then it produces the entity model — simple entities and entity folders with `{overview, items, children}` trees, `category` = path, `readTitleAliases` for title + aliases, language pairs merged (`"<ru> — <en>"`) — **conformant to the shared golden fixtures** in `test/fixtures/lore-model/`.
2. **AC2 (ARCHITECTURE §3.2 — card excluded):** Given an entity folder, when the model is built, then the card is **not** listed among its own `children[]`.
3. **AC3 (all four fixture cases pass):** Given each case under `test/fixtures/lore-model/cases/`, when the Dart loader's output is normalized by the Dart port of `normalize.js`, then it **deep-equals** that case's `expected.json` — byte-for-byte on `textSha`, exactly on ordering.
4. **AC4 (seam + purity):** Given the loader, when it reads files, then it goes through the `RepoStorage` port only — no `dart:io` in the `lore/` slice (AD-3 / AD-9).
5. **AC5 (hygiene):** `flutter analyze` clean; `flutter test` passes including the new fixture-conformance tests.

## Tasks / Subtasks

- [x] **Task 1 — Pure model types in the `lore/` slice (AC: 1, 4)**
  - [x] Create `apps/mobile/lib/lore/lore_model.dart` with pure, immutable types mirroring the reference model exactly: `LoreEntry`, `LoreNode`, `LoreItem`, `LoreLang`, `LoreOverview`, `LoreChild`. Field names/shape per the contract table in Dev Notes — do not "improve" the shape; it is pinned by the fixtures.
  - [x] Types are pure Dart: `dart:convert` at most, **no `dart:io`, no Flutter**.
  - [x] Note: the reference model's `file` (absolute path) is **dropped by `normalize`**, so the Dart model does not need it at all — `id`/`relDir`/`langs[].file` are all loreDir-relative and are what the fixtures pin.
- [x] **Task 2 — `readTitleAliases`, `prettify`, `passageOf` (AC: 1, 3)**
  - [x] `readTitleAliases(String text, String fallback) -> ({String title, List<String> aliases})`: title from the first `^#\s+(.+)$` (multiline) **trimmed**, else `fallback`; aliases from `^aliases:\s*(.+)$` (multiline, case-insensitive) split on `,` and trimmed; result is `[title, ...aliasParts]` with empties removed and **deduped preserving first-seen order** (JS `[...new Set(...)]` semantics).
  - [x] `prettify(String seg)`: replace `[-_]` with a space, then uppercase the first character if it is a word char (`[A-Za-z0-9_]`). `events` → `Events`; `relationship-quest-1` → `Relationship quest 1`.
  - [x] `passageOf(String text)`: first capture of `scene ⇄ passage:\s*"([^"]+)"` (note the literal `⇄`, U+21C4) or `null`. **This is required despite the addendum deferring it** — see the Dev Note "The addendum and the fixtures disagree".
- [x] **Task 3 — `buildNode` (the content tree) (AC: 1, 2, 3)**
  - [x] Port `buildNode(dir, cardBase, groupPath, flat)` faithfully — see the annotated algorithm in Dev Notes. Skip `media/` subdirectories; consider only `.md` files.
  - [x] Group files by base slug, collecting `ru`/`en`/`orig` language variants via `\.(ru|en)\.md$` (case-insensitive).
  - [x] **The card-exclusion guard (AC2):** push a file into `flat` (the entity's `children[]`) **only when `base != cardBase`**. This is the exact line the fixtures pin; getting it wrong is the documented historical bug.
  - [x] Folder card (`base == node.name || base == 'index'`) becomes `overview` and sets `node.title` — unless it *is* the entity card (`base == cardBase`), which the caller owns and which must be skipped entirely.
  - [x] Item title: `ru` **and** `en` present → `"${ru.title} — ${en.title}"` (spaced **em dash** U+2014); otherwise the primary's title, where primary = `orig ?? ru ?? en`. Item `passage` comes from `ru ?? en ?? orig`.
  - [x] Item `id` = `groupPath.isEmpty ? base : '$groupPath/$base'`; `group` = `groupPath` (empty string at the entity root, not null).
  - [x] Recurse into sorted subdirectories, extending `groupPath`.
- [x] **Task 4 — `walkCategory` / `makeEntry` / `loadLore` over the port (AC: 1, 4)**
  - [x] `loadLore(RepoStorage storage, String loreDir) -> Future<List<LoreEntry>>`. Depends **only** on the port (AC4). If `loreDir` doesn't exist, return `[]`.
  - [x] `walkCategory`: for each child of a directory — a subdirectory named `media` is skipped; a subdirectory containing `index.md` **or** `<folder-name>.md` yields an entity (that file is the card, the folder is its tree root); a subdirectory **without** either is a nested *category* and is descended into, extending the category path; a `.md` file is a simple entity.
  - [x] `category` is the path under `loreDir`; **top-level files get `'general'`** (the reference's `category || 'general'` falsiness on the empty string). Nested categories join with `/` (e.g. `characters/secondary`).
  - [x] `makeEntry`: `id` = loreDir-relative card path; `relDir` = loreDir-relative dir, or `'.'` when empty; `tree` = `buildNode(...)` for entity folders, `null` for simple entities; `children` = the `flat` list buildNode fills.
  - [x] **IDs are loreDir-relative and forward-slash normalized.** `RepoStorage` yields repo-relative paths (e.g. `lore/characters/frank.md`); the loader must strip the `loreDir` prefix to produce `characters/frank.md`.
- [x] **Task 5 — Dart port of `normalize.js` (test-side) (AC: 3)**
  - [x] Create `apps/mobile/test/lore/normalize.dart` reproducing `test/fixtures/lore-model/normalize.js` exactly: drop `file`; `text` → `textSha` = **first 16 hex chars of the UTF-8 sha256**; `langs` map key-sorted; entries sorted by `id`; `passage` null-defaulted.
  - [x] Add `crypto` to **`dev_dependencies` only** — sha256 is needed by the *test normalizer*, never by production code. Keep the app's runtime dependency set unchanged.
- [x] **Task 6 — Fixture-conformance tests (AC: 3, 5)**
  - [x] Create `apps/mobile/test/lore/lore_model_fixtures_test.dart`: discover every case directory under `../../test/fixtures/lore-model/cases` (repo-root fixtures — Flutter tests run with CWD = `apps/mobile`), run `loadLore` via `AllFilesRepoStorage(caseDir)` with `loreDir: 'lore'`, normalize, and deep-compare to that case's `expected.json`.
  - [x] Fail loudly if **no** case directories are found (mirrors the JS runner's `assert.ok(cases.length > 0)`) — an empty glob must not look like a pass.
  - [x] Compare parsed JSON structures (decode `expected.json` and the normalized output to `Map`/`List`) so failures show a structural diff rather than a string mismatch.
  - [x] `flutter analyze` clean; `flutter test` green.

### Review Findings

> **Toolchain note (resolved):** the local Flutter install used during implementation was emptied mid-review, blocking verification. KseiPo reinstalled Flutter globally to `C:\programs\flutter\bin` (Flutter 3.44.7, Dart 3.12.2 — same Dart as before). The 3 patches below were then applied and **verified**: all 4 golden fixtures still conform, `npm test` (JS reference) still 4/4, `flutter analyze` clean, `flutter test` **92 passing** (88 → +4).

- [x] [Review][Patch] **A directory named `index.md` or `<name>.md` aborts the entire load (AD-8 violation)** — the entity-card probe uses `storage.exists(candidate)`, which is true for directories too. A folder containing a *subdirectory* literally named `index.md` (or `<foldername>.md`) is then treated as having a card, `makeEntry` calls `storage.read()` on the directory, `read` throws `RepoStorageException`, and it propagates out of `loadLore`, aborting the whole walk. AD-8 requires malformed input to degrade, never crash the walk. Fix: the card probe must resolve to a **file** (check the subdir's `listDir` for a non-directory entry), and/or guard per-entity reads so a single failure skips that entity rather than aborting. [apps/mobile/lib/lore/lore_loader.dart — `_walkCategory` card probe + `_makeEntry`]
- [x] [Review][Patch] **The CR/`.trim()` justification comment is likely factually wrong** — it states "Dart's `.` matches `\r` (JS's does not)". Dart `RegExp` follows ECMAScript, where `.` does **not** match `\r` without `dotAll` — so the claim is almost certainly false (could not run the probe to confirm; the toolchain vanished). The `.trim()` is still correct and worth keeping, but reword the comment to justify it defensively without asserting a specific (wrong) `.`-vs-`\r` behavior. Add a blank/whitespace CRLF-heading test (`# \r\n`) — the only input that distinguishes the two interpretations — to pin actual behavior. [apps/mobile/lib/lore/lore_loader.dart readTitleAliases doc + lore_model.dart doc; + a new case in lore_loader_test.dart]
- [x] [Review][Patch] **Top-level `category: 'general'` is asserted only by code inspection** — every fixture entity lives under `characters/…`, so the `category.isEmpty ? 'general'` fallback (a card sitting directly in `loreDir`) is never pinned. The code is correct; add a Dart-only unit test (temp dir with a card at the lore root) asserting `category == 'general'`. Do **not** add a shared fixture case — that would touch the contract. [apps/mobile/test/lore/ — new test]
- [x] [Review][Resolved] **`children[]` ordering — RESOLVED via contract fix (KseiPo's call: "fix lore.js and add proper sorting").** `lib/lore.js` now sorts a folder's files by name before flattening, matching the Dart port, so `children[]` is deterministic in both implementations and no longer depends on `readdir` order. The fixture README now documents `children[]` as order-stable. Regenerating the goldens produced **no `children[]` reorder** (they were already alphabetical), confirming the fix changed guarantees, not output. [lib/lore.js; test/fixtures/lore-model/README.md]
- [x] [Review][Defer] **`localeCompare` (reference) vs `compareTo` (port) for entries and `langs` keys** — agree for every current fixture id (lowercase ASCII + `/ . -`) and the fixed `ru/en/orig` key set; already self-documented at the sort sites. Revisit if a fixture ever introduces mixed-case or Cyrillic ids/keys. [apps/mobile/test/lore/normalize.dart]
- [x] [Review][Resolved] **`prettify` capitalization — RESOLVED via contract fix (KseiPo's call: "we don't need to capitalize anything").** `prettify` now only replaces `-`/`_` with spaces and never changes case, in both `lib/lore.js` and the Dart port. Goldens regenerated: node titles `Events`→`events`, `Quests`→`quests` (3 lines total); overview-card titles from `# headings` are unaffected. README updated. [lib/lore.js; apps/mobile/lib/lore/lore_loader.dart]
- [x] [Review][Defer] **Malformed-UTF-8 U+FFFD substitution granularity may differ (Node/V8 vs Dart)** — both substitute replacement chars, but the count/placement per invalid run can differ, so `textSha` could diverge for *corrupt* files. Latent: real files are well-formed and fixtures are clean. [apps/mobile/lib/storage/all_files_repo_storage.dart:54]
- [x] [Review][Defer] **Defensive divergences unreachable from current callers** — `loadLore('')` walks the repo root where JS returns `[]`; `_rel` returns the full path on a non-prefixed input where JS would emit `../`; `_normalizeDir` strips `.`/empty but not `..` (storage strips `..` too). All unreachable because callers always pass `loreDir = 'lore'` (or a config default), but the two normalization routines disagreeing is a latent trap. [apps/mobile/lib/lore/lore_loader.dart]

## Dev Notes

### What this story is

The **Dart port of the read-model** — the first half of AD-2's "one contract, two
conformant implementations." Everything Epic 2 browses (categories, entities,
entity trees, RU/EN pairs) is produced by this loader. Its correctness is not a
matter of opinion: `test/fixtures/lore-model/` **is** the contract, and this story
is done when the Dart output deep-equals all four goldens.

Scope is the **read model only**. Out of scope here: the syncer-aware walk
(`.st*` filtering, conflict-copy surfacing) — that is **Story 2.1b**, deliberately
the next story; browse UI (2.2/2.3); the convention matcher (2.5). Also out of
scope permanently for v0.1: `findMentions` / `buildLoreGraph` (v0.2+, and absent
from `normalize`, so no fixture requires them).

### ⚠️ The addendum and the fixtures disagree — the fixtures win

`addendum.md` §E's port-scope table says **`passageOf` — "Defer — bridge only"**.
But `normalize.js` emits `passage` on every item, and the goldens pin real values
(`"passage": "Mira - Dream"` in `04-language-pairs`, 4 occurrences in
`03-sub-entry-tree`). **A port without `passageOf` cannot pass AC3.**

Per **AD-2** the fixtures are authoritative over prose ("Neither implementation is
authoritative over the other — the fixtures are"), and the fixture README is
blunter: "Prose docs describe the contract; **these files pin it.**" So implement
`passageOf` as a small extractor feeding the model's `passage` field. What stays
deferred is the *scene↔passage bridge feature* — extraction ≠ bridge.

### The exact contract (do not improvise the shape)

**`LoreEntry`** — `id`, `title`, `aliases`, `category`, `relDir`, `text`, `tree` (nullable), `children`.
**`LoreNode`** — `name`, `title`, `overview` (nullable), `items`, `children` (nested nodes).
**`LoreOverview`** — `id`, `text`, `relDir`.
**`LoreItem`** — `id`, `title`, `group`, `passage` (nullable), `langs` (map `lang` → `LoreLang`).
**`LoreLang`** — `file` (loreDir-relative — the reference stores the *relative id* here, not the absolute path), `relDir`, `title`, `text`.
**`LoreChild`** (flat) — `id`, `title`, `group`, `text`.

Annotated reference algorithm (`lib/lore.js:34-130`) — port faithfully:

```
buildNode(dir, cardBase, groupPath, flat):
  node = { name: basename(dir),
           title: groupPath.isEmpty ? '' : prettify(basename(dir)),
           overview: null, items: [], children: [] }
  files   = *.md in dir            subdirs = dirs in dir except 'media'
  byBase[base].langs[lang] = { id, relDir, title, text, passage }
      lang = ru|en from /\.(ru|en)\.md$/i else 'orig';  base = name minus lang minus '.md'
      if (base != cardBase) flat.add({ id, title, group: groupPath, text })   // ← AC2
  for base in sorted(byBase.keys):
      if base == node.name || base == 'index':
          if base == cardBase: continue            // entity card: caller owns it
          v = orig ?? ru ?? en;  node.overview = {id,text,relDir}; node.title = v.title; continue
      primary = orig ?? ru ?? en
      title   = (ru != null && en != null) ? '${ru.title} — ${en.title}' : primary.title
      items.add({ id: groupPath.isEmpty ? base : '$groupPath/$base',
                  title, group: groupPath,
                  passage: (ru ?? en ?? orig).passage, langs: … })
  for sub in sorted(subdirs):
      children.add(buildNode(dir/sub, null, groupPath.isEmpty ? sub : '$groupPath/$sub', flat))
```

### 🪤 Ordering traps that will silently break conformance

1. **`children[]` order follows *file iteration* order, and `normalize` does NOT sort it.** In the reference, `flat.add` happens in the *first* loop over `files` — which is raw `readdirSync` order, not the sorted `byBase` loop. The goldens were generated where that order came out alphabetical (see `04`'s children: `dream.en`, `dream.ru`, `only-en`, `only-ru`, `plain`). Dart's `Directory.list()`/`listDir` gives **no ordering guarantee**. → **Sort the `.md` file list by name before the flat-push loop** so `children[]` is deterministic and matches. This is the single most likely cause of a mystifying near-miss diff.
2. **`normalize` sorts with `localeCompare`; Dart has `compareTo`.** `localeCompare` is locale-aware; `compareTo` is UTF-16 code-unit. For the current fixture ids (lowercase ASCII + `/` `.` `-`) they agree — verified across all four cases — so use `compareTo`. But if a future fixture introduces mixed case or unusual punctuation and ordering mismatches, **this is where to look.**
3. **`byBase` keys and subdirs use JS default `.sort()`** = code-unit order, which *is* Dart's `compareTo`. Safe.
4. **`walkCategory` does not sort** — entry order is iteration order, but `normalize` sorts entries by `id`, so it doesn't matter.

### 🪤 Regex portability (JS → Dart)

- `^#\s+(.+)$` with `m`: in JS, `.` excludes `\r` and `$` matches before it; in **Dart, `.` matches `\r`** and multiline `$` matches only before `\n`. On CRLF input Dart would capture a trailing `\r`. The reference `.trim()`s the title and each alias, which neutralizes it — **keep those trims**. The fixtures are LF-pinned (`.gitattributes` `* -text`), so this bites only on real CRLF repos.
- `^aliases:\s*(.+)$` needs **both** `multiLine: true` **and** `caseSensitive: false`.
- `scene ⇄ passage:\s*"([^"]+)"` contains a literal **U+21C4**; the em dash in merged titles is **U+2014** with spaces on both sides. Both are load-bearing for `textSha`/title equality — do not retype them from memory, copy them.
- Dedupe must preserve first-seen order (`LinkedHashSet`, which is Dart's default `Set` iteration order).

### The normalization projection (test-side mirror of `normalize.js`)

- `textSha` = **first 16 hex chars** of `sha256(utf8.encode(text))`. This is what pins UTF-8 decoding and line endings exactly — a port that mis-decodes Cyrillic or normalizes newlines fails here instead of silently corrupting files later. That is the fixtures' stated purpose.
- Drop `file` from entries; keep `langs[].file` (already relative).
- `overview` → `{id, relDir, textSha}`; entry → `{id, title, aliases, category, relDir, textSha, tree, children:[{id,title,group,textSha}]}`; `entries` sorted by `id`.

### Files being MODIFIED / created

- **NEW** `lib/lore/lore_model.dart`, `lib/lore/lore_loader.dart` (split as you see fit; keep both pure).
- **MODIFIED** `lib/lore/lore.dart` — export the new model + loader from the slice barrel (AD-12), alongside the existing `project_config.dart` export. **Preserve** that export.
- **MODIFIED** `apps/mobile/pubspec.yaml` — `crypto` under **`dev_dependencies`**, nothing added to runtime deps.
- **NEW** `test/lore/normalize.dart`, `test/lore/lore_model_fixtures_test.dart`.
- **Do NOT touch** `lib/lore.js`, `test/fixtures/**`, or `scripts/update-goldens.js`. A golden diff is a contract change and this story is a *conformance* exercise, not a contract change. If the Dart port cannot match a golden, the bug is in the port — investigate before ever regenerating.

### Architecture guardrails

- **AD-2 — fixtures are the contract.** Both implementations assert against `test/fixtures/lore-model/`; neither is authoritative over the other. Contract changes go fixtures-first. [ARCHITECTURE-SPINE.md#AD-2]
- **AD-3 / AD-9 — the seam.** The loader takes a `RepoStorage`; no `dart:io` anywhere in `lore/`. The fixture test may use `AllFilesRepoStorage` (that's the composition point) but the loader itself must not know it exists. [#AD-3, #AD-9]
- **AD-8 — total.** Malformed/unreadable content is data, not a fault: `read` is already best-effort UTF-8 and `listDir` degrades to `[]`. A file that fails to parse must not abort the walk. [#AD-8]
- **AD-12 — slice barrel.** Consumers import `lore/lore.dart`, not internal files. [#AD-12]
- **Identity contract** — IDs are forward-slash normalized even on Android, and here they are relative to **`loreDir`**, not the repo root. [ARCHITECTURE-SPINE.md#Consistency Conventions; project-context.md]

### Previous story intelligence (Epic 1 — all four done)

- `RepoStorage.read` is best-effort UTF-8 (never throws on malformed bytes) and **re-attaches a leading BOM**; it **throws `RepoStorageException` for a missing file**. A BOM'd card would put `U+FEFF` at the start of `text` and change its `textSha` — the fixtures have no BOM'd files, so this shouldn't bite, but it's why `read` behaves that way.
- `listDir` returns repo-relative, forward-slash `RepoEntry`s and degrades to `[]` for missing/unreadable dirs (never throws).
- **Browse filtering (`.st*`, `media/`) lives in `app/browse_filter.dart` and is UI-only.** The loader must **not** import it — `media/` skipping is part of the *loader's own* contract (the reference skips it) and must be implemented here independently; `.st*` filtering is Story 2.1b's job, not this story's.
- Test conventions: pure logic → plain unit tests; anything touching real files → `AllFilesRepoStorage` + a real directory (here, the fixture case dirs). Fakes live in `test/fakes.dart`.
- Every code review this epic-and-a-half has found a real bug; the highest-risk areas here are the two ordering traps above and the `base != cardBase` guard.

### Git intelligence

`eef3327` (Story 1.4, Epic 1 complete) → `fcf34a3` (1.3) → `d465b88` (1.2) → `ade0c11` (1.1). The storage seam, atomic writer, and config resolution this story builds on are all committed and reviewed.

### Library / version policy

One new **dev-only** dependency: `crypto` (Dart-team package) for sha256 in the test normalizer. Pin current stable at `flutter pub add --dev crypto`. No runtime dependency changes.

### Testing standards

- The four fixture cases are the primary assertion. Discover them dynamically (don't hardcode four names) and fail if none are found.
- Prefer structural comparison of decoded JSON so a diff is readable.
- Beyond fixtures, unit-test the pure helpers directly: `readTitleAliases` (heading present/absent → slug fallback, aliases line case-insensitive, dedupe keeps the title first), `prettify`, `passageOf` (present/absent).
- If a golden mismatches, **do not regenerate it** — diff the structure and fix the port.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 2 · Story 2.1a] — user story, ACs (NFR2)
- [Source: lib/lore.js:21-130] — the reference implementation being ported (`LANG_RE`, `readTitleAliases`, `prettify`, `passageOf`, `buildNode`, `makeEntry`, `walkCategory`)
- [Source: test/fixtures/lore-model/README.md] — what each case pins, the normalization contract, the `.gitattributes` byte warning, and the resolved card-in-own-children history
- [Source: test/fixtures/lore-model/normalize.js] — the exact projection to reproduce
- [Source: test/lore-model.test.js] — the JS runner whose structure the Dart test mirrors
- [Source: ARCHITECTURE.md §3.2] (entity resolution, card not a sub-entry of itself) and §3.4
- [Source: ARCHITECTURE-SPINE.md#AD-2, #AD-3, #AD-8, #AD-9, #AD-12]
- [Source: addendum.md §E] — port-scope table (**note the `passageOf` conflict resolved above**)
- [Source: _bmad-output/project-context.md] — forward-slash IDs, UTF-8/Cyrillic first-class, entity resolution rules

## Dev Agent Record

### Agent Model Used

claude-sonnet-5 (Claude Sonnet 5)

### Debug Log References

- `flutter analyze` → No issues found (one compile error fixed en route: the `library;` directive must precede imports, not follow them).
- **`flutter test test/lore/lore_model_fixtures_test.dart` → all 4 golden cases passed on the first run**, no golden regenerated and no fixture touched.
- `flutter test` (full) → **88 passing** (71 → +17: 6 fixture-suite tests + 11 helper unit tests).
- `npm test` (JS reference, cross-check) → **4/4 passing**. Both implementations now assert green against the *same* fixtures — AD-2 satisfied end to end.
- Seam check: no `dart:io` in `lib/lore/` (only doc comments stating its absence); `package:crypto` appears nowhere under `lib/`.

### Completion Notes List

- **The contract is met, not approximated.** All four goldens deep-equal, including `textSha` — which means the Dart port decodes UTF-8 (Cyrillic) and preserves line endings byte-identically to the JS reference. That is precisely what the fixtures exist to prove.
- **Both ordering traps flagged in the story were real and were handled up front**, which is why conformance passed first try:
  - `children[]` order follows the *file-iteration* loop and `normalize` does not sort it, so the `.md` file list is sorted by name before the flat-push. Verified against case 03's five-child ordering and case 04's five-child ordering.
  - `normalize.js` sorts with `localeCompare` while Dart has `compareTo`; they agree for every current fixture id, so `compareTo` is used, with the divergence documented at the sort site for whoever hits it later.
- **`passageOf` was implemented despite `addendum.md` §E deferring it** — the goldens pin `passage` in 8 places across cases 03/04, and AD-2 makes the fixtures authoritative over prose. The *scene↔passage bridge feature* remains deferred; extraction is not the bridge. This planning-doc conflict is called out in the story's Dev Notes rather than silently resolved.
- **AC2 (card excluded from its own `children[]`)** is enforced by the single `base != cardBase` guard on the flat-push and pinned by cases 02/03/04. This is the exact line whose absence caused the documented historical JS/doc disagreement.
- **Scope held.** No `.st*` filtering in the loader (that is Story 2.1b, deliberately next) and no `findMentions`/`buildLoreGraph` (v0.2+, absent from `normalize`, so no fixture needs them). `media/` skipping *is* implemented here because it is part of the loader's own contract, independent of the UI-level `app/browse_filter.dart`.
- **`crypto` is dev-only** — sha256 is needed by the test normalizer, never by production code; runtime dependencies are unchanged.
- Nothing under `lib/lore.js`, `test/fixtures/**`, or `scripts/update-goldens.js` was modified. A golden diff would have been a contract change; this story was a conformance exercise.

### File List

**Created:**
- `apps/mobile/lib/lore/lore_model.dart` (`LoreEntry`, `LoreNode`, `LoreOverview`, `LoreItem`, `LoreLang`, `LoreChild`)
- `apps/mobile/lib/lore/lore_loader.dart` (`loadLore`, `readTitleAliases`, `prettify`, `passageOf`, the `walkCategory`/`makeEntry`/`buildNode` port)
- `apps/mobile/test/lore/normalize.dart` (Dart port of `test/fixtures/lore-model/normalize.js`)
- `apps/mobile/test/lore/lore_model_fixtures_test.dart` (golden conformance, mirrors `test/lore-model.test.js`)
- `apps/mobile/test/lore/lore_loader_test.dart` (helper unit tests)

**Modified:**
- `apps/mobile/lib/lore/lore.dart` (barrel exports the model + loader alongside the existing `project_config.dart`)
- `apps/mobile/pubspec.yaml` (`crypto ^3.0.7` under `dev_dependencies`; runtime deps unchanged)

**Modified — shared contract (normally off-limits; changed under KseiPo-approved, fixtures-first contract decisions post-review):**
- `lib/lore.js` (sort files before flattening `children[]`; `prettify` no longer capitalizes)
- `test/fixtures/lore-model/cases/03-sub-entry-tree/expected.json`, `.../04-language-pairs/expected.json` (regenerated via `npm run goldens` — node title case only)
- `test/fixtures/lore-model/README.md` (documents `children[]` order-stable + prettify case-unchanged)

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-20 | Implemented Story 2.1a: ported the lore read-model to Dart over the `RepoStorage` port — entity/category walk, entity-folder cards (`index.md` / `<folder>.md`), nested section trees with overview cards, RU/EN language-pair merging (`"<ru> — <en>"`), `readTitleAliases`/`prettify`/`passageOf`, and the card-excluded-from-its-own-children guard. Added a Dart port of `normalize.js` plus a fixture-conformance suite mirroring the JS runner. **All 4 golden fixtures pass; the JS reference still passes the same 4** — AD-2's "one contract, two conformant implementations" is now real. Tests 71 → 88. analyze clean. No fixture or reference file touched. |
| 2026-07-20 | **Contract change (KseiPo-approved, fixtures-first):** (A) `lib/lore.js` now sorts a folder's files before building `children[]`, making the flat list deterministic in both implementations (README documents `children[]` as order-stable); regenerating the goldens showed **no reorder**, confirming it changes the guarantee not the output. (B) `prettify` no longer capitalizes — `-`/`_`→space only, case unchanged, in both `lib/lore.js` and the Dart port; goldens regenerated (node titles `Events`→`events`, `Quests`→`quests`). Both implementations re-verified: JS 4/4, Dart 92 passing, analyze clean. These resolve the two contract-level items deferred from the review. |
| 2026-07-20 | Addressed code review (Sonnet 5 impl, 3 parallel layers): 3 patch findings fixed. **AD-8 robustness:** the entity-card probe used `exists()` (true for directories too), so a folder containing a subdirectory named `index.md`/`<name>.md` would `read()` a directory, throw, and abort the whole load (the JS reference shares this latent bug); the probe now resolves the card from the directory's own file listing, and per-entity/sub-entry reads are guarded so a single failure skips that entity rather than crashing the walk. **Corrected a false comment** claiming "Dart's `.` matches `\r`" — empirically probed and disproved (Dart follows ECMAScript, `.` excludes `\r`, same as JS); the `.trim()` stays (for surrounding spaces) with an accurate comment and CRLF/empty-heading tests. **Closed a fixture gap** — added a Dart-only integration test pinning the top-level `category: 'general'` fallback (no shared fixture touched). Re-verified: 4/4 goldens + 4/4 JS reference still green. Tests 88 → 92. analyze clean. 5 findings deferred (2 contract-level, pending KseiPo's call). |
