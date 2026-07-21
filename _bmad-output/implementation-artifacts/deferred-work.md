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
- **`_openEntry` doesn't `exists`-check a folder that vanished between listing and tap** — yields an empty picker with the Up button suppressed (dead end, but not a crash). `_openFile` already applies the port doc's `exists` disambiguation; `_openEntry` should too. [apps/mobile/lib/app/home_page.dart:152]
- **A `loreDir` configured with a trailing slash breaks `_atStart`** — `'lore/'` never equals `'lore'`, so the picker shows a phantom extra Up level. Fix by normalizing trailing slashes in `ProjectConfig.parse` or the picker. [apps/mobile/lib/app/lore_file_picker_page.dart:81]
- **A regular *file* named exactly `loreDir` passes the `exists` check** — the picker then opens on a file path, lists nothing, and hides Up. Fixing properly needs an `isDirectory`/stat capability on the `RepoStorage` port. [apps/mobile/lib/app/home_page.dart:145]
