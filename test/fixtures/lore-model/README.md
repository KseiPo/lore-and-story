# Golden fixtures — the lore model contract

These fixtures are the **operative contract** for the lore model
([ARCHITECTURE.md](../../../ARCHITECTURE.md) §3.2–3.3), asserted against by two
independent implementations that share no code:

| Consumer | Implementation | Runner |
|---|---|---|
| Desktop / core | `lib/lore.js` (reference) | `npm test` → `test/lore-model.test.js` |
| Mobile | the Dart port in `apps/mobile/` | *(pending — see [MOBILE.md](../../../MOBILE.md) ADR 4, §8)* |

Prose docs describe the contract; **these files pin it.** When the two disagree,
that is a bug in one of them — and finding out which is the entire point.

## Layout

```
lore-model/
  .gitattributes      # bytes must not be rewritten — see below
  normalize.js        # the projection both implementations must reproduce
  README.md
  cases/
    01-simple-entities/     lore/…  expected.json
    02-entity-folders/      lore/…  expected.json
    03-sub-entry-tree/      lore/…  expected.json
    04-language-pairs/      lore/…  expected.json
```

Each case is a self-contained `lore/` tree plus the normalized model it must
produce. The trees are **synthetic but shaped like the real story** — deliberately
so: real content would churn with the story repo, drag its size in, and couple
two repos that are otherwise independent.

## What each case pins

| Case | Contract clauses |
|---|---|
| `01-simple-entities` | `.md` in a category is a simple entity; title from `# heading`; **title falls back to the filename slug** when there is no heading; `aliases:` optional; aliases always include the title, deduped. Also pins the **EN title + RU aliases** shape the real cards use — which is what makes the alias index double as an AI translation glossary (MOBILE.md §6.2). |
| `02-entity-folders` | card via `<folder-name>.md` **and** via `index.md`; a folder **without** either is a nested *category* (`characters/secondary` → carrie's category), not an entity; `media/` skipped at both category and entity level. |
| `03-sub-entry-tree` | root sub-entry (`arc.md`); `events/` group; **nested** section with its own overview card (`quests/relationship-quest-1/`); `group` = subfolder path; folder names prettified into section titles; `scene ⇄ passage` extraction. |
| `04-language-pairs` | `ru`+`en` merge into one item titled `"<ru> — <en>"` (**original first**); `ru`-only keeps its RU title (the *needs translation* signal); `en`-only; `orig` (no suffix); `passage` read from the RU variant of a pair. |

## The normalization contract (`normalize.js`)

`expected.json` is not raw `loadLore()` output. Two transforms — **a Dart port
must reproduce both** or it cannot compare against these files:

1. **`file` is dropped.** It is the only absolute path in the model. Everything
   else (`id`, `relDir`, `langs[].file`) is already relative to `loreDir`.
2. **`text` becomes `textSha`** — first 16 hex chars of the UTF-8 sha256. Keeps
   the goldens small, and pins **decoding and line endings exactly**. That is the
   point, not a side effect: the corpus is Cyrillic and the mobile writer must
   round-trip bytes (ARCHITECTURE §5). A port that decodes UTF-8 wrongly, or
   normalizes newlines, fails here rather than silently corrupting the author's
   files.

Entries are sorted by `id` so the comparison does not depend on directory
iteration order.

## ⚠️ Do not let git rewrite these bytes

This repo is cloned with `core.autocrlf=true` on Windows. Without the
`.gitattributes` in this directory (`* -text`), checkout would convert LF→CRLF
and **every `textSha` would break on a fresh clone**. If the goldens ever fail
en masse on a new machine with no code change, check this first:

```sh
git check-attr text -- test/fixtures/lore-model/cases/01-simple-entities/lore/characters/frank.md
# want: text: unset
```

## Workflow

```sh
npm test            # assert both directions
npm run goldens     # regenerate expected.json from lib/lore.js
```

**A golden diff is a contract change.** `npm run goldens` exists to *show* you
that diff, not to make failures go away. The order is: decide the contract →
update the fixture → make both implementations follow (ADR 4). Regenerating to
silence a red test inverts that and defeats the mechanism.

`scripts/update-goldens.js` lives outside `test/` on purpose: `node --test test/`
executes every `.js` it finds there, so keeping the generator inside would let the
suite rewrite the very goldens it is asserting against (and race with itself doing
it).

## Resolved contract discrepancy (was: card in own `children[]`)

**The entity card is excluded from its own `children[]`** — code, goldens, and doc
now agree. ARCHITECTURE §3.2/§3.2a state the card "is **not** a sub-entry of
itself"; `lib/lore.js` enforces it with the `if (base !== cardBase)` guard on the
`flat.push(...)` (`lore.js:67`), and these goldens pin that behavior (e.g.
`selena` has `children: []`).

History: earlier, `buildNode` pushed *every* file into the flat list before the
`base === cardBase → continue` guard that already excluded the card from `items[]`,
so an entity's card leaked into its own `children[]`. It was **latent** on the
desktop (the UI renders `tree`, never `children`, and `buildLoreGraph` dedups its
edges), but it would have tripped the Dart port: an implementation written from
§3.2 would exclude the card and mismatch these goldens — looking like a port bug
rather than the reference/doc disagreement it was. Resolved by fixing `lore.js` to
match §3.2 (PRD open question O1), then regenerating the goldens off the corrected
loader. **The goldens now pin the doc's contract, not legacy behavior.**
