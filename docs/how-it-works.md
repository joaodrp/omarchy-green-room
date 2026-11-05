# How it works

Detail behind the [README](../README.md): why the camera and the microphone are held the way
they are, and the findings each part of the panel rests on. "The preview" below is the `glass`
item in `Panel.qml`.

## The capture lifecycle

The capture stack (`Camera` + `CaptureSession`) lives inside one root-level `Loader`. Its
`active` is bound to either mirror surface being open, panel or pin, and to a device existing.
The session targets whichever surface's `VideoOutput` is showing.

```
mirror opens  -> Loader mounts the stack -> Camera streams -> first frame -> preview fades in
mirror closes -> Loader destroys the stack -> /dev/videoN released
```

There is no explicit stop anywhere. Destruction is the off switch.

## Why teardown is the only camera-off

On Qt's FFmpeg camera backend (the default on Arch), `Camera.active = false` leaves the V4L2
device open and streaming. Only destroying the `Camera` object releases the sensor.

Verified against Qt 6.11 with `fuser /dev/video0`: the shell holds the device across an
`active = false`, and drops it within about 2 s of the Loader deactivating.

The same fact is why the stack is remounted (a brief `deviceRestart` flip) whenever the
*resolved* camera changes, rather than ever retargeting `cameraDevice` on a live `Camera`.
"Resolved" covers a chosen device, an `auto` default that moves, and a fallback after unplug.

## How the chosen camera is found

Qt's camera id is the `/dev/videoN` path, and the kernel numbers those in probe order, so a
saved path can name another camera after a reboot or replug. The choice is saved as path,
serial and name, and `devices.mjs` resolves it:

| Saved | Resolves to |
| --- | --- |
| `auto` | The system default |
| A serial | The input with that serial; among several (one camera can expose an IR input beside the RGB one), the one with the saved name. If none is connected, the default: no name match against a twin of the same model |
| A name, no serial | The camera with that name; with two of one name, the one at the saved path, else the first |
| A path only | The camera at that path |

The serial is the USB device's, read from `/sys/class/video4linux/videoN/device/../serial`
with a `FileView` per device. Reads are asynchronous, so the camera is chosen imperatively once
every connected device has reported, not by binding: a binding would re-point the `Camera`
when the list changes, before its serials say which camera is which. A device-list change
rebuilds the readers, so a path reused by another camera is always read again. Until every
serial is in, no new capture mounts: the previous answer may name a path another camera now
holds, and a `Camera` with no device opens the system default. A capture already running rides
out the rescan, and the remount key is path plus serial.

`devices.mjs` is plain JavaScript, imported by the panel and tested with
`node --test .github/test-devices.mjs`.

## Why live video, not a still-capture slideshow

Older camera plugins for Omarchy render a slideshow of JPEG still captures, because a
`VideoOutput` created after shell start never painted: the sink received frames, the scene
graph node did not. That bug does not reproduce on Qt 6.11 + Quickshell 0.3. A late-mounted
`VideoOutput` in a late-mapped window paints real frames, so this plugin uses the direct
pipeline, with none of the temp-file polling.

## Why MultiEffect masks the corners

`Rectangle { radius; clip: true }` clips children to the rectangle, not to the rounded shape,
so video would leak into the corners. The preview renders into a layer and is drawn through a
rounded `maskSource` by `MultiEffect`: real alpha clipping, which also stays correct on themes
with translucent popup backgrounds.

A new frame inside the layer does not schedule a window redraw, so the panel requests one on
each `videoFrameChanged` while the glass is showing. The pinned window draws the video directly
and needs none.

## The mic check

The meter is driven by Quickshell's `PwNodePeakMonitor` on `Pipewire.defaultAudioSource`, the
same primitive behind the shell audio panel's input meter.

### The scale

| | |
| --- | --- |
| Range | -60..0 dBFS over ten cells, 6 dB each |
| Why dBFS | Speech lands mid-meter, as in other mic-check UIs, and syllable-scale dynamics (~6-8 dB) visibly move it. A linear scale would show healthy speech (~-20 dBFS, 0.1 linear) as one dim cell |
| Top cell | Starts at -6 dBFS, the conventional caution zone, in the theme's urgent color |
| Peak hold | The brightest recently hit cell keeps glowing for a second, so a peak that lands between glances still registers |
| Speech target | -30..-12 dBFS, cells 6-8, tinted on hover: loud enough to sit well above room noise, with headroom below the caution cell |

One catch, established by measurement rather than documentation: `PwNodePeakMonitor.peak` is
not linear amplitude but its cube root (the PulseAudio perceptual volume curve). A -36 dBFS
room reads as `peak` 0.2505 = 0.01572^(1/3), verified against a simultaneous `pw-record`
capture. So true dBFS is `60*log10(peak)`, and the -60..0 display range maps to 0..1 as
`1 + log10(peak)`.

### The level

Scroll and `up`/`down` write `Pipewire.defaultAudioSource.audio.volume` in 5% steps, the value
the shell audio panel's input slider and the bar's mic icon read. There is no plugin copy of
the level: the source's own volume is the state, so the three never disagree.

A wheel notch is 120 units of `angleDelta`. Touchpads send smaller deltas, so the meter sums
them and steps once per notch's worth, starting over when the direction flips.

### Holding the microphone

- The monitor's `node` is set only while the check is on, and its PipeWire capture stream
  exists only while a mirror is showing (panel or pin). The microphone follows the camera's
  privacy story: `pw-dump` shows the "Quickshell Peak Detect" stream appearing and vanishing
  with the mirror.
- The node reference alone keeps the source bound (binding is not capture), which is what makes
  `audio.muted` readable. A muted or missing mic shows the slashed glyph instead of a silently
  flat bar.
- A plain peak monitor is invisible to WirePlumber's headset autoswitch, so a Bluetooth headset
  left in A2DP would keep its mic off and the meter would read a mic no call uses. The check
  therefore also holds a real capture (`pw-record` to `/dev/null`) while it runs, which flips
  the headset to its call profile, the same thing a call does. Released with the mirror.

### The watchdog

Stream errors are invisible to QML: Quickshell only logs them, and the meter reads zero. So
instead of an error state there is a watchdog. A meter flat for ten straight seconds gets its
node rebound, which is invisible on a genuinely quiet mic and revives a stream killed by, say, a
Bluetooth headset's profile switch. Verified by destroying the stream node with `pw-cli` and
watching it return.

## The pin

Pinning lifts the preview into a small always-on-top `FloatingWindow`: same video pipeline, same
mic meter, picture-in-picture manners.

| Interaction | How |
| --- | --- |
| Drag anywhere to move | The drag handler calls the backing window's native `startSystemMove`; the compositor drives the whole interaction |
| Drag any corner to resize | An invisible grip in each corner calls `startSystemResize` with that corner's edges. The window can sit in any corner of the screen, so every corner must resize toward the opposite one |
| Size sticks | A settled resize is written back as `pinWidth` |

### One window rule

The compositor treatment is a single window rule, registered on the first panel open through
the fork's runtime config eval (`hyprctl eval 'o.window(...)'`):

| Field | Gives |
| --- | --- |
| `float`, `pin` | Floating, on every workspace |
| `tag = "-default-opacity"`, `opacity = "1 1"` | Full opacity. The shell-wide `default-opacity` tag is visibly translucent over video and yields to nothing else |
| `no_initial_focus`, `no_dim` | No focus steal, no dimming |
| `keep_aspect_ratio` | 16:9 through resizes |
| `move = "monitor_w-window_w-40 monitor_h-window_h-40"` | Bottom-right placement, evaluated by the compositor at map against this window's size |

Details that matter:

- The rule keys on the window title: every Quickshell toplevel shares the `org.quickshell` app
  id, since Qt has no per-window Wayland app id.
- A rule is the only lever that covers all of the above. The `window.*` dispatchers act only on
  the focused window (their selectors merely filter), so placing the window by dispatch means
  focusing it first, and the focus handback can land on another workspace and drag the user
  there. With `move` in the rule, nothing is dispatched at all.
- Registration happens on panel open rather than widget load because every pin is preceded by
  an open, which leaves the async eval ample time to land. A rule with the same match replaces
  the earlier one, so re-running it is idempotent.

### The handoff

The camera never blinks across pinning: the one capture stack stays mounted, and
`CaptureSession.videoOutput` retargets between the panel's sink and the pin's. Two ordering
rules keep it seamless:

- `pin()` raises `pinned` before closing the panel, so the Loader's `active` never dips. A
  same-turn remount races the FFmpeg backend's asynchronous device release and stalls silently.
- The pin window is sized imperatively before it is shown. A declarative size binding can
  evaluate before the widget's own properties during creation, and the surface would map at a
  fallback size.

## Why the mirror flip is a transform

Mirroring is `Scale { xScale: -1 }` on the `VideoOutput`, render-side only. The pipeline never
touches pixels, so the snapshot starts from the camera's true frame.

## The snapshot

The frame comes from the capture session's own `ImageCapture`: the camera's frame at sensor
resolution, not a grab of the scaled preview. `magick` then makes it the preview's picture in
place: flipped when the mirror is on, center-cropped to 16:9 (a webcam sensor is usually 4:3;
the preview shows the same crop via `PreserveAspectCrop`). What you saw is what you get, and
`m` doubles as "snapshot as others see me".

From there the snapshot is an Omarchy screenshot:

| Step | Same as `omarchy-capture-screenshot` |
| --- | --- |
| Directory | `OMARCHY_SCREENSHOT_DIR`, else the XDG pictures dir, else `~/Pictures`, created if missing |
| Clipboard | `wl-copy` |
| Notification | Open and Edit buttons where `omarchy-notification-send` takes `--action`; else a click, or the "invoke last notification" keybind, opens the editor |
| Editor | `OMARCHY_SCREENSHOT_EDITOR` while it is installed, else Omasnap, else Tensaku |

A failed capture is a critical notification carrying the backend's message. The preview itself
never shows snapshot state beyond the shutter flash.
