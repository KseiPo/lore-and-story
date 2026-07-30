---
baseline_commit: ccd7ed5
---

# Story 2.7: Preview rendered markdown

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want a read-only preview that renders my markdown — including this project's conventions —
so that I can check how a card or scene reads without leaving the editor.

## Scope note (author decisions, 2026-07-26)

The epic's FR10 is minimally "a toggle that renders the buffer." KseiPo chose one enrichment beyond that for this story:

- **Project conventions are styled in preview** (not shown as raw text) — reusing the existing `convention_matcher` (AD-7), so `[[wikilinks]]`, `Name (emotion):`, `[placeholders]`, em-dash markers, and the Story 2.6 error kinds read the same way they do in the editor.

**Local image loading was split out** into its own follow-up story (**2.16 — Render local repo images in the preview**) because it reaches into the `storage/` slice (the `RepoStorage` port has only a UTF-8 `read`, not a bytes read). For this story, `![alt](src)` images render as their **alt text / a placeholder**; Story 2.16 swaps in real loading by extending the same `MarkdownPreview` widget. Keeping them separate makes 2.7 a clean, single-slice first cut.

## Acceptance Criteria

1. **AC1 (FR10 — read-only preview is the default surface, toggle to edit):** Given I open a file, when the editor loads (ready state), then it shows a **read-only, scrollable rendered view of the current in-memory buffer** (including unsaved edits) **by default**; an AppBar toggle switches to the raw-markdown editing surface (`TextField` + toolbar) and back. Preview is **display-only** — it never mutates the buffer, and it is **not** an editing mode (no WYSIWYG-in-place; the raw editor is a distinct mode you toggle into, consistent with MOBILE §5's "never hide markup *while editing*"). *(Author decision: land in the reading view; opt into editing.)*
2. **AC2 (standard markdown rendering):** Given buffer text, when preview renders, then standard markdown renders correctly — headings (H1–H6), `**bold**`/`_italic_`, ordered/unordered lists (including nesting), blockquotes, inline code and fenced code blocks, thematic breaks (`---`), hard line breaks, and `[text](url)` links **as styled (non-tappable, v0.1) text** — via the **dart-lang `markdown` parser** + a custom widget builder in `app/`. An `![alt](src)` image renders as its **alt text / a small placeholder** in this story (real local-image loading is Story 2.16). Rendering is read-only and scrolls independently.
3. **AC3 (project conventions styled — AD-7 reuse):** Given rendered text runs, when they contain this project's conventions, then `[[wikilinks]]`, `Name (emotion):` dialogue prefixes, `[placeholders]`, em-dash conditional markers, **and the Story 2.6 error kinds** (leaked twee/HTML, scene passage-links, unterminated `[[`) are **styled by reusing `convention_matcher`** — no second recognition implementation — and rendered with the **same convention style map as the editor** (extracted to a shared helper so editor and preview never drift). Markdown-structural kinds that markdown already renders (heading/bold/italic/list marker) are **not** re-applied by the matcher in preview (markdown owns them); the matcher styles only the conventions markdown leaves as literal text.
4. **AC4 (total — never crash — AD-8/NFR7):** Given malformed markdown, malformed/leaked markup, or a lossy-UTF-8 buffer, when I toggle preview, then rendering **never throws** — it degrades to best-effort/plain text; the preview opens, and toggling back to the editor leaves the buffer intact and still saveable. A parser failure yields a plain-text rendering of the raw buffer rather than an error screen.
5. **AC5 (reusable renderer for Stories 2.13 & 2.16):** Given the renderer, when it is built, then it is a **standalone `MarkdownPreview` widget** (input: the markdown `text`; output: a read-only rendered widget) — **not** inlined into `EditorPage`. Story 2.13 (card preview on the detail screen) must be able to drop it in unchanged, and Story 2.16 must be able to **extend it** (adding `storage`/`filePath` for image loading) without restructuring it. Keep its API minimal and its coupling to the editor zero.
6. **AC6 (hygiene; gates):** `flutter analyze` clean; `flutter test` green with new tests (toggle, markdown rendering, convention styling, malformed/lossy input). The **only** new dependency is `markdown` (the pure-Dart parser) — no `flutter_markdown` (discontinued). **No loader/model/contract change** (fixtures 4/4, `npm test` 4/4). Existing editor behavior — load, dirty, save, save-on-background/pop, lossy guard + banner, conflict banner (2.4), toolbar (2.5), convention highlighting (2.5/2.6) — is preserved.

## Tasks / Subtasks

- [x] **Task 1 — Markdown → widget renderer (`MarkdownPreview`) (AC: 2, 4, 5)**
  - [x] `flutter pub add markdown` (the dart-lang parser; pure Dart, no native). Do **not** add `flutter_markdown` (discontinued upstream) or a fork — we render the AST ourselves so we can reuse `convention_matcher` (AD-7) now and load images via the port later (Story 2.16).
  - [x] Add `apps/mobile/lib/app/markdown_preview.dart` — `class MarkdownPreview extends StatelessWidget`. **Constructor input:** `required String text`. No dependency on `EditorPage` (AC5). (Story 2.16 will add `storage`/`filePath` params for images — keep the widget structured so that's an additive change.)
  - [x] Parse with `md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)` → `parseLines(text.split('\n'))` (or `.parse(text)`), yielding `List<md.Node>`. Walk the AST to Flutter widgets: **block** nodes (`h1`–`h6`, `p`, `ul`/`ol`/`li` incl. nesting, `blockquote`, `pre`/`code` fenced, `hr`) → a column of block widgets; **inline** nodes (`text`, `em`, `strong`, `code`, `a`, `img`, `br`) → a `RichText`/`Text.rich` with the corresponding `TextStyle`s from `Theme.of(context).textTheme`. Read-only; wrap in a scroll view. Links render as styled text (colored), **not** tappable in v0.1 (navigation is Story 3.2 / FR19). An `img` node renders its **alt text** (or a small placeholder) — no file loading in this story.
  - [x] **Total (AC4):** wrap the parse+build in `try/catch`; on ANY failure return a plain `SelectableText`/`Text(text)` of the raw buffer (never an exception, never an error screen). Malformed markdown is content to show best-effort, not a fault.
- [x] **Task 2 — Convention styling in preview, reusing the matcher (AC: 3)**
  - [x] Extract the editor's `ConventionKind → TextStyle` mapping into a **shared** helper so editor and preview render conventions identically. Add `apps/mobile/lib/app/convention_styles.dart` with `TextStyle styleForConvention(ConventionKind kind, ColorScheme scheme, TextStyle base)` (move the body of `ConventionHighlightingController._styleFor` here) and refactor the controller to delegate to it. Pure mapping, no matching (AD-7).
  - [x] Also factor the **span-building** both consumers share: a helper `List<InlineSpan> buildConventionSpans(String text, {required TextStyle? base, required Set<ConventionKind> apply, required TextStyle Function(ConventionKind) styleFor})` that runs `matchConventions(text)`, keeps only tokens whose kind is in `apply`, and splits `text` into plain + styled runs (the same defensive, total, span-text-equals-input logic already in `buildTextSpan`). The controller uses it with **all** kinds; the preview uses it with **only the convention + error kinds** (exclude `heading`/`bold`/`italic`/`listMarker` — markdown renders those). This keeps the flattened-text-equals-input invariant in one place.
  - [x] In the renderer, when emitting a `md.Text` run, build its span via `buildConventionSpans(runText, apply: {wikilink, dialogueSpeaker, placeholder, emDash, leakedTwee, leakedHtml, scenePassageLink, malformedMarkup}, …)`. So markdown owns block/emphasis structure; the matcher owns the project conventions markdown leaves as literal text. (Heuristic caveat: `dialogueSpeaker` is line-anchored; on a text run that isn't a whole line it may not fire — acceptable for v0.1, note it.)
- [x] **Task 3 — Wire the toggle into `EditorPage` (AC: 1, 4, 6)**
  - [x] Add a preview toggle to the editor: an AppBar `IconButton` (`Icons.visibility_outlined` when editing ↔ `Icons.edit_outlined` when previewing) that flips a `bool _previewing` in `_EditorPageState`. **`_previewing` defaults to `true`** — the editor opens in the reading view (AC1). In the ready state, when `_previewing`, render `MarkdownPreview(text: _controller.text)` **in place of** the `Expanded(TextField)` + `EditorToolbar`; otherwise render the raw editor. **Preserve everything else:** the conflict banner (2.4), lossy banner, dirty indicator, Save action, save-on-background/pop, lossy guard. Save remains available from preview (the buffer is unchanged; you can still save your edits). The toolbar is shown only in the editing surface (nothing to insert into a read-only view).
  - [x] Preview shows the **current buffer** (`_controller.text`), so unsaved edits are visible (AC1). Toggling is pure UI state — no re-read, no write, no new async.
  - [x] Only offer preview in the **ready** state (not loading/error). Previewing a lossy-loaded file is fine (read-only render of the best-effort text); saving stays disabled by the existing lossy guard.
- [x] **Task 4 — Tests (AC: 1–6)**
  - [x] **Renderer widget tests** (`test/app/markdown_preview_test.dart`): headings/bold/italic/lists/blockquote/code/`---`/link-as-text render (assert structure in the widget tree, e.g. a bold run has `FontWeight.bold`, a fenced block renders monospace); an `![alt](x.png)` shows its alt text/placeholder (no load); a `[[wikilink]]`/`(emotion):`/`[placeholder]`/em-dash run carries the **convention** style (same as the shared map); a leaked-twee/`[[a->b]]` run carries the **error** style; **malformed markdown never throws** and still shows the text (AD-8). Include a Cyrillic sample.
  - [x] **Editor toggle widget tests** (`test/app/editor_page_test.dart`): the editor opens in preview (`MarkdownPreview` shown, `TextField`+`EditorToolbar` hidden); tapping the edit toggle shows the raw editor; tapping preview returns to the rendered view; **toggling does not change `_controller.text`** (edit → preview → back → text unchanged, still dirty); Save still works from preview; a lossy file opens in preview with Save disabled; the conflict banner still shows. **Because preview is now the default surface, editor/navigation tests that need the `TextField` first switch to edit mode** — via a shared `enterEditMode` helper (`test/app/editor_test_helpers.dart`); the `pumpEditor` helper enters edit mode by default. Regression: all existing editor/browse/detail/conflicts/widget tests stay green.
  - [x] **Shared-style regression**: a test that the extracted `styleForConvention` returns the same styles the controller used to (so the refactor didn't change editor highlighting); the existing controller tests must stay green.
  - [x] Contract gate: `flutter analyze` clean; `flutter test` green; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` **empty**.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). The Auditor independently reproduced every gate (analyze clean, 221/221, `npm test` 4/4, contract git-clean, single new dep) and found no functional defect in the ACs. Blind + Edge converged on one **High** — convention styling misfires on fragmented paragraphs — plus GFM-rendering gaps and small hygiene items.

**Patch:**

- [x] [Review][Patch] **High — convention styling misfires on fragmented paragraphs (false positives).** `MarkdownPreview._conventionSpans` runs the line-oriented `matchConventions` on **each AST text-node fragment** separately, so when markdown splits a line around inline emphasis/code/link, the `^`-anchored rules re-anchor mid-line. Two visible, easy-to-hit wrongs: (a) **false dialogue-speaker** styling on ordinary prose — `See **bold** intro: this.` colors ` intro:` as a speaker; (b) **false "invalid markup" red squiggle on a valid wikilink** — `[[Se*le*na]]` splits so the `[[Se` fragment fires `malformedMarkup` (unterminated `[[`) on properly-closed content. Fix: drop `malformedMarkup` from `previewConventionKinds` (an unterminated-`[[` signal is authoring-time, unreliable per-fragment, and its false positive is alarming), and apply `dialogueSpeaker` **only to a block's first inline text run** (preserves AC3's dialogue styling for the normal whole-line case, kills the mid-line false positives). [apps/mobile/lib/app/markdown_preview.dart _conventionSpans / convention_styles.dart previewConventionKinds] (blind+edge)
- [x] [Review][Patch] **Med — GFM tables render as glued, unseparated text.** `gitHubFlavored` enables tables, but `_block` has no `table`/`thead`/`tbody`/`tr`/`th`/`td` case → the `default` paragraph fallback recurses through cells with no separator (`| Name | Age |…` → `NameAge…`). Add minimal readable table rendering (rows on their own lines, cells separated). [apps/mobile/lib/app/markdown_preview.dart _block] (blind+edge)
- [x] [Review][Patch] **Med — GFM task-list checkboxes vanish.** `- [ ] todo` / `- [x] done` emit an `input[type=checkbox]` element `_inline` has no case for → the `default` recurses into its (empty) children → nothing renders, no glyph, no text. Handle `input` → render ☐/☑ from the `checked` attribute. [apps/mobile/lib/app/markdown_preview.dart _inline] (blind)
- [x] [Review][Patch] **Low-Med — a non-inline block nested in a list item is misclassified as inline; a nested `hr` disappears.** `_list` routes only `ul/ol/p/blockquote/pre` children to blocks; a nested heading falls to `_inline` (loses heading style) and a nested `hr` (no children) produces **no span at all** — the divider silently vanishes. Classify by a known-**inline** set instead (text/em/strong/code/a/img/br/del/input → inline; everything else → block). [apps/mobile/lib/app/markdown_preview.dart _list] (edge)
- [x] [Review][Patch] **Low-Med — ordered lists ignore the `start` attribute.** `_list` hardcodes `index = 1`, so `5. five\n6. six` renders `1. / 2.`. Read `list.attributes['start']`. [apps/mobile/lib/app/markdown_preview.dart _list] (blind)
- [x] [Review][Patch] **Low — hygiene trio.** `_heading`'s `(style ?? textTheme.titleLarge)!` force-unwrap can degrade the whole preview to plain text if both are null (give a non-null fallback); the `MarkdownPreview` doc references a removed `[buildInlineSpans]` symbol (fix to `_inline`); the module-level `_allKinds` set is mutable (`Set.unmodifiable`). [apps/mobile/lib/app/markdown_preview.dart / convention_highlighting_controller.dart] (blind)
- [x] [Review][Patch] **Coverage — preview convention styling under-tested.** Only `wikilink` + 2 of 4 error kinds are integration-tested through `MarkdownPreview`; `placeholder`, `emDash`, `leakedHtml`, and `dialogueSpeaker` (the last with the fragmentation caveat) are not, nor are hard line breaks / inline code. Add widget-level tests for those, plus regressions for the fixes above (valid `[[Se*le*na]]` not error-flagged; no false speaker after inline markup; table/task-list/ordered-start; nested `hr`). [apps/mobile/test/app/markdown_preview_test.dart] (auditor)

**Deferred:**

- [x] [Review][Defer] **A convention marker split across inline emphasis loses its highlight (false negative).** `**Frank**: hi` shows no dialogue styling; `[secret **loot**]` shows no placeholder. Benign — a *missed* highlight, never wrong styling or dropped text (the char-equals-input invariant holds). The correct fix is to match over a block's whole concatenated inline text and distribute tokens across fragments — a larger refactor deferred past v0.1. [apps/mobile/lib/app/markdown_preview.dart] (blind+edge)
- [x] [Review][Defer] **No memoization on `MarkdownPreview`.** It reparses the full document on every parent rebuild, unlike the controller's by-text memo. Not a measured problem for a read-only preview (no keystrokes reach it), but inconsistent with the codebase's own pattern; revisit if a large card previews sluggishly. [apps/mobile/lib/app/markdown_preview.dart] (blind)

**Dismissed:** none — every finding was a real, if small, issue.

## Dev Notes

### What this story is — a read-only render mode that stays faithful to *this* project

The editor (Stories 1.4/2.4/2.5/2.6) shows **raw markdown** — the markup *is* the content being proofread. FR10 adds the complementary view: a **read-only rendered preview** to see how a card/scene reads. **Per the author's decision, the preview is the surface you land on when opening a file; a toggle switches to the raw editor.** The preview is not a generic markdown viewer — it **reuses `convention_matcher`** to style this project's conventions. Three deliverables:

1. **`MarkdownPreview`** (`app/`) — a standalone widget: parse markdown (dart-lang `markdown`), walk the AST to read-only widgets, style project conventions via the shared matcher. Standalone so **Story 2.13** (card preview on the detail screen) reuses it and **Story 2.16** extends it (images) — both without restructuring (AC5).
2. **Shared convention styling** (`app/convention_styles.dart`) — `styleForConvention` + `buildConventionSpans`, extracted from the controller so editor and preview render conventions identically.
3. **The editor toggle** — swap the `TextField`/toolbar for `MarkdownPreview`, preserving all editor machinery.

Images render as alt text here; **Story 2.16** adds real loading (it needs a `RepoStorage.readBytes` the port lacks today).

### Why `markdown` (parser) + a custom builder — not `flutter_markdown`

- `flutter_markdown` is **discontinued upstream**; a community fork would be a heavier, less-official dependency.
- Turnkey renderers treat `[[wikilink]]`/`(emotion):` as literal text unless you register custom syntaxes — that would be a **second** convention recognizer, violating **AD-7** (one matcher, many consumers). We already have `convention_matcher`, reused by the editor highlighter (2.5) and the 3.1 linter.
- Owning the AST walk lets us (a) run **the same matcher** over rendered text runs for identical convention styling, and (b) later load images through the **`RepoStorage` port** (Story 2.16, offline — no network image fetch). The mature **`markdown` parser** (pure Dart, maintained) handles the standard-markdown 90%; our walker is a bounded amount of code. This is the strongest fit for a project whose whole ethos is one-shared-core + thin, port-friendly shells.

### The AD-7 reuse — markdown owns structure, the matcher owns conventions

Markdown parsing consumes `**bold**`, `# heading`, list markers, etc. — those render as real structure with the markup gone. The project conventions markdown **doesn't** recognize (`[[wikilinks]]`, `Name (emotion):`, `[placeholders]`, em-dash, and the 2.6 error kinds) survive into **text nodes**. So: build each text node's span with `buildConventionSpans(runText, apply: {conventions + error kinds})`, reusing the matcher and the shared `styleForConvention` map. Editor and preview then render conventions **identically** because they share both the recognizer and the style map. Filter **out** `heading/bold/italic/listMarker` in preview — markdown already rendered those; re-applying would double-style. (Note the `dialogueSpeaker` line-anchor caveat on non-line text runs — acceptable v0.1 heuristic, the 3.1 linter refines the matcher.)

### Total safety (AD-8 / NFR7) — the preview must never crash

- Wrap parse+build in `try/catch` → fall back to a plain `Text(rawBuffer)`. A malformed document renders best-effort, never an error screen.
- A **lossy-UTF-8** file (U+FFFD present) can still be previewed (read-only render of the best-effort text); Save stays disabled by the existing lossy guard.
- Toggling preview is pure UI state — it never mutates or re-reads the buffer and adds **no new async** ([[ad8-call-site]]), so the file still opens/edits/saves exactly as before. (Image loading — the only new I/O — arrives in Story 2.16, error-bounded inside a `FutureBuilder`.)

### Files being ADDED / MODIFIED (read before editing)

- **`apps/mobile/lib/app/markdown_preview.dart`** (NEW) — the `MarkdownPreview` widget (parser walk + convention styling). Standalone; constructor takes `text` only (Story 2.16 adds `storage`/`filePath`).
- **`apps/mobile/lib/app/convention_styles.dart`** (NEW) — shared `styleForConvention` + `buildConventionSpans`, extracted from the controller so editor and preview share them.
- **`apps/mobile/lib/app/convention_highlighting_controller.dart`** (MODIFY) — delegate `_styleFor`/span-building to `convention_styles.dart` (behavior unchanged — the existing controller tests are the guard).
- **`apps/mobile/lib/app/editor_page.dart`** (MODIFY) — add the `_previewing` toggle (defaults `true` → opens in preview) + AppBar action; in the ready body, swap `TextField`+`EditorToolbar` for `MarkdownPreview` when previewing. **Preserve** every existing behavior (banners, dirty, save, background/pop, lossy). Current state (from Story 2.6): ready body is a `Column` with the conflict banner, lossy banner, `Expanded(TextField(controller: _controller))`, then `EditorToolbar(controller: _controller)`; AppBar has the path + dirty indicator + Save action.
- **`apps/mobile/pubspec.yaml`** (MODIFY) — add `markdown:` (parser only).

**Not touched in this story** (Story 2.16 will): `apps/mobile/lib/storage/repo_storage.dart`, `all_files_repo_storage.dart`, `test/fakes.dart` — no `readBytes` here.

### Architecture guardrails

- **AD-7 — one matcher, many consumers.** Preview convention recognition **is** `convention_matcher`; preview convention styling **is** the shared `styleForConvention`. No second implementation. [ARCHITECTURE-SPINE.md#AD-7]
- **AD-8 / NFR7 — total.** Parse and render never throw; malformed input degrades to best-effort text; the file still opens/edits/saves. [#AD-8]
- **AD-2 — contract untouched.** No loader/model/fixtures change; `markdown` (parser) is the one new dep, in the UI layer only (like `permission_handler`/`shared_preferences`). Fixtures 4/4, `npm test` 4/4. [#AD-2]
- **Raw-vs-rendered (MOBILE §5).** The rule "never hide markup" governs the **editing** surface; a **separate read-only preview mode** (FR10) is explicitly allowed — the markup isn't hidden *while editing*, it's rendered in a distinct mode you opt into. [MOBILE §5 / PRD FR10]
- **AD-9 purity boundary.** The matcher stays pure `lore/`; the style map + span builder are Flutter (`TextStyle`/`ColorScheme`) so they live in `app/`, not `lore/`. [#AD-9]

### Previous story intelligence

- **2.5/2.6 (done):** `convention_matcher` (pure `lore/`) exposes `matchConventions(String) → List<ConventionToken>` over valid kinds **and** the 2.6 error kinds, plus `errorKinds`/`isError`. `ConventionHighlightingController.buildTextSpan` already builds total, defensive, span-text-equals-input spans — factor that logic into the shared `buildConventionSpans` so preview reuses it verbatim.
- **2.4 (done):** the editor renders a conflict banner via the exported `isConflictCopy`; keep it when adding the toggle.
- **Cross-model review ([[cross-model-code-review]])** finds a real issue every story — expect probing on: preview mutating the buffer (it must not), the shared-style refactor silently changing editor highlighting, and totality on malformed markdown. Cover these in tests up front.
- **Toolchain:** Flutter `C:\programs\flutter\bin` (not on PATH — prefix it); `flutter analyze` + `flutter test`; `npm test` for the JS cross-check.

### Git intelligence

Baseline `ccd7ed5` (Story 2.6 merged to main). The `app/` slice holds the editor/browse/preview UI. No markdown-render code exists yet. Branch per story, ff-merge to main, never push, model `Co-Authored-By` trailer ([[git-story-workflow]]).

### Library / version policy

**One new dependency: `markdown`** (dart-lang, pure-Dart parser) — pin the current stable at `pub add`. **Do not** add `flutter_markdown` (discontinued) or a community fork. No other deps: convention styling is the existing matcher + Flutter `TextStyle`. Rationale: the preview is UI (a dependency is acceptable, unlike the zero-dep core), but owning the AST walk is what lets us honor AD-7 and (in 2.16) load images offline through the port.

### Testing standards

- **Renderer → widget tests** (`test/app/markdown_preview_test.dart`): block + inline rendering; image-as-alt-text; convention/error styling on text runs; malformed-markdown no-throw; Cyrillic.
- **Editor → widget tests** (`editor_page_test.dart`): toggle shows/hides preview; buffer unchanged across toggle; save works from preview; lossy previewable + save disabled; conflict banner intact; no regressions.
- **Refactor guard**: shared `styleForConvention` equals the prior controller styles; existing controller/matcher tests stay green.
- **Contract gate:** fixtures 4/4, `npm test` 4/4, loader/model git-clean. `markdown` is UI-layer; the contract is untouched.

### Project Structure Notes

- New UI: `apps/mobile/lib/app/markdown_preview.dart`, `apps/mobile/lib/app/convention_styles.dart`.
- Modified UI: `apps/mobile/lib/app/convention_highlighting_controller.dart` (delegate to shared styles), `apps/mobile/lib/app/editor_page.dart` (toggle).
- Tests: `apps/mobile/test/app/markdown_preview_test.dart` (new); additions to `editor_page_test.dart`, `convention_highlighting_controller_test.dart`.
- Variance from the spine's "`lore/` owns preview UI": UI lives in `app/` in this codebase (the documented, established split since 2.2). `MarkdownPreview` joins the other `app/` widgets.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.7] — user story + AC (FR10 read-only preview toggle)
- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.13] — the card-preview-on-detail story that **reuses this renderer** ("same markdown renderer introduced in Story 2.7"); drives AC5 (standalone widget)
- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.16] — the split-out image-loading follow-up that **extends this renderer**
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR10] (read-only preview toggle rendering the buffer, not an editing mode), #NFR7 (malformed never crashes)
- [Source: MOBILE.md §5] — raw markup is a rule for the **editing** surface; a read-only preview mode is explicitly the allowed complement (styles without hiding *while editing*); §5.2 (the same matcher is reused across surfaces)
- [Source: ARCHITECTURE.md §3.3] — the conventions to style (`[[wikilinks]]`, dialogue `Name (emotion):`, `[placeholders]`, em-dash)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-7] (one matcher, many consumers), #AD-8 (total/never-throw), #AD-9 (per-slice purity), #AD-2 (contract untouched)
- [Source: apps/mobile/lib/app/editor_page.dart] — the editor the toggle is added to (preserve banners/dirty/save/pop/lossy)
- [Source: apps/mobile/lib/lore/convention_matcher.dart] — the matcher reused for convention styling (valid + 2.6 error kinds; `errorKinds`/`isError`)
- [Source: apps/mobile/lib/app/convention_highlighting_controller.dart] — the `_styleFor` map + total span-building to extract into shared `convention_styles.dart`
- [Source: _bmad-output/implementation-artifacts/2-6-flag-invalid-markup-without-crashing.md] — the 2.6 error kinds now also styled in preview; the total/never-throw discipline to carry forward
- [Source: _bmad-output/project-context.md] — conventions; non-ASCII (Cyrillic) first-class; UTF-8

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- Baseline before work: `flutter test` 197 passing, analyze clean.
- **Parser config probe (decisive):** before writing the renderer, empirically confirmed that `md.Document(extensionSet: gitHubFlavored, encodeHtml: false)` keeps raw text verbatim in `md.Text` nodes — `<<if $x>>`, `<b>bold</b>`, `[[Selena]]`, `[[a->b]]`, and Cyrillic all survive as literal text (NOT parsed into HTML elements, NOT escaped to `&lt;` entities). This is what lets the convention matcher flag them and keeps `&lt;`-style entities off-screen. `encodeHtml: true` (the default) would have broken both.
- `flutter analyze` → **No issues found.**
- `flutter test` → **221 passing** (197 → +24: 14 renderer/convention preview tests, 4 editor-toggle tests, 6 shared-style/`buildConventionSpans` tests).
- **Contract gate (AC6):** `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` **empty** — the matcher was **reused, not modified**; no loader/model/contract change.
- One new dependency: `markdown 7.3.1` (pure-Dart parser; `args` transitive). No `flutter_markdown`.

### Completion Notes List

- **`MarkdownPreview` (`app/markdown_preview.dart`) is a standalone renderer.** Constructor takes only `text` (AC5) — the editor toggle uses it now, Story 2.13 drops it onto the detail screen unchanged, and Story 2.16 extends it (adds `storage`/`filePath`) for images without restructuring. It parses with the dart-lang `markdown` parser (`encodeHtml: false`, gitHubFlavored) and walks the AST to read-only widgets: headings (themed sizes), paragraphs, nested ul/ol, blockquotes (left border), fenced/indented code (monospace, tinted), `hr`, inline `strong`/`em`/`del`/`code`/`a` (links styled, non-tappable — FR19 is Story 3.2). Images render as **alt text + an icon** placeholder (real loading is Story 2.16). Scrollable.
- **Total (AD-8/NFR7).** The whole parse+build is wrapped so a malformed document falls back to a plain `SelectableText` of the raw buffer — never an error screen. Verified with adversarial markdown (`# [[unclosed **bold ```…<<if $x >> ]]] [](`), empty buffer, and lossy-UTF-8 (previewable, Save stays disabled by the existing lossy guard).
- **AD-7 reuse — markdown owns structure, the matcher owns conventions.** Extracted the editor's kind→style map into shared `app/convention_styles.dart` (`styleForConvention` + `buildConventionSpans` + `previewConventionKinds`) and refactored `ConventionHighlightingController` to delegate to them (its existing tests are the behavior guard — all still green). When the renderer emits a `md.Text` run it styles the conventions markdown leaves as literal text (`[[wikilinks]]`, `(emotion):`, `[placeholders]`, em-dash, and the 2.6 error kinds) via the **same** matcher + style map as the editor — so a `[[a->b]]` gets the wavy error squiggle in preview exactly as in the editor, and a plain `[[Selena]]` does not. Markdown-structural kinds (heading/bold/italic/listMarker) are filtered out — markdown already rendered those.
- **Editor toggle (`editor_page.dart`) — preview-first.** `_previewing` **defaults to `true`**, so opening a file lands on the read-only reading view (author decision). An AppBar `IconButton` (visibility when editing ↔ edit when previewing, ready-state only) flips it; the ready body swaps the `TextField`+`EditorToolbar` for `Expanded(MarkdownPreview(text: _controller.text))`. Previewing is **pure UI state** — no re-read, no write, no new async — so the buffer, dirty indicator, Save, save-on-background/pop, lossy guard/banner, and the Story 2.4 conflict banner all keep working (verified: edit → preview → back keeps the exact dirty buffer; Save works from preview; a lossy file opens in preview with Save disabled).
- **Test alignment for preview-first.** Because the editor no longer opens on the `TextField`, tests that navigate into or edit the editor now switch to edit mode first via a shared `enterEditMode` helper (`test/app/editor_test_helpers.dart`); `pumpEditor` in the editor test enters edit mode by default (`edit: false` opts out for the toggle tests). Touched `browse_test.dart`, `conflicts_page_test.dart`, `entity_detail_page_test.dart`, and `widget_test.dart` — assertions unchanged, only the edit-mode switch added. Full suite green (221) with no weakened checks.
- **No `storage/` touch, no `lore/` change.** Image loading (the only `storage/` reach) is deferred to Story 2.16 by design — this is a clean single-slice cut. One UI dependency added; the ported contract is untouched.

### File List

**Added:**
- `apps/mobile/lib/app/markdown_preview.dart` (the `MarkdownPreview` widget: `markdown`-parser AST walk → read-only widgets; convention styling; image-as-alt-text)
- `apps/mobile/lib/app/convention_styles.dart` (shared `styleForConvention` + `buildConventionSpans` + `previewConventionKinds`, extracted from the controller)
- `apps/mobile/test/app/markdown_preview_test.dart`
- `apps/mobile/test/app/convention_styles_test.dart`
- `apps/mobile/test/app/editor_test_helpers.dart` (shared `enterEditMode` — editor opens preview-first, so tests needing the raw editor switch to it)

**Modified:**
- `apps/mobile/lib/app/convention_highlighting_controller.dart` (delegate `_styleFor`/span-building to `convention_styles.dart` — behavior unchanged)
- `apps/mobile/lib/app/editor_page.dart` (preview toggle: `_previewing` defaults `true` → preview-first + AppBar action + body swap)
- `apps/mobile/test/app/editor_page_test.dart` (preview-toggle widget tests; `pumpEditor` enters edit mode by default)
- `apps/mobile/test/app/browse_test.dart`, `apps/mobile/test/app/conflicts_page_test.dart`, `apps/mobile/test/app/entity_detail_page_test.dart`, `apps/mobile/test/widget_test.dart` (add `enterEditMode` after opening the editor — assertions otherwise unchanged)
- `apps/mobile/pubspec.yaml` / `pubspec.lock` (add `markdown`)

**Deliberately NOT modified (verified git-clean):** `apps/mobile/lib/lore/**` (matcher reused, not changed), `apps/mobile/lib/storage/**` (no `readBytes` — Story 2.16), `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-26 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers), 7 patches. **High (P1) — convention styling misfired on fragmented paragraphs:** the per-fragment matcher re-anchored line rules, so `See **bold** intro:` falsely styled `intro:` as a speaker and `[[Se*le*na]]` falsely got a red "invalid markup" error. Fixed: dropped `malformedMarkup` from preview kinds, and gate `dialogueSpeaker` to a block's first inline run (`atLineStart`) — whole-line dialogue still styles. **P2–P5 (GFM):** added table rendering (real `Table`, no more glued cells), task-list checkbox glyphs (☐/☑, were vanishing), nested-block-in-list classification by inline-tag set (a nested `hr` no longer disappears), and honoring the ordered-list `start` attribute. **P6:** `_heading` non-null fallback; fixed a stale doc reference; `_allKinds` now `Set.unmodifiable`. **P7:** +11 preview tests covering placeholder/em-dash/leakedHtml/dialogue and regressions for every fix. `matchConventions`/matcher **reused, not modified** (lore/ + contract git-clean). Tests 221 → 232; analyze clean; `npm test` 4/4. 2 findings deferred (markers split across emphasis lose their highlight — benign false-negative, needs whole-block matching; `MarkdownPreview` memoization). |
| 2026-07-26 | **Preview-first (author decision):** the editor now opens in the read-only preview by default (`_previewing` defaults `true`); the AppBar toggle switches to the raw editor. Updated AC1, Task 3, and Dev Notes to match. Aligned the test suite to the new default via a shared `enterEditMode` helper (`test/app/editor_test_helpers.dart`) — `pumpEditor` enters edit mode by default; browse/detail/conflicts/widget navigation tests switch to edit mode before asserting on the `TextField`. Assertions unchanged; full suite green (221); analyze clean. |
| 2026-07-26 | Implemented Story 2.7: read-only markdown preview (FR10). New `MarkdownPreview` widget (dart-lang `markdown` parser, `encodeHtml: false`, custom AST→widget walk) rendering headings/emphasis/lists/blockquotes/code/hr/links/images-as-alt-text, read-only + scrollable, total (AD-8 fallback to plain text). Reused `convention_matcher` (AD-7) to style this project's conventions + the 2.6 error kinds over rendered text runs, via a new shared `app/convention_styles.dart` (`styleForConvention`/`buildConventionSpans`) that the editor controller now also delegates to (one style map, no drift). Added a ready-state preview toggle to `EditorPage` (pure UI state; buffer/save/dirty/pop/lossy/conflict-banner all preserved). Image loading split to Story 2.16 (needs `RepoStorage.readBytes`); images render as alt text here. One new dep (`markdown 7.3.1`); no loader/model/contract change. Tests 197 → 221 (+24); analyze clean; `npm test` 4/4; `lore/` + contract git-clean. |
