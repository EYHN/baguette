# `baguette` CLI reference

All commands print JSON when there's structured data to return; one-shots
return `{"ok":true}` / `{"ok":false,"error":"…"}`. Errors go to stderr.

## Discovery — `list`

```bash
baguette list                  # human table (Booted ●  iPhone 17 Pro Max  iOS 26.4  <UDID>)
baguette list --json           # {"running":[…], "available":[…]}
```

Each device entry: `{ id, name, state, runtime, isBooted }`. Use `id`
(the UDID) for every other command. `state` is "Booted" or "Shutdown".

To pick the first running iPhone:

```bash
baguette list --json \
  | jq -r '.running[] | select(.name | startswith("iPhone")) | .id' \
  | head -1
```

## Lifecycle — `boot` / `shutdown`

```bash
baguette boot     --udid <UDID>
baguette shutdown --udid <UDID>
```

Headless boot — the CoreSimulator framework spins the device up without
opening Simulator.app. `boot` is idempotent: an already-booted device
returns `{"ok":true}`.

Under Xcode 27, `boot` also waits for the boot to finish and, if Device
Hub has attached to the device, reclaims the input surface (restarts
backboardd + SpringBoard, ~4 s — nothing is running yet). `--no-heal`
skips that.

## Reclaiming input from Device Hub — `heal`

```bash
baguette heal --udid <UDID>
```

Xcode 27's Device Hub attaches a HID daemon to every booted device, and
the iOS 27 runtime drops the legacy services baguette drives in
response — `tap` / `swipe` / `press` ack and land nowhere. `heal`
clears the daemon's state and restarts backboardd so the services come
back; **SpringBoard restarts with it, killing running apps** (no
reboot, ~4 s). Run it when `input` / `serve` print the "Device Hub has
attached" advisory, or after opening Device Hub on a device you booted
headlessly. Idempotent: an unshadowed device reports "nothing to heal".

## Surviving Simulator.app — `lifetime`

```bash
baguette lifetime              # report the current policy
baguette lifetime --detach     # leave devices booted on window close / quit
baguette lifetime --shutdown   # restore Apple's default
```

Simulator.app shuts a device down when you close its window or quit the
app, which kills devices baguette is driving. That bites even in a
headless workflow, because other toolchains (Expo's `i`, `xcrun simctl`
wrappers, Xcode) open Simulator.app for you — so a device you booted
headlessly acquires a window somebody can close.

The policy is two preferences in Simulator.app's own domain
(`com.apple.iphonesimulator`), which Apple groups under "Simulator
lifetime" and ships as `false`:

| Key | Simulator.app's wording |
|---|---|
| `DetachOnWindowClose` | "When closing a simulator's window leave it running" |
| `DetachOnAppQuit` | "When quitting leave simulators running" |

Both must detach for a device to survive — closing the window and
quitting the app are independent ways to lose it. The same toggles live
in Simulator → Settings… if you'd rather flip them by hand.

Two things worth knowing:

- **It's machine-wide.** These are Simulator.app's settings, not a
  device's, so there's no `--udid`. The change persists after baguette is
  uninstalled — which is why nothing applies it automatically. `serve`
  and `boot` only warn.
- **Quit Simulator.app first if you can.** A running Simulator.app may
  hold a cached copy of these keys and flush it back over the write when
  it quits. `lifetime` writes anyway (refusing would block the common
  case, since the device is often booted through Simulator.app) but tells
  you to restart it.

## Screen geometry — `chrome layout`

```bash
baguette chrome layout --udid <UDID>           # JSON
baguette chrome layout --device-name "iPhone 17 Pro Max"
```

Returns:

```json
{
  "composite": {"width": 552, "height": 1115},
  "screen":    {"width": 438, "height": 954, "x": 57, "y": 81},
  "innerCornerRadius": 55,
  "buttons": [...]
}
```

The `screen.width` / `screen.height` are the values you pass as `width` /
`height` on every gesture. `composite` is the bezel image dimensions.

## One-shot gestures

Same wire format as `baguette input`, one gesture per process. Use these
in shell scripts where you don't need streaming throughput.

```bash
baguette tap        --udid X --x 219 --y 478 --width 438 --height 954 [--duration 0.05]
baguette double-tap --udid X --x 219 --y 478 --width 438 --height 954 [--interval 0.05] [--duration 0.08]
baguette swipe --udid X --startX 219 --startY 760 --endX 219 --endY 190 \
                       --width 438 --height 954 [--duration 0.3]
baguette pinch --udid X --cx 219 --cy 478 --startSpread 60 --endSpread 240 \
                       --width 438 --height 954 [--duration 0.6]
baguette pan   --udid X --x1 175 --y1 478 --x2 263 --y2 478 \
                       --dx 0 --dy 200 --width 438 --height 954 [--duration 0.5]
baguette press --udid X --button home              # home | lock | power | volume-up | volume-down | action | app-switcher | swipe-to-app-switcher | swipe-to-home | pull-down-to-lock-screen | pull-down-to-notification-center
baguette press --udid X --button action --duration 1.2   # long-press → "Hold for Ring"
baguette press --udid X --button app-switcher                        # double home-press recipe → multitasking cards
baguette press --udid X --button swipe-to-app-switcher               # slow drag-and-hold from the bottom edge → cards (gesture path)
baguette press --udid X --button swipe-to-home                       # streamed home-indicator gesture
baguette press --udid X --button pull-down-to-lock-screen            # slow drag from top-left → lock-screen cover sheet
baguette press --udid X --button pull-down-to-notification-center    # slow drag from top-right → Notification Center
baguette key   --udid X --code KeyA --modifiers shift,command [--duration 0.2]
baguette type  --udid X --text "hello world"
baguette paste --udid X --text "héllo 🥖 any unicode" [--no-press]   # via sim pasteboard + Cmd+V
baguette clipboard get  --udid X        # print the sim's pasteboard text (raw, like pbpaste)
baguette clipboard sync --udid X        # host Mac pasteboard → sim, full-fidelity (images too)
baguette clipboard copy --udid X        # sim pasteboard → host Mac, full-fidelity (images too)
```

`x` / `y` etc. are device points (see `wire-protocol.md` for the
coordinate convention). `width` / `height` come from `chrome layout`.

### Hardware buttons — `press`

```bash
baguette press --udid X --button home                       # short tap
baguette press --udid X --button power --duration 2.5       # Siri / SOS hold
baguette press --udid X --button volume-up
```

| Button           | iOS effect                  | Long-hold (≥ ~0.8 s)              |
|------------------|-----------------------------|-----------------------------------|
| `home`           | Home / app switcher         | n/a                               |
| `lock`           | Sleep / wake                | n/a                               |
| `power`          | Sleep / wake                | Siri (~1.5 s) / SOS slider (~5 s) |
| `volume-up`      | Volume up                   | Accessibility shortcut            |
| `volume-down`    | Volume down                 | Accessibility shortcut            |
| `action`         | iPhone 15 Pro action button | "Hold for Ring" / silent flip     |
| `app-switcher`   | Two consecutive home presses → multitasking cards | n/a (canned shape) |
| `swipe-to-app-switcher` | Slow drag-and-hold from bottom edge → multitasking cards (gesture path) | n/a (canned shape) |
| `swipe-to-home`  | Swipe up from bottom edge → home | n/a (canned shape)           |
| `pull-down-to-lock-screen` | Slow drag down from top-left → lock-screen cover sheet | n/a (canned shape) |
| `pull-down-to-notification-center` | Slow drag down from top-right → Notification Center | n/a (canned shape) |

`--duration <seconds>` is optional (default ~100 ms). `siri` is
explicitly rejected — it crashes `backboardd` through every known
Indigo path. `app-switcher`, `swipe-to-app-switcher`, `swipe-to-home`,
`pull-down-to-lock-screen`, and `pull-down-to-notification-center`
are *virtual* buttons — no physical counterpart, but they're useful
when the agent wants the gesture vocabulary without managing a
streaming touch chain manually. See
[`docs/features/buttons.md`](../../../docs/features/buttons.md) and
[`docs/features/touches.md`](../../../docs/features/touches.md) for
the dispatch path.

### Keyboard — `key` / `type`

```bash
# Single keystroke. `--code` is a W3C KeyboardEvent.code.
baguette key --udid X --code KeyA                          # types 'a'
baguette key --udid X --code KeyA --modifiers shift        # 'A'
baguette key --udid X --code KeyA --modifiers shift,command --duration 0.2

# Multi-character text (US ASCII only).
baguette type --udid X --text "hello world"
baguette type --udid X --text "Login: alice@example.com"
```

Supported codes: `KeyA`–`KeyZ`, `Digit0`–`Digit9`, `Enter`, `Escape`,
`Backspace`, `Tab`, `Space`, `ArrowUp/Down/Left/Right`, US punctuation
(`Minus`, `Equal`, `BracketLeft`, …). Modifiers: `shift`, `control`,
`option`, `command` (comma-separated on the CLI). Phase-1 limits:
**no IME, no emoji, no accented characters** — those need
`KeyboardNSEvent` (phase 2). See
[`docs/features/keyboard.md`](../../../docs/features/keyboard.md).

## Streaming gestures — `input`

```bash
baguette input --udid <UDID>                # reads stdin, writes acks per line
```

Use for sequences. Reading stops on EOF. Pair with `tee` for logging:

```bash
{ echo '{"type":"button","button":"home"}'
  echo '{"type":"tap","x":219,"y":478,"width":438,"height":954}'
} | baguette input --udid X | tee /tmp/baguette-acks.log
```

## One-shot screenshot — `screenshot`

```bash
baguette screenshot --udid <UDID>                              # → JPEG on stdout
baguette screenshot --udid <UDID> --output /tmp/shot.jpg
baguette screenshot --udid <UDID> --quality 0.6 --scale 2 > thumb.jpg
```

| Flag       | Default | Effect                                                       |
|------------|---------|--------------------------------------------------------------|
| `--output` | stdout  | Write JPEG bytes to a file instead of stdout (CLI only).     |
| `--quality`| `0.85`  | JPEG lossy compression (0.0 – 1.0).                          |
| `--scale`  | `1`     | Integer downscale divisor: 1 = native, 2 = half, 3 = third.  |

Equivalent HTTP route during `baguette serve`:

```
GET http://localhost:8421/simulators/<UDID>/screenshot.jpg[?quality=0.6][?scale=2]
```

Same defaults, same bytes — the route and the CLI share `ScreenSnapshot.capture`.

**Failure modes:**
- **2 s timeout / `Failure.timeout`.** SimulatorKit only emits a frame
  on a screen change. A booted-but-idle simulator (lock screen with no
  visible clock tick, headless test runner waiting on input) may never
  produce a frame. Wake the screen with a gesture before capturing:
  ```bash
  baguette tap --udid X --x 1 --y 1 --width "$W" --height "$H"
  sleep 0.2
  baguette screenshot --udid X --output /tmp/shot.jpg
  ```
- **Unknown UDID.** HTTP returns `404 application/json {"ok":false,"error":"unknown udid: <udid>"}`;
  CLI exits non-zero with the same message on stderr.

**Limits:** JPEG only (no PNG / WebP / AVIF yet); raw framebuffer (no
bezel composite — that's a browser-side concern via `bezel.png`).

## 3D presentation render — `render-3d`

```bash
baguette render-3d --udid <UDID> \
  --variant finish=deep-blue --rotation=-8,18,0 \
  --size 1200x1200 --output device.png

baguette render-3d --screen screenshot.png --device iphone-17-pro \
  --variant finish=cosmic-orange --output device.png
```

Exactly one of `--udid` and `--screen` is required. With `--screen`, select an
installed model using `--device`. `--variant <set>=<choice>` is repeatable.
`--screen-glass` composites a subtle reflective cover glass over the screen
(off by default so screenshots stay pixel-stable).
Model bundles are discovered from `BAGUETTE_3D_MODEL_DIR`, Application
Support, then bundled `Resources/Models3D`.

HTTP uses `GET /simulators/<UDID>/3d-model.json` for public metadata and
`POST /simulators/<UDID>/render-3d.png` with JSON render options for the PNG.
The focused web UI uses these routes for its one-shot 3D preview.

## Add a file to the device — `install` / `add-media`

```bash
baguette install   --udid <UDID> ./MyApp.ipa     # install an app  → simctl install
baguette install   --udid <UDID> ./MyApp.app     # a real .app directory works too
baguette add-media --udid <UDID> ./photo.png     # add to Photos   → simctl addmedia
baguette add-media --udid <UDID> ./clip.mov
```

| Command     | Accepts                                              | simctl verb |
|-------------|-----------------------------------------------------|-------------|
| `install`   | `.ipa`, `.app`                                      | `install`   |
| `add-media` | `png jpg jpeg gif heic heif mov mp4 m4v`            | `addmedia`  |

Both take the file path as a positional argument and require `--udid`.
Classification is by extension; a path the verb can't accept exits
non-zero with a clear message (`Not an installable app …` / `Not a
supported image or video …`). Not a HID path — one-shot `xcrun simctl`.

Equivalent HTTP route during `baguette serve` (one endpoint, routed by
extension — app → install, `.zip` carrying one top-level `.app` →
extract + install, media → Photos):

```
POST http://localhost:8421/simulators/<UDID>/files?name=<filename>
     body = raw file bytes (.ipa / .app / .zip / media)
  → 200 {"ok":true,"kind":"app"}    (installed)
  → 200 {"ok":true,"kind":"media"}  (added to Photos)
  → 415 {"ok":false,"error":"no home for .<ext> on a simulator (apps, zipped apps, and media only)"}
  → 415 {"ok":false,"error":"no single .app bundle at the top level of the zip"}
  → 415 {"ok":false,"error":"ditto -x -k exited <N> (corrupt zip?)"}
```

The browser focus page (`/simulators/<UDID>`) accepts drag-and-drop onto
the device, posting to this route — a dropped folder-form `.app` is
packed into a stored zip in-page and posted as `<Name>.app.zip`. See
`docs/features/file-upload.md`.

**Limits:** in a `.zip` the `.app` must sit at the top level (for ipa
`Payload/` layout, drop the `.ipa` itself); the CLI takes a real `.app`
directory directly but not a `.zip`; generic docs (`.pdf`, `.json`, …)
have no home on a simulator and are refused.

## Appearance, contrast, text size — `interface`

```bash
baguette interface appearance --udid <UDID>                        # read → light | dark | unknown
baguette interface appearance --udid <UDID> dark                   # set
baguette interface contrast   --udid <UDID> enabled                # Increase Contrast
baguette interface text-size  --udid <UDID> accessibility-large    # Dynamic Type
baguette interface text-size  --udid <UDID> increment              # one step larger
```

| Leaf         | Values                                                              | simctl verb         |
|--------------|---------------------------------------------------------------------|---------------------|
| `appearance` | `light`, `dark`                                                     | `ui … appearance`   |
| `contrast`   | `enabled`, `disabled`                                               | `ui … increase_contrast` |
| `text-size`  | `increment`, `decrement`, or one of 12 categories                   | `ui … content_size` |

Every leaf reads with no value and sets with one. The 12 categories run
`extra-small` → `extra-extra-extra-large`, then the five accessibility
sizes `accessibility-medium` → `accessibility-extra-extra-extra-large`.

**A read on a device that isn't booted answers `unknown`, and exits 0.**
That's a state, not a failure — check for it rather than treating a
successful read as a real value. `unsupported` means the runtime has no
such setting. Neither can be *set*: `interface appearance unknown` is a
usage error, caught before simctl runs.

Useful for accessibility work: flip to dark / contrast on / an
accessibility text size, then re-run `describe-ui` and compare. See
[`docs/features/interface.md`](../../../docs/features/interface.md).

## Shake — `shake`

```bash
baguette shake --udid <UDID>   # UIKit motionShake on the frontmost app → simctl spawn notifyutil -p com.apple.UIKit.SimulatorShake
```

Device action (not a gesture): the frontmost responder gets
`motionBegan/Ended` with `UIEventSubtypeMotionShake`. iOS-only. Also on
`serve` as `POST /simulators/<UDID>/shake`. See
[`docs/features/shake.md`](../../../docs/features/shake.md).

## Simulated GPS location — `location`

```bash
baguette location set   --udid <UDID> 37.3318,-122.0312          # pin a point  → simctl location set
baguette location set   --udid <UDID> -- -37.8136,144.9631       # negative latitude: precede with --
baguette location start --udid <UDID> --speed 260 --distance 1000 \
                        37.629538,-122.395733 40.628083,-73.768254  # moving route → simctl location start
baguette location walk  --udid <UDID> --bearing 90 --speed 5 \
                        37.3349,-122.0090                        # head east    → simctl location start
baguette location clear --udid <UDID>                            # restore live  → simctl location clear
```

| Subcommand | Args                                                        | simctl verb |
|------------|-------------------------------------------------------------|-------------|
| `set`      | one `lat,lon` token                                         | `set`       |
| `start`    | two or more `lat,lon` tokens + `--speed`/`--distance`/`--interval` | `start` |
| `walk`     | one `lat,lon` token + `--bearing` (deg from N) + `--speed` (m/s) | `start` (projected) |
| `clear`    | (none)                                                      | `clear`     |

`walk` is the shell spelling of the browser's joystick: it heads off from
a position on a compass bearing and keeps going, which — unlike `set`'s
stationary pin (`course = -1`) — makes locationd derive
`CLLocation.course` from the travel. It projects a waypoint 600 s of
travel ahead and hands it to `start`. Stop it with `location set` (pins
it) or `location clear`. `--bearing` is normalised, so `-90` == `270`.

Two iOS-26 limits worth knowing before relying on this: `CLHeading` (the
magnetometer compass) is **unavailable in the simulator at all**, and
`course` is derived on a flat lat/lon grid so **diagonal** bearings come
back skewed by `1/cos(latitude)` (~6.5° at lat 37, ~18° at lat 60);
cardinal bearings are exact everywhere. See
[`docs/features/location.md`](../../docs/features/location.md).

Position and waypoints are `lat,lon` **tokens** (not `--lat` / `--lon`
flags) so a leading `-` in a western/southern coordinate isn't read as an
option. A token whose **latitude** starts with `-` must follow a `--`
separator. Latitude is validated to ±90, longitude to ±180; out-of-range
or <2-waypoint input exits non-zero with a clear message. Not a HID path —
one-shot `xcrun simctl location`.

Equivalent HTTP routes during `baguette serve`:

```
POST http://localhost:8421/simulators/<UDID>/location
     body = {"latitude":37.3318,"longitude":-122.0312}                      (a point)
       or = {"waypoints":[{"latitude":…,"longitude":…},…],"speed":260}      (a route; ≥2 waypoints)
  → 200 {"ok":true}
  → 400 {"ok":false,"error":"location body must be a point … or a … route"}

DELETE http://localhost:8421/simulators/<UDID>/location                     (clear)
  → 200 {"ok":true}
```

The browser focus page has a **Location** card (map-pin toolbar button)
with a Leaflet map — click to set a pin, or Route mode for waypoints. It
also has a place-name search (OSM Nominatim) and a "locate me" button
(the Mac's GPS). Note: `simctl location` has no read-back, so there's no
`GET …/location` and no way to query the device's current position. See
`docs/features/location.md`.

## CoreMotion — `motion`

```bash
baguette motion start --udid <UDID>                              # walking at 1.4 m/s, arms the dylib
baguette motion start --udid <UDID> --activity running           # 3.5 m/s unless --speed says otherwise
baguette motion set   --udid <UDID> --activity automotive        # change it; no re-arm, no relaunch
baguette motion stop  --udid <UDID>                              # park stationary + disarm
```

| Subcommand | Args | Effect |
|------------|------|--------|
| `start` | `[--activity <kind>] [--speed <m/s>] [--confidence low\|medium\|high]` | publish + arm the dylib |
| `set`   | same | publish only |
| `stop`  | (none) | publish stationary, then disarm |

`<kind>` is `stationary \| walking \| running \| cycling \| automotive`;
anything else exits non-zero rather than reporting `unknown`. `--speed`
defaults to that kind's usual pace (the browser's presets: Walk 1.4,
Run 3.5, Cycle 6, Drive 13.4).

**Not a simctl path, and the caveat matters more than usual.**
`CMMotionActivityManager`, `CMPedometer` and `CMMotionManager` all report
unavailable in a stock simulator, so baguette injects
`VirtualMotion.dylib` via `DYLD_INSERT_LIBRARIES`. dyld inserts at exec
time, so **only apps launched after `motion start` see anything** —
relaunch with
`xcrun simctl launch --terminate-running-process <UDID> <bundle-id>`.
Confirm injection is live with
`xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.baguette.motion"'`.

Equivalent HTTP routes during `baguette serve`:

```
POST http://localhost:8421/simulators/<UDID>/motion
     body = {"activity":"running","speed":3.6}    (names the kind)
       or = {"speed":6}                           (kind classified server-side)
  → 200 {"ok":true,"active":true,"activity":"cycling","steps":24,"metres":18.0,"speed":6.00}
  → 400 {"ok":false,"error":"motion body must name an activity: …"}

GET    http://localhost:8421/simulators/<UDID>/motion     (read back; → {"ok":true,"active":false} when off)
DELETE http://localhost:8421/simulators/<UDID>/motion     (park stationary + disarm)
```

Once armed, the **location** routes drive it: a walk vector or route
classifies by its speed, and a bare point (or `DELETE …/location`) parks
it stationary. Motion is opt-in — a location request never arms it. In the
browser, that's the **Drive motion sensors** toggle on the Location card.
Floor counting and the magnetometer stay unavailable on purpose. See
`docs/features/motion.md`.

## Network conditioning — `network`

```bash
baguette network set    --udid <UDID> --profile 3g                        # a named preset
baguette network set    --udid <UDID> --latency 300 --bandwidth 400 --loss 5
baguette network set    --udid <UDID> --offline                           # no connection at all
baguette network clear  --udid <UDID>                                     # stop, running apps included
baguette network status --udid <UDID>                                     # also plain `baguette network`
```

| Subcommand | Args | Effect |
|------------|------|--------|
| `set` | **exactly one of** `--profile <name>` / one or more of `--latency <ms>`, `--bandwidth <kbps>`, `--loss <percent>` / `--offline` | publish + arm the dylib |
| `clear` | (none) | publish "nothing", then disarm |
| `status` | (none) | report what this simulator is subject to |

Presets are Network Link Conditioner's, figures included:
`wifi | dsl | lte | 3g | edge | very-bad-network | 100-loss`. NLC states a
**one-way** delay, so each preset's round-trip latency is twice NLC's
number (`3g` = 200 ms, `edge` = 800 ms). The three numeric flags are independently
optional: give any one or more of them. An omitted `--latency` or `--loss`
is zero, and an omitted `--bandwidth` leaves the link unmetered (it is
downlink only in any case). Mixing a preset with explicit numbers, or with
`--offline`, exits non-zero rather than merging — and so does a `set`
naming nothing at all.

**Not a simctl path.** NLC and the `dnctl`/`pfctl` rules under it are
system-wide, so baguette injects `VirtualNetwork.dylib` via
`DYLD_INSERT_LIBRARIES` to scope conditioning to one simulator. dyld
inserts at exec time, so **only apps launched after `network set` are
conditioned** — relaunch with
`xcrun simctl launch --terminate-running-process <UDID> <bundle-id>`.
Changing the condition afterwards reaches a running app without a
relaunch. Confirm injection is live with
`xcrun simctl spawn <UDID> log stream --predicate 'subsystem == "com.baguette.network"'`.

Equivalent HTTP routes during `baguette serve`:

```text
POST http://localhost:8421/simulators/<UDID>/network
     body = {"profile":"3g"}
       or = {"latencyMs":300,"bandwidthKbps":400,"lossPercent":5}
       or = {"offline":true}
  → 200 {"ok":true,"active":true,"latencyMs":200,"bandwidthKbps":780,"lossPercent":0,
         "offline":false,"summary":"200 ms latency, 780 kbps","profiles":[…]}
  → 400 {"ok":false,"error":"network body must name exactly one of: …"}

GET    http://localhost:8421/simulators/<UDID>/network   (read back; → {"ok":true,"active":false,…} when off)
DELETE http://localhost:8421/simulators/<UDID>/network   (clear, running apps included)
```

**Only URLSession-shaped traffic is conditioned.** REST, GraphQL and image
loading are, and `URLSessionWebSocketTask` gets its own hooks (latency,
loss, offline — not bandwidth). An SDK that opens its own socket is not
reached: Ably's ably-cocoa vendors SocketRocket, and its hooks never fire.
`NWConnection`/Network.framework, raw sockets and most gRPC are not
conditioned either — structurally, since `URLProtocol` is part of the URL
Loading System. **`WKWebView` and Safari page loads are not
conditioned either**: WebKit fetches page resources in its own networking
process. A hybrid app's native `fetch` calls are throttled while the web
content beside them is not. For an app whose realtime layer uses a
**custom** WebSocket transport rather than `URLSessionWebSocketTask`,
`--offline` degrades its request traffic without the app noticing it went
offline. Loss is request-level (a proportion of requests
fail immediately), not packet-level. A debug React Native build has its JS
bundle download conditioned too, so arm something mild, let the app load,
then change the condition live. See `docs/features/network.md`.

## Accessibility tree — `describe-ui`

```bash
baguette describe-ui --udid <UDID>                                   # full frontmost-app tree, JSON to stdout
baguette describe-ui --udid <UDID> --x 172 --y 880                   # hit-test: topmost AX node at (172, 880)
baguette describe-ui --udid <UDID> --output /tmp/tree.json
```

Returns one JSON object (the root `AXNode`) per call:

```json
{
  "role": "AXButton",
  "subrole": null,
  "label": "Safari",
  "value": null,
  "identifier": "Safari",
  "title": null,
  "help": "Double tap to open",
  "frame": { "x": 136, "y": 844.33, "width": 72, "height": 72 },
  "enabled": true, "focused": false, "hidden": false,
  "children": []
}
```

`frame` is in **device points** — same units as `tap` / `swipe`
wire fields (`x`, `y`, `width`, `height`). An agent that wants to
"tap the Safari button" reads `frame.x + frame.width/2`,
`frame.y + frame.height/2` straight back into a `tap` envelope.

| Flag       | Default | Effect                                                       |
|------------|---------|--------------------------------------------------------------|
| `--x`      | unset   | Hit-test x coordinate (device points). Pair with `--y`.      |
| `--y`      | unset   | Hit-test y coordinate (device points). Pair with `--x`.      |
| `--output` | stdout  | Write the JSON to a file instead of stdout.                  |

Both `--x` and `--y` must be given together; either alone errors.

**Failure modes:**
- **`no accessibility data`** — simulator not booted, or the
  frontmost slot is empty (e.g. lock screen with nothing focused).
  Exits non-zero. Wake the screen with a gesture or boot the sim.
- **Framework load failure.** `baguette` logs `[ax]` lines on
  stderr; the CLI exits non-zero. Most common cause is running on
  an Xcode older than 26 — the dispatcher recipe targets iOS 26+.

## Live unified log — `logs`

```bash
baguette logs --udid <UDID>                                 # info-and-above, line-buffered to stdout
baguette logs --udid <UDID> --level debug                   # everything including debug-level chatter
baguette logs --udid <UDID> --style json                    # one JSON object per line
baguette logs --udid <UDID> --bundle-id com.apple.MobileSafari
baguette logs --udid <UDID> --predicate 'subsystem == "com.apple.UIKit"'
baguette logs --udid <UDID> | grep -i error                 # composes with shell pipelines; SIGINT to stop
```

| Flag           | Default   | Effect                                                            |
|----------------|-----------|-------------------------------------------------------------------|
| `--level`      | `info`    | `default` \| `info` \| `debug`. iOS-runtime `log stream` accepts only these three; **not** `notice / error / fault`. |
| `--style`      | `default` | `default` \| `compact` \| `json` \| `ndjson` \| `syslog`.         |
| `--predicate`  | unset     | Raw `NSPredicate` passed to `log stream --predicate` verbatim.    |
| `--bundle-id`  | unset     | Shorthand → `process == "<id>"`. ANDs with `--predicate` when both given. |

Equivalent WebSocket route during `baguette serve`:

```
WS  /simulators/<UDID>/logs?level=info&style=default[&predicate=…&bundleId=…]
→ {"type":"log_started"}
→ {"type":"log","line":"<entry>"}
→ {"type":"log_stopped","reason":"…"}
```

Filter is fixed at connect time — restart the socket to change it. Send `{"type":"stop"}` to terminate early.

**Failure modes:**
- **`logs: invalid --level '<x>'`** — the simulator's `log` binary only accepts `default | info | debug`. Map `error` / `fault` requirements onto a predicate (`messageType == 'error'`).
- **Spawn failure.** Surfaced on stderr as `logs: <error>`. Most common: simulator not booted.
- **Slow consumer (WS only).** Buffered to 2048 lines per socket; older lines drop silently if the client falls behind.

## Live frame stream — `stream`

```bash
baguette stream --udid <UDID> --format mjpeg --fps 60
baguette stream --udid <UDID> --format avcc  --fps 60      # H.264 NAL units
```

Writes the live encoded stream to stdout. Pipe to `ffplay` or a
recording sink. For a single still image use `baguette screenshot`
above — it has no encoder warm-up cost and respects a clean 2 s
timeout. `stream | head -c …` is *not* the snapshot path; the live
stream pipeline interferes with concurrent gestures.

## Standalone web UI — `serve` (for humans, not agents)

```bash
baguette serve [--host 127.0.0.1] [--port 8421]
# → http://localhost:8421/simulators            (device list)
# → http://localhost:8421/simulators/<UDID>     (focus mode — 1 sim, fullscreen)
# → http://localhost:8421/farm                  (multi-device dashboard)
```

Agents typically don't need this — `baguette input` is the programmatic
path. Mention it once if a human asks how to interact with the sim
themselves while you work.

## Bezel rasterisation — `chrome composite`

```bash
baguette chrome composite --udid <UDID>            > bezel.png
baguette chrome composite --device-name "iPhone 17 Pro Max" > bezel.png
```

Returns the device chrome (rounded glass + buttons) as a PNG, suitable
for compositing under a captured screenshot.

## Exit codes

`0` on success. `1` on any error; the JSON error body explains. Errors
that come from SimulatorHID (wrong UDID, device not booted, malformed
gesture) return `{"ok":false,"error":"…"}` and exit `1` — parse stdout,
not just the exit code.
