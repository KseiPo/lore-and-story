# Lore & Story — Mobile App Design

*The Android writing app (M5, pulled forward). Companion to [IDEA.md](IDEA.md)
(the "why") and [ARCHITECTURE.md](ARCHITECTURE.md) (the shared "how"); this
document is the mobile-specific "how". Status: design agreed, pre-scaffold.
Last updated: 2026-07-16.*

## 1. Scope

The mobile app is a **thin writing shell over the repo**. It reads and edits
lore entries and scene markdown on Android; it reads passages read-only (later);
it never touches twee editing, the graph, or the scene↔passage bridge. It shares
**no UI code** with the desktop tool — the repo files and the contracts in
[ARCHITECTURE.md](ARCHITECTURE.md) §3 are the only shared surface (ADR 5, 9).

Decisions carried in from the concept work: Flutter, Android-only for now; edits
markdown (lore + scenes), never twee.

## 2. Mobile ADRs (decided 2026-07-16)

1. **The working copy lives in shared storage; the app uses all-files access and
   real paths.** `MANAGE_EXTERNAL_STORAGE` + `dart:io` paths behind a thin
   `RepoStorage` interface. This keeps the Dart lore loader a near-line-for-line
   mirror of the reference `lib/lore.js` and preserves the desktop mental model
   ("a path into a synced folder"). The heavy permission is **a consequence of
   external sync**, not an independent choice — see §3.1, which is the important
   part of this ADR. Not Play-Store-distributable; irrelevant for a sideloaded
   personal tool. SAF is deliberately **not** used; `RepoStorage` exists so it
   *could* be added if distribution ever matters.
2. **The app is not the only writer.** A live syncer writes into the same folder
   concurrently. Every save is an **atomic write** (temp file + rename) so the
   syncer never observes a half-written file; the app re-scans on resume rather
   than watching files. Syncer metadata is filtered from the walk and conflict
   copies are surfaced, not swallowed. See §3.2.
3. **The RU/EN pair is a view, never a file.** `x.ru.md` + `x.en.md` merge into
   one editor item with a language toggle (ARCHITECTURE §3.3), but saves always
   write back to the **individual** file. The app must never collapse a pair
   into a single merged file. See §5.
4. **The Dart loader is a conformant reimplementation, guarded by golden
   fixtures.** `lib/lore.js` is the *reference*, but Dart cannot import it. Both
   implementations conform to the ARCHITECTURE §3.2–3.3 contract and are pinned
   to a shared fixture set (`test/fixtures/lore-model/`) that both loaders assert
   against. The fixtures are the anti-drift mechanism.
5. **Phone editing scope line.** v0.1 edits the *text* of existing files and may
   *create* an `.en` translation of an existing `.ru` file. It does **not**
   create entities, rename, move, or restructure folders. Promotion, `mkdir`, and
   reorganization remain desktop/manual operations (mirrors the desktop "editing
   scope line" in IDEA.md, adapted for the phone).
6. **Sync stays external; embedded git is evaluated and deferred.** ARCHITECTURE
   ADR 2 holds for now. Embedding a git client is a real option with a real
   payoff (no permission at all), but its cost is merge/auth/lifecycle, not the
   library. IDEA.md already sets the trigger: it becomes relevant *if one-tap
   commits from the phone are wanted*. See §3.3 for the evaluation and the
   conditions that would flip this.
7. **AI runs as direct API calls with a user-configured key.** This answers, for
   mobile, IDEA.md's open question ("API keys in-app vs. MCP + external agent vs.
   both"): MCP + external agent needs an agent runtime the phone doesn't have, so
   mobile is API-key-in-app. Sanctioned by ARCHITECTURE §6 ("no network calls
   except AI providers explicitly configured by the user") — this is not a
   conflict with ADR 2, whose "never authenticates" governs *sync*. See §6.
8. **The editor is raw markdown with structure helpers, never WYSIWYG.** Helper
   buttons that *insert* markdown (`##`, `- `) are fine and wanted — they are
   text insertion, not WYSIWYG. What is excluded is any mode that **hides
   markup**, because the prose conventions (ARCHITECTURE §3.3) *are* the content
   being proofread. Syntax highlighting (which styles without hiding) is the
   middle ground and is the recommended editing surface. See §5.

## 3. Storage & sync

### 3.1 The coupling (why the permission exists)

Modern Android (11+) denies a normal filesystem path to an arbitrary user
folder. The three options are **not independent axes** — the real structure of
the decision is:

> **The heavy permission is a consequence of external sync.** Something outside
> the app must reach the folder → the folder must live in shared storage →
> all-files access or SAF. Nothing outside reaches it → app-private storage →
> **no permission at all, and still real paths** → but then *the app itself must
> sync*, which means embedding git.

| Option | Permission | Paths | App owns auth? | App owns merge? |
|---|---|---|---|---|
| **All-files + external syncer** | `MANAGE_EXTERNAL_STORAGE` (heavy) | **real** | no | no | 
| SAF + external syncer | folder grant (light) | `DocumentFile` | no | no |
| App-private + embedded git | **none** | **real** | **yes** | **yes** |

**Chosen: all-files + external syncer** (ADR 1). SAF is rejected on port grounds
— `DocumentFile` traversal diverges from the path contract and makes the loader a
rewrite rather than a mirror. App-private is rejected only because it *forces*
embedded git (§3.3); its storage properties are otherwise the best of the three,
which is why this table replaced an earlier version that wrongly presented the
permission as a free-standing choice.

The user grants the permission once and picks the repo root — the folder they
sync, which **is** the lore folder itself. So `loreDir` defaults to the picked
root (not a `lore/` subfolder); the app may still read `lore-story.json`
(ARCHITECTURE §3.4) to redirect `loreDir` to a subfolder for the whole-repo-sync
case, honored only when that subfolder exists. (The desktop reference still
defaults to `lore`, since it assumes the whole repo is present.)

`RepoStorage` is the seam: `listDir`, `read`, `writeAtomic`, `exists`. The loader
and editor depend only on this interface, never on `MANAGE_EXTERNAL_STORAGE` or
`dart:io` directly — so both a future SAF backend *and* a future app-private +
git working copy are a root-path swap, not a rewrite.

### 3.2 Living alongside Syncthing

The app is one writer among several; the syncer owns propagation (ADR 2):

- **Ignore syncer metadata** in the walk — `.stfolder`, `.stignore`,
  `.stversions` — exactly as the loader already skips `media/`.
- **Surface conflict copies.** Files matching `*.sync-conflict-*.md` are shown
  as visible items (a "conflict" badge), never parsed as normal entries and
  never hidden. This *is* the conflict UI, and it is free.
- **No file watcher in v0.1.** Read on open, atomic-write on save, **re-scan on
  app resume**. With a single author and small per-entity files, conflicts are
  rare (ARCHITECTURE ADR 2); a background watcher is unearned complexity.
- **Atomic, surgical writes.** Write to a temp file in the same directory, then
  rename over the target, so the syncer never sees a partial write. Preserve the
  original line endings and trailing newline; encode/decode **explicit UTF-8**
  (Cyrillic content — never rely on platform defaults). Byte-exact except the
  intended change (ARCHITECTURE §5).

### 3.3 Embedded git: evaluated, deferred

Evaluated 2026-07-16 (ADR 6). Recorded because the analysis is reusable and the
trigger condition is real.

**The library is cheap.** [git2dart](https://pub.dev/packages/git2dart) (the
maintained successor to libgit2dart) gives Dart FFI bindings to libgit2 and
**bundles the native lib automatically on Android release builds** (arm64-v8a and
x86_64 — no armeabi-v7a). The pure-Dart [dart-git](https://github.com/GitJournal/dart-git)
is still self-described as experimental and scoped to GitJournal's needs.

**The cost is semantics, not the library:**

| Piece | Cost |
|---|---|
| git2dart + clone/pull/commit/push | small–medium |
| Auth (PAT over HTTPS, Android Keystore) | small, bounded — avoid SSH (drags in libssh2) |
| **Merge / diverged-branch UX** | **the real cost** — libgit2 gives primitives; the app owns conflict UI, dirty-tree-blocks-pull, merge-vs-rebase |
| Full clone incl. `media/` history | **unmeasured risk** — portrait PNGs; libgit2's shallow-clone support is historically weak |

**The move that collapses the big cost:** with a single author, pulls are almost
always fast-forward. Design it as **fast-forward-only sync that explicitly
refuses to merge** — "remote diverged → resolve on desktop." That keeps ADR 2's
*"never merges"* intact while dropping only *"never syncs/authenticates"*, and
turns "implement git" into clone + FF-pull + commit + push + one honest error
state.

**Why deferred:** v0.1's job is to prove the editing loop is pleasant on a phone.
Front-loading git means building auth, clone, and divergence handling *before*
knowing whether the core thesis holds. The throwaway cost is small — the
`RepoStorage` seam makes the working-copy swap a root-path change.

**What would flip it:** wanting one-tap commits from the phone (IDEA.md's stated
trigger), or the external-syncer dependency degrading (risk F, §10). **Measure
the repo's clone size with media history before committing** — that is the one
number that could kill the option outright.

### 3.4 The first spike is non-UI

Because the risk in v0.1 is concentrated in storage-grant and safe write-back,
the first build is a **headless loop**, before any browsing UI:

> grant a Syncthing'd folder → read one `.ru.md` → atomic write-back → confirm
> on the desktop that Syncthing propagated it with no conflict copy.

Prove the storage + sync loop on a real device before building screens.

## 4. App structure

Navigation maps 1:1 onto the loader's model (ARCHITECTURE §3.2) — no parallel
hierarchy is invented:

| Screen | Backed by | Notes |
|---|---|---|
| **Categories** | top-level `lore/` folders | characters, stations, races, world, plot, quests, promotion, meta |
| **Entities** | simple file *or* entity folder | one node type to the UI; `frank.md` and `selena/` are the same kind of thing |
| **Entity detail** | `buildNode` tree (`{overview, items, children}`) | card at top, then folder-named sections (Events, Quests); a quest is a nested section (overview + ordered stage files) |
| **Editor** | one card / sub-entry / scene file | §5 |

The entity-detail screen is the structurally interesting one: an entity is a
*tree* (card + `arc.md` + `events/` group + `quests/<quest>/` nested group),
rendered as a sectioned list whose headings are the prettified subfolder names.

## 5. Editing UX

The editing surface is **raw markdown text, styled but never hidden** (ADR 8).
Three layers, in increasing order of payoff:

### 5.1 Helper toolbar (key-accessory row)

A quick-insert row above the keyboard, in two groups — one mechanism underneath
(insert-at-cursor, wrap-selection, prefix-line):

- **Structure:** H1/H2/H3, bullet list, numbered list, bold, italic. These are
  real markdown that the cards genuinely use (profile block; "Character",
  "Past", "Memories" sections).
- **Project tokens:** `[[`, `[`, `]`, `—` (em-dash), a `(emotion):` snippet.
  The phone keyboard makes exactly this punctuation painful, and it's what the
  prose conventions need.

### 5.2 Syntax highlighting (the recommended surface)

A custom `TextEditingController` overriding `buildTextSpan()` returns styled
spans: headers larger, `[[wikilinks]]` colored, `**bold**` bold — while the
buffer underneath stays raw markdown. Standard Flutter technique, tractable, and
it is what makes the editor "not just a bare text field" without becoming a
WYSIWYG.

**The differentiator:** the same highlighter should highlight *this project's*
conventions, not just markdown — dialogue lines matching `Name (emotion):`,
`[placeholders]`, em-dash conditional markers. No generic editor does this
(Obsidian doesn't know what an `(emotion):` line is). It is a concrete reason
this app exists rather than pointing Obsidian at the folder — and the same
matcher is reused directly as the convention linter (§6.1).

### 5.3 Everything else

- **Preview:** a **read-only** toggle rendering the buffer. Not an editing mode.
- **Explicit save + save-on-background,** with a dirty indicator. No
  autosave-per-keystroke — that's sync churn and conflict-copy bait.
- **RU/EN pairs:** one item with `[RU][EN]` tabs, RU default (original language
  first, per the loader's merge). A missing `.en.md` shows a "needs translation"
  badge; editing the empty EN tab is a **create-translation** action that creates
  that file. Writes go to the individual file (ADR 3).
- **Wikilinks:** `[[` triggers autocomplete over the loaded entity titles +
  aliases; tapping an existing `[[Title]]` in preview navigates to that entity.
  In scene files, wikilinks are lore references, never passage jumps
  (ARCHITECTURE §3.3). **Deferred to v0.2.**

**Excluded:** full WYSIWYG / live-preview-that-hides-markup. The conventions are
the content being proofread; hiding the markup hides the thing under review.

## 6. AI assist (M2, on the phone)

This is IDEA.md M2 arriving on mobile, and it is **already sanctioned**:
ARCHITECTURE §6 permits "network calls to AI providers explicitly configured by
the user," and ADR 2's "never authenticates" governs *sync*, not AI. Shape
decided in ADR 7: **direct API calls, user-configured key** (Android Keystore via
`flutter_secure_storage`).

### 6.1 Three layers — one needs no AI at all

| Layer | Needs AI? | Ships |
|---|---|---|
| **Convention linting** | **No** — pure regex | **v0.2** — same matcher as the §5.2 highlighter |
| **RU→EN translation** | Yes | first AI milestone |
| **Grammar / prose quality** | Yes | after translation |

**Convention linting is free, offline, and instant.** A real share of "styling
errors" is mechanically detectable: twee markup leaking in (`<<`, `>>`, HTML),
`<<=$var>>` where `[placeholder]` belongs, dialogue lines missing the `Name:`
shape, unpaired em-dash conditional markers, `[[wikilinks]]` pointing at
entities that don't exist. Zero API cost. It is the same code as the
convention-aware highlighter — build once, surface twice.

**Translation ships before grammar** (inverting the intuitive order) because it
is the cheaper of the two to build — see below.

### 6.2 The glossary is already free

ARCHITECTURE §3.2 requires the `aliases:` line to "include foreign-language names
(the imported lore carries RU + EN aliases)." So `readTitleAliases` across all
entities — **already on the v0.1 Dart port list for entity browsing** (§8) —
yields title + RU aliases + EN aliases. That is exactly the term list a
translator needs so "Селена" → "Selena" every time.

The translation context pack is therefore: **the RU file + that alias glossary +
the §3.3 prose conventions.** A few KB. Nothing new to build.

**Translation also has no diff problem:** the output goes into `.en.md`, *a file
that does not exist yet*. It is a create, not an edit — the create-translation
action already in §5.3. Generate → populate the EN tab → author edits → explicit
save. No diff UI.

### 6.3 Grammar/style: findings, not rewrites

Return a **structured findings list** (`line`, `issue`, `suggestion`,
`severity`) rendered as a tappable list that jumps to the line — not a rewritten
file. Rationale: a diff UI on a phone is real work; "check for styling/grammar
errors" is a findings request, not a rewrite request; and suggestions preserve
the author's voice. This sidesteps the diff problem for the second AI feature
just as the create-a-new-file path sidesteps it for the first.

### 6.4 Shape, model, cost

- **No official Anthropic Dart SDK** (official SDKs: Python, TypeScript, Java,
  Go, Ruby, C#, PHP). Flutter talks to the Messages API over **raw HTTPS** — a
  JSON POST. Not a blocker, but two things an SDK would otherwise provide must be
  hand-rolled: **SSE parsing for streaming** (needed — a full scene translation is
  long output) and retry/error handling.
- **Model:** `claude-opus-4-8` (1M context; $5/M input, $25/M output). Use
  `thinking: {type: "adaptive"}` — literary translation with glossary adherence is
  exactly the non-trivial case.
- **Cost is a non-issue.** A scene plus glossary and conventions is roughly 10K
  input tokens (Cyrillic tokenizes less efficiently than English — budget
  generously); the English output maybe 5K. **≈ $0.18 per scene translated.**
  Cents per day at realistic volume. Do not design around cost.
- **Skip prompt caching.** The glossary + conventions prefix is ~2K tokens, below
  Opus 4.8's 4096-token minimum cacheable prefix — it would silently never cache.
- **Context preview is mandatory,** not optional: ARCHITECTURE §6 requires
  showing what leaves the machine before sending. On a phone that's a scrollable
  sheet (this file, N glossary terms, the conventions) behind the send button.

**Cheap fallback, for the record:** the phone could merely *mark* files and let
the desktop batch-translate — the "needs translation" badge already exists, and
that path needs zero AI code on mobile. Kept as the option if the AI milestone
slips.

## 7. v0.1 walking skeleton

The thinnest end-to-end slice that exercises every hard part once:

1. Grant the repo folder (the §3.4 spike).
2. Read `lore-story.json` → `loreDir`.
3. Walk `loreDir` → categories → entities → entity tree (the Dart port subset, §8).
4. Browse to and open a card / sub-entry / scene file in the plain editor.
5. Edit → explicit save → atomic, byte-exact write (§3.2).
6. Re-open + desktop check → round-trip confirmed.

**In v0.1:** browse → open → edit → save round-trip; RU/EN toggle; helper
toolbar; syntax highlighting; conflict-file surfacing.

**v0.2:** convention linting, wikilink autocomplete.

**Out:** mention detection, lore graph, passages/twee, scene↔passage bridge, AI,
search, in-app sync, file watching, entity/folder creation or restructuring
(ADR 5).

## 8. Dart port

The port covers the **read subset** of the reference loader plus a **new write
path** the JS core never needed (it is read-only).

| Rule (`lib/lore.js`) | v0.1 |
|---|---|
| `walkCategory` — simple vs entity folder (`index.md`/`<folder>.md`), category = path, skip `media/` | **Required** |
| `buildNode` — `{overview, items, children}` tree, group = subfolder path, `prettify` | **Required** (entity detail) |
| `readTitleAliases` — title from `# heading`, `aliases:` line | **Required** — *doubles as the AI translation glossary (§6.2)* |
| Language pairing (`LANG_RE`, `byBase`, ru/en merge, `"<ru> — <en>"` title) | **Required** (RU/EN toggle) |
| `passageOf` (`scene ⇄ passage` comment) | Defer — bridge only |
| `findMentions` / `buildLoreGraph` | Defer — v0.2+ (graph feature; O(n²) regex) |

**New on the Dart side (no JS equivalent):**

- **Atomic UTF-8 writer** honoring ARCHITECTURE §5 (temp + rename; preserve EOL /
  trailing newline; explicit UTF-8).
- **Syncer-aware walk** — filter `.stfolder`/`.stignore`/`.stversions`, surface
  `*.sync-conflict-*.md` (§3.2).
- **Convention matcher** — powers both the §5.2 highlighter and the §6.1 linter.

**Anti-drift:** `test/fixtures/lore-model/` — lore folders with expected parsed
output — asserted against by **both** the JS reference and the Dart port. The
fixtures are the operative contract (ADR 4); when the model changes, the fixtures
change first and both implementations follow.

## 9. Project layout

```
lore-and-story/
  lib/                       # JS core (reference loader, parser, analysis)
  public/                    # desktop POC UI
  apps/
    mobile/                  # Flutter (Android) writing app  ← this doc
  scripts/
    update-goldens.js        # `npm run goldens` (outside test/ — see fixtures README)
  test/
    lore-model.test.js       # asserts lib/lore.js against the goldens
    fixtures/
      lore-model/            # shared golden fixtures (JS + Dart)  (ADR 4)
        normalize.js         # the projection the Dart port must reproduce
        cases/               # 01-simple-entities … 04-language-pairs
```

The fixtures exist and the JS side asserts against them (`npm test`, zero deps —
`node:test`). See [test/fixtures/lore-model/README.md](test/fixtures/lore-model/README.md)
for what each case pins, the normalization contract the Dart port must reproduce,
and one **known discrepancy between `lib/lore.js` and ARCHITECTURE §3.2** that the
fixtures surfaced (the entity card appears in its own `children[]`). The goldens
pin current behavior; resolve that deliberately before the port copies it.

## 10. Risks

| # | Risk | Mitigation |
|---|---|---|
| A | Storage access decides how close the Dart port stays to the reference | All-files access + real paths behind `RepoStorage` (ADR 1, §3.1) |
| B | Concurrent writes with a live syncer → partial files / spurious conflicts | Atomic write, explicit save, re-scan on resume, surface conflict copies (ADR 2) |
| C | RU/EN merge collapsed into one file on save → corrupts bilingual model | Writes always target the individual file (ADR 3) |
| D | Two implementations of one contract, no shared code → drift | Golden fixtures both loaders assert against (ADR 4) |
| E | Scope creep toward "rebuild the desktop tool on a phone" | Phone editing scope line (ADR 5) |
| F | **External-syncer dependency is less stable than ADR 2 assumes** — Syncthing-Android was discontinued, the Catfriend1 fork changed hands to researchxxl, old repo pruned | Watch it; `RepoStorage` keeps embedded git (§3.3) a cheap pivot rather than a rewrite |

## 11. Open questions (post-v0.1)

- Should syncer-style exclusions be user-configurable in `lore-story.json`
  (e.g. an `ignore` list) rather than hardcoded?
- The drift-hash bookkeeping file (ARCHITECTURE §3.3) becomes a mobile concern
  only once the scene↔passage bridge exists — not in scope now.
- Read-only passage reference on mobile (the "reads passages read-only" half of
  M5): which representation the phone shows, and whether it needs the twee parser
  ported or just renders recovered scene files.
- How much of the lore graph is worth computing on-device (mention surfacing)
  vs. leaving to the desktop tool?
- Does the *desktop* AI integration want the same API-key shape as mobile (ADR 7),
  or does MCP + external agent still make sense there? ADR 7 answers this for the
  phone only.
