# Lore & Story — Mobile

A thin Flutter/Android writing surface over a file-based Twine/SugarCube story
repo. It lets the author browse and edit the project's markdown layers — lore
entries and plain-prose scene files — from a phone, while an external syncer
(Syncthing/Dropbox/git) owns propagation. It is a *writing surface*, not the
desktop POC ported to a phone.

The lore loader is a Dart reimplementation of the reference `lib/lore.js`, kept
honest by the shared golden fixtures in `test/fixtures/lore-model/`. See
[`MOBILE.md`](../../MOBILE.md), the PRD, and the architecture spine under
`_bmad-output/planning-artifacts/` for the full design.

## Status

Story 1.1 (walking-skeleton foundation) is in: grant a repo folder, remember it
across launches, and the `RepoStorage` seam every later slice builds on. Browsing,
editing, and the atomic write path land in Story 1.2 and Epic 2.

## Architecture (feature-sliced, hexagonal)

Vertical slices under `lib/`; each co-locates its model, port(s), adapter(s), and
UI. There is no top-level `domain/`/`adapters/`/`ui/` — purity is enforced per
slice at file granularity.

| Path | Role |
| --- | --- |
| `lib/storage/` | `RepoStorage` port + all-files `dart:io` adapter + root persistence + storage-permission service |
| `lib/lore/` | lore model, entity-tree walk, convention matcher, browse/editor UI (Epic 2 — placeholder) |
| `lib/ai/` | AI client port + Messages-API adapter + secure key store (Epic 4 — placeholder) |
| `lib/app/` | thin landing UI: permission → pick-root → ready; real-path repo picker |
| `lib/main.dart` | composition root — the **only** place that names the concrete `AllFilesRepoStorage` adapter |

**Key invariant:** the loader/editor depend only on `RepoStorage`
(`listDir`/`read`/`writeAtomic`/`exists`). No `dart:io` and no
`MANAGE_EXTERNAL_STORAGE` reference exists outside the `storage/` slice. The
concrete adapter is not exported from the slice barrel — only `main.dart` imports
it directly. This keeps a future SAF or app-private+git backend a root-path swap,
not a rewrite.

## Storage model

All-files access (`MANAGE_EXTERNAL_STORAGE`, Android 11+) over real `dart:io`
paths, chosen so the Dart loader stays a near-line-for-line mirror of the JS
reference. The repo-root picker returns a **real path** (e.g.
`/storage/emulated/0/…`), never a SAF `content://` tree URI. The permission is
granted by the user on a system settings screen, not a runtime dialog.

## Develop

```sh
flutter pub get
flutter analyze          # must be clean
flutter test             # unit + widget tests
flutter build apk --debug
flutter run              # on a connected Android 11+ device/emulator
```

### Windows build note

`android/gradle.properties` sets `kotlin.incremental=false`. The Kotlin
incremental-compilation cache (`*.tab` files) fails to close on this Windows
toolchain ("Could not close incremental caches"), breaking plugin compilation;
disabling it is the standard workaround and does not affect build correctness.
Revisit if building from a different environment.
