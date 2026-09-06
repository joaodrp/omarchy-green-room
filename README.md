# Green Room

A quick check of how you look, from the Omarchy bar. In the spirit of
[Hand Mirror](https://handmirror.app/) for macOS: click the bar icon,
see yourself in a mirrored live preview, click again and the camera is off.

## Features

- Live 16:9 video filling the whole panel — the framing call participants
  actually see — mirrored like a mirror (toggle to see yourself as others do)
- The camera is held only while a mirror is showing — panel or pin —
  and released when the last one closes; nothing keeps `/dev/videoN`
  busy in the background
- Controls appear only on hover: flip (`m`), next camera (`c`, only with
  more than one camera; the choice is persisted), mic check (`a`),
  snapshot (`s`), pin (`p`)
- Optional mic check: a segmented input level meter on the glass,
  dBFS-scaled so speech lands mid-meter, with a peak-hold and an urgent
  top cell when the input runs hot; the microphone, like the camera, is
  read only while the mirror is showing
- Pin (`p`): the mirror lifts out of the popup into a small always-on-top
  16:9 window in the bottom-right corner that follows you across
  workspaces — drag anywhere to move it, drag any corner to resize
  (aspect stays locked, the size sticks); the hover chip docks it back
  into the panel, while a click on the bar icon — or Esc, once the
  window has focus — closes it outright; the mic meter comes along when
  the mic check is on
- Snapshot (`s`): saves what the glass shows — mirrored or not, 16:9,
  at camera resolution — as a PNG, treated like any Omarchy screenshot:
  same directory, copied to the clipboard, and a notification that
  opens the editor on click
- Keybindable: `omarchy-shell io.github.joaodrp.green-room toggle`

## Requirements

- Omarchy 4.0 or newer
- Qt Multimedia (`qt6-multimedia`)
- A V4L2 webcam

## Install

```sh
omarchy plugin add https://github.com/joaodrp/omarchy-green-room.git --enable
```

## Settings

| Key | Default | What it does |
| --- | --- | --- |
| `device` | `auto` | Camera device id; `auto` follows the system default |
| `mirror` | `true` | Mirror the preview horizontally |
| `micCheck` | `false` | Show a live mic level meter on the glass |
| `previewWidth` | `560` | Mirror width in px (320-960, 16:9) |
| `pinWidth` | `320` | Pinned mirror width in px (240-960, 16:9); also set by resizing the pin |

## Why not omarchy-webcam or cam-preview?

[Webcam Controls](https://github.com/kristoferlund/omarchy-webcam) is a
camera tuning tool with a preview attached; [Camera
Preview](https://github.com/mandavkarpranjal/cam-preview) predates Qt
versions where live video works in the shell and renders a still-capture
slideshow. Green Room is just the pre-meeting check: one click, live
video, mirrored, with an optional mic meter, a pinnable corner mirror
and a snapshot — nothing else.

## License

MIT
