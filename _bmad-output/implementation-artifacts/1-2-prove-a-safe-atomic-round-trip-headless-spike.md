---
baseline_commit: ade0c1119bc18bc337f02ef23413c2e16cc4bc42
---

# Story 1.2: Prove a safe atomic round-trip (headless spike)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the app to read one file and write it back without the syncer ever seeing a partial or conflicting file,
so that I can trust it with my repo before any UI exists.

## Acceptance Criteria

1. **AC1 (FR15 / NFR1 — atomic, byte-exact write):** Given a granted Syncthing'd folder containing a `.ru.md` file, when the app reads it and writes it back via a debug trigger, then the write is atomic (temp file in the same directory + rename) and byte-identical — original EOL and trailing newline preserved, explicit UTF-8 encode/decode, no byte changed.
2. **AC2 (S1 — no conflict copy):** Given the write completes, when I check the desktop, then Syncthing has propagated the file with no `*.sync-conflict-*` copy and no leftover temp file.
3. **AC3 (NFR7 — malformed never throws on read):** Given a malformed or unexpected file (invalid UTF-8 bytes), when it is read, then reading never throws — content is handled as-is (best-effort decode), and the round-trip trigger reports the outcome instead of crashing.
4. **AC4 (temp-file lifecycle):** Given a prior write was interrupted (leaving an orphaned temp file), when the app next writes into that directory, then stale temp files matching the app's temp pattern are swept, so orphans do not accumulate in — or get propagated by — the synced repo.
5. **AC5 (scaffold hygiene):** Given a clean checkout, when I run the app from `apps/mobile/`, then `flutter analyze` is clean and `flutter test` passes, including new byte-exactness and malformed-read tests.

## Tasks / Subtasks

- [x] **Task 1 — Make `read` total: never throw on malformed content (AC: 3)**
  - [x] `read` now reads raw bytes then `utf8.decode(bytes, allowMalformed: true)` — invalid UTF-8 yields U+FFFD instead of throwing (NFR7 / AD-8).
  - [x] Genuine failures still throw: a missing file / I/O error → `RepoStorageException` (with `osErrorCode`). Only content decoding is total.
  - [x] Port doc updated: `read` is best-effort; a malformed file is not guaranteed byte-exact on write-back. **Refinement discovered during impl:** `utf8.decode` also strips a leading BOM, so `read` now re-attaches a `U+FEFF` when the raw bytes start with `EF BB BF` — otherwise BOM'd files (Windows editors write them) would lose 3 bytes on save.
- [x] **Task 2 — Harden `writeAtomic` to byte-exact + robust (AC: 1, 2)**
  - [x] Writes `utf8.encode(contents)` verbatim via `writeAsBytes` — no newline translation, no trimming; EOL and trailing newline preserved. (BOM preservation handled on the read side, see Task 1.)
  - [x] Temp-in-same-dir + `rename` kept, `flush: true`; the `// Story 1.2:` seed marker removed.
  - [x] On failure: `FileSystemException` → `RepoStorageException`, best-effort temp cleanup.
  - [x] Byte-exactness proven by the round-trip byte-compare tests (Task 5).
- [x] **Task 3 — Temp-file naming + stale-temp sweep (AC: 2, 4)**
  - [x] Temp name is `.lore-tmp-<basename>-<micros>-<rand>` (hidden, greppable, collision-proof) in the target directory.
  - [x] `_sweepStaleTemps` deletes pre-existing `.lore-tmp-*` in the target dir before writing (best-effort, never fails the write) — closes the deferred orphan-temp finding from the Story 1.1 review.
  - [x] Recorded (code comment + Dev Notes) that Story 2.1b's walk must skip `.lore-tmp-*`. Walk not implemented here.
- [x] **Task 4 — Headless round-trip debug trigger (AC: 1, 2, 3)**
  - [x] `storage/round_trip_spike.dart`: `RoundTripSpike.run` reads → `writeAtomic` → re-reads and returns a `SpikeResult` (identical? + a handled detail note); never throws. `findFirstMatching` BFS-finds a `.ru.md`, bounded by `maxNodes`.
  - [x] Ready-view "Run atomic round-trip" button finds the first `.ru.md`, runs the spike, and shows the result in a dialog; "no .ru.md found" when none.
  - [x] Malformed/missing files surface as a dialog message, never a crash (AC3).
- [x] **Task 5 — Tests (AC: 1, 3, 4, 5)**
  - [x] Byte-exact round-trip asserting **raw bytes** equal, across LF, CRLF, no-trailing-newline, leading BOM, and Cyrillic.
  - [x] Malformed read returns a string containing U+FFFD without throwing (NFR7).
  - [x] Temp lifecycle: no `.lore-tmp-*` remains after a write; a pre-seeded stale temp is swept on the next write.
  - [x] `RoundTripSpike`: identical=true for well-formed, identical=false-without-throw for malformed and for a missing file; `findFirstMatching` finds a nested `.ru.md` / returns null.
  - [x] `flutter analyze` clean; `flutter test` green (30 passing).
- [x] **Task 6 — On-device S1 verification (AC: 2) — DONE 2026-07-20**
  - [x] KseiPo ran it on a real Android 11+ device against a Syncthing'd folder: the round-trip propagated to the desktop with **no `*.sync-conflict-*` copy and no leftover `.lore-tmp-*`**. S1 acceptance gate PASSED — the atomic byte-exact write loop is proven safe end-to-end on real hardware.

### Review Findings

- [x] [Review][Patch] Spike corrupts a malformed file — `RoundTripSpike.run` computes `malformed` but calls `writeAtomic(path, before)` **unconditionally**, so running the debug button on a malformed `.ru.md` writes the lossy U+FFFD-substituted buffer back over the real file (data loss on exactly the files NFR7 protects). Gate the write behind `!malformed` and report "skipped to avoid corruption." [apps/mobile/lib/storage/round_trip_spike.dart:35]
- [x] [Review][Patch] Double-BOM drops a BOM (byte-exactness violation for well-formed input) — the `!decoded.startsWith(bom)` guard suppresses the re-attach exactly when a file legitimately starts with two BOMs (`utf8.decode` strips only the first). Remove the guard — `hasBom ? '$bom$decoded' : decoded` is correct for any N≥1 leading BOMs on the pinned SDK (which strips exactly one). Add a double-BOM test. [apps/mobile/lib/storage/all_files_repo_storage.dart:63]
- [x] [Review][Patch] Sweep deletes a concurrent write's in-flight temp — `_sweepStaleTemps` deletes **every** `.lore-tmp-*` in the target dir, so two overlapping `writeAtomic` calls into the same directory (even to different files) can collide: one's sweep unlinks the other's mid-flush temp → spurious `RepoStorageException`. Scope both the temp name and the sweep to the target's basename (`.lore-tmp-<basename>-*`). Latent in v0.1 (single write path) but this is the primitive Epic 2 leans on. [apps/mobile/lib/storage/all_files_repo_storage.dart:79]
- [x] [Review][Patch] Spike descends into syncer metadata — `findFirstMatching` BFS enqueues every directory, including `.stfolder`/`.stversions` (which hold versioned `.ru.md` copies) and `media/`, so the spike can pick and atomic-rewrite a file inside the syncer's private archive. Skip dot-dirs and `media/` when enqueuing (also the recorded Story 2.1b walk contract). [apps/mobile/lib/storage/round_trip_spike.dart:70]
- [x] [Review][Patch] Empty/degenerate write path escapes the root for sweep+temp — for a path that normalizes to empty, `_toOsPath('')` returns `_root` and `_dirname(_root)` is the **parent** of the repo root, so the sweep and temp creation happen outside the sandbox before `rename` fails. Not reachable in 1.2 (no caller passes empty) but a hole in the write primitive; guard `writeAtomic` to throw on an empty normalized path. [apps/mobile/lib/storage/all_files_repo_storage.dart:57]
- [x] [Review][Defer] No directory fsync after `rename` — the rename's directory entry isn't fsync'd, so a power-loss window can lose the rename though the bytes were flushed. NFR1 targets "no partial file" (rename satisfies); durability beyond that is out of v0.1 scope and the syncer re-propagates. [apps/mobile/lib/storage/all_files_repo_storage.dart:94]
- [x] [Review][Defer] `_sweepStaleTemps` lists the whole directory on every write (O(n) I/O per save) — cheap-enough for v0.1 repo sizes; revisit for NFR6 if a directory grows large. [apps/mobile/lib/storage/all_files_repo_storage.dart:79]
- [x] [Review][Defer] Temp name can exceed the 255-byte filename limit for a near-limit basename → `ENAMETOOLONG`. Very rare (lore slugs are short); bound the basename portion if it ever bites. [apps/mobile/lib/storage/all_files_repo_storage.dart:85]

## Dev Notes

### What this story is (and why it matters most)

This is the **S1 acceptance gate** and the MOBILE §3.4 first-spike: prove the
storage + sync write loop is safe *before* any browsing/editing UI is built on it.
Story 1.1 left `writeAtomic` as a minimal temp+rename seed with an explicit
`// Story 1.2:` marker and a `read` that throws on malformed bytes. This story
turns that seed into the real, byte-exact, crash-safe, syncer-safe write path and
proves it round-trips on a real device with no conflict copy. Everything in Epic 2
writes through this method — get it exactly right here.

### Byte-exactness vs. malformed input — the key design decision

The port stays **string-based** (`read` → `String`, `writeAtomic(path, String)`) —
"explicit UTF-8" per AC1/AD-4, not a raw-bytes API.

- **Well-formed UTF-8 is byte-exact.** UTF-8 has a single canonical encoding per
  code point, so `utf8.decode` then `utf8.encode` is the identity for valid input.
  EOL (`\n` vs `\r\n`) and the trailing newline live inside the string, so writing
  the string verbatim preserves them. A leading BOM (`U+FEFF`) is a normal code
  point — Dart's UTF-8 decoder does **not** strip it, and it re-encodes to
  `EF BB EF`, so it round-trips. `writeAtomic` must therefore never trim, normalize
  newlines, add/strip a BOM, or otherwise touch bytes — encode the string as-is.
- **Malformed input is decoded best-effort (`allowMalformed: true`) so `read`
  never throws (NFR7).** Invalid bytes become `U+FFFD`, which means a malformed
  file is **not** guaranteed byte-exact if written back. That is acceptable: AC3
  requires only that malformed *read* not throw, and the project's real repo files
  are well-formed UTF-8. If a future story needs to edit-and-preserve genuinely
  malformed bytes, add a bytes-level path then — do **not** add it now (YAGNI;
  keeps the Dart↔JS-adjacent surface minimal).

[Source: prd.md#FR15, #NFR1, #NFR7; ARCHITECTURE-SPINE.md#AD-4, #AD-8; project-context.md "Parsing & File-Writing Rules", "Files are UTF-8"]

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/storage/all_files_repo_storage.dart`** — the only `dart:io`
  file. Current state: `read` uses `readAsString(encoding: utf8)` (throws on
  malformed — the NFR7 bug to fix); `writeAtomic` is `writeAsString(..., utf8,
  flush: true)` to a `.tmp-<micros>` sibling then `rename`, with cleanup on
  failure and the `// Story 1.2:` marker. **Preserve:** the path normalization
  (strips `.`/`..`/absolute — do not regress the traversal guard), the
  `RepoStorageException` translation with `osErrorCode`, and `listDir`/`exists`
  behavior. Only `read`, `writeAtomic`, and temp handling change.
- **`apps/mobile/lib/storage/repo_storage.dart`** — the pure port. Update the
  `read` and `writeAtomic` doc comments to state the finalized contract
  (best-effort decode; byte-exact-for-well-formed write). No signature change.
- **`apps/mobile/lib/app/home_page.dart`** — add the debug round-trip action to
  the ready view (`_ReadyView`). Keep it thin; it depends only on the injected
  `RepoStorage`, never on the concrete adapter. Do not touch the epoch-guard /
  vanished-root logic added by the prior review.
- **`apps/mobile/lib/storage/storage.dart`** (barrel) — export the new
  `RoundTripSpike` helper if it should be visible to `app/`. Do **not** export the
  concrete `AllFilesRepoStorage` (that invariant was just tightened in review).

### Architecture guardrails

- **AD-4 — every write is atomic and byte-exact.** Temp-in-same-dir + rename;
  byte-exact except the intended change (here: no change at all); explicit UTF-8;
  never platform-default encoding. [ARCHITECTURE-SPINE.md#AD-4]
- **AD-5 — the external syncer owns propagation.** The app never syncs/merges. A
  clean atomic write is what keeps Syncthing from producing a conflict copy. The
  temp name must be one the syncer won't mistake for content and (Epic 2) the walk
  will skip. [ARCHITECTURE-SPINE.md#AD-5]
- **AD-8 — parsing/reads are total (never throw).** Malformed bytes are content to
  handle, not a fault. [ARCHITECTURE-SPINE.md#AD-8]
- **AD-3 / AD-9 — the seam.** All of this lives in the `storage/` adapter behind
  `RepoStorage`; the debug trigger in `app/` uses only the port. No `dart:io`
  outside the adapter. [ARCHITECTURE-SPINE.md#AD-3, #AD-9]

### Testing standards

- Unit-test the adapter against a real temp directory (`Directory.systemTemp`) —
  the only place `dart:io` in tests is allowed. Assert **byte-level** identity
  (`readAsBytes`), not just string equality, so EOL/BOM/trailing-newline
  preservation is genuinely proven.
- CRLF caution on Windows CI: construct test fixtures with explicit `\r\n` in Dart
  string literals and write via `writeAsBytes` so the git `autocrlf` setting can't
  mutate the fixture on disk. Assert against the exact bytes you wrote.
- Note the atomic-replace-over-existing-target behavior: on the Android/POSIX
  target `rename(2)` atomically replaces; the Story 1.1 tests already showed
  `File.rename` over an existing file succeeds on this Windows/Dart toolchain, so
  the overwrite test stays valid in CI.

### Previous story intelligence (Story 1.1 — done)

- `writeAtomic` seed and the `read`-throws-on-malformed behavior are the two things
  this story changes; everything else in the adapter is settled and reviewed.
- The seam is **structural**: `AllFilesRepoStorage` is not exported from the barrel;
  only `main.dart` names it. Keep it that way — the spike helper and UI use the port.
- Toolchain: `flutter analyze` + `flutter test` is the loop; the Android build needs
  `kotlin.incremental=false` (already set) on this Windows host.
- Deferred from the Story 1.1 review and **owned by this story**: orphaned `*.tmp-*`
  files getting synced (Task 3). The `writeAtomic` parent-directory-creation question
  remains deferred to Epic 2 create ops — do not solve it here.

### Git intelligence

Latest commit `ade0c11` "Scaffold mobile app and RepoStorage seam (Story 1.1)" on
branch `story/1.1-scaffold-app`. This story continues from that tree.

### Library / version policy

No new dependencies. `dart:convert` (`utf8`) and `dart:io` (already imported in the
adapter) cover everything. If the spike helper needs randomness for temp names, use
`dart:math` `Random` — no package.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1 · Story 1.2] — user story, ACs (FR15, NFR1, S1, NFR7)
- [Source: prd.md#FR15] (atomic byte-exact write), #NFR1 (write integrity, critical), #NFR7 (malformed never crashes), #S1 (round-trip acceptance gate, §3)
- [Source: addendum.md#F] (first spike — non-UI, on-device) and #E (new Dart atomic UTF-8 writer; syncer-aware walk skips temp/`*.sync-conflict-*`)
- [Source: ARCHITECTURE-SPINE.md#AD-4, #AD-5, #AD-8, #AD-3, #AD-9]
- [Source: _bmad-output/project-context.md] (surgical byte-exact writes; UTF-8 first-class; malformed as content)
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] (orphaned temp-file item, now owned here)

## Dev Agent Record

### Agent Model Used

claude-fable-5 (Claude Fable 5)

### Debug Log References

- `flutter analyze` → No issues found.
- `flutter test` → **30 passing** (was 18; +12 for byte-exactness, malformed read, temp sweep, and the round-trip spike).
- One real defect caught by the tests during impl: the initial "just re-encode the string" approach failed the **BOM round-trip** test — verified via a scratch `dart` snippet that `utf8.decode` strips a leading `EF BB BF`, so a BOM'd file lost 3 bytes on save. Fixed by re-attaching `U+FEFF` in `read` when the raw bytes start with a BOM. Re-ran: all green.

### Completion Notes List

- **Tasks 1–5 complete and verified; Task 6 (on-device S1 propagation check) is PENDING** — it needs KseiPo's phone + Syncthing and cannot run in CI. The "Run atomic round-trip" trigger is implemented and ready; the physical no-conflict-copy confirmation is the manual gate (same shape as the Story 1.1 device smoke). Story is at `review` with that one item outstanding.
- **`writeAtomic` is now genuinely byte-exact for well-formed UTF-8**, proven at the byte level across LF/CRLF/no-trailing-newline/BOM/Cyrillic. The design decision holds: string-based port, best-effort decode for NFR7, malformed files explicitly not byte-guaranteed.
- **BOM handling was the non-obvious part.** Dart's `utf8.decode` silently strips a leading BOM; since Windows editors/PowerShell on this project write BOMs (per project-context), `read` re-attaches `U+FEFF` so a save never drops it. Without this, "byte-exact except the intended change" would have been quietly violated for any BOM'd file.
- **Deferred item from the Story 1.1 review is closed here:** orphaned `.lore-tmp-*` files are swept from the target directory before each write, and the temp name is hidden + distinctive so a transient temp isn't mistaken for content.
- **Contract recorded for Epic 2:** the syncer-aware walk (Story 2.1b) must skip `.lore-tmp-*` (noted in code + Dev Notes).
- No new dependencies; `dart:convert` + `dart:io` + `dart:math` only.

### File List

**Modified:**
- `apps/mobile/lib/storage/all_files_repo_storage.dart` (total `read` with BOM preservation; byte-exact `writeAtomic`; `_sweepStaleTemps`, `_dirname`, `_tmpPrefix`, `_rand`)
- `apps/mobile/lib/storage/repo_storage.dart` (finalized `read`/`writeAtomic` doc contract)
- `apps/mobile/lib/storage/storage.dart` (barrel exports `round_trip_spike.dart`)
- `apps/mobile/lib/app/home_page.dart` (debug "Run atomic round-trip" trigger + result dialog)
- `apps/mobile/test/storage/all_files_repo_storage_test.dart` (byte-exact, malformed, temp-sweep tests; temp-prefix update)

**Created:**
- `apps/mobile/lib/storage/round_trip_spike.dart` (`RoundTripSpike`, `SpikeResult`, `findFirstMatching`)
- `apps/mobile/test/storage/round_trip_spike_test.dart`

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-20 | Implemented Story 1.2 (S1 acceptance gate): hardened `writeAtomic` to atomic + byte-exact (canonical UTF-8 written verbatim; EOL/trailing-newline/BOM preserved), made `read` total on malformed input (best-effort decode, NFR7) with BOM re-attachment, added hidden temp naming + stale-temp sweep (closing the Story 1.1 deferred orphan-temp finding), and added a headless `RoundTripSpike` + a debug "Run atomic round-trip" trigger. Tests 18 → 30 (byte-exact across LF/CRLF/no-newline/BOM/Cyrillic; malformed read; temp lifecycle; spike). analyze clean. Tasks 1–5 done; Task 6 (on-device S1 no-conflict-copy check) pending user's device. Status → review. |
| 2026-07-20 | Addressed code review (Opus 4.8 vs Fable impl): 5 patch findings fixed. Spike now **skips the write-back for a malformed file** (was corrupting it — data loss); removed the double-BOM guard (was dropping a BOM for well-formed files starting with two); scoped the temp name + stale-temp sweep to the target basename (was deleting a concurrent write's in-flight temp); `findFirstMatching` now skips dot-dirs + `media/` (was descending into `.stversions` and rewriting archived files); `writeAtomic` rejects an empty path (was escaping the root via `_dirname`). Tests 30 → 36 (double-BOM, empty content, empty-path guard, concurrent different-files, malformed-write-skip-no-corruption, metadata-skip). analyze clean. 3 findings deferred (fsync durability, sweep O(n), temp-name length). Task 6 (on-device S1) still pending. Status stays review. |
