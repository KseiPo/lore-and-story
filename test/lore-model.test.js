'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { loadLore } = require('../lib/lore');
const { normalize } = require('./fixtures/lore-model/normalize');

const CASES_DIR = path.join(__dirname, 'fixtures', 'lore-model', 'cases');

const cases = fs
  .readdirSync(CASES_DIR, { withFileTypes: true })
  .filter(d => d.isDirectory())
  .map(d => d.name)
  .sort();

assert.ok(cases.length > 0, 'no fixture cases found');

for (const name of cases) {
  test(`lore-model: ${name}`, () => {
    const dir = path.join(CASES_DIR, name);
    const goldenFile = path.join(dir, 'expected.json');

    assert.ok(
      fs.existsSync(goldenFile),
      `missing golden: ${goldenFile} — run \`npm run goldens\``
    );

    const actual = normalize(loadLore(path.join(dir, 'lore')));
    const expected = JSON.parse(fs.readFileSync(goldenFile, 'utf8'));
    assert.deepStrictEqual(actual, expected);
  });
}
