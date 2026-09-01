# How it works

## The capture lifecycle

The whole capture stack — `Camera`, `CaptureSession`, `VideoOutput` — lives inside one `Loader`
whose `active` is bound to the panel's open state, gated on a device existing:

```
panel opens  -> Loader mounts the stack -> Camera streams -> first frame -> glass fades in
panel closes -> Loader destroys the stack -> /dev/videoN released
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
stream exists only while the panel is also open. So the microphone follows the camera's privacy
story — held only while you look — and `pw-dump` shows the "Quickshell Peak Detect" stream
appearing and vanishing with the panel. The node reference alone keeps the source bound (binding
is not capture), which is what makes `audio.muted` readable; a muted or missing mic shows the
slashed glyph instead of a silently flat bar. Stream errors are invisible to QML — Quickshell
only logs them, and the meter reads zero — so there is no audio equivalent of the camera's
error glass.

## Why the mirror flip is a transform

Mirroring is `Scale { xScale: -1 }` on the `VideoOutput` — render-side only. The pipeline never
touches pixels, and anything downstream (a future snapshot) sees the unmirrored frame for free.
