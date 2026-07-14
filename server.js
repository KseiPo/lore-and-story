'use strict';

const fs = require('fs');
const path = require('path');
const express = require('express');
const { buildStoryModel } = require('./lib/twee-parser');
const { loadLore, findMentions } = require('./lib/lore');

// Project config: which story to visualize and project-specific link widgets.
// Re-read on every request, so editing config.json + Rescan in the UI is
// enough to point the app at another project — no server restart needed.
function readConfig() {
  let config = {};
  const file = path.join(__dirname, 'config.json');
  if (fs.existsSync(file)) {
    try {
      // strip BOM — editors and PowerShell often write one
      config = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
    } catch (err) {
      console.error(`config.json is invalid (${err.message}) — using defaults`);
    }
  }
  return {
    port: process.env.PORT || config.port || 3987,
    storyDir: path.resolve(process.env.STORY_DIR || config.storyDir || path.join(__dirname, 'story')),
    loreDir: path.resolve(process.env.LORE_DIR || config.loreDir || path.join(__dirname, 'lore')),
    linkMacros: config.linkMacros || [],
    codeDirs: (config.codeDirs || []).map(d => path.resolve(d)),
    dynamicTags: config.dynamicTags || [],
  };
}
const { port: PORT, storyDir: STORY_DIR, loreDir: LORE_DIR } = readConfig();

// Collect string literals from project script files AND the twee sources.
// A literal equal to a passage name counts as a code reference; literal
// fragments also feed the composed-name heuristic (star + ' - ' + location).
function addLiterals(literals, src, relFile) {
  const push = lit => {
    if (!lit || lit.length < 3) return;
    const list = literals.get(lit) || [];
    if (list.length < 5 && !list.includes(relFile)) list.push(relFile);
    literals.set(lit, list);
  };
  const quoted = /'((?:[^'\\\n]|\\.){2,90})'|"((?:[^"\\\n]|\\.){2,90})"/g;
  let m;
  while ((m = quoted.exec(src)) !== null) push(m[1] || m[2]);
  const template = /`((?:[^`\\]|\\.){2,300})`/g;
  while ((m = template.exec(src)) !== null) {
    for (const frag of m[1].split(/\$\{[^}]*\}/)) push(frag);
  }
}

function collectCodeLiterals(dirs, tweeFiles) {
  const literals = new Map(); // literal -> [relative file paths]
  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    const walk = d => {
      for (const item of fs.readdirSync(d, { withFileTypes: true })) {
        const full = path.join(d, item.name);
        if (item.isDirectory() && item.name !== 'node_modules') walk(full);
        else if (/\.(ts|js|json)$/.test(item.name) && !item.name.endsWith('.d.ts')) {
          addLiterals(literals, fs.readFileSync(full, 'utf8'), path.relative(dir, full).replace(/\\/g, '/'));
        }
      }
    };
    walk(dir);
  }
  for (const f of tweeFiles) addLiterals(literals, f.source, f.relPath.replace(/\\/g, '/'));
  return literals;
}

const app = express();

// Vendor libs served straight from node_modules — no bundler needed for the POC.
const vendor = {
  '/vendor/cytoscape.min.js': 'cytoscape/dist/cytoscape.min.js',
  '/vendor/dagre.min.js': 'dagre/dist/dagre.min.js',
  '/vendor/cytoscape-dagre.js': 'cytoscape-dagre/cytoscape-dagre.js',
  '/vendor/marked.min.js': 'marked/marked.min.js',
};
for (const [route, mod] of Object.entries(vendor)) {
  app.get(route, (req, res) => res.sendFile(require.resolve(mod)));
}

app.use(express.static(path.join(__dirname, 'public')));

function collectTweeFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  const files = [];
  const walk = d => {
    for (const item of fs.readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, item.name);
      if (item.isDirectory()) walk(full);
      else if (/\.(twee|tw)$/.test(item.name)) {
        files.push({
          source: fs.readFileSync(full, 'utf8'),
          filePath: full,
          relPath: path.relative(dir, full),
        });
      }
    }
  };
  walk(dir);
  return files;
}

// Everything is parsed fresh on every request: the files ARE the database.
app.get('/api/data', (req, res) => {
  try {
    const t0 = Date.now();
    const cfg = readConfig();
    const tweeFiles = collectTweeFiles(cfg.storyDir);
    const story = buildStoryModel(tweeFiles, {
      linkMacros: cfg.linkMacros,
      dynamicTags: cfg.dynamicTags,
      codeLiterals: collectCodeLiterals(cfg.codeDirs, tweeFiles),
    });
    const lore = findMentions(loadLore(cfg.loreDir), story.passages);
    res.json({ story, lore, storyDir: cfg.storyDir, loreDir: cfg.loreDir, parseMs: Date.now() - t0 });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Server-sent events: notify the UI when any story/lore file changes on disk.
const sseClients = new Set();
app.get('/api/events', (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.write('retry: 1000\n\n');
  sseClients.add(res);
  req.on('close', () => sseClients.delete(res));
});

let debounce = null;
function notifyChange() {
  clearTimeout(debounce);
  debounce = setTimeout(() => {
    for (const client of sseClients) client.write('data: changed\n\n');
  }, 150);
}
for (const dir of [STORY_DIR, LORE_DIR]) {
  if (fs.existsSync(dir)) {
    try {
      fs.watch(dir, { recursive: true }, notifyChange);
    } catch { /* recursive watch unsupported on some platforms — Rescan button still works */ }
  }
}
// Editing config.json (e.g. pointing storyDir at another project) refreshes the
// UI too. Note: file watchers stay on the startup dirs until the next restart.
try { fs.watch(path.join(__dirname, 'config.json'), notifyChange); } catch { /* optional */ }

app.listen(PORT, () => {
  console.log(`lore-and-story POC running at http://localhost:${PORT}`);
  console.log(`  story dir: ${STORY_DIR}`);
  console.log(`  lore  dir: ${LORE_DIR}`);
});
