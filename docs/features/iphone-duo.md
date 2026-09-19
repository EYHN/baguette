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
`stream`, `serve`, `record`) now goes through the phone `Display`
rather than an unbound screen and a fixed-target input.

### Framebuffer: the `primary` panel, not the largest

`ConnectedScreens.binding(kind: .phone)` used to take the largest
portrait port. On the Duo that is the unfolded panel, which is black,
so `baguette screenshot` returned 2007×2853 of nothing. Connected
Screens carries a `Device Name:` per screen, and CoreSimulator names
the device's own panel `primary` and a foldable's second `primary-1`.
The parser now keeps that name, the port snapshot carries the mark
across the size-join, and a marked port wins outright. Devices and
enumerate output without the name fall through to the shape rule
unchanged.

`DeviceProfile` reads the same fact from `capabilities.plist` — among
the `integrated` entries it prefers `deviceName == "primary"` — so a
9-slice bezel would size to the cover, not the inner panel.

### Digitizer: the panel's own registration, not the shared slot

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
screen 3 — both built-in, and the slot ends on screen 3: the dark one.
backboardd confirms it: a tap sent to `0x32` arrives on
`ACEFADE00000009`, the sender bound to LCD-1's display UUID, and
nothing on the cover reacts.

The cover panel's own key is `0x40000001` — the `1073741825` that has
sat in the guest's published known-targets list all along
(`(50, 13, 11, 53, 51, 302, 300, 1, 14, 60, 12, 100, 54, 1073741825, 301)`).
[`companion-screens.md`](companion-screens.md) read that number as a
near-miss "registered by something else"; the something else is
step 2 above for screen 1. A tap sent there lands on `ACEFADE00000007`
and opens Settings.

`DisplayTouchTarget.resolve(kind: .phone, connectedScreenId:)` now
returns `IndigoHIDTouchTarget.panel(screenId:)` when a panel is bound
and the slot when none is. `SimulatorKitDisplay.input()` only binds one
when `IntegratedPanels.several(in:)` says the in-process port walk
found more than one portrait panel — so a one-shot tap on any
single-panel device is exactly what it was (`0x32`, no guest
round-trip, ~230 ms), and on the Duo it pays one `simctl io enumerate`
(~130 ms → ~380 ms) to learn that the lit panel is screen 1.

The rule from the CarPlay work stands, sharpened: **a target is a
registration.** `panel(screenId:)` is only ever fed a screen id that
Connected Screens lists as `Integrated`, because only those get a
create-digitizer message. Screen 2 is TVOut; `0x40000002` is still the
number that takes the guest down.

## Coordinates

Same convention as everywhere else — device points, in the lit panel's
space. `baguette chrome layout --udid <UDID>` reports the cover's
466 × 678 while folded, and that is what to pass as `--width` /
`--height`. `describe-ui` frames come back in the same space.

## What the beta cannot do yet

- **No fold / unfold.** Apple's Duo guidance describes six poses
  (closed, tent, open landscape, book, open portrait, laptop), but
  nothing shipped drives them. Host side: `simctl io screenConfig` has
  only `power` and `geometry` (powering `primary-1` on lights nothing —
  the guest's pose, not the panel's power, decides what is drawn);
  `devicectl device motion` can *monitor* a hinge angle on real
  hardware and `simulate` offers biometrics / location / statusBar;
  neither Xcode 27.0's nor 27.1 beta's Device Hub has a pose control —
  DeviceKit ships exactly one Duo asset, `v68_Closed`; UniversalHID /
  `dtuhidd` carry no hinge event type. So the Duo is a 466 × 678 phone
  with a dark second panel until Apple wires a control up.

  Where the pose actually lives, for whoever picks this up:
  - `SBFDevicePoseProvider` (SpringBoardFoundation) owns the pose.
    Its angle comes from a CoreMotion hinge manager
    (`_cmAngleManager`; CoreMotion is the guest's consumer of
    `kIOHIDEventTypeHingeAngle`), and CoreMotion is gated off on the
    simulator platform — the same hardware-capability bit that makes
    `motion.md` inject `VirtualMotion.dylib`. The hinge therefore
    reports `isAvailable = NO` and the pose never leaves *closed*.
  - It persists `SBFDevicePoseLastKnownCMAngle` in `com.apple.springboard`
    as `{isAvailable, minAngleDegrees, maxAngleDegrees, angleDegrees,
    velocityDegreesPerSeconds}` and `SBFDisplayContentModeResolver`
    reads it at init. Writing `angleDegrees = 180, isAvailable = 1`
    and restarting SpringBoard was tried: read back fine, no effect —
    the live manager's unavailability wins.
  - Two override entry points exist, both inside the guest:
    `systemServiceServer:client:setDevicePoseOverride:` (a SpringBoard
    system service) and `setDisplayToolProfileOverride:` behind
    `SBSDisplayToolService` ("swap display" / "setPrimary" / "hinge
    replay"), which logs *Insufficient authorization* for unentitled
    clients. A spike would be: inject into a guest process that holds
    the entitlement, or inject a CM hinge shim into SpringBoard the way
    `VirtualMotion` shims apps — `launchctl setenv` in the guest launchd
    plus a SpringBoard kickstart. Neither is done.

  When a control does land, "lit" will need a host-side signal —
  `primary` will presumably stop being the answer once the cover turns
  off — and that is the first thing to re-measure.
- **The unfolded panel is not a plane of its own.** `--display` still
  accepts `phone | carplay`. Exposing `primary-1` would today stream a
  black surface and drive a digitizer for a panel the guest has turned
  off. It becomes worth adding the day the hinge does.
