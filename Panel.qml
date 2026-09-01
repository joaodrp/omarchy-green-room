import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Green Room: click the bar icon, see yourself. The panel is nothing but
// the glass — a live 16:9 mirror. Idle it reads as dark glass with a
// specular glare; live video fades in like the mirror catching light.
// Controls appear only on hover.
//
// The whole capture stack (Camera + CaptureSession + VideoOutput) mounts and
// is destroyed together with the popup, via the Loader inside the glass:
// on Qt's FFmpeg camera backend `Camera.active = false` leaves /dev/videoN
// open and streaming, and only destroying the Camera object releases the
// sensor.
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
  // that exists only while the panel is open with the check on — the mic,
  // like the camera, is held only while you look.
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
    enabled: root.opened
  }

  // A peak monitor is deliberately invisible to WirePlumber's headset
  // autoswitch, so a Bluetooth headset left in A2DP keeps its mic off and
  // the meter reads a mic no call would use. Hold a real capture while
  // the check runs — what a call does: the headset flips to its
  // mic-capable profile and the meter shows what the far side would
  // hear. Released with the panel, like the camera. (Bluetooth audio
  // quality drops to call-grade while held; that is the honest preview.)
  Process {
    command: ["pw-record", "/dev/null"]
    running: root.opened && root.micCheck && !!root.micSource
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
    running: root.opened && root.micCheck && !!root.micSource
    onTriggered: if (micPeak.peak <= 0) root.micRebind = true
  }

  // ---------------------------------------------------------------- sizing
  // 16:9, the framing call participants actually see.
  readonly property int mirrorWidth: Util.clamp(root.setting("previewWidth", 560), 320, 960)
  readonly property int mirrorHeight: Math.round(root.mirrorWidth * 9 / 16)

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

  // ------------------------------------------------------------------- bar
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰴂"
    active: root.opened && root.cameraError === ""
    tooltipText: "Green Room"
    onPressed: function(button) { if (button === Qt.LeftButton) root.toggle() }
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

        Loader {
          anchors.fill: parent
          active: root.opened && root.hasDevices && !root.deviceRestart
          onActiveChanged: {
            if (!active) {
              root.live = false
              root.cameraError = ""
            }
          }
          sourceComponent: VideoOutput {
            id: videoOutput
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: root.cameraError === ""
            opacity: root.live ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            transform: Scale {
              origin.x: videoOutput.width / 2
              xScale: root.mirrored ? -1 : 1
            }

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
            CaptureSession { camera: camera; videoOutput: videoOutput }
            Connections {
              target: videoOutput.videoSink
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
      // On the chips' dark plate so it separates from any scene: the plate
      // carries it over bright video, the light unlit ticks over dark.
      Rectangle {
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

        // Ten cells across -60..0 dBFS — 6 dB each, so syllable-scale
        // dynamics (~6-8 dB) visibly move the meter while you talk: nine
        // accent cells up to -6, then an urgent cell for the caution zone.
        // The brightest recently hit cell
        // keeps glowing dimly for a second after the level falls below it,
        // so glanced-past peaks still register. No transition animations: a
        // meter should be instant, and an animating cell inside the layered
        // glass would keep the whole layer repainting.
        //
        // PwNodePeakMonitor.peak is the cube root of linear amplitude (the
        // PulseAudio perceptual volume curve) — measured: a -36 dBFS room
        // read as peak 0.2505 = 0.01572^(1/3). So true dBFS is
        // 60*log10(peak), and -60..0 maps to 0..1 as 1 + log10(peak).
        Row {
          id: micMeter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          readonly property int cells: 10
          // The caution cell starts at -6 dBFS = 0.9 on the 0..1 scale;
          // the accent cells split the range below it evenly.
          readonly property real cautionLevel: 0.9
          readonly property real cellSpan: cautionLevel / (cells - 1)
          readonly property real level: micPeak.peak > 0
            ? Util.clamp(1 + Math.log10(micPeak.peak), 0, 1) : 0
          // Quantized once, so per-cell bindings re-evaluate only when the
          // picture changes, not on every peak update (~50-100/s).
          readonly property int litCells: level > cautionLevel
            ? cells : Math.ceil(level / cellSpan)
          property int heldCell: -1
          onLitCellsChanged: {
            // While the level covers the held cell the hold is invisible and
            // needs no decay; the decay runs from the moment the level first
            // drops below — started, not restarted, so fluctuation further
            // down cannot extend a stale hold past its second.
            if (litCells - 1 >= heldCell) { heldCell = litCells - 1; holdDecay.stop() }
            else if (!holdDecay.running) holdDecay.start()
          }

          Timer {
            id: holdDecay
            interval: 1000
            onTriggered: micMeter.heldCell = micMeter.litCells - 1
          }

          Repeater {
            model: micMeter.cells

            Rectangle {
              required property int index
              readonly property bool lit: index < micMeter.litCells
              readonly property color onColor: index === micMeter.cells - 1
                ? Color.urgent : Color.accent

              width: Style.space(8)
              height: Style.space(7)
              // Light ticks on the dark plate, theme colors for the lit
              // cells — the scale stays readable over any scene.
              color: lit ? onColor
                : index === micMeter.heldCell ? Util.alpha(onColor, 0.45)
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
