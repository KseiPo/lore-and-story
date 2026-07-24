---
stepsCompleted: ['step-01-validate-prerequisites', 'step-02-design-epics', 'step-03-create-stories', 'step-04-final-validation']
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md
  - _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/addendum.md
  - MOBILE.md
  - ARCHITECTURE.md
  - _bmad-output/project-context.md
---

# Lore & Story Mobile - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for the Lore & Story
Flutter/Android mobile app, decomposing the requirements from the PRD and the
technical decisions in the PRD addendum / MOBILE.md / ARCHITECTURE.md into
implementable stories. (No formal BMad architecture.md exists yet; the addendum
and MOBILE.md serve as the technical-requirements source.)

## Requirements Inventory

### Functional Requirements

**MVP (v0.1 walking skeleton) — groups A–E + FR24–FR25**

- **FR1**: Grant access to a user-chosen repo root in shared storage and remember it across launches.
- **FR2**: The picked repo folder is the lore folder itself, so `loreDir` defaults to the repo root; `lore-story.json` may redirect it to a subfolder (whole-repo sync) when that subfolder exists. Missing/invalid config, or a non-existent `loreDir`, falls back to the root without blocking.
- **FR3**: Re-scan the repo on app resume (no live watcher in v0.1); provide a manual refresh.
- **FR4**: Show a Categories screen listing top-level folders under `loreDir`.
- **FR5**: Present simple files and entity folders as one node type in the Entities list (`frank.md` and `selena/` behave identically).
- **FR6**: Render an Entity-detail content tree (`{overview, items, children}`) — card, folder-named sections, nested quests; `media/` excluded.
- **FR7**: Open any card/sub-entry/scene in a raw-markdown editor (never WYSIWYG / markup-hiding).
- **FR8**: Provide a helper toolbar for structure (H1–H3, lists, bold, italic) and project tokens (`[[`, `[`, `]`, `—`, `(emotion):`) via insert/wrap/prefix actions.
- **FR9**: Apply convention-aware syntax highlighting over the raw buffer (markdown + `[[wikilinks]]`, `Name (emotion):`, `[placeholders]`, em-dash conditionals).
- **FR9a**: Render invalid/suspect markup in a distinct error style (malformed markup, leaked twee `<<…>>`/HTML, scene `[[label->passage]]`) so the author can fix it fast.
- **FR10**: Provide a read-only preview toggle rendering the buffer (not an editing mode).
- **FR11**: Explicit save + save-on-background with a dirty indicator; no autosave-per-keystroke.
- **FR12**: Present an RU/EN file pair as one item with `[RU][EN]` tabs, RU default.
- **FR13**: Show a "needs translation" badge when `.en.md` is absent; editing the empty EN tab creates the file (create-translation).
- **FR14**: Always write saves back to the individual RU/EN file; never collapse a pair into one file.
- **FR15**: Perform every save as an atomic, byte-exact UTF-8 write (temp file + rename; preserve EOL and trailing newline).
- **FR16**: Filter syncer metadata (`.stfolder`, `.stignore`, `.stversions`) in the walk (hardcoded list for MVP).
- **FR17**: Surface conflict copies (`*.sync-conflict-*.md`) as visible badged items; never parse or hide them.
- **FR24** *(MVP)*: Create a new simple entity in a chosen category (seed `# Title`); may create the category folder for a new top-level category.
- **FR25** *(MVP)*: Create a new sub-entry/event within an entity folder (create the group subfolder if needed); RU/EN-aware.

**Phased (later scope)**

- **FR18** *(v0.2)*: Convention linter — a navigable findings list sharing FR9a's matcher (leaked twee, misplaced `<<=$var>>`, scene passage-link syntax, malformed dialogue, unpaired conditionals, dangling wikilinks). Offline, no AI.
- **FR19** *(v0.2)*: `[[` autocomplete over entity titles + aliases; tapping a `[[Title]]` in preview navigates to that entity.
- **FR20** *(AI-1)*: Configure an AI provider API key stored in secure device storage.
- **FR21** *(AI-1)*: Generate an EN translation into the EN tab (a create) using a context pack of the RU file + alias glossary + prose conventions.
- **FR22** *(AI-1)*: Show a mandatory context preview of exactly what leaves the device before any AI send; gate sending behind it.
- **FR23** *(AI-2)*: Request a grammar/style review and render a structured findings list (line/issue/suggestion/severity); never a rewritten file.
- **FR26** *(Promotion phase)*: Promote a simple entity to an entity folder (`<slug>.md` → `<slug>/<slug>.md`, card bytes preserved) so it can hold sub-entries; the only authoring op that moves a file.

### NonFunctional Requirements

- **NFR1** *(critical)*: Write integrity — no observable partial file; byte-exact; explicit UTF-8; preserved EOL/trailing newline.
- **NFR2**: Model conformance / anti-drift — the Dart loader conforms to ARCHITECTURE §3.2–3.3 and asserts against the shared golden fixtures.
- **NFR3**: Portability seam — loader/editor depend only on a `RepoStorage` interface (`listDir`, `read`, `writeAtomic`, `exists`), never on the storage permission or raw file APIs.
- **NFR4**: Offline-first — all MVP and v0.2 functionality works with no network; only AI phases need connectivity.
- **NFR5**: Security & privacy — local-only, no telemetry; only network calls are to the user-configured AI provider; API key in secure storage; nothing sent without the FR22 preview.
- **NFR6**: Responsiveness — browsing/opening feel instant on a real repo; resume re-scan introduces no noticeable stall.
- **NFR7** *(critical)*: Malformed input never crashes — loader/highlighter/editor treat malformed markup as content to flag, degrade to plain/error text, never throw; malformed files still open/edit/save.

### Additional Requirements

_Technical / setup requirements from the PRD addendum, MOBILE.md, and ARCHITECTURE.md that shape the epics (no formal architecture.md yet):_

- **Greenfield scaffold**: new Flutter (Android) app under `apps/mobile/`. No external starter template specified — the project scaffold itself is Epic 1's first story.
- **Storage backend**: `MANAGE_EXTERNAL_STORAGE` + `dart:io` real paths, behind the `RepoStorage` seam (NFR3). Android 11+.
- **Non-UI first spike (MOBILE §3.4)**: prove the headless storage + sync loop (grant folder → read one `.ru.md` → atomic write-back → verify Syncthing propagation, no conflict copy) **before** building any browsing UI. This is the highest-risk slice and belongs in the foundation epic.
- **Dart port of the lore loader**: read subset of `lib/lore.js` — `walkCategory`, `buildNode`, `readTitleAliases`, language pairing — plus new write path; pinned to `test/fixtures/lore-model/` golden fixtures (NFR2).
- **New Dart-side components**: atomic UTF-8 writer (FR15/NFR1), syncer-aware walk (FR16/FR17), convention matcher (FR9/FR9a, reused as FR18 linter).
- **AI transport (AI phases)**: raw HTTPS to the Messages API (no official Anthropic Dart SDK) with hand-rolled SSE streaming + retry; model `claude-opus-4-8`; key via `flutter_secure_storage`.

_(Prior O1 fixture-correctness dependency is resolved — commit `23c5df4` fixed the `lib/lore.js` card-in-own-children discrepancy, so the golden fixtures the Dart port conforms to are now correct.)_

### UX Design Requirements

_None — no UX design document exists for this project. The PRD's journeys (UJ-1–3) and editing-UX section (MOBILE §5) provide interaction intent inline; formal UX-DRs are not extracted._

### FR Coverage Map

- **FR1**: Epic 1 — grant & remember repo root
- **FR2**: Epic 1 — resolve `loreDir` from `lore-story.json`
- **FR3**: Epic 2 — re-scan on resume + manual refresh
- **FR4**: Epic 2 — categories screen
- **FR5**: Epic 2 — entities list (one node type)
- **FR6**: Epic 2 — entity-detail tree
- **FR7**: Epic 1 — raw-markdown editor (bare in E1, enriched in E2)
- **FR8**: Epic 2 — helper toolbar
- **FR9**: Epic 2 — convention-aware highlighting
- **FR9a**: Epic 2 — invalid-markup error highlighting
- **FR10**: Epic 2 — read-only preview
- **FR11**: Epic 1 — explicit save + save-on-background
- **FR12**: Epic 2 — RU/EN tabs
- **FR13**: Epic 2 — needs-translation badge / create-translation
- **FR14**: Epic 2 — write to individual file, never collapse a pair
- **FR15**: Epic 1 — atomic byte-exact UTF-8 write
- **FR16**: Epic 2 — filter syncer metadata in the walk
- **FR17**: Epic 2 — surface conflict copies
- **FR18**: Epic 3 — convention linter
- **FR19**: Epic 3 — wikilink autocomplete / navigation
- **FR20**: Epic 4 — AI key config
- **FR21**: Epic 4 — EN translation generation
- **FR22**: Epic 4 — mandatory context preview
- **FR23**: Epic 4 — grammar/style findings
- **FR24**: Epic 2 — create new simple entity
- **FR25**: Epic 2 — create new sub-entry / event
- **FR26**: Epic 5 — promote simple → folder

## Epic List

### Epic 1: Edit a file end-to-end (v0.1 — thin vertical slice)

Grant the repo, open one real file, edit it in a bare editor, save it back
atomically, and verify it landed byte-exact on the desktop with no conflict copy.
The thinnest thread through every layer — it proves the highest-risk
storage/sync/write path (the **S1 acceptance gate**) while being a real,
demonstrable user action.
**FRs covered:** FR1, FR2, FR7, FR11, FR15
**Also establishes:** the Flutter `apps/mobile/` scaffold, the `RepoStorage` seam
(NFR3), a minimal single-file read from the Dart loader, the atomic UTF-8 writer
(NFR1), crash-safe handling (NFR7), and the headless first-spike (MOBILE §3.4).

### Epic 2: Browse, edit, and create lore & scenes (v0.1 — full experience)

Browse the whole lore base (categories → entities → entity tree), edit any
card/sub-entry/scene with the convention-aware editor (highlighting +
invalid-markup flagging + preview + RU/EN tabs), see conflict copies surfaced, and
create new entities and events. The complete v0.1 writing experience, built on the
proven foundation.
**FRs covered:** FR3, FR4, FR5, FR6, FR8, FR9, FR9a, FR10, FR12, FR13, FR14, FR16, FR17, FR24, FR25
**Notes:** full Dart loader port (`walkCategory` / `buildNode` / `readTitleAliases`
/ language pairing) + syncer-aware walk; authoring (FR24–FR25) is the **closing
story cluster** — a distinct create/`mkdir` write path, ordered after the edit
path is solid.

### Epic 3: Convention tooling (v0.2)

Catch styling mistakes across a whole file and navigate lore fast: the convention
linter (a navigable findings list reusing the FR9a matcher) and `[[wikilink]]`
autocomplete + tap-to-navigate.
**FRs covered:** FR18, FR19

### Epic 4: AI writing assist (AI phases)

Configure an AI key and get help under a mandatory send-preview: RU→EN translation
first, then grammar/style findings. One epic (shared HTTP client, key store, and
context-preview sheet). **Release checkpoint: translation (FR21) ships before
grammar (FR23)** — the deliberate PRD phasing.
**FRs covered:** FR20, FR21, FR22, FR23

### Epic 5: Promote entity to folder (promotion phase)

Grow a simple card into an entity folder so it can hold sub-entries — the one
authoring op that moves an existing file, isolated and carefully sequenced under
the syncer.
**FRs covered:** FR26

---

## Epic 1: Edit a file end-to-end (v0.1 — thin vertical slice)

Grant the repo, open one real file, edit it, save it atomically, and verify it
round-trips to the desktop byte-exact. Proves the highest-risk storage/sync/write
path (the S1 acceptance gate).

**Epic Definition of Done (every story):** works fully offline (NFR4); browsing and
opening feel instant (NFR6).

### Story 1.1: Scaffold the app and grant the repo folder

As the author,
I want to launch the app, grant it access to my repo folder, and have it remembered,
So that the app can reach my synced files on later launches without re-granting.

**Acceptance Criteria:**

**Given** a fresh install on Android 11+, **When** I open the app and choose my repo root (a Syncthing folder or a folder inside one), **Then** the app requests all-files access and stores the chosen root path. *(FR1)*

**Given** I have granted access and picked a root, **When** I relaunch the app, **Then** it reopens the same root without asking again.

**Given** the app code, **When** the loader or editor needs the filesystem, **Then** it goes through a `RepoStorage` interface (`listDir`, `read`, `writeAtomic`, `exists`) and never touches `dart:io` or the permission directly. *(NFR3)*

### Story 1.2: Prove a safe atomic round-trip (headless spike)

As the author,
I want the app to read one file and write it back without the syncer ever seeing a partial or conflicting file,
So that I can trust it with my repo before any UI exists.

**Acceptance Criteria:**

**Given** a granted Syncthing'd folder containing a `.ru.md` file, **When** the app reads it and writes it back via a debug trigger, **Then** the write is atomic (temp file in the same dir + rename) and byte-identical (EOL and trailing newline preserved, explicit UTF-8). *(FR15, NFR1)*

**Given** the write completes, **When** I check the desktop, **Then** Syncthing has propagated the file with no `*.sync-conflict-*` copy. *(S1)*

**Given** a malformed or unexpected file, **When** it is read, **Then** reading never throws — content is handled as-is. *(NFR7)*

### Story 1.3: Resolve project configuration

As the author,
I want the app to read my project's `lore-story.json`,
So that it knows where my lore lives without in-app configuration.

**Acceptance Criteria:**

**Given** a repo root containing `lore-story.json`, **When** the app opens the repo, **Then** it resolves `loreDir` from it (default: the repo root itself — the picked folder is the lore folder). *(FR2)*

**Given** the file is missing or invalid JSON, **When** the app opens the repo, **Then** it falls back to defaults and continues without blocking or crashing.

### Story 1.4: Open and save one file in a bare editor

As the author,
I want to open a file, edit its text, and save it,
So that I can make a real edit from my phone end-to-end.

**Acceptance Criteria:**

**Given** a resolved `loreDir`, **When** I pick a file, **Then** its raw markdown loads into an editable text field with no markup hidden. *(FR7)*

**Given** I have edited the buffer, **When** I tap save, **Then** the file is written via the Story 1.2 atomic writer, the dirty indicator clears, and backgrounding also saves. *(FR11)*

**Given** the buffer differs from disk, **When** I look at the editor, **Then** a dirty indicator is visible.

## Epic 2: Browse, edit, and create lore & scenes (v0.1 — full experience)

The complete v0.1 writing experience on the proven foundation. Authoring
(Stories 2.10–2.11) is the closing cluster, ordered after the edit path is solid.

**Epic Definition of Done (every story):** works fully offline (NFR4); browsing and
opening feel instant (NFR6).

### Story 2.1a: Port the lore loader (read-model)

As the author,
I want the app to parse my lore folder into the entity model,
So that everything I've written is available to browse.

**Acceptance Criteria:**

**Given** my `loreDir`, **When** the loader parses it, **Then** it produces the entity model — simple entities and entity folders with `{overview, items, children}` trees, category = path, `readTitleAliases` for title + aliases, language pairs merged (`"<ru> — <en>"`) — conformant to the shared golden fixtures. *(NFR2)*

**Given** an entity folder, **When** the model is built, **Then** the card is not listed among its own `children[]` (per ARCHITECTURE §3.2).

### Story 2.1b: Syncer-aware walk and rescan

As the author,
I want the walk to coexist with my syncer and refresh when I come back,
So that browsing reflects the current repo without stale or junk entries.

**Acceptance Criteria:**

**Given** `media/` folders and syncer metadata (`.stfolder`, `.stignore`, `.stversions`), **When** the walk runs, **Then** they are skipped. *(FR16)*

**Given** a `*.sync-conflict-*.md` file, **When** the walk runs, **Then** it is detected as a conflict item (surfaced by Story 2.4), never parsed as a normal entry.

**Given** I resume the app or tap refresh, **When** it reloads, **Then** it re-scans the repo (no live watcher). *(FR3)*

### Story 2.2: Browse categories and entities

As the author,
I want to browse my categories and the entities inside them,
So that I can navigate to any card.

**Acceptance Criteria:**

**Given** the scanned model, **When** I open the app, **Then** I see a Categories screen listing top-level `loreDir` folders. *(FR4)*

**Given** a category, **When** I open it, **Then** I see its entities, with a simple file (`frank.md`) and an entity folder (`selena/`) presented as the same kind of item. *(FR5)*

### Story 2.3: View an entity's detail tree

As the author,
I want to see an entity's card and its sections,
So that I can find the specific sub-entry or scene to edit.

**Acceptance Criteria:**

**Given** an entity, **When** I open it, **Then** I see the card on top followed by folder-named sections (Events, Quests), nested quests shown as nested sections, headings prettified. *(FR6)*

**Given** an entity folder, **When** it renders, **Then** `media/` is not shown as content and the card is not listed as its own child.

### Story 2.4: Surface sync conflict copies

As the author,
I want conflict copies shown clearly,
So that I notice and resolve sync collisions instead of editing the wrong file.

**Acceptance Criteria:**

**Given** a `*.sync-conflict-*.md` file in the walk, **When** lists render, **Then** it appears as a visible item with a "conflict" badge. *(FR17)*

**Given** such a file, **When** the model is built, **Then** it is never parsed as a normal entry and never hidden.

### Story 2.5: Edit with helper toolbar and convention highlighting

As the author,
I want quick-insert buttons and convention-aware highlighting,
So that phone editing of these files is fast and readable.

**Acceptance Criteria:**

**Given** the editor is open, **When** I use the helper toolbar, **Then** I can insert structure (H1–H3, lists, bold, italic) and project tokens (`[[`, `[`, `]`, `—`, `(emotion):`) via insert/wrap/prefix. *(FR8)*

**Given** file text, **When** it renders, **Then** markdown structure plus conventions (`[[wikilinks]]`, `Name (emotion):`, `[placeholders]`, em-dash conditionals) are highlighted while the buffer stays raw markdown. *(FR9)*

**Given** the highlighter is implemented, **When** the convention matcher is built, **Then** it is factored as a standalone component the linter (Story 3.1) reuses — not inlined into the editor widget.

### Story 2.6: Flag invalid markup without crashing

As the author,
I want invalid or suspect markup highlighted distinctly,
So that I can spot and fix mistakes fast.

**Acceptance Criteria:**

**Given** text with malformed markup, leaked twee (`<<…>>`, HTML), or scene `[[label->passage]]`, **When** it renders, **Then** those spans get a distinct error style. *(FR9a)*

**Given** any input the highlighter can't classify, **When** `buildTextSpan` runs, **Then** it degrades to plain text and never throws; the file still opens, edits, and saves. *(NFR7)*

### Story 2.7: Preview rendered markdown

As the author,
I want a read-only preview,
So that I can check how a card reads.

**Acceptance Criteria:**

**Given** the editor, **When** I toggle preview, **Then** the current buffer renders as read-only markdown; toggling back returns to editing. *(FR10)*

### Story 2.8: Edit RU/EN pairs safely

As the author,
I want a paired RU/EN file shown as one item with tabs,
So that I can work bilingually without corrupting the pair.

**Acceptance Criteria:**

**Given** `x.ru.md` + `x.en.md`, **When** I open the item, **Then** it shows `[RU][EN]` tabs with RU default. *(FR12)*

**Given** I edit and save either tab, **When** the write happens, **Then** it targets that individual file only and never merges the pair into one file. *(FR14)*

### Story 2.9: Create a translation from a missing EN

As the author,
I want to start an EN translation when it's missing,
So that I can fill the gap on the phone.

**Acceptance Criteria:**

**Given** an RU file with no `.en.md`, **When** the item renders, **Then** it shows a "needs translation" badge. *(FR13)*

**Given** I edit the empty EN tab and save, **When** the write happens, **Then** the `.en.md` file is created (a create, not a merge).

### Story 2.10: Create a new entity

As the author,
I want to create a new card,
So that I can add a race or location from the phone.

**Acceptance Criteria:**

**Given** a category, **When** I create a new entity and enter a title, **Then** a new `.md` seeded with `# Title` is written via the atomic writer. *(FR24)*

**Given** I create the first entity of a brand-new top-level category, **When** I confirm, **Then** the category folder is created too.

### Story 2.11: Create a new event / sub-entry

As the author,
I want to add an event under an entity,
So that a character can accumulate written content.

**Acceptance Criteria:**

**Given** an entity folder, **When** I add a new sub-entry to a group (e.g. `events/`), **Then** a new file is created there, creating the group subfolder if needed, RU/EN-aware. *(FR25)*

### Story 2.12: Retire the raw file picker in favor of full browse

As the author,
I want a single, consistent way to reach my files — the lore browse,
So that the app isn't cluttered with a second, weaker navigation path that lists raw filenames instead of titles, RU/EN tabs, and conflict badges.

**Context:** "Open a file" + `LoreFilePickerPage` were Epic 1 scaffolding (Story 1.4), kept through Story 2.2 as a secondary action because the browse then only opened an entity's *card*. Once the browse reaches everything an author edits — cards, sub-entries, events, scenes, quests (Story 2.3's detail tree) and RU/EN pairs (Stories 2.8/2.9) — the raw picker is redundant. This is the closing consolidation story of Epic 2; it must run **after** 2.3 (and ideally the editor cluster 2.5–2.9) so removal strands nothing.

**Acceptance Criteria:**

**Given** the browse reaches every editable lore file (card, sub-entry, scene, language variant) via categories → entities → the detail tree, **When** the home surface renders, **Then** the "Open a file" button is gone and browsing is the single navigation path in.

**Given** the raw picker is no longer user-reachable, **When** it is retired, **Then** `LoreFilePickerPage` and the home handlers that drove it (`_openFile`/`_openFileFrom`) are removed cleanly with no dead or half-wired code — **or** the picker is kept only as an explicitly-justified, clearly-labeled advanced/escape-hatch entry point (decide during the story), not as a co-equal primary action. *(AD-12 / hygiene)*

**Given** everything previously reachable through "Open a file", **When** I browse after the change, **Then** each editable lore file remains reachable — no regression in access (verify cards, sub-entries, scenes, and RU/EN variants).

**Notes:** Removing the picker also closes several deferred picker-only bugs (trailing-slash `loreDir`, a file named exactly `loreDir`, the `_openEntry`/`_openFile` `exists`-vs-`isDirectory` conflation) — see `deferred-work.md`. Not tied to a new FR; a UX-consolidation/hygiene story.

## Epic 3: Convention tooling (v0.2)

**Epic Definition of Done (every story):** works fully offline (NFR4); linting and
navigation feel instant (NFR6).

### Story 3.1: Lint a file for convention errors

As the author,
I want a navigable list of styling mistakes in a file,
So that I can clean it up quickly.

**Acceptance Criteria:**

**Given** a file, **When** I run the linter, **Then** it lists mechanically detectable errors (leaked twee, misplaced `<<=$var>>`, scene `[[label->passage]]`, malformed dialogue lines, unpaired conditionals, dangling `[[wikilinks]]`) using the same matcher as the highlighter. *(FR18)*

**Given** a finding, **When** I tap it, **Then** the editor jumps to that line; **And** with no network, linting still works (offline, no AI).

### Story 3.2: Autocomplete and navigate wikilinks

As the author,
I want `[[` autocomplete and tappable wikilinks,
So that lore references are fast and correct.

**Acceptance Criteria:**

**Given** I type `[[` in the editor, **When** the autocomplete opens, **Then** it suggests entity titles + aliases and inserts the chosen one. *(FR19)*

**Given** a rendered `[[Title]]` in preview, **When** I tap it, **Then** it navigates to that entity.

## Epic 4: AI writing assist (AI phases)

**Epic Definition of Done (every story):** the app stays usable offline — AI actions
require network and fail gracefully when it's absent (NFR4/NFR5); non-AI
interactions stay responsive (NFR6).

### Story 4.1: Configure an AI key and stand up the API client

As the author,
I want to store my AI provider key securely and have the app ready to call the API,
So that AI features work without exposing the key.

**Acceptance Criteria:**

**Given** settings, **When** I enter an API key, **Then** it is stored in secure device storage (Keystore) and never logged or shown in plain text after entry. *(FR20, NFR5)*

**Given** there is no official Anthropic Dart SDK, **When** the client is built, **Then** it calls the Messages API over raw HTTPS with SSE stream parsing and retry/error handling — a reusable client for translation (4.3) and grammar (4.4).

### Story 4.2: Preview exactly what will be sent

As the author,
I want to see everything that will leave my device before any AI call,
So that I stay in control of what's shared.

**Acceptance Criteria:**

**Given** an AI action is about to send, **When** it triggers, **Then** a scrollable preview shows the exact payload (the file, glossary terms, conventions) and sending is gated behind it. *(FR22)*

**Given** I dismiss the preview, **When** I cancel, **Then** nothing is sent.

### Story 4.3: Translate RU → EN (release checkpoint)

As the author,
I want AI to draft the EN translation of an RU file,
So that I can fill missing translations fast.

**Acceptance Criteria:**

**Given** an RU file lacking its EN pair, **When** I request translation, **Then** the app assembles the context pack (RU file + alias glossary + prose conventions), shows the FR22 preview, and on confirm streams a translation (via the Story 4.1 client) into the EN tab as a create. *(FR21)*

**Given** the draft arrives, **When** I review it, **Then** I can edit it and explicitly save to `.en.md`.

**Release checkpoint:** this story is independently shippable; grammar (Story 4.4) is not required for it.

### Story 4.4: Grammar / style findings

As the author,
I want AI grammar/style feedback as a findings list,
So that I can improve prose while keeping my voice.

**Acceptance Criteria:**

**Given** a file, **When** I request a review, **Then** the app (after the FR22 preview) returns a structured findings list (`line`, `issue`, `suggestion`, `severity`) as a tappable list that jumps to the line — never a rewritten file. *(FR23)*

## Epic 5: Promote entity to folder (promotion phase)

**Epic Definition of Done (every story):** works fully offline (NFR4); promotion
completes without a noticeable stall (NFR6).

### Story 5.1: Promote a simple entity to an entity folder

As the author,
I want to convert a flat card into an entity folder,
So that it can hold events and quests like a full character.

**Acceptance Criteria:**

**Given** a simple entity `<slug>.md`, **When** I promote it, **Then** the app creates `<slug>/` and moves the card to `<slug>/<slug>.md` (the folder index), preserving the card's bytes exactly. *(FR26)*

**Given** the move, **When** it runs, **Then** it is atomic and the model re-scans to show the entity as a folder that can hold sub-entries. *(FR25)*

**Given** a conflict copy exists for that entity, **When** I try to promote, **Then** promotion is blocked until it is resolved. *(R8)*

**Given** the entity's card is open with unsaved edits, **When** I try to promote, **Then** the app saves-or-blocks first — it never moves the file out from under a dirty buffer. *(AD-10)*
