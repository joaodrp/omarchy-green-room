import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Green Room: click the bar icon, see yourself. The panel is nothing but
// the glass — a live 16:9 mirror. Idle it reads as dark glass with a
// specular glare; live video fades in like the mirror catching light.
// Controls appear only on hover.
//
// The capture stack (Camera + CaptureSession) mounts and is destroyed
// together with whichever surface shows it — the popup or the pinned
// mirror — via the root-level Loader: on Qt's FFmpeg camera backend
// `Camera.active = false` leaves /dev/videoN open and streaming, and
// only destroying the Camera object releases the sensor.
Panel {
  id: root
  moduleName: "io.github.joaodrp.green-room"
  ipcTarget: "io.github.joaodrp.green-room"

  // ---------------------------------------------------------------- devices
  MediaDevices { id: mediaDevices }

  readonly property var devices: mediaDevices.videoInputs
  readonly property bool hasDevices: devices.length > 0
  readonly property string requestedDeviceId: String(root.setting("device", "auto") || "auto")
  // Mirrored by default: an unmirrored preview is useless for fixing your hair.
  readonly property bool mirrored: root.setting("mirror", true) !== false
  // Framing guides: rule-of-thirds lines, the top one the eye line — the
  // one thing a mirror cannot tell you is whether you are centered and
  // at eye height.
  readonly property bool guides: root.setting("guides", false) === true
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var selectedDevice: {
    if (!root.hasDevices) return null
    if (root.requestedDeviceId !== "auto") {
      for (var i = 0; i < root.devices.length; i++) {
        if (String(root.devices[i].id) === root.requestedDeviceId) return root.devices[i]
      }
    }
    return mediaDevices.defaultVideoInput
  }

  function cycleDevice() {
    if (root.devices.length < 2) return
    var current = root.selectedDevice ? String(root.selectedDevice.id) : ""
    var next = 0
    for (var i = 0; i < root.devices.length; i++) {
      if (String(root.devices[i].id) === current) { next = (i + 1) % root.devices.length; break }
    }
    root.persistSetting("device", String(root.devices[next].id))
  }

  // ------------------------------------------------------------------- mic
  // Mic check: a peak meter on the glass, fed by a PipeWire capture stream
  // that exists only while the mirror is showing (panel or pin) with the
  // check on — the mic, like the camera, is held only while you look.
  readonly property bool micCheck: root.setting("micCheck", false) === true
  readonly property var micSource: Pipewire.defaultAudioSource
  // No source reads as muted: on a mic check, "nothing will be heard"
  // must not look like "you're quiet".
  readonly property bool micMuted: !micSource || !micSource.audio || micSource.audio.muted === true

  // The node reference alone keeps the source bound while the check is on
  // — binding is not capture, so nothing holds the mic — and a bound node
  // is what makes audio.muted readable. The capture stream exists only
  // while enabled. Stream errors are invisible to QML (Quickshell only
  // logs them); the meter degrades to reading zero.
  PwNodePeakMonitor {
    id: micPeak
    node: root.micCheck && !root.micRebind ? root.micSource : null
    enabled: root.showing
  }

  // A peak monitor is deliberately invisible to WirePlumber's headset
  // autoswitch, so a Bluetooth headset left in A2DP keeps its mic off and
  // the meter reads a mic no call would use. Hold a real capture while
  // the check runs — what a call does: the headset flips to its
  // mic-capable profile and the meter shows what the far side would
  // hear. Released with the mirror, like the camera. (Bluetooth audio
  // quality drops to call-grade while held; that is the honest preview.)
  Process {
    command: ["pw-record", "/dev/null"]
    running: root.showing && root.micCheck && !!root.micSource
  }

  // Watchdog for the invisible stream death: a Bluetooth profile switch
  // (headset in/out of ears) can kill the capture stream with no signal
  // reaching QML, freezing the meter at zero until a manual reopen. A
  // meter flat for ten straight seconds is either true silence or that
  // death; rebinding the node is invisible for the former and revives
  // the latter.
  property bool micRebind: false
  onMicRebindChanged: if (micRebind) Qt.callLater(function() { root.micRebind = false })
  Timer {
    interval: 10000
    repeat: true
    running: root.showing && root.micCheck && !!root.micSource
    onTriggered: if (micPeak.peak <= 0) root.micRebind = true
  }

  // The meter's derivation, at root because it reads the one mic — the
  // two MicMeterPlate surfaces are pure presentation over these values,
  // so per-peak math runs once and a held peak survives the pin handoff.
  //
  // Ten cells across -60..0 dBFS — 6 dB each, so syllable-scale dynamics
  // (~6-8 dB) visibly move the meter while you talk: nine accent cells up
  // to -6, then an urgent cell for the caution zone. The brightest
  // recently hit cell keeps glowing dimly for a second after the level
  // falls below it, so glanced-past peaks still register.
  //
  // PwNodePeakMonitor.peak is the cube root of linear amplitude (the
  // PulseAudio perceptual volume curve) — measured: a -36 dBFS room
  // read as peak 0.2505 = 0.01572^(1/3). So true dBFS is
  // 60*log10(peak), and -60..0 maps to 0..1 as 1 + log10(peak).
  readonly property int meterCells: 10
  // The caution cell starts at -6 dBFS = 0.9 on the 0..1 scale; the
  // accent cells split the range below it evenly.
  readonly property real meterCaution: 0.9
  readonly property real meterCellSpan: meterCaution / (meterCells - 1)
  readonly property real meterLevel: micPeak.peak > 0
    ? Util.clamp(1 + Math.log10(micPeak.peak), 0, 1) : 0
  // Quantized once, so per-cell bindings re-evaluate only when the
  // picture changes, not on every peak update (~50-100/s).
  readonly property int meterLitCells: meterLevel > meterCaution
    ? meterCells : Math.ceil(meterLevel / meterCellSpan)
  property int meterHeldCell: -1
  onMeterLitCellsChanged: {
    // While the level covers the held cell the hold is invisible and
    // needs no decay; the decay runs from the moment the level first
    // drops below — started, not restarted, so fluctuation further
    // down cannot extend a stale hold past its second.
    if (meterLitCells - 1 >= meterHeldCell) { meterHeldCell = meterLitCells - 1; holdDecay.stop() }
    else if (!holdDecay.running) holdDecay.start()
  }
  Timer {
    id: holdDecay
    interval: 1000
    onTriggered: root.meterHeldCell = root.meterLitCells - 1
  }

  // ------------------------------------------------------------------- pin
  // Pin: the mirror lifts out of the popup into a small always-on-top
  // 16:9 window in the bottom-right corner — the panel's glass gone
  // picture-in-picture. Drag anywhere to move it, drag the corner to
  // resize (aspect locked by the compositor); the hover chip docks it
  // back into the panel, Esc and the bar icon close it outright.
  property bool pinned: false
  // A mirror surface — panel or pin — is up: the gate for everything
  // held only while you look (camera Loader, mic stream, watchdog).
  readonly property bool showing: opened || pinned
  // The window's only compositor identity (Qt has no per-window Wayland
  // app id, so every Quickshell toplevel is org.quickshell): the rule
  // and the placement dispatches all key on this one string.
  readonly property string pinTitle: "Green Room"

  // close() means "mirror off", pin included: the IPC `close` verb (and
  // Esc, and toggle's closing half) must never leave a pinned camera
  // running behind a closed panel — that is the privacy promise. pin()
  // hides through the controller directly to keep its handoff ordering.
  function close() {
    root.pinned = false
    root.controller.hide()
  }

  // Only a live mirror is worth pinning: with no picture in the panel
  // there is no picture to lift out.
  function pin() {
    if (!root.live) return
    // Size before the flip: the surface is created the moment pinned
    // rises, and a size set after that is ignored for the initial
    // configure. Then pinned rises before the panel hides, so the
    // capture Loader's active never dips false mid-handoff. A dip would
    // destroy and same-turn remount the camera, and the FFmpeg backend
    // releases /dev/videoN asynchronously — the instant reopen of a
    // still-held device stalls silently, with no frame and no error.
    pinWindow.applySize()
    root.pinned = true
    root.controller.hide()
  }

  // A camera problem while pinned docks the mirror back into the panel:
  // the pin is pure picture and cannot explain itself, the panel can
  // (error text, "no camera found").
  onCameraErrorChanged: if (cameraError !== "" && pinned) root.open()
  onHasDevicesChanged: if (!hasDevices && pinned) root.open()

  // Panel and pin are exclusive views of the one capture stack: opening
  // the panel takes the mirror back. The first open also registers the
  // pin window's compositor rule through the fork's runtime config eval —
  // rules are the only lever that covers float, pin, aspect lock and the
  // shell-wide default-opacity tag (visibly translucent over video),
  // since the `window.*` dispatchers act only on the focused window.
  // Deferred to here rather than widget load because every pin is
  // preceded by an open (pin needs a live mirror), which leaves the
  // async eval ample time to land before the surface maps; re-running
  // it in a later session is behaviorally idempotent.
  property bool pinRuleRegistered: false
  onOpenedChanged: {
    if (!opened) return
    root.pinned = false
    if (root.pinRuleRegistered) return
    root.pinRuleRegistered = true
    pinRuleProc.running = true
  }

  // Not fire-and-forget: a failed eval (IPC down, stock Hyprland without
  // the fork's eval) would make every pin of the session map tiled and
  // translucent with nothing attributing it to this plugin. A non-ok
  // reply warns and re-arms the registration for the next open.
  Process {
    id: pinRuleProc
    command: ["hyprctl", "eval",
      'o.window({ class = "^org.quickshell$", title = "^' + root.pinTitle + '$" }, { '
      + 'tag = "-default-opacity", opacity = "1 1", float = true, pin = true, '
      + 'no_initial_focus = true, no_dim = true, keep_aspect_ratio = true })']
    stdout: StdioCollector { id: pinRuleOut }
    onExited: function(exitCode, exitStatus) {
      if (pinRuleOut.text.trim() === "ok") return
      console.warn("green-room", "pin window rule registration failed:",
        pinRuleOut.text.trim() || ("exit " + exitCode), "- retrying on next open")
      root.pinRuleRegistered = false
    }
  }

  // -------------------------------------------------------------- snapshot
  // Snapshot: what the glass shows — the mirror setting and the 16:9
  // crop as you see them — handled like any omarchy screenshot from
  // there on: saved to the screenshot directory, copied to the
  // clipboard, announced by a notification that opens the editor on
  // click. The frame comes from the capture session's own ImageCapture,
  // so it is the camera's, at sensor resolution, never the scaled glass;
  // mirror and crop are applied to the file afterwards.
  signal snapshotSaved(string path)
  function snapshot() {
    if (!root.live || snapshotDir.running) return
    snapshotDir.running = true
  }

  // The directory is resolved per snapshot by omarchy-capture-screenshot's
  // own rule (env override, XDG pictures dir, ~/Pictures) and created the
  // way that script creates it, so a snapshot always lands beside the
  // screenshots.
  Process {
    id: snapshotDir
    command: ["bash", "-c",
      '[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs; '
      + 'd="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"; mkdir -p "$d" && echo "$d"']
    stdout: StdioCollector { id: snapshotDirOut }
    onExited: function(exitCode, exitStatus) {
      var dir = snapshotDirOut.text.trim()
      if (exitCode !== 0 || dir === "") { root.snapshotFailed("could not create the screenshot directory"); return }
      // The mirror can close between the keypress and this reply.
      if (!capture.item) return
      capture.item.snapshot(dir + "/green-room-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".png")
    }
  }

  // The sensor frame becomes the glass's picture in place: flipped when
  // the mirror is on, center-cropped to 16:9 (the fx picks whichever
  // side the sensor's aspect leaves too long). Then the same wording and
  // click action as a screenshot notification, so the "invoke last
  // notification" keybind edits a snapshot too.
  onSnapshotSaved: function(path) {
    var q = Util.shellQuote(path)
    Util.execDetached('magick ' + q + (root.mirrored ? ' -flop' : '')
      + " -gravity center -extent '%[fx:w*9>h*16?h*16/9:w]x%[fx:w*9>h*16?h:w*9/16]' " + q + '; '
      + 'wl-copy --type image/png <' + q + '; '
      + 'omarchy-notification-send "Snapshot saved to clipboard and file" "Edit with Super + Alt + , (or click this)" '
      + '--image ' + q + ' --exec "$(printf "%q %q" "${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit}" ' + q + ')"')
  }

  function snapshotFailed(message) {
    console.warn("green-room", "snapshot failed:", message)
    Util.execDetached('omarchy-notification-send -u critical "Green Room: snapshot failed" ' + Util.shellQuote(message))
  }

  // ---------------------------------------------------------------- sizing
  // 16:9, the framing call participants actually see.
  readonly property int mirrorWidth: Util.clamp(root.setting("previewWidth", 560), 320, 960)
  readonly property int mirrorHeight: Math.round(root.mirrorWidth * 9 / 16)

  // The pin window's width (16:9 follows). Written back when the user
  // resizes the pinned window, so the chosen size sticks across pins;
  // reader and writer share these bounds (mirrored in manifest.json).
  readonly property int pinMinWidth: 240
  readonly property int pinMaxWidth: 960
  readonly property int pinWidth: Util.clamp(root.setting("pinWidth", 320), pinMinWidth, pinMaxWidth)
  readonly property int pinHeight: Math.round(root.pinWidth * 9 / 16)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ----------------------------------------------------------------- state
  // The chip under the pointer (null = none). The caption derives its
  // text from this reference, so a hint that changes under a stationary
  // pointer can never go stale.
  property var hoveredChip: null
  // "" = fine, otherwise the message shown on the glass.
  property string cameraError: ""
  // First frame arrived for the current session: the glass lights up.
  property bool live: false
  // Set briefly when the camera selection changes so the capture stack is
  // torn down and remounted with the new device.
  property bool deviceRestart: false

  // Keyed on the resolved device, not the setting: hotplug can flip the
  // resolution (auto default changes, chosen camera unplugged) without the
  // setting moving, and retargeting a live Camera is the path that leaves
  // the old /dev/videoN open. Same-device resolutions do not restart.
  readonly property string activeDeviceId: root.selectedDevice ? String(root.selectedDevice.id) : ""
  onActiveDeviceIdChanged: {
    root.deviceRestart = true
    Qt.callLater(function() { root.deviceRestart = false })
  }

  // Merge one key into this widget's inline settings. Local-first so the
  // glass reacts on the click; the shell.json write settles behind it.
  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    else
      console.warn("green-room", "shell.updateEntryInline unavailable; setting", key, "will not survive a restart")
  }

  // --------------------------------------------------------------- capture
  // One capture stack serves both surfaces: the session re-targets its
  // sink when the mirror moves between the popup glass and the pinned
  // window, so the camera is opened once and never contended across the
  // handoff.
  Loader {
    id: capture
    active: root.showing && root.hasDevices && !root.deviceRestart
    onActiveChanged: {
      if (!active) {
        root.live = false
        root.cameraError = ""
      }
    }
    sourceComponent: Item {
      id: captureStack
      // The one place that decides which surface the frames feed. Bound
      // here rather than on root: this evaluates at mount, when both
      // video ids exist — a root-level binding can evaluate during
      // widget creation, capture nothing, and never re-fire.
      readonly property var sink: root.pinned ? pinVideo : panelVideo

      Camera {
        id: camera
        active: true
        // undefined (not null) keeps the property unset until a
        // device resolves, at which point the binding re-evaluates.
        cameraDevice: root.selectedDevice !== null ? root.selectedDevice : undefined
        onErrorOccurred: function(error, errorString) {
          if (error === Camera.NoError) return
          console.warn("green-room", "camera error", error, errorString)
          root.cameraError = String(errorString || "") || "Camera unavailable"
        }
      }
      function snapshot(path) { imageCapture.captureToFile(path) }

      CaptureSession {
        camera: camera
        videoOutput: captureStack.sink
        imageCapture: ImageCapture {
          id: imageCapture
          fileFormat: ImageCapture.PNG
          onImageSaved: function(requestId, fileName) { root.snapshotSaved(fileName) }
          onErrorOccurred: function(requestId, error, message) { root.snapshotFailed(message) }
        }
      }
      Connections {
        target: captureStack.sink.videoSink
        // One-shot once healthy: disabling drops the per-frame
        // dispatch. Stays armed while errored so a frame from a
        // recovered camera clears the stale error glass — errorOccurred
        // never re-fires with NoError on its own.
        enabled: !root.live || root.cameraError !== ""
        function onVideoFrameChanged() {
          root.cameraError = ""
          root.live = true
        }
      }
    }
  }

  // ------------------------------------------------------------------- bar
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰴂"
    active: root.showing && root.cameraError === ""
    tooltipText: "Green Room"
    // While pinned the icon is an off switch: the red icon reads as "on",
    // so the click ends the pin, not detours through the panel — that
    // stays one more click away for the rarer "back to the big mirror".
    onPressed: function(button) {
      if (button !== Qt.LeftButton) return
      if (root.pinned) root.pinned = false
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // Edge to edge: the glass is the whole card, no padding ring, and no
    // card border — the bezel hairline below is the panel's only ring, so
    // the video area stays exactly 16:9.
    padding: 0
    borderSpec: Border.none()
    contentWidth: root.mirrorWidth
    contentHeight: root.mirrorHeight

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m") root.persistSetting("mirror", !root.mirrored)
        else if (t === "c") root.cycleDevice()
        else if (t === "a") root.persistSetting("micCheck", !root.micCheck)
        else if (t === "g") root.persistSetting("guides", !root.guides)
        else if (t === "p") root.pin()
        else if (t === "s") root.snapshot()
      }

      // Glass content, rendered offscreen and drawn through the rounded
      // mask. The layers exist only while the panel's window is mapped, so
      // the shell does not keep two offscreen textures alive for a popup
      // that is typically open seconds per day — gated on the window, not
      // `opened`, so the close fade still has a texture to draw.
      Item {
        id: glass
        anchors.fill: parent
        visible: false
        layer.enabled: panel.visible

        Rectangle { anchors.fill: parent; color: "#0a0a0c" }

        // Specular glare: dark glass reflecting nothing. Gone once live.
        Item {
          anchors.fill: parent
          visible: !root.live
          Rectangle {
            x: -parent.width * 0.15; y: parent.height * 0.02
            width: parent.width * 0.5; height: parent.height * 1.1
            rotation: 24
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.05) }
              GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
          }
          Rectangle {
            x: parent.width * 0.42; y: -parent.height * 0.05
            width: parent.width * 0.1; height: parent.height * 1.1
            rotation: 24
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
              GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.035) }
              GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
          }
        }

        MirrorVideo {
          id: panelVideo
          showing: !root.pinned
        }
      }

      // Rounded-corner mask: real alpha clipping, so corners stay clean
      // on themes with translucent popups.
      Rectangle {
        id: glassMask
        anchors.fill: parent
        visible: false
        layer.enabled: panel.visible
        layer.smooth: true
        color: "white"
        antialiasing: true
        radius: Style.cornerRadius
      }

      MultiEffect {
        anchors.fill: parent
        source: glass
        maskEnabled: true
        maskSource: glassMask
      }

      // No frame around live video — screens are bezel-less, and the video
      // is its own edge. The hairline exists only for the dark glass, which
      // would otherwise dissolve into a dark wallpaper; it fades away as
      // the video fades in.
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        antialiasing: true
        radius: Style.cornerRadius
        border.width: Style.spacing.hairline
        border.color: root.live ? "transparent" : Util.alpha(root.barForeground, 0.22)
        Behavior on border.color { ColorAnimation { duration: 300 } }
      }

      // HoverHandler rather than MouseArea: hover must survive the pointer
      // moving onto the chips (a MouseArea loses containsMouse to them,
      // fading out the very control under the cursor).
      HoverHandler {
        id: hoverArea
      }

      // Mic check meter: not hover-gated — you watch it while talking.
      // Before the scrim in draw order so the hover chrome wins overlaps.
      MicMeterPlate {}

      // Hover chrome: a bottom scrim with icon-only controls. Disabled while
      // faded out so an invisible chip cannot swallow a click.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(64)
        bottomLeftRadius: Style.cornerRadius
        bottomRightRadius: Style.cornerRadius
        // Shown over live video and over the no-camera/error glass alike:
        // the mic chip must stay reachable with a dead camera, which is
        // exactly when "at least check my mic" matters.
        opacity: hoverArea.hovered && (root.live || !root.hasDevices || root.cameraError !== "") ? 1 : 0
        enabled: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(10)
          spacing: Style.space(8)

          ChipButton {
            glyph: "󱃧"
            on: root.mirrored
            hint: root.mirrored ? "mirrored (m)" : "as others see you (m)"
            onActivated: root.persistSetting("mirror", !root.mirrored)
          }

          ChipButton {
            visible: root.devices.length > 1
            glyph: "󰄈"
            hint: (root.selectedDevice ? String(root.selectedDevice.description) : "") + " (c)"
            onActivated: root.cycleDevice()
          }

          ChipButton {
            glyph: "󰍬"
            on: root.micCheck
            hint: root.micCheck ? "mic check on (a)" : "mic check off (a)"
            onActivated: root.persistSetting("micCheck", !root.micCheck)
          }

          ChipButton {
            visible: root.live
            glyph: "󰊓"
            on: root.guides
            hint: root.guides ? "framing guides on (g)" : "framing guides off (g)"
            onActivated: root.persistSetting("guides", !root.guides)
          }

          ChipButton {
            visible: root.live
            glyph: "󰄀"
            hint: "snapshot (s)"
            onActivated: root.snapshot()
          }

          ChipButton {
            visible: root.live
            glyph: "󰐃"
            hint: "pop out (p)"
            onActivated: root.pin()
          }
        }

        // One caption slot for whichever chip is hovered: says what the
        // control will act on, in place of a tooltip.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(54)
          text: root.hoveredChip ? root.hoveredChip.hint : ""
          visible: root.hoveredChip !== null
          color: Qt.rgba(1, 1, 1, 0.75)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Idle and error states live on the glass itself, which is always
      // black — no theme paints under the video, so white text is safe.
      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(48)
        visible: !root.hasDevices || root.cameraError !== ""
        // The backend does not retry a failed open on its own, so the way
        // out of an error is a remount — tell the user which one they have.
        text: !root.hasDevices ? "No camera found"
          : root.cameraError + "\nReopen to retry."
        color: Qt.rgba(1, 1, 1, 0.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }
  }

  // -------------------------------------------------------------- pin window
  // The same glass, picture-in-picture. The compositor side (float, pin,
  // opacity, aspect lock) comes from the rule registered above; the
  // window side is plain QML: native interactive move from a drag
  // anywhere, native resize from the corner grip.
  FloatingWindow {
    id: pinWindow
    visible: root.pinned
    title: root.pinTitle
    color: "#0a0a0c"

    // Imperative on purpose, called by pin() before the visibility flip:
    // the initial configure ignores sizes set after the surface exists,
    // and a declarative binding can evaluate before root's properties
    // during widget creation and stick at an invalid size.
    function applySize() {
      implicitWidth = root.pinWidth
      implicitHeight = root.pinHeight
    }

    // Corner placement once per map — a rule cannot express "monitor edge
    // minus this window's size", so it is a dispatch. The focus sandwich
    // is load-bearing: every `window.*` dispatcher acts only on the
    // focused window (the selector merely filters), so the window is
    // focused for the move and focus handed straight back.
    onBackingWindowVisibleChanged: if (backingWindowVisible) pinPlace.start()
    Timer {
      id: pinPlace
      interval: 150
      onTriggered: {
        // The pin can be gone again before this fires — then the focus
        // sandwich would only yank the user's focus for nothing.
        if (!root.pinned || !pinWindow.screen) return
        var s = pinWindow.screen
        Hyprland.dispatch("hl.dsp.focus({ window = [[title:^" + root.pinTitle + "$]] })")
        Hyprland.dispatch("hl.dsp.window.move({ title = [[^" + root.pinTitle + "$]], x = "
          + (s.x + s.width - pinWindow.implicitWidth - 40) + ", y = "
          + (s.y + s.height - pinWindow.implicitHeight - 40) + " })")
        Hyprland.dispatch("hl.dsp.focus({ last = true })")
      }
    }

    // A user resize that settles becomes the new default pin size,
    // clamped with the same bounds the reader applies so the stored
    // setting always matches a size the pin can actually take.
    onWidthChanged: if (backingWindowVisible) pinSizeSave.restart()
    Timer {
      id: pinSizeSave
      interval: 1000
      onTriggered: {
        if (!root.pinned) return
        var w = Util.clamp(Math.round(pinWindow.width), root.pinMinWidth, root.pinMaxWidth)
        if (w !== root.pinWidth) root.persistSetting("pinWidth", w)
      }
    }

    Item {
      id: pinContent
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.pinned = false

      MirrorVideo {
        id: pinVideo
        showing: root.pinned
      }

      // Plain drag anywhere moves the window — PiP manners. target: null
      // so nothing moves client-side; the compositor drives the whole
      // interaction. Chip clicks still land: a press without movement
      // never activates the handler.
      DragHandler {
        target: null
        acceptedButtons: Qt.LeftButton
        onActiveChanged: if (active) pinContent.Window.window.startSystemMove()
      }

      HoverHandler { id: pinHover }

      MicMeterPlate {}

      // Resize grips in all four corners, since the window can sit in any
      // corner of the screen: invisible, the cursor change is the
      // affordance. The compositor keeps 16:9 (keep_aspect_ratio in the
      // rule).
      Repeater {
        model: [
          { edges: Qt.TopEdge | Qt.LeftEdge, cursor: Qt.SizeFDiagCursor },
          { edges: Qt.TopEdge | Qt.RightEdge, cursor: Qt.SizeBDiagCursor },
          { edges: Qt.BottomEdge | Qt.LeftEdge, cursor: Qt.SizeBDiagCursor },
          { edges: Qt.BottomEdge | Qt.RightEdge, cursor: Qt.SizeFDiagCursor }
        ]
        Item {
          required property var modelData
          anchors.left: modelData.edges & Qt.LeftEdge ? parent.left : undefined
          anchors.right: modelData.edges & Qt.RightEdge ? parent.right : undefined
          anchors.top: modelData.edges & Qt.TopEdge ? parent.top : undefined
          anchors.bottom: modelData.edges & Qt.BottomEdge ? parent.bottom : undefined
          width: Style.space(24)
          height: Style.space(24)
          HoverHandler { cursorShape: modelData.cursor }
          DragHandler {
            target: null
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) pinContent.Window.window.startSystemResize(modelData.edges)
          }
        }
      }

      // Dock the mirror back into the panel — the reverse of the pin chip,
      // wearing a restore glyph rather than a pin: this is "go back", not
      // "turn off" (Esc and the bar icon close outright). open() raises
      // opened, whose handler clears pinned — the same seamless sink
      // retarget as pinning, in reverse.
      ChipButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(8)
        glyph: "󰖲"
        opacity: pinHover.hovered ? 1 : 0
        enabled: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        onActivated: root.open()
      }
    }
  }

  // The live mirror image: one per surface, fed by the capture session
  // one at a time. `showing` keeps the inactive surface faded so a stale
  // last frame never lingers behind the active one.
  component MirrorVideo: VideoOutput {
    id: video

    required property bool showing

    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
    visible: root.cameraError === ""
    opacity: root.live && showing ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220 } }
    transform: Scale {
      origin.x: video.width / 2
      xScale: root.mirrored ? -1 : 1
    }

    // Framing guides, on the surface so they fade with the picture. Two
    // verticals then two horizontals, at a third and two thirds.
    Repeater {
      model: root.guides ? 4 : 0
      Rectangle {
        required property int index
        readonly property bool vertical: index < 2
        readonly property real at: (index % 2 + 1) / 3
        x: vertical ? Math.round(video.width * at) : 0
        y: vertical ? 0 : Math.round(video.height * at)
        width: vertical ? Style.spacing.hairline : video.width
        height: vertical ? video.height : Style.spacing.hairline
        color: Qt.rgba(1, 1, 1, 0.4)
      }
    }

    // Shutter flash on a saved snapshot. A child of the surface, it
    // inherits the surface's opacity, so only the showing mirror blinks.
    Rectangle {
      anchors.fill: parent
      color: "white"
      opacity: 0
      NumberAnimation on opacity { id: shutter; running: false; from: 0.6; to: 0; duration: 350 }
      Connections { target: root; function onSnapshotSaved(path) { shutter.restart() } }
    }
  }

  // The mic meter on its dark plate, shared by the panel glass and the
  // pinned window; the level math and peak-hold live at root (the meter
  // reads one mic, not one surface), so the hold survives the handoff
  // and updates run once. The plate separates the meter from any scene:
  // it carries the cells over bright video, the light unlit ticks over
  // dark.
  component MicMeterPlate: Rectangle {
    visible: root.micCheck
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(12)
    anchors.bottomMargin: Style.space(10)
    width: meterRow.width + Style.space(16)
    height: Style.space(30)
    radius: Style.cornerRadius
    color: Qt.rgba(0, 0, 0, 0.45)
    opacity: root.micMuted ? 0.45 : 1

    // Hovering the meter names the metered mic: it follows the default
    // source, and "wrong mic" (a forgotten headset) should be
    // diagnosable in one glance.
    HoverHandler { id: meterHover }

    Row {
      id: meterRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.micMuted ? "󰍭" : "󰍬"
        color: Qt.rgba(1, 1, 1, 0.75)
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Repeater {
          model: root.meterCells

          Rectangle {
            required property int index
            readonly property bool lit: index < root.meterLitCells
            readonly property color onColor: index === root.meterCells - 1
              ? Color.urgent : Color.accent

            width: Style.space(8)
            height: Style.space(7)
            // Light ticks on the dark plate, theme colors for the lit
            // cells — the scale stays readable over any scene. No color
            // Behavior on purpose: a meter should be instant, and an
            // animating cell inside the panel's layered glass would keep
            // the whole layer repainting.
            color: lit ? onColor
              : index === root.meterHeldCell ? Util.alpha(onColor, 0.45)
              : Qt.rgba(1, 1, 1, 0.12)
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: meterHover.hovered
        text: root.micSource
          ? String(root.micSource.nickname || root.micSource.description || root.micSource.name)
          : "no mic"
        color: Qt.rgba(1, 1, 1, 0.75)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Icon chip for the hover chrome. The kit buttons derive their state
  // fills from theme alphas tuned for themed panel surfaces; over moving
  // video those fills are too faint to read, so the chips own their
  // fixed-contrast states.
  component ChipButton: Rectangle {
    id: chip

    property string glyph: ""
    property string hint: ""
    property bool on: false

    signal activated()

    width: Style.space(34)
    height: width
    radius: Style.cornerRadius
    color: chipArea.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.45)
    border.width: chip.on ? Style.spacing.hairline : 0
    border.color: Util.alpha(Color.accent, 0.9)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: chip.glyph
      color: "#ffffff"
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: chipArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
      // Guarded clear: chip A's exit may arrive after chip B's enter, and
      // must not blank the caption B just claimed.
      onContainsMouseChanged: {
        if (containsMouse) root.hoveredChip = chip
        else if (root.hoveredChip === chip) root.hoveredChip = null
      }
    }
  }
}
