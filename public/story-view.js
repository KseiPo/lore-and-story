/* Story-flow view: passages graph + analysis sidebar + passage detail. */
'use strict';

const StoryView = (() => {
  let view = null;
  let data = null;
  let statsText = '';
  const hiddenFolders = new Set();
  const folderColor = {};

  const $ = sel => document.querySelector(sel);
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function assignFolderColors(passages) {
    [...new Set(passages.map(p => p.folder))].sort().forEach((f, i) => {
      folderColor[f] = `hsl(${Math.round(i * 137.5) % 360}, 55%, 58%)`;
    });
  }

  function visiblePassages() {
    const storyOnly = $('#storyOnly').checked;
    return data.story.passages.filter(p =>
      !hiddenFolders.has(p.folder) && (!storyOnly || p.tags.includes('story')));
  }

  function buildElements() {
    const passages = visiblePassages();
    const names = new Set(passages.map(p => p.name));
    const elements = [];
    for (const p of passages) {
      elements.push({
        data: { id: p.name, label: p.name, color: folderColor[p.folder] },
        classes: [
          p.name === data.story.start ? 'start' : '',
          data.story.issues.orphans.includes(p.name) ? 'orphan' : '',
          data.story.codeRefs[p.name] ? 'coderef' : '',
        ].join(' '),
      });
    }
    const ghosts = new Set();
    data.story.edges.forEach((e, i) => {
      if (e.kind === 'dynamic' || !names.has(e.source)) return;
      let target = e.target;
      if (e.broken) {
        target = 'ghost:' + e.target;
        if (!ghosts.has(target)) {
          ghosts.add(target);
          elements.push({ data: { id: target, label: e.target + ' ✕' }, classes: 'ghost' });
        }
      } else if (!names.has(target)) return;
      elements.push({
        data: { id: 'e' + i, source: e.source, target },
        classes: (e.broken ? 'brokenedge' : '') + (e.kind === 'include' ? ' includeedge' : '')
          + (e.kind === 'stored' ? ' storededge' : ''),
      });
    });
    return elements;
  }

  const STYLE = [
    { selector: 'node.start', style: {
      'background-color': '#4fc06d', width: 22, height: 22,
      'border-width': 3, 'border-color': '#a7e6ba', 'font-size': 9, color: '#d7f5e0',
    } },
    { selector: 'node.orphan', style: { 'border-width': 3, 'border-color': '#f0a13e' } },
    { selector: 'node.coderef', style: { 'border-width': 2, 'border-color': '#4ecdc4', 'border-style': 'double' } },
    { selector: 'node.ghost', style: {
      'background-color': '#2a1c1c', shape: 'rectangle', 'border-width': 1.5,
      'border-color': '#e05252', 'border-style': 'dashed', color: '#e08b8b',
    } },
    { selector: 'edge.brokenedge', style: { 'line-color': '#e05252', 'target-arrow-color': '#e05252', 'line-style': 'dashed' } },
    { selector: 'edge.includeedge', style: { 'line-color': '#5b9cf5', 'target-arrow-color': '#5b9cf5', 'line-style': 'dotted' } },
    { selector: 'edge.storededge', style: { 'line-color': '#a97ff0', 'target-arrow-color': '#a97ff0', 'line-style': 'dashed' } },
  ];

  function render() {
    const t0 = performance.now();
    if (view) view.cy.destroy();
    view = createGraphView({
      container: $('#graph'),
      elements: buildElements(),
      layout: { name: 'dagre', rankDir: $('#rankdir').value, nodeSep: 18, rankSep: 55, edgeSep: 8 },
      style: STYLE,
      onNodeTap: node => { view.focus(node); if (!node.hasClass('ghost')) showPassage(node.id()); },
      onBackground: hideDetail,
    });
    const layoutMs = Math.round(performance.now() - t0);
    if (view.cy.zoom() < 0.45) {
      view.cy.zoom(0.6);
      const start = view.cy.getElementById(data.story.start);
      if (start.nonempty()) view.cy.center(start);
    }
    const s = data.story;
    statsText = `${s.passages.length} passages · ${s.edges.length} links · ${data.lore.length} lore · parse ${data.parseMs} ms · layout ${layoutMs} ms`;
    $('#stats').textContent = statsText;
  }

  function issueSection(title, cls, items, renderItem) {
    if (!items.length) return `<div class="issue-head ok">✓ ${title} <span class="cnt">0</span></div>`;
    return `<div class="issue-head ${cls}">${title} <span class="cnt">${items.length}</span></div>
      <div class="issue-list">${items.map(renderItem).join('')}</div>`;
  }

  function renderSidebar() {
    const iss = data.story.issues;
    $('#issues').innerHTML = '<h2>Analysis</h2>' +
      issueSection('Orphan passages', 'warn', iss.orphans, n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`) +
      issueSection('Broken links', 'err', iss.broken, e => `<div class="item" data-sel="${esc(e.source)}">${esc(e.source)} → <b>${esc(e.target)}</b></div>`) +
      issueSection('Dynamic links', 'info', iss.dynamic, e => `<div class="item" data-sel="${esc(e.source)}">${esc(e.source)} → ${esc(e.target)}</div>`) +
      issueSection('Dead ends (endings?)', 'info', iss.endings, n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`) +
      issueSection('Composed names (heuristic)', 'info', iss.composed, c => `<div class="item" data-sel="${esc(c.name)}" title="${esc(c.parts.join(' + '))}">${esc(c.name)}</div>`) +
      issueSection('Reached from code', 'info', iss.codeReferenced, n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`) +
      issueSection('Dynamic by tag', 'info', iss.dynamicTagged, n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`);

    const counts = {};
    for (const p of data.story.passages) counts[p.folder] = (counts[p.folder] || 0) + 1;
    $('#folders').innerHTML = '<h2>Folders (click to toggle)</h2>' +
      Object.keys(counts).sort().map(f =>
        `<div class="item folder ${hiddenFolders.has(f) ? 'muted' : ''}" data-folder="${esc(f)}">
          <span class="dot" style="background:${folderColor[f]}"></span>${esc(f)}<span class="cnt">${counts[f]}</span></div>`).join('');
  }

  function hideDetail() { $('#detail').classList.add('hidden'); }

  function showPassage(name) {
    const p = data.story.passages.find(x => x.name === name);
    if (!p) return;
    const outgoing = data.story.edges.filter(e => e.source === name);
    const incoming = data.story.edges.filter(e => e.target === name);
    const vscode = `vscode://file/${encodeURI(p.file.replace(/\\/g, '/'))}:${p.line}`;
    const mentions = data.lore.filter(l => l.mentionedIn.includes(name));
    const refs = data.story.codeRefs[name];

    $('#detail').innerHTML = `
      <button class="closebtn" data-close="detail">✕</button>
      <h2>${esc(p.name)}</h2>
      <div class="meta">
        ${p.tags.map(t => `<span class="tag">${esc(t)}</span>`).join('')}
        ${p.words} words · <a href="${vscode}">${esc(p.rel)}:${p.line} ↗ VS Code</a>
      </div>
      <h3>Outgoing (${outgoing.length})</h3>
      ${outgoing.map(e => `<a class="linkrow" data-sel="${esc(e.target)}">→ ${esc(e.target)} <span class="kind">${e.kind}${e.broken ? ' · BROKEN' : ''}</span></a>`).join('') || '<span class="kind">none — dead end</span>'}
      <h3>Incoming (${incoming.length})</h3>
      ${incoming.map(e => `<a class="linkrow" data-sel="${esc(e.source)}">← ${esc(e.source)} <span class="kind">${e.kind}</span></a>`).join('') || '<span class="kind">none — orphan?</span>'}
      ${refs ? `<h3>Referenced in code</h3>${refs.map(f => `<div class="kind">⚙ ${esc(f)}</div>`).join('')}` : ''}
      ${mentions.length ? `<h3>Lore mentioned</h3>${mentions.map(l => `<a class="linkrow" data-lore="${esc(l.id)}">${esc(l.title)}</a>`).join('')}` : ''}
      <h3>Source</h3>
      <pre>${esc(p.text)}</pre>`;
    $('#detail').classList.remove('hidden');
  }

  function wireEvents() {
    $('#search').addEventListener('input', () => view && view.highlight($('#search').value.trim().toLowerCase()));
    $('#search').addEventListener('keydown', evt => {
      if (evt.key === 'Enter' && view) {
        const hit = view.cy.nodes('.hit').first();
        if (hit.nonempty()) { view.select(hit.id()); showPassage(hit.id()); }
      }
    });
    $('#storyOnly').addEventListener('change', render);
    $('#rankdir').addEventListener('change', render);
    $('#fit').addEventListener('click', () => view && view.cy.fit(undefined, 30));
  }

  return {
    wireEvents,
    setData(d) { data = d; assignFolderColors(d.story.passages); renderSidebar(); render(); },
    select(name) { if (view) { view.select(name); showPassage(name); } },
    toggleFolder(f) { hiddenFolders.has(f) ? hiddenFolders.delete(f) : hiddenFolders.add(f); render(); renderSidebar(); },
    refreshStats() { if (statsText) $('#stats').textContent = statsText; },
    showPassage,
  };
})();
