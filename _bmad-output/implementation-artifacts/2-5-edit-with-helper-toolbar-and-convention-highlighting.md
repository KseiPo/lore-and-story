---
baseline_commit: b6238e8
---

# Story 2.5: Edit with helper toolbar and convention highlighting

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want quick-insert buttons and convention-aware highlighting,
so that phone editing of these files is fast and readable.

## Acceptance Criteria

1. **AC1 (FR8 — helper toolbar):** Given the editor is open, when I use a helper toolbar above the keyboard, then I can insert **structure** (H1/H2/H3, bullet list, numbered list, bold, italic) and **project tokens** (`[[`, `[`, `]`, `—`, an `(emotion):` snippet) via three mechanisms — **insert-at-cursor**, **wrap-selection**, and **prefix-line** — and each action updates the buffer and the dirty state.
2. **AC2 (FR9 — convention-aware highlighting):** Given file text, when it renders in the editor, then **markdown structure** (headings, `**bold**`, `_italic_`/`*italic*`, list markers) **plus this project's conventions** (`[[wikilinks]]`, dialogue `Name (emotion):` lines, `[placeholders]`, em-dash `—` conditional markers) are visually highlighted **while the underlying buffer stays raw markdown** (no WYSIWYG, no markup hidden — typing `**x**` shows `**x**`).
3. **AC3 (AD-7 — one matcher, factored standalone):** Given the highlighter, when the convention matcher is built, then it is a **standalone, pure component in the `lore/` slice** (no Flutter, no `dart:io` — AD-9) that returns typed tokens over a string; the highlighter consumes it, and it is written so the **Story 3.1 linter reuses the same matcher** (and Story 2.6 extends it with error kinds) — it is **not** inlined into the editor widget.
4. **AC4 (AD-8/NFR7 — total, never hides, never throws):** Given any input including malformed/unexpected markup, when the highlighter's `buildTextSpan` runs, then it **degrades to plain text and never throws**; the buffer is never mutated by highlighting; a malformed file still opens, edits, and saves.
5. **AC5 (hygiene; no regressions):** Existing editor behavior is preserved — load, dirty indicator, explicit save, save-on-background, save-on-pop, the lossy-UTF-8 guard, and the conflict-copy banner (Story 2.4). `flutter analyze` clean; `flutter test` green with new matcher/controller/toolbar/editor tests; fixtures 4/4 and `npm test` 4/4 (no loader/model/contract change).

## Tasks / Subtasks

- [x] **Task 1 — Pure convention matcher in `lore/` (AC: 2, 3, 4)**
  - [x] Add `apps/mobile/lib/lore/convention_matcher.dart` — **pure Dart, no Flutter, no `dart:io`** (AD-9). Export from the `lore/` barrel (`lore.dart`).
  - [x] Define `enum ConventionKind { heading, bold, italic, listMarker, wikilink, dialogueSpeaker, placeholder, emDash }` and `class ConventionToken { final int start; final int end; final ConventionKind kind; }` (half-open `[start, end)` offsets into the input string).
  - [x] Implement `List<ConventionToken> matchConventions(String text)` returning a **sorted, non-overlapping** token list (see Dev Notes for the line-oriented algorithm, recommended regexes, and precedence). **CRLF-safe** (offsets into the original text; a trailing `\r` must not shift or break matches).
  - [x] **Never throws (AC4):** wrap the body so any regex/indexing failure returns whatever tokens were collected (or empty) rather than throwing. Malformed input is content to flag, not a fault.
  - [x] Keep `ConventionKind` **open to extension**: Story 2.6 adds error kinds (leaked twee, invalid markup, scene passage-links) and Story 3.1's linter consumes the same tokens — do not hard-wire assumptions that only these 8 kinds exist.
- [x] **Task 2 — Highlighting `TextEditingController` in `app/` (AC: 2, 4)**
  - [x] Add `apps/mobile/lib/app/convention_highlighting_controller.dart` — `class ConventionHighlightingController extends TextEditingController`, overriding `TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing})`.
  - [x] In `buildTextSpan`: call `matchConventions(text)`, then build a **flat** `TextSpan` whose children are the plain gaps + the styled token spans (kind → `TextStyle`, merged onto the base `style`). Styles come from `Theme.of(context)` (headings larger+bold+primary; wikilink/dialogue/placeholder/emDash colored; bold→`FontWeight.bold`; italic→`FontStyle.italic`; listMarker muted). **Preserve the composing underline** behavior for IME when `withComposing` is true (fall back to `super.buildTextSpan` semantics for composing if it complicates things — but never drop text).
  - [x] **Total (AC4):** wrap the whole tokenize+build in `try/catch`; on ANY error return `TextSpan(text: text, style: style)` (plain). The concatenation of all child spans' text MUST equal `text` exactly — assert/verify no character is dropped or duplicated (a highlighter that loses characters corrupts what the user sees).
  - [x] The controller holds **no** matching logic of its own — it only maps `ConventionKind → TextStyle` and consumes `matchConventions` (AD-7).
- [x] **Task 3 — Helper toolbar + pure text-ops in `app/` (AC: 1)**
  - [x] Add `apps/mobile/lib/app/editor_toolbar.dart`: (a) **pure text-operation functions** over `TextEditingValue` — `insertAtCursor(value, text)`, `wrapSelection(value, before, after)`, `prefixLines(value, prefix)` — each returning a new `TextEditingValue` with correct text **and** selection/cursor; and (b) an `EditorToolbar` widget (a horizontally scrollable row of compact buttons) that applies them to the editor's controller.
  - [x] **Buttons (FR8):** Structure — H1/H2/H3 (`prefixLines('# '/'## '/'### ')`), bullet (`prefixLines('- ')`), numbered (`prefixLines('1. ')`), bold (`wrapSelection('**','**')`), italic (`wrapSelection('_','_')`). Project tokens — `[[` (insert `[[]]` with the cursor **between** the pairs, ready to type the title), `[` and `]` (single-char inserts), `—` (insert the em-dash U+2014), `(emotion):` (insert `(emotion): ` snippet).
  - [x] `wrapSelection` with an empty selection inserts `before+after` and places the cursor **between** them (so bold/italic/`[[` work with no selection). `prefixLines` toggles/prepends the prefix to every line the selection touches (v0.1: prepend; no need to un-prefix).
  - [x] Applying an action goes through the controller's `value` setter so the existing `_onChanged` listener marks the buffer dirty (AC1). Keep the ops **pure and unit-testable** (no widget needed to test them).
- [x] **Task 4 — Wire into `EditorPage` (AC: 1, 2, 5)**
  - [x] In `apps/mobile/lib/app/editor_page.dart`, change `_controller` to a `ConventionHighlightingController` (the `TextField` picks up `buildTextSpan` automatically). **Preserve** everything: `_load`, `_onChanged`/dirty, `_save`/`_canSave`, save-on-background, `_handlePop`, the lossy-UTF-8 guard + banner, the conflict-copy banner (Story 2.4), and the `kDirtyIndicatorKey`.
  - [x] Add the `EditorToolbar` **above the keyboard** — place it at the bottom of the ready-state body (after the `Expanded(TextField)`), so `resizeToAvoidBottomInset` keeps it just above the on-screen keyboard. Only show it in the ready state (not loading/error); it's fine to show for a lossy file, but wrapping/inserting into a non-savable buffer is acceptable (save stays disabled by the lossy guard).
  - [x] The buffer stays raw (AC2): the `TextField` continues to edit `_controller.text` directly; highlighting is display-only.
- [x] **Task 5 — Tests (AC: 1–5)**
  - [x] **Matcher unit tests** (`test/lore/`, pure): each kind matches its convention with correct ranges (heading `#`/`##`/`###` lines; `**bold**`; `_italic_`/`*italic*`; `- `/`* `/`1. ` list markers; `[[wikilink]]`; `Name (emotion):` dialogue prefix incl. a Cyrillic example `Селена (спокойно):`; `[placeholder]` single-bracket, and `[[x]]` is **not** a placeholder; `—` em-dash). Non-overlap/precedence (a `[[link]]` is a wikilink not a placeholder; bold not double-counted as italic). CRLF input yields the same tokens as LF. Malformed/pathological input returns without throwing.
  - [x] **Controller tests** (`test/app/`): `buildTextSpan` over a sample produces a `TextSpan` whose flattened text equals the input (no characters lost) and whose children carry the expected styles for a couple of kinds; a malformed input returns a plain span and never throws (AD-8).
  - [x] **Text-op unit tests** (`test/app/`): `insertAtCursor`, `wrapSelection` (with and without a selection → cursor placement), `prefixLines` (single and multi-line selection) produce the expected text + selection.
  - [x] **Editor widget tests** (`test/app/`): tapping bold wraps the selection (`**x**`) and marks dirty; H2 prefixes the line (`## `); `[[` inserts `[[]]` with the cursor between; the buffer shows raw markup (typing `**x**` yields literal `**x**` in the `TextField`); save still works (regression); the toolbar shows in the ready state.
  - [x] Re-run fixtures (4/4) and `npm test` (4/4); `flutter analyze` clean; `flutter test` green. Confirm existing editor tests (`editor_page_test.dart`) and the conflict-banner tests still pass.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers). The Acceptance Auditor independently re-ran the gates (analyze clean, 176/176, `npm test` 4/4, contract+loader/model git-clean; matcher confirmed pure — 0 imports) and **all 5 ACs fully implemented**. Blind Hunter confirmed **no ReDoS** (regexes linear, <2ms at 70k chars). Findings below are gaps around the edges.

**Patch:**

- [x] [Review][Patch] **Toolbar buttons steal focus → the keyboard closes.** Material `IconButton`/`TextButton` request focus on tap, so the `TextField` loses focus and the IME dismisses — defeating FR8's "toolbar above the keyboard." Wrap the toolbar in `Focus(canRequestFocus: false, descendantsAreFocusable: false, …)` so taps fire without moving focus. [apps/mobile/lib/app/editor_toolbar.dart] (blind)
- [x] [Review][Patch] **`prefixLines` off-by-one + start-of-buffer bug.** The `consumed <= selEndInRegion` check prefixes the *next* line when a selection ends exactly at a `\n` (an ordinary "select the line" shape); and a caret at offset 0 of a buffer starting with `\n` no-ops and returns an inverted selection (the `sel.start > 0 ? … : 0` clamp finds the leading `\n`). Fix the boundary condition (distinguish a collapsed caret at a line start from a selection ending there) and compute `firstLineStart` as 0 when `sel.start == 0`. [apps/mobile/lib/app/editor_toolbar.dart prefixLines] (blind+edge)
- [x] [Review][Patch] **The pure text-ops aren't total — a stale out-of-range selection throws `RangeError`.** `_sel` checks `isValid` but never clamps offsets to `text.length`; `insertAtCursor`/`wrapSelection` then throw on `substring`/`replaceRange`, and `prefixLines` silently prefixes every line. Clamp `_sel`'s start/end to `[0, text.length]` — the matcher and `buildTextSpan` are total (try/catch); these user-reachable ops should be too. [apps/mobile/lib/app/editor_toolbar.dart _sel] (blind+edge)
- [x] [Review][Patch] **A line-start `[[wikilink]]` in a dialogue-shaped line loses its highlight.** `dialogueSpeaker` outranks `wikilink` and the `_dialogue` leading-char class `[^\s:.!?]` doesn't exclude `[`, so `[[Name]] (emotion): text` drops the wikilink token in overlap resolution. Exclude `[` from the dialogue leading char so the wikilink survives. Add a test. [apps/mobile/lib/lore/convention_matcher.dart _dialogue] (auditor)
- [x] [Review][Patch] **Heading token includes the trailing `\r` on CRLF lines.** The whole-line heading span runs through the carriage return; trim it so the CRLF-safe claim is clean (cosmetic but trivial). [apps/mobile/lib/lore/convention_matcher.dart _matchLine] (blind)
- [x] [Review][Patch] **No memoization — `buildTextSpan` re-matches the whole buffer on every rebuild.** Add a light by-text memo in the controller so non-text rebuilds (selection/theme/focus) reuse the last tokens. (Per-keystroke full-doc match on very long scenes remains a deferred, larger concern; regexes are linear so it's cost, not a hang.) [apps/mobile/lib/app/convention_highlighting_controller.dart] (blind)
- [x] [Review][Patch] **Test comment overclaims.** The editor "keeps buffer raw" test asserts on `controller.text` (via the finder), not `buildTextSpan`; correct the comment (the render invariant is proven in the controller test). [apps/mobile/test/app/editor_page_test.dart] (auditor)

**Deferred:**

- [x] [Review][Defer] **IME composing underline not drawn** — `buildTextSpan` ignores `withComposing`/`value.composing`, so the standard in-progress-composition underline never renders. Documented v0.1 tradeoff; Cyrillic is direct-input (not composed), so low practical impact. Revisit if composed (e.g. CJK) input is needed. [apps/mobile/lib/app/convention_highlighting_controller.dart] (blind)
- [x] [Review][Defer] **Dialogue heuristic misses a speaker after a stray colon** — `See note 3:00 — Frank: hi` yields no dialogue token (`matchAsPrefix` can't skip the earlier colon). Heuristic limitation; the Story 3.1 linter will refine the matcher. [apps/mobile/lib/lore/convention_matcher.dart _dialogue] (blind)
- [x] [Review][Defer] **Per-keystroke full-document re-match on long scene files** — the memo above helps non-text rebuilds only; true incremental/viewport matching is a larger change. Realistic files are small (a scene is a few KB), so deferred. [apps/mobile/lib/app/convention_highlighting_controller.dart] (blind)
- [x] [Review][Defer] **Lone `\r` (old-Mac) not treated as a line break** — `split('\n')` only; a heading then swallows the rest of the "line". No such files in this project; cosmetic (span only). [apps/mobile/lib/lore/convention_matcher.dart] (edge)

## Dev Notes

### What this story is — the convention-aware editing surface (three pieces)

This is the story that makes the editor "not just a bare text field." Three deliverables, each independently testable:

1. **A pure convention matcher** (`lore/`) — recognizes this project's conventions over a string and returns typed tokens. **This is the AD-7 keystone:** the highlighter consumes it now, the **Story 3.1 linter** consumes the *same* tokens later, and **Story 2.6** extends it with error kinds. It must be pure (`lore/`, no Flutter) and total (never throws).
2. **A highlighting `TextEditingController`** (`app/`) — overrides `buildTextSpan` to style the raw buffer using the matcher's tokens. Display-only; the buffer stays raw markdown (the whole point — the markup *is* the content being proofread, MOBILE §5).
3. **A helper toolbar** (`app/`) — quick-insert for the punctuation a phone keyboard makes painful, via insert/wrap/prefix.

### The conventions to highlight (ARCHITECTURE §3.3 — the source of truth)

FR9's explicit set for this story:

- **Markdown structure:** headings (`#`/`##`/`###`, highlight up to `######`), `**bold**`, `_italic_` (the project's canonical underscore emphasis) and `*italic*`, list markers (`- `, `* `, `1. `).
- **`[[wikilinks]]`** — lore entity references (`[[Title]]`), never passage jumps.
- **Dialogue `Name (emotion):` lines** — e.g. `Селена (спокойно): Иногда техника…` (Cyrillic is first-class). The emotion parenthetical is the distinctive marker.
- **`[placeholders]`** — readable single-bracket variables: `[имя героя]`, `[награда]`. **Not** `[[wikilinks]]`.
- **Em-dash conditional markers** — the em-dash `—` (U+2014), e.g. `— если игрок знаком с доктором Джулией — … — иначе — …`.

*(Out of scope for 2.5, do not build: choice/return link forms `**Choice** _(→ Passage)_` / `_(↩ back)_`, `scene ⇄ passage` comments, monologue markers `Мысль:`/`*Thought:*`. They can be added to the matcher later. And **error/invalid** markup styling is **Story 2.6** — 2.5 highlights only *valid* conventions.)*

### Recommended matcher algorithm (line-oriented, total, non-overlapping)

Process the text **line by line**, tracking a running offset, and emit tokens with offsets into the *original* string (CRLF-safe — split on `\n`; a line may retain a trailing `\r`, which the `^`-anchored line rules ignore and the inline rules don't care about):

```
matchConventions(text):
  tokens = []; offset = 0
  for each line (split on '\n', keep the '\r' if present):
    for each token t from matchLine(line): tokens.add(shift t by offset)
    offset += line.length + 1        // +1 for the consumed '\n'
  return tokens   // already ordered by construction; non-overlap enforced in matchLine
```

`matchLine(line)` (all offsets line-relative):

- **Heading:** if `^#{1,6}\s`, emit ONE `heading` token spanning the whole line and **return** (headings are "larger" — the whole line; inline tokens inside a heading are deliberately not separately highlighted in v0.1).
- Otherwise, collect **line-start** markers then **inline** tokens, then resolve overlaps by precedence:
  - **listMarker:** `^\s*([-*]|\d+\.)\s` → token over the marker (+trailing space).
  - **dialogueSpeaker:** a name-like prefix ending in `:`. **Recommended (heuristic, tunable):** `^\s*(\p{L}[\p{L}\p{M}0-9 '’-]{0,39}?)(\s*\([^)]*\))?\s*:\s` (Unicode-aware; `\p{L}` covers Cyrillic). Emit a `dialogueSpeaker` token over the prefix up to and including the `:`. *This is inherently heuristic — a line like `Note: …` can match; that is acceptable for highlighting, and the linter (3.1) will tune it. Prefer requiring either the `(emotion)` parenthetical OR a short single-word name to cut false positives; document whatever you choose.*
  - **inline** (scan the line; drop any that overlap a higher-precedence token): `wikilink` `\[\[[^\[\]]+\]\]` (precedence over placeholder), `placeholder` `\[[^\[\]]+\]` (a single-bracket run — exclude those adjacent to another `[`/`]` so `[[x]]` is not two placeholders), `bold` `\*\*[^*]+\*\*` (precedence over italic), `italic` `_[^_\n]+_` and `\*[^*\n]+\*`, `emDash` the literal `—`.
- **Overlap resolution:** collect candidate matches, sort by start; walk left-to-right emitting a token only if it doesn't overlap the last emitted one (higher-precedence kinds considered first at the same start). The result MUST be sorted and non-overlapping — the controller relies on it.

Provide these as a starting point; the dev may refine the regexes, but must keep the output **sorted, non-overlapping, total, and CRLF-safe**, and keep all matching in the pure matcher.

### The highlighting controller (`buildTextSpan`) — the total-safety contract

`TextField` calls `controller.buildTextSpan(context:, style:, withComposing:)` on every rebuild. Override it:

```dart
@override
TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
  try {
    final tokens = matchConventions(text);         // pure matcher
    final spans = <InlineSpan>[];
    var i = 0;
    for (final t in tokens) {
      if (t.start < i || t.end > text.length || t.start > t.end) continue; // defensive
      if (t.start > i) spans.add(TextSpan(text: text.substring(i, t.start), style: style));
      spans.add(TextSpan(text: text.substring(t.start, t.end), style: _styleFor(t.kind, context, style)));
      i = t.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i), style: style));
    return TextSpan(style: style, children: spans);
  } catch (_) {
    return TextSpan(text: text, style: style);      // AD-8: never throw, never hide/drop text
  }
}
```

**Invariant (test it):** the concatenation of all emitted spans' `text` equals `text` exactly — no character dropped, added, or reordered. This is what keeps the *buffer raw and the display faithful*. The defensive `continue` guards make out-of-range/overlapping tokens harmless even if the matcher regresses.

**IME/composing:** if honoring `withComposing` (the composing-region underline) alongside custom spans proves fiddly, it is acceptable for v0.1 to ignore the composing underline (do NOT drop or reorder text to achieve it). Never sacrifice the text-equals-input invariant for the underline.

### Helper toolbar & pure text-ops

The insert/wrap/prefix operations are **pure functions over `TextEditingValue`** (text + `TextSelection`), so they unit-test without a widget:

- `insertAtCursor(value, s)` — replace the selection with `s`; put the cursor after it.
- `wrapSelection(value, before, after)` — wrap the selected range with `before`/`after`; **empty selection** → insert `before+after` and put the cursor *between* them.
- `prefixLines(value, prefix)` — prepend `prefix` to the first char of every line the selection spans (v0.1: always prepend; no un-prefix toggle needed).

Get the selection right (base/extent, affinity) — an off-by-one cursor is the classic bug here; the unit tests are your guard. Apply via `controller.value = op(controller.value)` so `_onChanged` fires and the dirty indicator updates.

**Layout:** a compact, **horizontally scrollable** `Row` of ~12 buttons (icons or short labels) — `SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(...))` — pinned at the bottom of the editor body so it rides just above the keyboard. Group visually: structure buttons, then a divider, then project-token buttons.

### Files being MODIFIED / ADDED (read before editing)

- **`apps/mobile/lib/lore/convention_matcher.dart`** (NEW, pure) — the matcher; exported from `lore.dart`.
- **`apps/mobile/lib/app/convention_highlighting_controller.dart`** (NEW) — the controller + `ConventionKind → TextStyle`.
- **`apps/mobile/lib/app/editor_toolbar.dart`** (NEW) — pure text-ops + the toolbar widget.
- **`apps/mobile/lib/app/editor_page.dart`** (MODIFY) — current state: a `_EditorPageState` with a `TextEditingController _controller`; `_load` sets `_controller.text` (listener detached during the set); `_onChanged` tracks `_dirty`; `_save`/`_canSave` (single-flight, disabled on lossy load); `didChangeAppLifecycleState` saves on background; `_handlePop` saves-or-asks on back; `build` = `PopScope` → `Scaffold(appBar: path + dirty indicator + Save, body: _buildBody())`; `_buildBody` ready-state is a `Column` with the conflict banner (2.4), the lossy banner, then `Expanded(TextField(controller: _controller, maxLines: null, expands: true, monospace))`. **Change:** `_controller` becomes `ConventionHighlightingController`; add `EditorToolbar` at the bottom of the ready `Column`. **Preserve every other behavior** — the 1.4/2.4 reviews hardened save/dirty/pop/lossy/conflict; do not regress them.
- **`apps/mobile/lib/lore/lore.dart`** (MODIFY) — export `convention_matcher.dart`.

### Architecture guardrails

- **AD-7 — one matcher, many consumers.** All convention recognition lives in `convention_matcher.dart`. The controller and (later) the linter/FR9a consume its tokens; neither reimplements matching. This is the single most important structural rule of this story. [ARCHITECTURE-SPINE.md#AD-7]
- **AD-8 / NFR7 — total.** The matcher and `buildTextSpan` never throw; unclassifiable input degrades to plain text; a malformed file still opens/edits/saves. The span-text-equals-input invariant is part of this. [#AD-8]
- **AD-9 — purity.** The matcher is pure `lore/` (no Flutter/`dart:io`). The controller/toolbar are Flutter and live in `app/`. Styles/`TextEditingValue`/`BuildContext` never leak into `lore/`. [#AD-9]
- **Raw-markup rule (MOBILE §5, PRD):** never WYSIWYG, never hide markup — highlight over the raw buffer. Typing `**x**` shows `**x**`. This is a product invariant, not a preference. [PRD editing-UX]
- **AD-2 — contract untouched.** No loader/model change; `convention_matcher` is new and not part of the fixtures. Fixtures 4/4, `npm test` 4/4 (AC5). [#AD-2]
- **NFR6 — responsive.** `buildTextSpan` runs per keystroke; keep `matchConventions` O(n) over the text with a bounded regex set. Cards are a few KB — fine. Don't add per-character allocations in a hot loop; don't re-run on unrelated rebuilds if avoidable, but do not prematurely cache. [prd.md#NFR6]

### Previous story intelligence

- **2.4 (done):** `editor_page.dart` now also renders a **conflict-copy banner** (via the exported `isConflictCopy`) and imports `lore/`. Your toolbar/controller changes must keep that banner and the lossy banner intact. The 1.4/2.4 reviews hardened the save/dirty/pop machinery and the AD-8-at-call-site pattern — preserve them.
- **2.1a–2.3:** the `lore/` slice holds pure model logic (loader, model, `categoriesOf`); `convention_matcher.dart` joins it as another pure `lore/` component. The `app/` (UI) + `lore/` (pure) split is the established layout (the documented variance from the spine's "lore/ owns UI" wording).
- **Toolchain:** Flutter `C:\programs\flutter\bin` (3.44.7 / Dart 3.12.2); `flutter analyze` + `flutter test`; `npm test` for the JS reference cross-check. Dart regex supports Unicode property escapes (`\p{L}`) with `unicode: true` on `RegExp` — needed for Cyrillic name/dialogue matching; verify at build.

### Git intelligence

`b6238e8` (Story 2.4) is the baseline; it added the editor conflict banner + the `isConflictCopy` import into `editor_page.dart`. `lore/` currently holds `lore_loader`/`lore_model`/`lore_browse`/`project_config` (all pure) — `convention_matcher` is the next pure `lore/` inhabitant. No prior highlighting/toolbar code exists (the web POC's `highlight()` is unrelated search-highlighting).

### Library / version policy

**No new dependencies.** A hand-rolled regex matcher + a custom `TextEditingController` + Material buttons cover everything. Do **not** add a markdown or syntax-highlighting package — the whole point is *this project's* conventions, and a generic package can't do `(emotion):`/`[placeholder]`/em-dash conditionals (MOBILE §5.2). (A markdown *renderer* may come later for the FR10 preview — Story 2.7 — but that is rendering, not this editing surface.)

### Testing standards

- **Matcher → pure unit tests** in `test/lore/` (no widget): assert token kinds + ranges per convention, non-overlap/precedence, CRLF==LF, and no-throw on pathological input. Include Cyrillic examples.
- **Controller → widget/unit tests** in `test/app/`: the span-text-equals-input invariant, a couple of style assertions, and no-throw on malformed input.
- **Text-ops → pure unit tests** in `test/app/`: insert/wrap(with & without selection)/prefix, checking text AND resulting selection.
- **Editor → widget tests** in `test/app/`: toolbar actions mutate the buffer + dirty state; raw markup stays literal; save regression; toolbar visible in ready state.
- **Contract gate:** fixtures 4/4, `npm test` 4/4, `git status --porcelain lib/lore.js test/fixtures/ scripts/` empty. `convention_matcher` is Dart-only and outside the fixtures.

### Project Structure Notes

- New pure logic: `apps/mobile/lib/lore/convention_matcher.dart` (exported from `lore.dart`).
- New UI: `apps/mobile/lib/app/convention_highlighting_controller.dart`, `apps/mobile/lib/app/editor_toolbar.dart`; modified `apps/mobile/lib/app/editor_page.dart`.
- Tests: `apps/mobile/test/lore/convention_matcher_test.dart`; `apps/mobile/test/app/convention_highlighting_controller_test.dart`, `editor_toolbar_test.dart`, and additions to `editor_page_test.dart`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.5] — user story + ACs (FR8, FR9, matcher-factoring)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR8] (toolbar: structure + tokens via insert/wrap/prefix), #FR9 (convention-aware highlighting over the raw buffer), #NFR7 (malformed never crashes)
- [Source: MOBILE.md §5.1] (helper toolbar — two groups, one mechanism), §5.2 (custom `TextEditingController.buildTextSpan`; highlight *this project's* conventions; same matcher reused as the linter), §5 intro (raw markdown, styled but never hidden — ADR 8)
- [Source: ARCHITECTURE.md §3.3] — the exact prose conventions (dialogue `Name (emotion):`, `[placeholders]`, em-dash conditionals, `[[wikilinks]]`)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-7] (one convention matcher, many consumers), #AD-8 (total/never-throw), #AD-9 (per-slice purity)
- [Source: apps/mobile/lib/app/editor_page.dart] — the editor being extended (controller, save/dirty/pop, lossy + conflict banners) — preserve its behavior
- [Source: _bmad-output/project-context.md] — dialogue/monologue/placeholder conventions; non-ASCII (Cyrillic) is first-class; UTF-8 always
- [Source: _bmad-output/implementation-artifacts/2-4-surface-sync-conflict-copies.md] — prior story: the editor conflict banner + `isConflictCopy` reuse pattern (AD-7 in miniature)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- `flutter analyze` → **No issues found.**
- `flutter test` → **176 passing** (145 → +31): matcher unit tests, controller tests, text-op unit tests, and editor toolbar widget tests.
- **Contract gate (AC5)** → `npm test` 4/4; fixtures pass (part of `flutter test`); `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` is **empty** (contract + loader/model shape untouched — the matcher is additive). The only `lore/` changes are the new `convention_matcher.dart` + its barrel export.
- One test needed a fix during dev: the "multiple styled spans" controller test originally used bold *inside* a heading — but headings subsume inline tokens by design, so it's a single span; changed to a non-heading line.

### Completion Notes List

- **The AD-7 keystone is a pure `lore/` matcher.** `convention_matcher.dart` exposes `matchConventions(String) → List<ConventionToken>` over `ConventionKind` {heading, bold, italic, listMarker, wikilink, dialogueSpeaker, placeholder, emDash}. It is **line-oriented** (heading subsumes its line; other lines collect line-start + inline candidates), **precedence-resolved to non-overlapping** (wikilink beats placeholder so `[[x]]` isn't `[x]`; bold beats italic so `**x**` isn't `*x*`), **CRLF-safe** (a trailing `\r` never breaks a match), and **total** (wrapped so it never throws). No Flutter/`dart:io` — the linter (3.1) and error kinds (2.6) will consume/extend the same tokens.
- **The highlighter is display-only over the raw buffer.** `ConventionHighlightingController extends TextEditingController` overrides `buildTextSpan`: it maps each kind → `TextStyle` (from the theme) and builds a flat span list. **Invariant, tested:** the concatenation of all spans' text equals the buffer exactly — highlighting never drops, adds, reorders, or hides a character (that's what keeps the buffer raw markdown). Defensive per-token range checks + a `try/catch → plain span` make it total (AD-8). This is *why* the pre-existing "loads raw content untransformed" editor test still passes with the new controller.
- **The helper toolbar is pure ops + a widget.** `editor_toolbar.dart` has unit-testable `insertAtCursor`/`wrapSelection`/`prefixLines` over `TextEditingValue` (with correct caret/selection), and an `EditorToolbar` row (H1/H2/H3, bullet/numbered, bold, italic | `[[`, `[`, `]`, `—`, `(emotion):`). `[[` and bold/italic use `wrapSelection` (empty selection → pair with caret between; a selection → wrapped). Actions go through `controller.value` so the existing `_onChanged` marks the buffer dirty.
- **Editor integration preserved everything.** Only two changes to `editor_page.dart`: the controller type became `ConventionHighlightingController`, and `EditorToolbar` was added below the `TextField`. Load, dirty, explicit save, save-on-background, save-on-pop, the lossy-UTF-8 guard, and the Story 2.4 conflict banner are all intact (existing editor tests still green).
- **No new dependencies** — deliberately no markdown/syntax-highlighting package; the point is *this project's* conventions (`(emotion):`, `[placeholder]`, em-dash), which a generic package can't do.
- **Known v0.1 limitations (documented, not defects):** the dialogue-speaker regex is heuristic (a `Word:` line can match — acceptable for highlighting; the linter will tune it); inline tokens inside a heading line are not separately styled (the heading is "larger" as a whole); the IME composing underline (`withComposing`) is not drawn (never at the cost of the text-equals-input invariant); toolbar taps may dismiss the soft keyboard (a focus-retention polish, out of scope). Error/invalid-markup styling is Story 2.6.

### File List

**Added:**
- `apps/mobile/lib/lore/convention_matcher.dart` (pure AD-7 matcher: `ConventionKind`, `ConventionToken`, `matchConventions`)
- `apps/mobile/lib/app/convention_highlighting_controller.dart` (`TextEditingController.buildTextSpan` override; kind→style; total)
- `apps/mobile/lib/app/editor_toolbar.dart` (pure `insertAtCursor`/`wrapSelection`/`prefixLines` + the `EditorToolbar` widget)
- `apps/mobile/test/lore/convention_matcher_test.dart`
- `apps/mobile/test/app/convention_highlighting_controller_test.dart`
- `apps/mobile/test/app/editor_toolbar_test.dart`

**Modified:**
- `apps/mobile/lib/lore/lore.dart` (export `convention_matcher.dart`)
- `apps/mobile/lib/app/editor_page.dart` (use `ConventionHighlightingController`; add `EditorToolbar` below the field)
- `apps/mobile/test/app/editor_page_test.dart` (helper-toolbar group: visible, bold/H2/`[[` actions, toolbar-edit-then-save)

**Deliberately NOT modified (verified git-clean):** `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`, `apps/mobile/lib/lore/lore_loader.dart`, `apps/mobile/lib/lore/lore_model.dart` (the matcher is additive; no model/contract change — AC5).

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-26 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers): 7 patch findings fixed. **Keyboard-focus (High):** the toolbar is now wrapped in a non-focusable `Focus` so buttons don't steal focus and dismiss the soft keyboard the toolbar sits above. **`prefixLines` (High):** fixed the boundary off-by-one (a selection ending exactly at a `\n` no longer prefixes the next line) and the offset-0 / leading-`\n` no-op-with-inverted-selection bug. **Total ops (Med):** `_sel` now clamps offsets to text length so a stale out-of-range selection can't throw `RangeError`. **Highlight fidelity:** a line-start `[[wikilink]]` in a dialogue-shaped line keeps its highlight (excluded `[` from the dialogue leading char); heading token trims a trailing CRLF `\r`. **Perf:** by-text memo so `buildTextSpan` reuses tokens on non-text rebuilds. **Test accuracy:** corrected an overclaiming comment. +4 tests (prefix boundaries, out-of-range clamp, dialogue-wikilink). Tests 176 → 180; `flutter analyze` clean; fixtures 4/4; `npm test` 4/4; contract+loader/model git-clean. 4 findings deferred (IME composing underline; dialogue-after-stray-colon; per-keystroke full-doc match on long scenes; lone `\r`); 2 dismissed (clearing composing after a text edit is correct; selection-direction normalization is fine). Blind Hunter confirmed no ReDoS. |
| 2026-07-24 | Implemented Story 2.5: helper toolbar + convention-aware highlighting. Added the pure `lore/convention_matcher.dart` (AD-7 keystone — `matchConventions` over 8 convention kinds; line-oriented, precedence-resolved non-overlapping, CRLF-safe, never-throws; reused by the 3.1 linter and extended by 2.6). Added `ConventionHighlightingController` (`buildTextSpan` styles tokens over the raw buffer; invariant: span text == buffer exactly; total via try/catch). Added `EditorToolbar` with pure insert/wrap/prefix ops (H1–H3/list/bold/italic + `[[`/`[`/`]`/`—`/`(emotion):`). Wired both into `EditorPage` (controller swap + toolbar), preserving save/dirty/pop/lossy/conflict-banner. No new dependencies; no loader/model/contract change (fixtures 4/4, npm 4/4, git-clean). Tests 145 → 176 (+31); analyze clean. |
