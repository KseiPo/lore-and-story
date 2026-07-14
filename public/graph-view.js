/* Shared graph engine — used by both the story-flow view and the lore view.
   This is the seed of the "universal graph-view library" (ARCHITECTURE.md ADR 6). */
'use strict';

const BASE_STYLE = [
  { selector: 'node', style: {
    width: 14, height: 14,
    label: 'data(label)', color: '#aeb4c4', 'font-size': 7,
    'text-valign': 'bottom', 'text-margin-y': 3, 'text-wrap': 'ellipsis', 'text-max-width': 90,
  } },
  { selector: 'node[color]', style: { 'background-color': 'data(color)' } },
  { selector: 'edge', style: {
    width: 1, 'line-color': '#3d4354',
    'target-arrow-shape': 'triangle', 'target-arrow-color': '#3d4354',
    'arrow-scale': 0.7, 'curve-style': 'straight',
  } },
  { selector: '.dim', style: { opacity: 0.12 } },
  { selector: 'node.hit', style: { 'border-width': 4, 'border-color': '#5b9cf5' } },
  { selector: 'node:selected', style: { 'border-width': 4, 'border-color': '#fff' } },
];

/** Create a graph view in a container. Returns {cy, focus, select, run}. */
function createGraphView(opts) {
  const cy = cytoscape({
    container: opts.container,
    elements: opts.elements,
    wheelSensitivity: 0.25,
    layout: opts.layout,
    style: [...BASE_STYLE, ...(opts.style || [])],
  });

  cy.on('tap', 'node', evt => opts.onNodeTap && opts.onNodeTap(evt.target));
  cy.on('tap', evt => {
    if (evt.target === cy) {
      cy.elements().removeClass('dim');
      if (opts.onBackground) opts.onBackground();
    }
  });

  const view = {
    cy,
    focus(node) {
      const hood = node.closedNeighborhood();
      cy.elements().addClass('dim');
      hood.removeClass('dim');
    },
    select(id) {
      const node = cy.getElementById(id);
      if (node.nonempty()) {
        cy.elements().unselect();
        node.select();
        view.focus(node);
        cy.animate({ center: { eles: node }, zoom: Math.max(cy.zoom(), 1.0) }, { duration: 250 });
      }
      return node;
    },
    highlight(query) {
      cy.nodes().removeClass('hit');
      if (query && query.length >= 2) {
        cy.nodes().filter(n => (n.data('label') || '').toLowerCase().includes(query)).addClass('hit');
      }
      return cy.nodes('.hit');
    },
  };
  return view;
}
