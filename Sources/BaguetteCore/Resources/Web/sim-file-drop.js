// sim-file-drop.js — drag-and-drop files onto the device.
//
// Hangs `window.SimFileDrop` on the global so sim-native.js can make the
// focus view accept dropped files: an .ipa/.app installs an app, an
// image/video lands in Photos.
//
// This is a dumb sender. For each dropped file it POSTs the raw bytes to
// `POST /simulators/<udid>/files?name=<filename>` and shows the result.
// All domain logic — which file is an app vs media, which simctl verb,
// the "no home on a simulator" rejection — lives on the Swift side
// (`Server.addFile`, `AppBundle`, `MediaItem`). See
// docs/features/file-upload.md.
//
// The drop highlight traces the device *screen* — the bezel exposes a
// `screenArea` rect with the exact clip-radius (Bezel.mount), so the
// overlay mirrors its geometry and reads as a clean rounded rectangle on
// the phone rather than a boxy bounding box with the side buttons poking
// through.

(function () {
  'use strict';

  function ensureStyles() {
    if (document.getElementById('simFileDropStyles')) return;
    const s = document.createElement('style');
    s.id = 'simFileDropStyles';
    s.textContent = `
      .sfd-overlay {
        position: absolute; z-index: 5; box-sizing: border-box;
        display: flex; align-items: center; justify-content: center;
        background: rgba(16,18,24,0.42); backdrop-filter: blur(1.5px);
        border: 2px dashed rgba(255,255,255,0.85);
        font: 600 13px/1.35 -apple-system, system-ui, sans-serif; color: #fff;
        text-align: center; pointer-events: none; padding: 14px;
        text-shadow: 0 1px 3px rgba(0,0,0,0.55);
      }
      .sfd-overlay .sfd-plus {
        display: inline-flex; align-items: center; justify-content: center;
        width: 30px; height: 30px; margin-bottom: 9px; border-radius: 50%;
        background: rgba(255,255,255,0.16); font-size: 20px; line-height: 1;
      }
      .sfd-overlay .sfd-col { display: flex; flex-direction: column; align-items: center; }
      .sfd-toasts {
        position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%);
        z-index: 9999; display: flex; flex-direction: column; gap: 8px;
        align-items: center; pointer-events: none;
      }
      .sfd-toast {
        font: 500 13px/1.35 -apple-system, system-ui, sans-serif; color: #fff;
        background: rgba(28,30,38,0.94); border: 1px solid rgba(255,255,255,0.12);
        border-radius: 11px; padding: 8px 13px; max-width: 360px;
        box-shadow: 0 6px 22px rgba(0,0,0,0.35); transition: opacity .3s;
      }
      .sfd-toast.sfd-ok   { border-color: rgba(80,200,120,0.55); }
      .sfd-toast.sfd-err  { border-color: rgba(235,110,110,0.6); }
      .sfd-toast.sfd-busy { border-color: rgba(120,160,235,0.55); }
    `;
    document.head.appendChild(s);
  }

  function hasFiles(e) {
    return !!e.dataTransfer &&
      Array.prototype.indexOf.call(e.dataTransfer.types, 'Files') >= 0;
  }

  function attach(host, opts) {
    if (!host || !opts || !opts.udid) return;
    const udid = opts.udid;
    ensureStyles();

    const overlay = document.createElement('div');
    overlay.className = 'sfd-overlay';
    overlay.innerHTML =
      '<span class="sfd-col"><span class="sfd-plus">+</span>Drop to add to device</span>';

    // Toasts are fixed to the viewport, so a bezel remount (which wipes
    // the device frame's children) can't strip them.
    let toasts = document.getElementById('sfdToasts');
    if (!toasts) {
      toasts = document.createElement('div');
      toasts.id = 'sfdToasts';
      toasts.className = 'sfd-toasts';
      document.body.appendChild(toasts);
    }

    function toast(msg, kind) {
      const t = document.createElement('div');
      t.className = 'sfd-toast sfd-' + (kind || 'busy');
      t.textContent = msg;
      toasts.appendChild(t);
      if (kind !== 'busy') {
        setTimeout(() => { t.style.opacity = '0'; }, 3200);
        setTimeout(() => { t.remove(); }, 3600);
      }
      return t;
    }

    // Mirror the live screen rect (computed fresh each time so it tracks
    // remounts, orientation, and viewport scaling) and slot the overlay
    // in as a sibling of the screen, above it.
    function showOverlay() {
      const canvas = host.querySelector('#simStreamCanvas');
      const screenArea = canvas && canvas.parentElement;
      const wrapper = screenArea && screenArea.parentElement;
      if (!wrapper || !screenArea) return;
      overlay.style.left = screenArea.style.left;
      overlay.style.top = screenArea.style.top;
      overlay.style.width = screenArea.style.width;
      overlay.style.height = screenArea.style.height;
      overlay.style.borderRadius = screenArea.style.borderRadius;
      wrapper.appendChild(overlay);
    }
    function hideOverlay() {
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    }

    // dragenter/over must preventDefault for `drop` to fire. A depth
    // counter avoids flicker as the cursor crosses child elements.
    let depth = 0;
    host.addEventListener('dragenter', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth++;
      showOverlay();
    });
    host.addEventListener('dragover', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    });
    host.addEventListener('dragleave', () => {
      depth = Math.max(0, depth - 1);
      if (depth === 0) hideOverlay();
    });
    host.addEventListener('drop', (e) => {
      e.preventDefault();
      depth = 0;
      hideOverlay();
      const files = e.dataTransfer && e.dataTransfer.files;
      if (!files || !files.length) return;
      for (let i = 0; i < files.length; i++) upload(files[i]);
    });

    async function upload(file) {
      const busy = toast('Adding ' + file.name + '…', 'busy');
      try {
        const res = await fetch(
          '/simulators/' + encodeURIComponent(udid) +
            '/files?name=' + encodeURIComponent(file.name),
          { method: 'POST', body: file }
        );
        busy.remove();
        let body = {};
        try { body = await res.json(); } catch (_) { /* non-JSON */ }
        if (res.ok && body.ok) {
          const what = body.kind === 'app' ? 'Installed' : 'Added';
          toast(what + ' ' + file.name, 'ok');
        } else {
          toast(file.name + ': ' + (body.error || ('HTTP ' + res.status)), 'err');
        }
      } catch (err) {
        busy.remove();
        toast(file.name + ': ' + (err && err.message ? err.message : 'upload failed'), 'err');
      }
    }

    // Expose for visual verification / tests.
    return { showOverlay, hideOverlay };
  }

  window.SimFileDrop = { attach };
})();
