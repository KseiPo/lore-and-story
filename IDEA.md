# Lore & Story — App Concept

*Working title. Status: concept + risk-probe POC. Last updated: 2026-07-14.*

## Problem

Writing a large visual novel in Twine/SugarCube today forces a choice between two broken workflows, plus external tools for lore:

1. **Twine GUI** — great visual overview of passage flow, but becomes slow and buggy as the story grows; the GUI *is* the database (one giant archive blob), so everything degrades together.
2. **Dev workflow** (VSCode + bundler + watch mode + one passage per file) — scales well, git-friendly, but has no visual overview: easy to leave a passage orphaned/unlinked and never notice.
3. **Lore lives elsewhere** (Notion, Google Docs) — disconnected from the story. Using AI means a triple-copy loop: copy lore/passage into ChatGPT → discuss/correct there → copy result back to VSCode → reformat.

## Core insight

**The file system stays the single source of truth. Everything else — the graph, the analysis, the lore cross-references — is a *derived view* computed by parsing the files.**

This one decision eliminates the sync/corruption problems of hybrid tools, keeps the project git-friendly and AI-readable, and means the visual layer can never diverge from reality.

## What the app actually is: a writing pipeline

Four stages; the app's job is to remove friction *between* them:

| Stage | Where | What happens |
|---|---|---|
| 1. **Write** | Phone or desktop | Write and *revise* real markdown files: lore entries and plain-prose scene files (no separate drafts area — the author keeps returning to the same character/location/scene files) |
| 2. **Transform** | Desktop | Turn a scene into real passages (or propagate scene edits into existing ones): split, link, AI-assisted grammar / translation / lore-consistency — always as reviewable diffs |
| 3. **Verify** | Desktop | Visual graph: where am I in the flow, orphans, broken links, unreachable clusters, contradictions |
| 4. **Polish** | VSCode | Media, widgets, macros, final formatting |

The single highest-value feature (above the graph): **killing the triple-copy AI loop.** Because story + lore + drafts live in one repo, the app can auto-build AI context (passage + character sheets of everyone mentioned + glossary + style guide) and apply results in place.

## Architecture decisions (agreed so far)

- **Files = source of truth.** Twee passages as-is; lore as markdown files with light conventions (folders = categories, e.g. `lore/characters/`, `lore/places/`; optional `aliases:` line for mention detection).
- **Step zero (no app needed):** move lore out of Notion/Google Docs into markdown in the story repo. Immediately useful — any AI tool pointed at the repo can use it.
- **Mobile edits markdown, never twee.** Phone reads and edits lore entries and scene files (the author's actual writing surface) and gets read-only passages for reference. Twee editing stays desktop-only. Single author + small per-entity files keep sync conflicts rare; when they happen they surface as the syncer's conflict copies.
- **The story text lives in two representations** (decided 2026-07-14): plain-prose *scene files* in `scenes/` mirror twee passages by name. Scenes are for writing, revising, AI editing and translation; passages are the playable form. Existing passages get their scene files *recovered* by stripping markup; afterwards an AI-assisted, review-first bridge propagates changes between the layers. No separate drafts inbox — the author edits real files.
- **Sync transport is dumb:** git (GitJournal proves git-in-Flutter works on Android) or Syncthing/Dropbox. No backend, no accounts, offline-first for free. Android only for now.
- **Editing scope line:** the app edits *story text and structure* (prose, lore, passage links); VSCode edits *code* (widgets, macros, JS/CSS, bundler). Deep-link into VSCode (`vscode://file/...:line`) from any passage node. Never compete with the IDE.
- **Parser stays shallow on purpose:** extract passages + links (`[[...]]`, `<<link>>`, `<<button>>`, `<<goto>>`, `<<include>>`), leave everything else untouched. Dynamic links (`<<goto $var>>`, computed targets) are marked honestly as "dynamic" rather than pretending the graph is complete.

## Stack (leaning, not final)

- **Mobile capture app:** Flutter (Android first).
- **Desktop (graph + transform + AI):** web technology — the mature graph ecosystem (Cytoscape, dagre/elkjs, React Flow) is all JS; Dart graph libs are hobby-grade. Either a local web app, a Tauri shell, or Flutter-with-WebView for the graph pane. Decide after the POC.
- **One universal graph-view library, used twice:** the story flow (passages + links) and the lore web (entities + relations/mentions) are the same visualization problem — directed graph, focus mode, search, clustering, theming. Build it once as a shared module; both views consume it.
- The two apps share no UI code; they share the **data contract — the repo itself** (see [ARCHITECTURE.md](ARCHITECTURE.md) for the contracts).

## Scale requirements (from the real story)

Reference project: the author's current in-progress VN — **367 passages (302 story + 65 widget/utility), chapter 1 not yet finished.** Full story plausibly 1,500–3,000+ passages. Therefore, from day one:

- Full-graph hairball is a non-goal. Default view clustered by file/folder (files already encode chapters/scenes), expand on demand.
- **Focus mode** (selected passage + N hops) as primary navigation; search-first, not pan-first.
- Live re-parse on save is cheap at any realistic size; rendering/layout is where scale bites.

## Prior art

- **Twee 3 Language Tools** (VSCode ext): the standard dev-workflow companion (syntax, diagnostics); covers editing, not flow overview or lore.
- **articy:draft**: commercial flow+lore tool; validates demand, but heavyweight, proprietary, not Twine-native.
- **Obsidian**: covers lore half (markdown + graph + backlinks), knows nothing about twee links.
- Niche "twee-on-disk + derived graph + lore + AI context packs" appears unoccupied.

## Risks

1. **Graph readability/perf at scale** — the boss fight; the exact thing that killed Twine GUI. Mitigate with clustering + focus mode.
2. **Parser coverage** — custom widgets/macros that navigate produce false orphans; link extraction must be extensible (per-project regex/plugin config).
3. **Scope creep toward "rebuild Twine"** — antidote: the editing scope line above.
4. **Sync ambitions** — antidote: drafts-inbox model; revisit only if capture-only mobile proves insufficient.

## POC findings (2026-07-14, tested on the real story)

Ran the POC in this repo against the author's real story project (367 passages, 302 story):

- **Performance is a non-issue at this scale:** full re-parse of 234 files ≈ 50 ms; dagre layout of 301 nodes ≈ 250 ms. Live re-parse on every save is viable; extrapolating, even 3,000 passages stays interactive (layout will need clustering long before parsing hurts).
- **The real boss fight is not the graph — it's data-driven navigation.** Only ~55% of navigation is static links; the rest goes through variables, TS data files (`passage: 'Selena - ...'`), and composed names (`starName + ' - ' + locationName`). Naive analysis reported **139 false orphans out of 301 passages** — useless noise.
- **The noise is fixable with generic, configurable techniques.** Three layers took it to **2 orphans, both genuine** (`Test` dev passage; one name composed with a number): ① scan configured script dirs for string literals matching passage names; ② exempt configured tags (`dream`); ③ composed-name heuristic — word-break segmentation of passage names over the literal corpus (case-insensitive). Broken links went 8 → 0 (all were parser gaps: quoted wiki targets `[[Text|'Name']]`, bare `<<include Victory>>`, `<<goto setup.fn()>>` → dynamic).
- **Parser must read *all* passages for reachability** (nav widgets and specials link too), and per-project `linkMacros` config (e.g. `backLink`) is essential.
- **Stored references** (`<<set $minigameReturn to 'Passage'>>` … later `<<goto $minigameReturn>>`) are a first-class link kind: an assignment whose string equals a passage name is an edge from the assigning passage. Found all 10 minigame/event returns in the real story with zero false positives (non-matching strings are ignored, never "broken").
- Conclusion: the concept is validated; the differentiating hard part (and moat) is the **analysis layer that understands data-driven SugarCube projects**, not the graph rendering.

## Packaging decision (2026-07-14): one product, two thin shells

"One app vs several apps" is the wrong framing — the unit of integration is the
**repo (data contract) + shared JS core** (parser/analysis/lore), not a single binary.

- **Desktop** = the current Node + web UI, evolved. When packaging matters, wrap it
  in **Tauri** (native folder picker, tray, single .exe) — the web UI carries over
  unchanged. Until then `npm start` + browser is fine for a personal tool. A folder
  picker + recent-projects list can be added to the POC *without* Tauri (server-side
  directory-browse API) to kill manual config.json editing.
- **Mobile (Android)** = separate small writing app (Flutter), later. Reads and
  edits lore + scene markdown, reads passages read-only. Shares zero UI with
  desktop, shares the data contract.
  (Alternative to evaluate when we get there: Tauri 2 also targets Android, which
  would make it literally one codebase — but Android file access/background behavior
  there is younger than Flutter's; decide at mobile time, not now.)
- **Sync is not an app feature.** Files-as-source-of-truth means any file syncer
  works underneath: **Syncthing** (recommended: free, P2P, no account, great on
  Android + Windows) or Dropbox for the phone↔desktop folder; git stays the desktop
  authoring history as today. The app only watches files and re-parses — it never
  implements sync, merging, or accounts. Embedded git-on-mobile (GitJournal-style)
  only becomes relevant if one-tap commits from the phone are ever wanted.

## Roadmap (follows the author's writing workflow)

1. ~~**POC (risk probe):** parse the real story, render graph, measure perf, validate analysis signal-vs-noise.~~ ✅ done — see findings above. The review UI is deliberately *last* in the daily workflow, so the POC covers the final stage already.
2. **M0 — Import & extraction:** migrate lore from Notion/Google Docs into `lore/` (export → convert → organize); *recover* plain-prose scene files from all existing twee passages (strip macros/HTML, AI-assisted where mechanical stripping isn't enough); create `lore-story.json` in the story repo.
3. **M1 — Writing workbench:** edit the real markdown files in-app — lore entries and scene files; category templates (character, location, faction); `[[wikilink]]` autocomplete; **lore graph** as the first consumer of the shared graph-view library; project picker + recent projects.
4. **M2 — AI assist:** proofread / translate / consistency-check on the file being edited, with auto-assembled context packs (mentioned characters' sheets, glossary, style guide) shown before sending. Kills the copy-paste loop.
5. **M3 — Scene↔passage bridge:** new scene → new passage(s) (split, link, project macros); drift detection between existing scenes and passages; AI-assisted propagation of edits in both directions — always as reviewable diffs.
6. **M4 — Review maturation:** flow-graph clustering/collapse by folder, story-only polish; flow view moves onto the shared graph-view library.
7. **M5 — Mobile (Flutter, Android):** edit lore + scenes, read passages; Syncthing/Dropbox folder sync underneath.
8. **Later ideas:** MCP server (`get_lore("Mira")`, `find_broken_links()`) for Claude Code etc.; other formats (Harlowe, Ink, Yarn) via pluggable link extractors; Tauri packaging.

## Open questions

- Which AI provider/integration shape for v2 (API keys in-app vs. MCP + external agent vs. both)?
- Lore file conventions: how much structure (frontmatter?) before it stops feeling like plain writing?
- Does the transform step need a dedicated side-by-side draft↔passages UI, or is it an AI conversation with file edits?
- Tauri vs. local web app vs. Flutter+WebView for desktop shell.
