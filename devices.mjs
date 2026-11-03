// Which connected camera a saved choice means. Pure, so the same code runs in
// the panel and under `node --test`.
//
// A device is { id, serial, name }: id is the Qt device id (the /dev/videoN
// path on the FFmpeg backend, renumbered by probe order), serial is the USB
// serial from sysfs ("" when the camera has none), name is Qt's description.
// The saved choice has the same three fields; id "auto" means the system
// default.
//
// Returns the index into `devices`, or -1 for the system default.
export function resolveDevice(devices, saved) {
  const id = saved && saved.id ? String(saved.id) : "auto"
  if (id === "auto") return -1
  const serial = saved.serial ? String(saved.serial) : ""
  const name = saved.name ? String(saved.name) : ""

  // The serial identifies the camera itself, wherever it was numbered; one
  // camera can expose several inputs under it (an IR sensor beside the
  // RGB one), which the name tells apart. A saved camera with a serial
  // that is not connected is absent: falling through to the name could
  // pick another unit of the same model.
  if (serial !== "") return pick(devices, d => d.serial === serial, name, id)

  // No serial: the name, which cannot tell two units of one model apart.
  if (name !== "") return pick(devices, d => d.name === name, name, id)

  // A choice saved before names were: the id is all there is.
  return devices.findIndex(d => d.id === id)
}

// The one match; among several, the one with the saved name, then the one
// still at the saved id, then the first: a stable answer when inputs
// share a serial or a name.
function pick(devices, matches, name, id) {
  const found = []
  devices.forEach((d, i) => { if (matches(d)) found.push(i) })
  if (found.length === 0) return -1
  const named = found.filter(i => devices[i].name === name)
  const pool = named.length > 0 ? named : found
  const atId = pool.find(i => devices[i].id === id)
  return atId !== undefined ? atId : pool[0]
}

// The sysfs file holding the USB serial for a /dev/videoN id, or "" for an
// id that is not a V4L2 node (another backend, or no serial to read).
export function serialPath(id) {
  const m = /^\/dev\/(video\d+)$/.exec(String(id))
  return m ? "/sys/class/video4linux/" + m[1] + "/device/../serial" : ""
}
