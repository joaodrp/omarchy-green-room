# Contributing

Bug reports, cameras that misbehave, and pull requests are all welcome.

If your camera shows the error glass or never lights up, that is a setup worth an issue: say the
camera model, `v4l2-ctl --list-devices` output, and what `qs log -p "$OMARCHY_PATH/shell"` prints
when the panel opens.

## Layout

| File | |
| --- | --- |
| `manifest.json` | Plugin contract: kind, entry point, settings schema and defaults |
| `Panel.qml` | Everything: the bar icon, the glass, the capture stack, the hover chrome, the pin window |
| `docs/how-it-works.md` | The capture lifecycle, and why teardown is the only camera-off |
| `docs/images/`, `preview.png` | README screenshots; see [Screenshots](#screenshots) |
| `.github/` | CI, and the manifest check it runs |

## Running it

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.joaodrp.green-room
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.joaodrp.green-room
```

Hot reload watches the plugins directory with `inotifywait -r`, which ignores a symlinked
checkout. Working from a symlink means restarting the shell for every change:

```sh
omarchy-restart-shell
qs log -p "$OMARCHY_PATH/shell" --tail 60   # QML errors land here, and only with -p
```

## Checks

```sh
omarchy plugin validate "$PWD"
python3 .github/check-manifest.py   # manifest, README table and Panel.qml reads agree

# QML lint needs an import dir holding a `qs` symlink to the shell
mkdir -p /tmp/qslint && ln -sfn "$OMARCHY_PATH/shell" /tmp/qslint/qs
/usr/lib/qt6/bin/qmllint -I /tmp/qslint Panel.qml
```

Use the Qt 6 `qmllint` path above: the one on `PATH` is Qt 5 and fails on every Quickshell file.
It warns `unqualified`, `missing-property` and `signal-handler-parameters` on this plugin and
every first-party panel alike — Quickshell typing gaps, not defects. Compare the warning set
before and after a change rather than aiming for silence.

The checks prove the file parses. They do not prove the panel draws, the camera streams, or the
sensor is released. For that:

```sh
omarchy-shell io.github.joaodrp.green-room open
fuser /dev/video0        # held by the shell while open
omarchy-shell io.github.joaodrp.green-room close
fuser /dev/video0        # nothing within ~2s
```

and look at the panel.

CI runs the manifest check. `omarchy plugin validate` and the linter need Omarchy and Quickshell
on the machine, so run those two yourself.

## Screenshots

The README pictures show a generated person, not a contributor's room. To reshoot them, feed
the panel a clip instead of the webcam: make a looping video from the image, then, in a local
patch you do not commit, replace the `Camera` inside the capture stack with a `MediaPlayer`
that targets the same sink:

```sh
ffmpeg -loop 1 -i face.png -t 5 -pix_fmt yuv420p -r 30 fake.mp4
```

```qml
MediaPlayer { source: "file:///path/to/fake.mp4"; videoOutput: captureStack.sink
              loops: MediaPlayer.Infinite; Component.onCompleted: play() }
```

The `live` flag, the chrome, the meter, the guides and the pin all behave as with a camera,
since every one of them hangs off the sink; only the snapshot does not, as `ImageCapture` needs
a real `Camera`. Capture with `grim`, then crop; the display is scale 2, so captured pixels are
twice the logical size. A cursor warp (`hl.dsp.cursor.move`) generates no motion event, so
follow it with a `wlrctl pointer move 2 2` to make the hover chrome appear.

## Conventions

Native to Omarchy first. Before inventing a component, look for the built-in that solves it in
`$OMARCHY_PATH/shell/Ui/` or in a first-party panel under `$OMARCHY_PATH/shell/plugins/`. The
local components earn their existence the same way: `ChipButton` because the kit buttons derive
their state fills from theme alphas tuned for themed panel surfaces — too faint to read over
moving video — and `MirrorVideo` / `MicMeterPlate` because the panel glass and the pinned window
render the same content.

Theme tokens (`Style.*`, `Color.*`) for everything that sits on the card; fixed black/white only
for what sits on the video, which no theme controls.

Comments carry what the code cannot: why an obvious alternative was rejected. They describe the
current state, never the change — git history holds that.

## Gotchas

- **`Camera.active = false` does not release the camera** on the FFmpeg backend. Only destroying
  the `Camera` object does — that is what the Loader teardown is for. See
  [docs/how-it-works.md](docs/how-it-works.md).
- **Hover dies under child controls with a `MouseArea`.** QML delivers hover to the topmost item
  only; the glass uses a whole-panel `HoverHandler`, which sees hover through children, and the
  scrim's opacity reads it. Keep it that way.
- **`Rectangle { clip: true }` clips to the rectangle, not the radius.** Rounded video corners go
  through the `MultiEffect` mask.
- **Icon glyphs lie.** Verify any new Nerd Font codepoint by rendering it
  (`magick ... label:'<glyph>'`) before shipping; two of the first three glyphs in this plugin
  were an airplane and an "HD" badge.
- **The webcam may be gone.** A Studio Display's camera disappears with the display link; the
  panel must show the no-camera glass, not error out.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), one logical change each. Describe
what the change does and why, in the body, with backticks around identifiers.

## Scope

One glance, one mirror. Camera tuning and effects are out of scope; this plugin stays the thing
you click before a meeting.
