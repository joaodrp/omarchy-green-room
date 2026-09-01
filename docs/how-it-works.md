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

## Why the mirror flip is a transform

Mirroring is `Scale { xScale: -1 }` on the `VideoOutput` — render-side only. The pipeline never
touches pixels, and anything downstream (a future snapshot) sees the unmirrored frame for free.
