/* Lore view: entity graph (wikilinks + mentions) + category tree + entity detail
   with rendered markdown card, a nested content tree (events / quests / …),
   language-merged sub-entries (RU original + EN), and passage cross-links. */
'use strict';

const LoreView = (() => {
  let view = null;
  let data = null;
  let currentEntity = null;
  const catColor = {};

  const $ = sel => document.querySelector(sel);
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function assignColors() {
    [...new Set(data.lore.map(l => l.category.split('/')[0]))].sort().forEach((c, i) => {
      catColor[c] = `hsl(${Math.round(i * 137.5 + 40) % 360}, 60%, 60%)`;
    });
  }

  // walk a content tree collecting its merged items (for the graph)
  function flattenItems(node, acc = []) {
    if (!node) return acc;
    node.items.forEach(i => acc.push(i));
    node.children.forEach(c => flattenItems(c, acc));
    return acc;
  }
  function findItem(node, id) {
    if (!node) return null;
    for (const i of node.items) if (i.id === id) return i;
    for (const c of node.children) { const f = findItem(c, id); if (f) return f; }
    return null;
  }

  function buildElements() {
    const showMentions = $('#showMentions').checked;
    const showSubs = $('#showSubs').checked;
    const elements = [];
    for (const e of data.lore) {
      const items = flattenItems(e.tree);
      elements.push({
        data: {
          id: e.id, label: e.title, color: catColor[e.category.split('/')[0]],
          size: 14 + Math.min(e.mentionedIn.length, 30) * 0.9 + items.length * 1.5,
        },
        classes: 'entity',
      });
      if (showSubs) {
        for (const it of items) {
          elements.push({ data: { id: it.id, label: it.title, parentEntity: e.id }, classes: 'sub' });
          elements.push({ data: { id: 'sub:' + it.id, source: e.id, target: it.id }, classes: 'subedge' });
        }
      }
    }
    for (const edge of data.loreEdges) {
      if (edge.kind === 'mention' && !showMentions) continue;
      elements.push({
        data: { id: `le:${edge.source}:${edge.target}:${edge.kind}`, source: edge.source, target: edge.target },
        classes: edge.kind === 'link' ? 'linkedge' : 'mentionedge',
      });
    }
    return elements;
  }

  const STYLE = [
    { selector: 'node.entity', style: { width: 'data(size)', height: 'data(size)', 'font-size': 9, color: '#d6dae4' } },
    { selector: 'node.sub', style: {
      'background-color': '#39404f', shape: 'round-rectangle', width: 10, height: 10,
      'font-size': 6, color: '#8a91a3',
    } },
    { selector: 'edge.linkedge', style: { 'line-color': '#5b9cf5', 'target-arrow-color': '#5b9cf5', width: 1.5 } },
    { selector: 'edge.mentionedge', style: {
      'line-color': '#3d4354', 'target-arrow-color': '#3d4354', 'line-style': 'dashed',
      width: 1, 'target-arrow-shape': 'none',
    } },
    { selector: 'edge.subedge', style: { 'line-color': '#2e3342', 'target-arrow-shape': 'none', width: 1 } },
  ];

  function render() {
    const t0 = performance.now();
    if (view) view.cy.destroy();
    view = createGraphView({
      container: $('#loreGraph'),
      elements: buildElements(),
      layout: { name: 'cose', animate: false, nodeRepulsion: 9000, idealEdgeLength: 60, padding: 30 },
      style: STYLE,
      onNodeTap: node => {
        view.focus(node);
        if (node.hasClass('sub')) showEntity(node.data('parentEntity'), node.id());
        else showEntity(node.id());
      },
      onBackground: () => $('#loreDetail').classList.add('hidden'),
    });
    const layoutMs = Math.round(performance.now() - t0);
    if (view.cy.zoom() < 0.4) view.cy.fit(undefined, 40);
    $('#stats').textContent =
      `${data.lore.length} entities · ${data.loreEdges.length} relations · parse ${data.parseMs} ms · layout ${layoutMs} ms`;
  }

  function renderTree() {
    const byCat = {};
    for (const e of data.lore) (byCat[e.category] = byCat[e.category] || []).push(e);
    $('#loreTree').innerHTML = '<h2>Lore entities</h2>' +
      Object.keys(byCat).sort().map(cat =>
        `<div class="issue-head"><span class="dot" style="background:${catColor[cat.split('/')[0]]}"></span>${esc(cat)} <span class="cnt">${byCat[cat].length}</span></div>` +
        byCat[cat].map(e => {
          const n = flattenItems(e.tree).length;
          return `<div class="item" data-lore="${esc(e.id)}">${esc(e.title)}
            <span class="cnt">${n ? '📁' + n + ' · ' : ''}${e.mentionedIn.length}💬</span></div>`;
        }).join('')).join('');
  }

  function rewriteMedia(text, relDir) {
    return text.replace(/!\[([^\]]*)\]\((?!https?:|\/)([^)]+)\)/g,
      (m, alt, src) => `![${alt}](/lore-files/${encodeURI(relDir + '/' + src.replace(/^\.\//, ''))})`);
  }

  // drop a body's own leading H1 + mapping comment (the title is already shown as the row/section header)
  function stripHead(text) {
    return text.replace(/^\s*#\s+.*(?:\r?\n)+/, '').replace(/^<!--[^>]*-->\s*(?:\r?\n)+/, '');
  }
  const bodyMd = (text, relDir) => marked.parse(stripHead(rewriteMedia(text, relDir)));

  // render one content node (section) recursively as sidebar-style rows
  function renderNode(node) {
    let html = '';
    if (node.title) html += `<h3 class="sec">${esc(node.title)}</h3>`;
    if (node.overview) html += `<div class="overview md">${bodyMd(node.overview.text, node.overview.relDir)}</div>`;
    for (const it of node.items) {
      const langs = Object.keys(it.langs);
      const badges = (langs.includes('ru') ? '<span class="lang">RU</span>' : '')
        + (langs.includes('en') ? '<span class="lang">EN</span>' : '');
      html += `<a class="linkrow" data-item="${esc(it.id)}">${esc(it.title)} ${badges}</a>`;
    }
    for (const c of node.children) html += `<div class="subsec">${renderNode(c)}</div>`;
    return html;
  }

  function showEntity(id, focusItemId, focusLang) {
    const e = data.lore.find(x => x.id === id);
    if (!e) return;
    currentEntity = e;
    const card = marked.parse(rewriteMedia(e.text, e.relDir));

    const links = data.loreEdges.filter(x => x.source === id && x.kind === 'link')
      .map(x => data.lore.find(l => l.id === x.target)).filter(Boolean);
    const backlinks = data.loreEdges.filter(x => x.target === id && x.kind === 'link')
      .map(x => data.lore.find(l => l.id === x.source)).filter(Boolean);

    let subBody = '';
    if (focusItemId) {
      const item = findItem(e.tree, focusItemId);
      if (item) {
        const langKeys = Object.keys(item.langs);
        const lang = focusLang && item.langs[focusLang] ? focusLang
          : (item.langs.ru ? 'ru' : item.langs.en ? 'en' : langKeys[0]);
        const v = item.langs[lang];
        const toggle = langKeys.length > 1
          ? '<span class="langtoggle">' + langKeys.map(k =>
              `<button data-item="${esc(item.id)}" data-lang="${k}" class="${k === lang ? 'on' : ''}">${k.toUpperCase()}</button>`).join('') + '</span>'
          : '';
        const passage = item.passage
          ? `<a class="linkrow" data-passage="${esc(item.passage)}">→ open passage: ${esc(item.passage)}</a>` : '';
        subBody = `<div class="subentry"><h3>▸ ${esc(v.title)} ${toggle}</h3>${passage}
          <div class="md">${bodyMd(v.text, v.relDir)}</div></div>`;
      }
    }

    $('#loreDetail').innerHTML = `
      <button class="closebtn" data-close="loreDetail">✕</button>
      <div class="meta"><span class="tag">${esc(e.category)}</span> ${e.mentionedIn.length} passage mentions</div>
      <div class="md">${card}</div>
      ${e.tree ? `<div class="content-tree">${renderNode(e.tree)}</div>` : ''}
      ${subBody}
      ${links.length ? `<h3>Links to</h3>${links.map(l => `<a class="linkrow" data-lore="${esc(l.id)}">→ ${esc(l.title)}</a>`).join('')}` : ''}
      ${backlinks.length ? `<h3>Linked from</h3>${backlinks.map(l => `<a class="linkrow" data-lore="${esc(l.id)}">← ${esc(l.title)}</a>`).join('')}` : ''}
      ${e.mentionedIn.length ? `<h3>Mentioned in passages (${e.mentionedIn.length})</h3>${e.mentionedIn.map(n => `<a class="linkrow" data-passage="${esc(n)}">${esc(n)}</a>`).join('')}` : ''}`;
    $('#loreDetail').classList.remove('hidden');

    if (view) { view.cy.elements().removeClass('hit'); view.cy.getElementById(id).addClass('hit'); }
  }

  function wireEvents() {
    $('#loreSearch').addEventListener('input', () => view && view.highlight($('#loreSearch').value.trim().toLowerCase()));
    $('#loreSearch').addEventListener('keydown', evt => {
      if (evt.key === 'Enter' && view) {
        const hit = view.cy.nodes('.hit').first();
        if (hit.nonempty()) { view.select(hit.id()); showEntity(hit.id()); }
      }
    });
    $('#showMentions').addEventListener('change', render);
    $('#showSubs').addEventListener('change', render);
    $('#loreFit').addEventListener('click', () => view && view.cy.fit(undefined, 40));
  }

  return {
    wireEvents,
    setData(d) { data = d; assignColors(); renderTree(); render(); },
    show(id) { if (view) view.select(id); showEntity(id); },
    showItem(itemId, lang) { if (currentEntity) showEntity(currentEntity.id, itemId, lang); },
    rendered() { return !!view; },
  };
})();
