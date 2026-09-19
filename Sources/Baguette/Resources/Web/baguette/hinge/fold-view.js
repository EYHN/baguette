// FoldView — the device drawn as a book while its hinge moves.
//
// The page renders one flat device: a bare bezel <img> and the live
// screen <canvas> inside a wrapper that CSS-rotates for orientation.
// While the hinge is turning, this draws that same device — bezel plus
// the frame the stream just painted, rotated as the page shows it —
// into two canvases clipped at the seam, and turns the right leaf
// about the seam in perspective by the runtime's own angle
// (`HingeSweep.leafTransform`). The flat device is hidden underneath
// and comes back the moment the sweep settles, so taps always land on
// flat geometry. Integration-only: composition and DOM, no rules.
(function (root) {
  'use strict';

  class FoldView {
    /**
     * @param {HTMLElement} frameRoot   #nativeDeviceFrame — wrapper > img + screen area > canvas
     * @param {() => number} rotation   the page's current CSS rotation in degrees
     */
    constructor(frameRoot, rotation) {
      this.root = frameRoot;
      this.rotation = rotation;
      this.stage = null;
      this.left = null;
      this.right = null;
      this.scratch = document.createElement('canvas');
      this.raf = null;
      this.angle = 180;
    }

    get showing() { return !!this.stage; }

    /** Draw at this hinge angle, mounting the stage on first call. */
    update(degrees) {
      this.angle = degrees;
      if (!this.stage && !this._mount()) return;
      this.right.style.transform = root.Baguette.HingeSweep.leafTransform(degrees);
      if (!this.raf) this._tick();
    }

    /** Take the stage down and show the flat device again. */
    hide() {
      if (this.raf) { cancelAnimationFrame(this.raf); this.raf = null; }
      if (this.stage) { this.stage.remove(); this.stage = null; this.left = this.right = null; }
      this.root.style.visibility = '';
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
      const stage = document.createElement('div');
      stage.style.cssText = [
        'position:fixed', `left:${rect.left}px`, `top:${rect.top}px`,
        `width:${rect.width}px`, `height:${rect.height}px`,
        'z-index:60', 'pointer-events:none', 'perspective:2200px',
        'perspective-origin:50% 50%',
      ].join(';');
      const dpr = window.devicePixelRatio || 1;
      const leaf = (clip) => {
        const c = document.createElement('canvas');
        c.width = Math.round(rect.width * dpr);
        c.height = Math.round(rect.height * dpr);
        c.style.cssText = [
          'position:absolute', 'inset:0', 'width:100%', 'height:100%',
          `clip-path:${clip}`, 'transform-origin:50% 50%',
          'backface-visibility:hidden', 'will-change:transform',
        ].join(';');
        return c;
      };
      this.left = leaf('inset(0 50% 0 0)');
      this.right = leaf('inset(0 0 0 50%)');
      stage.appendChild(this.left);
      stage.appendChild(this.right);
      document.body.appendChild(stage);
      this.stage = stage;
      this.rect = rect;
      this.dpr = dpr;
      this.root.style.visibility = 'hidden';
      return true;
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
        sc.save();
        const r = parseFloat(screenArea.style.borderRadius) || 0;
        if (r > 0 && sc.roundRect) {
          sc.beginPath(); sc.roundRect(sx, sy, sw, sh, Math.min(sw, sh) * r / 100); sc.clip();
        }
        sc.drawImage(canvas, sx, sy, sw, sh);
        sc.restore();
      }
      const deg = this.rotation();
      const sideways = Math.abs(deg % 180) === 90;
      const dw = sideways ? this.rect.height : this.rect.width;
      const dh = sideways ? this.rect.width : this.rect.height;
      for (const leaf of [this.left, this.right]) {
        const ctx = leaf.getContext('2d');
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
