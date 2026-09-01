# AGENTS.md

Instructions for coding agents working in this repository (see [agents.md](https://agents.md)).

An [Omarchy 4](https://omarchy.org/manual/shell-plugins/) shell plugin: a `bar-widget` for the
Quattro Quickshell shell, id `io.github.joaodrp.green-room`.

Read these first, and do not restate them here:

| Doc | Holds |
| --- | --- |
| [README.md](README.md) | What the mirror does, its settings and its keys |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Layout, how to run it, the checks, conventions, gotchas |
| [docs/how-it-works.md](docs/how-it-works.md) | The capture lifecycle, and why teardown is the only camera-off |

## Working here

**The camera is real hardware.** The panel must release `/dev/videoN` the moment it closes;
`fuser /dev/video0` before and after is the check, not the code reading as if it releases.
CONTRIBUTING.md's Gotchas has why `Camera.active = false` is not enough.

**There are no tests that prove the panel draws.** A clean `qmllint` and a loading shell say the
file parses, not that video renders or the hover chrome appears. Look at it.

**Look at it properly.** `grim` captures, `hyprctl dispatch movecursor` drives hover. The display
is scale 2, so captured pixels are twice the logical size. Never kill `grim` mid-capture: it
wedges the compositor's screencopy, and every later capture hangs until that clears.

**Check the log with `-p`.** `qs log` without `-p "$OMARCHY_PATH/shell"` prints nothing useful, so
an empty result is not evidence of a clean load.

**Reload is a restart.** `omarchy-restart-shell` after every change; hot reload ignores a
symlinked checkout. Never `omarchy-refresh-shell` — that resets the user's bar to defaults.

Report what you verified and what you could not. A claim you did not check is worth less than
saying you did not check it.
