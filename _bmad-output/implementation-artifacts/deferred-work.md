# Deferred Work

## Deferred from: code review of 1-1-scaffold-the-app-and-grant-the-repo-folder (2026-07-20)

- **Orphaned `*.tmp-*` files on process kill get synced by Syncthing** — `writeAtomic` cleanup only runs on the exception path; a process kill between `writeAsString` and `rename` leaves `x.md.tmp-<epoch>` junk inside the synced folder, propagated to every device. Deferred to **Story 1.2** (writeAtomic hardening owns the temp-file lifecycle: temp naming that the syncer ignores or a startup sweep, plus fsync). [apps/mobile/lib/storage/all_files_repo_storage.dart:60]
- **SD-card / secondary-volume repo roots unreachable** — the root picker is hard-wired to `/storage/emulated/0`; a Syncthing folder on removable storage (`/storage/XXXX-XXXX/…`) cannot be selected. Spec prescribed primary shared storage for v0.1; backlog enhancement (enumerate external volumes). [apps/mobile/lib/app/root_picker_page.dart:33]
- **`writeAtomic` parent-directory semantics undefined** — the port contract is silent on whether missing parent dirs are created; today it throws. Epic 2 create ops (FR24/FR25 — new entity / new sub-entry may `mkdir`) must define and test this. [apps/mobile/lib/storage/repo_storage.dart:80]
- **No error stage for plugin-channel failures** — if `SharedPreferences.getInstance()` or the permission channel throws, `_refresh` never completes and the UI shows an eternal spinner; `_Stage` has no error state. Rare platform failure; v0.2 polish. [apps/mobile/lib/app/home_page.dart:57]
- **`setString` failure silently loses the chosen root** — `RepoRootStore.write` ignores the `bool` result; a failed persist looks configured this session and asks again next launch. Rare platform failure; v0.2 polish. [apps/mobile/lib/storage/repo_root_store.dart:19]
- **Release builds sign with debug keys** — `flutter create` default kept; fine for a sideloaded debug APK, must change before any real release build. [apps/mobile/android/app/build.gradle.kts:32]

## Deferred from: code review of 1-2-prove-a-safe-atomic-round-trip-headless-spike (2026-07-20)

- **No directory fsync after `rename`** — `writeAtomic` fsyncs the temp file contents (`flush: true`) but not the parent directory entry the `rename` creates, so a power-loss window can lose the rename. NFR1 targets "syncer never sees a partial file" (rename satisfies that); crash durability beyond that is out of v0.1 scope and the syncer re-propagates. [apps/mobile/lib/storage/all_files_repo_storage.dart:94]
- **`_sweepStaleTemps` scans the whole target directory on every write** — O(n) `listDir` per save purely to catch rare orphaned temps. Fine for v0.1 repo sizes; revisit for NFR6 (responsiveness) if a directory grows large. [apps/mobile/lib/storage/all_files_repo_storage.dart:79]
- **Temp filename can exceed the 255-byte limit** — `.lore-tmp-<basename>-<micros>-<rand>` for a basename near the FS limit produces `ENAMETOOLONG` and rejects an otherwise-valid write. Very rare (lore slugs are short); bound the basename portion if it ever surfaces. [apps/mobile/lib/storage/all_files_repo_storage.dart:85]

## Deferred from: code review of 1-3-resolve-project-configuration (2026-07-20)

- **Zero-width space (`U+200B`) survives `trim()`** in `ProjectConfig.parse`, yielding an effectively-blank but non-empty `loreDir`. Real but obscure (adversarial/copy-paste input); not worth v0.1 scope. [apps/mobile/lib/lore/project_config.dart:46]
- **`listDir` and `resolveProjectConfig` awaited sequentially instead of via `Future.wait`** on every repo open/resume — minor latency, repeats on every app resume. [apps/mobile/lib/app/home_page.dart:96]
- **A stale (superseded-epoch) refresh still performs the full config read** before being discarded — wasted I/O, not a correctness issue (the epoch guard already prevents the wrong UI state). [apps/mobile/lib/app/home_page.dart:96]
- **`_loreDir` isn't reset when leaving the ready stage** (unlike `_topLevel`) — currently harmless; tighten if a future feature reads `_loreDir` outside the ready branch. [apps/mobile/lib/app/home_page.dart:68]
- **`ProjectConfig.==`/`hashCode`/`toString` are untested** — add coverage if/when Epic 2 relies on config equality for caching or comparison. [apps/mobile/lib/lore/project_config.dart:53]
- **`resolveProjectConfig`'s `RepoStorageException` catch is only tested via the missing-file case**, not a genuine I/O error (e.g. `lore-story.json` existing as a directory). [apps/mobile/test/lore/project_config_test.dart]
- **AC5's "observable" clause has no widget-test assertion** on the rendered `loreDir` text (only verified by code inspection). [apps/mobile/test/widget_test.dart]

## Deferred from: code review of 1-4-open-and-save-one-file-in-a-bare-editor (2026-07-20)

- **Editor never re-checks the file before overwriting it** — open a file, background the app while Syncthing pulls a desktop edit, return and tap save: the remote edit is atomically and byte-exactly obliterated with no warning. A refuse-on-mismatch guard is cheap, but without the Epic 2 conflict UX (FR17 / Story 2.4) it produces a blocked save with no resolution path. **Revisit together with the conflict UI** — this is the highest-value deferred item in the log. [apps/mobile/lib/app/editor_page.dart:87]
- **`*.sync-conflict-*` files are unfiltered and freely editable** — deliberately NOT hidden, because FR17 requires conflict copies be surfaced with a badge rather than hidden. Editing one silently puts work in a file the syncer treats as garbage. Resolved by Story 2.4's conflict-badge UI. [apps/mobile/lib/storage/repo_storage.dart]
- ~~**`_openEntry` doesn't `exists`-check a folder that vanished between listing and tap**~~ — **RESOLVED 2026-07-31**: moot — picker retired in Story 2.12.
- ~~**A `loreDir` configured with a trailing slash breaks `_atStart`**~~ — **RESOLVED 2026-07-31**: moot — picker retired in Story 2.12.
- ~~**A regular *file* named exactly `loreDir` passes the `exists` check**~~ — **RESOLVED 2026-07-31**: moot — picker retired in Story 2.12.

## Deferred from: code review of 2-1a-port-the-lore-loader-read-model (2026-07-20)

- ~~`children[]` ordering under-specified~~ — **RESOLVED 2026-07-20**: `lib/lore.js` now sorts files before flattening; both implementations are deterministic; README documents it. (Goldens regenerated, no reorder.)
- ~~`prettify` capitalization~~ — **RESOLVED 2026-07-20**: `prettify` no longer changes case in either implementation (KseiPo: "we don't need to capitalize anything"); goldens regenerated.
- **`localeCompare` vs `compareTo` sort divergence** — the Dart normalizer sorts entries and `langs` keys with `compareTo` (UTF-16 code units) where the JS reference uses `localeCompare`. They agree for all current fixture ids (lowercase ASCII) and the `ru/en/orig` key set. Revisit if a fixture introduces mixed-case or Cyrillic ids/keys. [apps/mobile/test/lore/normalize.dart]
- **Malformed-UTF-8 replacement-char granularity may differ (Node/V8 vs Dart `Utf8Decoder`)** — only affects `textSha` of genuinely corrupt files; real files are well-formed. Latent. [apps/mobile/lib/storage/all_files_repo_storage.dart:54]

## Deferred from: code review of 2-1b-syncer-aware-walk-and-rescan (2026-07-20)

- **Conflict copies inside skipped dirs (`media/`, `.stversions/`) are never surfaced** — AC1's filter runs before AC2's conflict check, so a conflict inside a skipped dir is silently hidden. Defensible for syncer-internal dirs; the `media/` case is a real asset conflict the app cannot report. Pair with Story 2.4. [apps/mobile/lib/lore/lore_loader.dart]
- **An entity whose only card is a conflict copy silently demotes to a category** — its `tree`/`children[]` vanish and sub-entries are promoted to top-level entities. Requires the original card to be deleted. The correct behavior is a product question. [apps/mobile/lib/lore/lore_loader.dart]
- **A conflict copy is lost when its entity's card read fails** — `_makeEntry` reads the card before `_buildNode`, so the folder's conflicts are never recorded. The active-syncer race is exactly FR17's scenario. [apps/mobile/lib/lore/lore_loader.dart]
- **Every directory is listed twice per walk** — the entity-card probe discards its `listDir` result and the directory is listed again by `_walkCategory`/`_buildNode`, doubling syscalls on every resume (AD-10 rebuilds on every resume). Real NFR6 cost; deferred as a walk-structure refactor with conformance risk. [apps/mobile/lib/lore/lore_loader.dart]
- **Conflict copies outside `loreDir` are never surfaced** — a conflict in `story/` or the repo root is invisible while the banner shows a false all-clear. FR17 is repo-scoped, the loader is `loreDir`-scoped. [apps/mobile/lib/lore/lore_loader.dart]
- **Conflict copies of non-`.md` files are dropped** — notably `lore-story.json.sync-conflict-*.json`: the project config is conflicted and the author is never told. [apps/mobile/lib/lore/lore_loader.dart]
- **No progress feedback during a rescan**; **a missing/file `loreDir` reads as "0 lore entities"**; **a directory matching the conflict pattern is descended rather than recorded.** Minor UX/edge items; Story 2.2 restructures this surface. [apps/mobile/lib/app/home_page.dart, lore_loader.dart]

## Deferred from: code review of 2-2-browse-categories-and-entities (2026-07-24)

- **A real top-level folder literally named `general` merges with the synthetic root-card bucket** — a loose card at `loreDir` root and a real `general/` folder both resolve to `category == 'general'` (loader semantic, Story 2.1a), so `categoriesOf` groups them into one indistinguishable Categories row. No stranding or crash; unusual config. Revisit if the root-card bucket needs a reserved/rendered-distinct name. [apps/mobile/lib/lore/lore_browse.dart + apps/mobile/lib/lore/lore_loader.dart:238,243,250]
- **Rapid double-tap stacks duplicate routes** — a fast double-tap on a category row pushes two `CategoryEntitiesPage` routes; on an entity row, two `EditorPage` instances open on the same file. No navigation single-flight guard (unlike the app's `_refresh` coalescing). Pre-existing app-wide pattern (Story 2.1b's `_openEntry`); low impact. [apps/mobile/lib/app/home_page.dart `_openCategory`; apps/mobile/lib/app/category_entities_page.dart `_openEntity`]

## Deferred from: code review of loreDir=root requirement change (2026-07-24)

- ~~**A lore-story.json whose `loreDir` points at a FILE (not a directory) makes the "Open a file" picker root at that file path**~~ — **RESOLVED 2026-07-31**: moot — picker and `_openFile` retired in Story 2.12.

## Deferred from: code review of 2-3-view-an-entitys-detail-tree (2026-07-24)

- **Rapid double-tap stacks duplicate routes** — on a detail-page leaf/card row (two `EditorPage` pushes) and on the entity row in `CategoryEntitiesPage._openEntity` (two destination pages). No navigation single-flight guard; pre-existing app-wide pattern deferred repo-wide since Story 2.1b/2.2. [apps/mobile/lib/app/entity_detail_page.dart `_open`; apps/mobile/lib/app/category_entities_page.dart `_openEntity`]
- **Eager `ListView(children:)` in the entity detail page** — `_rows`/`_appendSection` materialize the whole entity outline on every build, unlike the sibling `CategoryEntitiesPage`'s `ListView.builder`. Realistic single-entity trees are small, so the descriptor-based lazy refactor is disproportionate for v0.1; revisit if entities grow content-heavy (NFR6). [apps/mobile/lib/app/entity_detail_page.dart:93]

## Deferred from: code review of 2-4-surface-sync-conflict-copies (2026-07-24)

- **Rapid double-tap stacks duplicate routes on the conflicts surfaces** — the home conflict banner (two `ConflictsPage` pushes) and a conflict row (two `EditorPage` of the same file, last-write-wins race). Pre-existing app-wide pattern (no navigation single-flight guard); this is a higher-stakes surface for it, but the trigger (fast double-tap + two manual edits+saves) is narrow. Fix repo-wide with a nav single-flight guard when the double-tap pattern is addressed. [apps/mobile/lib/app/home_page.dart banner InkWell; apps/mobile/lib/app/conflicts_page.dart `_open`]

## Deferred from: code review of 2-5-edit-with-helper-toolbar-and-convention-highlighting (2026-07-26)

- **IME composing underline not drawn** — `ConventionHighlightingController.buildTextSpan` ignores `withComposing`/`value.composing`, so the standard in-progress-composition underline never renders (vs stock TextField). Documented v0.1 tradeoff; Cyrillic is direct-input (not composed), low practical impact. Revisit if composed input (e.g. CJK) is needed. [apps/mobile/lib/app/convention_highlighting_controller.dart]
- **Dialogue heuristic misses a speaker after a stray colon** — e.g. `See note 3:00 — Frank: hi` yields no dialogueSpeaker token (`matchAsPrefix` can't skip the earlier colon). Heuristic limitation; the Story 3.1 linter will refine the shared matcher. [apps/mobile/lib/lore/convention_matcher.dart]
- **Per-keystroke full-document re-match on long scene files** — the by-text memo added in review only helps non-text rebuilds; true incremental/viewport-scoped matching is a larger change. Realistic files are small (a scene is a few KB), so deferred; regexes are linear (no ReDoS), so it's cost not a hang. [apps/mobile/lib/app/convention_highlighting_controller.dart]
- **Lone `\r` (old-Mac line endings) not treated as a line break** — `matchConventions` splits on `\n` only, so a `# Title\rword` heading span swallows the rest. No such files in this project; cosmetic (highlight span only, buffer unaffected). [apps/mobile/lib/lore/convention_matcher.dart]

## Deferred from: code review of 2-6-flag-invalid-markup-without-crashing (2026-07-26)

- **Suspect markup on a heading line is not flagged** — `_matchLine` early-returns a whole-line `heading` token (Story 2.5's "headings subsume inline" design), so `# <<if $x>>` / `# <script>` render as a plain heading; error kinds aren't scanned there and would be suppressed by the whole-line heading's top precedence anyway. Surfacing them means reworking heading precedence. Rare in practice; the Story 3.1 linter can refine. [apps/mobile/lib/lore/convention_matcher.dart]
- **Broader malformed-bracket cases beyond an unterminated `[[`** — a stray dangling `]]` (`[[a]]b]]`) is unstyled, and nested brackets in a target (`[[Chapter[1]->Scene2]]`) fall back to the 2-char unterminated-`[[` marker rather than a passage-link error. Story 2.6 deliberately scoped `malformedMarkup` to the unterminated-`[[` case; dangling/unpaired/nested detection is Story 3.1's linter (FR18), which consumes the same tokens. [apps/mobile/lib/lore/convention_matcher.dart]
- **An error token straddling a newline is not detected** — `<<if\n>>` / `<div\n>` produce no candidate on either line; the matcher is line-oriented for every kind (Story 2.5). Cross-line detection needs a pre-split scan. Rare; consistent with all other kinds. [apps/mobile/lib/lore/convention_matcher.dart]

## Deferred from: code review of 2-7-preview-rendered-markdown (2026-07-26)

- **A convention marker split across inline emphasis loses its preview highlight (false negative)** — `**Frank**: hi` shows no dialogue styling; `[secret **loot**]` shows no placeholder. `MarkdownPreview._conventionSpans` runs the matcher per AST text-fragment, so a marker straddling an `em`/`strong`/`a` boundary matches in no fragment. Benign (missed highlight, never wrong styling or dropped text). Correct fix: match over a block's whole concatenated inline text and distribute tokens across fragments (also folds in the line-anchor handling done inline for Story 2.7). Larger refactor; deferred past v0.1. [apps/mobile/lib/app/markdown_preview.dart]
- **No memoization on `MarkdownPreview`** — reparses the full document on every parent rebuild, unlike `ConventionHighlightingController`'s by-text memo. Not a measured problem for a read-only preview (no keystrokes reach it); revisit if a large card previews sluggishly (e.g. cache parsed blocks keyed by text, or make it Stateful). [apps/mobile/lib/app/markdown_preview.dart]

## Deferred from: code review of 2-10-create-a-new-entity (2026-07-31)

- **Cyrillic/non-ASCII group/title names always rejected by `_slugify`** — `[^a-z0-9\-]` strips all non-ASCII, so pure-Cyrillic input slugifies to empty string. Pre-existing from Story 2.10; requires design decision on slug strategy (transliterate? keep as-is?). Affects `_slugify` in `category_entities_page.dart`, `home_page.dart`, and `entity_detail_page.dart`.
- **TextEditingController not disposed in create-entity/sub-entry dialogs** — `_showCreateEntityDialog` and `_showCreateSubEntryDialog` create controllers without `.dispose()`. Controllers become unreachable when dialog closes and are GC'd; no system resource leak. Pre-existing pattern.
- **No re-entrancy guard on FAB during async storage calls** — Modal dialog prevents concurrent taps during dialog phase; theoretical only during the post-dialog await chain. Pre-existing app-wide pattern.

## Deferred from: code review of 2-9-create-a-translation-from-a-missing-en (2026-07-26)

- **Create-mode save can clobber a concurrently-synced `.en.md` (TOCTOU)** — `FileEditor._load` (createIfMissing) checks `exists` once; if the syncer delivers a real `.en.md` between that check and the save, the empty-create tab's `writeAtomic` overwrites it, with no on-disk baseline the author saw first. Consistent with the app's no-optimistic-locking design (AD-5 — the syncer owns propagation; a genuine collision yields a `*.sync-conflict-*` copy surfaced by Story 2.4), so content isn't truly lost, but create-mode widens the window. Revisit if optimistic locking / a pre-write existence re-check is ever wanted. [apps/mobile/lib/app/file_editor.dart]
- **The EN tab's "needs translation / will create" hint is stale after a successful create** — the `Icons.translate` tab hint is fixed from `_Variant.createIfMissing` at build time and keeps showing for the rest of the `PairedEditorPage` session after the file is created; it self-corrects on the next rescan/reopen (the reloaded `LoreItem` then has `en`). Cosmetic. Could clear the hint once the tab's file exists/has been saved. [apps/mobile/lib/app/paired_editor_page.dart]

## Deferred from: code review of 2-13-preview-the-entity-card-on-the-detail-screen (2026-07-31)

- **No `Semantics` label on the card's tap target** — the card `InkWell` relies on default semantics merge (the rendered text plus a generic tap action); no explicit "Card, tap to edit" label like `ListTile`'s structured title/subtitle gave for free. No established a11y-labeling pattern exists elsewhere in the app to hold this story to a higher bar; revisit if accessibility becomes a tracked requirement. [apps/mobile/lib/app/entity_detail_page.dart]
- **A blank/whitespace-only card collapses its tap target to ~32px** — `MarkdownPreview` renders `SizedBox.shrink()` for empty input, so the `entity-card` `InkWell` shrinks to just its 16px padding. Rare in practice (Story 2.10's create flow always seeds `# Title`); a minor UX papercut, not data loss. [apps/mobile/lib/app/entity_detail_page.dart, apps/mobile/lib/app/markdown_preview.dart]
- **`MarkdownPreview` has no memoization, now exercised by a new caller with potentially long cards** — reparses the full document on every parent rebuild. This is Story 2.7's own already-accepted tradeoff (see that story's deferred-work entry above — "not a measured problem for a read-only preview"); Story 2.13 just adds a second call site with the same characteristic. Revisit together if either card previews sluggishly in practice. [apps/mobile/lib/app/markdown_preview.dart]
