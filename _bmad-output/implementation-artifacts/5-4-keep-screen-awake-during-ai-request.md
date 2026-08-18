---
baseline_commit: 4b589ea
---

# Story 5.4: Keep the screen awake during an in-flight AI request

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the app to keep my screen on while an AI request is streaming,
so that a slow local model (e.g. LM Studio on my LAN, tested in Story 4.8) has time to finish before Android puts the app to sleep and kills the connection out from under it.

## Context

**A real local-server test surfaced this.** A slow local model can legitimately take longer to respond than it takes for the screen to lock. Once the screen turns off, Android moves the app out of the foreground-active state, and the in-flight streaming request to `AiClient.sendMessage` gets killed before any text arrives. This is a client-side, OS-lifecycle problem — the *connection itself* is severed, so `RetryingHttpSender`'s own retry/backoff (Story 4.8) can't help; retrying a connection the OS just killed doesn't make the local model any faster, and the story doesn't need to touch that machinery at all.

**Why keeping the screen on actually fixes this:** the standard "keep screen awake" mechanism on Android (`FLAG_KEEP_SCREEN_ON` on the activity's window — what the `wakelock_plus` package uses under the hood, confirmed via its published docs, no `WAKE_LOCK` permission required) doesn't hold a CPU wake lock directly; it prevents the screen from *dimming/locking due to inactivity* in the first place. As long as the screen never turns off, the Activity never leaves the foreground-active lifecycle state, so Android's Doze/background network restrictions — the actual thing killing the connection — never engage. Keeping the app foregrounded is the mechanism; keeping the screen on is how this story achieves that, with no new Android permission.

**Where the fix belongs — the `AiClient` port itself, not each caller.** Three places currently consume `AiClient.sendMessage`'s stream directly:
- `runTranslate` (`apps/mobile/lib/ai/translate_action.dart:227-229`, `await for (final chunk in aiClient.sendMessage(request))`)
- `runGrammarReview` (`apps/mobile/lib/ai/grammar_action.dart:192-194`, same pattern)
- `SettingsPage._testConnection` (`apps/mobile/lib/app/settings_page.dart:189-197`, a `.listen(...)` + `Completer` pattern)

`AiClient` already reaches all three through **13 files'** worth of existing constructor-injection threading from `main.dart` (confirmed via grep for `AiClient aiClient`/`required this.aiClient`/`widget.aiClient`: `settings_page.dart`, `grammar_action.dart`, `translate_action.dart`, `home_page.dart`, `paired_editor_page.dart`, `undetermined_language_page.dart`, `grammar_panel.dart`, `entity_navigation.dart`, `entity_detail_page.dart`, `editor_page.dart`, `category_entities_page.dart`, `conflicts_page.dart`, `app.dart`). **Do not thread a new dependency through any of these 13 files.** Instead, wrap the fix as a **decorator implementing `AiClient`**, mirroring `ProtocolRoutingAiClient`'s exact shape and placement in `ai_client.dart:160-177` (itself a "**pure**, zero-I/O implementation of `AiClient`... belongs beside the interface it implements rather than in an adapter file," per that class's own doc comment). Composed once in `main.dart`, this means:
- `main.dart` is the **only** file that changes to wire this in.
- All 13 files, and every existing `FakeAiClient`-based test for translate/grammar/settings, stay **completely untouched** — they depend only on the `AiClient` interface, never on which concrete implementation backs it.
- Any *future* AI action automatically gets the same protection, with nothing to remember to wrap individually.

## Acceptance Criteria

1. **(Screen stays on for the duration of any AI request)** Given any call to `AiClient.sendMessage` — translate, grammar review, or Test Connection — when the returned stream is active (from the moment it's listened to until it completes, errors, or is cancelled), then the device screen is prevented from turning off due to inactivity for that whole span, and the wake-hold is released the instant the stream ends, however it ends.
2. **(No new dependency threading)** Given the 13 files that already thread `AiClient` from `main.dart` down to `runTranslate`/`runGrammarReview`/`SettingsPage`, when this story ships, then none of them change — the fix is composed once, at the composition root, as a decorator around the existing `AiClient` instance.
3. **(Never breaks a request, even if the wake mechanism itself fails)** Given the underlying screen-wake plugin call fails for any reason (unsupported platform state, plugin error), when that happens, then the AI request proceeds and reports its own real outcome exactly as it would have otherwise — a failure to hold the wake state is never surfaced as, or allowed to cause, an AI request failure. *(AD-8)*
4. **(Correct under cancellation, not just success/failure)** Given Story 4.7's own `SettingsPage._testConnection`/`_testSubscription` cancellation path (the screen is popped mid-test), when the stream is cancelled rather than completing or erroring, then the wake-hold is still released — never left stuck on indefinitely after the screen that triggered it is gone.
5. **(No behavior change beyond wake-state timing)** Given the request content, retry/backoff/timeout discipline, and every typed exception `AiClient.sendMessage` can already produce, when this story ships, then none of it changes — this story only wraps the span of an existing call, it does not alter what that call does or how it fails.

**Non-goals** (explicitly out of scope):
- No foreground service, background execution, or any fix for the app being fully backgrounded to a different app mid-request — this story only prevents the *screen* from turning off while the app stays the active foreground app; switching away to another app is a materially bigger problem (needs a persistent notification and Android foreground-service plumbing this app has none of today) and is not what was reported.
- No increase to retry/backoff/timeout budgets, and no change to how many attempts a transient failure gets — this story prevents the OS from severing the connection in the first place; it does not change what happens once a request has genuinely failed.
- No user-visible indicator that the screen is being held awake (no icon, no toast) — invisible, correct-by-default behavior, consistent with how retry/backoff itself is already invisible to the author.
- No wake-hold outside the span of an actual `AiClient.sendMessage` call — general app browsing/editing is unaffected; the device's normal screen-timeout behavior is untouched everywhere else.
- No iOS-specific consideration — this app targets Android 11+ only (existing project scope); `wakelock_plus` is cross-platform but this story's testing/verification is Android-only.

## Tasks / Subtasks

- [x] **Task 1: Add the `wakelock_plus` dependency** (AC: 1)
  - [x] 1.1 Run `flutter pub add wakelock_plus` from `apps/mobile/` — let pub resolve whatever the current stable version is rather than hand-pinning a version number in this story (current stable at time of writing is 1.7.0; verify compatibility with this project's `sdk: ^3.12.2` constraint, `pubspec.yaml:22`, at implementation time).
    *(Resolved to 1.7.0, matching the story's own prediction — compatible with `sdk: ^3.12.2`.)*
  - [x] 1.2 Verify (don't assume) whether any `AndroidManifest.xml` change is needed. Published docs state `wakelock_plus` requires no special permission on any platform (it uses `FLAG_KEEP_SCREEN_ON` on the window, not `PowerManager.WakeLock` + the `WAKE_LOCK` permission) — confirm this holds for the resolved version before assuming `apps/mobile/android/app/src/main/AndroidManifest.xml` needs no edit.
    *(Verified directly: inspected the resolved package's own `android/src/main/AndroidManifest.xml` in the pub cache — it declares only the package name, no `<uses-permission>` of any kind. No manifest edit needed.)*

- [x] **Task 2: `ScreenWakeLock` — the injectable seam (AD-9)** (AC: 1, 3)
  - [x] 2.1 New `apps/mobile/lib/ai/screen_wake_lock.dart`. Not exported from `ai/ai.dart`'s barrel (AD-12) — mirrors exactly why `messages_api_client.dart`/`openai_compatible_client.dart` are withheld: only `main.dart` (composition root) and this slice's own tests import it directly.
  - [x] 2.2 `abstract interface class ScreenWakeLock { Future<void> enable(); Future<void> disable(); }` — the seam that makes Task 3's decorator testable without a real platform channel (a widget/unit test environment has none), mirroring every other I/O boundary in this app (`KeyStore`, `RepoStorage`) having a pure interface with a real adapter and a test fake.
  - [x] 2.3 `class WakelockPlusScreenWakeLock implements ScreenWakeLock` — the real adapter, wrapping `WakelockPlus.enable()`/`WakelockPlus.disable()` from `package:wakelock_plus/wakelock_plus.dart`. **Both methods must swallow any exception and never rethrow** (wrap each in `try`/`catch`, no-op on failure, no logging — this app has no telemetry, NFR5) — this is not just AD-8 style compliance, it is **load-bearing for Task 3's correctness**: `WakeLockAiClient.sendMessage`'s `finally` block calls `disable()`, and if `disable()` itself could throw, it would **mask the real stream error** the `finally` block is unwinding from (a thrown exception inside a `finally` block replaces whichever exception was already propagating). `enable()` must be equally exception-safe for the symmetric reason on the way in.

- [x] **Task 3: `WakeLockAiClient` — the decorator** (AC: 1, 2, 3, 4, 5)
  - [x] 3.1 Add to `apps/mobile/lib/ai/ai_client.dart`, directly beside `ProtocolRoutingAiClient` (both are pure, zero-I/O `AiClient`-wrapping decorators composed once at the composition root — same reasoning `ProtocolRoutingAiClient`'s own doc comment already states for its own placement there). Import `screen_wake_lock.dart` at the top of `ai_client.dart` (an internal same-slice import — not a barrel violation, `ai_client.dart` is already the file other adapters import into).
    *(Impl note: this import means `ai_client.dart`'s compiled dependency graph transitively reaches `package:wakelock_plus`, in tension with the file's own top-of-file doc comment claiming "no Flutter imports live here" (AD-9) — `ai_client.dart`'s own import list stays literally Flutter-free (it only names the sibling `screen_wake_lock.dart` file), but the concrete `WakelockPlusScreenWakeLock` adapter bundled in that sibling file is transitively reachable. This is exactly what this task explicitly instructs, with its own stated reasoning ("an internal same-slice import — not a barrel violation"), so implemented as directed rather than deviating into a bigger unrequested restructuring; noting it here for visibility.)*
  - [x] 3.2 Add the same `// ignore_for_file: prefer_initializing_formals` reasoning already documented at the top of `ai_client.dart:9-15` covers this new class too (private fields, public constructor parameter names) — no new ignore comment needed, just confirm the existing file-level one still applies.
  - [x] 3.3 Implementation:
    ```dart
    class WakeLockAiClient implements AiClient {
      final AiClient _inner;
      final ScreenWakeLock _screenWakeLock;

      const WakeLockAiClient({
        required AiClient inner,
        required ScreenWakeLock screenWakeLock,
      })  : _inner = inner,
            _screenWakeLock = screenWakeLock;

      @override
      Stream<String> sendMessage(AiRequest request) async* {
        await _screenWakeLock.enable();
        try {
          yield* _inner.sendMessage(request);
        } finally {
          await _screenWakeLock.disable();
        }
      }
    }
    ```
    Doc-comment explaining: wraps any `AiClient` to hold the screen awake for the exact span of `sendMessage`'s stream (AC1); `finally` on an `async*` generator runs on normal completion, on an error propagating through, **and** on the subscription being cancelled (Dart's documented async-generator semantics) — so AC4's cancellation case is covered by this same block, not a separate code path. Cross-reference `ProtocolRoutingAiClient` as the sibling decorator this mirrors.
    *(Verified empirically, not just trusted: `test/ai/wake_lock_ai_client_test.dart`'s cancellation test genuinely cancels an in-flight subscription and confirms `disable()` still runs — passed on first try, confirming the documented semantics hold for this project's resolved SDK version.)*
  - [x] 3.4 `const` constructor, matching `ProtocolRoutingAiClient`'s own `const` constructor (`ai_client.dart:164`) — both classes hold only injected `final` references, no mutable state.

- [x] **Task 4: Wire it into the composition root** (AC: 1, 2)
  - [x] 4.1 `main.dart`: import `ai/screen_wake_lock.dart` (a direct file import, not via the barrel — same pattern already used for `messages_api_client.dart`/`openai_compatible_client.dart`, `main.dart:5-6`).
  - [x] 4.2 Wrap the **existing** `ProtocolRoutingAiClient` construction (`main.dart:24-27`) with the new decorator, outermost — the wake-hold applies uniformly regardless of which protocol adapter actually handles a given request.
    *(`WakeLockAiClient` itself didn't need its own barrel import — it's declared in `ai_client.dart`, already exported via the `ai/ai.dart` barrel `main.dart` already imports; only `screen_wake_lock.dart`'s `WakelockPlusScreenWakeLock` needed the new direct import, per Task 2.1's AD-12 withholding.)*
  - [x] 4.3 Nothing else in `main.dart` changes — `aiClient` continues to be threaded into `LoreStoryApp(aiClient: aiClient, ...)` exactly as before; from that point down through all 13 files, `aiClient`'s static type is still `AiClient`, so no other file needs to know `WakeLockAiClient` exists at all (AC2).

- [x] **Task 5: Tests** (AC: 1, 3, 4, 5)
  - [x] 5.1 New `apps/mobile/test/ai/wake_lock_ai_client_test.dart` (a fresh, narrowly-scoped file — `test/ai/ai_client_test.dart` already exists testing `ProtocolRoutingAiClient` only; keep the two decorators' tests in separate files, matching one-class-per-test-file elsewhere in `test/ai/`).
  - [x] 5.2 Small in-file `class FakeScreenWakeLock implements ScreenWakeLock` recording `enableCalls`/`disableCalls` counts (or a simple ordered event log) — mirrors `FakeAiClient`'s own recording-double pattern (`test/fakes.dart:74-79`).
    *(Used a single ordered `calls` log rather than two separate counters — lets the "enable before disable, in order" assertion be a single list-equality check.)*
  - [x] 5.3 Test: on a successful `FakeAiClient` response, `enable()` is called before any chunk is yielded and `disable()` is called exactly once after the stream completes.
  - [x] 5.4 Test: on a `FakeAiClient` configured with an `error`, `disable()` is still called exactly once (the `finally` guarantee) even though the stream errors — and the original `AiClientException` still propagates to the listener unchanged (proves `WakelockPlusScreenWakeLock`'s own "never throws" contract, Task 2.3, doesn't accidentally swallow the real failure).
  - [x] 5.5 Test: cancelling the stream subscription partway through an in-progress response (use a controllable/streaming fake, mirroring `settings_page_test.dart`'s existing `_ControllableAiClient` pattern) still calls `disable()` — proves AC4, and is the exact scenario `SettingsPage.dispose()`'s `_testSubscription?.cancel()` exercises in production.
  - [x] 5.6 Test: the yielded text chunks pass through completely unchanged in order and content — this is a transparent decorator, not just a lifecycle wrapper; assert the collected output equals the inner fake's configured response exactly.
  - [x] 5.7 Full regression: run the entire existing `flutter test` suite — since no other file's production code changes (only `ai_client.dart` gains a new class and `main.dart` gains a two-line wrap), no other test file should need any update; confirm rather than assume.
  - [x] 5.8 `flutter analyze` clean.

## Dev Notes

- **This story's entire production-code footprint is: one new file (`ai/screen_wake_lock.dart`), one new class added to an existing file (`WakeLockAiClient` in `ai_client.dart`), and a two-line change in `main.dart`.** No widget, no screen, no test outside `test/ai/` needs to change. If the implementation ends up touching `settings_page.dart`, `translate_action.dart`, `grammar_action.dart`, or any of the other 11 files in the `AiClient`-threading chain, something has gone wrong — stop and reconsider against AC2.
- **Why a decorator, not per-call-site wrapping:** the three call sites (`runTranslate`, `runGrammarReview`, `_testConnection`) each already independently build an `AiRequest` and consume `aiClient.sendMessage(request)` — wrapping each site individually would mean writing (and remembering to write, for every future AI action) the same enable/try/finally/disable boilerplate three-plus times. A decorator around the single shared `AiClient` instance gets this once, correctly, for every current and future caller.
- **The `async*` + `try`/`finally` cancellation guarantee is the crux of this story's correctness** (AC4) — verify this is actually true for the resolved Dart/Flutter SDK version during implementation (it is documented, standard behavior, but Task 5.5's test is what actually proves it for this codebase, not the doc comment alone).
- **`ScreenWakeLock`'s two methods must never throw** — see Task 2.3's reasoning. This is the one place in this story where getting AD-8 "never throw" wrong would silently break a *different* guarantee (the original stream error would be masked by a new one from `finally`), not just violate a style rule.
- **Testing standard:** this project's `test/ai/` directory already has one file per production class-under-test where a class is standalone-testable (`ai_client_test.dart` for `ProtocolRoutingAiClient`, `ai_transport_test.dart` for `RetryingHttpSender`/`sseDataFrames`, `openai_compatible_client_test.dart`, `messages_api_client_test.dart`). Follow that convention with a new `wake_lock_ai_client_test.dart` rather than folding these tests into an existing file.

### Project Structure Notes

- New files: `apps/mobile/lib/ai/screen_wake_lock.dart`, `apps/mobile/test/ai/wake_lock_ai_client_test.dart`.
- Modified files: `apps/mobile/lib/ai/ai_client.dart` (new `WakeLockAiClient` class), `apps/mobile/lib/main.dart` (compose the decorator), `apps/mobile/pubspec.yaml` (new `wakelock_plus` dependency, added via `flutter pub add`, not hand-edited).
- Possibly modified: `apps/mobile/android/app/src/main/AndroidManifest.xml` — only if Task 1.2's verification finds a permission is actually needed (docs say no, but confirm rather than assume).
- No other file changes expected. This is the smallest-blast-radius story in Epic 5 so far — treat any larger diff as a signal to revisit the design against AC2 before proceeding.

### References

- [Source: apps/mobile/lib/ai/ai_client.dart#L147-177] — `ProtocolRoutingAiClient`, the exact decorator shape and placement this story mirrors.
- [Source: apps/mobile/lib/ai/translate_action.dart#L227-229] — one of the three existing `sendMessage` consumption sites (unchanged by this story, protected transparently).
- [Source: apps/mobile/lib/ai/grammar_action.dart#L192-194] — the second consumption site.
- [Source: apps/mobile/lib/app/settings_page.dart#L168-242] — `_testConnection`, the third consumption site, including the `_testSubscription` cancellation path AC4 targets.
- [Source: apps/mobile/lib/main.dart#L19-38] — the composition root this story's only real wiring change lands in.
- [Source: apps/mobile/test/fakes.dart#L64-79] — `FakeAiClient`, the pattern `FakeScreenWakeLock` (Task 5.2) mirrors.
- [Source: https://pub.dev/packages/wakelock_plus] — package docs: no special permission required on any platform, `WakelockPlus.enable()`/`.disable()` API.
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-8, AD-9, AD-12] — the architecture decisions this story must comply with.
- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.4] — the epic-level acceptance criteria this story file expands on.

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

- `flutter pub add wakelock_plus` — resolved to 1.7.0 as predicted.
- Verified no `AndroidManifest.xml` change needed by directly inspecting the resolved package's own `android/src/main/AndroidManifest.xml` in the pub cache (declares only the package name, no `<uses-permission>`).
- `flutter test test/ai/wake_lock_ai_client_test.dart` — red (`Method not found: 'WakeLockAiClient'`) before Task 3's implementation, green after 3/4 immediately; the 4th (error-path `disable()` timing) needed one `await Future<void>.delayed(Duration.zero)` added after `expectLater` to let the outer generator's `finally` fully unwind before asserting — a genuine microtask-ordering subtlety between stream-error delivery and `finally`'s own `await`, not a production bug. 4/4 green after.
- `flutter test` (full suite) — 788 passed, 0 failures; confirmed no test file outside `test/ai/wake_lock_ai_client_test.dart` needed any change (Task 5.7's prediction held).
- `flutter analyze` — "No issues found!"

**Review-fix round** (high effort, recall-biased, 2 finder agents given the small diff): 5 findings confirmed/plausible, 1 refuted. The refuted candidate — that the single shared `WakeLockAiClient` instance has no reference counting, so a concurrent second AI request could have its `disable()` turn off the wake lock while another is still in flight — was well-reasoned but the scenario is already unreachable: `PopScope` guards on the editor pages (`!_translating && !_reviewing`) block navigating away while a request streams, and Settings (the only other `sendMessage` caller) is only reachable by first popping back to Home, which sits below the editor in the navigation stack.
- `flutter test` (full suite) — 788 passed, 0 failures (net unchanged — 4 duplicate classes removed, replaced by 1 shared one). `flutter analyze` — "No issues found!"

### Completion Notes List

- This story's production-code footprint matched the Dev Notes' own prediction exactly: one new file (`ai/screen_wake_lock.dart`), one new class in `ai_client.dart`, a small wrap in `main.dart`, plus the `pubspec.yaml`/`pubspec.lock` dependency addition. No screen/widget file touched.
- `WakeLockAiClient.sendMessage`'s `finally`-based `disable()` guarantee was verified empirically, not just trusted from the doc comment: `test/ai/wake_lock_ai_client_test.dart`'s cancellation test genuinely cancels an in-flight `StreamSubscription` mid-response and confirms `disable()` still ran — this is the exact mechanism `SettingsPage.dispose()`'s `_testSubscription?.cancel()` relies on in production (AC4).
- One documented architectural tension (Task 3.1's own note): `ai_client.dart`'s top-of-file doc comment states "no Flutter imports live here" (AD-9 purity), but the new `import 'screen_wake_lock.dart';` transitively reaches `package:wakelock_plus` through that sibling file's own `WakelockPlusScreenWakeLock` adapter. `ai_client.dart`'s own import list stays literally Flutter-free; this is exactly what Task 3.1 explicitly instructed (with its own stated reasoning), so implemented as directed rather than deviating into an unrequested restructuring (e.g. splitting the interface from the adapter into separate files) — flagged for visibility, not treated as a defect to fix unilaterally.
- All 5 acceptance criteria verified: AC1 (the `wake_lock_ai_client_test.dart` success-path test proves `enable()` before any chunk, `disable()` exactly once after completion), AC2 (confirmed via `git status` — zero changes outside `ai_client.dart`/`main.dart`/`screen_wake_lock.dart`/the two `test/ai/` files/`pubspec.*`; all 13 `AiClient`-threading files and their existing `FakeAiClient`-based tests are byte-for-byte untouched), AC3 (`WakelockPlusScreenWakeLock`'s both methods wrap the real plugin call in `try`/`catch`, never rethrowing), AC4 (the cancellation test), AC5 (the "chunks pass through unchanged" test, plus the full regression suite staying green with zero other test file changes needed).

**Review-fix round:**
- Moved the "must never throw" contract from `WakelockPlusScreenWakeLock`'s doc comment onto the `ScreenWakeLock` interface itself, so any future implementer sees the load-bearing requirement at the interface level.
- Updated `main.dart`'s composition-root doc comment, which still described the pre-Story-5.4 `ProtocolRoutingAiClient`-only composition and hadn't been reconciled with the new `WakeLockAiClient` wrap.
- Consolidated 4 independently-hand-duplicated `_ControllableAiClient` test doubles (in `editor_page_test.dart`, `paired_editor_page_test.dart`, `settings_page_test.dart`, and this story's own new `wake_lock_ai_client_test.dart`) into one shared `ControllableAiClient` in `test/fakes.dart` — the 4th copy had already drifted from the other 3 (an added `add()` method, an async `complete()`) despite its own doc comment claiming to mirror them.
- Replaced three stacked `await Future<void>.delayed(Duration.zero)` calls in the cancellation test with exact, event-driven synchronization: a `Future<void> get disabled` completer added to `FakeScreenWakeLock` (completes the instant `disable()` first runs) and a per-chunk `Completer` for "first chunk received" — eliminating the turn-counting flakiness risk entirely, not just reducing it. The single delay in the error-path test was replaced the same way.
- The previously-dead `inner.add('partial')` setup line in the cancellation test is now actually asserted on (`expect(received, ['partial'])`), proving the response was genuinely in progress before cancellation — the line's original intent, now verified instead of merely narrated.

### File List

- `apps/mobile/lib/ai/screen_wake_lock.dart` (new — `ScreenWakeLock` interface + `WakelockPlusScreenWakeLock` real adapter; review-fix round: contract doc comment moved to the interface)
- `apps/mobile/test/ai/wake_lock_ai_client_test.dart` (new — `WakeLockAiClient` tests + `FakeScreenWakeLock`; review-fix round: uses shared `ControllableAiClient`, event-driven synchronization replacing timing delays)
- `apps/mobile/lib/ai/ai_client.dart` (modified — new `WakeLockAiClient` decorator, beside `ProtocolRoutingAiClient`)
- `apps/mobile/lib/main.dart` (modified — composition root wraps the existing `ProtocolRoutingAiClient` with `WakeLockAiClient`; review-fix round: doc comment reconciled)
- `apps/mobile/pubspec.yaml` (modified — `wakelock_plus: ^1.7.0` dependency, added via `flutter pub add`)
- `apps/mobile/pubspec.lock` (modified — resolved dependency versions)
- `apps/mobile/test/fakes.dart` (modified — review-fix round: new shared `ControllableAiClient`)
- `apps/mobile/test/app/editor_page_test.dart` (modified — review-fix round: removed duplicate `_ControllableAiClient`, uses shared fake, pruned unused `dart:async` import)
- `apps/mobile/test/app/paired_editor_page_test.dart` (modified — review-fix round: same)
- `apps/mobile/test/app/settings_page_test.dart` (modified — review-fix round: same, `dart:async` import kept — still used by `_SlowReadThemeModeStore`)

## Change Log

- 2026-08-18 — Implemented Story 5.4: added `wakelock_plus`, a `ScreenWakeLock` port + real adapter, and a `WakeLockAiClient` decorator that holds the device screen awake for the exact span of any `AiClient.sendMessage` call — composed once at the composition root, so a slow local model's in-flight connection survives past the point Android would otherwise sever it via Doze/background restrictions once the screen locks. Zero changes to any of the 13 files that already thread `AiClient` through the app. Full suite green (788/788), `flutter analyze` clean.
- 2026-08-18 — Code review (high effort, recall-biased, 8 angles): 5 of 6 findings confirmed/plausible, 1 refuted (a hypothesized concurrent-request wake-lock race, actually unreachable given existing `PopScope` navigation guards). Fixed all 5: moved the never-throw contract to the `ScreenWakeLock` interface; reconciled a stale composition-root doc comment; consolidated 4 drifted duplicate test fakes into one shared `ControllableAiClient`; replaced three timing-guessed test delays with exact event-driven synchronization; made a previously-dead test setup line actually verified. Full suite green (788/788), `flutter analyze` clean.
- 2026-08-18 — Marked done.
