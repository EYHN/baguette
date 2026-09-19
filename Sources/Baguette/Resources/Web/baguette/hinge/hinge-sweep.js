// HingeSweep — one pose change of a foldable's hinge, as the runtime
// reports it: the samples Device Hub sweeps through, with their times.
//
// Measured on iPhone Duo / iOS 27.1 through `devicectl device motion
// hinge-angle`: Device Hub's poses are 0° (closed), 130° (open) and
// 180° (flat), and a change between them is a 0.5–0.85 s ease-out at
// 60 Hz (3.8° → 130° took 0.84 s). SpringBoard swaps which panel is
// lit at 90°. The page draws the fold from live samples on the panel
// it has, and — because the swap means a reload — records a sweep so
// the panel it arrives at can replay it with the same timing.
(function (root) {
  'use strict';

  const SWAP_DEGREES = 90;
  /** Device Hub's open pose, measured; the bend is centred from here up. */
  const OPEN_POSE_DEGREES = 130;

  class HingeSweep {
    constructor(samples) {
      /** @type {Array<[number, number]>} [offsetMs, degrees] */
      this.samples = samples ? samples.slice() : [];
      this._startedAt = null;
      this._lastAt = null;
    }

    /**
     * Each leaf's turn about the seam for a hinge angle. The bend is
     * centred, as Device Hub draws it: the spine stays put and both
     * pages take half the fold, rising toward the viewer. Positive
     * rotateY brings an element's left edge forward, so the left leaf
     * turns positive and the right negative.
     */
    static leafTransforms(degrees) {
      const fold = Math.max(0, Math.min(180, 180 - degrees));
      const half = fold / 2;
      // Above the open pose the bend is centred. Below it the book is
      // shutting: the cover is the back of the left half, so the left
      // leaf folds over onto the right, taking the right leaf's share
      // of the bend as the angle falls — ±half at the open pose, the
      // whole fold on the left and the right flat when shut.
      const share = Math.max(0, Math.min(1, degrees / OPEN_POSE_DEGREES));
      const right = -half * share;
      const left = fold + right;
      const r = (v) => Math.round(v * 100) / 100;
      return { left: `rotateY(${r(left)}deg)`, right: `rotateY(${r(right)}deg)` };
    }

    push(degrees, atMs) {
      if (this._startedAt === null) this._startedAt = atMs;
      this._lastAt = atMs;
      this.samples.push([atMs - this._startedAt, degrees]);
    }

    get length() { return this.samples.length; }
    get from() { return this.samples.length ? this.samples[0][1] : null; }
    get to() { return this.samples.length ? this.samples[this.samples.length - 1][1] : null; }
    get opening() { return this.samples.length > 1 && this.to > this.from; }
    get durationMs() { return this.samples.length ? this.samples[this.samples.length - 1][0] : 0; }
    get litPanel() { return this.to !== null && this.to >= SWAP_DEGREES ? 'secondary' : 'primary'; }

    /** No sample for `quietMs`: the runtime has stopped moving. */
    settled(nowMs, quietMs) {
      return this._lastAt !== null && nowMs - this._lastAt >= quietMs;
    }

    toJSON() { return { samples: this.samples }; }

    static fromJSON(json) {
      const samples = json && Array.isArray(json.samples) ? json.samples : [];
      return new HingeSweep(samples.filter(s => Array.isArray(s) && s.length === 2));
    }

    /** Hands each sample on at its recorded offset. `schedule(fn, ms)`
     *  defaults to setTimeout; injectable so the timing is testable. */
    replay(onAngle, schedule) {
      const later = schedule || ((fn, ms) => setTimeout(fn, ms));
      for (const [offset, degrees] of this.samples) later(() => onAngle(degrees), offset);
      return this.durationMs;
    }
  }

  root.Baguette = root.Baguette || {};
  root.Baguette.HingeSweep = HingeSweep;
  root.Baguette.HINGE_SWAP_DEGREES = SWAP_DEGREES;
  root.Baguette.HINGE_OPEN_POSE_DEGREES = OPEN_POSE_DEGREES;
})(window);
