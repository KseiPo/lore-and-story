/* Lore & Story POC — graph UI. The server re-parses the twee files on every
   fetch; this file only renders derived data and never owns any state. */
'use strict';

cytoscape.use(cytoscapeDagre);

const $ = sel => document.querySelector(sel);
const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let cy = null;
let data = null;
const hiddenFolders = new Set();
const folderColor = {};

function assignFolderColors(passages) {
  const folders = [...new Set(passages.map(p => p.folder))].sort();
  folders.forEach((f, i) => {
    folderColor[f] = `hsl(${Math.round(i * 137.5) % 360}, 55%, 58%)`;
  });
}

function visiblePassages() {
  const storyOnly = $('#storyOnly').checked;
  return data.story.passages.filter(p =>
    !hiddenFolders.has(p.folder) && (!storyOnly || p.tags.includes('story'))
  );
}

function buildElements() {
  const passages = visiblePassages();
  const names = new Set(passages.map(p => p.name));
  const elements = [];

  for (const p of passages) {
    elements.push({
      data: {
        id: p.name, label: p.name, folder: p.folder,
        color: folderColor[p.folder],
        isStart: p.name === data.story.start,
        isOrphan: data.story.issues.orphans.includes(p.name),
      },
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
    } else if (!names.has(target)) return; // target filtered out of view
    elements.push({
      data: { id: 'e' + i, source: e.source, target },
      classes: (e.broken ? 'brokenedge' : '') + (e.kind === 'include' ? ' includeedge' : '')
        + (e.kind === 'stored' ? ' storededge' : ''),
    });
  });
  return elements;
}

function render() {
  const t0 = performance.now();
  const elements = buildElements();
  if (cy) cy.destroy();
  cy = cytoscape({
    container: $('#graph'),
    elements,
    wheelSensitivity: 0.25,
    layout: {
      name: 'dagre', rankDir: $('#rankdir').value,
      nodeSep: 18, rankSep: 55, edgeSep: 8,
    },
    style: [
      { selector: 'node', style: {
        width: 14, height: 14,
        label: 'data(label)', color: '#aeb4c4', 'font-size': 7,
        'text-valign': 'bottom', 'text-margin-y': 3, 'text-wrap': 'ellipsis', 'text-max-width': 90,
      } },
      { selector: 'node[color]', style: { 'background-color': 'data(color)' } },
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
      { selector: 'edge', style: {
        width: 1, 'line-color': '#3d4354',
        'target-arrow-shape': 'triangle', 'target-arrow-color': '#3d4354',
        'arrow-scale': 0.7, 'curve-style': 'straight',
      } },
      { selector: 'edge.brokenedge', style: { 'line-color': '#e05252', 'target-arrow-color': '#e05252', 'line-style': 'dashed' } },
      { selector: 'edge.includeedge', style: { 'line-color': '#5b9cf5', 'target-arrow-color': '#5b9cf5', 'line-style': 'dotted' } },
      { selector: 'edge.storededge', style: { 'line-color': '#a97ff0', 'target-arrow-color': '#a97ff0', 'line-style': 'dashed' } },
      { selector: '.dim', style: { opacity: 0.12 } },
      { selector: 'node.hit', style: { 'border-width': 4, 'border-color': '#5b9cf5' } },
      { selector: 'node:selected', style: { 'border-width': 4, 'border-color': '#fff' } },
    ],
  });
  const layoutMs = Math.round(performance.now() - t0);

  // A full fit of 300+ nodes shrinks them to invisible dots; start readable
  // instead, centered on the start passage.
  if (cy.zoom() < 0.45) {
    const startNode = cy.getElementById(data.story.start);
    cy.zoom(0.6);
    if (startNode.nonempty()) cy.center(startNode);
  }

  cy.on('tap', 'node', evt => {
    const node = evt.target;
    focusNeighborhood(node);
    if (!node.hasClass('ghost')) showPassage(node.id());
  });
  cy.on('tap', evt => {
    if (evt.target === cy) { cy.elements().removeClass('dim'); hideDetail(); }
  });

  const s = data.story;
  $('#stats').textContent =
    `${s.passages.length} passages · ${s.edges.length} links · parse ${data.parseMs} ms · layout ${layoutMs} ms`;
}

function focusNeighborhood(node) {
  const hood = node.closedNeighborhood();
  cy.elements().addClass('dim');
  hood.removeClass('dim');
}

function selectByName(name) {
  const node = cy.getElementById(name);
  if (node.nonempty()) {
    cy.elements().unselect();
    node.select();
    focusNeighborhood(node);
    cy.animate({ center: { eles: node }, zoom: Math.max(cy.zoom(), 1.2) }, { duration: 250 });
    showPassage(name);
  }
}

/* ---------- sidebar ---------- */

function issueSection(title, cls, items, render) {
  if (!items.length) return `<div class="issue-head ok">✓ ${title} <span class="cnt">0</span></div>`;
  const rows = items.map(render).join('');
  return `<div class="issue-head ${cls}">${title} <span class="cnt">${items.length}</span></div><div class="issue-list">${rows}</div>`;
}

function renderSidebar() {
  const iss = data.story.issues;
  $('#issues').innerHTML = '<h2>Analysis</h2>' +
    issueSection('Orphan passages', 'warn', iss.orphans,
      n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`) +
    issueSection('Broken links', 'err', iss.broken,
      e => `<div class="item" data-sel="${esc(e.source)}">${esc(e.source)} → <b>${esc(e.target)}</b></div>`) +
    issueSection('Dynamic links', 'info', iss.dynamic,
      e => `<div class="item" data-sel="${esc(e.source)}">${esc(e.source)} → ${esc(e.target)}</div>`) +
    issueSection('Dead ends (endings?)', 'info', iss.endings,
      n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`) +
    issueSection('Composed names (heuristic)', 'info', iss.composed,
      c => `<div class="item" data-sel="${esc(c.name)}" title="${esc(c.parts.join(' + '))}">${esc(c.name)}</div>`) +
    issueSection('Reached from code', 'info', iss.codeReferenced,
      n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`) +
    issueSection('Dynamic by tag', 'info', iss.dynamicTagged,
      n => `<div class="item" data-sel="${esc(n)}">${esc(n)}</div>`);

  const counts = {};
  for (const p of data.story.passages) counts[p.folder] = (counts[p.folder] || 0) + 1;
  $('#folders').innerHTML = '<h2>Folders (click to toggle)</h2>' +
    Object.keys(counts).sort().map(f =>
      `<div class="item folder ${hiddenFolders.has(f) ? 'muted' : ''}" data-folder="${esc(f)}">
        <span class="dot" style="background:${folderColor[f]}"></span>${esc(f)}<span class="cnt">${counts[f]}</span></div>`
    ).join('');

  const byCat = {};
  for (const l of data.lore) (byCat[l.category] = byCat[l.category] || []).push(l);
  $('#lore').innerHTML = '<h2>Lore (sample data)</h2>' +
    Object.keys(byCat).sort().map(cat =>
      `<div class="issue-head">${esc(cat)}</div>` +
      byCat[cat].map(l =>
        `<div class="item" data-lore="${esc(l.id)}">${esc(l.title)}<span class="cnt">${l.mentionedIn.length} ref</span></div>`
      ).join('')
    ).join('');
}

/* ---------- detail panel ---------- */

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
    <button class="closebtn" onclick="document.querySelector('#detail').classList.add('hidden')">✕</button>
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

function showLore(id) {
  const l = data.lore.find(x => x.id === id);
  if (!l) return;
  $('#detail').innerHTML = `
    <button class="closebtn" onclick="document.querySelector('#detail').classList.add('hidden')">✕</button>
    <div class="md">${marked.parse(l.text)}</div>
    <h3>Mentioned in ${l.mentionedIn.length} passages</h3>
    ${l.mentionedIn.map(n => `<a class="linkrow" data-sel="${esc(n)}">${esc(n)}</a>`).join('') || '<span class="kind">nowhere yet</span>'}`;
  $('#detail').classList.remove('hidden');

  if (cy) {
    cy.elements().addClass('dim');
    l.mentionedIn.forEach(n => cy.getElementById(n).removeClass('dim').addClass('hit'));
  }
}

/* ---------- events ---------- */

document.addEventListener('click', evt => {
  const t = evt.target.closest('[data-sel],[data-folder],[data-lore]');
  if (!t) return;
  if (t.dataset.sel) selectByName(t.dataset.sel);
  else if (t.dataset.lore) showLore(t.dataset.lore);
  else if (t.dataset.folder) {
    const f = t.dataset.folder;
    hiddenFolders.has(f) ? hiddenFolders.delete(f) : hiddenFolders.add(f);
    render(); renderSidebar();
  }
});

$('#search').addEventListener('input', () => {
  const q = $('#search').value.trim().toLowerCase();
  cy.nodes().removeClass('hit');
  if (q.length < 2) return;
  cy.nodes().filter(n => n.id().toLowerCase().includes(q)).addClass('hit');
});
$('#search').addEventListener('keydown', evt => {
  if (evt.key === 'Enter') {
    const hit = cy.nodes('.hit').first();
    if (hit.nonempty()) selectByName(hit.id());
  }
});

$('#storyOnly').addEventListener('change', () => { render(); });
$('#rankdir').addEventListener('change', () => { render(); });
$('#fit').addEventListener('click', () => cy.fit(undefined, 30));
$('#rescan').addEventListener('click', load);

const events = new EventSource('/api/events');
events.onmessage = () => load();
events.onerror = () => $('#live').classList.add('off');
events.onopen = () => $('#live').classList.remove('off');

async function load() {
  const res = await fetch('/api/data');
  data = await res.json();
  if (data.error) { $('#stats').textContent = 'ERROR: ' + data.error; return; }
  assignFolderColors(data.story.passages);
  renderSidebar();
  render();
}
load();
