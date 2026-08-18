---
baseline_commit: f170580
---

# Story 5.3: Show the resolved connection target when testing the AI connection

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want Test Connection to tell me the exact server address (and protocol/model) it just tried,
so that I can verify the app actually picked up my latest edit to `lore-story.json` — the file syncs via Syncthing along with the rest of the repo, so it can take a moment to arrive, and today Test Connection's outcome message gives no way to tell whether the app is still testing a stale value.

## Context

**Story 4.7 built Test Connection with a deliberate "no display" rule that this story narrowly amends.** `_testConnection()` in `apps/mobile/lib/app/settings_page.dart:168-242` already resolves everything needed for this story — `resolveOrigin(serverConfig)` and `resolveEffectiveProtocol(serverConfig)` are called at `settings_page.dart:183-184` to build the test `AiRequest` — but the outcome `SnackBar` never surfaces any of it:

- Success (`:214-216`): `SnackBar(content: Text('Connection successful.'))` — no endpoint, no protocol, no model.
- No text streamed back (`:200-210`): `'Connected, but the server returned no text — check the server address and protocol.'` — tells the author to go check, but doesn't show them what the app actually used.
- `AiClientException` (`:217-233`): either `'Server said: ${e.message}'` (remote-sourced) or the plain `e.message` (locally-diagnosed) — same gap.

Story 4.7's own AC5 said "Settings shows only the API key field — no server/protocol/model picker or display." That restriction was about not permanently cluttering the screen with a config summary; it was never about withholding this information at the one moment the author has explicitly asked the app to prove the connection works. **This story narrows AC5, it does not repeal it** — see AC2/Non-goals below.

**There is direct precedent for exactly this display elsewhere in the app**, which is what makes this low-risk: Story 4.7's own code review already added a `Server` section to the FR22 context preview (`translate_action.dart:201-204`, mirrored in `grammar_action.dart`):

```dart
final destination = ContextSection(
  label: 'Server',
  text: resolvedOrigin?.toString() ?? kDefaultAnthropicEndpoint,
);
```

The reasoning that shipped with it — *"AD-11 promises the preview shows exactly what leaves the device... the destination itself must be part of what's shown"* — applies identically here. `kDefaultAnthropicEndpoint` is already exported from `ai_server_config.dart` via the `ai/ai.dart` barrel (`ai.dart:16`), which `settings_page.dart` already imports (`settings_page.dart:5`) — **no new import is needed.**

**One existing test enforces the old, now-narrowed rule and needs to stay valid, not accidentally broken by a misreading.** `test/app/settings_page_test.dart:376-389` (`'a genuinely malformed lore-story.json shows a warning banner — never a display of the resolved config (AC5)'`) asserts `find.textContaining('anthropic')`/`'custom'` both `findsNothing` — but it **never taps Test Connection**; it only checks the malformed-config warning banner's own fixed text. That test is unaffected by this story and must still pass unchanged — it is not testing the same thing this story is about, and the AC2 amendment does not touch the warning-banner path at all.

**Several existing tests assert the SnackBar's *exact* current text and will need their assertions updated** (not the underlying behavior — just the string), since this story appends new text to those specific messages:
- `test/app/settings_page_test.dart:240` — `expect(find.text('Connection successful.'), findsOneWidget);`
- `:260` — `expect(find.text('Server said: bad key'), findsOneWidget);`
- `:350` — `expect(find.text('Connection successful.'), findsOneWidget);` (the `storage: null` / Anthropic-default fallback case)

By contrast, `:295` (`find.text('Connection successful.'), findsNothing` — a *different* sentence, the "no text returned" case) and the AC5 warning-banner test above are checking absence of unrelated text and remain valid unchanged — verify this rather than assuming it (Task 4).

## Acceptance Criteria

1. **(Resolved destination shown on test outcome)** Given I tap Test Connection and the app successfully resolves `lore-story.json`'s `ai` object and sends a request, when the outcome arrives — success, "server returned no text," or a remote/local failure that happened after the request was built — then the message also states the exact endpoint used (falling back to `kDefaultAnthropicEndpoint` when no override applies, exactly like the FR22 context preview's own fallback), the protocol (`anthropic`/`openai`), and the model if one is set — all three come from the same `lore-story.json` fields a sync delay could leave stale.
2. **(Narrow amendment to Story 4.7's AC5, not a repeal)** Given Story 4.7's AC5 ("Settings shows only the API key field — no server/protocol/model picker or display"), when this story ships, then that rule is narrowed, not reversed: Settings still shows no persistent, always-visible config picker or summary anywhere on the screen — the resolved destination/protocol/model appears only as part of Test Connection's own outcome feedback, exactly when and because the author explicitly triggered a live test.
3. **(Config-resolution failures are unaffected)** Given `resolveOrigin`/`resolveEffectiveProtocol` themselves throw an `AiConfigException` before any request is built (e.g. `server: "custom"` with no `baseUrl`), when Test Connection reports this, then the existing typed-exception message is shown exactly as it is today — no additional "tried ..." text is added, since nothing was actually resolved to attempt.
4. **(No behavior change beyond the message text)** Given the connection-testing logic Story 4.7/4.8 already built — the request itself, retry/timeout handling, the re-entrancy guards (`_testing`/`_saving`), the cancellable `_testSubscription` — when this story ships, then none of it changes; this is a UI-only enrichment of the outcome message's text, not a rework of the test flow.

**Non-goals** (explicitly out of scope):
- No automatic staleness detection (checking `lore-story.json`'s modified time, a content hash, or a "sync in progress" indicator) — the author's own ask is only to see what value the app resolved, so they can visually cross-check it against what they intended to write; detecting sync lag automatically is a different, unrequested feature.
- No persistent "current configuration" summary shown at all times on the Settings screen — still gated behind explicitly tapping Test Connection (AC2).
- No change to the request itself, retry/timeout/cancellation behavior, or the generic `catch (_)` fallback message (`settings_page.dart:234-241`, an unclassified failure) — only the specific outcome messages named in AC1 gain the new suffix. Whether the resolved values are even trustworthy at that point is unclear for a truly unclassified failure, so leave it unchanged.
- No new UI chrome (no new widget, no dialog) — the information is appended to the existing `SnackBar` text.

## Tasks / Subtasks

- [x] **Task 1: Capture the resolved destination/protocol/model in `_testConnection()`** (AC: 1, 3)
  - [x] 1.1 In `settings_page.dart:168-242`, alongside the existing `resolveOrigin(serverConfig)`/`resolveEffectiveProtocol(serverConfig)` calls used to build the `AiRequest` (`:183-184`), capture their results into local variables reused for both the request and the new diagnostic text — do not call these pure functions differently or duplicate logic; either reuse the same call sites' results directly, or call them once more (they are cheap and pure, so either is acceptable — dev's call, but prefer reusing the already-computed values for tidiness).
  - [x] 1.2 Build the endpoint string exactly like the FR22 context preview's own precedent: `final endpoint = resolvedOrigin?.toString() ?? kDefaultAnthropicEndpoint;` (mirrors `translate_action.dart:201-204` verbatim in spirit). `kDefaultAnthropicEndpoint` is already available via the existing `ai/ai.dart` barrel import — no new import needed.
  - [x] 1.3 This capture happens only on the success path of `resolveOrigin`/`resolveEffectiveProtocol` — i.e. only reachable code, since an `AiConfigException` thrown by either function is already caught by the existing `on AiClientException catch (e)` block (`:217`) before any endpoint/protocol/model would have been resolved (AC3 — nothing to capture in that case).
    *(Impl note: `targetSuffix` (`String?`) is declared just before the `try` block, not inside it — a `try`/`on X catch`/`catch` sequence does not share variable scope across its blocks in Dart, so a local declared inside `try` would not be visible from the `on AiClientException catch` handler that also needs it. It stays `null` when an `AiConfigException` is thrown during resolution, giving AC3 for free.)*

- [x] **Task 2: Append the resolved destination to the relevant outcome messages** (AC: 1, 3, 4)
  - [x] 2.1 Add a small private formatter, e.g. `String _connectionTargetSuffix(String endpoint, AiProtocol protocol, String? model) => ' (tried $endpoint, ${protocol.name}${model != null ? ', $model' : ''})';` — omits the model segment gracefully when `null` (the Anthropic-default case with no `model` override). Exact wording/punctuation is dev's call; the three pieces of information (endpoint, protocol, model-if-set) are the requirement, not the literal string.
  - [x] 2.2 Append the suffix to the success message (`:215`, today `'Connection successful.'`).
  - [x] 2.3 Append the suffix to the "no text returned" message (`:203-208`).
  - [x] 2.4 Append the suffix to **both** branches of the `AiClientException` handler (`:217-233`) — the `fromRemoteBody` `'Server said: ${e.message}'` case and the plain `e.message` case. This is the failure class most likely to actually be the sync-lag scenario the author described (e.g. auth failure because the URL/model changed but the app is still testing the old one) — do not skip it.
    *(Discovered during Task 3: this branch also covers `AiNotConfiguredException` ("No API key configured.") — that exception is thrown during the actual request, after config resolution already succeeded, so it correctly gains the suffix too. The story's own Task 3 line-number list didn't enumerate this test; updated it the same way per Task 6.1's general "if any [test] asserts on the exact SnackBar text, update it" mandate.)*
  - [x] 2.5 Do **not** append the suffix to the generic `catch (_)` fallback (`:234-241`) — see Non-goals.
  - [x] 2.6 Do **not** add any suffix logic to the `AiConfigException`-before-resolution path — it's already excluded by construction per Task 1.3; just confirm no accidental capture-and-append happens there.

- [x] **Task 3: Update the three existing exact-text SnackBar assertions this story's message change invalidates** (AC: 1)
  - [x] 3.1 `test/app/settings_page_test.dart:240` (`'tapping it with a successful response shows a success SnackBar (AC4)'`) — change `expect(find.text('Connection successful.'), findsOneWidget);` to `expect(find.textContaining('Connection successful.'), findsOneWidget);` (this file already uses `textContaining` for several other assertions — e.g. `:198`, `:297` — prefer it here too for resilience against the exact suffix wording).
  - [x] 3.2 `:260` (the "provider-sourced message is prefixed" test) — change `expect(find.text('Server said: bad key'), findsOneWidget);` to `expect(find.textContaining('Server said: bad key'), findsOneWidget);`. Keep `:261-262`'s existing `find.text('bad key'), findsNothing` assertion unchanged — that's specifically checking the raw, unprefixed message never also appears, which this story does not affect.
  - [x] 3.3 `:350` (the `storage: null` fallback test) — same `textContaining` change. This test is also the right place to additionally assert the fallback endpoint appears: add `expect(find.textContaining(kDefaultAnthropicEndpoint), findsOneWidget);` right after, proving AC1's fallback-to-default case is actually exercised (the test already sets up exactly this scenario — `storage: null`).
    *(Also updated a fourth test not enumerated here — the "locally-diagnosed failure (no key configured)" test — see Task 2.4's note.)*

- [x] **Task 4: Verify the two tests that should NOT need changes actually still pass** (AC: 1, 2)
  - [x] 4.1 Run `:280-298` (the "no text returned" test) unmodified and confirm `find.text('Connection successful.'), findsNothing` still passes — it's checking absence of a *different* sentence than the one this story modifies, so it should be unaffected; confirm rather than assume.
    *(Confirmed — passed unmodified.)*
  - [x] 4.2 Run `:376-389` (the malformed-`lore-story.json` warning-banner test, which asserts `find.textContaining('anthropic')`/`'custom'` both `findsNothing`) unmodified and confirm it still passes — it never taps Test Connection, so no SnackBar exists in that test to leak protocol/server text into; confirm rather than assume.
    *(Confirmed — passed unmodified, along with the other 4 tests in that group.)*

- [x] **Task 5: New tests for the enriched message content** (AC: 1, 3)
  - [x] 5.1 A test asserting a successful Test Connection's SnackBar contains the resolved custom `baseUrl` when `lore-story.json` sets one — reuse the existing `FakeRepoStorage`/`kProjectConfigFile` setup pattern already at `:355-372`, but additionally assert the SnackBar text (that existing test only checks `aiClient.requests.single.model`/`.baseUrl`, not the displayed message — extend it or add a sibling test).
    *(Extended the existing test; also asserts the resolved protocol — discovered `server: "custom"` with no explicit `protocol` set defaults to `anthropic`, not `openai`, per `resolveEffectiveProtocol`'s own documented default — corrected an initial wrong assumption in the test before it passed.)*
  - [x] 5.2 A test asserting the model name appears in the message when `serverConfig.model` is set, and is gracefully omitted (no dangling comma/blank segment) when it's `null` (the Anthropic-default case).
  - [x] 5.3 Extend the existing `:300-317` test ("an unusable server config... is reported via the same typed-exception path") to additionally assert the shown message does **not** contain any "tried ..." suffix text (AC3) — the config-resolution failure path must stay exactly as it was, with no new diagnostic text appended.

- [x] **Task 6: Regression + lint** (AC: 1, 2, 3, 4)
  - [x] 6.1 Full `flutter test` run — confirm no other test file (outside `settings_page_test.dart`) asserts on Test Connection's SnackBar text; if any is found, update it the same way as Task 3.
  - [x] 6.2 `flutter analyze` clean.

## Dev Notes

- **This story touches exactly one file's production code** (`apps/mobile/lib/app/settings_page.dart`, specifically `_testConnection()`) plus its test file. No new files, no new dependencies, no new imports (`kDefaultAnthropicEndpoint`/`resolveOrigin`/`resolveEffectiveProtocol`/`AiProtocol` are all already imported via the existing `ai/ai.dart` barrel import at `settings_page.dart:5`).
- **Reuse, don't reinvent:** the exact `resolvedOrigin?.toString() ?? kDefaultAnthropicEndpoint` expression already exists in `translate_action.dart:203` and `grammar_action.dart` — copy that pattern's *reasoning*, not necessarily its `ContextSection` machinery (that's for the FR22 preview sheet, a different UI surface; this story only needs a plain string appended to `SnackBar` text).
- **AD-8 discipline still applies:** none of this story's changes should introduce a new way for `_testConnection` to throw unexpectedly. The formatter (Task 2.1) operates only on already-resolved, non-null-where-required values (an `AiProtocol` enum is never null by the time Task 1's capture runs; `endpoint` always has a value via the `??` fallback; only `model` is legitimately nullable and is handled by the formatter's own null check).
- **Testing standard:** this project's existing `settings_page_test.dart` mixes `find.text(...)` (exact match) and `find.textContaining(...)` (substring match) depending on what's being asserted. Task 3 prefers `textContaining` specifically because this story does not mandate exact wording — only that the three pieces of information (endpoint, protocol, model) are present somewhere in the message.
- **Independent of Story 5.2** (theme switching) — both stories touch files under `apps/mobile/lib/app/`, but Story 5.2 (if it lands first) touches `SettingsPage`'s `AppBar`/toggle placement, not `_testConnection`'s message text; this story touches `_testConnection`'s message text, not the `AppBar`. No functional overlap; no ordering dependency either direction.

### Project Structure Notes

- Modified files only: `apps/mobile/lib/app/settings_page.dart`, `apps/mobile/test/app/settings_page_test.dart`. No new files.
- No conflicts with the unified project structure — this is a scoped, single-slice (`app/`) change.

### References

- [Source: apps/mobile/lib/app/settings_page.dart#L168-242] — `_testConnection()`, the method this story modifies.
- [Source: apps/mobile/lib/ai/translate_action.dart#L196-204] — the precedent `ContextSection(label: 'Server', ...)` pattern and its own review-fix reasoning.
- [Source: apps/mobile/lib/ai/ai.dart#L14-20] — confirms `ai_server_config.dart` (and therefore `kDefaultAnthropicEndpoint`) is already exported via the barrel `settings_page.dart` imports.
- [Source: apps/mobile/test/app/settings_page_test.dart#L230-389] — every existing test this story's Dev Notes and Tasks reference by line number.
- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.3] — the epic-level acceptance criteria this story file expands on.
- [Source: _bmad-output/planning-artifacts/epics.md#Story 4.7 AC5] — the rule this story narrowly amends; read it before implementing to understand exactly what "narrowed, not repealed" must mean in practice.

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

- `flutter test test/app/settings_page_test.dart` — red (3 tests: the extended custom-`baseUrl` test, the new model-omitted test, and the `storage: null` fallback test's new `kDefaultAnthropicEndpoint` assertion) before Task 1/2's implementation, green after (35/35) once a wrong test assumption (expected `openai` protocol for a bare `server: "custom"` config with no explicit `protocol`, which actually defaults to `anthropic` per `resolveEffectiveProtocol`'s own documented rule) was corrected.
- `flutter analyze` — two dead-code/dead-null-aware-expression warning pairs on an initial defensive `${targetSuffix ?? ''}` in the success/no-text branches (Dart's flow analysis proves `targetSuffix` is non-null by that point, since it's unconditionally assigned earlier with no intervening path back to null) — simplified to plain `$targetSuffix`; final run: "No issues found!"
- `flutter test` (full suite) — 781 passed, 0 failures.
- Confirmed via grep: no test file outside `settings_page_test.dart` asserts on Test Connection's SnackBar text (Task 6.1).

**Review-fix round** (high effort, recall-biased, 2 finder agents across 8 angles given the small diff): 5 findings confirmed/plausible, 1 refuted (a theoretical post-resolution `AiConfigException` path, proven unreachable — `resolveOrigin` itself guarantees the effective protocol can never be `openai` when it returns a null origin, so nothing inside `OpenAiCompatibleClient` can throw `AiConfigException` through this call site).
- New `test/ai/ai_server_config_test.dart` group (`describeEndpoint`, 4 tests) — pure-function coverage for the new endpoint-path logic, including trailing-slash handling.
- `flutter test` (full suite) — 784 passed, 0 failures. `flutter analyze` — "No issues found!"

### Completion Notes List

- `_testConnection()` now captures `endpoint`/`protocol`/`serverConfig.model` right after `resolveOrigin`/`resolveEffectiveProtocol` succeed, building `targetSuffix` (a nullable local declared *before* the `try` block, not inside it — Dart's `try`/`catch` blocks don't share scope, and the `on AiClientException catch` handler also needs to read it) once. It stays `null` if an `AiConfigException` is thrown during resolution, so AC3 (no diagnostic text on a config-resolution failure) falls out of the control flow for free rather than needing a separate check.
- The suffix is appended to 3 of the 4 outcome paths per the story's Task 2: success, "no text returned," and both branches of the `AiClientException` handler. The generic `catch (_)` fallback is deliberately left untouched (Non-goals).
- Discovered while implementing Task 2.4/3: the existing "(Review fix) a locally-diagnosed failure (no key configured) is shown without the remote-origin prefix" test (`AiNotConfiguredException`) also takes the `AiClientException` branch, and that exception is thrown during the actual request — after config resolution already succeeded — so it correctly gains the suffix too, breaking its exact-text assertion. This test wasn't in the story's own enumerated Task 3 list (written against a stale line-number baseline); updated it the same way per Task 6.1's general mandate to fix any test asserting on the exact SnackBar text.
- All 4 acceptance criteria verified: AC1 (endpoint/protocol/model all present in the success message and in the custom-`baseUrl` extended test; fallback-to-default proven via the `storage: null` test asserting `kDefaultAnthropicEndpoint`), AC2 (no new persistent UI — the suffix is only ever part of a `SnackBar`, gated behind an explicit tap, confirmed unchanged by the untouched malformed-config-warning test group), AC3 (the "unusable server config" test explicitly asserts no "Tried: ..." text appears), AC4 (full regression suite green — no change to the request, retry/cancellation, or re-entrancy logic).

**Review-fix round:**
- Added `describeEndpoint({required Uri? origin, required AiProtocol protocol})` to `ai_server_config.dart` — a pure, total function that appends the same protocol-specific request path (`/messages`/`/chat/completions`) each `AiClient` adapter's own endpoint resolution uses, so the diagnostic endpoint shown now matches what was actually requested for a custom server too (previously only the Anthropic-default case, which already baked the path into `kDefaultAnthropicEndpoint`, was precise). `_testConnection()` calls this instead of the bare `resolvedOrigin?.toString() ?? kDefaultAnthropicEndpoint` fallback.
- Restructured `_testConnection()` to resolve config in its own leading `try`/`on AiConfigException catch` block — mirroring `translate_action.dart`/`grammar_action.dart`'s own established pattern — before the network-call `try`/`catch`. `resolvedOrigin`/`protocol`/`targetSuffix` are non-nullable from that point on; the nullable-flag-threaded-through-one-shared-try/catch design (and its explanatory comment) is gone.
- `_connectionTargetSuffix` now starts with a newline + `Tried:` label instead of a bare leading space, so the trusted diagnostic text has a clear, hard-to-spoof visual boundary from `e.message`, which can originate from a remote server's response body.
- Consolidated a near-duplicate test (the "model segment omitted" test merged into the existing `storage: null` test, which already set up the identical scenario).

### File List

- `apps/mobile/lib/app/settings_page.dart` (modified — `_testConnection()` restructured into a two-phase resolve-then-request flow; `_connectionTargetSuffix` now uses a newline+label delimiter)
- `apps/mobile/lib/ai/ai_server_config.dart` (modified — review-fix round: new `describeEndpoint` function)
- `apps/mobile/test/app/settings_page_test.dart` (modified — 4 existing tests' assertions loosened to `textContaining`/extended, 1 new test added, 1 near-duplicate test consolidated in the review-fix round)
- `apps/mobile/test/ai/ai_server_config_test.dart` (modified — review-fix round: new `describeEndpoint` test group, 4 tests)

## Change Log

- 2026-08-18 — Implemented Story 5.3: Test Connection's outcome message now states the resolved endpoint/protocol/model it actually used, narrowing (not repealing) Story 4.7's AC5 "no display" rule to the moment the author explicitly triggers a live test — so a Syncthing sync lag on `lore-story.json` is immediately visible instead of silently testing a stale value. Full suite green (781/781), `flutter analyze` clean.
- 2026-08-18 — Code review (high effort, recall-biased, 8 angles): 5 of 6 findings confirmed/plausible, 1 refuted. Fixed all 5: added `describeEndpoint` so the shown endpoint matches the actual request path for custom servers too (previously only the Anthropic default was precise); restructured `_testConnection()` to resolve config in its own leading try/catch, mirroring existing sibling precedent, so "did resolution succeed" is a structural fact instead of a nullable flag; gave the trusted diagnostic suffix a clear newline+label delimiter from potentially server-controlled error text; consolidated a near-duplicate test. Full suite green (784/784), `flutter analyze` clean.
- 2026-08-18 — Marked done.
