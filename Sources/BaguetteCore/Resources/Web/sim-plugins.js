// sim-plugins.js — renders plugin contributions in focus mode.
//
// Plugins live in their OWN rail on the right edge, deliberately apart
// from the device toolbar. Baguette ships the toolbar; plugins are
// third-party code you installed. Keeping them physically separate is
// a trust signal, not decoration: you should always be able to tell
// "baguette did this" from "something I installed did this", and a
// plugin button must never be able to impersonate a core control.
//
// The host owns every pixel. A plugin ships a manifest describing what
// it wants (a titled panel, an icon from baguette's own set, a list
// fed by one of its commands); this file draws it with host markup.
// Nothing a plugin ships is ever loaded into this page — no plugin
// <script>, no plugin CSS, no plugin HTML. Every string from
// /plugins.json goes through escapeHTML or textContent.
//
// That constraint is what keeps the ~70 lines of Origin /
// Sec-Fetch-Site / DNS-rebind checks on the server meaningful: a
// same-origin plugin script would make all of it moot.
//
// Wire:
//   GET  /plugins.json                        → manifests
//   POST /plugins/<id>/commands/<cmd>?udid=   → {"ok",…,"rows":[…]}
(function (root) {
  'use strict';

  // Glyphs matching Domain/Plugin/PanelBody.swift's `PluginIcon`. A
  // manifest names one; it can never supply markup. Keep the two in
  // sync — an icon the host doesn't have is rejected at parse time, so
  // a missing case here means a plugin that validated can't render.
  const ICONS = {
    accessibility: '<circle cx="12" cy="4.5" r="1.8"/><path d="M4.5 8.5h15M12 8v6M12 14l-3.5 6M12 14l3.5 6"/>',
    reload:        '<path d="M20 12a8 8 0 1 1-2.4-5.7"/><path d="M20 4v5h-5"/>',
    link:          '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 1 0-5.7-5.7L11.5 7"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3A4 4 0 1 0 11 18.7l1.5-1.5"/>',
    list:          '<line x1="8" y1="7" x2="20" y2="7"/><line x1="8" y1="12" x2="20" y2="12"/><line x1="8" y1="17" x2="20" y2="17"/><circle cx="4.5" cy="7" r="1"/><circle cx="4.5" cy="12" r="1"/><circle cx="4.5" cy="17" r="1"/>',
    bell:          '<path d="M18 8a6 6 0 1 0-12 0c0 6-2 7-2 7h16s-2-1-2-7"/><path d="M13.7 20a2 2 0 0 1-3.4 0"/>',
    wrench:        '<path d="M14.7 6.3a4 4 0 0 0 5 5l-9 9a2.8 2.8 0 1 1-4-4z"/>',
    lock:          '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    globe:         '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 3 2.5 15 0 18M12 3c-2.5 3-2.5 15 0 18"/>',
    camera:        '<rect x="3" y="6.5" width="13" height="11" rx="2"/><path d="M16 10.5 21 8v8l-5-2.5z"/>',
    clock:         '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
    document:      '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    play:          '<path d="M8 5.5v13l11-6.5z"/>',
    // Also what the host resolves an unrecognised icon name to, so a
    // plugin naming a glyph added after this build still draws
    // something deliberate. Defined below, wired in after PUZZLE.
    puzzle:        '',
  };

  // The rail's own emblem — a puzzle piece. Names the rail as "the
  // plugins system" so the group reads as distinct from the toolbar.
  const PUZZLE =
    '<path d="M10 4.5a2 2 0 0 1 4 0c0 .3-.1.6-.2.9.2-.1.5-.1.7-.1h1.5a1 1 0 0 1 1 1v1.5c0 .2 0 .5-.1.7.3-.1.6-.2.9-.2a2 2 0 0 1 0 4c-.3 0-.6-.1-.9-.2.1.2.1.5.1.7v2.5a1 1 0 0 1-1 1h-2.5c-.2 0-.5 0-.7-.1.1.3.2.6.2.9a2 2 0 0 1-4 0c0-.3.1-.6.2-.9-.2.1-.5.1-.7.1H6a1 1 0 0 1-1-1v-2.5c0-.2 0-.5.1-.7-.3.1-.6.2-.9.2a2 2 0 0 1 0-4c.3 0 .6.1.9.2C5 8.6 5 8.3 5 8.1V6.4a1 1 0 0 1 1-1h1.5c.2 0 .5 0 .7.1-.1-.3-.2-.6-.2-.9z"/>';

  ICONS.puzzle = PUZZLE;

  const SEVERITY_COLOR = { error: '#b91c1c', warn: '#b45309', info: '#64748b' };

  function escapeHTML(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function svgWrap(inner, size) {
    const n = size || 17;
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" '
         + 'stroke-linecap="round" stroke-linejoin="round" width="' + n + '" height="' + n
         + '" aria-hidden="true">' + inner + '</svg>';
  }

  const iconSVG = (name) => svgWrap(ICONS[name] || ICONS.list, 17);

  class PluginPanels {
    /**
     * @param {object} opts
     * @param {string} opts.udid
     * @param {HTMLElement} [opts.mount]     where the rail + panel attach (default document.body)
     * @param {() => boolean} [opts.isBooted]
     * @param {(frame:object|null) => void} [opts.onHighlight]
     * @param {(point:{x:number,y:number}) => void} [opts.onTap]  device points
     * @param {(msg:string) => void} [opts.log]
     */
    constructor({ udid, mount, isBooted, onHighlight, onTap, log }) {
      this.udid = udid;
      this.mount = mount || document.body;
      this.isBooted = isBooted || (() => true);
      this.onHighlight = onHighlight || (() => {});
      this.onTap = onTap || (() => {});
      this.log = log || (() => {});
      this.plugins = [];
      this.openPanelID = null;
      this.rail = null;
      this.host = null;
      // The hover flyout: at most one open, owned by one group button.
      this.flyout = null;
      this.flyoutGroup = null;
      this.flyoutButton = null;
      this.flyoutCloseTimer = null;
      this.onFlyoutKeydown = (event) => { if (event.key === 'Escape') this.closeFlyout(); };
    }

    /**
     * Fetch the contributed panels and draw the rail.
     *
     * `keepRailOnFailure` separates two different failures. On a cold
     * start, an unreachable `/plugins.json` means this server has no
     * plugin support and the right answer is to mount nothing. On a
     * *reload* the rail was already on screen and the user is mid-task
     * — dropping it there would take away the "+" button, which is the
     * only in-browser way to add a plugin, with nothing but a page
     * refresh to bring it back.
     */
    async load({ keepRailOnFailure = false } = {}) {
      let payload;
      try {
        const res = await fetch('/plugins.json', { cache: 'no-cache' });
        if (!res.ok) throw new Error('plugins.json: ' + res.status);
        payload = await res.json();
      } catch (_) {
        if (!keepRailOnFailure) return; // no server-side plugins; nothing to mount
        payload = null;
      }
      this.plugins = (payload && payload.plugins) || [];
      this.render();
    }

    /**
     * The plugins that have something to show right now, each with the
     * panels it currently contributes.
     *
     * One plugin is one rail slot, however many tools it ships. A
     * plugin with eight panels used to spend eight slots and nothing
     * said the eight belonged together; grouping by the contributing
     * plugin makes the rail's length a count of what you installed,
     * not of what those things happen to contribute.
     */
    visibleGroups() {
      const out = [];
      for (const plugin of this.plugins) {
        const panels = (plugin.panels || []).filter(
          (panel) => !(panel.when === 'simulator.booted' && !this.isBooted())
        );
        if (!panels.length) continue;   // nothing to show ⇒ no slot
        out.push({ name: plugin.name, icon: plugin.icon, panels });
      }
      return out;
    }

    render() {
      PluginPanels.injectCSS();
      this.buildRail();
      for (const group of this.visibleGroups()) this.addGroup(group);
      // The "+ Add" entry point always shows, so a fresh user with no
      // plugins can still add their first bakery from the browser.
      this.addAddButton();
    }

    /// Tear the rail down and re-fetch — used after an install so the
    /// new plugin's button appears without a page reload.
    async reload() {
      this.closeFlyout();
      if (this.rail) this.rail.remove();
      if (this.host) this.host.remove();
      this.rail = null;
      this.host = null;
      this.openPanelID = null;
      await this.load({ keepRailOnFailure: true });
    }

    buildRail() {
      const rail = document.createElement('aside');
      rail.className = 'plugin-rail';
      rail.setAttribute('aria-label', 'Plugins');
      // Emblem cap — labels the whole strip as the plugins system.
      const cap = document.createElement('div');
      cap.className = 'plugin-rail-cap';
      cap.title = 'Plugins';
      cap.innerHTML = svgWrap(PUZZLE, 16);
      rail.appendChild(cap);
      const divider = document.createElement('div');
      divider.className = 'plugin-rail-divider';
      rail.appendChild(divider);

      const host = document.createElement('div');
      host.className = 'plugin-host';
      host.hidden = true;

      this.mount.appendChild(rail);
      this.mount.appendChild(host);
      this.rail = rail;
      this.host = host;
    }

    /**
     * One rail slot for one plugin.
     *
     * A plugin contributing a single panel keeps the old behaviour —
     * click opens it. Making you hover, wait, and then pick the only
     * item would be ceremony over a button. Only a plugin with more
     * than one tool earns the flyout.
     */
    addGroup(group) {
      const button = document.createElement('button');
      button.className = 'plugin-rail-btn';
      // The icon is a host-owned constant chosen by name — the only
      // markup here, and it never contains plugin input. The server
      // resolves which glyph represents the plugin (`Plugin.railIcon`),
      // so a plugin with no icon of its own already arrives wearing its
      // first panel's; the puzzle piece is the last resort.
      button.innerHTML = group.icon ? iconSVG(group.icon) : svgWrap(PUZZLE, 17);

      const single = group.panels.length === 1 ? group.panels[0] : null;
      // title / setAttribute, never innerHTML, for manifest text.
      if (single) {
        button.title = single.title + ' — ' + group.name;
        button.setAttribute('aria-label', single.title + ' (' + group.name + ')');
        button.addEventListener('click', () => this.toggle(group, single));
      } else {
        button.classList.add('plugin-rail-group');
        button.title = group.name + ' — ' + group.panels.length + ' tools';
        button.setAttribute('aria-label', group.name + ', ' + group.panels.length + ' tools');
        button.setAttribute('aria-haspopup', 'menu');
        button.setAttribute('aria-expanded', 'false');
        // Hover opens it; click and keyboard focus do too, so the rail
        // stays usable on a trackpad-less touch screen and by tab.
        button.addEventListener('mouseenter', () => this.openFlyout(group, button));
        button.addEventListener('mouseleave', () => this.scheduleFlyoutClose());
        button.addEventListener('focus', () => this.openFlyout(group, button));
        button.addEventListener('click', () => {
          if (this.flyoutGroup === group.name) this.closeFlyout();
          else this.openFlyout(group, button);
        });
      }

      group.button = button;
      this.rail.appendChild(button);
    }

    // --- the flyout ---------------------------------------------------
    //
    // Opens to the LEFT of the rail, aligned to the group button, and
    // lists each tool with its icon *and* its name. Icons alone stop
    // telling a plugin's tools apart once there are more than two or
    // three of them — the label is the point of the expansion.

    openFlyout(group, button) {
      this.cancelFlyoutClose();
      if (this.flyoutGroup === group.name) return;   // already showing
      this.closeFlyout();

      const flyout = document.createElement('div');
      flyout.className = 'plugin-flyout';
      flyout.setAttribute('role', 'menu');
      flyout.setAttribute('aria-label', group.name);

      const head = document.createElement('div');
      head.className = 'plugin-flyout-head';
      head.textContent = group.name;   // manifest text → textContent, never markup
      flyout.appendChild(head);

      for (const panel of group.panels) {
        const item = document.createElement('button');
        item.className = 'plugin-flyout-item';
        item.setAttribute('role', 'menuitem');
        if (this.openPanelID === panel.id) item.classList.add('active');

        const glyph = document.createElement('span');
        glyph.className = 'plugin-flyout-glyph';
        glyph.innerHTML = iconSVG(panel.icon);       // host constant
        const label = document.createElement('span');
        label.className = 'plugin-flyout-label';
        label.textContent = panel.title;             // untrusted → textContent
        item.appendChild(glyph);
        item.appendChild(label);

        item.addEventListener('click', () => {
          this.toggle(group, panel);
          this.closeFlyout();
        });
        flyout.appendChild(item);
      }

      flyout.addEventListener('mouseenter', () => this.cancelFlyoutClose());
      flyout.addEventListener('mouseleave', () => this.scheduleFlyoutClose());
      this.mount.appendChild(flyout);

      this.flyout = flyout;
      this.flyoutGroup = group.name;
      this.flyoutButton = button;
      button.setAttribute('aria-expanded', 'true');
      button.classList.add('expanded');
      document.addEventListener('keydown', this.onFlyoutKeydown);
      this.positionFlyout(flyout, button);
    }

    /// Centre the flyout on its button, then keep it on screen — a
    /// group near the top or bottom of a short window would otherwise
    /// hang off the edge.
    positionFlyout(flyout, button) {
      const rail = this.rail.getBoundingClientRect();
      const anchor = button.getBoundingClientRect();
      flyout.style.right = (window.innerWidth - rail.left + 8) + 'px';
      const height = flyout.offsetHeight;
      const centred = anchor.top + anchor.height / 2 - height / 2;
      const clamped = Math.max(12, Math.min(centred, window.innerHeight - height - 12));
      flyout.style.top = clamped + 'px';
    }

    /// A grace period so travelling from the button to the flyout
    /// across the 8px gap doesn't dismiss what you're reaching for.
    scheduleFlyoutClose() {
      this.cancelFlyoutClose();
      this.flyoutCloseTimer = setTimeout(() => this.closeFlyout(), 160);
    }

    cancelFlyoutClose() {
      if (this.flyoutCloseTimer) clearTimeout(this.flyoutCloseTimer);
      this.flyoutCloseTimer = null;
    }

    closeFlyout() {
      this.cancelFlyoutClose();
      if (this.flyoutButton) {
        this.flyoutButton.setAttribute('aria-expanded', 'false');
        this.flyoutButton.classList.remove('expanded');
      }
      if (this.flyout) this.flyout.remove();
      this.flyout = null;
      this.flyoutGroup = null;
      this.flyoutButton = null;
      document.removeEventListener('keydown', this.onFlyoutKeydown);
    }

    /// A "+" at the foot of the rail that opens the add-a-bakery modal.
    addAddButton() {
      const divider = document.createElement('div');
      divider.className = 'plugin-rail-divider';
      this.rail.appendChild(divider);

      const button = document.createElement('button');
      button.className = 'plugin-rail-btn plugin-rail-add';
      button.title = 'Add a plugin from a bakery';
      button.setAttribute('aria-label', 'Add a plugin');
      button.innerHTML = svgWrap('<path d="M12 5v14M5 12h14"/>', 18);
      button.addEventListener('click', () => this.openAddModal());
      this.rail.appendChild(button);
    }

    /// The rail highlights the *plugin* whose panel is open, not the
    /// panel — the panel no longer has a slot of its own to light up.
    toggle(group, panel) {
      if (this.openPanelID === panel.id) { this.close(); return; }
      for (const b of this.rail.querySelectorAll('.plugin-rail-btn')) {
        b.classList.toggle('active', b === group.button);
      }
      this.open(group.name, panel);
    }

    close() {
      this.openPanelID = null;
      this.host.innerHTML = '';
      this.host.hidden = true;
      this.onHighlight(null);
      for (const b of this.rail.querySelectorAll('.plugin-rail-btn')) b.classList.remove('active');
    }

    async open(pluginName, panel) {
      this.openPanelID = panel.id;
      this.host.hidden = false;
      this.renderShell(pluginName, panel, '<div class="plugin-status">Running…</div>');

      const body = panel.body || {};
      if (body.kind !== 'list') {
        this.renderShell(pluginName, panel, '<div class="plugin-status">Unsupported panel</div>');
        return;
      }

      const [id, cmd] = String(body.source).split(':');
      await this.invoke(pluginName, panel, id, cmd, null);
    }

    /**
     * Run one of a plugin's commands and render the answer into the
     * open panel. Both the panel's own `source` and a `rowAction:
     * "run"` click land here, so a row that changes something re-renders
     * from the command's fresh output rather than from what the browser
     * assumed would happen.
     *
     * @param {string} id       plugin id
     * @param {string} cmd      command id within that plugin
     * @param {object|null} args  arguments from the clicked row, if any
     */
    async invoke(pluginName, panel, id, cmd, args) {
      const body = panel.body || {};
      let payload;
      try {
        const url = '/plugins/' + encodeURIComponent(id) + '/commands/' + encodeURIComponent(cmd)
                  + '?udid=' + encodeURIComponent(this.udid);
        const init = { method: 'POST' };
        if (args) {
          init.headers = { 'content-type': 'application/json' };
          init.body = JSON.stringify({ args });
        }
        const res = await fetch(url, init);
        payload = await res.json();
      } catch (error) {
        this.renderShell(pluginName, panel, this.statusHTML('Could not reach the server: ' + error));
        return;
      }
      // Guard against a slow response landing after the user moved on.
      if (this.openPanelID !== panel.id) return;

      if (!payload.ok) {
        this.renderShell(pluginName, panel,
          this.statusHTML(payload.error || payload.message || 'Plugin failed'));
        return;
      }
      this.renderRows(pluginName, panel, payload.rows || [], body.rowAction);
    }

    /**
     * Copy a row's text, and say so when the browser won't.
     *
     * `navigator.clipboard` is undefined outside a secure context, and
     * while `127.0.0.1` counts as secure, `serve` accepts
     * `--allowed-hosts` — so the page can be reached by hostname over
     * plain http, where this is simply absent. Calling it there throws
     * inside the click handler and the row just looks selected with
     * nothing on the clipboard. `writeText` can also reject on a
     * permission failure, which was likewise unhandled.
     */
    copyToClipboard(text, row) {
      const clipboard = navigator.clipboard;
      if (!clipboard || typeof clipboard.writeText !== 'function') {
        this.noteRowError(row, 'clipboard needs https or localhost');
        return;
      }
      clipboard.writeText(text).catch((error) => {
        this.noteRowError(row, String((error && error.message) || error));
      });
    }

    /** A short-lived note on one row, for a failure that isn't the panel's. */
    noteRowError(row, message) {
      if (!row) return;
      const previous = row.querySelector('.plugin-inline-error');
      if (previous) previous.remove();
      const note = document.createElement('span');
      note.className = 'plugin-error plugin-inline-error';
      note.textContent = ' ' + message;
      row.appendChild(note);
      setTimeout(() => note.remove(), 4000);
    }

    statusHTML(message) {
      return '<div class="plugin-status plugin-error">' + escapeHTML(message) + '</div>';
    }

    renderShell(pluginName, panel, innerHTML) {
      this.host.innerHTML =
        '<div class="plugin-card">'
        + '<div class="plugin-head">'
        +   '<span class="plugin-title">' + escapeHTML(panel.title) + '</span>'
        +   '<span class="plugin-tag">' + escapeHTML(pluginName) + '</span>'
        +   '<button class="plugin-close" aria-label="Close">✕</button>'
        + '</div>'
        + '<div class="plugin-body">' + innerHTML + '</div>'
        + '</div>';
      const close = this.host.querySelector('.plugin-close');
      if (close) close.addEventListener('click', () => this.close());
    }

    renderRows(pluginName, panel, rows, rowAction) {
      if (!rows.length) {
        this.renderShell(pluginName, panel, '<div class="plugin-status">Nothing to report</div>');
        return;
      }
      const action = new window.Baguette._PluginRowAction(rowAction);
      const items = rows.map((row, index) => {
        const color = SEVERITY_COLOR[row.severity] || SEVERITY_COLOR.info;
        const clickable = action.actionable(row) ? ' plugin-row-clickable' : '';
        return '<li class="plugin-row' + clickable + '" data-index="' + index + '">'
             + '<span class="plugin-dot" style="background:' + color + '"></span>'
             + '<span class="plugin-row-text">'
             +   '<span class="plugin-row-title">' + escapeHTML(row.title) + '</span>'
             +   (row.subtitle
                   ? '<span class="plugin-row-sub">' + escapeHTML(row.subtitle) + '</span>'
                   : '')
             + '</span></li>';
      }).join('');
      this.renderShell(pluginName, panel, '<ul class="plugin-rows">' + items + '</ul>');

      const list = this.host.querySelector('.plugin-rows');
      if (!list || !rowAction) return;
      list.addEventListener('click', (event) => {
        const li = event.target.closest('.plugin-row');
        if (!li) return;
        const row = rows[Number(li.dataset.index)];
        if (!row) return;
        const intent = action.intent(row);
        if (!intent) return;   // an inert row stays inert, selection included
        for (const other of list.querySelectorAll('.plugin-row')) {
          other.classList.toggle('plugin-row-active', other === li);
        }
        if (intent.kind === 'highlight') this.onHighlight(intent.frame);
        if (intent.kind === 'tap') this.onTap(intent.point);
        if (intent.kind === 'copy') this.copyToClipboard(intent.text, li);
        if (intent.kind === 'run') {
          // The row names a command within its own plugin; the plugin
          // id comes from the panel's own source, so a row can never
          // reach into a different plugin.
          const pluginID = String((panel.body || {}).source || '').split(':')[0];
          this.invoke(pluginName, panel, pluginID, intent.command, intent.args);
        }
      });
    }

    // --- add-a-bakery modal ------------------------------------------
    //
    // Preview only. Cloning a repo and reading its menu is safe and
    // needs the browser; *installing* writes files that later run as
    // programs, and this page's only protection is a set of origin
    // heuristics. A terminal carries trust context a web page can't —
    // you typed the command — so the modal ends by handing you one.

    openAddModal() {
      const overlay = document.createElement('div');
      overlay.className = 'plugin-modal-overlay';
      overlay.innerHTML =
        '<div class="plugin-modal" role="dialog" aria-label="Add a plugin">'
        + '<div class="plugin-head">'
        +   '<span class="plugin-title">Add a plugin</span>'
        +   '<button class="plugin-close" aria-label="Close">✕</button>'
        + '</div>'
        + '<div class="plugin-modal-body">'
        +   '<label class="plugin-field-label">Bakery — a git repo with a baguette.json</label>'
        +   '<div class="plugin-field-row">'
        +     '<input class="plugin-input" type="text" placeholder="owner/repo or a git URL" spellcheck="false">'
        +     '<button class="plugin-btn plugin-preview-btn">Preview</button>'
        +   '</div>'
        +   '<div class="plugin-modal-result"></div>'
        + '</div>'
        + '</div>';
      this.mount.appendChild(overlay);

      const close = () => overlay.remove();
      overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
      overlay.querySelector('.plugin-close').addEventListener('click', close);

      const input = overlay.querySelector('.plugin-input');
      const result = overlay.querySelector('.plugin-modal-result');
      const preview = () => this.previewInto(input.value.trim(), result, close);
      overlay.querySelector('.plugin-preview-btn').addEventListener('click', preview);
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') preview(); });
      input.focus();
    }

    async previewInto(ref, result, closeModal) {
      if (!ref) return;
      result.innerHTML = '<div class="plugin-status">Fetching…</div>';
      let data;
      try {
        const res = await fetch('/bakeries/preview', {
          method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ ref }),
        });
        data = await res.json();
        if (!res.ok) throw new Error(data.error || 'preview failed');
      } catch (error) {
        result.innerHTML = '<div class="plugin-status plugin-error">' + escapeHTML(String(error.message || error)) + '</div>';
        return;
      }

      const shortCommit = String(data.commit || '').slice(0, 10);
      // Each offered plugin becomes the command that installs it, not a
      // button that does. Installing puts files on the machine that
      // later run as programs, and a terminal carries trust context a
      // web page can't — you typed it. See `docs/features/plugins.md`.
      const rows = (data.plugins || []).map((p) =>
        '<li class="plugin-offer">'
        + '<span class="plugin-row-title">' + escapeHTML(p.name) + '</span>'
        + '<code class="plugin-cmd">baguette plugin install '
        +   escapeHTML(ref) + '/' + escapeHTML(p.name) + '</code>'
        + '<button class="plugin-btn plugin-copy-cmd" data-plugin="' + escapeHTML(p.name) + '">Copy</button>'
        + '</li>').join('');

      result.innerHTML =
        '<div class="plugin-warn">'
        +   '⚠ Plugins from <b>' + escapeHTML(data.name || ref) + '</b> run as programs on your Mac '
        +   'with your permissions. Only add sources you trust. '
        +   '<span class="plugin-commit">@' + escapeHTML(shortCommit) + '</span>'
        + '</div>'
        + '<ul class="plugin-offers">' + rows + '</ul>'
        + '<div class="plugin-status">Run one of these in a terminal, then reopen the rail.</div>';

      for (const btn of result.querySelectorAll('.plugin-copy-cmd')) {
        btn.addEventListener('click', () => {
          const row = btn.closest('.plugin-offer');
          const cmd = row && row.querySelector('.plugin-cmd');
          this.copyToClipboard(cmd ? cmd.textContent : '', row);
        });
      }
    }

  }

  // Host-owned styling. Injected here rather than added to
  // sim-native.html so the module stays self-contained; no plugin
  // contributes CSS. The rail gets an accent seam so it reads as a
  // distinct system, not another toolbar.
  const CSS = `
  .plugin-rail { position: fixed; right: 16px; top: 50%; transform: translateY(-50%);
                 display: flex; flex-direction: column; align-items: center; gap: 6px;
                 padding: 8px 6px; z-index: 45;
                 background: var(--nv-bar-bg, rgba(255,255,255,0.92));
                 border: 1px solid var(--nv-bar-border, rgba(15,23,42,0.10));
                 border-left: 2px solid var(--accent, #2563eb);
                 border-radius: 14px;
                 box-shadow: var(--nv-bar-shadow, 0 8px 30px rgba(15,23,42,0.12));
                 backdrop-filter: blur(18px) saturate(1.5);
                 -webkit-backdrop-filter: blur(18px) saturate(1.5);
                 color: var(--nv-text, #1d1d1f); }
  .plugin-rail-cap { display: inline-flex; align-items: center; justify-content: center;
                     width: 30px; height: 24px; color: var(--accent, #2563eb); opacity: 0.85; }
  .plugin-rail-divider { width: 20px; height: 1px; margin: 1px 0 3px;
                         background: var(--nv-divider, rgba(15,23,42,0.14)); }
  .plugin-rail-btn { position: relative; width: 34px; height: 34px; padding: 0; border: 0;
                     cursor: pointer;
                     display: inline-flex; align-items: center; justify-content: center;
                     background: transparent; border-radius: 9px; color: var(--nv-text, #1d1d1f);
                     transition: background 0.12s ease, transform 0.12s ease; }
  .plugin-rail-btn:hover  { background: var(--nv-btn-hover, rgba(15,23,42,0.06)); }
  .plugin-rail-btn:active { transform: scale(0.94); }
  .plugin-rail-btn.active { background: color-mix(in srgb, var(--accent, #2563eb) 16%, transparent);
                            color: var(--accent, #2563eb); }
  .plugin-rail-btn.expanded { background: var(--nv-btn-hover, rgba(15,23,42,0.06)); }
  /* A caret on plugins that hold more than one tool: says "there is
     more here, and it opens leftward" before you hover to find out. */
  .plugin-rail-group::after { content: ''; position: absolute; left: 3px; top: 50%;
                              margin-top: -3px; border: 3px solid transparent;
                              border-right-color: currentColor; opacity: 0.4;
                              transition: opacity 0.12s ease; }
  .plugin-rail-group:hover::after, .plugin-rail-group.expanded::after { opacity: 0.75; }

  .plugin-flyout { position: fixed; z-index: 50; min-width: 172px; max-width: 260px;
                   padding: 5px; display: flex; flex-direction: column; gap: 1px;
                   background: var(--nv-bar-bg, rgba(255,255,255,0.96));
                   border: 1px solid var(--nv-bar-border, rgba(15,23,42,0.10));
                   border-right: 2px solid var(--accent, #2563eb);
                   border-radius: 12px;
                   box-shadow: 0 10px 34px rgba(15,23,42,0.20);
                   backdrop-filter: blur(18px) saturate(1.5);
                   -webkit-backdrop-filter: blur(18px) saturate(1.5);
                   animation: plugin-flyout-in 0.12s ease-out; }
  @keyframes plugin-flyout-in { from { opacity: 0; transform: translateX(6px); }
                                to   { opacity: 1; transform: translateX(0); } }
  @media (prefers-reduced-motion: reduce) { .plugin-flyout { animation: none; } }
  .plugin-flyout-head { padding: 5px 8px 6px; font: 600 10px/1 -apple-system, sans-serif;
                        letter-spacing: 0.06em; text-transform: uppercase;
                        color: var(--accent, #2563eb);
                        border-bottom: 1px solid var(--nv-divider, rgba(15,23,42,0.10));
                        margin-bottom: 3px; overflow: hidden; text-overflow: ellipsis;
                        white-space: nowrap; }
  .plugin-flyout-item { display: flex; align-items: center; gap: 9px; width: 100%;
                        padding: 7px 9px; border: 0; border-radius: 8px; cursor: pointer;
                        background: transparent; text-align: left;
                        font: 500 12px/1.2 -apple-system, sans-serif;
                        color: var(--nv-text, #1d1d1f);
                        transition: background 0.1s ease; }
  .plugin-flyout-item:hover { background: var(--nv-btn-hover, rgba(15,23,42,0.06)); }
  .plugin-flyout-item.active { background: color-mix(in srgb, var(--accent, #2563eb) 14%, transparent);
                               color: var(--accent, #2563eb); }
  .plugin-flyout-glyph { display: inline-flex; flex: 0 0 auto;
                         color: var(--nv-text-muted, rgba(29,29,31,0.65)); }
  .plugin-flyout-item:hover .plugin-flyout-glyph,
  .plugin-flyout-item.active .plugin-flyout-glyph { color: inherit; }
  .plugin-flyout-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .plugin-host { position: fixed; right: 72px; top: 50%; transform: translateY(-50%);
                 width: 340px; max-height: 66vh; z-index: 44; }
  .plugin-card { background: var(--nv-bar-bg, rgba(255,255,255,0.94));
                 border: 1px solid var(--nv-bar-border, rgba(15,23,42,0.10));
                 border-top: 2px solid var(--accent, #2563eb);
                 border-radius: 14px; box-shadow: 0 10px 34px rgba(15,23,42,0.20);
                 backdrop-filter: blur(18px) saturate(1.5);
                 -webkit-backdrop-filter: blur(18px) saturate(1.5);
                 overflow: hidden; display: flex; flex-direction: column; max-height: 66vh; }
  .plugin-head { display: flex; align-items: center; gap: 8px; padding: 10px 12px;
                 border-bottom: 1px solid var(--nv-divider, rgba(15,23,42,0.10)); }
  .plugin-title { font: 600 12px/1 -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                  color: var(--nv-text, #1d1d1f); letter-spacing: 0.02em; }
  .plugin-tag { font: 600 10px/1 -apple-system, sans-serif; letter-spacing: 0.04em;
                text-transform: lowercase; color: var(--accent, #2563eb);
                background: color-mix(in srgb, var(--accent, #2563eb) 12%, transparent);
                padding: 3px 6px; border-radius: 999px; }
  .plugin-close { margin-left: auto; border: 0; background: transparent; cursor: pointer;
                  font-size: 12px; color: var(--nv-text-muted, rgba(29,29,31,0.65)); padding: 2px 4px; }
  .plugin-body { overflow-y: auto; }
  .plugin-status { padding: 14px 12px; font: 400 12px/1.4 -apple-system, sans-serif;
                   color: var(--nv-text-muted, rgba(29,29,31,0.65)); }
  .plugin-error { color: #b91c1c; }
  .plugin-rows { list-style: none; margin: 0; padding: 4px 0; }
  .plugin-row { display: flex; gap: 8px; align-items: flex-start; padding: 8px 12px;
                font: 400 12px/1.35 -apple-system, sans-serif; color: var(--nv-text, #1d1d1f); }
  .plugin-row-clickable { cursor: pointer; }
  .plugin-row-clickable:hover { background: var(--nv-btn-hover, rgba(15,23,42,0.06)); }
  .plugin-row-active { background: var(--nv-btn-active, rgba(15,23,42,0.12)); }
  .plugin-dot { width: 7px; height: 7px; border-radius: 50%; margin-top: 4px; flex: 0 0 auto; }
  .plugin-row-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .plugin-row-sub { color: var(--nv-text-muted, rgba(29,29,31,0.65)); font-size: 11px;
                    overflow-wrap: anywhere; }
  .plugin-highlight { position: absolute; border: 2px solid var(--accent, #2563eb);
                      background: rgba(37,99,235,0.16); border-radius: 3px;
                      pointer-events: none; z-index: 30; }

  .plugin-rail-add { color: var(--accent, #2563eb); }

  .plugin-modal-overlay { position: fixed; inset: 0; z-index: 60;
                          display: flex; align-items: center; justify-content: center;
                          background: rgba(15,23,42,0.32); backdrop-filter: blur(2px); }
  .plugin-modal { width: min(440px, 92vw);
                  background: var(--nv-bar-bg, rgba(255,255,255,0.98));
                  border: 1px solid var(--nv-bar-border, rgba(15,23,42,0.12));
                  border-top: 2px solid var(--accent, #2563eb);
                  border-radius: 14px; box-shadow: 0 20px 60px rgba(15,23,42,0.30);
                  overflow: hidden; }
  .plugin-modal-body { padding: 14px; display: flex; flex-direction: column; gap: 10px; }
  .plugin-field-label { font: 500 11px/1.3 -apple-system, sans-serif;
                        color: var(--nv-text-muted, rgba(29,29,31,0.65)); }
  .plugin-field-row { display: flex; gap: 8px; }
  .plugin-input { flex: 1; padding: 8px 10px; border-radius: 8px;
                  border: 1px solid var(--nv-bar-border, rgba(15,23,42,0.16));
                  background: var(--panel, #fff); color: var(--nv-text, #1d1d1f);
                  font: 400 13px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace; }
  .plugin-btn { padding: 8px 12px; border: 0; border-radius: 8px; cursor: pointer;
                font: 600 12px/1 -apple-system, sans-serif; color: #fff;
                background: var(--accent, #2563eb); }
  .plugin-btn:disabled { opacity: 0.6; cursor: default; }
  .plugin-warn { font: 400 12px/1.45 -apple-system, sans-serif; color: var(--nv-text, #1d1d1f);
                 background: color-mix(in srgb, #b45309 10%, transparent);
                 border: 1px solid color-mix(in srgb, #b45309 26%, transparent);
                 border-radius: 8px; padding: 10px; }
  .plugin-commit { font: 500 11px/1 ui-monospace, Menlo, monospace;
                   color: var(--nv-text-muted, rgba(29,29,31,0.65)); }
  .plugin-offers { list-style: none; margin: 4px 0 0; padding: 0;
                   display: flex; flex-direction: column; gap: 6px; }
  .plugin-offer { display: flex; align-items: center; justify-content: space-between;
                  gap: 10px; padding: 8px 10px; border-radius: 8px;
                  background: var(--nv-btn-hover, rgba(15,23,42,0.05));
                  font: 500 13px/1.2 -apple-system, sans-serif; color: var(--nv-text, #1d1d1f); }
  .plugin-inline-error { font-size: 11px; margin-left: 8px; }
  /* The install command. Selectable and monospaced — it exists to be
     read and run, so it must look like something you'd paste. */
  .plugin-cmd { flex: 1 1 auto; min-width: 0; overflow-x: auto; white-space: nowrap;
                user-select: all; -webkit-user-select: all;
                font: 500 11px/1.6 ui-monospace, Menlo, monospace;
                color: var(--nv-text-muted, rgba(29,29,31,0.75)); }

  @media (max-width: 560px) {
    .plugin-host { right: 12px; left: 12px; width: auto; }
  }
  `;

  function injectCSS() {
    if (document.getElementById('plugin-panel-css')) return;
    const style = document.createElement('style');
    style.id = 'plugin-panel-css';
    style.textContent = CSS;
    document.head.appendChild(style);
  }

  root.PluginPanels = PluginPanels;
  root.PluginPanels.injectCSS = injectCSS;
})(window);
