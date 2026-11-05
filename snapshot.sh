#!/bin/bash
# A snapshot goes where Omarchy's screenshots go and is announced the way
# they are. Panel.qml runs it; .github/test-snapshot.mjs tests it.
#
#   snapshot.sh dir                    create and print the screenshot directory
#   snapshot.sh finish <png> [mirror]  crop, copy and announce a saved snapshot

# Omarchy 4.5 hands screenshots to Omasnap; earlier versions save them itself.
omasnap_screenshots() {
  local capture
  capture=$(command -v omarchy-capture-screenshot) && grep -q omasnap "$capture"
}

# [output] directory from omasnap.conf, with `~` expanded as Omasnap does.
omasnap_conf_dir() {
  local conf=${XDG_CONFIG_HOME:-$HOME/.config}/omasnap/omasnap.conf line section="" key value found=""
  [[ -r $conf ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^[[:space:]]*\[(.*)\][[:space:]]*$ ]]; then
      section=${BASH_REMATCH[1]}
    elif [[ $section == output && $line == *=* ]]; then
      key=${line%%=*} value=${line#*=}
      key=${key//[[:space:]]/}
      value=${value#"${value%%[![:space:]]*}"} value=${value%"${value##*[![:space:]]}"}
      [[ $key == directory ]] || continue
      [[ $value == "~" ]] && value=$HOME
      # shellcheck disable=SC2088 # the config's literal tilde
      [[ $value == "~/"* ]] && value=$HOME/${value#"~/"}
      found=$value
    fi
  done <"$conf"
  printf '%s' "$found"
}

dir() {
  local d
  # shellcheck source=/dev/null
  [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
  if omasnap_screenshots; then
    d=${OMASNAP_SCREENSHOT_DIR:-${OMARCHY_SCREENSHOT_DIR:-}}
    [[ -n $d ]] || d=$(omasnap_conf_dir)
    [[ -n $d ]] || d=${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots
  else
    d=${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}
  fi
  mkdir -p "$d" && printf '%s\n' "$d"
}

finish() {
  local shot=$1 flop=() editor send
  [[ ${2-} == mirror ]] && flop=(-flop)
  local headline="Snapshot saved to clipboard and file"

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

  send=$(command -v omarchy-notification-send) || return 1

  # Omarchy announces screenshots with Open and Edit buttons once
  # omarchy-notification-send takes --action; before that, a click edits and
  # Super + Alt + , clicks the newest card. Its usage line says which.
  if grep -q '^# omarchy:args=.*--action' "$send"; then
    exec "$send" "$headline" --image "$shot" \
      --action Open xdg-open --action Edit "$editor" --with "$shot"
  fi
  exec "$send" "$headline" "Edit with Super + Alt + , (or click this)" --image "$shot" \
    --exec "$editor" "$shot"
}

case ${1-} in
  dir) dir ;;
  finish) shift; finish "$@" ;;
  *) sed -n '5,6p' "$0" >&2; exit 2 ;;
esac
