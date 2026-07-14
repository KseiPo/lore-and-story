/* Coordinator: loads data, switches between story/lore views, routes cross-view
   clicks (a passage's lore mention → lore view; a lore mention → story view). */
'use strict';

cytoscape.use(cytoscapeDagre);

const $ = sel => document.querySelector(sel);
let data = null;
let current = 'story';
let loreLoaded = false;

function switchView(name) {
  current = name;
  $('#story-view').classList.toggle('hidden', name !== 'story');
  $('#lore-view').classList.toggle('hidden', name !== 'lore');
  $('#storyControls').classList.toggle('hidden', name !== 'story');
  $('#loreControls').classList.toggle('hidden', name !== 'lore');
  for (const b of document.querySelectorAll('#tabs button')) b.classList.toggle('active', b.dataset.view === name);
  // Lore graph must lay out while visible (cytoscape needs real container size).
  if (name === 'lore' && data && !loreLoaded) { LoreView.setData(data); loreLoaded = true; }
  if (name === 'story') StoryView.refreshStats();
}

document.querySelectorAll('#tabs button').forEach(b =>
  b.addEventListener('click', () => switchView(b.dataset.view)));

// Delegated clicks shared by both views.
document.addEventListener('click', evt => {
  const t = evt.target.closest('[data-sel],[data-folder],[data-lore],[data-passage],[data-item],[data-close]');
  if (!t) return;
  if (t.dataset.close) { $('#' + t.dataset.close).classList.add('hidden'); return; }
  if (t.dataset.item) LoreView.showItem(t.dataset.item, t.dataset.lang);       // sub-entry (with optional language)
  else if (t.dataset.sel) StoryView.select(t.dataset.sel);
  else if (t.dataset.folder) StoryView.toggleFolder(t.dataset.folder);
  else if (t.dataset.passage) { switchView('story'); StoryView.select(t.dataset.passage); }
  else if (t.dataset.lore) { switchView('lore'); if (!loreLoaded) { LoreView.setData(data); loreLoaded = true; } LoreView.show(t.dataset.lore); }
});

StoryView.wireEvents();
LoreView.wireEvents();
$('#rescan').addEventListener('click', load);

const events = new EventSource('/api/events');
events.onmessage = () => load();
events.onerror = () => $('#live').classList.add('off');
events.onopen = () => $('#live').classList.remove('off');

async function load() {
  const res = await fetch('/api/data');
  data = await res.json();
  if (data.error) { $('#stats').textContent = 'ERROR: ' + data.error; return; }
  StoryView.setData(data);
  loreLoaded = false;
  if (current === 'lore') { LoreView.setData(data); loreLoaded = true; }
}
load();
