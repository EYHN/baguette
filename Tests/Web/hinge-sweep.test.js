'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { loadBrowserModule } = require('./helpers/load-browser-module.js');

const MODULE_PATH = path.join(
  __dirname, '..', '..', 'Sources', 'Baguette', 'Resources', 'Web',
  'baguette', 'hinge', 'hinge-sweep.js'
);

function load() {
  return loadBrowserModule(MODULE_PATH).Baguette;
}

// Device Hub's pose change, as devicectl reports it: 0° closed, 130°
// its open pose, 180° flat, swept over 0.5–0.85 s at 60 Hz with an
// ease-out (measured 3.8 → 130 in 0.84 s). The page draws the fold
// from these samples, and replays a recorded sweep on the panel it
// arrives at after the swap.

test('both leaves turn about the seam by half the fold: flat at 180°, edge-on at 0°', () => {
  const { HingeSweep } = load();
  // Device Hub's bend is centred — the spine stays put and both
  // pages rise toward the viewer. Positive rotateY brings the left
  // edge forward, negative the right, so the two get opposite halves.
  assert.deepEqual(HingeSweep.leafTransforms(180), { left: 'rotateY(0deg)', right: 'rotateY(0deg)' });
  assert.deepEqual(HingeSweep.leafTransforms(130), { left: 'rotateY(25deg)', right: 'rotateY(-25deg)' });
  assert.deepEqual(HingeSweep.leafTransforms(0), { left: 'rotateY(90deg)', right: 'rotateY(-90deg)' });
});

test('a sweep records samples with their times and knows its direction', () => {
  const { HingeSweep } = load();
  const s = new HingeSweep();
  s.push(3.8, 1000); s.push(57, 1030); s.push(130, 1840);
  assert.equal(s.length, 3);
  assert.equal(s.from, 3.8);
  assert.equal(s.to, 130);
  assert.equal(s.opening, true);
  assert.equal(s.durationMs, 840);
});

test('a sweep is settled once no sample has landed for the quiet window', () => {
  const { HingeSweep } = load();
  const s = new HingeSweep();
  s.push(130, 1000); s.push(60, 1200);
  assert.equal(s.settled(1300, 250), false);
  assert.equal(s.settled(1460, 250), true);
  assert.equal(s.opening, false);
});

test('which panel a settled sweep leaves lit follows the 90° boundary', () => {
  const { HingeSweep } = load();
  const open = new HingeSweep(); open.push(0, 0); open.push(130, 800);
  const shut = new HingeSweep(); shut.push(130, 0); shut.push(2, 800);
  assert.equal(open.litPanel, 'secondary');
  assert.equal(shut.litPanel, 'primary');
});

test('a sweep round-trips through JSON for the hand-off across a reload', () => {
  const { HingeSweep } = load();
  const s = new HingeSweep();
  s.push(3.8, 1000); s.push(130, 1840);
  const back = HingeSweep.fromJSON(JSON.parse(JSON.stringify(s.toJSON())));
  assert.deepEqual(back.samples, [[0, 3.8], [840, 130]]);
  assert.equal(back.to, 130);
});

test('replaying a sweep hands each sample on at its recorded offset', () => {
  const { HingeSweep } = load();
  const s = new HingeSweep();
  s.push(0, 100); s.push(60, 130); s.push(130, 160);
  const calls = [];
  const timers = [];
  const schedule = (fn, ms) => { timers.push([ms, fn]); };
  s.replay((a) => calls.push(a), schedule);
  assert.deepEqual(timers.map(t => t[0]), [0, 30, 60]);
  timers.forEach(t => t[1]());
  assert.deepEqual(calls, [0, 60, 130]);
});
