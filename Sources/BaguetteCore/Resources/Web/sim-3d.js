// sim-3d.js — live server-rendered 3D simulator stream.
(function () {
  'use strict';

  function Sim3DPanel() {
    this.host = null;
    this.stage = null;
    this.canvas = null;
    this.udid = '';
    this.model = null;
    this.session = null;
    this.format = 'mjpeg';
    this.background = '#f1f3f6';
    this.rotation = { x: -8, y: 18, z: 0 };
    this.zoom = 1;
    this.mode = 'pose';
    this.variants = {};
    this.screenGlass = false;
    this.deviceSize = { width: 1, height: 1 };
    this.onFps = null;
    this.pointer = null;
    this.interactiveScreen = null;
    // Where the screen mesh currently lands in the rendered image
    // (server-pushed `screen_quad`, normalized to the output frame) —
    // lets Interact mode map a canvas click onto the device screen at
    // any camera pose instead of treating the whole canvas as the
    // screen. `null` until the first message arrives.
    this.screenQuad = null;
    this.restartTimer = null;
    this.cameraFrame = 0;
    this.generation = 0;
    this.onMouseMove = (event) =>
      this.pointerMove('mouse', event.clientX, event.clientY, event);
    this.onMouseUp = (event) =>
      this.pointerUp('mouse', event.clientX, event.clientY, event);
    this.onTouchMove = (event) => this.touchMove(event);
    this.onTouchEnd = (event) => this.touchEnd(event);
    this.onTouchCancel = () => this.cancelPointer();
  }

  Sim3DPanel.prototype.attach = async function (host, stage, udid, options) {
    this.host = host;
    this.stage = stage;
    this.udid = udid;
    options = options || {};
    this.deviceSize = options.deviceSize || this.deviceSize;
    this.onFps = options.onFps || null;
    this.format = options.format === 'avcc' ? 'avcc' : 'mjpeg';
    this.background = options.background || this.background;
    this.renderLoading('Loading 3D model…');
    try {
      const response = await fetch(
          '/simulators/' + encodeURIComponent(udid) + '/3d-model.json',
          { cache: 'no-store' }
      );
      if (!response.ok) {
        throw new Error(response.status === 404
          ? 'No 3D model is installed for this simulator.'
          : 'Could not load model metadata.');
      }
      this.model = await response.json();
      (this.model.variantSets || []).forEach((set) => {
        this.variants[set.id] = set.default;
      });
      this.renderControls();
      this.mountStage();
      this.start();
    } catch (error) {
      this.renderError(error.message || String(error));
    }
  };

  Sim3DPanel.prototype.mountStage = function () {
    if (!this.stage) return;
    this.stage.innerHTML =
        '<canvas class="r3d-live-canvas" aria-label="Live 3D simulator"></canvas>' +
        '<div class="r3d-stage-tools" aria-label="3D interaction mode">' +
          '<button type="button" class="active" data-stage-mode="pose">Pose</button>' +
          '<button type="button" data-stage-mode="interact">Interact</button>' +
          '<button type="button" data-stage-reset title="Reset to front">Reset</button>' +
        '</div>' +
        '<button type="button" class="r3d-inspector-toggle" ' +
          'title="Show 3D inspector" aria-label="Show 3D inspector" ' +
          'onclick="window.__nativeToggle3DInspector && window.__nativeToggle3DInspector()">' +
          '<span aria-hidden="true">☷</span></button>' +
        '<div class="r3d-live-state" data-role="live-state">' +
          '<span class="r3d-spinner"></span><span>Loading model…</span>' +
        '</div>';
    this.canvas = this.stage.querySelector('canvas');
    this.canvas.addEventListener('mousedown', (event) => {
      if (event.button === 0 && this.mode === 'pose') {
        this.pointerDown('mouse', event.clientX, event.clientY, event);
      }
    });
    this.canvas.addEventListener('touchstart', (event) => {
      if (this.mode !== 'pose') return;
      if (event.changedTouches.length !== 1) return;
      const touch = event.changedTouches[0];
      this.pointerDown(touch.identifier, touch.clientX, touch.clientY, event);
    }, { passive: false });
    this.canvas.addEventListener('dblclick', () => this.resetCamera());
    this.canvas.addEventListener('wheel', (event) => this.zoomCamera(event), {
      passive: false,
    });
    this.stage.querySelectorAll('[data-stage-mode]').forEach((button) => {
      button.addEventListener('click', () => this.setMode(button.dataset.stageMode));
    });
    this.stage.querySelector('[data-stage-reset]').addEventListener(
        'click', () => this.resetCamera()
    );
    const transport = new window.Baguette._Transport({
      send: (payload) => this.send(payload),
    });
    this.interactiveScreen = new window.Baguette._Screen({
      rect: { width: this.deviceSize.width, height: this.deviceSize.height },
    }, transport);
    this.setMode(this.mode);
  };

  Sim3DPanel.prototype.start = function () {
    this.stop();
    if (!this.canvas || !this.model) return;
    this.screenQuad = null;
    const generation = ++this.generation;
    const size = this.outputSize();
    const params = new URLSearchParams({
      rotation: [this.rotation.x, this.rotation.y, this.rotation.z].join(','),
      width: String(size.width),
      height: String(size.height),
      fit: 'cover',
      background: this.background,
    });
    if (this.screenGlass) params.set('screenGlass', 'true');
    Object.keys(this.variants).forEach((set) => {
      params.append('variant', set + ':' + this.variants[set]);
    });
    const scheme = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const path = '/simulators/' + encodeURIComponent(this.udid) +
        '/stream.3d.' + this.format + '?' + params.toString();
    this.setState('Loading model…', true);
    this.session = new window.StreamSession({
      udid: this.udid,
      format: this.format,
      canvas: this.canvas,
      url: scheme + '//' + location.host + path,
      onFps: (fps) => {
        if (generation === this.generation && this.onFps && fps > 0) {
          this.onFps(fps);
        }
      },
      onLog: (message, error) => {
        if (error && generation === this.generation) {
          this.setState(message || '3D decode failed', false, true);
        }
      },
      onText: (envelope) => {
        if (generation !== this.generation) return false;
        if (envelope && envelope.type === 'screen_quad') {
          this.screenQuad = window.Baguette._ScreenQuad.fromCorners(envelope.corners);
          return true;
        }
        if (envelope && envelope.error) {
          this.setState(envelope.error, false, true);
          return true;
        }
        return false;
      },
      onOpen: () => {
        if (generation !== this.generation) return;
        this.setState('Waiting for frame…', true);
        this.sendCamera();
      },
      onPaint: () => {
        if (generation === this.generation) this.setState('', false);
      },
      onClose: () => {
        if (generation === this.generation && this.canvas &&
          !this.canvas.hasAttribute('data-painted')) {
          this.setState('3D stream disconnected', false, true);
        }
      },
      onError: () => {
        if (generation === this.generation) {
          this.setState('3D stream failed', false, true);
        }
      },
    });
    this.session.start();
  };

  Sim3DPanel.prototype.stop = function () {
    this.cancelPointer();
    this.generation += 1;
    if (this.restartTimer) clearTimeout(this.restartTimer);
    this.restartTimer = null;
    if (this.cameraFrame) cancelAnimationFrame(this.cameraFrame);
    this.cameraFrame = 0;
    if (this.session) this.session.stop();
    this.session = null;
  };

  Sim3DPanel.prototype.setFormat = function (format) {
    const next = format === 'avcc' ? 'avcc' : 'mjpeg';
    if (this.format === next) return;
    this.format = next;
    this.renderControls();
    this.start();
  };

  Sim3DPanel.prototype.setBackground = function (background) {
    if (!/^#[0-9a-f]{6}$/i.test(background || '') ||
        background.toLowerCase() === this.background.toLowerCase()) return;
    this.background = background;
    this.scheduleRestart(0);
  };

  Sim3DPanel.prototype.detach = function () {
    this.stop();
    if (this.interactiveScreen) this.interactiveScreen.detach();
    this.interactiveScreen = null;
    if (this.host) this.host.innerHTML = '';
    if (this.stage) this.stage.innerHTML = '';
    this.host = null;
    this.stage = null;
    this.canvas = null;
  };

  Sim3DPanel.prototype.send = function (payload) {
    return !!(this.session && this.session.send(payload));
  };

  Sim3DPanel.prototype.scheduleRestart = function (delay) {
    if (this.restartTimer) clearTimeout(this.restartTimer);
    this.restartTimer = setTimeout(() => {
      this.restartTimer = null;
      this.start();
    }, delay == null ? 80 : delay);
  };

  Sim3DPanel.prototype.renderLoading = function (message) {
    if (!this.host) return;
    this.host.innerHTML =
        '<div class="r3d-empty"><span class="r3d-spinner"></span><span></span></div>';
    this.host.querySelector('.r3d-empty span:last-child').textContent = message;
  };

  Sim3DPanel.prototype.renderError = function (message) {
    if (!this.host) return;
    this.host.innerHTML =
        '<div class="r3d-empty r3d-error"><strong>3D stream unavailable</strong>' +
        '<span data-role="message"></span>' +
        '<button type="button" data-role="retry">Try Again</button></div>';
    this.host.querySelector('[data-role="message"]').textContent = message;
    this.host.querySelector('[data-role="retry"]').addEventListener(
        'click', () => this.attach(this.host, this.stage, this.udid, {
          deviceSize: this.deviceSize, onFps: this.onFps, format: this.format,
        })
    );
  };

  Sim3DPanel.prototype.renderControls = function () {
    const variants = (this.model.variantSets || []).map((set) => {
      const choices = (set.choices || []).map((choice) => {
        const color = choice.previewColor
          ? '<i style="--swatch:' + escapeAttr(choice.previewColor) + '"></i>'
          : '';
        return '<button type="button" class="r3d-choice" data-set="' +
            escapeAttr(set.id) + '" data-choice="' + escapeAttr(choice.id) + '">' +
            color + '<span>' + escapeHTML(choice.displayName) + '</span></button>';
      }).join('');
      return '<section class="r3d-section"><label>' +
          escapeHTML(set.displayName) + '</label><div class="r3d-choices">' +
          choices + '</div></section>';
    }).join('');
    this.host.innerHTML =
        '<div class="r3d-live-summary"><strong>' +
          escapeHTML(this.model.displayName) + '</strong><span>Live ' +
          escapeHTML(this.format.toUpperCase()) + '</span></div>' +
        variants +
        '<section class="r3d-section"><label>Screen</label>' +
          '<div class="r3d-presets">' +
            '<button type="button" data-role="glass-toggle">Glass reflections</button>' +
          '</div>' +
        '</section>' +
        '<section class="r3d-section"><label>View</label>' +
          '<div class="r3d-presets">' +
            '<button type="button" data-preset="-8,18,0">Hero</button>' +
            '<button type="button" data-preset="0,0,0">Front</button>' +
            '<button type="button" data-preset="0,38,0">Side</button>' +
            '<button type="button" data-preset="-28,28,0">Top</button>' +
          '</div>' +
        '</section>' +
        '<details class="r3d-advanced"><summary>Advanced rotation</summary>' +
          '<div class="r3d-advanced-body">' +
            rangeRow('x', 'Tilt', -45, 45, this.rotation.x) +
            rangeRow('y', 'Turn', -80, 80, this.rotation.y) +
            rangeRow('z', 'Roll', -45, 45, this.rotation.z) +
          '</div></details>' +
        '<div class="r3d-footer">' +
          '<button type="button" class="r3d-download" data-role="download">Save Frame</button>' +
        '</div>';

    this.host.querySelectorAll('.r3d-choice').forEach((button) => {
      button.classList.toggle(
          'active', this.variants[button.dataset.set] === button.dataset.choice
      );
      button.addEventListener('click', () => {
        this.variants[button.dataset.set] = button.dataset.choice;
        this.host.querySelectorAll(
            '.r3d-choice[data-set="' + cssEscape(button.dataset.set) + '"]'
        ).forEach((candidate) => candidate.classList.toggle(
            'active', candidate.dataset.choice === button.dataset.choice
        ));
        this.scheduleRestart(0);
      });
    });
    this.host.querySelectorAll('[data-axis]').forEach((range) => {
      const output = this.host.querySelector(
          '[data-value="' + range.dataset.axis + '"]'
      );
      range.addEventListener('input', () => {
        this.rotation[range.dataset.axis] = Number(range.value);
        if (output) output.textContent = range.value + '°';
        this.sendCamera();
      });
    });
    this.host.querySelectorAll('[data-preset]').forEach((button) => {
      button.addEventListener('click', () => {
        const values = button.dataset.preset.split(',').map(Number);
        ['x', 'y', 'z'].forEach((axis, index) => {
          this.rotation[axis] = values[index];
          const range = this.host.querySelector('[data-axis="' + axis + '"]');
          const output = this.host.querySelector('[data-value="' + axis + '"]');
          if (range) range.value = String(values[index]);
          if (output) output.textContent = values[index] + '°';
        });
        this.sendCamera();
      });
    });
    this.host.querySelectorAll('[data-mode]').forEach((button) => {
      button.addEventListener('click', () => this.setMode(button.dataset.mode));
    });
    const glassToggle = this.host.querySelector('[data-role="glass-toggle"]');
    glassToggle.classList.toggle('active', this.screenGlass);
    glassToggle.addEventListener('click', () => {
      this.screenGlass = !this.screenGlass;
      glassToggle.classList.toggle('active', this.screenGlass);
      this.scheduleRestart(0);
    });
    this.host.querySelector('[data-role="download"]').addEventListener(
        'click', () => this.download()
    );
  };

  Sim3DPanel.prototype.setMode = function (mode) {
    this.mode = mode === 'interact' ? 'interact' : 'pose';
    this.cancelPointer();
    if (this.stage) this.stage.dataset.mode = this.mode;
    if (this.interactiveScreen && this.canvas) {
      if (this.mode === 'interact') {
        this.interactiveScreen.bindInteraction({
          element: this.canvas,
          overlayHost: this.stage,
          mapClientPoint: (clientX, clientY) => this.mapClientPoint(clientX, clientY),
        });
      } else {
        this.interactiveScreen.unbindInteraction();
      }
    }
    const selector = '[data-mode], [data-stage-mode]';
    document.querySelectorAll(selector).forEach((candidate) => {
      const value = candidate.dataset.mode || candidate.dataset.stageMode;
      candidate.classList.toggle('active', value === this.mode);
    });
  };

  Sim3DPanel.prototype.outputSize = function () {
    const rect = this.stage ? this.stage.getBoundingClientRect() : null;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    return {
      width: Math.max(480, Math.min(1600, Math.round((rect && rect.width || 960) * ratio))),
      height: Math.max(480, Math.min(1600, Math.round((rect && rect.height || 960) * ratio))),
    };
  };

  Sim3DPanel.prototype.setState = function (message, busy, error) {
    if (!this.stage) return;
    const state = this.stage.querySelector('[data-role="live-state"]');
    if (!state) return;
    state.hidden = !message;
    state.toggleAttribute('data-error', !!error);
    const label = state.querySelector('span:last-child');
    if (label) label.textContent = message || '';
    const spinner = state.querySelector('.r3d-spinner');
    if (spinner) spinner.hidden = !busy;
    if (!message && this.canvas) this.canvas.setAttribute('data-painted', '');
  };

  Sim3DPanel.prototype.pointerDown = function (id, clientX, clientY, event) {
    if (this.mode !== 'pose' || !this.canvas ||
        !this.canvas.hasAttribute('data-painted')) return;
    event.preventDefault();
    this.cancelPointer();
    this.pointer = {
      id: id, x: clientX, y: clientY, time: performance.now(),
      action: event.altKey ? 'zoom' : 'orbit',
      zoom: this.zoom,
      rotation: { x: this.rotation.x, y: this.rotation.y, z: this.rotation.z },
    };
    if (id === 'mouse') {
      document.addEventListener('mousemove', this.onMouseMove, { passive: false });
      document.addEventListener('mouseup', this.onMouseUp, { passive: false });
    } else {
      document.addEventListener('touchmove', this.onTouchMove, { passive: false });
      document.addEventListener('touchend', this.onTouchEnd, { passive: false });
      document.addEventListener('touchcancel', this.onTouchCancel);
    }
  };

  Sim3DPanel.prototype.pointerMove = function (id, clientX, clientY, event) {
    if (!this.pointer || id !== this.pointer.id || this.mode !== 'pose') return;
    event.preventDefault();
    if (this.pointer.action === 'zoom') {
      this.zoom = Math.max(0.5, Math.min(3,
          this.pointer.zoom * Math.exp((this.pointer.y - clientY) * 0.008)));
      this.sendCamera();
      return;
    }
    this.rotation.x = Math.max(-80, Math.min(80,
        this.pointer.rotation.x + (clientY - this.pointer.y) * 0.35));
    this.rotation.y = Math.max(-180, Math.min(180,
        this.pointer.rotation.y + (clientX - this.pointer.x) * 0.35));
    this.syncCameraControls();
    this.sendCamera();
  };

  Sim3DPanel.prototype.pointerUp = function (id, clientX, clientY, event) {
    if (!this.pointer || id !== this.pointer.id) return;
    event.preventDefault();
    this.cancelPointer();
  };

  Sim3DPanel.prototype.touchMove = function (event) {
    if (!this.pointer || this.pointer.id === 'mouse') return;
    const touch = Array.from(event.touches).find(
        (candidate) => candidate.identifier === this.pointer.id
    );
    if (touch) this.pointerMove(
        touch.identifier, touch.clientX, touch.clientY, event
    );
  };

  Sim3DPanel.prototype.touchEnd = function (event) {
    if (!this.pointer || this.pointer.id === 'mouse') return;
    const touch = Array.from(event.changedTouches).find(
        (candidate) => candidate.identifier === this.pointer.id
    );
    if (touch) this.pointerUp(
        touch.identifier, touch.clientX, touch.clientY, event
    );
  };

  Sim3DPanel.prototype.cancelPointer = function () {
    this.pointer = null;
    document.removeEventListener('mousemove', this.onMouseMove);
    document.removeEventListener('mouseup', this.onMouseUp);
    document.removeEventListener('touchmove', this.onTouchMove);
    document.removeEventListener('touchend', this.onTouchEnd);
    document.removeEventListener('touchcancel', this.onTouchCancel);
  };

  /**
   * canvas-pixel click → device-screen point, for Interact mode.
   * Maps through the last `screen_quad` the server pushed instead of
   * treating the whole canvas as a 1:1 screen crop — the rendered
   * screen is a rotated, perspective-foreshortened quad sitting inside
   * a larger canvas (device body/bezel/background/cover-glass).
   */
  Sim3DPanel.prototype.mapClientPoint = function (clientX, clientY) {
    const ScreenQuad = window.Baguette._ScreenQuad;
    const outside = { x: 0, y: 0, xNorm: 0, yNorm: 0, inside: false };
    if (!this.screenQuad || !this.canvas || !this.canvas.width || !this.canvas.height) {
      return outside;
    }
    const rect = ScreenQuad.contentRect(this.canvas);
    if (!rect.width || !rect.height) return outside;
    const contentU = (clientX - rect.left) / rect.width;
    const contentV = (clientY - rect.top) / rect.height;
    const solved = this.screenQuad.locate(contentU, contentV);
    const xNorm = Math.max(0, Math.min(1, solved.u));
    const yNorm = Math.max(0, Math.min(1, solved.v));
    const { width, height } = this.deviceSize;
    return { x: xNorm * width, y: yNorm * height, xNorm, yNorm, inside: solved.inside };
  };

  Sim3DPanel.prototype.sendCamera = function () {
    if (this.cameraFrame) return;
    this.cameraFrame = requestAnimationFrame(() => {
      this.cameraFrame = 0;
      this.send({
        type: 'set_3d_camera',
        rotation: this.rotation,
        zoom: this.zoom,
      });
    });
  };

  Sim3DPanel.prototype.syncCameraControls = function () {
    ['x', 'y', 'z'].forEach((axis) => {
      const value = Math.round(this.rotation[axis]);
      const range = this.host && this.host.querySelector('[data-axis="' + axis + '"]');
      const output = this.host && this.host.querySelector('[data-value="' + axis + '"]');
      if (range) range.value = String(value);
      if (output) output.textContent = value + '°';
    });
  };

  Sim3DPanel.prototype.resetCamera = function () {
    this.rotation = { x: 0, y: 0, z: 0 };
    this.zoom = 1;
    this.syncCameraControls();
    this.sendCamera();
  };

  Sim3DPanel.prototype.zoomCamera = function (event) {
    if (this.mode !== 'pose') return;
    event.preventDefault();
    this.zoom = Math.max(0.5, Math.min(3,
        this.zoom * Math.exp(-event.deltaY * 0.0015)));
    this.sendCamera();
  };

  Sim3DPanel.prototype.download = function () {
    if (!this.canvas || !this.canvas.hasAttribute('data-painted')) return;
    const link = document.createElement('a');
    link.href = this.canvas.toDataURL('image/png');
    link.download = (this.model.id || 'device') + '-live-3d.png';
    link.click();
  };

  function rangeRow(axis, label, min, max, value) {
    return '<div class="r3d-range-row"><span>' + label + '</span>' +
        '<input type="range" min="' + min + '" max="' + max + '" value="' +
        value + '" data-axis="' + axis + '">' +
        '<output data-value="' + axis + '">' + value + '°</output></div>';
  }
  function escapeHTML(value) {
    const div = document.createElement('div');
    div.textContent = String(value || '');
    return div.innerHTML;
  }
  function escapeAttr(value) {
    return escapeHTML(value).replace(/"/g, '&quot;');
  }
  function cssEscape(value) {
    return window.CSS && CSS.escape ? CSS.escape(value) : value.replace(/"/g, '\\"');
  }

  window.Sim3DPanel = Sim3DPanel;
})();
