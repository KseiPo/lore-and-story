---
baseline_commit: 6c4be3127d5b63a287b1e39e4818fe5027e7d1fc
---

# Story 4.2: Preview exactly what will be sent

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to see everything that will leave my device before any AI call,
so that I stay in control of what's shared.

## Context

**FR22, and the epics.md ACs for this story:**
> Before any send, the app shows a **context preview** — a scrollable sheet of exactly what will leave the device (the file, the glossary terms, the conventions). Sending is gated behind this preview. *(Mandatory per `ARCHITECTURE.md` §6.)*
>
> Given an AI action is about to send, When it triggers, Then a scrollable preview shows the exact payload (the file, glossary terms, conventions) and sending is gated behind it. Given I dismiss the preview, When I cancel, Then nothing is sent.

**Scope, precisely — this story builds the reusable gate, not a real AI action.** Neither Story 4.3 (translate) nor Story 4.4 (grammar) exists yet — the epics.md AC's "an AI action is about to send" describes how a *future* caller will use this component, exactly the same shape as Story 4.1 ("stand up the plumbing, not wire it into a feature"). Story 4.3's own AC explicitly assembles "the context pack (RU file + alias glossary + prose conventions)" and *then* "shows the FR22 preview" — the assembly is 4.3's job, not this story's. This story owns only:
1. A generic, reusable preview sheet that renders an ordered list of labeled text sections in full, verbatim, no truncation/summarization.
2. The confirm/cancel gate itself — a definite yes/no the caller acts on.

Nothing here calls `AiClient`, assembles a glossary, or reads a file. It has no network, no storage, no `ai/` port dependency at all — it is pure presentation plus one boolean decision.

**One design decision made up front, with reasoning, since neither the PRD/addendum/architecture spell out the exact data shape:**

**The preview's input is a generic `List<ContextSection>` (`label` + `text`), not hardcoded fields for "the file / glossary / conventions."** FR22's wording ("the file, the glossary terms, the conventions") describes *Story 4.3's specific* context pack; Story 4.4's (grammar) context pack is never specified anywhere and may differ (it's plausible grammar review doesn't need a glossary at all). Hardcoding three named fields here would force Story 4.4 to either stuff mismatched data into fields that don't fit, or refactor this widget later. A generic ordered list of labeled sections is reusable by both without knowing their exact shapes in advance, and still satisfies FR22 literally: each section is rendered by its own label with its own full text.

**Slice placement — this lives in `ai/`, not `app/`, unlike every other dialog/sheet in this codebase (e.g. `lint_panel.dart`).** This isn't a stylistic choice — `ARCHITECTURE-SPINE.md`'s slice-ownership table states it explicitly: *"`ai/` | `AiClient` port + Messages-API/SSE adapter + secure key store + context-preview / translate / grammar UI"* and the Capability→Architecture map: *"Epic 4 — AI assist | `ai/` (port + adapter + **context-preview UI**) | AD-11."* AD-9's "no Flutter imports" purity rule binds only the pure *port* file (`ai_client.dart`) — adapters and UI within the same slice are expected to do I/O/Flutter work (exactly like `key_store.dart`/`messages_api_client.dart` already do). This is a new *kind* of file for the slice (UI, not port/adapter), but not a new *exception* to any rule.

## Acceptance Criteria

1. **(FR22 — the gate itself)** Given a list of context sections, when the preview is shown, then a scrollable bottom sheet renders before any send can happen — the caller gets a `Future<bool>` it must await before proceeding.
2. **(FR22 — exact content, not a summary)** Each section's **full, verbatim text** is rendered — never truncated, elided, or summarized — so "exactly what will leave the device" is literally true, not approximately true.
3. **(Confirm)** Given the preview is showing, when I tap Confirm/Send, then the sheet closes and the returned `Future<bool>` resolves to `true`.
4. **(Cancel — every dismissal path)** Given the preview is showing, when I dismiss it — tapping Cancel, the system back gesture, or tapping outside the sheet — then the returned `Future<bool>` resolves to `false` in every case; nothing is sent.
5. **(AD-8 — total, never crash)** An empty `sections` list renders a clear "nothing to preview" state rather than a blank/broken sheet; a section with empty `text` still renders its label (not silently dropped) — the list of *what's about to be sent* must never lie by omission.
6. **(Reusable — no feature-specific shape)** The component's public API is `List<ContextSection>` (or equivalent generic label+text pairs) — it has no field named `glossary`/`conventions`/`file`, no dependency on `AiClient`, translation, or grammar-review specifics, so Stories 4.3 and 4.4 can each pass their own context pack shape without this widget changing.
7. **(Slice placement)** The preview lives in `apps/mobile/lib/ai/`, matching `ARCHITECTURE-SPINE.md`'s explicit slice-ownership table — not `apps/mobile/lib/app/`, where this codebase's other dialogs/sheets (e.g. `lint_panel.dart`) otherwise live.
8. **(Offline-safe — NFR4)** This story makes no network call of any kind and adds no new dependency on `AiClient`/`MessagesApiClient` — the component only renders text and returns a boolean, so the app's fully-offline behavior for every non-AI feature (and even this AI-adjacent one) is unaffected.

**Non-goals:** assembling any real context pack — the RU file, the alias glossary, or the prose conventions (Story 4.3's job); actually calling `AiClient.sendMessage` on confirm (Stories 4.3/4.4's job, once they exist); redacting, diffing, or otherwise transforming section content before display; a character/token count estimate (not required by any FR/NFR — add later only if a concrete need appears); persisting or remembering "always confirm" — every send is gated, every time, per FR22's own "mandatory" wording.

## Tasks / Subtasks

- [x] **Task 1: The generic preview sheet** (AC: 1, 2, 3, 4, 5, 6, 7)
  - [x] 1.1 New file `apps/mobile/lib/ai/context_preview.dart` — `ContextSection` (`label`, `text`) + `Future<bool> showContextPreview(...)`, mirroring `lint_panel.dart`'s shape.
  - [x] 1.2 `showModalBottomSheet<bool>(isScrollControlled: true, ...)`, `SafeArea`-wrapped, sections rendered via `SelectableText`, Confirm/Cancel `FilledButton`/`TextButton`. `return result ?? false;` normalizes the barrier/back-dismiss `null` case, matching `confirmDiscardUnsaved`'s identical pattern. Both button callbacks guard `if (!context.mounted) return;` before popping (AD-8-at-call-site, zero-cost here since both fire synchronously with no async gap).
  - [x] 1.3 Empty `sections` renders a keyed `Nothing to preview.` state; each section (even one with empty `text`) renders its own keyed block — count of rendered blocks always equals `sections.length`.
  - [x] 1.4 Exported from `apps/mobile/lib/ai/ai.dart`'s barrel.

- [x] **Task 2: Tests** (AC: all)
  - [x] 2.1 New file `apps/mobile/test/ai/context_preview_test.dart` — 9 tests: full-text/no-truncation rendering (a 5000-char section), the FR22-literal-fields traceability test, Confirm→`true`, Cancel→`false`, **verified empirically**: system back gesture (`tester.binding.handlePopRoute()`) → `false`, barrier tap-outside → `false` (both confirmed against the real implementation, not assumed), empty `sections` → empty state, multiple sections render in order, an empty-text section still renders its label. All pass on first run.

- [x] **Task 3: Regression and hygiene gates** (AC: all)
  - [x] 3.1 Full `flutter test` green — 499 tests passing (490 pre-existing + 9 new).
  - [x] 3.2 `flutter analyze` clean — 0 issues.
  - [x] 3.3 Confirmed: `git status --porcelain` under `lib/`/`test/` shows exactly 3 files — `ai/ai.dart` (modified), `ai/context_preview.dart` (new), `test/ai/context_preview_test.dart` (new). No `app/`, `lore/`, `storage/`, or Story 4.1 file touched.
  - [x] 3.4 Confirmed: `context_preview.dart`'s only import is `package:flutter/material.dart` — no `AiClient`/`MessagesApiClient`/`KeyStore`/`package:http`/storage dependency of any kind.

### Review Findings

Cross-model adversarial review (Blind Hunter + Edge Case Hunter + Acceptance Auditor, all on Opus; implementation was on Sonnet 5) against the uncommitted diff. Every finding below was verified by reading the actual source — several were also independently confirmed by the reviewing subagents via throwaway widget-test probes, not just reasoned about.

- [x] [Review][Patch] **Confirming an empty preview resolves `true`.** The Send button has no conditional disabling — with `sections: []` the sheet shows "Nothing to preview." and an enabled Send button; tapping it resolves `true`, and a caller acts on that as consent to send. This is the exact failure mode AC5 exists to prevent ("the list of what's about to be sent must never lie by omission") and directly undermines AD-11's core guarantee, arrived at from the other direction — confirmed independently by all three review layers via live probes. [apps/mobile/lib/ai/context_preview.dart:74-78]
- [x] [Review][Patch] `_pop`'s `if (!context.mounted) return;` guard returns **without popping** if it ever fired — stranding `showContextPreview`'s `Future<bool>` unresolved forever, which inverts the "never strand" half of AD-8 in the very guard added in AD-8's name. Neither cited precedent actually supports this shape: `settings_page.dart` only guards `State.mounted` after a genuine `await`, and `confirmDiscardUnsaved` (the more relevant precedent) has no guard at all in its button callbacks, because — as this file's own comment concedes — there is no async gap in which unmounting could occur. [apps/mobile/lib/ai/context_preview.dart:87-94]
- [x] [Review][Patch] AC2's "never truncated" test (`expect(find.text(longText), findsOneWidget)`) only proves the string reached a widget's `text`/`data` property — it would stay green even if a future edit added `maxLines`/`overflow` and visually clipped the content, since `find.text` doesn't inspect rendered/scroll geometry. The current implementation is genuinely correct (verified: full scroll extent reaches the end of a 5000-char section), but the test can't detect the regression it exists to prevent. [apps/mobile/test/ai/context_preview_test.dart — "renders each section's exact label and full, untruncated text"]
- [x] [Review][Patch] The barrier-dismiss test's `tester.tapAt(const Offset(200, 10))` only lands on the modal barrier because the test's payload is a single short section, leaving most of the screen uncovered. With a realistic, near-full-height preview (an actual file), the same coordinate would land on the sheet's own content, not the barrier — the test would silently stop testing what it claims. Target `find.byType(ModalBarrier)` directly instead of a raw coordinate. [apps/mobile/test/ai/context_preview_test.dart — "tapping outside the sheet (barrier dismiss) resolves false"]
- [x] [Review][Patch] Every section is built eagerly in a plain `Column` inside `SingleChildScrollView`, diverging from `lint_panel.dart` — the story's own cited prior art — which uses `ListView.builder(shrinkWrap: true)` for exactly this "list of items in a sheet" shape. Confirmed via probe: 200 sections all build immediately, none lazily. A component whose purpose is previewing potentially-large content shouldn't lay out everything at once. [apps/mobile/lib/ai/context_preview.dart:106-134]
- [x] [Review][Patch] `ContextSection` has no `==`/`hashCode`, isn't `final class`/`@immutable`, and the `sections` list isn't defensively copied before being handed to the sheet builder — no live bug was found (a mutation-after-show probe didn't reproduce a display divergence), but a type whose entire contract is "what you see is what's sent" deserves a tighter value-type guarantee than a plain mutable class with a stored-by-reference list. [apps/mobile/lib/ai/context_preview.dart:8-13, 35-45]
- [x] [Review][Patch] `apps/mobile/lib/ai/ai.dart`'s barrel doc comment still describes the slice as "port + adapter" and doesn't mention that it now also exports UI (`context_preview.dart`). [apps/mobile/lib/ai/ai.dart]
- [x] [Review][Patch] This story's own Dev Notes misattribute "AD-7 (one source of truth)" — the actual `AD-7` in `ARCHITECTURE-SPINE.md` is "One convention matcher, many consumers" (binds the highlighter/linter, a different ADR entirely). No general "one source of truth" ADR exists in the spine; correct the citation. [this file — Dev Notes → Architecture constraints]
- [x] [Review][Defer] Nothing structurally enforces the confirm gate — `showContextPreview` returns a bare `bool`, and `AiClient.sendMessage` remains directly callable without ever going through it, so the guarantee is a convention, not a compiler-enforced one (e.g. a capability-token type only this function can mint, required by the send path, would make it structural). Deferred: this only matters once Story 4.3 builds a real send call site to protect against being bypassed — designing the token shape now, with zero consumers, risks guessing wrong and having to redesign it anyway. [apps/mobile/lib/ai/context_preview.dart — API shape]
- [x] [Review][Defer] `ContextSection` (label+text pairs) cannot structurally represent the full wire payload a real AI request carries (model id, `max_tokens`, any system-prompt boilerplate the caller doesn't choose to show as a section) — "exactly what leaves the device" is only as complete as the sections a caller includes, with nothing here enforcing completeness. Deferred to Story 4.3: when assembling the real context pack, include a section for the non-file/glossary/convention parts of the request too, not just the three FR22 names literally. This is not a flaw introduced by keeping `ContextSection` decoupled from `AiRequest` — AC6 deliberately chose that decoupling, and it still stands. [apps/mobile/lib/ai/context_preview.dart — `ContextSection` vs apps/mobile/lib/ai/ai_client.dart's `AiRequest`]
- [x] [Review][Defer] Copy ("This will be sent" / "Send" / "Nothing to preview.") is hardcoded and feature-agnostic, with no indication of *where* the data is going (which provider/host) and no `Semantics` treatment for what is meant to be a mandatory consent surface. Deferred: Story 4.3/4.4 know which provider is configured (via Story 4.1's `KeyStore`/Settings) and can pass more specific copy, or this component can grow an optional parameter then — neither is required by any AC stated for this story. [apps/mobile/lib/ai/context_preview.dart — copy/accessibility]

**Dismissed as noise / false alarm / already correct:** `_bmad-output/planning-artifacts/epics.md` showing as modified with two new stories (4.5/4.6) not appearing in this review's diff, and Task 3.3's hygiene-gate check being scoped to `lib/`/`test/` only — both flagged by all three review layers as a "hidden scope creep" concern, but this is a false alarm: that `epics.md` change is unrelated pre-existing planning work from an earlier conversation turn (adding Stories 4.5/4.6 to the backlog), deliberately excluded from this review's diff because it isn't part of Story 4.2's implementation, not a hidden expansion introduced by it; the barrel (`ai.dart`) exporting a Flutter-dependent UI file, "breaking AD-9 purity" (AD-9 binds only model/matcher files per its own text — confirmed directly — not UI; this is exactly what the story's own Context section describes doing, sanctioned by the architecture, not a violation); forcing the user to scroll to the end before Send is enabled (a real UX idea, but not required by any FR/NFR, and would add real friction for a large file — out of this story's scope); whitespace-only/control-character section text or labels rendering as an apparently-empty block (narrow, cosmetic, no realistic near-term caller); guarding against a missing `Navigator`/`MaterialLocalizations` ancestor (unrealistic — every real call site is inside the app's normal widget tree; a loud dev-time assertion failure is the correct behavior here, not a silent catch); the FR22-literal-fields "traceability" test not exercising materially different code paths than the generic multi-section test (fair characterization, but the test still has legitimate documentation value and causes no harm); the test importing the whole `ai.dart` barrel instead of `context_preview.dart` directly (doesn't meaningfully change AC8 enforcement — Task 3.4's grep is already the correct mechanism); no test for a host route being popped while the sheet is open (speculative, not connected to any stated AC, and already covered indirectly by the same `result ?? false` normalization).

## Dev Notes

### What changes, precisely

- **New:** `apps/mobile/lib/ai/context_preview.dart` (the `ContextSection` type + `showContextPreview`), `apps/mobile/test/ai/context_preview_test.dart`.
- **Modified:** `apps/mobile/lib/ai/ai.dart` (one new barrel export line).
- **Unchanged:** everything else — `app/`, `lore/`, `storage/`, and every Story 4.1 file. This story has zero integration point yet (no caller exists until Story 4.3), so nothing outside `ai/` should need to change.

### Architecture constraints

- **AD-11 (the ADR this story partly implements):** *"Nothing is sent until the user confirms a **context-preview** showing exactly what leaves the device."* This story is the mechanism that makes that literally true — it must never be possible for a future caller to bypass it or for it to silently resolve "yes" without genuine user action (AC4's every-dismissal-path-is-false requirement is the concrete expression of this).
- **Slice ownership (`ARCHITECTURE-SPINE.md`'s table, quoted in Context above):** the context-preview UI is explicitly `ai/`'s to own, not `app/`'s — don't follow `lint_panel.dart`'s placement precedent here, even though the *shape* of the code (a top-level function wrapping `showModalBottomSheet`) should closely mirror it.
- **AD-8 (total, never throw):** an empty or partially-empty `sections` list must render a safe, honest state — never crash, never silently drop a section from what's displayed (that would defeat the entire point of a "see exactly what leaves the device" gate).
- **A note for future stories, not this one (no ADR governs this directly — `AD-7` is "One convention matcher, many consumers," which binds the highlighter/linter, a different concern):** when Story 4.3 assembles a real context pack, it will need to build *both* the `List<ContextSection>` shown here *and* the eventual `AiRequest` sent via `AiClient` from the same underlying data, so the preview and the actual request can never drift apart. Nothing to implement now — just don't design `ContextSection` in a way that would make that harder later (a plain label+text pair doesn't).
- **Testing standard for this story:** despite being pure UI, this gates a genuine data-safety concern (accidental exfiltration of file/glossary content) — this project's testing-emphasis policy explicitly carves out exactly this case ("decline [a UI test ask] unless it gates a data-safety path"). Cover it thoroughly, including the Flutter-dismissal-semantics edge cases (Task 2.1), not just the happy path.

### Previous story intelligence

Story 4.1 (most recently completed) is a different domain (network client, secrets), but two of its lessons apply directly here:
- **"Verify before asserting" for Flutter framework/platform behavior, not just reasoning it through** — Story 4.1 found a genuine, non-obvious Dart `Stream`/`async*` bug this way (documented in its Debug Log). This story's own analog is `showModalBottomSheet`'s exact dismiss-value semantics (does a back-gesture/barrier-dismiss genuinely produce `null`, and does this codebase's Flutter version's default barrier behavior actually allow tap-outside-to-dismiss for a bottom sheet at all, or does that need `enableDrag`/`isDismissible` set explicitly?) — confirm empirically with a real widget-test probe (Task 2.1), don't assume.
- **A related but *inapplicable* Story 3.1 lesson, noted so it isn't over-applied**: `lint_panel.dart`'s `runLintAndShowPanel` had a real bug where `showModalBottomSheet`'s returned Future doesn't complete until the sheet is *dismissed*, not when the panel's *data* is ready — which mattered there because findings were loaded *asynchronously before* the panel opened. That gotcha doesn't apply here: `showContextPreview` receives its `sections` already assembled by the caller (no async load step of its own), so there's no separate "data ready" moment to decouple from "dismissed." Do not add an `onLoaded`-style callback here — it would solve a problem this story doesn't have.

### Project Structure Notes

This is the first UI file in `apps/mobile/lib/ai/` — every existing file there (`ai_client.dart`, `key_store.dart`, `messages_api_client.dart`) is a port or adapter, not a widget. No changes to `apps/mobile/lib/lore/lore_loader.dart`, `lore_model.dart`, `convention_matcher.dart`, or any golden fixture. No changes to `apps/mobile/lib/storage/**`. No changes to any Story 4.1 file.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 4.2, and Story 4.3 for the "app assembles the context pack... shows the FR22 preview" scope boundary]
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md — FR22 (Group G), FR23 (Group H, "The FR22 context preview applies")]
- [Source: MOBILE.md §6.4 — "Context preview is mandatory, not optional. ARCHITECTURE §6 requires showing what leaves the machine before sending... a scrollable sheet (this file, N glossary terms, the conventions) behind the send button." (addendum.md §C covers transport/model/cost/key-storage only — it has no context-preview note of its own; don't look for this quote there.)]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md — AD-11 (binds this story directly), AD-8, AD-9 (purity scope — binds only the pure port file, not this UI file); slice-ownership table's `ai/` row explicitly naming "context-preview... UI"; Capability→Architecture map's "Epic 4 — AI assist | `ai/` (port + adapter + context-preview UI) | AD-11" row]
- [Source: apps/mobile/lib/app/lint_panel.dart — `showLintPanel`'s shape (top-level function wrapping `showModalBottomSheet`, `isScrollControlled: true`, `SafeArea`, key-per-row for testability) this story's `showContextPreview` mirrors, and the "Future completes on dismiss, not on data-ready" gotcha explicitly noted above as *not* applicable here]
- [Source: apps/mobile/lib/app/editor_page.dart — `confirmDiscardUnsaved`, the existing `showDialog<bool>` confirm/cancel-gate precedent this story's boolean-returning shape matches]
- [Source: apps/mobile/lib/ai/ai_client.dart, key_store.dart, messages_api_client.dart, apps/mobile/lib/app/settings_page.dart — Story 4.1's files; read for context/precedent, unchanged by this story]
- [Source: _bmad-output/implementation-artifacts/4-1-configure-an-ai-key-and-stand-up-the-api-client.md — most recent story; source of the "verify empirically" and `showModalBottomSheet` dismiss-Future lessons above]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5 (story creation and implementation).

### Debug Log References

- The story's two "verify empirically, don't assume" dismiss-semantics claims (system back gesture and barrier tap-outside both resolving `false` via `result ?? false`, not `null`/unresolved) were confirmed directly against the running implementation via `tester.binding.handlePopRoute()` and `tester.tapAt()` on the barrier — both passed on the first test run, no implementation changes needed.

### Completion Notes List

- All 8 ACs implemented across Tasks 1–3: the generic preview sheet (AC1, 2, 5, 6, 7), Confirm/Cancel/back/barrier gating (AC3, 4), offline-safety by construction (AC8 — no network-capable import anywhere in the new file).
- Design held up exactly as planned: `ContextSection`'s generic label+text shape needed no changes; the `ai/` (not `app/`) slice placement, and the `result ?? false` dismiss-normalization mirroring `confirmDiscardUnsaved`, both worked as specified.
- This story has no integration point yet and needs none — `context_preview.dart` is proven entirely by its own tests, with zero callers, exactly as scoped ("stand up the gate," not wire it into a feature — that's Story 4.3's job).
- Full regression: 499 `flutter test` passing (490 pre-existing + 9 new), `flutter analyze` clean, changes confined to exactly the 3 files the story specified.

### File List

**New:**
- `apps/mobile/lib/ai/context_preview.dart`
- `apps/mobile/test/ai/context_preview_test.dart`

**Modified:**
- `apps/mobile/lib/ai/ai.dart` (barrel export + doc comment)
- `_bmad-output/implementation-artifacts/deferred-work.md` (3 deferred review items appended)

## Change Log

| Date | Change |
|------|--------|
| 2026-08-07 | Implemented the generic context-preview sheet (`ContextSection` + `showContextPreview`) gating on explicit confirm, all 8 ACs; full regression green; status → review. |
| 2026-08-07 | Code review (cross-model, Opus vs. Sonnet 5 implementation): 8 patch findings applied — Send disabled on empty preview, `_pop` guard removed (matched `confirmDiscardUnsaved` precedent, no async gap existed), truncation test now asserts on `SelectableText.data`/`maxLines` directly, barrier-dismiss test targets `ModalBarrier` instead of a coordinate, sections render via `ListView.builder` instead of an eager `Column`, `ContextSection` is now `@immutable` with value equality and the sections list is defensively copied, `ai.dart`'s doc comment now mentions the UI export, and the story's own AD-7 misattribution is corrected. 3 items deferred to `deferred-work.md`. Full regression re-verified green (499 tests, `flutter analyze` clean) after patches; status → done. |
