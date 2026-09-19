// FoldView — the unfolded panel drawn as a book at the hinge's angle.
//
// The page renders one flat device: a bare bezel <img> and the live
// screen <canvas> inside a wrapper that CSS-rotates for orientation.
// Device Hub's open pose is 130°, a visibly bent book, and its sweeps
// turn the hinge at 60 Hz — so on a foldable this draws that same
// device (bezel plus the frame the stream just painted, rotated as the
// page shows it, clipped with the simulator's own mask) into two
// leaves, each a real half page hinged at the seam, and turns them in
// perspective by the runtime's angle (`HingeSweep.leafAngles`).
//
// The left leaf is two-faced: the unfolded panel on its front and the
// live cover, mirrored, on its back — so shutting the book turns the
// cover toward the viewer and lays it on the right half, and opening
// starts from there. The leaves are plain half-width boxes, not
// clip-paths: `clip-path` flattens an element's 3D context and the
// back face would never show through.
//
// It stays up while the device is bent and hands input through: the
// leaves carry 1×1 markers at the screen's corners, the browser
// projects those through the 3D transform, and `mapClientPoint`
// inverts each leaf's projected quad with `ScreenQuad.locate` — the
// same hook the 3D stage uses — so a click on the tilted leaf lands
// where it looks. Flat (≥ FLAT_DEGREES) the stage comes down and the
// flat device takes input again.
//
// The shut book is the cover on the left leaf's back; the page shows
// the real cover panel afterwards, in its own place and size.
// `moveProgress` slides and scales the whole stage between the two,
// driven by the hinge angle over its last degrees, so the swap is
// invisible and the slide is part of the fold. Integration-only: DOM
// and canvas.
(function (root) {
  'use strict';

  const FLAT_DEGREES = 178;

  class FoldView {
    /**
     * @param {HTMLElement} frameRoot   #nativeDeviceFrame — wrapper > img + screen area > canvas
     * @param {() => number} rotation   the page's current CSS rotation in degrees
     * @param {object} [screenDef]      definition.screen — for the mask
     * @param {object} [screenPart]     the SDK Screen part, to rebind input
     * @param {object} [opts]           `front.wrapper()` — the unfolded
     *   panel's mounted wrapper (default: the wrapper the frame shows);
     *   `back.wrapper()` / `back.maskImage` — the cover's.
     */
    constructor(frameRoot, rotation, screenDef, screenPart, opts) {
      this.root = frameRoot;
      this.rotation = rotation;
      this.screenDef = screenDef || null;
      this.screenPart = screenPart || null;
      this.front = (opts && opts.front) || null;
      // The cover is the back of the left leaf. `back.wrapper()` yields
      // the cover panel's mounted wrapper (bezel + live canvas), drawn
      // mirrored onto the leaf's reverse so that shutting the book
      // turns the cover toward the viewer — black until the guest
      // lights it, exactly as Device Hub shows it.
      this.back = (opts && opts.back) || null;
      this.backMask = null;
      if (this.back && this.back.maskImage) {
        const m = new Image();
        m.src = this.back.maskImage;
        m.onload = () => { this.backMask = m; };
      }
      this.stage = null;
      this.leaves = null;
      this.scratch = document.createElement('canvas');
      this.backScratch = document.createElement('canvas');
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
      const a = root.Baguette.HingeSweep.leafAngles(degrees);
      this.leafAngles = a;
      this.leaves.left.el.style.transform = `rotateY(${a.left}deg)`;
      this.leaves.right.el.style.transform = `rotateY(${a.right}deg)`;
      // Past the seam the left leaf lies on the right one; the stage
      // is flat (siblings paint in order), so stack it by hand.
      this.leaves.left.el.style.zIndex = a.left > 90 ? '2' : '1';
      if (!this.raf) this._tick();
    }

    /** The sweep has stopped: stay bent, or come down when flat. */
    settle(degrees) {
      if (degrees >= FLAT_DEGREES) { this.hide(); return; }
      this.update(degrees);
    }

    /** Stop redrawing; the leaves keep their last frame. For the moment
     *  the panel under the stage is being swapped for the other one. */
    freeze() {
      if (this.raf) { cancelAnimationFrame(this.raf); this.raf = null; }
    }

    /** Take the stage down without touching the device underneath —
     *  it is no longer the one this view was built on. */
    dispose() {
      this.freeze();
      window.removeEventListener('resize', this._onResize);
      if (this.stage) { this.stage.remove(); this.stage = null; this.leaves = null; }
      this.root.style.visibility = '';
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

    _parts(wrapper) {
      // A foldable's frame holds both panels' wrappers; the unfolded
      // one is the device this view draws — named by `front`, else
      // whichever the frame shows.
      wrapper = wrapper || (this.front && this.front.wrapper && this.front.wrapper())
        || Array.from(this.root.querySelectorAll(':scope > div'))
          .find((w) => w.style.display !== 'none') || null;
      const img = wrapper && wrapper.querySelector(':scope > img');
      const canvas = wrapper && wrapper.querySelector('canvas');
      if (!wrapper || !img || !canvas) return null;
      return { wrapper, img, canvas, screenArea: canvas.parentElement };
    }

    // The hardware buttons the SDK mounted over `wrapper`, drawn where
    // they sit: below the bezel (poking through its slots) or above it,
    // trimmed as their overlay is.
    _drawButtons(sc, wrapper, W, H, above) {
      for (const btn of wrapper.querySelectorAll('button[data-btn]')) {
        if ((btn.style.zIndex === '2') !== above) continue;
        const img = btn.querySelector('img');
        if (!img || !img.complete || !img.naturalWidth) continue;
        const pct = (v) => parseFloat(v) / 100;
        const x = pct(btn.style.left) * W, y = pct(btn.style.top) * H;
        const w = pct(btn.style.width) * W, h = pct(btn.style.height) * H;
        if (!(w > 0 && h > 0)) continue;
        sc.save();
        const m = /inset\(([^)]*)\)/.exec(btn.style.clipPath || '');
        if (m) {
          // The browser serialises the inset as a CSS shorthand: one to
          // four values, top / right / bottom / left.
          const v = m[1].trim().split(/\s+/).map((n) => parseFloat(n) / 100);
          const t = v[0], r = v.length > 1 ? v[1] : t;
          const bt = v.length > 2 ? v[2] : t, l = v.length > 3 ? v[3] : r;
          sc.beginPath(); sc.rect(x + l * w, y + t * h, w * (1 - l - r), h * (1 - t - bt)); sc.clip();
        }
        sc.drawImage(img, x, y, w, h);
        sc.restore();
      }
    }

    // Bezel, buttons and live frame (clipped with the panel's mask) in
    // the wrapper's own layout space, drawn into `scratch` with a
    // margin all round for the buttons that stand proud of the body.
    // Returns the scratch with its CSS-pixel size and that margin, or
    // null when there is nothing to draw yet. With `seam`, the body is
    // two hinged halves: their corners at the seam are rounded, which
    // notches the edge where they meet, and the crease runs between.
    _compose(parts, mask, scratch, def, seam) {
      const { wrapper, img, canvas, screenArea } = parts;
      // A hidden wrapper has no layout; size it like the bezel image.
      let W = wrapper.offsetWidth, H = wrapper.offsetHeight;
      if ((W < 2 || H < 2) && img.naturalWidth) {
        W = img.naturalWidth; H = img.naturalHeight;
      }
      if (W < 2 || H < 2) return null;
      const vp = def && def.viewport;
      const px = vp && vp.width ? W / vp.width : 1;   // CSS px per chrome px
      const mg = (def && def.buttonMargins) || {};
      const pad = Math.ceil(Math.max(mg.top || 0, mg.left || 0, mg.bottom || 0, mg.right || 0) * px);
      const SW = W + 2 * pad, SH = H + 2 * pad;
      if (scratch.width !== Math.round(SW * this.dpr) || scratch.height !== Math.round(SH * this.dpr)) {
        scratch.width = Math.round(SW * this.dpr); scratch.height = Math.round(SH * this.dpr);
      }
      const sc = scratch.getContext('2d');
      sc.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      sc.clearRect(0, 0, SW, SH);
      sc.translate(pad, pad);
      this._drawButtons(sc, wrapper, W, H, false);
      sc.save();
      if (seam) {
        // Two bodies meeting at the seam, each with rounded corners.
        const r = Math.max(2, ((def && def.rect && def.rect.x) || 0) * 1.2 * px);
        const tall = H >= W;
        sc.beginPath();
        if (tall) { sc.roundRect(0, 0, W, H / 2, r); sc.roundRect(0, H / 2, W, H / 2, r); }
        else      { sc.roundRect(0, 0, W / 2, H, r); sc.roundRect(W / 2, 0, W / 2, H, r); }
        sc.clip();
      }
      if (img.complete && img.naturalWidth) sc.drawImage(img, 0, 0, W, H);
      // The screen rect: from layout when there is one, else from the
      // definition's percentages against the bezel's natural size.
      let sx = screenArea.offsetLeft, sy = screenArea.offsetTop;
      let sw = screenArea.offsetWidth, sh = screenArea.offsetHeight;
      if (sw < 2 || sh < 2) {
        const pct = (v) => parseFloat(v) / 100;
        sx = pct(screenArea.style.left) * W; sy = pct(screenArea.style.top) * H;
        sw = pct(screenArea.style.width) * W; sh = pct(screenArea.style.height) * H;
      }
      if (canvas.width && canvas.height && sw > 0 && sh > 0) {
        if (mask) {
          const f = scratch._frame || (scratch._frame = document.createElement('canvas'));
          if (f.width !== Math.round(sw * this.dpr) || f.height !== Math.round(sh * this.dpr)) {
            f.width = Math.round(sw * this.dpr); f.height = Math.round(sh * this.dpr);
          }
          const fc = f.getContext('2d');
          fc.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
          fc.globalCompositeOperation = 'source-over';
          fc.clearRect(0, 0, sw, sh);
          fc.drawImage(canvas, 0, 0, sw, sh);
          fc.globalCompositeOperation = 'destination-in';
          fc.drawImage(mask, 0, 0, sw, sh);
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
        if (seam) {
          // The crease, as the flat page draws it.
          sc.fillStyle = 'rgba(0,0,0,0.28)';
          if (H >= W) sc.fillRect(sx, sy + sh / 2 - 0.5, sw, 1);
          else        sc.fillRect(sx + sw / 2 - 0.5, sy, 1, sh);
        }
      }
      sc.restore();
      this._drawButtons(sc, wrapper, W, H, true);
      return { scratch, width: SW, height: SH, pad };
    }

    // The hardware buttons that stand on the body's edges, as the
    // page shows them: which edge, where along it and how long. Each
    // SDK button is a box in the wrapper's own (portrait) space; it is
    // turned as the wrapper is and read against the body's outline.
    _edgeButtons(wrapper, rotation, rect) {
      const out = [];
      const turn = ((rotation % 360) + 360) % 360;
      const Wp = turn % 180 === 90 ? rect.height : rect.width;
      const Hp = turn % 180 === 90 ? rect.width : rect.height;
      const pct = (v) => parseFloat(v) / 100;
      for (const btn of wrapper.querySelectorAll('button[data-btn]')) {
        const x = pct(btn.style.left) * Wp, y = pct(btn.style.top) * Hp;
        const w = pct(btn.style.width) * Wp, h = pct(btn.style.height) * Hp;
        if (!(w > 0 && h > 0)) continue;
        let r;
        if (turn === 90)       r = { x: Hp - y - h, y: x, w: h, h: w };
        else if (turn === 180) r = { x: Wp - x - w, y: Hp - y - h, w, h };
        else if (turn === 270) r = { x: y, y: Wp - x - w, w: h, h: w };
        else                   r = { x, y, w, h };
        if (r.x < 0)                      out.push({ edge: 'left', at: r.y, extent: r.h });
        else if (r.x + r.w > rect.width)  out.push({ edge: 'right', at: r.y, extent: r.h });
        else if (r.y < 0)                 out.push({ edge: 'top', at: r.x, extent: r.w });
        else if (r.y + r.h > rect.height) out.push({ edge: 'bottom', at: r.x, extent: r.w });
      }
      return out;
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
        'z-index:60', 'perspective:1400px', 'perspective-origin:50% 50%',
        'cursor:crosshair', 'touch-action:none', '-webkit-user-select:none', 'user-select:none',
      ].join(';');
      const dpr = window.devicePixelRatio || 1;
      const marker = (x, y) => {
        const m = document.createElement('div');
        m.style.cssText = `position:absolute;left:${x}px;top:${y}px;width:1px;height:1px;pointer-events:none;`;
        return m;
      };
      const halfW = rect.width / 2;
      // Room outside the body for the buttons that stand proud of it.
      const pad = Math.ceil(rect.width * 0.03);
      // The body's thickness: each leaf is a slab, not a sheet. Its
      // outer, top and bottom edges are faces standing back from the
      // screen, so a tilted leaf shows its side the way Device Hub's
      // model does, and the shut book has a spine.
      const T = Math.max(4, Math.round(rect.width * 0.03));
      const rotation = this.rotation();
      const nubs = this._edgeButtons(parts.wrapper, rotation, rect);
      const leaf = (side) => {
        const el = document.createElement('div');
        el.style.cssText = [
          'position:absolute', 'top:0', 'height:100%', `width:${halfW}px`,
          side === 'left' ? 'left:0' : `left:${halfW}px`,
          side === 'left' ? 'transform-origin:100% 50%' : 'transform-origin:0 50%',
          'transform-style:preserve-3d', 'will-change:transform',
        ].join(';');
        // The canvas overhangs the leaf's outer edge and top and bottom
        // by `pad`, never the seam.
        const cw = halfW + pad, ch = rect.height + 2 * pad;
        const cbox = `position:absolute;left:${side === 'left' ? -pad : 0}px;top:${-pad}px;`
          + `width:${cw}px;height:${ch}px;pointer-events:none;backface-visibility:hidden;`;
        const c = document.createElement('canvas');
        c.width = Math.round(cw * dpr);
        c.height = Math.round(ch * dpr);
        c.style.cssText = cbox;
        el.appendChild(c);
        // The edges. Each face is hinged on the leaf's outline and
        // turned to stand behind the screen; the outer face carries
        // the buttons that sit on that edge as raised nubs.
        const face = (css) => {
          const f = document.createElement('div');
          f.style.cssText = 'position:absolute;pointer-events:none;'
            + 'background:linear-gradient(to right,#2c2c2f,#0e0e10);'
            + `border-radius:${T / 2}px;` + css;
          el.appendChild(f);
          return f;
        };
        const outer = side === 'left'
          ? face(`left:0;top:0;width:${T}px;height:100%;transform-origin:0 50%;transform:rotateY(90deg)`)
          : face(`right:0;top:0;width:${T}px;height:100%;transform-origin:100% 50%;transform:rotateY(-90deg)`);
        const top = face(`left:0;top:0;width:100%;height:${T}px;transform-origin:50% 0;transform:rotateX(-90deg)`);
        const bottom = face(`left:0;bottom:0;width:100%;height:${T}px;transform-origin:50% 100%;transform:rotateX(90deg)`);
        for (const n of nubs) {
          const onThisLeaf = n.edge === side || ((n.edge === 'top' || n.edge === 'bottom')
            && (side === 'left' ? n.at < halfW : n.at >= halfW));
          if (!onThisLeaf) continue;
          const nub = document.createElement('div');
          const along = n.edge === side ? `top:${n.at}px;height:${n.extent}px;left:1px;right:1px;`
            : `left:${n.at - (side === 'right' ? halfW : 0)}px;width:${n.extent}px;top:1px;bottom:1px;`;
          nub.style.cssText = 'position:absolute;background:#3a3a3d;border-radius:2px;' + along;
          (n.edge === side ? outer : n.edge === 'top' ? top : bottom).appendChild(nub);
        }
        // The left leaf's reverse: the cover, pre-turned so it faces the
        // viewer once the leaf has swung past the seam, and set back by
        // the body's thickness — it is the far side of the slab.
        let back = null;
        if (side === 'left' && this.back) {
          back = document.createElement('canvas');
          back.width = c.width; back.height = c.height;
          // Pre-turned about its own centre: canvas x = 0 is the seam,
          // x = halfW the outer edge and the overhang lies beyond it.
          back.style.cssText = cbox + `transform:translateZ(${-T}px) rotateY(180deg);`;
          el.appendChild(back);
        }
        // Screen corners of this leaf's half, leaf-local: TL, TR, BR, BL.
        const x0 = side === 'left' ? screenBox.left : 0;
        const x1 = side === 'left' ? halfW : screenBox.left + screenBox.width - halfW;
        const y0 = screenBox.top, y1 = screenBox.top + screenBox.height;
        const corners = [marker(x0, y0), marker(x1, y0), marker(x1, y1), marker(x0, y1)];
        corners.forEach((m) => el.appendChild(m));
        return { el, canvas: c, back, corners };
      };
      this.leaves = { left: leaf('left'), right: leaf('right') };
      stage.appendChild(this.leaves.left.el);
      stage.appendChild(this.leaves.right.el);
      document.body.appendChild(stage);
      this.stage = stage;
      this.rect = rect;
      this.pad = pad;
      // The unfolded panel's rotation, taken now: the page may show
      // the cover (portrait) under the stage before the book is shut.
      this.frontRotation = this.rotation();
      this.halfW = halfW;
      this.dpr = dpr;
      this.coverBox = null;
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

    // Draw the unfolded panel rotated as the page shows it into both
    // leaves, and the cover mirrored onto the left leaf's reverse.
    _tick() {
      this.raf = requestAnimationFrame(() => { this.raf = null; if (this.stage) this._tick(); });
      const parts = this._parts();
      if (!parts) return;
      const front = this._compose(parts, this.mask, this.scratch, this.screenDef, !!(this.screenDef && this.screenDef.crease));
      if (!front) return;
      const deg = this.frontRotation;
      // The scratch is the wrapper's own layout (portrait); the
      // rotation below turns it as the page shows it.
      const dw = front.width, dh = front.height;
      const halfW = this.halfW, H = this.rect.height, pad = this.pad;
      const cw = halfW + pad, ch = H + 2 * pad;
      for (const side of ['left', 'right']) {
        const ctx = this.leaves[side].canvas.getContext('2d');
        ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
        ctx.clearRect(0, 0, cw, ch);
        ctx.save();
        // Each leaf holds its own half of the whole device, centred on
        // the seam; the canvas origin sits `pad` outside the leaf box.
        ctx.translate(side === 'left' ? halfW + pad : 0, H / 2 + pad);
        ctx.rotate(deg * Math.PI / 180);
        ctx.drawImage(front.scratch, -dw / 2, -dh / 2, dw, dh);
        ctx.restore();
        // A bent page is lit from the front: its face darkens toward
        // the spine the further it turns away. Only the body takes the
        // shade (source-atop), never the transparent surround.
        const tilt = this.leafAngles ? Math.abs(this.leafAngles[side]) : 0;
        const shade = Math.min(0.45, tilt / 90 * 0.45);
        if (shade > 0.01) {
          const seamX = side === 'left' ? cw : 0, outerX = side === 'left' ? 0 : cw;
          const g = ctx.createLinearGradient(outerX, 0, seamX, 0);
          g.addColorStop(0, 'rgba(0,0,0,0)');
          g.addColorStop(1, `rgba(0,0,0,${shade})`);
          ctx.save();
          ctx.globalCompositeOperation = 'source-atop';
          ctx.fillStyle = g;
          ctx.fillRect(0, 0, cw, ch);
          ctx.restore();
        }
      }
      const back = this.leaves.left.back;
      const coverWrapper = back && this.back.wrapper && this.back.wrapper();
      const coverParts = coverWrapper && this._parts(coverWrapper);
      if (!back || !coverParts) return;
      const cover = this._compose(coverParts, this.backMask, this.backScratch,
        this.back.screen || null, false);
      const ctx = back.getContext('2d');
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      ctx.clearRect(0, 0, cw, ch);
      if (!cover) return;
      // The cover fills the leaf edge to edge: shut, it is the same
      // physical half as the leaf under it, so its outline must cover
      // that leaf's exactly (the aspects differ by a few percent). It
      // is drawn as-is — the canvas is pre-turned by 180°, and the
      // leaf's own turn brings it back around to read normally.
      this.coverBox = { x: 0, y: 0, w: halfW, h: H };
      const bw = cover.width - 2 * cover.pad, bh = cover.height - 2 * cover.pad;
      const sx = halfW / bw, sy = H / bh;
      // Hinge side at canvas x = 0, outer edge at halfW (see the
      // canvas's own note), its buttons in the overhang beyond.
      ctx.drawImage(cover.scratch, -cover.pad * sx, pad - cover.pad * sy, cover.width * sx, cover.height * sy);
    }

    /** Where the cover shows on the shut book, in client coordinates:
     *  the left leaf turned onto the right half, its back facing out. */
    coverRect() {
      if (!this.stage || !this.coverBox) return null;
      const b = this.coverBox;
      // rotateY(180°) about the seam maps leaf-local x to 2·halfW − x.
      return {
        left: this.rect.left + 2 * this.halfW - b.x - b.w,
        top: this.rect.top + b.y,
        width: b.w, height: b.h,
      };
    }

    /**
     * Slide and scale the stage so that, at `progress` 1, the shut
     * book's cover lies exactly on `target` (a client rect — the real
     * cover in its own place); at 0 the stage is where the unfolded
     * panel is. Driven by the hinge over its last degrees, so the
     * book glides into the cover's place as it shuts, and out of it
     * as it opens.
     */
    moveProgress(progress, target) {
      if (!this.stage) return;
      const p = Math.max(0, Math.min(1, progress));
      const st = this.stage.style;
      const c = this.coverRect();
      if (p === 0 || !c || !target || !target.width) {
        st.transform = ''; st.transformOrigin = '';
        return;
      }
      const s = target.width / c.width;
      const dx = target.left + target.width / 2 - (c.left + c.width / 2);
      const dy = target.top + target.height / 2 - (c.top + c.height / 2);
      st.transformOrigin = `${c.left - this.rect.left + c.width / 2}px ${c.top - this.rect.top + c.height / 2}px`;
      st.transform = `translate(${dx * p}px, ${dy * p}px) scale(${1 + (s - 1) * p})`;
    }
  }

  root.Baguette = root.Baguette || {};
  root.Baguette._FoldView = FoldView;
})(window);
