'use strict';
/**
 * Scene extraction / backport tool (ADR 8, extraction direction).
 *
 * Compares story passages against the lore scene files' `scene ⇄ passage`
 * mappings, classifies uncovered passages (functional vs story prose), and
 * backports passage prose into markdown scene files:
 *   - fills missing .en.md next to mapped RU-only scene files
 *   - creates new scene files for unmapped story passages where the target
 *     location is unambiguous (plot chapters, character entity folders, …)
 *
 * Usage: node scripts/extract-scenes.js [--write]   (default: dry-run report)
 */
const fs = require('fs');
const path = require('path');
const { buildStoryModel } = require('../lib/twee-parser');

const ROOT = path.join(__dirname, '..');
const config = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8').replace(/^﻿/, ''));
const STORY_DIR = path.resolve(ROOT, config.storyDir);
const LORE_DIR = path.resolve(ROOT, config.loreDir);
const WRITE = process.argv.includes('--write');
const TODAY = new Date().toISOString().slice(0, 10);

// ---------- load passages ----------
function collectTwee(dir) {
  const files = [];
  (function walk(d) {
    for (const it of fs.readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, it.name);
      if (it.isDirectory()) walk(full);
      else if (/\.(twee|tw)$/.test(it.name)) files.push({ source: fs.readFileSync(full, 'utf8'), filePath: full, relPath: path.relative(dir, full) });
    }
  })(dir);
  return files;
}
const story = buildStoryModel(collectTwee(STORY_DIR), { linkMacros: config.linkMacros || [], returnMacros: config.returnMacros || [] });

// ---------- collect existing mappings from lore ----------
// map: passage name -> [{file, base, dir, hasEn, hasRu}]
const mapped = new Map();
const loreFiles = [];
(function walk(d) {
  for (const it of fs.readdirSync(d, { withFileTypes: true })) {
    const full = path.join(d, it.name);
    if (it.isDirectory()) { if (it.name !== 'media') walk(full); }
    else if (it.name.endsWith('.md')) loreFiles.push(full);
  }
})(LORE_DIR);

for (const file of loreFiles) {
  const text = fs.readFileSync(file, 'utf8');
  // a scene file may contain SEVERAL passage sections, each with its own
  // mapping comment (multi-passage scenes, see on-the-crossroads)
  for (const m of text.matchAll(/scene ⇄ passages?:\s*([^·\n]+?)\s*·/g)) {
    const raw = m[1].replace(/"/g, '').trim();
    if (raw === 'TBD' || raw.startsWith('TBD')) continue;
    let names = [];
    // family form: "Contract - veteran - Person/Start/End" or comma list
    const fam = raw.match(/^(.*\s-\s)([A-Za-zА-Яа-яё ]+(?:\/[A-Za-zА-Яа-яё ]+)+)$/);
    if (fam) names = fam[2].split('/').map(s => (fam[1] + s.trim()));
    else names = raw.split(',').map(s => s.trim()).filter(Boolean);
    const base = path.basename(file).replace(/\.(ru|en)\.md$/i, '').replace(/\.md$/, '');
    const dir = path.dirname(file);
    for (const n of names) {
      const arr = mapped.get(n) || [];
      arr.push({ file, base, dir });
      mapped.set(n, arr);
    }
  }
}
// determine language presence per mapped base
function langsOf(dir, base) {
  return {
    ru: fs.existsSync(path.join(dir, base + '.ru.md')),
    en: fs.existsSync(path.join(dir, base + '.en.md')),
    plain: fs.existsSync(path.join(dir, base + '.md')),
  };
}

// ---------- twee -> prose conversion ----------
function tweeToProse(text) {
  let t = text;
  t = t.replace(/\r/g, '');
  t = t.replace(/<<nobr>>|<<\/nobr>>|<<silently>>[\s\S]*?<<\/silently>>/g, '');
  // say/think with body
  t = t.replace(/<<say\s+"?([^">\s]+)"?[^>]*>>([\s\S]*?)<<\/say>>/g, (m, who, body) =>
    `${who === 'mc' ? 'Me' : who}: ${body.trim()}`);
  t = t.replace(/<<say[^>]*>>([\s\S]*?)<<\/say>>/g, (m, body) => `Me: ${body.trim()}`);
  t = t.replace(/<<think[^>]*>>([\s\S]*?)<<\/think>>/g, (m, body) => `Thought: ${body.trim()}`);
  // return-to-caller widgets — canonical form: **Label** _(↩ …)_
  t = t.replace(/<<linkBack\s+['"]([^'"]+)['"]\s*>>/g, '**$1** _(↩ back)_');
  t = t.replace(/<<linkBack\s*>>/g, '**Back** _(↩ back)_');
  t = t.replace(/<<wakeupLink\s+['"]([^'"]+)['"]\s*>>/g, '**$1** _(↩ wake up)_');
  t = t.replace(/<<wakeupLink\s*>>/g, '**Wake up** _(↩ wake up)_');
  // links — canonical form: **Text** _(→ Target)_  (all wiki variants: | -> <-)
  t = t.replace(/<<link\s+\[\[([^\]]+)\]\]\s*>>/g, '[[$1]]');
  t = t.replace(/<<link\s+"([^"]+)"\s+"([^"]+)"\s*>>/g, '**$1** _(→ $2)_');
  t = t.replace(/<<link\s+"([^"]+)"\s*>>/g, '**$1**');
  t = t.replace(/<<\/link>>|<<\/button>>/g, '');
  t = t.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g, '**$1** _(→ $2)_');
  t = t.replace(/\[\[([^\]]+?)->([^\]]+)\]\]/g, '**$1** _(→ $2)_');
  t = t.replace(/\[\[([^\]]+?)<-([^\]]+)\]\]/g, '**$2** _(→ $1)_');
  t = t.replace(/\[\[([^\]]+)\]\]/g, '**$1**');
  // conditionals -> authoring markers
  t = t.replace(/<<if\s+([^>]+)>>/g, '— if: $1 —');
  t = t.replace(/<<elseif\s+([^>]+)>>/g, '— else if: $1 —');
  t = t.replace(/<<else>>/g, '— else —');
  t = t.replace(/<<\/if>>/g, '— end if —');
  // media
  t = t.replace(/<<(?:image|video)\s+"([^"]+)"[^>]*>>/g, '[media: $1]');
  t = t.replace(/<<avatar\s+([^>\s]+)[^>]*>>/g, '[avatar: $1]');
  // variables in prose
  t = t.replace(/\$playerName|\$playerSurname/g, m => m === '$playerName' ? '[player name]' : '[player surname]');
  t = t.replace(/<<=\s*([^>]+?)\s*>>|<<print\s+([^>]+?)\s*>>/g, (m, a, b) => `[${(a || b).trim()}]`);
  // any remaining macros / widget calls -> drop the line if alone, else strip inline
  t = t.split('\n').map(line => {
    const stripped = line.replace(/<<[^>]*>>/g, '').replace(/<\/?[a-zA-Z][^>]*>/g, '');
    return stripped.trim() === '' && /<<|<[a-zA-Z]/.test(line) ? null : stripped;
  }).filter(l => l !== null).join('\n');
  // normalize double-bracket artifacts from chained rules ([[player name]])
  t = t.replace(/\[\[([^\]|]+)\]\]/g, '[$1]');
  // collapse blank runs
  t = t.replace(/\n{3,}/g, '\n\n').trim();
  return t;
}
const proseWords = text => (tweeToProse(text).replace(/\[[^\]]*\]|\*|—.*?—/g, '').match(/[A-Za-zА-Яа-яё']{2,}/g) || []).length;

// ---------- classification ----------
const FUNCTIONAL_FOLDERS = new Set(['widgets', 'minigames', 'meta', 'achievements', 'gallery', 'walkthrough', 'communicator', 'encounter', 'common', 'jobs']);
const FUNCTIONAL_NAMES = /GenerateEvents|NewDialog|GenerateJobs|EndCheck|Init$|^Test$|^Cheats|StoryMenu|PlayerSheet|PlayerShip|StarMap|^Sleep$|^Dream$|Minigame|^Market$|Hyperjump|^Doks|^Доки/i;
const MIN_PROSE_WORDS = 40;

const report = { coveredOk: [], missingEn: [], newScenes: [], manual: [], functional: [] };

// Explicit placements for passages the heuristics can't place (reviewed 2026-07-17).
// Multiple passages may share a target -> multi-section scene file.
const PLACEMENTS = {
  'Character - Dayron': 'characters/dayron/events/character-hub.en.md',
  'Character - Dayron - First Meet': 'characters/dayron/events/first-meet.en.md',
  'Character - Eric': 'characters/eric/events/character-hub.en.md',
  'Character - Loan': 'characters/loan/events/character-hub.en.md',
  'Character - Max Sholar': 'characters/max-sholar/events/character-hub.en.md',
  'Max Sholar - Burned out controller': 'characters/max-sholar/events/burned-out-controller.en.md',
  'Max Sholar - Broken powercore': 'characters/max-sholar/events/broken-powercore.en.md',
  'Character - PUSS-25': 'characters/puss-25/events/character-hub.en.md',
  'VAG-12 - Burned out controller': 'characters/vag-12/events/burned-out-controller.en.md',
  'Character - Sofia': 'characters/sofia-myers/events/character-hub.en.md',
  'Zara Lingerie Sex': 'characters/zara/events/lingerie-sex.en.md',
  'Nothing - Gossip': 'characters/zoey/events/nothing-gossip.en.md',
  'FirstMining': 'plot/chapter-1/scenes/first-mining.en.md',
  'FirstRepair': 'plot/chapter-1/scenes/first-repair.en.md',
  'Negotiations in Hyperspace': 'plot/chapter-1/scenes/negotiations-in-hyperspace.en.md',
  'Game Over - Caught': 'plot/prologue/scenes/game-over-caught.en.md',
  'First Jarr Encounter - Dream': 'plot/dreams/scenes/first-jarr-encounter-dream.en.md',
  'First Jarr Encounter - Dream 2': 'plot/dreams/scenes/first-jarr-encounter-dream.en.md',
  'First Jarr Encounter - Dream 3': 'plot/dreams/scenes/first-jarr-encounter-dream.en.md',
  'Sex - Dream': 'plot/dreams/scenes/sex-dream.en.md',
  'marcus_slutty-hitchhikers - Dream': 'plot/dreams/scenes/marcus-slutty-hitchhikers-dream.en.md',
  'Frank - Dream': 'plot/dreams/scenes/frank-dream.en.md',
};
// Minimal entity cards created alongside (loader needs a folder card).
const CARDS = {
  'characters/dayron/dayron.md': '# Dayron\naliases: Дайрон\n\n- **Occupation:** торговый брокер · **Location:** [[Theta Pavoris — Harbour]] → Trade Bay\n\nТорговый брокер за шестьдесят, ворчлив и суров, но в делах честен и знает рынок как никто другой. Рекомендация Зои.\n',
  'characters/eric/eric.md': '# Eric\naliases: Эрик\n\n- **Occupation:** помощник администратора · **Location:** [[Lambda Hadrionis — Melting Point]] → Control Center\n\nПомощник Линды Крэйвен в центре управления станции.\n',
  'characters/loan/loan.md': '# Loan\naliases: Лоан\n\n- **Occupation:** механик · **Location:** [[Epsilon Varix — Oasis-3]] → Hangar\n\nКардинианин: высокий, длинные пальцы, пепельно-серая кожа. Обслуживание и ремонт кораблей в ангаре колонии.\n',
  'characters/max-sholar/max-sholar.md': '# Max Sholar\naliases: Макс Шолар, Шолар\n\n- **Occupation:** инженер станции · **Location:** [[Lambda Hadrionis — Melting Point]] → Hangar\n\nМестный инженер и механик. Говорит редко, ворчит часто, но с корабельной техникой обращается как с живым существом. Людей не любит, но машины уважают его.\n',
  'characters/puss-25/puss-25.md': '# PUSS-25\naliases: ПУСС-25\n\n- **Occupation:** док-менеджер (андроид) · **Location:** [[Zeta Caeli — The Cold Heaven]] → Dock\n\nЧеловекоподобный андроид с женскими чертами; вместо глаз — светящаяся сенсорная полоска. В манере общения — почти кокетливость: сбой или намеренный дизайн?\n',
  'characters/vag-12/vag-12.md': '# VAG-12\naliases: ВАГ-12\n\n- **Occupation:** андроид-кладовщик · **Location:** [[Zeta Caeli — The Cold Heaven]] → Supply Bay\n\nАндроид старой серии, заведует складом снабжения. Покупает и продаёт при случае.\n',
  'plot/dreams/dreams.md': '# Dreams\naliases: Сны\n\nОбщие сновидения (система сна): сюжетные сны и шаблоны, не привязанные к одному персонажу. Персональные сны лежат у персонажей в `events/dream.*`.\n',
};

// character entity folders present in lore (for placement)
const charFolders = fs.readdirSync(path.join(LORE_DIR, 'characters'), { withFileTypes: true })
  .filter(d => d.isDirectory() && d.name !== 'media').map(d => d.name);
const charByPrefix = {
  'Selena': 'selena', 'Zoey': 'zoey', 'Aisha': 'aisha', 'Annie': 'annie', 'Mira': 'mira',
  'Zara': 'zara', 'Linda Craven': 'linda-craven', 'Dr. Sofia Myers': 'sofia-myers',
  'Sofia': 'sofia-myers', 'Carrie': 'carrie', 'Marcus': 'marcus',
};
const slugify = name => name.toLowerCase().replace(/['’«»"]/g, '').replace(/[^a-z0-9а-яё]+/gi, '-').replace(/^-+|-+$/g, '');

function placementFor(p) {
  if (p.folder === 'prologue') return path.join(LORE_DIR, 'plot', 'prologue', 'scenes');
  if (p.folder === 'chapter1') return path.join(LORE_DIR, 'plot', 'chapter-1', 'scenes');
  if (p.rel.startsWith('locations/Oasis-3')) return path.join(LORE_DIR, 'stations', 'epsilon-varix-oasis-3', 'events');
  const prefix = Object.keys(charByPrefix).find(k => p.name.startsWith(k + ' - '));
  if (prefix && charFolders.includes(charByPrefix[prefix]))
    return path.join(LORE_DIR, 'characters', charByPrefix[prefix], 'events');
  return null;
}

// longest-first mapped names, for folding sub-passages into their base scene
const mappedNames = [...mapped.keys()].sort((a, b) => b.length - a.length);

const byTarget = new Map(); // target file -> [passages in order]
const addToTarget = (target, p) => {
  const arr = byTarget.get(target) || [];
  arr.push(p);
  byTarget.set(target, arr);
};

const placed = new Map(); // explicit-placement target -> [passages]
for (const p of story.passages) {
  const hits = mapped.get(p.name);
  if (hits) {
    const h = hits[0];
    const l = langsOf(h.dir, h.base);
    if (l.ru && !l.en && !l.plain) addToTarget(path.join(h.dir, h.base + '.en.md'), p);
    else report.coveredOk.push(p.name);
    continue;
  }
  if (PLACEMENTS[p.name]) {
    const t = path.join(LORE_DIR, PLACEMENTS[p.name]);
    (placed.get(t) || placed.set(t, []).get(t)).push(p);
    continue;
  }
  const words = proseWords(p.text);
  const functional = FUNCTIONAL_FOLDERS.has(p.folder) || FUNCTIONAL_NAMES.test(p.name)
    || p.tags.some(t => ['UI', 'widget', 'minigame'].includes(t)) || words < MIN_PROSE_WORDS;
  if (functional) { report.functional.push(`${p.name}  [${p.folder}, ${words}w]`); continue; }

  // sub-passage of a mapped scene? (e.g. "Selena - Dock inspection Route A")
  const base = mappedNames.find(n => p.name.startsWith(n + ' '));
  if (base) {
    const h = mapped.get(base)[0];
    const l = langsOf(h.dir, h.base);
    if (l.ru && !l.en && !l.plain) { addToTarget(path.join(h.dir, h.base + '.en.md'), p); continue; }
    report.manual.push(`${p.name}  [sub-passage of "${base}" — EN already authored, merge by hand]`);
    continue;
  }

  const dir = placementFor(p);
  if (dir) {
    // strip character prefix from event slugs (Aisha - Dream -> dream.en.md)
    const prefix = Object.keys(charByPrefix).find(k => p.name.startsWith(k + ' - '));
    const slugBase = prefix ? p.name.slice(prefix.length + 3) : p.name;
    report.newScenes.push({ p, target: path.join(dir, slugify(slugBase) + '.en.md') });
  } else report.manual.push(`${p.name}  [${p.folder}, ${words}w]`);
}

// order passages within a shared target: story-stage rank, then name
const STAGE_RANK = { Person: 0, Start: 1, Middle: 2, End: 3 };
const rank = n => { const last = n.split(' - ').pop().trim(); return STAGE_RANK[last] ?? 5; };
for (const [target, ps] of byTarget) {
  ps.sort((a, b) => rank(a.name) - rank(b.name) || a.name.localeCompare(b.name));
  report.missingEn.push({ target, passages: ps });
}
report.missingEn.sort((a, b) => a.target.localeCompare(b.target));

// ---------- output ----------
console.log(`passages: ${story.passages.length} | mapped ok: ${report.coveredOk.length} | missing EN files: ${report.missingEn.length} | new scenes: ${report.newScenes.length} | manual: ${report.manual.length} | functional (skipped): ${report.functional.length}\n`);
console.log('-- missing EN files (backport passage text next to existing RU) --');
report.missingEn.forEach(x => console.log('  ' + path.relative(LORE_DIR, x.target) + '  <=  ' + x.passages.map(p => p.name).join(' + ')));
console.log('\n-- new scene files (unmapped story passages, placement known) --');
report.newScenes.forEach(x => console.log('  ' + x.p.name + '  ->  ' + path.relative(LORE_DIR, x.target)));
console.log('\n-- explicit placements (PLACEMENTS map) --');
for (const [t, ps] of placed) console.log('  ' + path.relative(LORE_DIR, t) + '  <=  ' + ps.map(p => p.name).join(' + '));
console.log('\n-- needs manual attention --');
report.manual.forEach(x => console.log('  ' + x));

if (WRITE) {
  let n = 0;
  for (const [rel, content] of Object.entries(CARDS)) {
    const file = path.join(LORE_DIR, rel);
    if (!fs.existsSync(file)) {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, content, 'utf8');
      console.log('  card: ' + rel);
    }
  }
  const writeScene = (passages, target) => {
    const title = passages[0].name;
    const mapping = passages.length === 1 ? `"${title}"` : `"${passages.map(p => p.name.split(' - ').pop()).join('/')}" of "${title.split(' - ').slice(0, -1).join(' - ') || title}"`;
    const parts = passages.map(p =>
      (passages.length > 1 ? `## ${p.name}\n\n` : '') + tweeToProse(p.text));
    const md = `# ${title}\n<!-- scene ⇄ passage${passages.length > 1 ? 's' : ''}: ${passages.length === 1 ? `"${title}"` : passages.map(p => `"${p.name}"`).join(', ')} · lang: en -->\n<!-- backported from passage ${TODAY} — needs review -->\n\n${parts.join('\n\n')}\n`;
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, md, 'utf8');
    n++;
  };
  report.missingEn.forEach(x => writeScene(x.passages, x.target));
  report.newScenes.forEach(x => writeScene([x.p], x.target));
  for (const [t, ps] of placed) writeScene(ps, t);
  console.log(`\nwritten: ${n} files`);
} else {
  console.log('\n(dry run — pass --write to generate files)');
}
