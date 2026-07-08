// sim-location.js — simulated-location map picker for the focus page.
//
// Hangs `window.LocationPanel` on the global so sim-native.js can surface
// a floating glass card with a Leaflet map. Click the map to drop a pin
// and "Set location"; switch to Route mode to drop two or more waypoints
// and "Start route" a moving location.
//
// The panel is a dumb sender: "Set location" POSTs
// `{latitude,longitude}`, "Start route" POSTs `{waypoints:[…],speed}`,
// and "Clear" sends DELETE — all to `/simulators/<udid>/location`. The
// Swift side owns all domain logic (`simctl location` argv, range
// validation). Map tiles come from OpenStreetMap at runtime; only the
// Leaflet library itself is vendored. See `docs/features/location.md`.
//
// Two map conveniences are browser-side only:
//   • Search — geocodes a place name via OSM Nominatim and recentres the
//     map (no API key; a runtime fetch, like the tiles).
//   • Locate me — centres on the *host Mac's* real position via the
//     browser geolocation API. (simctl has no read-back, so the device's
//     own simulated position can't be queried — this is the Mac's GPS.)

(function () {
  'use strict';

  // Apple Park — a friendly default centre when the device has no pin yet.
  const DEFAULT_CENTER = [37.3349, -122.0090];
  const DEFAULT_ZOOM = 13;
  const TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  const TILE_ATTR = '&copy; OpenStreetMap contributors';
  // OSM geocoder — free, no API key, CORS-enabled. Low-volume dev use
  // only; respect Nominatim's usage policy (1 req/sec).
  const GEOCODE_URL = 'https://nominatim.openstreetmap.org/search';
  const FOUND_ZOOM = 14;

  function round6(n) { return Math.round(n * 1e6) / 1e6; }

  class LocationPanel {
    constructor() {
      this.host = null;
      this.udid = null;
      this.map = null;
      this.mode = 'point';        // 'point' | 'route'
      this.marker = null;         // point-mode draggable pin
      this.routePins = [];        // route-mode waypoint markers
      this.routeLine = null;      // route-mode polyline
    }

    attach(host, udid) {
      if (!host || !udid) return;
      this.host = host;
      this.udid = udid;
      this._build();
      // Leaflet needs a sized, on-screen container; the card fades in via
      // opacity so it's laid out, but invalidate once on the next frame
      // to be safe against any mount-time zero-size race.
      requestAnimationFrame(() => { if (this.map) this.map.invalidateSize(); });
    }

    // Re-measure when the card is reopened (sim-native reuses the mounted
    // panel), so the tiles fill the container after any layout change.
    refresh() {
      if (this.map) requestAnimationFrame(() => this.map.invalidateSize());
    }

    detach() {
      if (this.map) { this.map.remove(); this.map = null; }
      this.marker = null;
      this.routePins = [];
      this.routeLine = null;
      if (this.host) { this.host.innerHTML = ''; this.host = null; }
    }

    // ---- view construction --------------------------------------

    _build() {
      this.host.innerHTML =
        '<div class="loc-search">' +
          '<input class="loc-search-input" id="nativeLocationSearch" type="text" ' +
                 'placeholder="Search a place…" aria-label="Search a location">' +
          '<button class="loc-icon-btn" id="nativeLocationSearchBtn" title="Search" aria-label="Search">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
                 'stroke-linecap="round" width="15" height="15" aria-hidden="true">' +
              '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l4.5 4.5"/></svg>' +
          '</button>' +
          '<button class="loc-icon-btn" id="nativeLocationLocate" title="My current location" ' +
                  'aria-label="My current location">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
                 'stroke-linecap="round" width="15" height="15" aria-hidden="true">' +
              '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg>' +
          '</button>' +
        '</div>' +
        '<div class="loc-modes">' +
          '<button class="loc-seg-btn active" data-mode="point">Point</button>' +
          '<button class="loc-seg-btn" data-mode="route">Route</button>' +
        '</div>' +
        '<div class="loc-map" id="nativeLocationMap"></div>' +
        '<div class="loc-readout" id="nativeLocationReadout">Click the map to choose a position.</div>' +
        '<div class="loc-row loc-route-only" hidden>' +
          '<label class="loc-row-label">Speed</label>' +
          '<input class="loc-field" id="nativeLocationSpeed" type="number" min="1" ' +
                 'placeholder="20" aria-label="Route speed in metres per second">' +
          '<span class="loc-unit">m/s</span>' +
        '</div>' +
        '<div class="loc-actions">' +
          '<button class="loc-apply" id="nativeLocationApply" disabled>Set location</button>' +
          '<button class="loc-clear" id="nativeLocationClear">Clear</button>' +
        '</div>';

      this.host.querySelectorAll('.loc-seg-btn').forEach((btn) => {
        btn.addEventListener('click', () => this._setMode(btn.getAttribute('data-mode')));
      });
      this.host.querySelector('#nativeLocationApply')
        .addEventListener('click', () => this._apply());
      this.host.querySelector('#nativeLocationClear')
        .addEventListener('click', () => this._clear());

      this.host.querySelector('#nativeLocationSearchBtn')
        .addEventListener('click', () => this._search());
      this.host.querySelector('#nativeLocationSearch')
        .addEventListener('keydown', (e) => {
          if (e.key === 'Enter') { e.preventDefault(); this._search(); }
        });
      this.host.querySelector('#nativeLocationLocate')
        .addEventListener('click', () => this._locateMe());

      this._initMap();
    }

    _initMap() {
      if (typeof L === 'undefined') {
        this._readout('Map library failed to load — check your connection.');
        return;
      }
      const el = this.host.querySelector('#nativeLocationMap');
      this.map = L.map(el, { zoomControl: true, attributionControl: true })
        .setView(DEFAULT_CENTER, DEFAULT_ZOOM);
      L.tileLayer(TILE_URL, { maxZoom: 19, attribution: TILE_ATTR }).addTo(this.map);
      this.map.on('click', (e) => this._onMapClick(e.latlng));
    }

    _pinIcon() {
      return L.divIcon({
        className: 'loc-pin',
        html: '<span class="loc-pin-dot"></span>',
        iconSize: [16, 16],
        iconAnchor: [8, 8],
      });
    }

    // ---- mode + interaction -------------------------------------

    _setMode(mode) {
      if (mode === this.mode) return;
      this.mode = mode;
      this.host.querySelectorAll('.loc-seg-btn').forEach((b) =>
        b.classList.toggle('active', b.getAttribute('data-mode') === mode));
      this.host.querySelector('.loc-route-only').hidden = (mode !== 'route');
      this.host.querySelector('#nativeLocationApply').textContent =
        (mode === 'route') ? 'Start route' : 'Set location';
      this._reset();
    }

    _reset() {
      if (this.marker) { this.map.removeLayer(this.marker); this.marker = null; }
      this.routePins.forEach((m) => this.map.removeLayer(m));
      this.routePins = [];
      if (this.routeLine) { this.map.removeLayer(this.routeLine); this.routeLine = null; }
      this._readout(this.mode === 'route'
        ? 'Click the map to add waypoints (two or more).'
        : 'Click the map to choose a position.');
      this._syncApply();
    }

    _onMapClick(latlng) {
      if (this.mode === 'point') {
        this._setPoint(latlng);
      } else {
        const m = L.marker(latlng, { icon: this._pinIcon() }).addTo(this.map);
        this.routePins.push(m);
        this._drawRoute();
        this._syncApply();
      }
    }

    // Drop or move the single point-mode pin. Shared by map clicks,
    // search results, and "locate me".
    _setPoint(latlng) {
      if (!this.marker) {
        this.marker = L.marker(latlng, { icon: this._pinIcon(), draggable: true }).addTo(this.map);
        this.marker.on('move', (e) => this._readPoint(e.latlng));
        this.marker.on('moveend', () => this._syncApply());
      } else {
        this.marker.setLatLng(latlng);
      }
      this._readPoint(latlng);
      this._syncApply();
    }

    // Recentre on a coordinate. In Point mode it also drops the pin so
    // the result is immediately ready to send; in Route mode it just
    // pans there so the user can click to add waypoints.
    _goTo(lat, lon, label) {
      if (!this.map || isNaN(lat) || isNaN(lon)) return;
      this.map.setView([lat, lon], FOUND_ZOOM);
      if (this.mode === 'point') {
        this._setPoint(L.latLng(lat, lon));
      } else if (label) {
        this._readout(label + ' — click to add as a waypoint.');
      }
    }

    // ---- search + locate ----------------------------------------

    _search() {
      const input = this.host.querySelector('#nativeLocationSearch');
      const q = input && input.value.trim();
      if (!q) return;
      this._readout('Searching…');
      fetch(`${GEOCODE_URL}?format=json&limit=1&q=${encodeURIComponent(q)}`, {
        headers: { Accept: 'application/json' },
      })
        .then((r) => (r.ok ? r.json() : []))
        .then((results) => {
          if (!results || !results.length) { this._readout(`No match for “${q}”.`); return; }
          const r = results[0];
          this._goTo(parseFloat(r.lat), parseFloat(r.lon), r.display_name);
        })
        .catch(() => this._readout('Search failed — network error.'));
    }

    _locateMe() {
      if (!navigator.geolocation) { this._readout('This browser has no geolocation.'); return; }
      this._readout('Locating…');
      navigator.geolocation.getCurrentPosition(
        (pos) => this._goTo(pos.coords.latitude, pos.coords.longitude, 'Your location'),
        () => this._readout('Location permission denied or unavailable.'),
        { enableHighAccuracy: true, timeout: 8000 }
      );
    }

    _drawRoute() {
      const pts = this.routePins.map((m) => m.getLatLng());
      if (this.routeLine) { this.map.removeLayer(this.routeLine); this.routeLine = null; }
      if (pts.length >= 2) {
        this.routeLine = L.polyline(pts, { color: '#3b82f6', weight: 3 }).addTo(this.map);
      }
      this._readout(`${pts.length} waypoint${pts.length === 1 ? '' : 's'} — `
        + (pts.length >= 2 ? 'ready to start.' : 'add at least one more.'));
    }

    _readPoint(latlng) {
      this._readout(`${round6(latlng.lat)}, ${round6(latlng.lng)}`);
    }

    _readout(text) {
      const el = this.host && this.host.querySelector('#nativeLocationReadout');
      if (el) el.textContent = text;
    }

    _syncApply() {
      const apply = this.host.querySelector('#nativeLocationApply');
      if (!apply) return;
      apply.disabled = (this.mode === 'point')
        ? !this.marker
        : this.routePins.length < 2;
    }

    // ---- send ----------------------------------------------------

    _apply() {
      if (this.mode === 'point') {
        if (!this.marker) return;
        const { lat, lng } = this.marker.getLatLng();
        this._post({ latitude: round6(lat), longitude: round6(lng) });
      } else {
        if (this.routePins.length < 2) return;
        const waypoints = this.routePins.map((m) => {
          const p = m.getLatLng();
          return { latitude: round6(p.lat), longitude: round6(p.lng) };
        });
        const body = { waypoints };
        const speed = parseFloat(this.host.querySelector('#nativeLocationSpeed').value);
        if (!isNaN(speed) && speed > 0) body.speed = speed;
        this._post(body);
      }
    }

    _post(body) {
      fetch(`/simulators/${encodeURIComponent(this.udid)}/location`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }).then((res) => {
        this._readout(res.ok ? 'Location sent ✓' : 'Location failed — is the device booted?');
      }).catch(() => this._readout('Location failed — network error.'));
    }

    _clear() {
      fetch(`/simulators/${encodeURIComponent(this.udid)}/location`, { method: 'DELETE' })
        .then((res) => this._readout(res.ok ? 'Cleared — live location restored.' : 'Clear failed.'))
        .catch(() => this._readout('Clear failed — network error.'));
      this._reset();
    }
  }

  window.LocationPanel = LocationPanel;
})();
