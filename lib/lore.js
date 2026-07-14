'use strict';

const fs = require('fs');
const path = require('path');

/**
 * Loads lore entries from markdown files under loreDir.
 * Folder structure gives the category: lore/characters/mira.md -> category "characters".
 * The entry title is the first `# Heading`, falling back to the filename.
 * Optional `aliases:` line right after the heading adds extra names for mention detection.
 */
function loadLore(loreDir) {
  if (!fs.existsSync(loreDir)) return [];
  const entries = [];

  const walk = dir => {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, item.name);
      if (item.isDirectory()) walk(full);
      else if (item.name.endsWith('.md')) {
        const text = fs.readFileSync(full, 'utf8');
        const heading = text.match(/^#\s+(.+)$/m);
        const title = heading ? heading[1].trim() : path.basename(item.name, '.md');
        const aliasLine = text.match(/^aliases:\s*(.+)$/mi);
        const aliases = [title, ...(aliasLine ? aliasLine[1].split(',').map(s => s.trim()) : [])];
        entries.push({
          id: path.relative(loreDir, full).replace(/\\/g, '/'),
          title,
          aliases: [...new Set(aliases.filter(Boolean))],
          category: path.relative(loreDir, path.dirname(full)).replace(/\\/g, '/') || 'general',
          file: full,
          text,
        });
      }
    }
  };
  walk(loreDir);
  return entries;
}

/** For each lore entry, find which passages mention any of its aliases. */
function findMentions(loreEntries, passages) {
  const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return loreEntries.map(entry => {
    const pattern = new RegExp(`\\b(${entry.aliases.map(escape).join('|')})\\b`, 'i');
    const mentionedIn = passages.filter(p => pattern.test(p.text)).map(p => p.name);
    return { ...entry, mentionedIn };
  });
}

module.exports = { loadLore, findMentions };
