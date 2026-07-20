---
baseline_commit: ce7834fcd8d3aadeb746a219bcb8e14ea13197bc
---

# Story 1.1: Scaffold the app and grant the repo folder

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to launch the app, grant it access to my repo folder, and have it remembered,
so that the app can reach my synced files on later launches without re-granting.

## Acceptance Criteria

1. **AC1 (FR1 — grant + store root):** Given a fresh install on Android 11+, when I open the app and choose my repo root (a Syncthing folder or a folder inside one), then the app requests all-files access (`MANAGE_EXTERNAL_STORAGE`) and stores the chosen root path.
2. **AC2 (FR1 — remembered across launches):** Given I have granted access and picked a root, when I relaunch the app, then it reopens the same root without asking again (no re-grant, no re-pick).
3. **AC3 (NFR3 / AD-3 — the seam):** Given the app code, when the loader or editor needs the filesystem, then it goes through a `RepoStorage` interface (`listDir`, `read`, `writeAtomic`, `exists`) and never touches `dart:io` or the permission directly. No `dart:io` or `MANAGE_EXTERNAL_STORAGE` reference exists outside the `storage/` slice's adapter file(s).
4. **AC4 (permission-denied path — NFR7 spirit):** Given I decline or have not yet granted all-files access, when I try to proceed, then the app shows a clear "grant access" state and never crashes; granting later (returning from Settings) lets me continue without restarting the app.
5. **AC5 (scaffold hygiene):** Given a clean checkout, when I run the app from `apps/mobile/`, then it builds and launches on an Android 11+ device/emulator, and `flutter analyze` and the (seed) `flutter test` pass.

## Tasks / Subtasks

- [x] **Task 1 — Scaffold `apps/mobile/` Flutter app (AC: 5)**
  - [x] Created the app: `flutter create --org dev.kseipo --project-name lore_and_story --platforms=android apps/mobile` (Android-only platform, since it is a sideloaded Android app and iOS can't build on this Windows host). Package id `dev.kseipo.lore_and_story`.
  - [x] Set Android `minSdk = 30` (Android 11) explicitly in `apps/mobile/android/app/build.gradle.kts`; verified `minSdkVersion="30"` in the merged manifest. `compileSdk`/`targetSdk` inherit Flutter stable defaults.
  - [x] Established the feature-sliced layout under `apps/mobile/lib/`: `storage/`, `lore/` (placeholder), `ai/` (placeholder), `app/` (thin UI), `main.dart` composition root. No top-level `domain/`/`adapters/`/`ui/` folders.
  - [x] `apps/mobile/.gitignore` from `flutter create` is present; `build/` is ignored (verified — no build artifacts tracked).
- [x] **Task 2 — Define the `RepoStorage` port (AC: 3)**
  - [x] `storage/repo_storage.dart`: pure port `RepoStorage` (abstract interface) with `listDir`, `read`, `writeAtomic`, `exists`, plus `rootPath`. No `dart:io`/Flutter/network imports.
  - [x] Documented that paths are repo-relative and forward-slash normalized even on Android; added `RepoStorageException` so callers handle failures without importing `dart:io`.
  - [x] `RepoEntry` value type (name, forward-slash repo path, isDirectory) with value equality. Pure.
- [x] **Task 3 — Implement the all-files `dart:io` adapter (AC: 1, 3, 4)**
  - [x] `storage/all_files_repo_storage.dart`: `AllFilesRepoStorage implements RepoStorage` — the only file importing `dart:io`. Constructed with the absolute root; translates forward-slash repo paths ↔ real OS paths and normalizes backslash/leading-slash/`.` inputs.
  - [x] `listDir`/`read` (explicit UTF-8)/`exists` implemented fully; `writeAtomic` is a minimal same-dir temp+rename with a `// Story 1.2: harden byte-exactness …` marker (not gold-plated).
  - [x] `listDir` degrades to empty on `FileSystemException` (missing dir / permission), never throws; `read`/`writeAtomic` translate `FileSystemException` → `RepoStorageException` (no `dart:io` type leaks across the seam).
- [x] **Task 4 — Request all-files access (AC: 1, 4)**
  - [x] Declared `<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />`; verified present in the merged manifest.
  - [x] `storage/storage_permission.dart` gates the permission via `permission_handler` (`Permission.manageExternalStorage`) — kept inside `storage/` so the permission never leaks outside the slice. Home page checks on launch and requests when absent (routes to the system settings screen).
  - [x] `HomePage` is a `WidgetsBindingObserver` and re-checks on `AppLifecycleState.resumed`, so a grant made in Settings applies without an app restart. (App-lifecycle only — not the Epic 2 AD-10 model rescan.)
- [x] **Task 5 — Pick and persist the repo root (AC: 1, 2)**
  - [x] `app/root_picker_page.dart`: in-app directory browser over `RepoStorage.listDir` rooted at `kPrimaryExternalStorageRoot` (`/storage/emulated/0`), returning a **real path** — deliberately NOT a SAF `content://` URI.
  - [x] `storage/repo_root_store.dart` persists the root via `shared_preferences` (non-secret app config). `flutter_secure_storage` not used (reserved for Epic 4).
  - [x] On launch, a stored root skips the picker and goes straight to the ready state (covered by the "ready view" widget test + `repo_root_store_test`).
- [x] **Task 6 — Wire the composition root (AC: 3)**
  - [x] `main.dart` constructs `AllFilesRepoStorage` via a `storageFactory` and injects it as `RepoStorage`. Grep-verified `AllFilesRepoStorage` is named only in `main.dart`; the app depends only on the port.
  - [x] `app/home_page.dart` renders the three states — needs-permission, needs-root, ready (shows root path + top-level entries read through the seam). Thin; real browsing is Epic 2.
- [x] **Task 7 — Tests & analyze (AC: 5)**
  - [x] `test/storage/all_files_repo_storage_test.dart` covers path-joining, forward-slash normalization (incl. backslash/leading-slash inputs), `listDir`/`read`(UTF-8/Cyrillic)/`exists`/`writeAtomic` (+ no temp leftovers) against a temp dir. Plus `repo_root_store_test.dart` (persistence round-trip) and `widget_test.dart` (three states).
  - [x] `flutter analyze` clean; `flutter test` all pass; `flutter build apk --debug` succeeds. Default `analysis_options.yaml` (flutter_lints) retained.

### Review Findings

- [x] [Review][Decision] On-device smoke test — RESOLVED 2026-07-20: KseiPo ran the app on a physical Android device; grant → pick folder → relaunch-remembers works as expected. AC5 device-launch and the live AC1/AC4 grant flow are verified on hardware.
- [x] [Review][Patch] `..` segments escape the repo root — `_normalizeRepoPath` filters `''` and `.` but not `..`; `read('../../x')` resolves outside the root while the doc comment claims the guard is complete; no test covers it [apps/mobile/lib/storage/all_files_repo_storage.dart:98]
- [x] [Review][Patch] Barrel exports the concrete adapter, making the AD-9/AD-12 seam convention-only — any barrel importer can name `AllFilesRepoStorage`; stop exporting it and have `main.dart` import the internal file [apps/mobile/lib/storage/storage.dart:6]
- [x] [Review][Patch] Missing/inaccessible stored root renders as an empty "ready" repo — no `exists('')` check before ready state, and `listDir` maps permission-denied/mid-stream errors to `[]` (contract only promises empty for *missing dir*), so a vanished root looks like success [apps/mobile/lib/app/home_page.dart:80; apps/mobile/lib/storage/all_files_repo_storage.dart:38]
- [x] [Review][Patch] Reentrant refresh races — lifecycle-resume `_refresh` can interleave with an in-flight one (stale run overwrites fresh state); same pattern in the picker's un-awaited `_load` on rapid taps; add epoch guards [apps/mobile/lib/app/home_page.dart:57; apps/mobile/lib/app/root_picker_page.dart:37]
- [x] [Review][Patch] `openSettings()` fallback is dead code — documented as the permanent-denial recovery but no UI path calls it; wire it when `request()` returns false [apps/mobile/lib/app/home_page.dart:91]
- [x] [Review][Patch] `RepoStorageException` drops `osError` — callers can't distinguish not-found from permission-denied; carry the OS error detail into the exception [apps/mobile/lib/storage/all_files_repo_storage.dart:51]
- [x] [Review][Patch] Test gaps tracking the real bugs — no `..` traversal test, no Cyrillic **write→read** round-trip, no `writeAtomic` failure-path test [apps/mobile/test/storage/all_files_repo_storage_test.dart]
- [x] [Review][Patch] Picker allows selecting `/storage/emulated/0` itself as repo root — one mis-tap makes all of shared storage the repo; require confirmation for the storage root [apps/mobile/lib/app/root_picker_page.dart:60]
- [x] [Review][Patch] Android device path constant lives in the pure port file — `kPrimaryExternalStorageRoot` is platform config in `repo_storage.dart`; move it out of the port [apps/mobile/lib/storage/repo_storage.dart:97]
- [x] [Review][Patch] Template residue — stale "TODO: Specify your own unique Application ID" above the already-set ID; pubspec description still "A new Flutter project." [apps/mobile/android/app/build.gradle.kts:18; apps/mobile/pubspec.yaml:2]
- [x] [Review][Defer] Orphaned `*.tmp-*` files on process kill get synced by Syncthing — cleanup only runs on the exception path; a kill between write and rename leaves junk that propagates to every device [apps/mobile/lib/storage/all_files_repo_storage.dart:60] — deferred to Story 1.2 (writeAtomic hardening owns temp-file lifecycle: naming, sweep, fsync)
- [x] [Review][Defer] SD-card / secondary-volume repo roots unreachable — picker is hard-wired to `/storage/emulated/0` [apps/mobile/lib/app/root_picker_page.dart:33] — deferred, spec prescribed primary shared storage for v0.1; backlog enhancement
- [x] [Review][Defer] `writeAtomic` parent-directory semantics undefined — whether parents are created is unspecified/untested; Epic 2 create ops (FR24/25) must decide [apps/mobile/lib/storage/repo_storage.dart:80] — deferred to Epic 2 create stories
- [x] [Review][Defer] No error stage for plugin-channel failures — a throwing `SharedPreferences`/permission channel leaves an eternal spinner [apps/mobile/lib/app/home_page.dart:57] — deferred, rare platform failure; v0.2 polish
- [x] [Review][Defer] `setString` failure silently loses the chosen root [apps/mobile/lib/storage/repo_root_store.dart:19] — deferred, rare platform failure; v0.2 polish
- [x] [Review][Defer] Release builds sign with debug keys [apps/mobile/android/app/build.gradle.kts:32] — deferred until a real release build matters (sideloaded debug APK is current reality)

## Dev Notes

### What this story is (and is not)

This is the **foundation story** for the whole app: it stands up `apps/mobile/` and establishes the **`RepoStorage` seam** that every later slice depends on. It delivers a _real user action_ (grant → pick root → remembered) but deliberately stops short of reading/rendering lore (Epic 2) and short of the rigorous atomic write (Story 1.2). Keep it thin; resist building browsing UI or hardening `writeAtomic` here.

### Architecture guardrails (must follow)

- **AD-3 / NFR3 — the seam is the point.** Domain and UI depend **only** on `RepoStorage` (`listDir`, `read`, `writeAtomic`, `exists`). No `dart:io` and no `MANAGE_EXTERNAL_STORAGE` reference may exist outside the `storage/` slice's adapter file. This is what keeps a future SAF backend or app-private+git working copy a _root-path swap, not a rewrite_. [Source: ARCHITECTURE-SPINE.md#AD-3; prd.md#NFR3; addendum.md §A]
- **AD-9 — per-slice purity at file granularity.** The `RepoStorage` port and any model types are **pure Dart** (no `dart:io`, no network, no Flutter imports). All I/O lives only in the adapter file. There is **no** top-level `domain/`/`adapters/`/`ui/` layout. [Source: ARCHITECTURE-SPINE.md#AD-9]
- **AD-12 — feature-sliced packaging, private internals.** `lore/`, `storage/`, `ai/` are flat peer slices under `lib/`; each exposes a public interface (its port/barrel). Other slices depend only on that interface, never on internal files. `main.dart` is the composition root and the only place that wires a concrete adapter to a port. [Source: ARCHITECTURE-SPINE.md#AD-12; #Structural Seed]
- **AD-4 (relevant, deferred here).** Every write is atomic + byte-exact (temp-in-same-dir + rename; preserve EOL/trailing newline; explicit UTF-8). Story 1.1 only needs the port method to _exist_; **Story 1.2 proves it safe** against a live syncer. Do not fully implement byte-exactness here, but do not implement a naive non-atomic write that Story 1.2 must rip out — a temp+rename stub is the right seed. [Source: ARCHITECTURE-SPINE.md#AD-4; epics.md Story 1.2]
- **Identity contract.** Repo-relative path IDs are **forward-slash normalized even on Android** (`characters/selena/selena.md`, never backslash). The adapter converts between forward-slash repo paths and real OS paths. [Source: ARCHITECTURE-SPINE.md#Consistency Conventions; project-context.md "Cross-implementation contract rules"]
- **AD-1 boundary — what may be persisted.** Derived model data is never persisted. The chosen **repo root path is user configuration**, not derived data — persisting it (via `shared_preferences`) is fine and expected. Do not build any app database or cache of file contents. [Source: ARCHITECTURE-SPINE.md#AD-1]

### Storage & permission decision (why all-files, why real paths)

The heavy `MANAGE_EXTERNAL_STORAGE` permission is a **consequence of external sync**, deliberately chosen over SAF so the Dart loader can use real `dart:io` paths and stay a near-line-for-line mirror of `lib/lore.js`. SAF was **rejected** because `DocumentFile` traversal diverges from the path contract, turning the loader into a rewrite. Android 11+ is assumed (scoped-storage era). Not Play-Store-distributable — irrelevant for a sideloaded personal tool. [Source: addendum.md §A; prd.md §7]

> **Picker must return a real path (disaster to avoid).** Because the whole design rests on real `dart:io` paths, do **not** use a SAF-based directory picker (e.g. `file_picker`'s `getDirectoryPath`, which on Android returns a `content://` document-tree URI). Once `MANAGE_EXTERNAL_STORAGE` is granted, the app can enumerate the real filesystem itself — so the "picker" should be an in-app directory browser over `RepoStorage.listDir` rooted at primary shared storage (conventionally `/storage/emulated/0`), returning the selected real path. A `content://` URI stored as the root will silently break the entire loader in Epic 2. [Source: addendum.md §A]

### Permission mechanics (Android 11+)

`MANAGE_EXTERNAL_STORAGE` is a special "All files access" permission: it is **not** granted by a normal runtime dialog — the OS opens a Settings screen where the user toggles the app on. Plan for: manifest declaration; a launch-time check of the current state; an intent to the "All files access" settings screen; and a **resume-time re-check** so a grant made in Settings applies without restarting the app (AC4). `permission_handler`'s `Permission.manageExternalStorage` wraps this; the dev should confirm it is the current best-maintained option at scaffold time. [Source: epics.md Story 1.1 AC; addendum.md §A]

### Suggested slice layout (illustrative, not prescriptive beyond AD-9/AD-12)

```text
apps/mobile/
  lib/
    storage/
      repo_storage.dart          # PURE port: RepoStorage + RepoEntry
      all_files_repo_storage.dart# ONLY file importing dart:io / permission
      repo_root_store.dart        # persists chosen root (shared_preferences)
      storage.dart                # barrel (public interface of the slice)
    lore/                         # placeholder for Epic 2 (may be empty/stub)
    ai/                           # placeholder for Epic 4 (may be empty/stub)
    app/                          # thin launch UI: permission / pick-root / ready
    main.dart                     # composition root — builds adapter, injects port
  android/app/src/main/AndroidManifest.xml   # MANAGE_EXTERNAL_STORAGE
  test/
    storage/all_files_repo_storage_test.dart
```

(If the permission-gate/landing UI grows, it can live in its own `app/` or under a slice — keep it thin and out of `storage/` internals.)

### Proposed `RepoStorage` port (finalize signatures during impl)

```dart
/// Pure port. Paths are repo-relative and forward-slash normalized,
/// even on Android. No dart:io / Flutter / network in this file.
abstract interface class RepoStorage {
  Future<List<RepoEntry>> listDir(String path);
  Future<String> read(String path);              // explicit UTF-8 decode
  Future<void> writeAtomic(String path, String contents); // Story 1.2 hardens byte-exactness
  Future<bool> exists(String path);
}
```

`writeAtomic`'s final signature (how EOL/trailing-newline preservation is expressed) is settled in **Story 1.2**; keep it minimal-but-atomic here.

### Testing standards

- Unit-test the adapter against a real temp directory (`Directory.systemTemp`) — the one place `dart:io` in tests is fine. Assert path joining and **forward-slash normalization** of repo-relative paths, plus `listDir`/`read`/`exists` behavior and graceful handling of a missing path.
- `flutter analyze` clean; `flutter test` green. Widget/permission-flow tests are not required for this story (permission is device-driven); a smoke test that the app builds and the composition root wires an adapter is enough.
- The JS reference core (`lib/lore.js`) and shared fixtures (`test/fixtures/lore-model/`) are **not exercised** by this story — model conformance (NFR2) begins with the loader port in Story 2.1a.

### Project Structure Notes

- **Greenfield:** no `apps/` directory exists yet (confirmed) — this story creates `apps/mobile/`. Target monorepo layout per addendum §G places the Flutter app beside the existing JS core (`lib/`), `public/`, and shared `test/fixtures/`. Do not disturb the existing Node reference implementation. [Source: addendum.md §G; project-context.md]
- **Operational envelope:** single-user sideloaded app — no backend, no accounts, no CI/CD required (built locally). No network in this story (offline-first, NFR4). [Source: ARCHITECTURE-SPINE.md#Structural Seed]

### Library / version policy

The architecture **deliberately does not pin exact Flutter channel or package versions** — they are pinned at scaffold (`flutter create` / `flutter pub add`) against current stable, not asserted upstream. Recommended packages for this story: `permission_handler` (all-files access), `shared_preferences` (persist root path). Pin whatever is current-stable at scaffold and record the chosen versions in `pubspec.yaml`; verify each is actively maintained before adopting. `flutter_secure_storage` is **not** used here — it is reserved for the AI key in Epic 4. [Source: ARCHITECTURE-SPINE.md#Stack, #Deferred]

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1 · Story 1.1] — user story, ACs (FR1, NFR3)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR1] and #NFR3, #NFR4, #§7 (Android 11+, no telemetry)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/addendum.md#A] (storage/permission decision, RepoStorage seam, SAF rejected) and #G (target layout)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-3] (seam), #AD-9 (per-slice purity), #AD-12 (slicing), #AD-1 (persistence boundary), #Structural Seed, #Consistency Conventions, #Stack
- [Source: _bmad-output/project-context.md] (forward-slash path normalization; UTF-8 first-class; thin-shell rule)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- `flutter analyze` → **No issues found** (after fixing two initial lints: an unused `material.dart` import in `widget_test.dart` and a `prefer_initializing_formals` on the test-only `FakeRepoStorage`).
- `flutter test` → **15 passing** (adapter unit tests over a temp dir; root-store persistence round-trip; three-state widget tests).
- `flutter build apk --debug` → initially failed on `shared_preferences_android:compileDebugKotlin` with "Could not close incremental caches" (`*.tab` file-locking, a known Kotlin-incremental flake on this Windows toolchain — **not** an app compile error, reproduced after `flutter clean`). Resolved by adding `kotlin.incremental=false` to `android/gradle.properties`; **build then succeeded** (`app-debug.apk`).
- Merged manifest verified: `minSdkVersion="30"` and `MANAGE_EXTERNAL_STORAGE` both present.
- Seam invariant grep-verified: no `dart:io` import, no `permission_handler`/`MANAGE_EXTERNAL_STORAGE` reference, and no `AllFilesRepoStorage` construction outside `storage/` (the sole `AllFilesRepoStorage` reference is in `main.dart`, the composition root).

### Completion Notes List

- **All 5 ACs satisfied**, with one honest caveat: **AC5's "launches on an Android 11+ device/emulator"** could not be exercised — no Android device/emulator is connected to this host (only Windows/Chrome/Edge). Verified instead by a successful `flutter build apk --debug` (proves minSdk 30 + manifest permission + plugin Android integration compile) plus green analyze/test. **The live grant flow (AC1/AC4 on-device) needs KseiPo's phone** — recommend a quick manual smoke: install the APK, tap Grant access → toggle in Settings → return → pick a Syncthing folder → confirm it's remembered on relaunch.
- **Scope held to Story 1.1:** `writeAtomic` is a minimal same-dir temp+rename seed with an explicit `// Story 1.2:` marker — byte-exact/EOL-preserving hardening is deliberately left to Story 1.2. No browsing UI (Epic 2) built.
- **Design choices worth noting for review:** (1) the storage *permission* service lives inside `storage/` (not `app/`) so the permission never leaks past the slice boundary, satisfying AC3 strictly; (2) the repo-root picker is an in-app real-path directory browser over the seam, deliberately **not** a SAF `content://` picker (addendum §A); (3) `RepoStorageException` keeps `dart:io` exception types from crossing the port.
- **New dependencies (within story guidance):** `permission_handler ^12.0.3`, `shared_preferences ^2.5.5`.
- **`--platforms=android`** used at scaffold (Android-only app; keeps the tree lean and iOS is unbuildable on this Windows host).

### File List

**Created (app source):**
- `apps/mobile/lib/main.dart` (composition root; replaced the scaffold counter app)
- `apps/mobile/lib/storage/repo_storage.dart`
- `apps/mobile/lib/storage/all_files_repo_storage.dart`
- `apps/mobile/lib/storage/repo_root_store.dart`
- `apps/mobile/lib/storage/storage_permission.dart`
- `apps/mobile/lib/storage/android_storage.dart` (added in review: `kPrimaryExternalStorageRoot`, moved out of the pure port)
- `apps/mobile/lib/storage/storage.dart` (barrel)
- `apps/mobile/lib/lore/lore.dart` (placeholder slice)
- `apps/mobile/lib/ai/ai.dart` (placeholder slice)
- `apps/mobile/lib/app/app.dart`
- `apps/mobile/lib/app/home_page.dart`
- `apps/mobile/lib/app/root_picker_page.dart`

**Created (tests):**
- `apps/mobile/test/widget_test.dart` (replaced the scaffold counter test)
- `apps/mobile/test/fakes.dart`
- `apps/mobile/test/storage/all_files_repo_storage_test.dart`
- `apps/mobile/test/storage/repo_root_store_test.dart`

**Modified (Android config):**
- `apps/mobile/android/app/build.gradle.kts` (minSdk = 30)
- `apps/mobile/android/app/src/main/AndroidManifest.xml` (MANAGE_EXTERNAL_STORAGE; app label "Lore & Story")
- `apps/mobile/android/gradle.properties` (kotlin.incremental=false — Windows toolchain workaround)
- `apps/mobile/pubspec.yaml` (+ permission_handler, shared_preferences)

**Generated by `flutter create`** (not individually listed): the rest of `apps/mobile/` (Gradle wrapper, resources, `analysis_options.yaml`, `pubspec.lock`, etc.).

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-20 | Implemented Story 1.1: scaffolded `apps/mobile/` (Flutter, Android, minSdk 30), established the `RepoStorage` seam (pure port + `dart:io` adapter + root persistence + permission service in `storage/`), wired the composition root, and added a thin three-state landing UI + real-path repo picker. Tests: 15 passing; analyze clean; debug APK builds. Status → review. |
| 2026-07-20 | Addressed code review: 10 patch findings fixed. `..` traversal closed in `_normalizeRepoPath` (+test); barrel no longer exports the concrete adapter (seam now structural, not documented — `main.dart` imports the adapter directly); vanished/inaccessible root routes to re-pick via `exists('')` instead of showing an empty repo; epoch guards on `_refresh` and picker `_load` fix reentrancy races; `openSettings()` wired as the permission fallback; `RepoStorageException` now carries `osErrorCode`; storage-root selection requires confirmation; `kPrimaryExternalStorageRoot` moved out of the pure port into `android_storage.dart`; template residue removed (build.gradle TODO, pubspec description); added `..`-traversal, Cyrillic write→read, and `writeAtomic` failure tests. On-device smoke confirmed passing by KseiPo. Tests: 18 passing; analyze clean. 6 findings deferred (logged in `deferred-work.md`). Status → done. |
