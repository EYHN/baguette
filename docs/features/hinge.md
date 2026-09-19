# Hinge (iPhone Duo)

iPhone Duo folds. `baguette hinge` moves its hinge — Device Hub's pose
picker from the CLI, the HTTP route and the page — and reads it back.

```bash
baguette hinge --udid <UDID>                    # {"ok":true,"angleDegrees":130.0}
baguette hinge --udid <UDID> --pose closed      # 0°   sweeps over 0.8 s
baguette hinge --udid <UDID> --pose open        # 130° Device Hub's book pose
baguette hinge --udid <UDID> --pose flat        # 180°
baguette hinge --udid <UDID> --angle 95 --duration 1.2
```

```http
POST /simulators/<udid>/hinge?pose=open
POST /simulators/<udid>/hinge?angle=95&duration=1.2
GET  /simulators/<udid>/hinge
```

The `POST` blocks for the sweep and answers `{"ok":true}`; `400` for a
pose that is not `closed`/`open`/`flat`, an angle off 0–180 or a
negative duration; `404` for an unknown udid; `500` when the device
could not be driven (no `HingeControl` shipped, guest refused). On the
3D socket the picker sends `{"type":"set_pose","hingeDegrees":130}`,
and the book follows the hinge samples as the device folds, panels
swapping under it exactly as when Device Hub does it. A phone answers
the `GET` with `foldable:false` and has nothing to drive.

## How the hinge is driven

Nothing on the host sets the hinge: `devicectl device motion
hinge-angle` only reads it, `simctl` has no verb, and Device Hub's
window is opaque to accessibility. Device Hub itself speaks CoreDevice's
`UniversalHIDService` — a Swift-only private API with no module
interface — to a daemon in the guest, `dtuhidd`
(`/usr/libexec/dtuhidd`, from CoreSimulator's iphoneos platform
support). That daemon owns a set of virtual HID services registered
with backboardd through the private `HID.framework`
(`HIDVirtualEventService`), one of which it names `avpCustom`: usage
page `0xFF61`, usage `0x5B`, transport `CoreDevice`. Every pose command
Device Hub sends is dispatched on it as a **vendor-defined
`IOHIDEvent`** (page `0xFF61`, usage `0x5B`, version 0) whose payload
is a small keyed record. Watched with a HID event monitor inside the
guest while Device Hub's picker ran:

```
{provider: "com.apple.Virtualization.VirtualMachines",
 source:   "hinge-slider-control",  type: "range", value: <degrees as double>}
{provider: "com.apple.Virtualization.VirtualMachines",
 source:   "orientation-picker-control", type: "enum", value: "portrait"}
```

The record's wire form: `d3 00 00 00`, then items of `[u24 aux][u8
type]` with the top bit of `type` marking a container's last entry —
`0x01` dictionary (aux = entry count), `0x08` key (NUL-terminated, aux
= length incl NUL), `0x09` string (aux = length), `0x04` double (aux =
`0x3f`, 8 bytes little-endian) — every item padded to 4 bytes. The
`provider` names the VM-based device stack these controls were built
for; the simulator's consumer accepts them from any service of that
shape.

So baguette ships **`HingeControl`** (`Injected/HingeControl/`), an
iOS-Simulator *executable* — the first non-dylib under `Injected/`,
built and staged by the same loop — which `GuestHingeMotor` starts once
per device with `xcrun simctl spawn <udid> <HingeControl> serve` and
keeps: it registers a service of the same shape and plays each line it
is written on stdin (`sweep <from> <to> <ms>` at 60 Hz with Device
Hub's ease-out, `angle <deg>`, `orientation <name>`). The encoder
reproduces Device Hub's payload byte for byte. Sweeps queue behind one
another; a pose costs no spawn after the first (~0.9 s round trip for
Device Hub's 0.8 s sweep). `SharedHinge.fold(to:over:)` starts each
sweep from the angle last heard — or shut, as the device boots, when
nothing has been heard — and `DevicectlHinge` reads the sweep back like
any other, so the page, `litPanel` and the chrome all follow.

`orientation-picker-control` is Device Hub's rotate button by the same
route (`HingeMotor.turn(to:)`); the page's rotate button still sends
the Purple orientation event, which the guest honours or not per app.

## Known limits

- Device Hub and baguette both feed the same hinge; whoever sent last
  wins, and Device Hub's picker shows its own last pick, not the
  device's angle, until it next reads the hinge.
- `HingeControl` needs the iOS 27.1 simulator's private `HID.framework`
  to accept a virtual service from an unentitled process, which it does;
  a future runtime may not.
- The guest's hinge stream (`devicectl`) can go silent after a
  SpringBoard restart (`baguette heal`); driving still works, reading
  it back resumes once Device Hub or baguette moves the pose again.
