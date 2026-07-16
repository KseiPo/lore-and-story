'use strict';

const crypto = require('crypto');

/**
 * Normalize `loadLore()` output into the shape the golden files pin.
 *
 * Two transforms, both load-bearing for the JS ⇄ Dart contract (ADR 4):
 * - `file` is dropped. It is the only absolute path in the model; everything
 *   else (`id`, `relDir`, `langs[].file`) is already relative to loreDir.
 * - `text` becomes `textSha`. Keeps the goldens small, and pins UTF-8 decoding
 *   and line endings exactly — which is the point, since the corpus is Cyrillic
 *   and the mobile writer must round-trip bytes (ARCHITECTURE §5).
 *
 * A Dart port must reproduce this projection to compare against the same files.
 */

const textSha = text =>
  crypto.createHash('sha256').update(text, 'utf8').digest('hex').slice(0, 16);

const normLangs = langs =>
  Object.fromEntries(
    Object.entries(langs)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([lang, v]) => [
        lang,
        { file: v.file, relDir: v.relDir, title: v.title, textSha: textSha(v.text) },
      ])
  );

const normNode = node =>
  node && {
    name: node.name,
    title: node.title,
    overview: node.overview
      ? { id: node.overview.id, relDir: node.overview.relDir, textSha: textSha(node.overview.text) }
      : null,
    items: node.items.map(i => ({
      id: i.id,
      title: i.title,
      group: i.group,
      passage: i.passage ?? null,
      langs: normLangs(i.langs),
    })),
    children: node.children.map(normNode),
  };

const normEntry = e => ({
  id: e.id,
  title: e.title,
  aliases: e.aliases,
  category: e.category,
  relDir: e.relDir,
  textSha: textSha(e.text),
  tree: e.tree ? normNode(e.tree) : null,
  children: e.children.map(c => ({
    id: c.id,
    title: c.title,
    group: c.group,
    textSha: textSha(c.text),
  })),
});

/** @param {Array} entries output of loadLore(loreDir) */
const normalize = entries => ({
  entries: entries.map(normEntry).sort((a, b) => a.id.localeCompare(b.id)),
});

module.exports = { normalize, textSha };
