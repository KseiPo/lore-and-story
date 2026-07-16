'use strict';

// Regenerates every cases/*/expected.json from the current lib/lore.js output.
// Run via `npm run goldens`, then READ THE DIFF — a golden change is a contract
// change (ADR 4) and must be intentional, not laundered through a regen.
//
// Lives outside test/ deliberately: `node --test test/` executes every .js it
// finds there, which would run this generator alongside the assertions and let
// the suite rewrite the goldens it is supposed to be checking.

const fs = require('fs');
const path = require('path');

const { loadLore } = require('../lib/lore');
const { normalize } = require('../test/fixtures/lore-model/normalize');

const CASES_DIR = path.join(__dirname, '..', 'test', 'fixtures', 'lore-model', 'cases');

for (const d of fs.readdirSync(CASES_DIR, { withFileTypes: true })) {
  if (!d.isDirectory()) continue;
  const dir = path.join(CASES_DIR, d.name);
  const model = normalize(loadLore(path.join(dir, 'lore')));
  fs.writeFileSync(
    path.join(dir, 'expected.json'),
    JSON.stringify(model, null, 2) + '\n',
    'utf8'
  );
  console.log(`${d.name}: ${model.entries.length} entities`);
}
