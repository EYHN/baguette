# Xcode 27's Device Hub and the input surface

Xcode 27 replaced Simulator.app with **Device Hub**. It doesn't just
draw the device window — it attaches a HID daemon of its own to every
booted simulator, and the iOS 27 runtime tears down the legacy input
services baguette drives in its favour. After that, `baguette tap` /
`swipe` / `press` still print `{"ok":true}` and the device never sees
the event. This page is the root cause, the repair, and where it is
wired ([#77](https://github.com/tddworks/baguette/issues/77)).

## Entry points

| Surface | Invocation | What it does |
|---------|------------|--------------|
| **CLI** | `baguette boot --udid <UDID>` | Boots, waits for the boot to finish, heals if Device Hub attached. `--no-heal` opts out. |
| **CLI** | `baguette heal --udid <UDID>` | Heals on demand — for a device booted some other way, or one Device Hub was opened on later. |
| **HTTP** | `POST /simulators/<UDID>/boot` | Same heal as the CLI boot, after `{"ok":true}` is decided. |
| **`baguette input`** | startup | One advisory on stderr naming `baguette heal` when the surface is shadowed. |
| **`baguette serve`** | stream attach | Same advisory in the server log, per WebSocket. |

The heal is not free: it restarts backboardd, and SpringBoard with it.
**Running apps are killed**, the device is not rebooted, and it is back
in about four seconds. That's why `boot` does it unasked — nothing is
running yet — while sessions only advise.

## What actually breaks

Device Hub runs a guest daemon per device, `dtuhidd`
(`CoreSimulator.framework/…/Platforms/iphoneos/usr/libexec/dtuhidd`,
launchd label `com.apple.coredevice.dtuhidd`). On start it registers
its own CoreDevice virtual HID services inside backboardd —
`mainTouchscreen(0x101)`, `touchscreen(0x104)`, `mainKeyboard`,
`mainScreenButtons` — and publishes one Darwin notify state:

```
com.apple.coredevice.dtuhidd.active = 1
```

backboardd's `SimHIDVirtualServiceManager` (the `SimulatorHID` library
that hosts the legacy Indigo services `IndigoHIDInput` sends to through
`SimDeviceLegacyHIDClient`) watches that state. On `dtuhidd state
changed to active` it **disconnects** `ExternalKeyboardService`,
`MainScreenButtonsService` and the main-display `ScreenTouchService`.

The iOS 27 runtime then never gets them back. Its lazy reconnect —
`Connecting dtuhidd-suppressed service due to IndigoHID event` on the
next Indigo message — re-adds the **same, already-invalidated**
`IOHIDServiceRef`: the guest log shows `Service added` and `Service
removed` for it in the same millisecond, `digitizer attached` never
follows, and SimulatorHID records the service as connected so it never
tries again. Every later event goes to a service backboardd doesn't
have. Two consequences:

- **Touch is a boot-order race.** If SimulatorHID initialises *before*
  dtuhidd flips the state (typically ~100 ms apart), it connects the
  touch service, then disconnects it → dead. If dtuhidd is already
  active at init, the touch service is *born suppressed* and the first
  baguette tap lazily creates a fresh one → works, even though it is
  not the main-display digitizer. Booting headless and opening Device
  Hub afterwards always takes the first branch.
- **Buttons and keyboard are dead whenever Device Hub has attached.**
  Those two services are always connected at init and always
  disconnected on activation — no race, no priming trick.

The reporter's workaround ("send any event before Device Hub attaches")
works for touch because SimulatorHID skips disconnecting the touch
service when it has already seen an Indigo event. It does nothing for
buttons, and there is no boot-time window for it when Device Hub is
already running.

## The repair

Two guest commands, in this order:

```bash
xcrun simctl spawn <UDID> notifyutil -s com.apple.coredevice.dtuhidd.active 0
xcrun simctl spawn <UDID> launchctl kickstart -k system/com.apple.backboardd
```

The new backboardd's SimulatorHID initialises reading "no Device Hub"
and connects every legacy service; the legacy touch service becomes the
main-display digitizer. dtuhidd notices its HID clients died
(`notification: terminated, reactivating`) and re-registers its own
services alongside (`*** already have a main display digitizer`) — the
same coexistence as the reporter's primed scenario, where both Device
Hub and baguette keep working. Verified on iOS 27.0 (24A434): taps land,
`press home` produces `Button began/finished` from the legacy sender.

Order matters. Clearing the state *after* the restart would hand the
new backboardd an active→inactive edge, and on iOS 27 that edge is
exactly the connect→disconnect that kills a service. Clearing it alone,
without the restart, reconnects nothing usable — the dead services are
already marked connected.

The state stays `0` until dtuhidd itself restarts, i.e. until the user
quits and relaunches Device Hub. At that point `shadowed` reads `1`
again, the advisory comes back, and `baguette heal` repairs it again.

## Detection

`xcrun simctl spawn <UDID> notifyutil -g com.apple.coredevice.dtuhidd.active`
printing `… 1` is the whole signal. It is one guest round-trip (~300 ms)
and it is exact: `1` means Device Hub attached during this backboardd's
life, which is precisely the condition that needs healing (buttons are
gone regardless of how the touch race went). Xcode 26 runtimes never
publish the key and read as `0`; so does a device that is shut down.

`baguette boot` has one more subtlety: `Simulator.boot()` returns as
soon as the device *state* flips. launchd starts SpringBoard and
backboardd within a second of that, dtuhidd publishes its state a
second later, and the home screen is many seconds out. So the boot
path first blocks on `simctl bootstatus -b`, then — only if Device Hub
is running on the host (`com.apple.dt.Devices`) — waits up to ten
seconds for the state to appear before deciding there is nothing to
heal. On a warm boot `bootstatus` returns ~1.3 s after `boot`, which is
too close to dtuhidd's ~2 s to trust on its own.

Ground truth when investigating, rather than the reporter's
"did Settings launch" probe (which is confounded by whatever icon sits
at the tapped point):

```bash
xcrun simctl spawn <UDID> log show --last 30s \
  --predicate 'process == "backboardd" AND category == "TouchEvents" AND eventMessage CONTAINS "presence: touching"'
```

## Where it lives

```
Domain/Simulator/
  DeviceHubAttachment      parse the notify state · the advisory text
  LaunchdJobs              parse `launchctl list` → pid of a label
  InputSurface             @Mockable: shadowed(on:) · ready(on:) · reclaim(on:)
                           + heal(on:) / healAfterBoot(on:) default impls → HealOutcome
Infrastructure/Simulator/
  SimctlInputSurface       the argv above over `Subprocess`; polls `launchctl list`
                           until SpringBoard is back under a new pid, then settles 2 s
  DeviceHubApp             is Device Hub running on the host (NSRunningApplication)
App/Commands/
  BootCommand              healAfterBoot unless --no-heal
  HealCommand              heal
  InputCommand             shadowed → advisory
Infrastructure/Server/Server.swift
  POST /simulators/:udid/boot → healAfterBoot · streamWS → advisory
```

Everything down to the `xcrun` spawn is unit-covered through
`MockSubprocess` (`SimctlInputSurfaceTests`); `HostSubprocess` and
`DeviceHubApp` are the integration-only lines.

## What this is not

- **Not a change to how input is sent.** baguette still speaks the
  legacy Indigo port. Device Hub itself uses CoreDevice +
  `UniversalHID.framework`, which reaches dtuhidd's `IndigoHIDServer`
  over guest XPC (`com.apple.coredevice.feature.remote.hid.digitizer`
  and siblings). Adopting that transport is the durable fix — Apple is
  clearly retiring the legacy services — but it is a separate
  reverse-engineering effort; Xcode 27's SimulatorKit still ships only
  `SimDeviceLegacyHIDClient`.
- **Not `baguette lifetime`.** That writes Simulator.app's preferences
  (`com.apple.iphonesimulator`); Device Hub ignores them, and quitting
  Device Hub shuts every booted device down. No Device Hub equivalent
  has been found yet.
- **Not prevention.** SimulatorHID reacts to state *changes*, so
  forcing the state to `0` during boot still yields the fatal
  connect→disconnect once dtuhidd flips it. Heal after the fact.
