#!/bin/bash
# Run the Green Room panel in its own Quickshell instance; see CONTRIBUTING.md.
#
#   host.sh start ['{"micCheck":true}']   (re)start; settings merge over the manifest defaults
#   host.sh ipc open|close|toggle         call the panel
#   host.sh log                           the instance's log
#   host.sh stop
#
# GR_PLUGIN  plugin folder to load (default: this checkout)
# GR_X       x of the stand-in bar icon, in logical px (default: 900)
set -euo pipefail

src=$(dirname "$(readlink -f "$0")")
repo=$(readlink -f "$src/../..")
run="${XDG_RUNTIME_DIR:-/tmp}/green-room-test-host"
plugin=$(readlink -f "${GR_PLUGIN:-$repo}")

# Matched on the whole command line: a pattern match would also hit the
# shell running this script.
running() { pgrep -x -f "qs -p $run" >/dev/null; }
stop() { pkill -x -f "qs -p $run" || true; while running; do sleep 0.2; done; }

case "${1:-}" in
  start)
    stop
    mkdir -p "$run"
    cp "$src/shell.qml" "$run/"
    ln -sfn "$OMARCHY_PATH/shell/Commons" "$run/Commons"
    ln -sfn "$OMARCHY_PATH/shell/Ui" "$run/Ui"
    settings=$(jq -c --argjson s "${2:-{\}}" '.barWidget.defaults + $s' "$plugin/manifest.json")
    GR_PLUGIN="$plugin" GR_SETTINGS="$settings" GR_X="${GR_X:-900}" \
      setsid qs -p "$run" >"$run/log.txt" 2>&1 </dev/null &
    for _ in $(seq 50); do grep -q 'Configuration Loaded' "$run/log.txt" 2>/dev/null && break; sleep 0.1; done
    grep -q 'Configuration Loaded' "$run/log.txt" || { cat "$run/log.txt"; exit 1; }
    ;;
  ipc) qs -p "$run" ipc call io.github.joaodrp.green-room "${2:?open, close or toggle}" ;;
  log) cat "$run/log.txt" ;;
  stop) stop ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
