---
project_name: 'Lore & Story'
user_name: 'KseiPo'
date: '2026-07-19'
sections_completed: ['technology_stack', 'core_architecture', 'parsing_writing', 'authoring_conventions', 'critical_rules']
existing_patterns_found: 12
status: 'complete'
rule_count: 50
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Project Framing (read first)

The **product goal is a Flutter/Dart mobile app** (Android first; design in
`MOBILE.md`). The Node.js code in this repo (`lib/`, `server.js`, `public/`) is a
**risk-probe POC and reference implementation** — not the end product. The
derived-model contract, pinned by golden fixtures in `test/fixtures/lore-model/`,
exists so the JS impl **and** the Dart port assert against the *same* shape. There
is no Dart code in the repo yet; today's work is still the Node POC + fixtures.

> Consequence for every rule below: the JS core is a *contract source*. Keep it
> cheap to re-implement in Dart and identical in behavior.

## Technology Stack & Versions

**Runtime:** Node.js ≥ 20. **No build step, no bundler, no TypeScript** — all
deliberately deferred until the core stabilizes (ARCHITECTURE.md §2). Do not
introduce TS, a bundler, or a frontend framework without a concrete, demonstrated
need.

**Core (`lib/`) — zero runtime dependencies, and this is a hard boundary:**
- `lib/*` may `require` **only Node builtins** (`fs`, `path`). No npm packages.
- `server.js` may use `express`; `public/*` may use the vendored browser libs.
- *Why it's a hard rule:* the core is ported to Dart, so every dependency is a
  second implementation to write and keep behavior-identical against the fixtures.

**Cross-implementation contract rules (JS and Dart must match):**
- **All path IDs are forward-slash normalized**, even on Windows:
  `path.relative(...).replace(/\\/g, '/')`. IDs look like
  `characters/selena/selena.md`, never backslash. A new file-walker that omits
  this `.replace` will break fixtures on one OS and pass on another.

**Server (`server.js`):** `express` ^4.19.2 — one data endpoint (`/api/data`)
plus an SSE endpoint (`/api/events`) for live reload. Everything is parsed fresh
per request; there is no cache.

**Frontend (`public/`):** vanilla JS as **IIFE modules exposing one global** —
`const LoreView = (() => { … })();`. **No ES modules, no `import`/`export`, no
build.** Vendor browser libs are **served from `node_modules` via an explicit
route map** in `server.js` (`/vendor/...`). Adding a frontend library means adding
a `server.js` route + a `<script>` tag — never an `import`.

**Graph rendering:** `cytoscape` ^3.28.1 + `cytoscape-dagre` ^2.5.0 +
`dagre` ^0.8.5 (browser only). `marked` ^12.0.2 for markdown.

**Testing:** Node's built-in runner — `node:test` / `node:assert`, run via
`npm test` (`node --test test/lore-model.test.js`). No Jest/Vitest/Mocha.

**Scripts:** `npm start` (server on :3987) · `npm test` · `npm run goldens`
(regenerate golden fixtures — see Category on data contracts).

## Critical Implementation Rules

### Core Architecture & Data Contracts

- **Files are the single source of truth; derived data is NEVER persisted.**
  Graph, analysis, lore cross-refs, mentions — all recomputed by parsing on every
  request. No database, no cache. If a feature wants to persist something, it is
  either authored content (belongs in the *user's* story repo) or it must be
  recomputed. (ADR 1, §5) The one sanctioned exception is future scene↔passage
  *bookkeeping* (e.g. last-synced hashes) — bookkeeping, not content.

- **The `/api/data` shape is a pinned contract — extend, never break.** Payload:
  `{ story, lore, loreEdges, storyDir, loreDir, parseMs }`. The `lore` /
  `loreEdges` shapes are specified in ARCHITECTURE.md §3.2a and the story shape in
  §3.5. This is the contract between the core and *both* UIs and the Dart port.

- **Golden fixtures are the contract, not an afterthought.** `loadLore`'s output
  is asserted against `test/fixtures/lore-model/cases/*/expected.json` (via
  `test/fixtures/lore-model/normalize.js`). When you change the model shape:
  1. update the contract (ARCHITECTURE.md §3.2a) and the code,
  2. run `npm run goldens` to regenerate `expected.json`,
  3. eyeball the fixture diff — it *is* the review of your shape change.
  Extend fixtures *with* the contract change, never after it.

- **One shared core, thin shells (ADR 5).** All logic lives in `lib/`. Shells
  (web app now, Tauri/Flutter later) stay as thin as possible. Don't put model
  logic in `server.js`, `public/*`, or a shell.

- **One graph engine, two graphs (ADR 6).** Story flow and the lore web are the
  same problem (directed graph + focus + search). `public/graph-view.js` serves
  both; neither view owns rendering logic.

- **Story and lore are two views over one payload (ADR 9).** They are independent
  UIs a coordinator switches between; both render the same `/api/data`. Keep them
  connected only by cross-view links, not by shared state.

### Parsing & File-Writing Rules

- **The parser stays shallow — on purpose (ADR 3).** It extracts passage headers
  and link expressions only; it never interprets SugarCube semantics beyond that
  and leaves all other text untouched. Resist teaching it SugarCube. When you need
  to recognize something new, add a *configurable extractor*, not special-case
  logic. Project-specific navigation (custom widgets) is **configuration**
  (`linkMacros`, `returnMacros`, `dynamicTags`, `codeDirs`), never code.

- **Writes to the user's story repo are SURGICAL — byte-exact except the intended
  change.** Parsing must round-trip untouched content unchanged. Never reformat,
  re-indent, or normalize a file you're editing.

- **The scene↔passage bridge never writes silently.** Every propagation between a
  scene and its passage is presented as a reviewable diff the author approves.
  No silent edits, ever.

- **Files are UTF-8, and non-ASCII is first-class.** The scene↔passage marker is a
  literal `⇄` (U+21C4); aliases include Cyrillic; prose uses em-dash conditional
  markers and `—`. Always read/write with `'utf8'`. Never assume ASCII; never
  strip or "normalize" non-ASCII characters.

- **Strip a BOM before parsing text as data.** `config.json` is read with
  `.replace(/^﻿/, '')` before `JSON.parse` because editors and PowerShell on
  this (Windows) machine write one. That line is load-bearing, not dead code —
  don't remove it; apply the same guard to any new config/JSON reader.

- **Analysis layers must earn their place.** Reachability is a stack of
  independent, individually-simple, *generic and configurable* layers
  (ARCHITECTURE.md §4) — static links, stored refs, code refs, tag exemption,
  composed names. New layers must be generic and demonstrated against a real
  project before merging; never a project-specific hack.

- **`config.json` is re-read on every request** (`readConfig()`), so pointing the
  tool at another project needs only an edit + Rescan — no restart. Don't cache
  config at module load for request-path logic.

- **`fs.watch` recursive isn't universal.** The recursive watcher is wrapped in
  try/catch because some platforms don't support it; the Rescan button is the
  fallback. Don't assume the watcher fired.

### Lore & Prose Authoring Conventions

**Entity resolution (how `loadLore` walks `lore/`) — structure, not schema:**
- A `.md` file in a category folder is a **simple entity**.
- A folder containing `index.md` **or** `<folder-name>.md` is an **entity folder**:
  that file is the entity *card*; every other `.md` inside (recursively) is a
  **sub-entry**. A sub-entry's *group* is its subfolder path (`quests/`, …).
- A folder without such an index file is just a (sub)category — the walk descends.
- **`media/` folders are skipped by the walker** and served as static assets.
- The entity card is **not** among its own `children[]` — it is not a sub-entry of
  itself (§3.2). Preserve this when touching the model.

**Lore card conventions:**
- `# Title` (first heading) is the canonical name; filename/folder is only a slug.
- Optional `aliases:` line (comma-separated) extends mention detection — include
  foreign-language names (imported lore carries RU + EN aliases).
- **Mentions** (implicit edges): case-insensitive word-boundary match of
  title+aliases against passage text and other cards.
- **Wikilinks** (explicit edges): `[[Title]]` anywhere in an entity → edge between
  entities. `[[…]]` is reserved for **lore entity references only** — in scene
  prose they are NEVER passage jumps.
- No frontmatter unless a concrete feature requires it. Everything else is free-form.

**Scene file (plain-prose) conventions (§3.3):**
- Scenes are markdown prose — **no SugarCube macros, no HTML, no game logic**
  (that lives only in the final twee passage).
- The `<!-- scene ⇄ passage: "Passage Name" · lang: en -->` comment is the
  explicit link to the twee passage. Tools collect **all** such comments per file.
- **Bilingual scenes are paired files:** `base.ru.md` + `base.en.md`. A missing
  `.en.md` is a deliberate "needs translation" signal — not a defect. The model
  merges the pair into one item titled `<ru> — <en>` (original language first).
- Canonical player-choice / link form (2026-07-17): `**Choice text** _(→ Passage
  Name)_` — underscore emphasis (stable under Prettier). Bold-only `**Choice**`
  when there's no target.
- **Return links** (widgets that go back, not to a named target):
  `**Label** _(↩ back)_` / `**Label** _(↩ wake up)_`. Passages with a
  `returnMacros` widget are never dead ends.
- Dialogue `Name (emotion): phrase.`; inner monologue `Мысль: …` / `*Thought:* …`;
  variable placeholders in readable brackets `[имя героя]` — never `<<=$var>>`.
- Multi-passage scenes stay ONE file with a `# <Passage Name>` section per passage,
  each carrying its own scene⇄passage comment.

**Content taxonomy & ownership (§3.2b):**
- Separate the three fused kinds: **card** (the bible), **design** (`arc.md` — the
  author's reference), **events** (written prose scenes), **quests** (ordered scene
  chains under `quests/<quest>/`).
- **Event ownership:** an event belongs to the character who *drives* it; a
  location owns only its own intro/first-visit scenes. Locations never own
  character events — they reference people via `[[wikilinks]]`.
- Promote a secondary character to its own entity folder the moment it accumulates
  content (same category; the card's `Type` marks the tier).

### Critical Don't-Miss Rules & Terminology

**Terminology — use these exact words in code, comments, docs, and identifiers:**
- **passage** — a twee unit (the playable form).
- **scene** — a plain-prose markdown unit (where prose is written/revised).
- **entry** (or **entity**) — a lore unit.
- **project** — one story repo.
- Don't blur "scene" and "passage": they are two representations of the *same*
  narrative, linked by passage name — never synonyms.

**Anti-patterns (things agents do here that are wrong):**
- ❌ Persisting any derived data to disk (see Core Architecture rules).
- ❌ Deepening the twee parser to understand SugarCube semantics.
- ❌ Reformatting a user's file while making a surgical edit.
- ❌ `import`-ing a frontend lib instead of adding a `/vendor` route + `<script>`.
- ❌ Adding an npm dependency to `lib/`.
- ❌ Treating `[[wikilinks]]` as passage jumps (they are lore references).
- ❌ Treating a lone `.en.md` or a missing `.en.md` as an error.
- ❌ Silently propagating a scene↔passage edit (must be a reviewable diff).

**Security / privacy (§6):**
- The tool is **local-only**: no telemetry, no network calls except (future) AI
  providers the user explicitly configures.
- `codeDirs` scanning is **read-only and never executes** project code.
- **AI features must show the assembled context pack before sending** — the user
  sees exactly what leaves the machine.

**Developer workflow:**
- Prefer the dedicated model/parser code paths; keep shells thin.
- Run `npm test` after any change to `lib/lore.js` or the model shape; regenerate
  goldens with `npm run goldens` and review the diff.
- Naming stays consistent with the terminology above across code and docs.

---

## Usage Guidelines

**For AI Agents:**
- Read this file before implementing any code in this repo.
- Follow ALL rules exactly; when in doubt, prefer the more restrictive option.
- Treat the JS core as a *contract source* for the Dart port — behavior over cleverness.
- Deeper "why" lives in `ARCHITECTURE.md` (the how), `IDEA.md` (the why), and
  `MOBILE.md` (the mobile/Dart design). This file is the fast-path rule set.

**For Humans:**
- Keep this file lean and focused on agent needs.
- Update it when the stack changes, the `/api/data` contract changes, or a new
  convention is enforced across the lore.
- Remove rules that become obvious over time.

Last Updated: 2026-07-19
