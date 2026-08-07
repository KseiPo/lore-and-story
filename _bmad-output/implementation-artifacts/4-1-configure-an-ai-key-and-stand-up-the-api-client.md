---
baseline_commit: 8f2806ea0ecffd016affbbafa8b458556d8eb7f6
---

# Story 4.1: Configure an AI key and stand up the API client

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to store my AI provider key securely and have the app ready to call the API,
so that AI features work without exposing the key.

## Context

**FR20 / NFR5 / NFR4, and the two epics.md ACs for this story:**
> Given settings, When I enter an API key, Then it is stored in secure device storage (Keystore) and never logged or shown in plain text after entry. (FR20, NFR5)
>
> Given there is no official Anthropic Dart SDK, When the client is built, Then it calls the Messages API over raw HTTPS with SSE stream parsing and retry/error handling — a reusable client for translation (4.3) and grammar (4.4).

This is the **first story of Epic 4** and a genuinely new domain for this codebase: it is the first story to introduce *any* outbound network call, the first to touch a secrets-storage API, and the first to populate the `ai/` slice (currently a 7-line placeholder barrel, `apps/mobile/lib/ai/ai.dart`). Confirmed via full-tree grep: zero existing HTTP/network client code anywhere in `apps/mobile/lib/` (the only "http" hits are `markdown_preview.dart`'s explicit *refusal* to fetch `http://` image URLs, and an unrelated regex in `convention_matcher.dart`).

**Scope is narrower than "AI translation/grammar working end-to-end."** Re-reading Stories 4.2–4.4 confirms the epic is phased deliberately:
- **4.2** ("Preview exactly what will be sent") builds the mandatory context-preview sheet (FR22) — **not this story's job**.
- **4.3** ("Translate RU→EN," the release checkpoint) assembles the context pack (RU file + alias glossary + prose conventions) and, on confirm, "streams a translation **via the Story 4.1 client**" — future tense, doesn't exist yet.
- **4.4** ("Grammar/style findings") likewise consumes the Story 4.1 client later.

So **this story stands up the plumbing only**: a secure key store with a settings UI, and a reusable, tested `AiClient` adapter that can talk to Anthropic's Messages API — proven by tests against a fake HTTP layer, not by any real feature invoking it yet (no context-pack assembly, no translate/grammar UI, no context-preview sheet). This is a coherent, common shape for the first story of a multi-story technical epic, and matches the epic's own Definition of Done language ("shared HTTP client, key store... Story 4.1").

**Two design decisions made up front, with reasoning, since neither PRD/architecture/`MOBILE.md` commit to specifics:**

1. **There is no existing Settings screen or navigation entry point anywhere in the app.** `HomePage`'s `AppBar` (`apps/mobile/lib/app/home_page.dart:315`) is `AppBar(title: const Text('Lore & Story'))` with no `actions:`. This story adds a settings icon there that pushes a new `SettingsPage` — the minimal, standard Flutter pattern, consistent with how every other screen in this app is reached (a plain `Navigator.of(context).push` from an `AppBar` affordance). Building a fuller settings surface (multiple pages, provider switcher, etc.) is out of scope — Epic 4 targets one provider (Anthropic) only; nothing in any planning doc suggests a provider-selection UI.
2. **HTTP transport library: `package:http`, not raw `dart:io HttpClient`.** The addendum's "no official Anthropic Dart SDK → hand-roll SSE parsing and retry/error handling" is about not having an *AI-specific* SDK — it does not forbid a general-purpose HTTP package. `package:http`'s `Client.send()` returns a `StreamedResponse` whose byte stream can be read incrementally, which is exactly what SSE parsing needs, and it keeps the client easily testable (inject a `http.Client`, substitute a fake in tests) without reinventing TLS/socket handling for zero benefit. The SSE *parsing* itself (turning `data: {...}\n\n` chunks into typed events) is still fully hand-rolled application code, honoring the addendum's actual concern.

## Acceptance Criteria

1. **(FR20 / NFR5 — key entry & storage)** Given the new Settings screen, when I type an API key and tap Save, then it is persisted via `flutter_secure_storage` (Android Keystore-backed) — never via `shared_preferences`, and never passed to `print`/`debugPrint`/any logging call.
2. **(NFR5 — never shown in plaintext after entry)** Given a key has already been saved, when I reopen Settings, then the text field is never pre-filled with the saved value — at most a masked "API key configured" indicator is shown, never the key itself.
3. **(Clear/replace)** Given a saved key, when I tap Clear, then it is deleted from secure storage and Settings reflects "not configured"; given a key is already configured, entering and saving a new one replaces it (no merge/append).
4. **(AD-8 — total, never crash)** A secure-storage read/write/delete failure (e.g. Keystore unavailable) never crashes the Settings screen or the app — it degrades to a visible "couldn't access secure storage" state, matching this project's total/never-throw discipline at UI call sites.
5. **(Client construction — epics.md AC2)** Given the `ai/` slice, `MessagesApiClient` implements an `AiClient` port and issues requests to Anthropic's Messages API (`model: claude-opus-4-8`, `thinking: {type: "adaptive"}` per the addendum) as a raw HTTPS JSON POST — no Anthropic SDK dependency of any kind.
6. **(SSE streaming)** Given a streaming Messages API response, the client incrementally parses Server-Sent Events into a Dart `Stream` of text deltas as they arrive — never buffers the whole response before yielding anything (the addendum's stated reason: "a full scene translation is long output").
7. **(Retry/error handling)** A transient failure (network error, HTTP 429, HTTP 5xx) is retried with bounded backoff (not unbounded, not zero-delay hot-looping); a non-retryable failure (401 invalid key, 400 bad request) surfaces immediately as a typed error with no retry attempt.
8. **(Key never leaks via the client)** The API key is sent only in the Messages API's required auth header, never appears in any exception message, log line, or debug output the client produces.
9. **(Slice boundary — AD-9/AD-12)** `MessagesApiClient` is not exported from `apps/mobile/lib/ai/ai.dart`'s barrel — only the `AiClient` port, its value/error types, and the key-store type are; only `main.dart` (and this story's own `test/ai/` files, same as `test/storage/all_files_repo_storage_test.dart` already imports its adapter directly) may import `messages_api_client.dart` directly — mirrors exactly how `storage/storage.dart` withholds `AllFilesRepoStorage`.
10. **(Testable without a real network call or a real key)** The HTTP transport is injected (constructor parameter), so the client's request-building, SSE-parsing, and retry logic are covered by unit tests using a fake/mock HTTP layer. No test in this story makes a real network call, requires a real Anthropic API key, or costs money to run.
11. **(Offline-safe — NFR4)** Nothing added by this story calls the Messages API as a side effect of app startup, opening Settings, or saving/clearing a key — the client is only ever invoked explicitly (by a future feature, or a test's fake transport). The app's existing fully-offline behavior for every non-AI feature is unaffected.

**Non-goals:** the context-preview sheet (FR22 — Story 4.2); assembling a real translation/grammar context pack, or any UI that actually triggers a translate/grammar call (Stories 4.3/4.4); support for any AI provider other than Anthropic (no provider-selection UI — single adapter only); prompt caching — **review correction**: the addendum's stated reason (the ~2K-token glossary+conventions prefix is below Opus 4.8's minimum cacheable prefix) doesn't hold; Opus 4.8's minimum is actually 1024 tokens, and ~2K is comfortably above that, so the prefix *is* cacheable. The scoping is unaffected either way — caching is Story 4.3's concern (it assembles the actual prompt), not this plumbing story's — but 4.3 should treat caching as available, not skip it on this now-corrected premise; a rich multi-page Settings UI (one screen, one field, Save/Clear).

## Tasks / Subtasks

- [x] **Task 1: Add the secure-storage dependency and scaffold the `ai/` slice's port** (AC: 1, 9)
  - [x] 1.1 Ran `flutter pub add flutter_secure_storage` from `apps/mobile/` — pinned `11.0.0` (current stable).
  - [x] 1.2 New file `apps/mobile/lib/ai/ai_client.dart` — the slice's pure port (mirrors `storage/repo_storage.dart`'s shape and doc-comment style: no `dart:io`, no `package:http`, no Flutter imports — AD-9). Defines `AiClient`, `AiRequest`, and a sealed `AiClientException` hierarchy (`AiAuthException`, `AiInvalidRequestException`, `AiRateLimitException`, `AiServerException`, `AiNetworkException`).
  - [x] 1.3 New file `apps/mobile/lib/ai/key_store.dart` — `KeyStore` wrapping `flutter_secure_storage`, `read()`/`write()`/`clear()`/`isConfigured()`. **Deviation from the story's original plan, verified empirically**: `flutter_secure_storage` 11.0.0 ships a built-in `@visibleForTesting static FlutterSecureStorage.setMockInitialValues(...)`, mirroring `shared_preferences`'s own test support exactly — so the constructor-injection fallback this subtask specified turned out unnecessary; `KeyStore` constructs `const FlutterSecureStorage()` internally, matching `RepoRootStore`'s pattern of not injecting `SharedPreferences.getInstance()` either.
  - [x] 1.4 Updated `apps/mobile/lib/ai/ai.dart`'s barrel to export `ai_client.dart` and `key_store.dart` only.

- [x] **Task 2: `MessagesApiClient` adapter — request, raw HTTPS, SSE parsing, retry** (AC: 5, 6, 7, 8, 10, 11)
  - [x] 2.1 Added `http: ^1.6.0` to `pubspec.yaml`.
  - [x] 2.2 New file `apps/mobile/lib/ai/messages_api_client.dart` — `MessagesApiClient implements AiClient`, constructor takes an injected `http.Client` and `KeyStore`. Builds the request per the wire contract in Dev Notes (`model`, `thinking: {type: "adaptive"}`, `stream: true`, `x-api-key`/`anthropic-version` headers), sends it, reads the response as a `StreamedResponse`.
  - [x] 2.3 Hand-rolled SSE line parsing (`data: ...` lines → `content_block_delta.delta.text`) into the `Stream<String>` (AC6). Malformed/non-JSON lines are skipped (AD-8), never crash the stream.
  - [x] 2.4 HTTP status codes mapped to the AC7 exception hierarchy: 401→`AiAuthException`, 400→`AiInvalidRequestException` (both non-retryable), 429/5xx retried then exhaust to `AiRateLimitException`/`AiServerException`; connectivity failures retried then exhaust to `AiNetworkException`. An in-stream SSE `error` event maps the same way via `_mapErrorEvent`.
  - [x] 2.5 Bounded retry (`maxAttempts = 3` default) with exponential backoff (500ms·2^attempt), both overridable via constructor params — `backoff` is injectable specifically so Task 4.2's tests can run near-instantly.
  - [x] 2.6 Verified: the key is read fresh into a local `apiKey` variable used only to set the `x-api-key` header; no exception message, log call, or the request body itself ever includes it (request body only carries `model`/`max_tokens`/`thinking`/`stream`/`system`/`messages`).

- [x] **Task 3: Settings UI — entry point, enter/save/clear** (AC: 1, 2, 3, 4)
  - [x] 3.1 New file `apps/mobile/lib/app/settings_page.dart` — `SettingsPage` (StatefulWidget) taking `KeyStore` by injection. Loads via `isConfigured()` (never `read()`); renders "not configured" + field + Save, or "configured" + Clear (AC2/AC3). All 3 secure-storage operations are try/catch-wrapped — load failure shows an error state, save/clear failure shows a snackbar and stays on the current stage, never throws past the widget (AC4).
  - [x] 3.2 Added a `settings-action` `IconButton` to `HomePage`'s `AppBar.actions` (previously empty) that pushes `SettingsPage`.
  - [x] 3.3 Threaded `KeyStore` from `main.dart` → `LoreStoryApp` → `HomePage`, matching the `rootStore`/`permission`/`storageFactory` injection shape. Updated the 4 existing test files that construct `LoreStoryApp` directly (`widget_test.dart`, `browse_test.dart`, `create_entity_test.dart`, `promote_entity_test.dart`) to pass `keyStore: const KeyStore()` — mechanical, compile-error-driven, same as Story 3.2's `loreDir` threading precedent.

- [x] **Task 4: Tests** (AC: all)
  - [x] 4.1 `apps/mobile/test/ai/key_store_test.dart` — 8 tests: isConfigured/read before any value, write/read round-trip, isConfigured after write, a fresh instance sees a persisted write, replace-not-merge, clear, clear-on-empty is a no-op. **Verified empirically (not assumed)**: `flutter_secure_storage` 11.0.0 has a built-in `FlutterSecureStorage.setMockInitialValues({})`, mirroring `shared_preferences`'s own mock support — confirmed by reading the package source, not by copying the MethodChannel-mocking approach this subtask originally hypothesized.
  - [x] 4.2 `apps/mobile/test/ai/messages_api_client_test.dart` — 12 tests using `http.MockClient.streaming`: request body shape + headers + key never in the body, no-key-configured throws without sending, SSE deltas in order across a deliberately-misaligned multi-chunk split, streaming genuinely incremental (a delta is observed before the stream closes), a malformed SSE line is skipped without crashing, an in-stream `error` event maps to the right exception, 401/400 throw immediately with exactly 1 attempt, 429 retries to exhaustion (`AiRateLimitException`) and also retries-then-recovers, 5xx retries to exhaustion (`AiServerException`), a thrown transport exception retries to exhaustion (`AiNetworkException`). All retries use a near-zero injected backoff. No test performs a real HTTP call.
  - [x] 4.3 `apps/mobile/test/app/settings_page_test.dart` — 7 tests: entry field when unconfigured, save shows configured, a pre-saved key is never re-displayed (only the masked label), Clear returns to unconfigured, replace-not-merge via the UI, a load failure shows the error state, a save failure shows a snackbar and stays on the entry field — all without `tester.takeException()` reporting anything.

- [x] **Task 5: Regression and hygiene gates** (AC: all)
  - [x] 5.1 Full `flutter test` green — 473 tests passing (446 pre-existing + 27 new).
  - [x] 5.2 `flutter analyze` clean — 0 issues.
  - [x] 5.3 Confirmed no `lore_loader.dart`/`lore_model.dart`/`convention_matcher.dart`/fixture changes: `git status --porcelain` on those paths is empty.
  - [x] 5.4 Confirmed `apps/mobile/lib/storage/**` is unchanged: `git status --porcelain` empty.
  - [x] 5.5 Confirmed: `grep -rn "print(\|debugPrint(\|log(" apps/mobile/lib/ai apps/mobile/lib/app/settings_page.dart` returns no matches.

### Review Findings

Cross-model adversarial review (Blind Hunter + Edge Case Hunter + Acceptance Auditor, all on Opus; implementation was on Sonnet 5) against the uncommitted diff. Every finding below was verified by reading the actual source (and, for the Android manifest finding, the actual manifest files) — not taken on the subagents' word.

- [x] [Review][Patch] Android Auto Backup posture — **resolved by user decision: disable Android backup entirely** (`android:allowBackup="false"`) — added to the main manifest's `<application>` tag. [apps/mobile/android/app/src/main/AndroidManifest.xml]
- [x] [Review][Patch] Release builds have no `android.permission.INTERNET` — fixed: added to the main manifest, with a comment explaining the debug/profile overlays don't cover release builds. [apps/mobile/android/app/src/main/AndroidManifest.xml]
- [x] [Review][Patch] A mid-stream failure escapes `AiClientException`'s typed hierarchy entirely — fixed via `.handleError()` on the parsed stream (not a try/catch around `yield*`, which — verified empirically via isolated `dart run` probes — does not reliably intercept errors delegated through a chain of two nested async* generators; it silently hung instead of propagating). **Also verified empirically**: `.timeout()` must be applied to the raw byte stream feeding `_parseSse` (an async* generator), not to `_parseSse`'s own output, or a `.toList()` consumer can hang indefinitely instead of receiving the timeout error — a genuine, non-obvious Dart async-generator/Stream interaction, not a hypothetical. 5 new tests cover mid-stream connection failure, malformed UTF-8, and both timeout shapes. [apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] AC3 violated: Settings had no way to replace an already-configured key — fixed: added a "Replace" button (alongside Clear) that switches to the entry field *without* deleting the stored key first, so a cancelled or failed replace never leaves the app unconfigured. 2 new tests. [apps/mobile/lib/app/settings_page.dart]
- [x] [Review][Patch] `stop_reason` was never inspected — fixed: `message_delta` is now parsed; `max_tokens`/`refusal` throw `AiInvalidRequestException` instead of completing silently. 3 new tests (`max_tokens`, `refusal`, and a normal `end_turn` completing cleanly). [apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] Unmapped 4xx statuses fell through to `AiServerException` — fixed: 403/404/413 now route through `AiInvalidRequestException` alongside 400. 1 new test (all three statuses, non-retried). [apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] No timeout on the HTTP request or the SSE stream — fixed: added constructor-injectable `requestTimeout` (default 30s) and `streamIdleTimeout` (default 60s). 2 new tests. [apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] 429 retry never read `retry-after` — fixed: a present, valid `retry-after` header (seconds form, clamped to a 30s ceiling against a hostile/broken value) is used instead of the default backoff. 1 new test. [apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] Multi-line SSE `data:` fields weren't concatenated — fixed: consecutive `data:` lines within one event are now buffered and joined with `\n` before decoding, per the SSE spec. 1 new test. [apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] Two vacuous test assertions — fixed: `returnsNormally` → `await expectLater(..., completes)`; the trivially-true `isNot(contains(null))` assertion removed. [apps/mobile/test/ai/key_store_test.dart, apps/mobile/test/ai/messages_api_client_test.dart]
- [x] [Review][Patch] AC8's exception-message guarantee was untested — fixed: 2 new tests assert `AiClientException.message` never contains the key (a connection-failure path and a 401-response path); the network-failure message was also narrowed from interpolating a whole exception to just its `runtimeType`. [apps/mobile/lib/ai/messages_api_client.dart, apps/mobile/test/ai/messages_api_client_test.dart]
- [x] [Review][Patch] `_Stage.error` was a dead end — fixed: added a Retry action that re-attempts the load. 1 new test. [apps/mobile/lib/app/settings_page.dart]
- [x] [Review][Patch] Tapping Save with an empty field silently no-op'd — fixed: shows a snackbar ("Enter a key first"). 1 new test. [apps/mobile/lib/app/settings_page.dart]
- [x] [Review][Patch] No test verified the `HomePage` settings icon navigates to `SettingsPage` — fixed: 1 new test in `widget_test.dart` taps the real icon end-to-end. [apps/mobile/test/widget_test.dart]
- [x] [Review][Patch] Three hand-rolled `KeyStore` test doubles duplicated `test/fakes.dart`'s pattern; 4 pre-existing widget tests used a real, unmocked `KeyStore()` — fixed: added `FakeKeyStore` (with `failing`/`failWrites` flags, mirroring `FakeRepoStorage`'s shape) to `test/fakes.dart`; `settings_page_test.dart` and all 4 pre-existing widget tests now use it, dropping the `flutter_secure_storage` platform-channel dependency from tests entirely. [apps/mobile/test/fakes.dart, apps/mobile/test/app/settings_page_test.dart, apps/mobile/test/widget_test.dart, apps/mobile/test/app/browse_test.dart, apps/mobile/test/app/create_entity_test.dart, apps/mobile/test/app/promote_entity_test.dart]
- [x] [Review][Patch] `AiAuthException` conflated "no key configured" with "the provider rejected the key" — fixed: added a distinct `AiNotConfiguredException`. 1 renamed test. [apps/mobile/lib/ai/ai_client.dart, apps/mobile/lib/ai/messages_api_client.dart]
- [x] [Review][Patch] `KeyStore.write` didn't reject control characters — fixed: throws `ArgumentError` (via `async`, delivered as a `Future` rejection, not a synchronous throw a caller's `await`/`try` might not expect) for an empty key or one containing a control character; the message never embeds the rejected value itself (would have been a self-inflicted AC8 violation — caught before it shipped). 1 new test. [apps/mobile/lib/ai/key_store.dart, apps/mobile/test/ai/key_store_test.dart]
- [x] [Review][Patch] Story Dev Notes overstated Opus 4.8's minimum cacheable prefix as 4096 tokens (actually 1024) — corrected. [this file — Non-goals]
- [x] [Review][Defer] In-stream SSE `error` events bypass retry entirely (0 attempts) while the identical failure via HTTP status code gets retried up to `maxAttempts` — deferred: fixing this means replaying an already-partially-streamed request, a meaningfully bigger architectural change than this patch round; document as a known limitation for Story 4.3/4.4 to weigh. [apps/mobile/lib/ai/messages_api_client.dart:165-166]
- [x] [Review][Defer] `AiRequest.maxTokens` defaults to 8192 alongside always-on `thinking: {type: "adaptive"}`, which caps thinking *and* response text together — a real truncation risk for "a full scene translation," per the addendum's own framing — deferred: this is a tuning question that depends on real prompt sizes only Story 4.3 (the actual caller) can answer; 4.1's plumbing correctly leaves `maxTokens` caller-overridable. [apps/mobile/lib/ai/ai_client.dart:26]
- [x] [Review][Defer] `flutter_secure_storage` 11.0.0's transitive dependency surface (`jni`, `jni_flutter`, `win32`, `objective_c`, `flutter_secure_storage_web`, etc.) is large for storing one string — deferred: inherent to the current-stable version the architecture doc explicitly instructs pinning to ("verify current stable at scaffold"), not actionable without deliberately downgrading to a stale/less-maintained version. [apps/mobile/pubspec.yaml]

**Dismissed as noise / already covered / matches existing precedent:** `pubspec.yaml`'s `^11.0.0` caret range vs. the story's "pinned" wording (every other dependency in this file uses a caret range too — normal Flutter convention, not a deviation); `ai.dart`'s barrel exporting `KeyStore` while withholding `MessagesApiClient` (mirrors `storage/storage.dart`'s own precedent exactly — `RepoRootStore`, which also wraps a plugin, is exported there too); `KeyStore` being a concrete class with no port "breaking AD-9" (`RepoRootStore` is the identical shape — matches existing convention, not a new deviation); the default backoff's theoretical integer-overflow past attempt 62 (Dart's native `int` is 64-bit; unreachable at any `maxAttempts` value this story or a realistic caller would ever set); the Debug Log's wire-contract-verification process complaint (the Acceptance Auditor independently re-verified the contract against the current published reference and confirmed it correct — no residual functional risk remains); `KeyStore.write('')` reaching an inconsistent state (unreachable given `SettingsPage`'s existing empty-string guard, and `isConfigured`/`read` would stay consistent regardless).

## Dev Notes

### What changes, precisely

- **New `ai/` slice files:** `ai_client.dart` (port + value/error types), `key_store.dart` (secure-storage adapter), `messages_api_client.dart` (HTTP/SSE adapter, **not** exported from the barrel) — populating `ai.dart`'s current 7-line placeholder.
- **New `app/` file:** `settings_page.dart`.
- **Modified:** `app/home_page.dart` (+settings AppBar action), `app/app.dart` (+`KeyStore` injection into `LoreStoryApp`), `main.dart` (composition root constructs `KeyStore`, wires it down), `pubspec.yaml` (+`flutter_secure_storage`, +`http` if not already present).
- **Unchanged:** everything in `lore/`, `storage/`, the existing editor/preview/lint/autocomplete surfaces — this story is additive and touches no existing feature's behavior.

### Messages API wire contract (not fully specified in any planning doc — verify before finalizing)

None of epics.md/PRD/addendum/MOBILE.md/architecture state the literal endpoint, headers, or SSE event shape — only the model name and `thinking` param. AC10's fake-transport tests will pass even with a wrong header name or misparsed delta shape, which would defeat this story's whole purpose (a client that actually works against the real API). The Messages API's stable, documented shape as of this writing:

- **Endpoint:** `POST https://api.anthropic.com/v1/messages`
- **Headers:** `x-api-key: <key>` (not `Authorization: Bearer`), `anthropic-version: 2023-06-01`, `content-type: application/json`
- **Body:** `{"model": "claude-opus-4-8", "max_tokens": <int>, "thinking": {"type": "adaptive"}, "stream": true, "system": "...", "messages": [{"role": "user", "content": "..."}]}`
- **SSE event stream** (each event is `event: <type>\ndata: <json>\n\n`): `message_start` → one or more `content_block_start`/`content_block_delta` (delta shape `{"type": "text_delta", "text": "..."}`, this is what AC6's `Stream<String>` yields) /`content_block_stop` → `message_delta` (carries `stop_reason`) → `message_stop`. An `error` event (auth/overload/etc.) can arrive instead of/within the stream and must map into the AC7 exception hierarchy, not crash the parser (AD-8). `ping` events may appear and should be ignored.

**Before finalizing `messages_api_client.dart`, verify this shape against Anthropic's current published Messages API + streaming reference** (headers, event names, and delta JSON keys are the parts most likely to have shifted) rather than trusting this doc-derived summary blindly — the same "verify before asserting" discipline this story's Dev Notes already applies to `flutter_secure_storage` mocking.

### Architecture constraints

- **AD-9 (per-slice purity, I/O in adapters only):** `ai_client.dart` stays pure Dart — no `dart:io`, no `package:http`, no Flutter. All I/O (`flutter_secure_storage`, `package:http`) lives only in `key_store.dart`/`messages_api_client.dart`.
- **AD-11 (the ADR this whole story implements):** "AI calls go direct to the Messages API over HTTPS with a **user-configured** key in secure device storage (never logged or persisted in plaintext). Nothing is sent until the user confirms a context-preview... The `ai/` slice produces text only — it never writes files." The context-preview half is Story 4.2's job; this story must not add any code path that sends a request without going through a caller-supplied prompt (i.e., don't hard-code a request to fire from Settings itself — Settings only manages the key).
- **AD-12 (slice privacy):** `ai/` exposes its port + value types + `KeyStore` via `ai.dart`'s barrel; `MessagesApiClient` is named only by `main.dart`, exactly like `storage/`'s `AllFilesRepoStorage`.
- **AD-8 (total, never throw) at UI call sites:** a `KeyStore`/`MessagesApiClient` failure must degrade to visible state, never crash — apply this project's "AD-8 at the call site" lesson (enforce it in `SettingsPage`'s own try/catch, not just inside the adapters).
- **Testing standard for this story:** the key-store round-trip and the HTTP/SSE/retry logic are business logic and data-safety-adjacent (a key that silently fails to save, or a client that retries forever/never, is a real defect) — cover them thoroughly. The Settings screen gets representative flow tests (configured/not-configured/clear/error), not exhaustive layout tests, per this project's stated testing philosophy (`project-context.md`'s Testing emphasis section).

### Previous story intelligence

Story 3.2 (most recently completed) is a UI-only story in a completely different domain (text editing/navigation), so little *code* carries forward — but its process lessons do:
- **Cross-model review found a real, verified bug last time** (a text-corruption edge case reasoning alone missed) — for this story, the highest-risk, easiest-to-get-subtly-wrong areas are the SSE parser (partial-chunk boundaries, multi-line `data:` fields) and the retry/backoff logic (off-by-one attempt counts, retrying non-retryable errors) — write real tests against a fake transport for these, don't just reason through them.
- **"Verify before asserting" for framework/platform uncertainty**, not just reasoning: `flutter_secure_storage`'s test-mocking mechanism is exactly this kind of uncertainty (Task 4.1 calls this out explicitly) — confirm empirically rather than assuming it behaves like `shared_preferences`'s mock support.
- **Cross-check the diff's file list against `git status` before sending to review subagents** — this story touches fewer files than 3.2 but spans two previously-separate concerns (secrets + networking); don't let either half go unreviewed.

### Project Structure Notes

This is the first story to populate `apps/mobile/lib/ai/` beyond its placeholder barrel, and the first to add a `test/ai/` directory (mirroring the existing `test/lore/`, `test/app/`, `test/storage/` split). No changes to `apps/mobile/lib/lore/lore_loader.dart`, `lore_model.dart`, `convention_matcher.dart`, or any golden fixture. No changes to `apps/mobile/lib/storage/**`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 4.1, and Stories 4.2–4.4 for scope boundaries]
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md — FR20, FR21, FR22, FR23, NFR4, NFR5]
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/addendum.md §C "AI shape, model, cost" — transport, model, SSE, retry, key storage, glossary]
- [Source: MOBILE.md §6 "AI assist" (§6.4 "Shape, model, cost" especially) — the fuller narrative version of the addendum, plus ADR 7]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md — AD-8, AD-9, AD-11 (binds this story directly), AD-12; slice ownership table (`ai/` row); stack table (`flutter_secure_storage`, `claude-opus-4-8`)]
- [Source: _bmad-output/project-context.md — Security/privacy §6, Testing emphasis]
- [Source: apps/mobile/lib/storage/repo_storage.dart — the port shape this story's `AiClient` port mirrors]
- [Source: apps/mobile/lib/storage/repo_root_store.dart — the secure-vs-non-secure storage precedent, and its own forward-reference to this exact story]
- [Source: apps/mobile/lib/storage/storage.dart — the barrel pattern (export port + value types, withhold the concrete adapter) this story's `ai.dart` mirrors]
- [Source: apps/mobile/lib/main.dart, apps/mobile/lib/app/app.dart, apps/mobile/lib/app/home_page.dart — the composition-root injection pattern and the AppBar this story adds a settings entry point to]
- [Source: apps/mobile/lib/ai/ai.dart — the existing placeholder barrel this story populates]
- [Source: apps/mobile/pubspec.yaml — confirms no `flutter_secure_storage`/`http`/network dependency exists yet]
- [Source: apps/mobile/test/storage/repo_root_store_test.dart — the `shared_preferences` mock-testing precedent; `flutter_secure_storage`'s equivalent must be verified separately, see Task 4.1]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5 (story creation and implementation).

### Debug Log References

- `flutter_secure_storage` 11.0.0 (current stable, pinned by `flutter pub add`) ships a built-in `FlutterSecureStorage.setMockInitialValues(...)`, verified by reading the package source rather than assuming the MethodChannel-mocking mechanism the story originally hypothesized — confirms the "verify before asserting" note in Dev Notes was warranted, and simplified `KeyStore` (no injection seam needed).
- `prefer_initializing_formals` fired on `MessagesApiClient`'s constructor (public named params `httpClient`/`keyStore`/... assigned to private fields `_httpClient`/`_keyStore`/...) — following the lint's literal suggestion (`this._httpClient` as a named parameter) would make that parameter's name private and therefore uncallable by name from any other file. Resolved with a file-level `// ignore_for_file: prefer_initializing_formals` and a comment explaining why, rather than following a lint suggestion that would break the public API.
- The Messages API wire contract (endpoint, headers, SSE event/delta shape) documented in the story's Dev Notes was used as-is for `messages_api_client.dart` and the SSE-parsing tests; all 12 `messages_api_client_test.dart` tests (including the deliberately chunk-misaligned SSE test and the mid-stream-error test) passed on first run against that contract. Post-review, the Acceptance Auditor independently re-verified the same contract against the current published reference and confirmed it correct.
- **Post-review, isolated `dart run` probes (not `flutter test`, to strip away test-framework noise) found a genuine Dart async-generator/Stream gotcha**: `try { yield* someStream; } catch (...) { }` does not reliably catch errors from a delegated stream — a chain of `outerAsyncGenerator { yield* innerAsyncGenerator(src).timeout(d).handleError(rethrow-wrapped) }` silently hung instead of propagating, reproduced 5 times with progressively narrower probes before finding the actual trigger: `.timeout()` sitting *between* two nested async* generators, consumed via `.toList()`, on a source that never emits before the deadline. Fixed by moving `.timeout()` below the innermost generator (onto the raw byte stream feeding `_parseSse`) and using `.handleError()` (not try/catch) on the outer stream — verified with the same probes before touching production code, then covered by real tests.

### Completion Notes List

- All 11 ACs implemented across Tasks 1–5: secure key storage + Settings UI (AC1–4), `MessagesApiClient` (AC5–8, 10–11), slice boundary (AC9).
- `KeyStore` ended up simpler than planned: `flutter_secure_storage` 11.0.0's built-in mock support meant the constructor-injection fallback Task 1.3 specified wasn't needed — `KeyStore` constructs `const FlutterSecureStorage()` internally, matching `RepoRootStore`'s existing pattern.
- `MessagesApiClient`'s retry backoff and `KeyStore`'s underlying storage are both designed for testability per the story's own guidance: `backoff` is an injectable `Duration Function(int attempt)` (tests use `Duration.zero`), and `flutter_secure_storage`'s own mock support covers `KeyStore` without any extra seam.
- Nothing in this story invokes `MessagesApiClient` from the UI — `main.dart` constructs only `KeyStore` (Settings needs it); `MessagesApiClient` is proven exclusively by its own tests, exactly as scoped ("stand up the plumbing," not wire it into a feature — that's Stories 4.3/4.4).
- Post cross-model review (Blind Hunter + Edge Case Hunter + Acceptance Auditor on Opus), 1 decision (Android backup posture, resolved by user: disable entirely) and 18 patches were applied, including two high-severity, verified-real defects: a missing `INTERNET` permission that would have made every AI call fail in a release build, and a mid-stream failure that escaped the typed exception hierarchy entirely. Applying the fix for the latter surfaced a genuine Dart runtime gotcha (see Debug Log) that would otherwise have shipped a silent-hang bug in the idle-timeout feature the same patch round added. 3 findings were deferred as real-but-architecturally-out-of-proportion for this story (logged in `deferred-work.md`); 6 were dismissed as noise or matching existing codebase precedent. See the Review Findings subsection above for the full breakdown.
- Full regression after patches: 490 `flutter test` passing (473 pre-patch + 17 new), `flutter analyze` clean, no changes to `lore_loader.dart`/`lore_model.dart`/`convention_matcher.dart`/fixtures/`storage/`, no logging calls anywhere near key-handling code.

### File List

**New:**
- `apps/mobile/lib/ai/ai_client.dart`
- `apps/mobile/lib/ai/key_store.dart`
- `apps/mobile/lib/ai/messages_api_client.dart`
- `apps/mobile/lib/app/settings_page.dart`
- `apps/mobile/test/ai/key_store_test.dart`
- `apps/mobile/test/ai/messages_api_client_test.dart`
- `apps/mobile/test/app/settings_page_test.dart`

**Modified:**
- `apps/mobile/lib/ai/ai.dart`
- `apps/mobile/lib/app/app.dart`
- `apps/mobile/lib/app/home_page.dart`
- `apps/mobile/lib/main.dart`
- `apps/mobile/android/app/src/main/AndroidManifest.xml` (`INTERNET` permission, `allowBackup="false"`)
- `apps/mobile/pubspec.yaml` / `pubspec.lock` (+`flutter_secure_storage`, +`http`)
- `apps/mobile/test/fakes.dart` (+`FakeKeyStore`)
- `apps/mobile/test/widget_test.dart`
- `apps/mobile/test/app/browse_test.dart`
- `apps/mobile/test/app/create_entity_test.dart`
- `apps/mobile/test/app/promote_entity_test.dart`

## Change Log

| Date | Change |
|------|--------|
| 2026-08-07 | Implemented secure AI-key storage + Settings UI (Tasks 1, 3) and the `MessagesApiClient` adapter with SSE parsing + retry (Task 2), all 11 ACs; full regression green; status → review. |
| 2026-08-07 | Cross-model code review (Opus): 1 decision resolved (Android backup posture), 18 patches applied (incl. a missing release-build `INTERNET` permission and a mid-stream exception-typing gap that also surfaced a genuine Dart async-generator/`.timeout()` runtime bug), 3 deferred, 6 dismissed; full regression green. |
