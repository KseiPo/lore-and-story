# Addendum — Lore & Story Mobile

Technical-how and options-considered depth extracted from `MOBILE.md`. Belongs in
the downstream architecture / solution-design document, not the PRD body. The PRD
states capabilities; this records the mechanisms and rejected alternatives.

## A. Storage & permission decision (MOBILE §2 ADR 1, §3.1)

The heavy permission is **a consequence of external sync**, not a free-standing
choice. Options considered:

| Option | Permission | Paths | App owns auth? | App owns merge? |
|---|---|---|---|---|
| **All-files + external syncer (CHOSEN)** | `MANAGE_EXTERNAL_STORAGE` (heavy) | real | no | no |
| SAF + external syncer | folder grant (light) | `DocumentFile` | no | no |
| App-private + embedded git | none | real | yes | yes |

- **Chosen:** all-files + external syncer. Real `dart:io` paths keep the Dart
  loader a near-line-for-line mirror of `lib/lore.js`.
- **SAF rejected** on port grounds — `DocumentFile` traversal diverges from the
  path contract, making the loader a rewrite not a mirror.
- **App-private rejected** only because it *forces* embedded git; otherwise its
  storage properties are the best of the three.
- Not Play-Store-distributable; irrelevant for a sideloaded personal tool.
- **`RepoStorage` seam** (`listDir`, `read`, `writeAtomic`, `exists`) is the
  abstraction that makes both a future SAF backend and a future app-private+git
  working copy a root-path swap rather than a rewrite. (PRD NFR3.)

## B. Embedded git — evaluated, deferred (MOBILE §2 ADR 6, §3.3)

- **Library is cheap:** `git2dart` (FFI to libgit2) bundles the native lib on
  Android release builds (arm64-v8a, x86_64; no armeabi-v7a). Pure-Dart
  `dart-git` is experimental/GitJournal-scoped.
- **Cost is semantics, not the library:** auth (PAT over HTTPS + Android Keystore;
  avoid SSH/libssh2) is bounded; the real cost is **merge / diverged-branch UX**;
  **full clone incl. `media/` history is an unmeasured risk** (libgit2 shallow
  clone historically weak).
- **The move that collapses the cost:** single author ⇒ pulls are almost always
  fast-forward. Design **FF-only sync that explicitly refuses to merge**
  ("remote diverged → resolve on desktop"). Keeps ADR 2's "never merges" while
  dropping only "never syncs/authenticates".
- **Deferred** because v0.1's job is to prove the editing loop; front-loading git
  builds auth/clone/divergence before the core thesis is known. `RepoStorage`
  makes the working-copy swap cheap.
- **Trigger to revisit:** wanting one-tap commits from the phone, or the external
  syncer degrading (risk R6). **Measure repo clone size with media history first**
  — the one number that could kill the option (PRD R7).

## C. AI shape, model, cost (MOBILE §2 ADR 7, §6.4)

- **Transport:** no official Anthropic Dart SDK → Flutter calls the Messages API
  over raw HTTPS (JSON POST). Hand-roll **SSE parsing for streaming** (long
  translation output) and retry/error handling.
- **Model:** `claude-opus-4-8` (1M context). Use `thinking: {type: "adaptive"}` —
  literary translation with glossary adherence is the non-trivial case.
- **Cost is a non-issue:** ~10K input (Cyrillic tokenizes less efficiently) + ~5K
  output ≈ **$0.18 per scene**. Do not design around cost.
- **Skip prompt caching:** the glossary+conventions prefix (~2K tokens) is below
  Opus 4.8's 4096-token minimum cacheable prefix — would silently never cache.
- **Key storage:** Android Keystore via `flutter_secure_storage`.
- **Glossary is free:** `readTitleAliases` across entities (already needed for
  browsing) yields title + RU/EN aliases — exactly the translator term list.
- **Cheap fallback:** phone merely *marks* files "needs translation"; desktop
  batch-translates. Zero mobile AI code — kept if the AI milestone slips.

## D. Editor mechanics (MOBILE §5)

- **Highlighting:** custom `TextEditingController` overriding `buildTextSpan()`
  returns styled spans (headers larger, `[[wikilinks]]` colored, `**bold**` bold)
  while the buffer stays raw markdown. Standard Flutter technique.
- **The differentiator:** the same highlighter matches *this project's*
  conventions (`Name (emotion):`, `[placeholders]`, em-dash conditionals), not
  just markdown — and the **same matcher is reused as the convention linter**
  (PRD FR18). Build once, surface twice.
- **Invalid-span category (PRD FR9a, NFR7):** the matcher emits an `invalid` span
  kind (malformed/unterminated markup, leaked twee, scene `[[label->passage]]`)
  rendered in an error style. `buildTextSpan()` must be **total** — any region it
  can't classify falls through to a plain span; it never throws on malformed
  input. Highlighting is best-effort; the raw buffer is always intact and saveable.
- **Excluded:** WYSIWYG / live-preview-that-hides-markup — the conventions are the
  content being proofread.

## E. Dart port scope (MOBILE §8)

Read subset of the reference loader + a new write path (the JS core is read-only).

| Rule (`lib/lore.js`) | v0.1 |
|---|---|
| `walkCategory` (simple vs entity folder, category=path, skip `media/`) | Required |
| `buildNode` (`{overview,items,children}`, group=subfolder, `prettify`) | Required |
| `readTitleAliases` (title from `# heading`, `aliases:` line) | Required — doubles as AI glossary |
| Language pairing (`LANG_RE`, `byBase`, ru/en merge, `"<ru> — <en>"`) | Required |
| `passageOf` (`scene ⇄ passage` comment) | Defer — bridge only |
| `findMentions` / `buildLoreGraph` | Defer — v0.2+ (O(n²) regex graph) |

**New on the Dart side (no JS equivalent):** atomic UTF-8 writer (temp+rename,
preserve EOL/trailing newline); syncer-aware walk (filter `.st*`, surface
`*.sync-conflict-*.md`); convention matcher (highlighter + linter).

**Authoring write ops (PRD Group I — reverses the read-only assumption further):**
- *Create entity / sub-entry* (FR24–25, MVP): new-file writes through the atomic
  writer; may `mkdir` a category or group folder. Low risk.
- *Promote simple→folder* (FR26, phase): create `<slug>/`, **move** `<slug>.md` →
  `<slug>/<slug>.md` preserving bytes. A move is the syncer-riskiest op (delete +
  create); design it atomic, re-scan on resume, and block while a conflict copy
  exists for the entity (PRD R8). Deferred until the edit+create loop is proven.

## F. First spike (non-UI) (MOBILE §3.4)

Before any browsing UI, prove the storage+sync loop headless on a real device:
grant a Syncthing'd folder → read one `.ru.md` → atomic write-back → confirm on
desktop that Syncthing propagated it with no conflict copy. Risk is concentrated
in storage-grant + safe write-back; de-risk it first.

## G. Target project layout (MOBILE §9)

```
lore-and-story/
  lib/                 # JS core (reference loader, parser, analysis)
  public/              # desktop POC UI
  apps/mobile/         # Flutter (Android) writing app  ← this PRD
  scripts/update-goldens.js
  test/
    lore-model.test.js
    fixtures/lore-model/   # shared golden fixtures (JS + Dart)
```
