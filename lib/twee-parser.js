'use strict';

// Parses Twee 3 / SugarCube source files into passages, links and analysis data.
// The file system stays the source of truth — everything here is a derived view.

const SPECIAL_PASSAGES = new Set([
  'StoryTitle', 'StoryData', 'StoryInit', 'StoryAuthor', 'StoryBanner',
  'StoryCaption', 'StoryDisplayTitle', 'StoryInterface', 'StoryMenu',
  'StorySubtitle', 'PassageDone', 'PassageFooter', 'PassageHeader',
  'PassageReady', 'StorySettings', 'StoryShare',
]);

const NON_STORY_TAGS = new Set(['script', 'stylesheet', 'widget', 'Twine.private']);

/** Parse a single .twee file into passages. */
function parseTweeFile(source, filePath) {
  const passages = [];
  const lines = source.split(/\r?\n/);
  let current = null;

  lines.forEach((line, i) => {
    const header = line.match(/^::\s*([^[{]+?)\s*(\[(.*?)\])?\s*(\{.*\})?\s*$/);
    if (header) {
      if (current) passages.push(current);
      current = {
        name: header[1].trim(),
        tags: header[3] ? header[3].split(/\s+/).filter(Boolean) : [],
        file: filePath,
        line: i + 1,
        text: '',
      };
    } else if (current) {
      current.text += line + '\n';
    }
  });
  if (current) passages.push(current);
  return passages;
}

// Targets that are variables, function calls or expressions can't be resolved statically.
const isVariable = s => /^[$_]/.test(s) || s.includes('(') || s.startsWith('setup.');

/**
 * Extract outgoing links from SugarCube passage text.
 * opts.linkMacros: names of custom widgets whose FIRST argument is a passage
 * target (e.g. <<backLink "Star Map">>), configurable per project.
 */
function extractLinks(text, opts = {}) {
  const links = [];

  // [[Target]] | [[Text|Target]] | [[Text->Target]] | [[Target<-Text]] (+ optional setter [...])
  const wiki = /\[\[(.+?)\]\]/g;
  let m;
  while ((m = wiki.exec(text)) !== null) {
    let inner = m[1];
    const setterIdx = inner.indexOf('][');
    if (setterIdx !== -1) inner = inner.slice(0, setterIdx);
    let target;
    if (inner.includes('->')) target = inner.split('->').pop();
    else if (inner.includes('<-')) target = inner.split('<-')[0];
    else if (inner.includes('|')) target = inner.split('|').pop();
    else target = inner;
    // SugarCube evaluates quoted targets as expressions: [[Text|'Some Passage']]
    target = target.trim().replace(/^(['"])(.*)\1$/, '$2');
    if (target) links.push({ target, kind: isVariable(target) ? 'dynamic' : 'link' });
  }

  // <<link "Text" "Target">> / <<button "Text" "Target">>
  const macroLink = /<<(?:link|button)\s+(?:"[^"]*"|'[^']*')\s+(?:"([^"]+)"|'([^']+)')/g;
  while ((m = macroLink.exec(text)) !== null) {
    links.push({ target: m[1] || m[2], kind: 'macro' });
  }

  // <<goto "Target">>, <<goto Target>> or <<goto $variable>> (dynamic)
  const goto = /<<goto\s+(?:"([^"]+)"|'([^']+)'|([^\s>[][^>]*?))\s*>>/g;
  while ((m = goto.exec(text)) !== null) {
    const target = m[1] || m[2] || m[3];
    links.push({ target, kind: isVariable(target) ? 'dynamic' : 'goto' });
  }

  // <<include "Target">> / <<display Target>> — transclusion, not navigation.
  // The argument may be quoted or a bare token (or a variable → dynamic).
  const include = /<<(?:include|display)\s+(?:"([^"]+)"|'([^']+)'|([^\s>[]+))/g;
  while ((m = include.exec(text)) !== null) {
    const target = m[1] || m[2] || m[3];
    links.push({ target, kind: isVariable(target) ? 'dynamic' : 'include' });
  }

  // <<set $var to 'Passage Name'>> — deferred navigation: the name is stored
  // now and jumped to later via <<goto $var>>. Only counts as a link if the
  // string matches an existing passage (checked by the caller), so ordinary
  // string assignments are never flagged as broken links.
  const setvar = /<<set\s+[$_][\w.[\]$]*\s+to\s+(?:"([^"]+)"|'([^']+)')\s*>>/g;
  while ((m = setvar.exec(text)) !== null) {
    links.push({ target: m[1] || m[2], kind: 'stored', candidate: true });
  }

  // Project-specific navigation widgets: <<backLink "Target">>, <<backLink Target>>, <<backLink _var>>
  for (const name of opts.linkMacros || []) {
    const macro = new RegExp(`<<${name}\\s+(?:"([^"]+)"|'([^']+)'|([^\\s>]+))`, 'g');
    while ((m = macro.exec(text)) !== null) {
      const target = m[1] || m[2] || m[3];
      links.push({ target, kind: isVariable(target) ? 'dynamic' : 'macro' });
    }
  }

  return links;
}

/** Build the full story model from a list of {source, filePath, relPath} entries. */
function buildStoryModel(files, opts = {}) {
  const passages = files.flatMap(f =>
    parseTweeFile(f.source, f.filePath).map(p => {
      const rel = (f.relPath || f.filePath).replace(/\\/g, '/');
      return { ...p, rel, folder: rel.includes('/') ? rel.split('/')[0] : '(root)' };
    })
  );

  // Start passage from StoryData, falling back to "Start"
  let start = 'Start';
  const storyData = passages.find(p => p.name === 'StoryData');
  if (storyData) {
    try { start = JSON.parse(storyData.text).start || start; } catch { /* malformed JSON — keep default */ }
  }

  const isStory = p =>
    !SPECIAL_PASSAGES.has(p.name) && !p.tags.some(t => NON_STORY_TAGS.has(t));

  const storyPassages = passages.filter(isStory);
  const names = new Set(passages.map(p => p.name));

  // Links are extracted from ALL passages (widget definitions and specials
  // navigate too — e.g. a nav widget linking to "Star Map"), so reachability
  // sees them; the graph only renders edges between visible story passages.
  const edges = [];
  const seen = new Set();
  for (const p of passages) {
    if (p.tags.some(t => t === 'script' || t === 'stylesheet')) continue;
    for (const link of extractLinks(p.text, opts)) {
      // candidate links (stored references) only count when the string
      // actually names a passage — ordinary assignments are ignored
      if (link.candidate && !names.has(link.target)) continue;
      const key = `${p.name}\u0000${link.target}\u0000${link.kind}`;
      if (seen.has(key)) continue;
      seen.add(key);
      edges.push({
        source: p.name,
        target: link.target,
        kind: link.kind,
        utilitySource: !isStory(p),
        broken: link.kind !== 'dynamic' && !names.has(link.target),
      });
    }
  }

  const hasIncoming = new Set(edges.filter(e => !e.broken && e.kind !== 'dynamic').map(e => e.target));
  const hasOutgoing = new Set(edges.map(e => e.source));

  // Passages reached from code/data (string literals in script files) or via
  // runtime naming conventions (marked by tags like "dream") are not orphans.
  const codeRefs = {};
  if (opts.codeLiterals) {
    for (const p of storyPassages) {
      const refs = opts.codeLiterals.get(p.name);
      if (refs) codeRefs[p.name] = refs;
    }
  }
  const dynamicTags = new Set(opts.dynamicTags || []);
  const dynamicTagged = storyPassages
    .filter(p => p.tags.some(t => dynamicTags.has(t)))
    .map(p => p.name);
  const dynTaggedSet = new Set(dynamicTagged);

  // Composed-name heuristic: runtime code often builds passage names from
  // string fragments (e.g. starName + ' - ' + locationName). If a passage
  // name can be assembled from literals found in the code/twee corpus, it is
  // probably reached dynamically — report it separately, not as an orphan.
  const literals = opts.codeLiterals || new Map();
  const litList = [...new Set([...literals.keys()]
    .filter(l => l.length >= 3).map(l => l.toLowerCase()))];
  // Can `name` be segmented into 2+ known literals (optionally joined by
  // separators like " - ", "_", " ")? Classic word-break DP. Case-insensitive:
  // code often stores ids lowercase ('shipyard') and capitalizes at runtime.
  const composedFrom = rawName => {
    const name = rawName.toLowerCase();
    const seps = [' - ', '_', ' '];
    const memo = new Map();
    const walk = (i, parts) => {
      if (i === name.length) return parts >= 2 ? [] : null;
      const key = i + ':' + Math.min(parts, 2);
      if (memo.has(key)) return memo.get(key);
      memo.set(key, null); // guard against rescanning failures
      for (const lit of litList) {
        if (name.startsWith(lit, i)) {
          const rest = walk(i + lit.length, parts + 1);
          if (rest) { const r = [lit, ...rest]; memo.set(key, r); return r; }
        }
      }
      for (const sep of seps) {
        if (parts > 0 && name.startsWith(sep, i)) {
          const rest = walk(i + sep.length, parts);
          if (rest) { memo.set(key, rest); return rest; }
        }
      }
      return null;
    };
    return walk(0, 0);
  };

  const composed = [];
  const orphans = [];
  for (const p of storyPassages) {
    if (p.name === start || hasIncoming.has(p.name)
      || codeRefs[p.name] || dynTaggedSet.has(p.name)) continue;
    const parts = composedFrom(p.name);
    if (parts) composed.push({ name: p.name, parts });
    else orphans.push(p.name);
  }
  // Return-to-caller widgets (dialog/popup pattern): <<linkBack>> returns to
  // the previous passage, <<wakeupLink>> ends a dream and returns to
  // $sleepLocation. Passages containing one are NOT dead ends.
  const returnRe = (opts.returnMacros || []).length
    ? new RegExp(`<<(?:${opts.returnMacros.join('|')})[\\s>]`) : null;
  const returners = new Set(
    storyPassages.filter(p => returnRe && returnRe.test(p.text)).map(p => p.name));

  const endings = storyPassages
    .filter(p => !hasOutgoing.has(p.name) && !returners.has(p.name))
    .map(p => p.name);
  const broken = edges.filter(e => e.broken);
  const dynamic = edges.filter(e => e.kind === 'dynamic');

  return {
    start,
    passages: storyPassages.map(p => ({
      name: p.name,
      tags: p.tags,
      file: p.file,
      rel: p.rel,
      folder: p.folder,
      line: p.line,
      text: p.text.trim(),
      words: p.text.trim().split(/\s+/).filter(Boolean).length,
    })),
    specials: passages.filter(p => !isStory(p)).map(p => ({ name: p.name, file: p.file, line: p.line })),
    edges,
    codeRefs,
    issues: { orphans, broken, dynamic, endings, dynamicTagged, composed, codeReferenced: Object.keys(codeRefs).sort(), returners: [...returners].sort() },
  };
}

module.exports = { parseTweeFile, extractLinks, buildStoryModel };
