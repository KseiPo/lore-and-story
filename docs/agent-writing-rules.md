# Writing rules for AI agents: lore & scene files

This repository holds the lore and the prose scenes of a visual novel. The author
reads and edits it on a phone with the **Lore & Story** app, and Syncthing syncs it
between devices. The app works everything out from **file names, folder structure
and a few inline markers**. A file that breaks these rules doesn't cause an error:
it gets misfiled, silently hidden, or flagged by the app's linter. Follow every rule
below whenever you create, edit, rename or translate anything here. If a request
would break a rule, say so and ask the author before going ahead.

Terms:

- **lore root**: the folder the app opens as lore. By default that's the repo root;
  `lore-story.json` can point it at a subfolder (`"loreDir": "lore"`). All paths
  below are relative to the lore root.
- **entity**: one lore subject (a character, station, race…), stored either as one
  file or as a folder.
- **card**: an entity's main description file.
- **sub-entry**: any other file inside an entity folder (events, quest stages,
  design notes).
- **scene**: plain-prose story text. **Event** is this project's word for a
  standalone scene.
- **passage**: the playable twee version of a scene. It lives in the game code, not
  here.

## 1. Ground rules

1. **Change only what you were asked to change.** Keep every other byte as it is:
   encoding, line endings, trailing newline, blank lines, heading and emphasis
   style. Never run a formatter or markdown linter (Prettier, markdownlint…) over
   these files, and never re-wrap paragraphs. The app writes byte-exact, and a
   whole-file reformat reaches every device as a full rewrite, which invites sync
   conflicts.
2. **Read a file again right before you edit it.** The author may have changed it
   on the phone since you last looked.
3. **UTF-8, and non-ASCII is content.** Cyrillic, `—` (em dash), `⇄`, `·`, `«»` and
   `…` all carry meaning; never transliterate, replace or "normalize" them. New files
   use UTF-8 without a BOM and LF line endings.
4. **Every `.md` file under the lore root is lore.** Don't create notes, plans,
   TODOs, summaries, READMEs or index files there, because the app lists every one of
   them as an entity. Keep scratch work outside the lore root or in a dot-folder
   (for example `.agent-notes/`), which the app ignores. That applies to this rules
   file too.
5. **No invented structure.** No YAML front matter, no metadata blocks, no
   generated indexes. Structure comes only from folders, file names and the
   conventions below.
6. **Ask before restructuring.** Get the author's go-ahead before you rename, move,
   delete, split, merge or promote a file. The author may have it open with unsaved
   edits in the app, and every rename ripples through sync. Never rename a file only
   to "fix" its name.
7. **Prose files never contain game code.** No SugarCube macros, no HTML, no
   `$variables`: twee exists only in the final passages. Don't edit `.twee` or
   script files unless the author explicitly asks.
8. **Leave the sync and app machinery alone** (§7, §8).

## 2. Folder layout

### 2.1 Categories

The top-level folders under the lore root are the **categories** the app shows on
its home screen (for example `characters`, `stations`, `races`, `world`, `plot`,
`quests`, `promotion`, `meta`). Put new material into an existing category, and ask
before you create a new top-level folder.

- A subfolder without a card is a sub-category. The app lists its entities under
  their top-level category, so `characters/secondary/carrie.md` shows up under
  *characters*.
- A `.md` file directly in the lore root lands in a synthetic **general** bucket.
  Don't put lore there, and don't name a folder `general`.

### 2.2 Entities: one file or a folder

- **Simple entity**: a single file, such as `characters/mira.md`. Use this form
  while the entity has nothing but its card.
- **Entity folder**: a folder whose card is named exactly **`<folder-name>.md`**,
  such as `characters/selena/selena.md`. Everything else inside the folder is that
  entity's content. (`index.md` also works as the card, but the existing lore uses
  `<folder-name>.md`. Never have both.)

**The card never has a language suffix.** If `selena/` contains only
`selena.ru.md`, the app does not treat it as a card. It treats `selena/` as a
sub-category, and every file inside it, events included, turns into a separate
loose entity.

```
characters/
  mira.md                          simple entity
  secondary-characters.md          list of minor characters
  selena/                          entity folder
    selena.md                      the card (same name as the folder)
    arc.md                         design notes (sub-entry at the entity root)
    media/                         images for the card and all its sub-entries
      portrait.png
    events/                        standalone scenes, one scene per file
      dock-inspection.ru.md
      dock-inspection.en.md
    quests/
      relationship-quest-1/        one quest = an ordered chain of scenes
        relationship-quest-1.md    quest overview card (same name as the folder)
        01-hobby.ru.md
        02-minigame.ru.md
stations/
  <station>/
    <station>.md                   factual station card
    events/                        the station's own intro / first-visit scenes
promotion/
  <post>.ru.md, <post>.en.md       marketing texts, one Patreon post per file
```

### 2.3 What goes inside an entity folder

Keep these kinds of content apart, and never mix them in one file:

- **Card** (`<slug>.md`): the character bible. It holds the profile block (type,
  faction, age, occupation, location, want / need / fear), then character, past,
  memories and the portrait prompt. Keep it compact and factual. The app shows it at
  the top of the entity screen.
- **Design** (`arc.md`, at the entity root): relationship progression, planned
  events, quest outlines. This is the author's reference material, not prose and
  not canon.
- **Events** (`events/<slug>.<lang>.md`): written scenes, one scene per file.
- **Quests** (`quests/<quest>/`): an ordered chain of scenes. Each quest has an
  overview card `<quest>.md` and one file per stage (`01-…`, `02-…`). Stages are
  ordinary scenes.
- **Images**: in `media/` at the entity root.

The same split applies to locations (station card, description, events) and to any
entity that builds up written content.

Every subfolder becomes a section in the app. The section heading is the folder name
with `-`/`_` shown as spaces, in the same case. When a folder needs a proper title
or a description, give it an overview card: `<folder>/<folder>.md` with a
`# Title`. Sections can nest (`quests/<quest>/`), and a sub-entry can also sit
directly in the entity folder, like `arc.md`.

### 2.4 Who owns an event

- An event belongs to the character who **drives** it. Carrie's «Конец смены» lives
  in `characters/carrie/events/` even though it happens in her bar.
- A location owns only its own intro and first-visit scenes
  (`stations/<station>/events/`). Locations never own character events; they refer
  to people through staff lists with `[[wikilinks]]`.
- Minor characters stay as entries in `secondary-characters.md` until they have
  content of their own. At that point they get their own entity folder in the same
  category, and the `Type` field on their card marks the tier.
- `promotion/` holds marketing texts: one Patreon post per file, as paired
  `.ru.md`/`.en.md` files where both languages exist. Station lore *articles* are
  marketing, so they belong here; station cards keep only factual canon.
- Put scenes under the entity that owns them. The app offers RU/EN tabs and
  translation only there.

### 2.5 Promoting a simple entity to a folder

When a simple entity needs events or quests (ask the author first):

1. Create `<slug>/` next to `<slug>.md` and move the card to `<slug>/<slug>.md`
   without changing its content, except for step 2.
2. The card is now one level deeper, so prefix every **relative** image path in it
   with `../`: `![](media/frank.jpg)` becomes `![](../media/frank.jpg)`. Leave
   `http(s)://` and absolute paths alone. The app's own "Promote to folder" action
   does exactly this.
3. Then add the sub-entries.

Promote only top-level simple entities. If the card has a language suffix
(`frank.ru.md`), ask the author how to name the folder.

### 2.6 Names the app treats specially

Don't use these names by accident:

| Name | What the app does |
| --- | --- |
| `media/` | Treats it as an image folder and never reads it for text, so a `.md` inside is invisible. |
| anything starting with `.` | Ignores it (hidden files, `.git`, `.stversions`, dot-folders). |
| `<folder>/<folder>.md`, `index.md` | Uses it as that folder's card or overview, not as a normal entry. A sub-entry named after its own folder (`events/events.md`) becomes the section overview. A translation next to an entity card (`selena/selena.en.md`) is **invisible**. |
| `*.sync-conflict-YYYYMMDD-HHMMSS-XXXXXXX.md` | Shows it as a Syncthing conflict copy, never as lore (§8). |
| `general/` (top level) | Merges it with the lore-root "general" bucket. |
| `ai-prompts.md`, `lore-story.json` (repo root) | Reads them as app configuration (§7). |

## 3. File names

- **Slug**: lowercase Latin letters, digits and hyphens only, such as
  `dock-inspection`, `relationship-quest-1` or `the-wandering-fox`. No spaces,
  capitals, Cyrillic, apostrophes or other punctuation; the app's own create buttons
  produce only these characters. Use a short English slug even for a Russian scene
  (for «Проверка в доке», `dock-inspection`), and English spellings for names
  (`selena`, `mira`). The file name is only an ID. The name the app displays is the
  `# Title` inside the file, which can be in any language.
- **Language suffix**: `.ru.md` or `.en.md` (lowercase) after the slug. Both files
  of a pair share exactly the same slug.
- **Cards take no suffix.** That covers entity cards, simple entities, and section
  or quest overviews (§4).
- **New sub-entries always get a suffix**, normally `<slug>.ru.md` because Russian
  is the default authoring language. The app treats a suffix-less sub-entry as
  "language not assigned yet".
- Never keep both `x.md` and `x.ru.md` / `x.en.md` in the same folder.
- **Order**: the app lists the items in a section alphabetically by file name. For
  an ordered chain, number the files with zero-padded prefixes: `01-`, `02-` …
  `10-`.
- Image files follow the same rules (`portrait.png`, `selena-dock.jpg`), with no
  spaces.

## 4. Languages (RU / EN)

- **One language per file.** A translation is a separate file next to the original,
  with the same slug: `dock-inspection.ru.md` and `dock-inspection.en.md`. Never put
  both languages in one file, and never merge a pair.
- **Pairing works only for sub-entries inside an entity folder** (events, quest
  stages, sub-entries at the entity root). The app shows the pair as one item titled
  `<RU title> — <EN title>`, with RU/EN tabs.
- A lone `.ru.md` shows a "needs translation" badge. That badge is an intended to-do
  signal, not an error, so don't create empty or stub `.en.md` files to clear it. A
  lone `.en.md` is also fine: it's an English-only or English-original scene.
- **Cards are single-language files with no suffix**: entity cards, simple entities,
  and section or quest overviews. The app doesn't pair them. A translated copy next
  to an entity card is invisible, and `mira.ru.md` plus `mira.en.md` at category
  level show up as two separate entities. Put a card's names in both languages into
  its aliases line instead (§5.1). The exception is `promotion/` posts: they are
  paired files by decision, and the app simply lists both.
- The app's own "New entity" button creates simple entities as `<slug>.ru.md`. Those
  files work too; leave them as they are.

### 4.1 Translating

Follow the same rules as the app's built-in AI translation, so that both produce the
same kind of output:

- **Translate only the human-readable prose.** Keep the markdown structure
  (headings, lists, emphasis, blank lines, paragraph breaks) and every marker
  exactly as it is. The translation should line up with its source paragraph for
  paragraph.
- **Names**: use the glossary, meaning every card's `# Title` plus its aliases line,
  so each name comes out the same everywhere.
- **Dialogue**: translate the speaker name (via the glossary), the emotion and the
  phrase, and keep the `Name (emotion): ` shape.
- **Inner monologue**: `Мысль:` becomes `Thought:`, and the reverse.
- **Placeholders**: translate the words inside and keep the brackets. `[имя героя]`
  becomes `[hero's name]`.
- **Passage and choice links**: translate the label before `->` or `|`. **Never**
  translate or change the passage name after the separator; it's an identifier.
- **Return links**: translate the label after `<-`. The return type before it
  (`back`, `wake up`) never changes.
- **Conditionals**: keep the markers (`— если`, `— иначе —`, `— конец условия —`)
  as they are, and translate the condition text and the branch prose.
- **Lore wikilinks** `[[Title]]`: use the entity's name in the target language only
  when it is one of that entity's title or aliases, so the link still resolves.
  Otherwise leave it unchanged.
- **The `scene ⇄ passage` comment**: keep the passage name and switch
  `lang: ru` ↔ `lang: en`. Don't add the comment if the source doesn't have one.
- **Re-translating over an existing translation throws away the author's edits to
  it.** The app asks before replacing a translation, and you should too: either get
  confirmation, or update only the paragraphs whose source actually changed.

## 5. File anatomy

### 5.1 Entity card

- **Line 1**: `# <Title>`, the canonical display name (the app uses the first `# `
  heading in the file). If there is none, the app falls back to the file name.
- **Line 2, the aliases line** (optional, strongly recommended): it starts at
  column 0 with `aliases:`, followed by comma-separated names. List every form the
  entity goes by, in Russian and English, plus nicknames and callsigns (for example
  `aliases: Селена, Selena Vance`). Only the first such line counts, and a name must
  not contain a comma. Aliases drive `[[wikilink]]` resolution and autocomplete,
  mention detection, and the AI translation glossary.
- **Body**: free markdown. A typical card has a profile block followed by `## `
  sections (Character, Past, Memories, Portrait prompt…).
- In a profile block, write `**Type**: value` (colon outside the bold) or use a list
  item (`- **Type:** value`). The app's linter flags a line that starts with
  `**Type:** value` as a dialogue line missing a space. Don't mass-rewrite existing
  cards just for this.
- Titles and aliases must not contain `[[`, `]]`, `->`, `<-` or `|`, because a name
  containing them can't be wikilinked.

The app reads the aliases line only on **entity cards**. Sub-entries and overviews
use just their `# Title`.

### 5.2 Scene / event file

```markdown
# Проверка в доке

<!-- scene ⇄ passage: "Selena - Dock inspection" · lang: ru -->

Селена (спокойно): Иногда техника чувствует, когда на неё злятся.
```

- **First line**: `# <Scene title>`, which the app shows as the item's name.
- **The mapping comment** (optional) ties the scene to its twee passage. Its exact
  form is `<!-- scene ⇄ passage: "<Passage Name>" · lang: ru -->`, with a literal
  `⇄` (U+21C4), straight double quotes around the passage name, and ` · ` (U+00B7).
  Both language files carry the same passage name; only `lang:` differs. **Never
  invent a passage name.** Add the comment only when the author gives you the name
  or it exists in the game code. Without the comment, a scene maps to a passage by
  its title or file name.
- Then plain prose, following the conventions in §6.

### 5.3 Multi-passage scenes

When one story moment is split across several passages for UX reasons, keep it as
**one file**:

- Give each passage its own `# <Passage Name>` section, each with its own mapping
  comment.
- Link between sections with the passage-link form (§6.4).
- Write branch variants inside one passage (the "choices" widget) as `####` headings
  within that section.

The app titles the file after its first heading. The author's
`on-the-crossroads.en.md` is the reference example.

### 5.4 Allowed markdown

- Headings: `#` for the title, `##` / `###` for sections, `####` for branch variants.
- `**bold**` and `*italic*` / `_italic_`.
- `- ` and `1. ` lists.
- Paragraphs separated by blank lines.
- Images (§6.8).

Everything else stays plain text. The app's editor shows raw markdown with
highlighting and is never WYSIWYG, because the conventions below are part of what
the author proofreads.

## 6. Prose conventions

### 6.1 Dialogue

`Name (emotion): phrase.` The emotion is optional.

```
Селена (спокойно): Иногда техника чувствует, когда на неё злятся.
Carrie: Last call!
```

- The speaker name starts the line as plain text: not bold, not italic, not a
  wikilink. Those forms lose the dialogue highlight, and `**Name:**` is flagged.
- Keep names to 40 characters or fewer, with no `.`, `!`, `?` or `:` inside. For
  example, `Dr. Julia:` isn't recognized as dialogue.
- **A space after the colon is required.** `Frank:hello` is flagged.

### 6.2 Inner monologue

Write `Мысль: …` in Russian files and `Thought: …` in English files, the same way as
a dialogue line. An emotion is allowed (`Мысль (устало): …`). Don't use italics: the
old `*Thought:*` form is flagged by the app.

### 6.3 Variable placeholders

Put readable words in square brackets: `[имя героя]`, `[награда]`,
`[станция назначения]`, `[hero's name]`. Never write `<<=$var>>` or a bare `$var`.

### 6.4 Player choices and passage links

- `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]`: the label goes
  before the separator and the exact target passage name after it.
- A choice without a target yet is just bold text: `**Начать атаку**`.
- These old forms are retired; never write them: `**Choice** _(→ Passage Name)_`
  and `**Label** _(↩ back)_`.

### 6.5 Return links

Some widgets send the reader back instead of forward to a named passage:

- `[[back<-Label]]` returns to the previous passage (`<<linkBack>>`).
- `[[wake up<-Label]]` ends a dream (`<<wakeupLink>>`).

The return type comes before `<-` and the label after it. The arrow direction
carries meaning: `->` and `|` always mean "forward to a named passage", and `<-`
always means "go back, no target".

### 6.6 Lore wikilinks

`[[Title]]` with **no separator** refers to a lore entity. Title must match that
entity's `# Title` or one of its aliases (case-insensitive); tapping the link in the
app opens the entity, and the linter flags a link that matches nothing as dangling.

- Link only to entities that exist. For a new name, write plain text and ask the
  author whether it should become an entity.
- Wikilinks have **no display text.** `|` turns a link into a passage link, so the
  Obsidian-style `[[Selena|Селена]]` is actually a link to a passage named «Селена».
  Write `[[Селена]]` instead, which resolves if Селена is one of the entity's
  aliases.
- A wikilink is never a passage jump. The app decides what a `[[…]]` pair is purely
  by its shape: whether it contains a separator.

### 6.7 Authoring conditionals

Conditionals use em-dash markers with Russian keywords, built from a real `—`
(U+2014) with spaces around it:

```
— если игрок знаком с доктором Джулией — текст для этого случая — иначе — другой текст — конец условия —
```

- Every `— если … —` needs a matching `— конец условия —` somewhere after it.
  `— иначе —` is optional. The branches can span several lines or paragraphs.
- The opening marker `— если <condition> —` must sit on **one line**. Keep the
  condition under about 300 characters, with **no square brackets in the
  condition**: no `[[wikilinks]]` and no `[placeholders]`. Otherwise the app loses
  the opening marker and flags the closer.
- Only `—` works. Markers written with `–` or `-` aren't recognized.
- The keywords stay in Russian in English files too, because they are the only form
  the app checks (see §4.1).

### 6.8 Images

`![alt text](media/portrait.png)`, with the path relative to the file that contains
the image link:

- `media/` sits at the entity root. The card uses `media/x.png`, a file in `events/`
  uses `../media/x.png`, and a quest stage uses `../../media/x.png`.
- No web URLs (the app never downloads images), no leading `/`, and no spaces or
  `%20` in paths.
- Keep each image under 15 MB.

### 6.9 Never in prose

- Twee / SugarCube: `<<if>>`, `<<set>>`, `<<=$var>>`, `<<goto>>`… (flagged)
- HTML tags: `<br>`, `<span>`, `<i>`… (flagged). The mapping comment is the only
  HTML allowed.
- An unclosed `[[` (flagged).
- YAML front matter.

## 7. Configuration files at the repo root

Don't edit these unless the author asks.

- **`lore-story.json`**: project configuration.
  - `loreDir` sets where the lore root is.
  - The optional `ai` object chooses the AI provider: `server` (`anthropic`,
    `openrouter` or `custom`), `protocol` (`anthropic` or `openai`), `model`, and
    `baseUrl` for a custom server.
  - Other keys (`storyDir`, `scenesDir`, `codeDirs`, `linkMacros`, `returnMacros`,
    `dynamicTags`) are for the desktop tool.
  - **Never put an API key or any other secret in this file.** It syncs to every
    device; the key lives only in the app's secure settings.
- **`ai-prompts.md`**: optional replacements for the text the app sends to its AI.
  - Only these `# ` headings are recognized (case-insensitive, spelled exactly like
    this):
    - `# Translation Instructions` for RU→EN (`(RU→EN)` / `(RU->EN)` also accepted)
    - `# Translation Instructions (EN→RU)`, or `# Translation Instructions (EN->RU)`
    - `# Conventions`, used for both directions
    - `# Grammar Instructions`
  - A section runs until the next `# ` heading; `##` headings are part of its body.
  - An empty section means "use the app's default". Unknown headings are ignored.
    If a heading repeats, the last occurrence wins.
  - If you edit `# Conventions`, keep it consistent with this file.

## 8. Sync safety

- `.stfolder`, `.stignore` and `.stversions/` belong to Syncthing. Never touch them.
- A file like `selena.sync-conflict-20260801-101530-ABCDEFG.md` is a **conflict
  copy**: two devices edited the same file. Don't edit, delete, rename or merge it on
  your own. Tell the author, who decides which version wins. Don't restructure an
  entity while it has a conflict copy.
- `.lore-tmp-*` files are the app's temporary write files. Leave them alone.
- Don't create temp or backup files (`*.bak`, `*~`, `*.orig`) inside the synced
  folder.

## 9. Checklist before you finish

- [ ] New files are in the right place (§2), with slug names. Sub-entries have a
      language suffix; cards don't.
- [ ] Every new file starts with `# Title`. New entity cards have an aliases line
      with both Russian and English names.
- [ ] Each translation is a separate file with the same slug, the same structure,
      and the same passage names and link targets as its source.
- [ ] Dialogue follows `Name (emotion): …` with a space after the colon;
      monologue uses `Мысль:` / `Thought:`; placeholders are in `[brackets]`.
- [ ] Links: `[[Choice->Passage]]`, `[[back<-Label]]`, and `[[Entity]]` links that
      resolve. No `[[name|display]]`.
- [ ] Conditionals are paired, use a real `—`, and have no brackets in the
      condition.
- [ ] No twee, HTML, `$vars` or front matter, and no stray `.md` notes under the
      lore root.
- [ ] Only the requested text changed; nothing was reformatted.

## 10. What the app's linter flags

| Finding | Example |
| --- | --- |
| Twee in prose | `<<set $x to 1>>`, `<<=$name>>` |
| HTML tag | `<br>` |
| Unclosed wikilink | `[[Selena` |
| Dialogue colon without a space | `Frank:hello`, `**Селена:** …`, `*Thought:* …` |
| Unpaired conditional | a `— если … —` with no `— конец условия —` (checked only once the file contains at least one closer) |
| Dangling wikilink | `[[Selina]]` when no entity has that title or alias |

Valid conventions (dialogue, links, placeholders, conditionals) are only
highlighted, never flagged. A file this linter passes can still break the placement
and naming rules in §2–§4, which the app doesn't report; check those yourself.

---

_Source of truth: the Lore & Story app repo (ARCHITECTURE.md §3.2–3.3, the app's
convention matcher and linter). Last synced with the app: 2026-09-24._
