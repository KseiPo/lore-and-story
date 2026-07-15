# Lore & Story — Technical Reference

*Contracts, technology choices, conventions and architectural decisions.
Companion to [IDEA.md](IDEA.md) (the "why"); this document is the "how".
Last updated: 2026-07-14.*

## 1. Architectural decisions (ADRs)

1. **Files are the single source of truth.** Every view — graph, analysis, lore
   cross-references, mention lists — is derived by parsing and is never
   persisted. There is no database, no cache to invalidate, no possibility of
   the visual layer diverging from reality. Re-parse cost is negligible
   (measured: ~50 ms for a 234-file project).
2. **Sync is external.** The tool watches files; it never syncs, merges or
   authenticates. Any folder syncer (Syncthing, Dropbox) or VCS (git) works
   underneath. Mobile edits markdown only (lore, scenes) and never twee;
   with a single author and small per-entity files, conflicts are rare and
   surface as the syncer's conflict copies rather than app logic.
3. **Shallow, config-driven twee parsing.** The parser extracts passage
   headers and link expressions; it never interprets SugarCube beyond that and
   leaves all other text untouched. Project-specific navigation (custom
   widgets) is configuration, not code.
4. **Multi-layer reachability analysis.** Static links alone produce unusable
   noise on data-driven stories (measured: 139 false orphans out of 301
   passages). The analysis stacks independent, individually-simple layers —
   see §4. New layers must be generic and configurable, never project-specific
   hacks.
5. **One shared core, thin shells.** All logic lives in plain JS libraries.
   Shells (local web app today, Tauri wrapper later, Flutter capture app on
   mobile) stay as thin as possible and share the repo as their data contract.
6. **One universal graph-view library, two graphs.** Story flow (passages +
   links) and the lore web (entities + relations/mentions) are the same
   problem: directed graph, focus mode, search, clustering, theming. One
   visualization module serves both; neither view owns rendering logic.
7. **Lore is markdown with light conventions** (§3.2) — readable by humans,
   git, and AI tools without any export step. Structure comes from folders and
   a few optional inline conventions, never from a schema that makes writing
   feel like data entry.
8. **The story text exists in two representations.** Plain-prose *scene files*
   (markdown, §3.3) and twee passages are two views of the same narrative,
   linked by passage name. Scenes are where prose is written and revised;
   passages are the playable form. Missing scene files are recovered from
   passages by stripping markup; after that, changes on either side are
   propagated by an AI-assisted, review-first bridge — never silently (§3.3).
   The author edits *real* files on both layers; there is no separate
   "drafts" staging area.
9. **Story and lore are separate views over one data layer.** The passage-flow
   view and the lore view are independent UIs (own sidebar, graph, detail
   panel) that a shared coordinator switches between; they may later become two
   apps. They stay connected by cross-view links (a passage's lore mentions
   jump to the lore view; a lore entity's passage mentions jump to the story
   view) and by the shared graph engine (ADR 6). Neither view owns the data —
   both render the same `/api/data` payload.

## 2. Components & technology

| Component | Status | Technology | Notes |
|---|---|---|---|
| Core: twee parser + analysis | working (POC) | Node.js, plain CommonJS, zero deps | `lib/twee-parser.js` |
| Core: lore model + graph | working (POC) | Node.js, plain CommonJS | `lib/lore.js` — entity folders, sub-entries, mention + wikilink edges |
| Core: graph-view library | working (POC) | Cytoscape.js + dagre/cose (browser) | `public/graph-view.js` — shared by both views (ADR 6) |
| UI: story-flow view | working (POC) | vanilla JS module | `public/story-view.js` |
| UI: lore view | working (POC) | vanilla JS module | `public/lore-view.js` — entity graph + markdown detail |
| Core: scene↔passage bridge | planned | AI-assisted diff + propagation | extraction (twee → scene md) first; drift sync later; always review-first |
| Desktop app | POC | Express server + vanilla JS/HTML/CSS, SSE for live reload | later: same UI wrapped in Tauri for folder picker / tray / installer |
| Mobile app | planned | Flutter (Android first) | writes/edits lore + scene markdown; twee read-only; no shared UI code |
| AI integration | planned | provider-agnostic; context packs assembled from repo files; possibly MCP server over the story model | kills the copy-paste loop |
| Sync | out of scope by design | Syncthing / Dropbox / git — user's choice | see ADR 2 |

Environment: Node.js ≥ 20, no build step for the POC (vendor libs served from
`node_modules`). TypeScript may be introduced when the core stabilizes; not
before.

## 3. Data contracts

### 3.1 Story project layout (target)

The tool adapts to existing projects; nothing below is mandatory except
"passages are `.twee`/`.tw` files under one root". Reference layout:

```
<story-repo>/
  src/twee/            # passages — the playable form; polished in VSCode
  src/scripts/         # game code; scanned read-only for passage references
  lore/                # the lore base (§3.2)
    characters/
      mira.md          # simple entity: one file
      selena/          # entity folder: card + attached sub-entries
        selena.md      # the entity card (matches folder name; or index.md)
        media/         # images referenced by the card/sub-entries
        quests/
          relationship-quest-1.md   # sub-entry, group "quests"
    stations/
    races/
    world/
  scenes/              # plain-prose scene files mirroring passages (§3.3)
  lore-story.json      # per-project tool config (§3.4)
```

### 3.2 Lore entry contract

An entity is either **one markdown file** or an **entity folder**. Category =
folder path (relative to `lore/`) up to the entity.

```markdown
# Display Title
aliases: nickname, alternate spelling, callsign

Free markdown body. May reference other entries as [[Display Title]]
(wikilink) — these become explicit edges in the lore graph.
```

**Entity resolution rules** (how the loader walks `lore/`):

- A `.md` file in a category folder is a **simple entity**.
- A folder containing `index.md` **or** `<folder-name>.md` is an **entity
  folder**: that file is the entity *card*; every other `.md` inside it
  (recursively) is a **sub-entry** attached to the entity. The sub-entry's
  *group* is its subfolder path (`quests/`, `events/`, …) — used to organize
  the detail panel and, later, the editor.
- A folder **without** such an index file is just a (sub)category; the walk
  descends into it.
- `media/` folders are skipped by the walker and served as static assets.

This is how "a character has a card plus folders of related content (events,
relationship quests…)" is expressed — structurally, with no schema. A simple
`mira.md` and a full `selena/` folder are the same kind of thing to every
consumer; growing one into the other is just `mkdir` + move.

- `# Title` (first heading) is the canonical name; filename/folder is a slug.
- `aliases:` line (optional) extends mention detection; include foreign-language
  names (the imported lore carries RU + EN aliases).
- **Mention detection** (implicit edges): case-insensitive word-boundary match
  of title + aliases against passage text and other lore cards.
- **Wikilinks** (explicit edges): `[[Title]]` anywhere in the entity (card or
  sub-entries) → edge between entities.
- Anything else is free-form. No frontmatter unless a concrete feature
  requires it.

### 3.2a Derived lore model (API shape)

`GET /api/data` also returns `lore` and `loreEdges`:

- `lore[]`: `id, title, aliases, category, file, relDir, text, children[],
  mentionedIn[]` — where `children[]` are `{id, title, group, file, text}`
  and `mentionedIn[]` are passage names.
- `loreEdges[]`: `{source, target, kind}` with `kind` ∈ `link` (wikilink) |
  `mention` (card text contains another entity's alias).

### 3.2b Character content taxonomy (worked example)

Imported character docs fuse **three** kinds of content that must be separated
(pilot: Selena, 2026-07-14 — 132 KB file → 6.5 KB card + design + 14 scenes):

1. **Card** (`selena.md`) — the character *bible*: profile block (type,
   faction, age, occupation, location, want/need/fear), character, past,
   memories, portrait prompt. Compact; this is what the lore node/detail shows.
2. **Design** (`arc.md`, a root sub-entry) — relationship-level progression,
   planned events, quest outlines. Reference the author reads while writing;
   not prose, not bible.
3. **Events** (`events/*.md`) — the written prose of standalone relationship
   interactions. "Events" is this VN's domain term for what §3.3 calls scenes.
4. **Quests** (`quests/<quest>/…`) — an ordered chain of scenes. A quest is a
   subfolder with an overview card (`<quest>.md`) and one file per stage; stages
   are scenes like any other. Selena's pilot: `quests/relationship-quest-1/`
   with `relationship-quest-1.md` (overview) + `01-…` … `08-…` stage files.

Sub-entries nest arbitrarily: a subfolder's own `<name>.md`/`index.md` is that
section's overview; folder names become section headings (`events/` → "Events").
The same split applies to locations (card + description + events) and any entity
that accumulates written content.

**Event ownership** (decided 2026-07-14): an event belongs to the **character
who drives it** (Carrie's "Конец смены" lives under `characters/carrie/events/`
even though it happens in her bar); a location's own **intro/first-visit scenes
belong to the station** (`stations/<station>/events/`). Locations never own
character events — they reference people via staff lists with `[[wikilinks]]`,
and mention detection links the rest. Secondary characters get **promoted** from
the `secondary-characters.md` list to their own entity folder the moment they
accumulate content (Carrie, Marcus) — same category, `Type`/card marks the tier.

**Promotion posts** live in a top-level `lore/promotion/` category — one Patreon
post per document (paired `.ru.md`/`.en.md` where both languages exist),
including the station lore articles, which are marketing texts, not station
canon (station cards keep the factual content only).

### 3.3 Scene files contract (plain-prose story layer)

One authored scene = one scene file. Scenes may live **under their entity**
(`characters/selena/scenes/…`, the pilot's choice — keeps a character's
material together) **or** in a top-level `scenes/` tree mirroring `storyDir`;
both are valid and the bridge treats them the same.

```markdown
# <Scene Title>
<!-- scene ⇄ passage: "Selena - Echoes of the Past" · lang: en -->

Plain readable prose. No SugarCube macros, no HTML, no game logic —
twee exists only in the final passages.
```

**Prose conventions** (enforced across lore 2026-07-14):

- Dialogue: `Name (emotion): phrase.` — e.g. `Селена (спокойно): Иногда
  техника чувствует, когда на неё злятся.` Emotion is optional.
- Inner monologue: `Мысль: …` (RU) / `*Thought:* …` (EN).
- Variable placeholders: readable square brackets — `[имя героя]`,
  `[награда]`, `[станция назначения]` — never `<<=$var>>`.
- Player choices: bold text, optionally with the target passage as a note —
  `**Начать атаку**`, `**Перелезть** *(→ At Spaceport)*`.
- Authoring conditionals: em-dash markers — `— если игрок знаком с доктором
  Джулией — … — иначе — … — конец условия —`.
- `[[Wikilinks]]` are reserved for lore entity references (cards/overviews);
  they are never passage jumps.

- **Bilingual scenes are paired files:** `echoes-of-the-past.ru.md` +
  `echoes-of-the-past.en.md` (decision 2026-07-14). A missing `.en.md` is a
  visible "needs translation" signal — exactly the AI-translation workflow.
  The model merges the pair into one item titled `<ru> — <en>` (original
  language first); the UI shows one row with a RU/EN toggle, RU default.
- The `scene ⇄ passage` comment is the explicit link to the twee passage —
  the seed of the M3 bridge. Where absent, the first heading / filename maps
  by name.
- **Origin, either direction:** written first as prose and later transformed
  into a passage, or *recovered* from an existing passage by stripping markup
  (macros, HTML, code) — how the layer gets bootstrapped for a story that
  already has hundreds of passages.
- Scene files are where prose revision, AI editing and translation happen;
  the twee passage keeps the game logic and presentation.
- New ideas that aren't a passage yet are just scene files (or lore entries)
  like any other — there is no separate drafts area; the author edits real
  files and returns to them over time.

**Open design questions (M-scene-sync):** drift detection needs bookkeeping
(e.g. last-synced content hashes in a small state file — an accepted
exception to ADR 1, since it is bookkeeping, not content); propagation of an
edit from scene → passage (and back) is AI-assisted and always presented as a
reviewable diff, never applied silently.

### 3.4 Per-project config (`lore-story.json` in the story repo)

Describes the *story project*, so it belongs in the story repo (currently the
POC keeps a global `config.json` in the tool repo — to be migrated).

```jsonc
{
  "storyDir": "src/twee",        // passage root, relative to the repo
  "loreDir": "lore",
  "scenesDir": "scenes",
  "codeDirs": ["src/scripts"],   // scanned for passage-name literals
  "linkMacros": ["backLink"],    // custom widgets: first arg = passage target
  "dynamicTags": ["dream"]       // tags meaning "reached at runtime"
}
```

### 3.5 Derived story model (API shape, informal)

`GET /api/data` returns `{ story, lore, parseMs }` where `story` contains:

- `passages[]`: `name, tags, file, rel, folder, line, text, words`
- `edges[]`: `source, target, kind, utilitySource, broken`
  - `kind`: `link` (wiki), `macro` (`<<link>>`/`<<button>>`/custom), `goto`,
    `include`, `stored` (assignment of a passage name to a variable),
    `dynamic` (unresolvable expression)
- `issues`: `orphans, broken, dynamic, endings, dynamicTagged, composed,
  codeReferenced`
- `codeRefs`: passage → referencing script files

This shape is the contract between core and any UI; extend, don't break.

## 4. Reachability analysis layers

Applied in order when deciding whether a passage is an orphan; each layer is
independent and configurable:

1. **Static links** — all `kind`s above except `dynamic`, extracted from *all*
   passages (widgets and specials navigate too).
2. **Stored references** — `<<set $var to 'Name'>>` where the string equals an
   existing passage name (deferred `<<goto $var>>` pattern). Non-matching
   strings are ignored, never "broken".
3. **Code references** — string literals in `codeDirs` files (and twee source)
   equal to a passage name.
4. **Tag exemption** — passages tagged with any `dynamicTags` entry.
5. **Composed names** — word-break segmentation: the name can be assembled
   from 2+ string literals found in the corpus (case-insensitive, separators
   ` - `, `_`, ` `). Reported as its own category, not silently accepted.

Validated result on the reference project (367 passages, ~45% of navigation
data-driven): 139 false orphans → 2 true findings, 0 false broken links.

## 5. Developer conventions

- **Derived data is never written to disk.** If a feature wants to persist
  something, it's either authored content (belongs to the user's repo) or
  it should be recomputed.
- **The parser stays shallow** (ADR 3). Resist making it understand SugarCube
  semantics; prefer a new configurable extractor.
- **Analysis layers must earn their place**: generic, configurable, and
  demonstrated against a real project before merging.
- **Writes to the user's story repo are surgical**: byte-exact except the
  intended change; parsing must round-trip untouched content.
- Plain CommonJS modules in `lib/`, no framework in the POC UI; introduce
  tooling (TS, bundler, framework) only when a concrete need appears.
- The scene↔passage bridge never writes silently: every propagation is a
  reviewable diff the author approves.
- Names in code and docs: "passage" (twee unit), "scene" (plain-prose unit),
  "entry" (lore unit), "project" (one story repo).

## 6. Security / privacy notes

- The tool is local-only; no telemetry, no network calls except (future) AI
  providers explicitly configured by the user.
- `codeDirs` scanning is read-only and never executes project code.
- AI features must show what leaves the machine (the assembled context pack)
  before sending.
