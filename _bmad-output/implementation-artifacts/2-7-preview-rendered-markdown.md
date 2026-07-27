---
baseline_commit: ccd7ed5
---

# Story 2.7: Preview rendered markdown

Status: ready-for-dev

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

1. **AC1 (FR10 — read-only preview toggle):** Given the editor is open, when I tap a **preview toggle** (an AppBar affordance), then the raw-markdown `TextField` is replaced by a **read-only, scrollable rendered view of the current in-memory buffer** (including unsaved edits); toggling back returns to editing. Preview is **display-only** — it never mutates the buffer, and it is **not** an editing mode (no WYSIWYG-in-place; this is a distinct mode, consistent with MOBILE §5's "never hide markup *while editing*").
2. **AC2 (standard markdown rendering):** Given buffer text, when preview renders, then standard markdown renders correctly — headings (H1–H6), `**bold**`/`_italic_`, ordered/unordered lists (including nesting), blockquotes, inline code and fenced code blocks, thematic breaks (`---`), hard line breaks, and `[text](url)` links **as styled (non-tappable, v0.1) text** — via the **dart-lang `markdown` parser** + a custom widget builder in `app/`. An `![alt](src)` image renders as its **alt text / a small placeholder** in this story (real local-image loading is Story 2.16). Rendering is read-only and scrolls independently.
3. **AC3 (project conventions styled — AD-7 reuse):** Given rendered text runs, when they contain this project's conventions, then `[[wikilinks]]`, `Name (emotion):` dialogue prefixes, `[placeholders]`, em-dash conditional markers, **and the Story 2.6 error kinds** (leaked twee/HTML, scene passage-links, unterminated `[[`) are **styled by reusing `convention_matcher`** — no second recognition implementation — and rendered with the **same convention style map as the editor** (extracted to a shared helper so editor and preview never drift). Markdown-structural kinds that markdown already renders (heading/bold/italic/list marker) are **not** re-applied by the matcher in preview (markdown owns them); the matcher styles only the conventions markdown leaves as literal text.
4. **AC4 (total — never crash — AD-8/NFR7):** Given malformed markdown, malformed/leaked markup, or a lossy-UTF-8 buffer, when I toggle preview, then rendering **never throws** — it degrades to best-effort/plain text; the preview opens, and toggling back to the editor leaves the buffer intact and still saveable. A parser failure yields a plain-text rendering of the raw buffer rather than an error screen.
5. **AC5 (reusable renderer for Stories 2.13 & 2.16):** Given the renderer, when it is built, then it is a **standalone `MarkdownPreview` widget** (input: the markdown `text`; output: a read-only rendered widget) — **not** inlined into `EditorPage`. Story 2.13 (card preview on the detail screen) must be able to drop it in unchanged, and Story 2.16 must be able to **extend it** (adding `storage`/`filePath` for image loading) without restructuring it. Keep its API minimal and its coupling to the editor zero.
6. **AC6 (hygiene; gates):** `flutter analyze` clean; `flutter test` green with new tests (toggle, markdown rendering, convention styling, malformed/lossy input). The **only** new dependency is `markdown` (the pure-Dart parser) — no `flutter_markdown` (discontinued). **No loader/model/contract change** (fixtures 4/4, `npm test` 4/4). Existing editor behavior — load, dirty, save, save-on-background/pop, lossy guard + banner, conflict banner (2.4), toolbar (2.5), convention highlighting (2.5/2.6) — is preserved.

## Tasks / Subtasks

- [ ] **Task 1 — Markdown → widget renderer (`MarkdownPreview`) (AC: 2, 4, 5)**
  - [ ] `flutter pub add markdown` (the dart-lang parser; pure Dart, no native). Do **not** add `flutter_markdown` (discontinued upstream) or a fork — we render the AST ourselves so we can reuse `convention_matcher` (AD-7) now and load images via the port later (Story 2.16).
  - [ ] Add `apps/mobile/lib/app/markdown_preview.dart` — `class MarkdownPreview extends StatelessWidget`. **Constructor input:** `required String text`. No dependency on `EditorPage` (AC5). (Story 2.16 will add `storage`/`filePath` params for images — keep the widget structured so that's an additive change.)
  - [ ] Parse with `md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)` → `parseLines(text.split('\n'))` (or `.parse(text)`), yielding `List<md.Node>`. Walk the AST to Flutter widgets: **block** nodes (`h1`–`h6`, `p`, `ul`/`ol`/`li` incl. nesting, `blockquote`, `pre`/`code` fenced, `hr`) → a column of block widgets; **inline** nodes (`text`, `em`, `strong`, `code`, `a`, `img`, `br`) → a `RichText`/`Text.rich` with the corresponding `TextStyle`s from `Theme.of(context).textTheme`. Read-only; wrap in a scroll view. Links render as styled text (colored), **not** tappable in v0.1 (navigation is Story 3.2 / FR19). An `img` node renders its **alt text** (or a small placeholder) — no file loading in this story.
  - [ ] **Total (AC4):** wrap the parse+build in `try/catch`; on ANY failure return a plain `SelectableText`/`Text(text)` of the raw buffer (never an exception, never an error screen). Malformed markdown is content to show best-effort, not a fault.
- [ ] **Task 2 — Convention styling in preview, reusing the matcher (AC: 3)**
  - [ ] Extract the editor's `ConventionKind → TextStyle` mapping into a **shared** helper so editor and preview render conventions identically. Add `apps/mobile/lib/app/convention_styles.dart` with `TextStyle styleForConvention(ConventionKind kind, ColorScheme scheme, TextStyle base)` (move the body of `ConventionHighlightingController._styleFor` here) and refactor the controller to delegate to it. Pure mapping, no matching (AD-7).
  - [ ] Also factor the **span-building** both consumers share: a helper `List<InlineSpan> buildConventionSpans(String text, {required TextStyle? base, required Set<ConventionKind> apply, required TextStyle Function(ConventionKind) styleFor})` that runs `matchConventions(text)`, keeps only tokens whose kind is in `apply`, and splits `text` into plain + styled runs (the same defensive, total, span-text-equals-input logic already in `buildTextSpan`). The controller uses it with **all** kinds; the preview uses it with **only the convention + error kinds** (exclude `heading`/`bold`/`italic`/`listMarker` — markdown renders those). This keeps the flattened-text-equals-input invariant in one place.
  - [ ] In the renderer, when emitting a `md.Text` run, build its span via `buildConventionSpans(runText, apply: {wikilink, dialogueSpeaker, placeholder, emDash, leakedTwee, leakedHtml, scenePassageLink, malformedMarkup}, …)`. So markdown owns block/emphasis structure; the matcher owns the project conventions markdown leaves as literal text. (Heuristic caveat: `dialogueSpeaker` is line-anchored; on a text run that isn't a whole line it may not fire — acceptable for v0.1, note it.)
- [ ] **Task 3 — Wire the toggle into `EditorPage` (AC: 1, 4, 6)**
  - [ ] Add a preview toggle to the editor: an AppBar `IconButton` (e.g. `Icons.visibility_outlined` ↔ `Icons.edit_outlined`) that flips a `bool _previewing` in `_EditorPageState`. In the ready state, when `_previewing`, render `MarkdownPreview(text: _controller.text)` **in place of** the `Expanded(TextField)` + `EditorToolbar`; otherwise render the editor as today. **Preserve everything else:** the conflict banner (2.4), lossy banner, dirty indicator, Save action, save-on-background/pop, lossy guard. Save remains available from preview (the buffer is unchanged; you can still save your edits). The toolbar is hidden while previewing (nothing to insert into a read-only view).
  - [ ] Preview shows the **current buffer** (`_controller.text`), so unsaved edits are visible (AC1). Toggling is pure UI state — no re-read, no write, no new async.
  - [ ] Only offer preview in the **ready** state (not loading/error). Previewing a lossy-loaded file is fine (read-only render of the best-effort text); saving stays disabled by the existing lossy guard.
- [ ] **Task 4 — Tests (AC: 1–6)**
  - [ ] **Renderer widget tests** (`test/app/markdown_preview_test.dart`): headings/bold/italic/lists/blockquote/code/`---`/link-as-text render (assert structure in the widget tree, e.g. a bold run has `FontWeight.bold`, a fenced block renders monospace); an `![alt](x.png)` shows its alt text/placeholder (no load); a `[[wikilink]]`/`(emotion):`/`[placeholder]`/em-dash run carries the **convention** style (same as the shared map); a leaked-twee/`[[a->b]]` run carries the **error** style; **malformed markdown never throws** and still shows the text (AD-8). Include a Cyrillic sample.
  - [ ] **Editor toggle widget tests** (`test/app/editor_page_test.dart`): the preview toggle appears in the ready state; tapping it hides the `TextField`+`EditorToolbar` and shows `MarkdownPreview`; tapping again returns to the editor; **previewing does not change `_controller.text`** (edit → toggle preview → toggle back → text unchanged, still dirty); Save still works from preview; a lossy file can be previewed and Save stays disabled; the conflict banner still shows. Regression: existing editor tests stay green.
  - [ ] **Shared-style regression**: a test that the extracted `styleForConvention` returns the same styles the controller used to (so the refactor didn't change editor highlighting); the existing controller tests must stay green.
  - [ ] Contract gate: `flutter analyze` clean; `flutter test` green; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` **empty**.

## Dev Notes

### What this story is — a read-only render mode that stays faithful to *this* project

The editor (Stories 1.4/2.4/2.5/2.6) shows **raw markdown** — the markup *is* the content being proofread. FR10 adds the complementary view: a **read-only rendered preview** you toggle into to see how a card/scene reads. Per the author's decision (see Scope note), the preview is not a generic markdown viewer — it **reuses `convention_matcher`** to style this project's conventions. Three deliverables:

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
- **`apps/mobile/lib/app/editor_page.dart`** (MODIFY) — add the `_previewing` toggle + AppBar action; in the ready body, swap `TextField`+`EditorToolbar` for `MarkdownPreview` when previewing. **Preserve** every existing behavior (banners, dirty, save, background/pop, lossy). Current state (from Story 2.6): ready body is a `Column` with the conflict banner, lossy banner, `Expanded(TextField(controller: _controller))`, then `EditorToolbar(controller: _controller)`; AppBar has the path + dirty indicator + Save action.
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

### Debug Log References

### Completion Notes List

### File List
