'use strict';

const fs = require('fs');
const path = require('path');

/**
 * Lore model with entity folders and nested, language-aware sub-entries.
 *
 * Layout rules inside loreDir:
 * - a `.md` file in a category folder is a simple entity;
 * - a folder containing `index.md` or `<folder-name>.md` is an ENTITY FOLDER:
 *   that file is the entity card; everything else inside is its content tree;
 * - inside an entity, subfolders (events/, quests/, quests/<quest>/ …) form a
 *   tree of sections; a subfolder's own `<name>.md`/`index.md` is that
 *   section's overview ("folder card");
 * - files named `<base>.ru.md` / `<base>.en.md` are language variants of the
 *   same item and are merged into one entry (original language first);
 * - `media/` folders hold images and are skipped.
 */

const LANG_RE = /\.(ru|en)\.md$/i;

function readTitleAliases(text, fallback) {
  const heading = text.match(/^#\s+(.+)$/m);
  const title = heading ? heading[1].trim() : fallback;
  const aliasLine = text.match(/^aliases:\s*(.+)$/mi);
  const aliases = [title, ...(aliasLine ? aliasLine[1].split(',').map(s => s.trim()) : [])];
  return { title, aliases: [...new Set(aliases.filter(Boolean))] };
}

const prettify = seg => seg.replace(/[-_]/g, ' ');
const passageOf = text => (text.match(/scene ⇄ passage:\s*"([^"]+)"/) || [])[1] || null;

function loadLore(loreDir) {
  if (!fs.existsSync(loreDir)) return [];
  const entries = [];
  const rel = f => path.relative(loreDir, f).replace(/\\/g, '/');

  // Build the content tree for one folder (recursively). `cardFile` is the
  // entity/section card to exclude from its own items. Returns a node and
  // pushes every leaf language-file into `flat` (for the graph & mentions) —
  // except the entity card, which is not a sub-entry of itself (§3.2).
  function buildNode(dir, cardBase, groupPath, flat) {
    const node = {
      name: path.basename(dir),
      title: groupPath ? prettify(path.basename(dir)) : '',
      overview: null, items: [], children: [],
    };
    const files = [];
    const subdirs = [];
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      if (item.isDirectory()) { if (item.name !== 'media') subdirs.push(item.name); }
      else if (item.name.endsWith('.md')) files.push(item.name);
    }
    // Sort files so the flat `children[]` list (built in this order below) is
    // deterministic and matches the Dart port — `children[]` is the one
    // normalize-visible output that follows enumeration, and readdir order is
    // not guaranteed across filesystems.
    files.sort();

    // group files by base slug, collecting language variants
    const byBase = {};
    for (const name of files) {
      const langMatch = name.match(LANG_RE);
      const lang = langMatch ? langMatch[1].toLowerCase() : 'orig';
      const base = name.replace(LANG_RE, '').replace(/\.md$/, '');
      const full = path.join(dir, name);
      const text = fs.readFileSync(full, 'utf8');
      const { title } = readTitleAliases(text, base);
      (byBase[base] = byBase[base] || { base, langs: {} }).langs[lang] =
        { lang, file: full, id: rel(full), relDir: rel(dir), title, text, passage: passageOf(text) };
      if (base !== cardBase) flat.push({ id: rel(full), title, group: groupPath, text });
    }

    for (const base of Object.keys(byBase).sort()) {
      const g = byBase[base];
      // this folder's own card (overview) — matches folder name or index
      if (base === node.name || base === 'index') {
        if (base === cardBase) continue; // the entity card itself (handled by caller)
        const v = g.langs.orig || g.langs.ru || g.langs.en;
        node.overview = { id: v.id, text: v.text, relDir: v.relDir };
        node.title = v.title;
        continue;
      }
      const ru = g.langs.ru, en = g.langs.en, orig = g.langs.orig;
      const primary = orig || ru || en;
      const title = ru && en ? `${ru.title} — ${en.title}` : primary.title;
      node.items.push({
        id: (groupPath ? groupPath + '/' : '') + base,
        title, group: groupPath,
        passage: (ru || en || orig).passage,
        langs: Object.fromEntries(Object.entries(g.langs).map(([k, v]) =>
          [k, { file: v.id, relDir: v.relDir, title: v.title, text: v.text }])),
      });
    }

    for (const sub of subdirs.sort()) {
      node.children.push(buildNode(path.join(dir, sub), null,
        groupPath ? `${groupPath}/${sub}` : sub, flat));
    }
    return node;
  }

  const makeEntry = (cardFile, category, folder) => {
    const text = fs.readFileSync(cardFile, 'utf8');
    const { title, aliases } = readTitleAliases(text, path.basename(cardFile, '.md'));
    const entry = {
      id: rel(cardFile), title, aliases, category,
      file: cardFile, relDir: rel(path.dirname(cardFile)) || '.', text,
      tree: null, children: [],
    };
    if (folder) {
      const cardBase = path.basename(cardFile, '.md');
      entry.tree = buildNode(folder, cardBase, '', entry.children);
    }
    return entry;
  };

  const walkCategory = (dir, category) => {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, item.name);
      if (item.isDirectory()) {
        if (item.name === 'media') continue;
        const index = ['index.md', item.name + '.md']
          .map(n => path.join(full, n)).find(f => fs.existsSync(f));
        if (index) entries.push(makeEntry(index, category || 'general', full));
        else walkCategory(full, category ? `${category}/${item.name}` : item.name);
      } else if (item.name.endsWith('.md')) {
        entries.push(makeEntry(full, category || 'general', null));
      }
    }
  };
  walkCategory(loreDir, '');
  return entries;
}

const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** For each lore entity, find which passages mention any of its aliases. */
function findMentions(loreEntries, passages) {
  return loreEntries.map(entry => {
    const pattern = new RegExp(`\\b(${entry.aliases.map(escapeRe).join('|')})\\b`, 'i');
    const mentionedIn = passages.filter(p => pattern.test(p.text)).map(p => p.name);
    return { ...entry, mentionedIn };
  });
}

/**
 * Edges between lore entities:
 * - 'link'    — explicit [[wikilink]] anywhere in the entity (card or sub-entries)
 * - 'mention' — entity A's card text contains an alias of entity B
 */
function buildLoreGraph(entries) {
  const index = new Map();
  for (const e of entries) for (const a of e.aliases) index.set(a.toLowerCase(), e.id);

  const edges = [];
  const seen = new Set();
  const add = (source, target, kind) => {
    if (!target || source === target) return;
    const key = `${source}|${target}|${kind}`;
    if (seen.has(key)) return;
    seen.add(key);
    edges.push({ source, target, kind });
  };

  for (const e of entries) {
    const allText = [e.text, ...e.children.map(c => c.text)].join('\n');
    const wiki = /\[\[([^\]]+)\]\]/g;
    let m;
    while ((m = wiki.exec(allText)) !== null) add(e.id, index.get(m[1].trim().toLowerCase()), 'link');
    for (const other of entries) {
      if (other === e) continue;
      const pattern = new RegExp(`\\b(${other.aliases.map(escapeRe).join('|')})\\b`, 'i');
      if (pattern.test(e.text)) add(e.id, other.id, 'mention');
    }
  }
  return edges;
}

module.exports = { loadLore, findMentions, buildLoreGraph };
