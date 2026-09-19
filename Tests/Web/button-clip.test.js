'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { loadBrowserModule } = require('./helpers/load-browser-module.js');

const MODULE_PATH = path.join(
  __dirname, '..', '..', 'Sources', 'Baguette', 'Resources', 'Web',
  'baguette', 'parts', 'button.js'
);

function Button() {
  return loadBrowserModule(MODULE_PATH).Baguette._Button;
}

// A button's DOM overlay must show exactly what the baked composite
// shows: the body plus `buttonMargins` around it, nothing further. The
// bake clips by drawing on a canvas that size; the overlay clips each
// button with an inset expressed in percent of the button's own box,
// which is what CSS clip-path takes.
const viewport = { width: 660, height: 924 };
const margins = { top: 10, left: 10, bottom: 10, right: 10 };

test('a cap fully inside the canvas needs no clip', () => {
  const box = { leftPct: 10, topPct: 10, widthPct: 5, heightPct: 2 };
  assert.equal(Button().clipInset(box, viewport, margins), null);
});

test('iPhone Duo phone14 power: a tall cap on the top edge keeps only the margin', () => {
  // X Power BTN is 16×107 anchored top; at rest its top edge sits at
  // -95 px in bare coordinates. The canvas starts at -10, so 85 of
  // the 107 px are clipped from the top: 85 / 107 = 79.44%.
  const box = {
    leftPct: 196 / 660 * 100, topPct: -95 / 924 * 100,
    widthPct: 16 / 660 * 100, heightPct: 107 / 924 * 100,
  };
  assert.equal(Button().clipInset(box, viewport, margins), 'inset(79.44% 0% 0% 0%)');
});

test('a cap poking past the left rail is clipped from the left', () => {
  // Vol BTN 63×16 centred 5 px in from the left edge: spans -26.5..36.5.
  const box = {
    leftPct: -26.5 / 660 * 100, topPct: 114 / 924 * 100,
    widthPct: 63 / 660 * 100, heightPct: 16 / 924 * 100,
  };
  // 16.5 px past the canvas edge (-10) → 16.5 / 63 = 26.19%.
  assert.equal(Button().clipInset(box, viewport, margins), 'inset(0% 0% 0% 26.19%)');
});

test('a cap past the right and bottom edges is clipped on those sides', () => {
  const box = {
    leftPct: (660 - 5) / 660 * 100, topPct: (924 - 5) / 924 * 100,
    widthPct: 25 / 660 * 100, heightPct: 25 / 924 * 100,
  };
  // Spans 655..680 horizontally against a canvas ending at 670: 10/25.
  assert.equal(Button().clipInset(box, viewport, margins), 'inset(0% 40% 40% 0%)');
});

test('no margins means clipping to the body itself', () => {
  const box = { leftPct: -10 / 660 * 100, topPct: 0, widthPct: 20 / 660 * 100, heightPct: 2 };
  assert.equal(Button().clipInset(box, viewport, undefined), 'inset(0% 0% 0% 50%)');
});
