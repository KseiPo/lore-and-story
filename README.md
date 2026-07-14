# Lore & Story — POC

Risk-probe proof of concept for the app described in [IDEA.md](IDEA.md): a visual
story-flow + lore companion for file-based Twine/SugarCube projects. The file
system is the source of truth; the graph and all analysis are derived views.

## Run

```
npm install
npm start        # http://localhost:3987
```

## Configure (`config.json`)

Copy [config.example.json](config.example.json) to `config.json` (gitignored)
and point it at your project. The config is re-read on every request: edit it
and click **Rescan** in the UI (or reload the page) — no server restart needed.

| Key | Meaning |
|---|---|
| `storyDir` | Folder scanned recursively for `.twee`/`.tw` files |
| `loreDir` | Folder with lore markdown (subfolders = categories) |
| `linkMacros` | Custom widgets whose first argument is a passage target (e.g. `backLink`) |
| `codeDirs` | Script folders scanned for string literals (data-driven navigation) |
| `dynamicTags` | Passage tags meaning "reached dynamically at runtime — never an orphan" |

## What it does

- Parses all passages and links (`[[...]]`, `<<link>>`, `<<button>>`, `<<goto>>`,
  `<<include>>`, configured custom widgets); re-parses live on every file save (SSE).
- Renders the flow graph (Cytoscape + dagre), colored by folder, with focus mode
  (click a node → its neighborhood), search, and per-passage detail incl.
  `vscode://` deep link to the exact file and line.
- Analysis: orphans, broken links, dynamic links, dead ends — with three layers of
  false-positive suppression for data-driven stories:
  1. string literals in `codeDirs` matching passage names ("reached from code"),
  2. `dynamicTags` exemptions,
  3. composed-name heuristic: names assemblable from code literals
     (`starName + ' - ' + locationName`) are flagged as such, not as orphans.
- Lore browser: markdown entries with alias-based mention detection across passages
  (sample data in `lore/`).

## Result on a real project (367 passages)

Parse ~50 ms, layout ~250 ms. Orphan false positives went 139 → 2 after the three
suppression layers; both remaining findings were genuine. See IDEA.md → "POC findings".
