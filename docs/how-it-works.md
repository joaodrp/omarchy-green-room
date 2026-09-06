# How it works

## The capture lifecycle

The capture stack — `Camera` and `CaptureSession` — lives inside one root-level `Loader`
whose `active` is bound to either mirror surface (panel or pin) being open, gated on a device
existing; the session targets whichever surface's `VideoOutput` is showing:

```
mirror opens  -> Loader mounts the stack -> Camera streams -> first frame -> glass fades in
mirror closes -> Loader destroys the stack -> /dev/videoN released
```

There is no explicit stop anywhere: destruction is the off switch.

## Why teardown is the only camera-off

On Qt's FFmpeg camera backend (the default on Arch), `Camera.active = false` leaves the V4L2
device open and streaming; only destroying the `Camera` object releases the sensor. Verified
against Qt 6.11: `fuser /dev/video0` shows the shell holding the device across an
`active = false`, and dropping it within ~2s of the Loader deactivating.

This is also why the stack is remounted (via a brief `deviceRestart` flip) whenever the
*resolved* camera changes — a chosen device, but also an `auto` default that moves or a fallback
after unplug — rather than ever retargeting `cameraDevice` on a live `Camera`.

## Why live video, not a still-capture slideshow

Older camera plugins for Omarchy render a "slideshow" of JPEG still captures because a
`VideoOutput` created after shell start never painted — the sink received frames, the scene
graph node did not. That bug does not reproduce on Qt 6.11 + Quickshell 0.3: a late-mounted
`VideoOutput` in a late-mapped window paints real frames. So this plugin uses the direct
pipeline, with none of the temp-file polling.

## Why MultiEffect masks the corners

`Rectangle { radius; clip: true }` clips children to the rectangle, not to the rounded shape, so
video would leak into the corners. The glass renders into a layer and is drawn through a rounded
`maskSource` by `MultiEffect` — real alpha clipping, which also stays correct on themes with
translucent popup backgrounds.

## The mic check

The level meter is driven by Quickshell's `PwNodePeakMonitor` on `Pipewire.defaultAudioSource` —
the same primitive behind the shell audio panel's input meter.

The ten cells cover -60..0 dBFS — 6 dB per cell, fine enough that syllable-scale dynamics move
the meter while you talk — so speech lands mid-meter the way it does in other mic-check UIs; a
linear amplitude scale would show healthy speech (~-20 dBFS, 0.1 linear) as one dim cell.
One catch, established by measurement rather than documentation: `PwNodePeakMonitor.peak` is not
linear amplitude but its cube root (the PulseAudio perceptual volume curve) — a -36 dBFS room
reads as `peak` 0.2505 = 0.01572^(1/3), verified against a simultaneous `pw-record` capture. So
true dBFS is `60*log10(peak)`, and the -60..0 display range maps to 0..1 as `1 + log10(peak)`.
The top cell starts at -6 dBFS — the conventional caution zone — and lights in the theme's
urgent color; the brightest recently hit cell holds for a second so a peak that lands between
glances still registers. Unlike the camera, it needs no
teardown dance: the monitor's `node` is set only while the check is on, and its PipeWire capture
stream exists only while a mirror is also showing (panel or pin). So the microphone follows the
camera's privacy story — held only while you look — and `pw-dump` shows the "Quickshell Peak
Detect" stream appearing and vanishing with the mirror. The node reference alone keeps the source bound (binding
is not capture), which is what makes `audio.muted` readable; a muted or missing mic shows the
slashed glyph instead of a silently flat bar. Stream errors are invisible to QML — Quickshell
only logs them, and the meter reads zero — so instead of an error glass there is a watchdog: a
meter flat for ten straight seconds gets its node rebound, which is invisible on a genuinely
quiet mic and revives a stream killed by, say, a Bluetooth headset's profile switch (verified by
destroying the stream node with `pw-cli` and watching it return).

## The pin

Pinning lifts the panel's glass into a small always-on-top `FloatingWindow` — same video
pipeline, same mic meter, picture-in-picture manners: drag anywhere to move (the drag handler
calls the backing window's native `startSystemMove`, so the compositor drives the whole
interaction), an invisible grip in each corner for `startSystemResize` (the window can sit in
any corner of the screen, so every corner must resize toward the opposite one), and a settled
resize becomes the new default size.

The compositor treatment — float, pin to every workspace, full opacity, no dim, no focus
steal, locked 16:9 — is one window rule the plugin registers on the first panel open (every
pin is preceded by one, which leaves the async eval ample time to land) through the fork's
runtime config eval (`hyprctl eval 'o.window(...)'`), keyed on the window title since every
Quickshell toplevel shares the `org.quickshell` app id (Qt has no per-window Wayland app id).
A rule is the only lever that covers all of it: the shell-wide `default-opacity` tag, visibly
translucent over video, yields to nothing else, and the `window.*` dispatchers act only on the
focused window (their selectors merely filter), which makes scripted correction fragile. The
one dispatch that remains is corner placement at map — a rule cannot express "monitor edge
minus this window's size" — and it runs inside a focus sandwich for exactly that reason.

The camera never blinks across the handoff: one capture stack lives in a root-level Loader
gated on either surface being open, and `CaptureSession.videoOutput` simply retargets between
the panel's sink and the pin's. Two ordering rules keep it seamless: `pin()` raises `pinned`
before closing the panel so the Loader's `active` never dips (a same-turn remount races the
FFmpeg backend's asynchronous device release and stalls silently), and the pin window is sized
imperatively before it is shown (a declarative size binding can evaluate before the widget's
own properties during creation and the surface would map at a fallback size).

## Why the mirror flip is a transform

Mirroring is `Scale { xScale: -1 }` on the `VideoOutput` — render-side only. The pipeline never
touches pixels, so the snapshot below starts from the camera's true frame.

## The snapshot

The frame comes from the capture session's own `ImageCapture` — the camera's frame at sensor
resolution, not a grab of the scaled glass. It is then made into the glass's picture in place:
`magick` flips it when the mirror is on and center-crops it to 16:9 (a webcam sensor is usually
4:3; the glass shows the same crop via `PreserveAspectCrop`), so what you saw is what you get and
the `m` key doubles as "snapshot as others see me".

From there the snapshot is an Omarchy screenshot: the directory is resolved by the same rule as
`omarchy-capture-screenshot` (`OMARCHY_SCREENSHOT_DIR`, else the XDG pictures dir, else
`~/Pictures`, created if missing), the file goes on the clipboard with `wl-copy`, and the
notification carries the same wording and `--exec` as a screenshot's, so a click or the "invoke
last notification" keybind opens the screenshot editor on it. A failed capture is a critical
notification with the backend's message; the glass itself never shows snapshot state beyond the
shutter flash.
