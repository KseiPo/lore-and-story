---
title: 'Lore & Story — Mobile App PRD'
status: final
created: 2026-07-19
updated: 2026-07-19
scope: 'v0.1 MVP + phased roadmap'
stakes: 'solo / personal tool'
---

# Lore & Story — Mobile App PRD

## 1. Overview

**Lore & Story Mobile** is a thin Flutter/Android writing app over a file-based
Twine/SugarCube story repo. It lets the author browse and edit the two markdown
layers of the project — **lore entries** and **plain-prose scene files** — from a
phone, while an external syncer (Syncthing/Dropbox/git) owns propagation. It is a
*writing surface*, not the desktop tool ported to a phone: no twee editing, no
flow graph, no scene↔passage bridge.

The app shares **no UI code** with the desktop POC. Its only shared surface is the
repo's files and the data contracts in `ARCHITECTURE.md` §3. The lore loader is a
Dart reimplementation of the reference `lib/lore.js`, kept honest by the shared
golden fixtures (`test/fixtures/lore-model/`).

**Why it exists (over pointing Obsidian at the folder):** a generic markdown
editor doesn't understand *this project's* conventions. The differentiating value
is a convention-aware editing surface — highlighting and (later) linting of
dialogue `Name (emotion):` lines, `[[wikilinks]]`, `[placeholders]`, and em-dash
conditionals, and **live flagging of invalid markup** (a generic editor can't tell
that a scene's `[[label->passage]]` is wrong) — plus first-class RU/EN bilingual
handling and safe coexistence with a live syncer.

## 2. Users & Context

Single-operator tool. The user is the **solo author** of the visual novel
(KseiPo), writing and revising on a phone in spare moments, against a repo folder
that a background syncer keeps in step with the desktop. The app is **one writer
among several** (the syncer, the desktop tool, VSCode). There is no second role,
no collaboration model, no account.

### 2.1 Core user journey (the loop the app must make pleasant)

> **UJ-1 — Edit a scene on the phone.** The author opens the app on the couch,
> lands on the category list (characters, stations, …), taps into a character,
> sees the entity's card and its sections (Events, Quests), opens a scene in the
> RU tab, fixes a line of dialogue using the helper row for the `—` and
> `(emotion):` punctuation the phone keyboard buries, taps save, and closes the
> app. Back at the desktop later, the change is already there — no conflict copy,
> byte-identical except the edited line.

This round-trip — **grant → browse → open → edit → atomic save → verified on
desktop** — is the product thesis. Everything in v0.1 exists to make it work and
feel good.

> **UJ-2 — Add new material.** Mid-writing, the author realizes a new location
> needs a card. From the stations category they create a new entity, type the
> `# Title`, and start writing. Later, an existing character needs a new event —
> they add it under that character's `events/` group. New files, byte-safe,
> synced like any edit.

> **UJ-3 — Grow a character into a folder.** A secondary character (`mira.md`,
> one flat file) has accumulated enough that it needs its own events. The author
> **promotes** it: the card becomes `mira/mira.md` (bytes untouched), and now
> events and quests can hang off it — the same structure a character like Selena
> already has. (This moves a file, so it lands in a later, carefully-designed
> phase.)

## 3. Goals & Success Metrics

**Product goal:** prove the phone can be a genuine writing surface for this
project — that the editing loop is pleasant and *safe* enough that the author
reaches for the phone instead of waiting for the desktop.

**Success signals** (solo tool — adoption-by-self, not analytics):

- **S1 — Round-trip proven:** on a real device with a live syncer, a
  browse→edit→save cycle propagates to the desktop with **zero app-caused
  conflict copies** and a byte-exact diff (only the intended change). *(This is
  the v0.1 acceptance gate; it is also the MOBILE.md §3.4 first-spike criterion.)*
- **S2 — Real use:** the author actually edits lore/scenes on the phone in normal
  writing sessions, rather than deferring every text edit to the desktop.
- **S3 — Convention support earns its keep:** the convention-aware editor (and
  later linter) is used and catches real styling errors the author would have
  missed.

**Counter-metrics** (must NOT happen — a win on speed that loses here is a loss):

- **C1 — No data loss / corruption:** the app never produces a partially written
  file, never corrupts encoding (Cyrillic), never drops a trailing newline or
  rewrites untouched bytes.
- **C2 — No collapsed pairs:** an RU/EN pair is never merged into a single file
  on save.
- **C3 — No spurious conflicts:** app writes do not generate syncer conflict
  copies under normal (non-concurrent-edit) use.

## 4. Scope

### 4.1 MVP — v0.1 "walking skeleton"

The thinnest end-to-end slice that exercises every hard part once: repo grant →
resolve config → walk lore → browse categories/entities/entity-tree → open a
card/sub-entry/scene → edit → atomic byte-exact save → verified round-trip; plus
RU/EN toggle, helper toolbar, convention-aware highlighting, and conflict-file
surfacing; plus low-risk authoring (create a new entity, create a new
event/sub-entry). Requirements: §5 groups A–E, plus FR24–FR25.

### 4.2 Phased roadmap (specified as later scope)

- **Phase v0.2 — Convention tooling** (§5 group F): convention linting (reusing
  the highlighter's matcher) and `[[wikilink]]` autocomplete + preview navigation.
- **Phase — Promotion / restructure** (§5 group I, FR26): promote a simple entity
  to an entity folder (card as index) so it can hold sub-entries. The one
  authoring op that **moves** a file — deferred until the edit + create loop is
  proven safe under the syncer.
- **Phase AI-1 — Translation** (§5 group G): RU→EN scene/card translation via a
  user-configured AI key, with a mandatory context preview. Ships before grammar
  because it is cheaper to build (a *create*, not a diff) and the glossary is free.
- **Phase AI-2 — Grammar/style findings** (§5 group H): a structured findings
  list (line/issue/suggestion/severity), never a rewritten file.

### 4.3 Out of scope

Twee editing; the flow graph; mention detection / lore-graph computed on-device;
the scene↔passage bridge and its drift bookkeeping; **renaming entities, moving
entities between categories, or arbitrary folder reorganization** beyond the
specific create/promote operations in Group I (these stay desktop/manual); in-app
search; file watching; **embedded-git sync** (evaluated and deferred — see
addendum); **read-only passage reference** on mobile (deferred). These are
referenced where they bound a requirement but are not specified here.

_Note: this PRD intentionally revises MOBILE.md ADR 5 (the "phone editing scope
line," which kept all creation and restructuring desktop-only) to permit
entity/event **creation** (MVP, FR24–FR25) and simple→folder **promotion** (a
later phase, FR26)._

## 5. Functional Requirements

IDs are stable and global. **MVP = groups A–E plus FR24–FR25**; groups F–H and
FR26 are phased. The mixed Group I tags each FR with its phase inline.

### Group A — Repo access & configuration (MVP)

- **FR1** — The app grants access to a user-chosen repo root folder that lives in
  shared storage (a syncer folder root or a folder inside one), and remembers it
  across launches.
- **FR2** — On open, the app reads `lore-story.json` (`ARCHITECTURE.md` §3.4) from
  the repo root to resolve `loreDir` (default `lore`). A missing/invalid config
  falls back to defaults without blocking.
- **FR3** — The app re-scans the repo on app resume (no live file watcher in
  v0.1). A manual refresh is available.

### Group B — Lore browsing (MVP)

- **FR4** — A **Categories** screen lists the top-level folders under `loreDir`
  (characters, stations, races, world, …).
- **FR5** — An **Entities** list presents simple files and entity folders as **one
  node type** — `frank.md` and `selena/` look and behave the same to the user
  (per the loader model; `index.md`/`<folder>.md` = card).
- **FR6** — An **Entity detail** screen renders the entity's content tree
  (`{overview, items, children}`): the card at top, then folder-named sections
  (Events, Quests), with nested quests (an overview + ordered stage files) shown
  as nested sections. Headings are the prettified subfolder names. `media/` is not
  shown as content.

### Group C — Editing (MVP)

- **FR7** — Tapping any card, sub-entry, or scene opens it in a **raw-markdown
  editor** (the markup is the content being proofread — never WYSIWYG / markup-
  hiding).
- **FR8** — A **helper toolbar** above the keyboard offers quick-insert for
  structure (H1/H2/H3, bullet list, numbered list, bold, italic) and project
  tokens (`[[`, `[`, `]`, `—`, an `(emotion):` snippet), via insert-at-cursor,
  wrap-selection, and prefix-line actions.
- **FR9** — The editor applies **convention-aware syntax highlighting** over the
  raw buffer: markdown structure plus this project's conventions — `[[wikilinks]]`,
  dialogue `Name (emotion):` lines, `[placeholders]`, em-dash conditional markers
  — while the underlying text stays raw markdown.
- **FR9a** — The same highlighter also renders **invalid / suspect markup in a
  distinct error style** so the author can spot and fix it fast — malformed or
  unterminated markup, leaked twee syntax (`<<…>>`, HTML) in prose, and Twine
  passage-link forms in scene files (`[[label->passage]]`, `[[a|b]]`) where the
  canonical `**label** _(→ target)_` belongs (in scenes, `[[…]]` is a lore
  reference only). This is the *editor surface* of error detection; the full
  navigable findings list is the v0.2 linter (FR18), sharing the same matcher.
- **FR10** — A **read-only preview** toggle renders the current buffer (rendered
  markdown); it is not an editing mode.
- **FR11** — Saving is **explicit** (a save action) plus **save-on-background**,
  with a visible dirty indicator. No autosave-per-keystroke.

### Group D — Bilingual RU/EN (MVP)

- **FR12** — An RU/EN file pair (`x.ru.md` + `x.en.md`) is presented as **one
  item** with `[RU][EN]` tabs, RU (original language) default — matching the
  loader's merge (`"<ru> — <en>"`).
- **FR13** — When the `.en.md` of a pair is absent, the item shows a **"needs
  translation"** badge; editing the empty EN tab is a **create-translation**
  action that creates the `.en.md` file.
- **FR14** — Saves **always write back to the individual file** (the RU or the EN
  file). The app must never collapse a pair into a single merged file.

### Group E — Sync coexistence & write integrity (MVP)

- **FR15** — Every save is an **atomic write**: write a temp file in the same
  directory, then rename over the target, so the syncer never observes a partial
  file. Writes are **byte-exact except the intended change** — preserve original
  line endings and trailing newline; encode/decode **explicit UTF-8**.
- **FR16** — The lore walk **filters syncer metadata** (`.stfolder`, `.stignore`,
  `.stversions`) exactly as it skips `media/`. The exclusion list is **hardcoded
  for MVP**; a user-configurable `ignore` list in `lore-story.json` is deferred.
- **FR17** — The walk **surfaces conflict copies**: files matching
  `*.sync-conflict-*.md` are shown as visible items with a "conflict" badge, never
  parsed as normal entries and never hidden. (This is the conflict UI.)

### Group F — Convention tooling (Phase v0.2)

- **FR18** — A **convention linter** flags mechanically detectable styling errors
  using the same matcher as FR9/FR9a's highlighter: leaked twee markup (`<<`, `>>`,
  HTML), `<<=$var>>` where a `[placeholder]` belongs, Twine passage-link syntax in
  scene files (`[[label->passage]]` / `[[a|b]]` where `**label** _(→ target)_`
  belongs), dialogue lines missing the `Name:` shape, unpaired em-dash conditional
  markers, and `[[wikilinks]]` pointing at entities that don't exist. Offline, no AI.
- **FR19** — `[[` triggers **autocomplete** over loaded entity titles + aliases;
  tapping an existing `[[Title]]` in preview navigates to that entity. (In scene
  files, wikilinks are lore references, never passage jumps.)

### Group G — AI translation (Phase AI-1)

- **FR20** — The author configures an AI provider **API key**, stored in secure
  device storage.
- **FR21** — For an RU file lacking its EN pair, the app **generates an English
  translation** into the EN tab (a create, not an edit), using a context pack of:
  the RU file + an **alias glossary** (title + RU/EN aliases across entities) +
  the `ARCHITECTURE.md` §3.3 prose conventions. The author edits the result and
  saves explicitly.
- **FR22** — Before any send, the app shows a **context preview** — a scrollable
  sheet of exactly what will leave the device (the file, the glossary terms, the
  conventions). Sending is gated behind this preview. *(Mandatory per
  `ARCHITECTURE.md` §6.)*

### Group H — Grammar/style findings (Phase AI-2)

- **FR23** — The app requests a **grammar/style review** and renders a
  **structured findings list** (`line`, `issue`, `suggestion`, `severity`) as a
  tappable list that jumps to the line. It returns findings, **not** a rewritten
  file. The FR22 context preview applies.

### Group I — Authoring & structure ops

- **FR24** *(MVP)* — **Create a new simple entity.** The author adds a new `.md`
  entry (e.g. a new race or location) in a chosen category, seeded with its
  `# Title`, via the atomic writer (FR15). May create the category folder when
  adding the first entry of a new top-level category.
- **FR25** *(MVP)* — **Create a new sub-entry / event** within an entity folder.
  The author adds a new file to a group (e.g. `events/`), creating the group
  subfolder if needed; RU/EN-aware (may begin as a lone `.ru.md` or `.en.md`).
  Via the atomic writer (FR15).
- **FR26** *(Phase — Promotion)* — **Promote a simple entity to an entity folder.**
  Convert `<slug>.md` into `<slug>/<slug>.md` (the card becomes the folder's
  index per the loader's `<folder-name>.md` rule), **preserving the card's bytes
  exactly**, so the entity can then hold sub-entries (FR25). This is the only
  authoring op that **moves** an existing file: it must be atomic and safe under
  the external syncer (R8), and is deferred until the edit + create loop is proven.

## 6. Non-Functional Requirements

- **NFR1 — Write integrity (critical):** no observable partial file; byte-exact
  writes; explicit UTF-8; preserved EOL and trailing newline. Directly enforces
  C1/C3.
- **NFR2 — Model conformance / anti-drift:** the Dart lore loader conforms to the
  `ARCHITECTURE.md` §3.2–3.3 contract and asserts against the **shared golden
  fixtures**; when the model changes, fixtures change first and both the JS
  reference and the Dart port follow. *(O1 — the card-in-own-children fixture
  discrepancy — is resolved: `lib/lore.js` excludes the card and the goldens pin
  that, so there is nothing for the port to copy. See §9.)*
- **NFR3 — Portability seam:** the loader and editor depend only on a `RepoStorage`
  interface (`listDir`, `read`, `writeAtomic`, `exists`), never on the storage
  permission or raw file APIs directly — so a future SAF backend or app-private +
  embedded-git working copy is a root-path swap, not a rewrite.
- **NFR4 — Offline-first:** all MVP and v0.2 functionality works with no network;
  only the AI phases require connectivity.
- **NFR5 — Security & privacy:** local-only; no telemetry; the only network calls
  are to the **user-configured** AI provider; the API key lives in secure device
  storage; nothing leaves the device without passing the FR22 context preview.
- **NFR6 — Responsiveness:** browsing and opening files feel instant on a real
  repo (the reference loader parses a 234-file project in ~50 ms on desktop);
  re-scan on resume must not introduce a noticeable stall.
- **NFR7 — Malformed input never crashes (critical):** existing files already
  contain mistakes and the author introduces more while editing, so the loader,
  highlighter, and editor must treat malformed or unexpected markup as **content
  to display and flag, never as a fault**. Any span the highlighter can't parse
  degrades to plain (or error-styled) text rather than throwing; a malformed file
  still opens, edits, and saves; a parse failure anywhere never blocks browsing or
  loses the buffer. Highlighting is best-effort and always recoverable.

## 7. Key constraints & dependencies

- **External syncer owns propagation** (`ARCHITECTURE.md` ADR 2): the app never
  syncs, merges, or authenticates a sync in v0.1. Risk: the syncer dependency is
  less stable than assumed (Syncthing-Android maintenance changes) — tracked as
  R6; the `RepoStorage` seam keeps embedded-git a cheap pivot.
- **Shared golden fixtures** are the operative contract between the JS reference
  and the Dart port; they already exist and the JS side asserts against them.
- **Minimum Android: 11+** (confirmed) — the all-files-access storage model
  assumes scoped-storage-era Android.
- **No telemetry / analytics** (confirmed) — success is judged by the author's own
  use (NFR5).
- Storage/permission model, git evaluation, AI provider/model/cost specifics, and
  Flutter editor mechanics are recorded in **`addendum.md`** (implementation
  detail, not PRD-level requirements).

## 8. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Storage access shapes how close the Dart port stays to the reference | All-files access + real paths behind `RepoStorage` (NFR3) |
| R2 | Concurrent writes with a live syncer → partial files / spurious conflicts | Atomic byte-exact write, explicit save, re-scan on resume, surface conflict copies (FR15–17, NFR1) |
| R3 | RU/EN pair collapsed into one file on save → corrupts bilingual model | Writes target the individual file (FR14, C2) |
| R4 | Two implementations of one contract, no shared code → drift | Golden fixtures both loaders assert against (NFR2) |
| R5 | Scope creep toward "rebuild the desktop tool on a phone" | Phone editing scope line (§4.3) |
| R6 | External-syncer dependency less stable than assumed | Watch it; `RepoStorage` keeps embedded git a cheap pivot, not a rewrite |
| R7 | Clone size with `media/` history could kill the deferred-git pivot | Measure repo clone size before ever committing to embedded git (addendum) |
| R8 | Promotion (FR26) moves a file under a live syncer (delete+create) → conflict copies or a lost card | Own phase, not MVP; atomic move preserving card bytes; re-scan on resume; block promotion while a conflict copy exists for that entity |

## 9. Open questions

- **O3** — Read-only passage reference on mobile: which representation the phone
  shows, and whether it needs the twee parser ported or just renders recovered
  scene files. *(Deferred feature; flagged for a later PRD.)*
- **O4** — How much lore-graph / mention surfacing is worth computing on-device
  vs. leaving to the desktop tool?

_Resolved: O1 — the `lib/lore.js` ↔ `ARCHITECTURE.md` §3.2 discrepancy (entity
card in its own `children[]`) is fixed: `buildNode` excludes the card via the
`base !== cardBase` guard (`lore.js:67`) and the shared goldens pin the
card-excluded behavior, so the Dart port inherits the correct contract. O2 —
syncer exclusions hardcoded for MVP, configurable `ignore` list deferred (FR16).
FR24 — phone may create new top-level categories. O5 — Android 11+. O6 — no
telemetry (§7)._

_Tech-implementation depth intentionally lives in `addendum.md`._
