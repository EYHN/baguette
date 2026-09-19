# iPhone Duo (Xcode 27.1, iOS 27.1)

Xcode 27.1 beta ships the first foldable simulator, **iPhone Duo**
(`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, `iPhone19,4`,
codename `V68`; SpringBoard calls it *Butterfly*). It is one device
with **two integrated panels**, and that broke two assumptions
baguette had made since day one: "the largest portrait framebuffer is
the phone" and "the phone's digitizer is `0x32`". This page is what the
device looks like from the host, what baguette does about it, and what
the beta does not let anyone do yet.

## Getting one

The device type needs `minRuntimeVersion 27.1`, so it does not exist
until an iOS 27.1 runtime is installed — Xcode 27.0's `simctl` lists
the type but refuses to create it (`Incompatible device`), and 27.1's
refuses until the runtime lands (`Invalid runtime`).

```bash
export DEVELOPER_DIR=/Applications/Xcode-27.1.0-Beta.app/Contents/Developer
xcodebuild -downloadPlatform iOS            # iOS 27.1 Simulator, 7.85 GB
xcrun simctl create 'iPhone Duo' \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-1
```

Installing the runtime through `xcodebuild -downloadPlatform` also
auto-creates one Duo (the profile is `createByDefaultForRuntimeVersions
≥ 27.1`), so the explicit `create` is only needed when the runtime was
added some other way. Then `baguette boot --udid <UDID>` as usual —
the Device Hub heal from [`device-hub.md`](device-hub.md) applies to
this device like any other iOS 27 one.

## What the host sees

`capabilities.plist` declares two `integrated` displays; `simctl io
enumerate` lists both under Connected Screens, each with a live
`com.apple.framebuffer.display` port and an IOSurface:

| | `primary` (cover) | `primary-1` (unfolded) |
|---|---|---|
| Screen ID | 1 | 3 |
| Name | `LCD` | `LCD-1` |
| Pixels | 1398 × 2034 @3x → 466 × 678 pt | 2007 × 2853 @3x → 669 × 951 pt |
| Chrome | `phone15` | `phone14` |
| Digitizer sender | `ACEFADE00000007` | `ACEFADE00000009` |
| At boot | lit, SpringBoard's `Main` display | **dark** — guest sets `display_id=3 … target_state=off` |

Both panels report `Power state: On` and `UI Orientation: Portrait`
from the host, so nothing on the host side says which one is lit. The
guest does: SpringBoard runs a `SBCoverDisplayConfigurationTransformer`,
lights the cover, and turns the unfolded panel off. **The Duo boots
folded, and this beta has no way to unfold it** — see the last section.

The usual decoys are there too: `tvOut` and `carPlay` at 720×480 and
the 7680×4320 `scene` port. Both chrome bundles ship a baked
`PhoneComposite`, so the bezel path is unaffected.

## What baguette does

Every phone-plane entry point (`tap` / `swipe` / `input`, `screenshot`,
`stream`, `serve`, `record`, `describe-ui`, `chrome layout`) follows
the **lit** panel. Which one that is comes from the hinge.

### The hinge is read, not driven

Device Hub folds and unfolds the Duo from the pose picker at the bottom
of its window. It streams the angle into the guest as HID reports
(`UniversalHID` → `dtuhidd` → `kIOHIDEventTypeHingeAngle` → CoreMotion
→ SpringBoard's pose provider), and SpringBoard decides which panel to
light. baguette reads that angle back with

```bash
xcrun devicectl device motion hinge-angle --device <UDID> --timeout 5
```

whose first sample is the current angle and lands in ~0.3 s;
`DevicectlHinge` takes it and terminates the monitor. `HingeAngle.
litPanel` puts the swap at 90°: Device Hub's closed pose reads ≈3°,
its open pose ≈130°. Only a device with more than one portrait panel
(`IntegratedPanels.several`) ever asks — a phone pays nothing.

`GET /simulators/<udid>/hinge` reports it:

```json
{"ok":true,"foldable":true,"angleDegrees":130.0,"litPanel":"secondary","orientation":"landscape-left"}
```

### Framebuffer: the lit panel

`ConnectedScreens.binding(kind: .phone, litPanel:)` binds the port
whose Connected Screen CoreSimulator names `primary` (cover) or
`primary-1` (unfolded) according to the hinge; a device with only a
primary gets it whatever the hinge says, and output without names falls
through to the shape rule unchanged. The binding also carries the
screen's `UI Orientation`, because the open pose puts SpringBoard in
landscape by itself.

### Digitizer: the lit panel's own registration, not the shared slot

This is the one that needed the disassembler. In
`SimulatorHID` (shipped with CoreSimulator, loaded into every
runtime's backboardd),
`-[SimHIDVirtualServiceManager createDigitizerForTargetID:withDisplayUID:isBuiltIn:]`
does three things:

1. builds `com.apple.SimulatorHID.ScreenTouchService.<displayUUID>`;
2. registers it in `allServices` under the **targetID the host's
   create message carried** — which it insists has "the ScreenID mask
   bit", i.e. `0x40000000 | screenId`;
3. if `isBuiltIn`, *also* stores it under the constant `@50` (`0x32`)
   and calls `setBuiltInDigitizerService:`, which overwrites.

So `0x32` was never a digitizer of its own. It is a **slot**, owned by
the last built-in panel created. Every single-panel device creates one
built-in panel and the slot is it. The Duo creates two — screen 1, then
screen 3 — both built-in, and the slot ends on screen 3. backboardd
confirms it: a tap sent to `0x32` arrives on `ACEFADE00000009`, the
sender bound to LCD-1's display UUID.

The panels' own keys are `0x40000001` (cover) and `0x40000003`
(unfolded); the former is the `1073741825` that has sat in the guest's
published known-targets list all along, which
[`companion-screens.md`](companion-screens.md) had read as a near-miss.
`DisplayTouchTarget.resolve(kind: .phone, connectedScreenId:)` returns
`IndigoHIDTouchTarget.panel(screenId:)` for the bound (lit) panel and
the slot when none is bound.

The rule from the CarPlay work stands, sharpened: **a target is a
registration.** `panel(screenId:)` is only ever fed a screen id that
Connected Screens lists as `Integrated`, because only those get a
create-digitizer message. Screen 2 is TVOut; `0x40000002` is still the
number that takes the guest down.

### Chrome, tap space and accessibility

`DeviceProfile` reads both panels from `capabilities.plist`: the cover
is the profile's own `phone15` / 466×678, the unfolded panel is
`primary-1`'s `phone14` / 669×951. `Chromes.assets(forDeviceName:panel:)`
serves either, and `Simulator.chrome(in:)` picks by `litPanel(in:)`,
so `chrome.json`, `definition.json`, `bezel.png` and `chrome layout
--udid` all describe the lit panel. `chrome layout --device-name
"iPhone Duo" --panel unfolded` reads the open layout by name, for a
device that is folded or not booted. `describe-ui` frames come back in
the lit panel's point space (`DisplayBinding.pointSize(scale:)`).

### The page follows

`sim.html` reads `/hinge` once at boot: on a foldable it takes the
guest's orientation instead of forcing portrait (SpringBoard turns the
open pose back to landscape the moment the home screen shows), then
polls every 2 s and reloads when the lit panel or its orientation
changes — the stream, bezel, tap space and rotation are all bound at
boot, so a change means starting over. A phone answers `foldable:false`
once and is never polled again.

Known cosmetic gap: `phone14`'s power button is anchored on the top
edge and drawn from a wide image, so in the open pose it protrudes as a
bar where Device Hub shows a nub. Positions match; the art does not.

## Coordinates

Same convention as everywhere else — device points, in the lit panel's
space. `baguette chrome layout --udid <UDID>` reports the cover's
466 × 678 while folded, and that is what to pass as `--width` /
`--height`. `describe-ui` frames come back in the same space.

## Driving the hinge from baguette

Not yet. Device Hub speaks to the guest over CoreDevice's `UniversalHID`
— a Swift-only private framework that creates a virtual HID service
from a descriptor and streams generic reports (`report type
identifier 19` on service `0x1000013f5`, 60 Hz sweeps) — which baguette
cannot call safely.

What was proven to work, and is the shape a control would take: a
~60-line shim injected into SpringBoard (the process that owns the
pose) which swizzles `-[CMAngleManager startAngleUpdatesToQueue:handler:]`,
keeps the handler, and feeds it `CMAngle`s fabricated with
`initWithAngle:timestamp:continuousTimestamp:` — struct
`{eventPhase, state, angleDegrees, mechanicalAngleDegrees, progress,
velocity, angleValid, velocityValid}` (the two ints are in that order,
the reverse of the ivars), `state < 3`, `eventPhase < 6`. Delivering 0°
lit the cover and 180° lit the unfolded panel, reversibly; intermediate
angles obey SpringBoard's own hysteresis and want a velocity sweep. It
must **forward** to the original handler, or Device Hub's own hinge
goes dead (that is what made Device Hub look inert during the first
investigation). The cost is `launchctl setenv DYLD_INSERT_LIBRARIES` in
the guest launchd plus a SpringBoard restart on first arm, which kills
running apps. Not shipped: Device Hub already provides the control, and
baguette following it covers the workflow.

## What the beta cannot do yet

- **Only two poses reach the simulator.** Apple's Duo guidance lists
  six (closed, tent, open landscape, book, open portrait, laptop);
  Device Hub's picker has three and drives closed (≈3°) and open
  (≈130°). Nothing on the host sets an arbitrary angle — `simctl io
  screenConfig` has only `power` and `geometry` (powering `primary-1`
  on lights nothing; the guest's pose decides), and `devicectl device
  simulate` offers biometrics / location / statusBar.
- **`describe-ui` in landscape** maps frames through a portrait point
  size, as it always has for a rotated iPhone; the open pose is
  landscape, so expect the same skew there.
