//@ pragma OmarchyLoadPatch
// A Quickshell instance that hosts only the Green Room panel, under a
// stand-in bar icon, so testing never reloads or restarts the user's shell.
// Run it through host.sh, which links the shell's Commons and Ui next to
// this file and passes the GR_* variables below.
//
// The pragma is the shell's own: without it `Color` resolves to Qt's type
// and every theme color is undefined.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

ShellRoot {
  PanelWindow {
    id: barWin
    anchors { top: true; left: true; right: true }
    implicitHeight: Style.bar.sizeHorizontal
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "green-room-test-host"
    // Only the stand-in icon takes input; the real bar under the strip
    // keeps working.
    mask: Region { item: host }

    // The slice of the shell's bar object the panel and the Ui kit read.
    QtObject {
      id: fakeBar
      property string position: "top"
      property bool vertical: false
      property string fontFamily: Style.font.family
      property color urgent: Color.urgent
      property bool foregroundAnimationEnabled: true
      property color barForeground: Color.foreground
      property real barSize: barWin.height
      property string activePopout: ""
      property var clickTargets: []
      function requestPopout(k) { activePopout = k }
      function releasePopout(k) { if (activePopout === k) activePopout = "" }
      // Settings live for the session only; the log shows each write.
      property var shell: ({
        updateEntryInline: function(name, entry) { console.warn("test-host setting", JSON.stringify(entry)) }
      })
    }

    Rectangle {
      anchors.fill: host
      color: Qt.rgba(0, 0, 0, 0.85)
    }

    Loader {
      id: host
      x: Number(Quickshell.env("GR_X") || 900)
      width: Style.bar.iconSlot
      height: barWin.height
      // Outside this config folder, as the shell loads plugins: inside it,
      // the qs.* imports resolve differently.
      Component.onCompleted: setSource("file://" + Quickshell.env("GR_PLUGIN") + "/Panel.qml", {
        settings: JSON.parse(Quickshell.env("GR_SETTINGS") || "{}"),
        bar: fakeBar
      })
    }
  }
}
