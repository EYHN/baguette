// FoldView — the unfolded panel drawn as a book at the hinge's angle.
//
// The page renders one flat device: a bare bezel <img> and the live
// screen <canvas> inside a wrapper that CSS-rotates for orientation.
// Device Hub's open pose is 130°, a visibly bent book, and its sweeps
// turn the hinge at 60 Hz — so on a foldable this draws that same
// device (bezel plus the frame the stream just painted, rotated as the
// page shows it, clipped with the simulator's own mask) into two
// leaves split at the seam, and turns the right leaf about the seam
// in perspective by the runtime's angle (`HingeSweep.leafTransform`).
//
// It stays up while the device is bent and hands input through: the
// leaves carry 1×1 markers at the screen's corners, the browser
// projects those through the 3D transform, and `mapClientPoint`
// inverts each leaf's projected quad with `ScreenQuad.locate` — the
// same hook the 3D stage uses — so a click on the tilted leaf lands
// where it looks. Flat (≥ FLAT_DEGREES) the stage comes down and the
// flat device takes input again. Integration-only: DOM and canvas.
(function (root) {
  'use strict';

  const FLAT_DEGREES = 178;

  class FoldView {
    /**
     * @param {HTMLElement} frameRoot   #nativeDeviceFrame — wrapper > img + screen area > canvas
     * @param {() => number} rotation   the page's current CSS rotation in degrees
     * @param {object} [screenDef]      definition.screen — for the mask
     * @param {object} [screenPart]     the SDK Screen part, to rebind input
     */
    constructor(frameRoot, rotation, screenDef, screenPart) {
      this.root = frameRoot;
      this.rotation = rotation;
      this.screenDef = screenDef || null;
      this.screenPart = screenPart || null;
      this.stage = null;
      this.leaves = null;
      this.scratch = document.createElement('canvas');
      this.raf = null;
      this.angle = 180;
      this.mask = null;
      if (this.screenDef && this.screenDef.maskImage) {
        const m = new Image();
        m.src = this.screenDef.maskImage;
        m.onload = () => { this.mask = m; };
      }
      this._onResize = () => { if (this.stage) { const a = this.angle; this.hide(); this.update(a); } };
    }

    static get FLAT_DEGREES() { return FLAT_DEGREES; }

    get showing() { return !!this.stage; }

    /** Draw at this hinge angle, mounting the stage on first call. */
    update(degrees) {
      this.angle = degrees;
      if (!this.stage && !this._mount()) return;
      const t = root.Baguette.HingeSweep.leafTransforms(degrees);
      this.leaves.left.el.style.transform = t.left;
      this.leaves.right.el.style.transform = t.right;
      if (!this.raf) this._tick();
    }

    /** The sweep has stopped: stay bent, or come down when flat. */
    settle(degrees) {
      if (degrees >= FLAT_DEGREES) { this.hide(); return; }
      this.update(degrees);
    }

    /** Take the stage down and hand input back to the flat device. */
    hide() {
      if (this.raf) { cancelAnimationFrame(this.raf); this.raf = null; }
      window.removeEventListener('resize', this._onResize);
      if (this.stage) { this.stage.remove(); this.stage = null; this.leaves = null; }
      this.root.style.visibility = '';
      const parts = this._parts();
      if (this.screenPart && parts) {
        this.screenPart.bindDOM({ screenArea: parts.screenArea, canvas: parts.canvas });
      }
    }

    _parts() {
      const wrapper = this.root.querySelector(':scope > div');
      const img = wrapper && wrapper.querySelector(':scope > img');
      const canvas = wrapper && wrapper.querySelector('canvas');
      if (!wrapper || !img || !canvas) return null;
      return { wrapper, img, canvas, screenArea: canvas.parentElement };
    }

    _mount() {
      const parts = this._parts();
      if (!parts) return false;
      const rect = parts.wrapper.getBoundingClientRect();
      if (rect.width < 10 || rect.height < 10) return false;
      // Where the screen sits inside the stage, in the visual frame.
      const sr = parts.screenArea.getBoundingClientRect();
      const screenBox = {
        left: sr.left - rect.left, top: sr.top - rect.top, width: sr.width, height: sr.height,
      };
      const seamX = rect.width / 2;

      const stage = document.createElement('div');
      stage.style.cssText = [
        'position:fixed', `left:${rect.left}px`, `top:${rect.top}px`,
        `width:${rect.width}px`, `height:${rect.height}px`,
        'z-index:60', 'perspective:2200px', 'perspective-origin:50% 50%',
        'cursor:crosshair', 'touch-action:none', '-webkit-user-select:none', 'user-select:none',
      ].join(';');
      const dpr = window.devicePixelRatio || 1;
      const marker = (x, y) => {
        const m = document.createElement('div');
        m.style.cssText = `position:absolute;left:${x}px;top:${y}px;width:1px;height:1px;pointer-events:none;`;
        return m;
      };
      const leaf = (side) => {
        const el = document.createElement('div');
        el.style.cssText = [
          'position:absolute', 'inset:0',
          side === 'left' ? 'clip-path:inset(0 50% 0 0)' : 'clip-path:inset(0 0 0 50%)',
          'transform-origin:50% 50%', 'backface-visibility:hidden', 'will-change:transform',
        ].join(';');
        const c = document.createElement('canvas');
        c.width = Math.round(rect.width * dpr);
        c.height = Math.round(rect.height * dpr);
        c.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none;';
        el.appendChild(c);
        // Screen corners of this leaf's half: TL, TR, BR, BL.
        const x0 = side === 'left' ? screenBox.left : seamX;
        const x1 = side === 'left' ? seamX : screenBox.left + screenBox.width;
        const y0 = screenBox.top, y1 = screenBox.top + screenBox.height;
        const corners = [marker(x0, y0), marker(x1, y0), marker(x1, y1), marker(x0, y1)];
        corners.forEach((m) => el.appendChild(m));
        return { el, canvas: c, corners };
      };
      this.leaves = { left: leaf('left'), right: leaf('right') };
      stage.appendChild(this.leaves.left.el);
      stage.appendChild(this.leaves.right.el);
      document.body.appendChild(stage);
      this.stage = stage;
      this.rect = rect;
      this.dpr = dpr;
      this.seamFraction = (seamX - screenBox.left) / screenBox.width;
      this.root.style.visibility = 'hidden';
      window.addEventListener('resize', this._onResize);
      if (this.screenPart) {
        this.screenPart.bindInteraction({
          element: stage, overlayHost: stage,
          mapClientPoint: (cx, cy) => this.mapClientPoint(cx, cy),
        });
      }
      return true;
    }

    _quad(leaf) {
      const pts = leaf.corners.map((m) => {
        const r = m.getBoundingClientRect();
        return [r.left + r.width / 2, r.top + r.height / 2];
      });
      return root.Baguette._ScreenQuad.fromCorners(pts);
    }

    /** Client point → screen point, through whichever leaf it lands on. */
    mapClientPoint(clientX, clientY) {
      const size = (this.screenPart && this.screenPart.size) || { width: 1, height: 1 };
      const miss = { x: 0, y: 0, xNorm: 0, yNorm: 0, inside: false };
      if (!this.leaves) return miss;
      const s = this.seamFraction;
      const right = this._quad(this.leaves.right).locate(clientX, clientY);
      if (right.inside) {
        const xNorm = s + right.u * (1 - s), yNorm = right.v;
        return { x: xNorm * size.width, y: yNorm * size.height, xNorm, yNorm, inside: true };
      }
      const left = this._quad(this.leaves.left).locate(clientX, clientY);
      if (left.inside) {
        const xNorm = left.u * s, yNorm = left.v;
        return { x: xNorm * size.width, y: yNorm * size.height, xNorm, yNorm, inside: true };
      }
      return miss;
    }

    // Compose bezel + live frame in the wrapper's own (unrotated) layout
    // space, then draw that rotated into both leaves.
    _tick() {
      this.raf = requestAnimationFrame(() => { this.raf = null; if (this.stage) this._tick(); });
      const parts = this._parts();
      if (!parts) return;
      const { wrapper, img, canvas, screenArea } = parts;
      const W = wrapper.offsetWidth, H = wrapper.offsetHeight;
      if (W < 2 || H < 2) return;
      const s = this.scratch;
      if (s.width !== Math.round(W * this.dpr) || s.height !== Math.round(H * this.dpr)) {
        s.width = Math.round(W * this.dpr); s.height = Math.round(H * this.dpr);
      }
      const sc = s.getContext('2d');
      sc.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      sc.clearRect(0, 0, W, H);
      if (img.complete && img.naturalWidth) sc.drawImage(img, 0, 0, W, H);
      const sx = screenArea.offsetLeft, sy = screenArea.offsetTop;
      const sw = screenArea.offsetWidth, sh = screenArea.offsetHeight;
      if (canvas.width && canvas.height && sw > 0 && sh > 0) {
        if (this.mask) {
          const f = this.frameScratch || (this.frameScratch = document.createElement('canvas'));
          if (f.width !== Math.round(sw * this.dpr) || f.height !== Math.round(sh * this.dpr)) {
            f.width = Math.round(sw * this.dpr); f.height = Math.round(sh * this.dpr);
          }
          const fc = f.getContext('2d');
          fc.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
          fc.globalCompositeOperation = 'source-over';
          fc.clearRect(0, 0, sw, sh);
          fc.drawImage(canvas, 0, 0, sw, sh);
          fc.globalCompositeOperation = 'destination-in';
          fc.drawImage(this.mask, 0, 0, sw, sh);
          sc.drawImage(f, sx, sy, sw, sh);
        } else {
          sc.save();
          const r = parseFloat(screenArea.style.borderRadius) || 0;
          if (r > 0 && sc.roundRect) {
            sc.beginPath(); sc.roundRect(sx, sy, sw, sh, Math.min(sw, sh) * r / 100); sc.clip();
          }
          sc.drawImage(canvas, sx, sy, sw, sh);
          sc.restore();
        }
      }
      const deg = this.rotation();
      const sideways = Math.abs(deg % 180) === 90;
      const dw = sideways ? this.rect.height : this.rect.width;
      const dh = sideways ? this.rect.width : this.rect.height;
      for (const leaf of [this.leaves.left, this.leaves.right]) {
        const ctx = leaf.canvas.getContext('2d');
        ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
        ctx.clearRect(0, 0, this.rect.width, this.rect.height);
        ctx.save();
        ctx.translate(this.rect.width / 2, this.rect.height / 2);
        ctx.rotate(deg * Math.PI / 180);
        ctx.drawImage(s, -dw / 2, -dh / 2, dw, dh);
        ctx.restore();
      }
    }
  }

  root.Baguette = root.Baguette || {};
  root.Baguette._FoldView = FoldView;
})(window);
