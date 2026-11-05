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
| `devices.mjs` | Which connected camera the saved choice means; plain JavaScript, tested with `node` |
| `snapshot.sh` | Where a snapshot is saved, and how it is copied and announced, as the installed Omarchy does for a screenshot; tested with `node` |
| `dev/host/` | A Quickshell instance that hosts only this panel; see [Running it](#running-it) |
| `docs/how-it-works.md` | The capture lifecycle, and why teardown is the only camera-off |
| `docs/images/` | README screenshots; see [Screenshots](#screenshots) |
| `preview.png` | The listing image the [plugin marketplace](https://plugins.omarchy.org/publish.html) reads from the repository root |
| `docs/card/` | The source of `preview.png` and the frames it shows; see [Listing image](#listing-image) |
| `.github/`, `release-please-config.json`, `.release-please-manifest.json` | CI with its manifest check and tests, and the release automation; see [Releases](#releases) |

## Running it

Develop in the test host: a second Quickshell instance that loads `Panel.qml` from this checkout
under a stand-in bar icon, with the shell's own `Ui` and `Commons` and the current theme. The
running shell is never reloaded or restarted, so the bar, open panels and keybinds stay as they
are.

```sh
dev/host/host.sh start '{"micCheck":true}'   # (re)load; settings merge over the manifest defaults
dev/host/host.sh ipc open                    # or close, toggle
dev/host/host.sh log                         # QML errors and console.warn lines
dev/host/host.sh stop
```

`start` again after every change. `GR_X` moves the stand-in icon (logical px, default 900);
`GR_PLUGIN` loads another folder, such as a patched copy for [Screenshots](#screenshots).
Settings written by the panel last until `stop`.

The host is for development. Check a finished change once in the real bar, from a symlinked
install:

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.joaodrp.green-room
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.joaodrp.green-room
omarchy-restart-shell
qs log -p "$OMARCHY_PATH/shell" --tail 60   # QML errors land here, and only with -p
```

Hot reload ignores the symlink, so the shell picks up a change only on restart. Never edit, copy
into or run `git` in a plugin folder under `~/.config/omarchy/plugins/` while the shell runs; see
[Gotchas](#gotchas).

## Checks

```sh
omarchy plugin validate "$PWD"
python3 .github/check-manifest.py   # manifest, README table and Panel.qml reads agree
node --test .github/test-devices.mjs   # camera resolution
node --test .github/test-snapshot.mjs  # snapshot notification

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
dev/host/host.sh start
dev/host/host.sh ipc open
fuser /dev/video0        # held while open
dev/host/host.sh ipc close
fuser /dev/video0        # nothing within ~2s
```

and look at the panel; [Testing live](#testing-live) does that without a person at the keyboard.

CI runs the manifest check and the `node` tests. `omarchy plugin validate` and the linter need
Omarchy and Quickshell on the machine, so run those two yourself.

## Testing live

Everything a person does at the panel can be scripted, so test changes yourself before asking
anyone to look.

| To | Run |
| --- | --- |
| Load a change | `dev/host/host.sh start` |
| Open, close | `dev/host/host.sh ipc open` / `close` |
| Press a panel key | `wtype p`, `wtype -k Up` (any key from the README table). Keys go to the focused surface: toggle `g` and watch it change first |
| Scroll | `wlrctl pointer scroll 15 0` (one notch down; negative scrolls up) |
| Read the mic level | `wpctl get-volume @DEFAULT_AUDIO_SOURCE@` |
| Move the pointer | `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'` (logical pixels) |
| See the screen | `grim -s 0.5 /tmp/screen.png`, then read the image |
| Find the pinned window | `hyprctl clients -j \| jq '.[] \| select(.title == "Green Room")'` |
| Read QML logs | `dev/host/host.sh log` |
| Check the cameras | `fuser /dev/video*` |

Debug with temporary `console.warn` lines and read them from the log. `grim -g` takes logical
coordinates: half the pixel position in a `grim -s 0.5` shot on a 2x display.

Video must move on its own. Park the pointer off the panel, then grab the video area twice and
compare exactly: a denoising camera barely changes a still scene.

```sh
grim -g "X,Y WxH" /tmp/a.png; sleep 1; grim -g "X,Y WxH" /tmp/b.png
magick compare -metric AE /tmp/a.png /tmp/b.png null:   # frozen: 0
```

Before blaming the panel, rule out the camera. Set the format explicitly: a device keeps the last
one any app chose, frame rate included.

```sh
ffmpeg -f v4l2 -input_format mjpeg -video_size 1280x720 -i /dev/videoN -t 5 -f null -
```

## Screenshots

The README pictures show a generated person, not a contributor's room. To reshoot them, feed
the panel a clip instead of the webcam: make a looping video from the image, then, in a copy of
the plugin outside the repository, replace the `Camera` inside the capture stack with a
`MediaPlayer` that targets the same sink, and drop `camera: camera` from the `CaptureSession`.
Load the copy with `GR_PLUGIN=/path/to/copy dev/host/host.sh start`. The image
must carry no chrome, since the controls are translucent, and is flipped (`magick -flop`) to
look right in the mirrored preview:

```sh
ffmpeg -loop 1 -i face.png -t 5 -pix_fmt yuv420p -r 30 fake.mp4
```

```qml
MediaPlayer { source: "file:///path/to/fake.mp4"; videoOutput: captureStack.sink
              loops: MediaPlayer.Infinite; Component.onCompleted: play() }
```

The `live` flag, the chrome, the meter, the guides and the pin all behave as with a camera,
since every one of them hangs off the sink; only the snapshot does not, as `ImageCapture` needs
a real `Camera`. Shoot on an empty workspace, and patch any caption that would show a real
device name. Capture with `grim`, then crop to match the existing pictures: 1150x740 for the
default width at scale 2, where captured pixels are twice the logical size. A picture about one
control is cut from that frame, 570 px wide with about 20 px of video around the control, and
shown at `width="285"`, the same scale as the full frames. A cursor warp
(`hl.dsp.cursor.move`) generates no motion event, so follow it with a `wlrctl pointer move 2 2`
to make the hover chrome appear.

### Listing image

`preview.png` is `docs/card/preview.html` rendered at 1920x1080. The marketplace crops it to about
2:1 and shows it 505 px wide with the plugin name underneath, so the page keeps everything that
matters out of the top and bottom 60 px. It is set in iA Writer Quattro S and JetBrainsMono Nerd
Font, both installed by Omarchy.

| File | Shot, with the same clip and patch as above | Cut |
| --- | --- | --- |
| `panel.png` | Hover chrome, every chip showing (the camera chip needs a second camera, or `visible: true`), meter at 7 cells | The 16:9 video area, 1120x630 |
| `meter.png` | Pointer on the meter, 6 cells, caption patched to `USB Microphone at 70%` | `520x110+0+520` of the video area |
| `chips.png` | Pointer on the camera chip, hint patched to `Studio Display Camera (c)` | `470x150+325+480` of the video area |

Pin the meter by replacing the `meterLitCells` binding with a constant. The outlines in the page
sit on `panel.png`'s meter and chip row, so check them after a new frame.

```sh
chromium --headless --hide-scrollbars --window-size=1920,1080 --screenshot=preview.png docs/card/preview.html
optipng -o2 preview.png
```

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
- **A write under `~/.config/omarchy/plugins/` reloads every plugin.** The shell watches the
  whole tree, `.git/` included, so a `git pull` or `checkout` there fires dozens of reloads.
  Each one rebuilds every panel, first-party ones too, and the log warns that the new IPC
  handlers "will not be used because another handler is registered": IPC calls and keybinds
  can be left pointing at the old panels until a restart. Work in the test host and keep the
  installed copy untouched.
- **Restart sparingly, never refresh.** `omarchy-restart-shell` blanks the bar and closes
  whatever is open; `omarchy-refresh-shell` resets the user's bar to defaults.
- **Stop Quickshell by its exact command line.** `pkill -f 'qs -p ...'` also matches the shell
  running the command and kills it; `host.sh` uses `pkill -x -f`.
- **`qs log` without `-p "$OMARCHY_PATH/shell"` prints nothing useful**, so an empty result is
  not evidence of a clean load.
- **`grim` hangs while the display is DPMS-off or the session is locked**; check
  `hyprctl monitors -j` before blaming the capture, and never kill `grim` mid-capture: it wedges
  the compositor's screencopy until that clears.
- **Report what you verified and what you could not.** A clean lint and a loading shell say the
  file parses, not that video renders or the sensor is released; `fuser /dev/video0` and a look
  at the panel are the checks.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), one logical change each. Describe
what the change does and why, in the body, with backticks around identifiers.

## Releases

[release-please](https://github.com/googleapis/release-please) reads the Conventional Commits on
`main` and keeps a release pull request open with the next version and the changelog. Merging
it bumps `version` in `manifest.json`, tags `vX.Y.Z` and publishes the GitHub release, then
checks that the tag and the manifest agree. `feat` bumps the minor version,
`fix` the patch, a `!` or `BREAKING CHANGE` footer the major. The release pull request is
opened with the workflow token, so CI does not run on it; the merge commit is checked as usual.

## Scope

One glance, one mirror. Camera tuning and effects are out of scope; this plugin stays the thing
you click before a meeting.
