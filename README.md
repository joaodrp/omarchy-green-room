# Hand Mirror

A quick check of how you look, from the Omarchy bar. In the spirit of
[Hand Mirror](https://handmirror.app/) for macOS: click the camera icon,
see yourself in a mirrored live preview, click again and the camera is off.

## Features

- Live 16:9 video filling the whole panel — the framing call participants
  actually see — mirrored like a mirror (toggle to see yourself as others do)
- The camera is held only while the panel is open and released when it
  closes — nothing keeps `/dev/videoN` busy in the background
- Controls appear only on hover: flip (`m`), next camera (`c`, only with
  more than one camera; the choice is persisted), mic check (`a`)
- Optional mic check: a segmented input level meter on the glass,
  dBFS-scaled so speech lands mid-meter, with a peak-hold and an urgent
  top cell when the input runs hot; the microphone, like the camera, is
  read only while the panel is open
- The panel border doubles as the camera-on light (accent while live)
- Keybindable: `omarchy-shell io.github.joaodrp.hand-mirror toggle`

## Requirements

- Omarchy 4.0 or newer
- Qt Multimedia (`qt6-multimedia`)
- A V4L2 webcam

## Install

```sh
omarchy plugin add https://github.com/joaodrp/omarchy-hand-mirror.git --enable
```

## Settings

| Key | Default | What it does |
| --- | --- | --- |
| `device` | `auto` | Camera device id; `auto` follows the system default |
| `mirror` | `true` | Mirror the preview horizontally |
| `micCheck` | `false` | Show a live mic level meter on the glass |
| `previewWidth` | `560` | Mirror width in px (320-960, 16:9) |

## Why not omarchy-webcam or cam-preview?

[Webcam Controls](https://github.com/kristoferlund/omarchy-webcam) is a
camera tuning tool with a preview attached; [Camera
Preview](https://github.com/mandavkarpranjal/cam-preview) predates Qt
versions where live video works in the shell and renders a still-capture
slideshow. Hand Mirror is just the mirror: one click, live video,
mirrored, nothing else.

## License

MIT
