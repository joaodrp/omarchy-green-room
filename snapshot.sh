#!/bin/bash
# Finish a snapshot the way Omarchy finishes a screenshot: the picture the
# glass showed, copied to the clipboard, and a notification that opens the
# screenshot editor on it. Panel.qml runs it; .github/test-snapshot.mjs tests it.
#
#   snapshot.sh <png> [mirror]

shot=$1
flop=()
[[ ${2-} == mirror ]] && flop=(-flop)

# Flipped when the mirror is on, center-cropped to 16:9: the fx picks
# whichever side the sensor's aspect leaves too long.
magick "$shot" "${flop[@]}" -gravity center \
  -extent '%[fx:w*9>h*16?h*16/9:w]x%[fx:w*9>h*16?h:w*9/16]' "$shot"
wl-copy --type image/png <"$shot"

# The user's editor while it is installed: an upgrade that replaces the
# editor leaves the variable naming the old one.
editor=${OMARCHY_SCREENSHOT_EDITOR-}
if ! command -v "$editor" >/dev/null 2>&1; then
  if command -v omasnap >/dev/null; then editor=omasnap; else editor=tensaku-edit; fi
fi

headline="Snapshot saved to clipboard and file"
send=$(command -v omarchy-notification-send) || exit 1

# Omarchy announces screenshots with Open and Edit buttons once
# omarchy-notification-send takes --action; before that, a click edits and
# Super + Alt + , clicks the newest card. Its usage line says which.
if grep -q '^# omarchy:args=.*--action' "$send"; then
  exec "$send" "$headline" --image "$shot" \
    --action Open xdg-open --action Edit "$editor" --with "$shot"
fi
exec "$send" "$headline" "Edit with Super + Alt + , (or click this)" --image "$shot" \
  --exec "$editor" "$shot"
