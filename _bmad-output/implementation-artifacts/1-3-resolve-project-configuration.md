---
baseline_commit: d465b88
---

# Story 1.3: Resolve project configuration

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

> **⚠️ Superseded default (2026-07-24):** This story was built when the default
> `loreDir` was `lore` (references below still say so, as a historical record).
> A later requirements change (FR2) made the picked repo folder the lore folder
> itself, so the **default `loreDir` is now the repo root (`''`)**; a
> `lore-story.json` may still redirect it to a subfolder that exists. See the
> updated FR2 in `prd.md` / `epics.md` and the architecture-spine Config row.

## Story

As the author,
I want the app to read my project's `lore-story.json`,
so that it knows where my lore lives without in-app configuration.

## Acceptance Criteria

1. **AC1 (FR2 — resolve `loreDir`):** Given a repo root containing `lore-story.json`, when the app opens the repo, then it resolves `loreDir` (default `lore`) from it.
2. **AC2 (FR2 — missing/invalid never blocks):** Given the file is missing or invalid JSON, when the app opens the repo, then it falls back to defaults (`loreDir = lore`) and continues without blocking or crashing.
3. **AC3 (re-read per open, no caching):** Given the repo is re-opened, resumed, or refreshed, when config resolves, then it is re-read from disk each time (never cached at module load), so an edited `lore-story.json` takes effect on the next open.
4. **AC4 (BOM-safe parse):** Given a `lore-story.json` written with a leading UTF-8 BOM (Windows editors/PowerShell do this), when it is parsed, then the BOM is stripped before JSON decoding so the file parses correctly rather than falling back to defaults.
5. **AC5 (observable + hygiene):** Given a resolved config, when the app reaches the ready state, then the resolved `loreDir` is shown (proving FR2 end-to-end); and `flutter analyze` is clean and `flutter test` passes including new config tests.

## Tasks / Subtasks

- [x] **Task 1 — `ProjectConfig` model + pure parser in the `lore/` slice (AC: 1, 2, 4)**
  - [x] `lore/project_config.dart`: immutable `ProjectConfig` (`loreDir` default `'lore'`) + `ProjectConfig.defaults`.
  - [x] Pure `ProjectConfig.parse(String raw)`: strips a single leading `U+FEFF` before `jsonDecode`; falls back to defaults on invalid JSON, non-object, missing/non-String/empty/whitespace `loreDir`. Never throws.
  - [x] Reads only `loreDir`; other keys ignored (forward-compatible). Also trims a leading `./` (accepts the JS POC `"./lore"` form).
  - [x] Pure Dart — only `dart:convert` + the `RepoStorage` port import; no `dart:io`/Flutter.
- [x] **Task 2 — `resolveProjectConfig` reader over the `RepoStorage` port (AC: 1, 2, 3)**
  - [x] `resolveProjectConfig(RepoStorage)` reads `kProjectConfigFile` (`'lore-story.json'`) and returns `ProjectConfig.parse(raw)`.
  - [x] `RepoStorageException` (missing file / I/O) → `ProjectConfig.defaults`; never throws, never blocks.
  - [x] Depends only on the port; `const kProjectConfigFile = 'lore-story.json'` defined.
- [x] **Task 3 — Resolve on repo open + surface `loreDir` (AC: 3, 5)**
  - [x] `home_page._refresh` calls `resolveProjectConfig(storage)` on the ready path (every launch/resume/change-folder — re-read, not cached) and stores `_loreDir`.
  - [x] `_ReadyView` shows a "Lore folder: `<loreDir>`" line — observable FR2 proof.
- [x] **Task 4 — Barrel export (AC: 1)**
  - [x] `lore/lore.dart` exports `project_config.dart`; `app/` imports the slice barrel, not the internal file.
- [x] **Task 5 — Tests (AC: 1, 2, 4, 5)**
  - [x] `test/lore/project_config_test.dart`: 9 pure `parse` cases (valid, `./` form, extra keys, BOM, missing key, invalid JSON/empty, non-object, non-String, empty/whitespace) + 4 `resolveProjectConfig` temp-dir cases (present, absent→defaults, BOM-on-disk, invalid JSON).
  - [x] `flutter analyze` clean; `flutter test` green (49 passing).

### Review Findings

- [x] [Review][Patch] `parse`/`resolveProjectConfig` don't actually enforce "never throws" — only `FormatException` (parse) and `RepoStorageException` (resolver) are caught, so a pathological `lore-story.json` (e.g. deeply nested JSON → `StackOverflowError`, which is an `Error` not caught by any `Exception`-typed clause) or a non-`RepoStorageException` read failure escapes uncaught, contradicting the doc comment and FR2/AD-8's "never blocks or crashes." [apps/mobile/lib/lore/project_config.dart:34, 71]
- [x] [Review][Patch] Repeated `./` prefix only stripped once — `{"loreDir":"././lore"}` yields `./lore` (still prefixed), contradicting the doc's claim of accepting the JS POC form. Strip all leading `./` segments, not just one. [apps/mobile/lib/lore/project_config.dart:47]
- [x] [Review][Patch] No length cap on `loreDir` — an oversized value is accepted verbatim and rendered directly in the ready view with no guard, unlike the empty/whitespace case which is explicitly bounded. Add a reasonable max-length check (fall back to defaults above it). [apps/mobile/lib/lore/project_config.dart:50]
- [x] [Review][Defer] Zero-width space (`U+200B`) survives `trim()`, yielding an effectively-blank but non-empty `loreDir` — real but obscure (adversarial/copy-paste input); not worth v0.1 scope. [apps/mobile/lib/lore/project_config.dart:46]
- [x] [Review][Defer] `listDir` and `resolveProjectConfig` are awaited sequentially instead of concurrently (`Future.wait`) on every repo open/resume — minor latency, not correctness. [apps/mobile/lib/app/home_page.dart:96]
- [x] [Review][Defer] A stale (superseded-epoch) refresh still performs the full config read before being discarded — wasted I/O, not a correctness issue (the epoch guard already prevents the wrong UI state). [apps/mobile/lib/app/home_page.dart:96]
- [x] [Review][Defer] `_loreDir` isn't reset when leaving the ready stage (unlike `_topLevel`) — currently harmless since it's only rendered in the ready stage and gets overwritten before the next ready render; worth tightening if a future feature reads `_loreDir` outside that branch. [apps/mobile/lib/app/home_page.dart:68]
- [x] [Review][Defer] `ProjectConfig.==`/`hashCode`/`toString` are untested — add coverage if/when Epic 2 relies on config equality for caching or comparison. [apps/mobile/lib/lore/project_config.dart:53]
- [x] [Review][Defer] `resolveProjectConfig`'s `RepoStorageException` catch is only tested via the missing-file case, not a genuine I/O error (e.g. `lore-story.json` existing as a directory) — same catch path, different `FileSystemException` origin; untested but low risk. [apps/mobile/test/lore/project_config_test.dart]
- [x] [Review][Defer] AC5's "observable" clause has no widget-test assertion on the rendered `loreDir` text (only verified by code inspection) — add a widget test asserting a non-default `loreDir` renders, when convenient. [apps/mobile/test/widget_test.dart]

## Dev Notes

### What this story is

Low-risk config resolution on the proven storage foundation: read `lore-story.json`
from the repo root, extract `loreDir` (default `lore`), and never block or crash on
a missing/invalid file. No browsing yet (Epic 2) — the observable behavior is
showing the resolved `loreDir` in the ready view. This is the first real code in the
`lore/` slice.

### The load-bearing BOM guard (do not skip)

`project-context.md` calls this out explicitly: *"Strip a BOM before parsing text as
data … `config.json` is read with `.replace(/^﻿/, '')` before `JSON.parse`
because editors and PowerShell on this (Windows) machine write one. That line is
load-bearing, not dead code — apply the same guard to any new config/JSON reader."*

This is sharper here than in the JS POC: **Story 1.2's `read` deliberately
re-attaches a leading BOM** (to keep file round-trips byte-exact), so a
`lore-story.json` saved with a BOM will arrive from `RepoStorage.read` **with** a
leading `U+FEFF`. `jsonDecode` throws on a leading BOM, which without the guard would
send every BOM'd config straight to the default fallback — silently ignoring the
user's real `loreDir`. So `ProjectConfig.parse` **must** strip one leading `U+FEFF`
before `jsonDecode`:

```dart
final cleaned = raw.startsWith('\u{FEFF}') ? raw.substring(1) : raw;
```

AC4 and a BOM test exist specifically to lock this in.

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/lore/lore.dart`** — currently a placeholder `library;` doc for the slice. Add the export; keep the doc.
- **`apps/mobile/lib/app/home_page.dart`** — `_refresh` currently, on the ready path, builds the storage, checks `exists('')`, lists top-level entries, and sets `_stage = ready`. **Add** a `resolveProjectConfig(storage)` call there and a `_loreDir` state field; pass it to `_ReadyView`. **Preserve:** the epoch guard (`_refreshEpoch`), the vanished-root `exists('')` check, and the round-trip spike trigger — do not regress them. `_ReadyView` is a `StatelessWidget` taking `rootPath`/`topLevel`/`onChangeFolder`/`onRunSpike`; add a `loreDir` field alongside.

### Architecture guardrails

- **AD-9 — per-slice purity.** `project_config.dart` is pure: model + parser use only `dart:convert`; the resolver depends only on the `RepoStorage` **port** (no `dart:io`, no Flutter). The slice's I/O still goes through `storage/`'s adapter. [ARCHITECTURE-SPINE.md#AD-9]
- **AD-12 — slice boundaries.** Config resolution is lore-domain (it locates the lore); it belongs in `lore/` and is consumed via the `lore.dart` barrel, not an internal file. [ARCHITECTURE-SPINE.md#AD-12]
- **AD-8 — total/never-throw.** Malformed/missing config is data to handle, not a fault: parse and resolve degrade to defaults, never throw. [ARCHITECTURE-SPINE.md#AD-8]
- **AD-1 — no persistence of derived state.** Config is re-read per open, never cached at module load (matches the JS `readConfig()`-per-request rule). Don't stash it in a static/singleton. [ARCHITECTURE-SPINE.md#AD-1; project-context.md "`config.json` is re-read on every request"]
- **Config contract.** `lore-story.json` at the repo root; `loreDir` default `lore`; missing/invalid → defaults, never block (Consistency Conventions / FR2). [ARCHITECTURE-SPINE.md#Consistency Conventions; ARCHITECTURE.md §3.4]

### Config file shape (only `loreDir` matters for v0.1)

`lore-story.json` (ARCHITECTURE.md §3.4) can contain `storyDir`, `loreDir`,
`scenesDir`, `codeDirs`, `linkMacros`, `dynamicTags`. The mobile app is a lore/scene
**writing surface** — no twee, no flow graph — so v0.1 reads **only `loreDir`** and
ignores the rest. `loreDir` is a repo-relative subpath; the default is `lore`. Note
the JS POC example uses `"./lore"` while §3.4 uses `"lore"` — accept either; if you
normalize, only trim a leading `./`, and rely on the `RepoStorage` path
normalization (which already strips `.`/`..`/absolute) for safety rather than
re-implementing sanitization here.

### Previous story intelligence (Stories 1.1, 1.2 — done)

- `RepoStorage.read` (from 1.2) is best-effort UTF-8 and **re-attaches a leading BOM**; it **throws `RepoStorageException` on a missing file** (not on malformed content). So the resolver must try/catch the read for the missing-file case → defaults. (Do not rely on `read` returning empty for a missing file — it throws.)
- The `storage/` adapter is the only `dart:io` file and is not exported from its barrel; the `lore/` slice depends on the `RepoStorage` port only. Keep that seam.
- Test pattern: pure logic as plain unit tests; anything touching files uses `AllFilesRepoStorage` against `Directory.systemTemp` (dart:io in tests only). Widget/UI tests use the fakes in `test/fakes.dart`.
- Toolchain: `flutter analyze` + `flutter test`; Android build needs `kotlin.incremental=false` (already set) on this Windows host.

### Git intelligence

Recent commits: `d465b88` "Prove safe atomic byte-exact write path (Story 1.2)",
`ade0c11` "Scaffold mobile app and RepoStorage seam (Story 1.1)". This story builds
on that storage foundation; no dependency changes expected.

### Library / version policy

No new dependencies. `dart:convert` (`jsonDecode`) covers parsing. No package needed.

### Testing standards

- Parser tests are pure and exhaustive over the failure shapes (that's where FR2's
  "never block" lives). Resolver tests use a temp dir + `AllFilesRepoStorage` so the
  BOM path is exercised against the real `read`.
- If a widget test asserts the ready view shows `loreDir`, update the existing
  ready-view widget test / `FakeRepoStorage` in `test/fakes.dart` so its `read`
  returns a config (or defaults) without throwing — the fake's `read` currently
  returns `''`, which `parse('')` correctly maps to defaults, so the ready-view test
  keeps working; extend only if you add a custom-`loreDir` assertion.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1 · Story 1.3] — user story, ACs (FR2)
- [Source: prd.md#FR2] (resolve `loreDir` from `lore-story.json`; missing/invalid → defaults, no block)
- [Source: ARCHITECTURE.md §3.4] (`lore-story.json` shape; `loreDir` default `lore`)
- [Source: ARCHITECTURE-SPINE.md#Consistency Conventions] (config re-read per open; missing/invalid → defaults), #AD-1, #AD-8, #AD-9, #AD-12
- [Source: _bmad-output/project-context.md] (**BOM-strip-before-parse is load-bearing**; config re-read per request, not cached)
- [Source: _bmad-output/implementation-artifacts/1-2-prove-a-safe-atomic-round-trip-headless-spike.md] (`read` re-attaches BOM + throws on missing file — why the guard and try/catch matter)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- `flutter analyze` → No issues found.
- `flutter test` → **49 passing** (36 → +13 config tests). No regressions; the existing ready-view widget test still passes (the fake's `read` returns `''`, which `parse('')` maps to defaults, so the ready view shows `loreDir = lore`).

### Completion Notes List

- **Fully complete and CI-verified — no on-device gate.** Unlike 1.1/1.2, this story's ACs (config resolution + the observable `loreDir` in the ready view) are entirely provable in CI, so it goes straight to `review` with everything green.
- **The BOM guard is the crux and is tested end-to-end.** Because Story 1.2's `read` re-attaches a leading BOM, a BOM-written `lore-story.json` arrives with a leading `U+FEFF`; `ProjectConfig.parse` strips exactly one before `jsonDecode`. A resolver test writes real `EF BB BF` bytes to disk and asserts the custom `loreDir` resolves — proving the guard works against the real read path, not just in isolation.
- **FR2 "never block" is enforced at both layers:** `parse` is total over every malformed shape (invalid JSON, non-object, wrong-typed/empty `loreDir`), and `resolveProjectConfig` catches `RepoStorageException` for the missing-file case (`read` throws on missing, per 1.2). Both fall back to `loreDir = lore`.
- **`lore/` slice's first real inhabitant**, kept pure (only `dart:convert` + the `RepoStorage` port), consumed via the `lore.dart` barrel. Config is re-resolved every open (not cached), matching the JS `readConfig()`-per-request rule.
- Only `loreDir` is read (v0.1 scope); `storyDir`/`scenesDir`/`codeDirs`/etc. are tolerated and ignored. No new dependencies.

### File List

**Created:**
- `apps/mobile/lib/lore/project_config.dart` (`ProjectConfig`, `ProjectConfig.parse`, `resolveProjectConfig`, `kProjectConfigFile`)
- `apps/mobile/test/lore/project_config_test.dart`

**Modified:**
- `apps/mobile/lib/lore/lore.dart` (barrel exports `project_config.dart`)
- `apps/mobile/lib/app/home_page.dart` (resolve config on the ready path; `_loreDir` state; "Lore folder" line in `_ReadyView`)

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-20 | Implemented Story 1.3 (FR2): added `ProjectConfig` + a total, BOM-stripping `parse` and a `resolveProjectConfig` reader over the `RepoStorage` port (missing/invalid → `loreDir = lore`, never blocks), resolved on every repo open (not cached), and surfaced the resolved `loreDir` in the ready view. First real code in the `lore/` slice. Tests 36 → 49 (9 parse cases + 4 resolver cases incl. a BOM-on-disk file). analyze clean. Status → review. |
| 2026-07-20 | Addressed code review (Sonnet 5 vs Opus impl): 3 patch findings fixed. Both `parse` and `resolveProjectConfig` now catch-all (was narrowly `FormatException`/`RepoStorageException` only, so a pathological deeply-nested JSON `StackOverflowError` or a non-`RepoStorageException` read failure could escape uncaught — violating FR2's "never blocks"); repeated leading `./` now fully stripped (was only one level); added a `loreDir` length cap. Tests 49 → 54 (repeated-`./`, `./`-alone, length-cap, deep-nesting-never-throws, directory-instead-of-file). analyze clean. 7 findings deferred (zero-width-space edge, two perf nits, a state-hygiene nit, and 3 test-coverage-only gaps). Status stays review. |
