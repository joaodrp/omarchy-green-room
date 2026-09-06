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

One catch, established by measurement rather than documentation: `PwNodePeakMonitor.peak` is
not linear amplitude but its cube root (the PulseAudio perceptual volume curve). A -36 dBFS
room reads as `peak` 0.2505 = 0.01572^(1/3), verified against a simultaneous `pw-record`
capture. So true dBFS is `60*log10(peak)`, and the -60..0 display range maps to 0..1 as
`1 + log10(peak)`.

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
| Notification | Same wording and `--exec`, so a click or the "invoke last notification" keybind opens the screenshot editor on it |

A failed capture is a critical notification carrying the backend's message. The preview itself
never shows snapshot state beyond the shutter flash.
