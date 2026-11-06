// The snapshot's directory, and its notification: which editor it opens,
// and in which form it hands that to omarchy-notification-send.
// Run: node --test .github/test-snapshot.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, symlinkSync, chmodSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const script = resolve(import.meta.dirname, "../snapshot.sh")
const OLD_ARGS = "# omarchy:args=[--image <path-or-uri>] <headline> [description] [--exec <program> [args...]]"
const NEW_ARGS = "# omarchy:args=[--image <path-or-uri>] <headline> [description] [--exec <program> [args...] | --action <label> <program> [words...]... [--with <args...>]]"

// A PATH holding only stubs, so the machine's own tools never leak in.
function sandbox(programs) {
  const bin = mkdtempSync(join(tmpdir(), "gr-snapshot-"))
  const stub = (name, body) => {
    writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`)
    chmodSync(join(bin, name), 0o755)
  }
  for (const tool of ["grep", "cat", "mkdir"]) {
    const real = ["/usr/bin", "/bin"].map((d) => join(d, tool)).find(existsSync)
    symlinkSync(real, join(bin, tool))
  }
  for (const name of programs) stub(name, "")
  return { bin, stub }
}

// The notification stub records its argv, one word per line.
function run({ args = OLD_ARGS, programs = [], env = {} } = {}) {
  const { bin, stub } = sandbox(programs)
  const out = join(bin, "argv")
  stub("magick", "")
  stub("wl-copy", "cat >/dev/null")
  stub("omarchy-notification-send", `${args}\nprintf '%s\\n' "$@" >"${out}"`)
  const shot = join(bin, "green-room-2026-11-05_10-00-00.png")
  writeFileSync(shot, "")
  execFileSync("/bin/bash", [script, "finish", shot], { env: { PATH: bin, HOME: bin, ...env } })
  return { shot, argv: readFileSync(out, "utf8").trimEnd().split("\n") }
}

test("Omarchy 4.0: Tensaku, as separate words after a trailing --exec", () => {
  const { shot, argv } = run({ programs: ["tensaku-edit"] })
  assert.deepEqual(argv.slice(-3), ["--exec", "tensaku-edit", shot])
  assert.ok(argv.includes("Edit with Super + Alt + , (or click this)"))
})

test("Omarchy 4.5: Open and Edit buttons, Edit in Omasnap", () => {
  const { shot, argv } = run({ args: NEW_ARGS, programs: ["omasnap"] })
  assert.deepEqual(argv.slice(argv.indexOf("--action")),
    ["--action", "Open", "xdg-open", "--action", "Edit", "omasnap", "--with", shot])
  assert.ok(!argv.includes("--exec"))
  assert.ok(!argv.some((a) => a.includes("Super")), "no keybind hint: 4.5 moved them")
})

test("OMARCHY_SCREENSHOT_EDITOR wins while it is installed", () => {
  const env = { OMARCHY_SCREENSHOT_EDITOR: "satty" }
  assert.deepEqual(run({ programs: ["satty", "tensaku-edit"], env }).argv.slice(-2, -1), ["satty"])
  const { argv } = run({ args: NEW_ARGS, programs: ["satty", "omasnap"], env })
  assert.equal(argv[argv.indexOf("Edit") + 1], "satty")
})

test("an OMARCHY_SCREENSHOT_EDITOR the upgrade removed falls back", () => {
  const env = { OMARCHY_SCREENSHOT_EDITOR: "tensaku-edit" }
  const { argv } = run({ args: NEW_ARGS, programs: ["omasnap"], env })
  assert.equal(argv[argv.indexOf("Edit") + 1], "omasnap")
})

test("Omasnap edits on 4.0 too, once installed", () => {
  assert.deepEqual(run({ programs: ["omasnap", "tensaku-edit"] }).argv.slice(-2, -1), ["omasnap"])
})

// HOME is the sandbox, shown as `~`; `conf` is omasnap.conf, `pictures` the
// XDG pictures dir.
function dir({ omasnap = false, env = {}, conf, pictures } = {}) {
  const { bin, stub } = sandbox([])
  stub("omarchy-capture-screenshot", omasnap ? "exec omasnap --notify" : "grim")
  if (conf !== undefined) {
    mkdirSync(join(bin, ".config/omasnap"), { recursive: true })
    writeFileSync(join(bin, ".config/omasnap/omasnap.conf"), conf)
  }
  if (pictures) {
    mkdirSync(join(bin, ".config"), { recursive: true })
    writeFileSync(join(bin, ".config/user-dirs.dirs"), `XDG_PICTURES_DIR="$HOME/${pictures}"\n`)
  }
  const out = execFileSync("/bin/bash", [script, "dir"], { env: { PATH: bin, HOME: bin, ...env } })
  const d = out.toString().trim()
  assert.ok(existsSync(d), `${d} is created`)
  return d.startsWith(bin + "/") ? "~" + d.slice(bin.length) : d
}

test("Omarchy 4.0 directory: OMARCHY_SCREENSHOT_DIR, else the pictures dir", () => {
  assert.equal(dir(), "~/Pictures")
  assert.equal(dir({ pictures: "Fotos" }), "~/Fotos")
  const shots = mkdtempSync(join(tmpdir(), "gr-shots-"))
  assert.equal(dir({ env: { OMARCHY_SCREENSHOT_DIR: shots } }), shots)
})

test("Omarchy 4.5 directory: Omasnap's, under the pictures dir by default", () => {
  assert.equal(dir({ omasnap: true }), "~/Pictures/Screenshots")
  assert.equal(dir({ omasnap: true, pictures: "Fotos" }), "~/Fotos/Screenshots")
})

test("Omarchy 4.5 directory: omasnap.conf, under both environment overrides", () => {
  const conf = "[editor]\ndirectory = ~/Wrong\n[output]\nautosave = true\n directory = ~/Pictures/Captures \n"
  assert.equal(dir({ omasnap: true, conf }), "~/Pictures/Captures")
  const shots = mkdtempSync(join(tmpdir(), "gr-shots-"))
  assert.equal(dir({ omasnap: true, conf, env: { OMARCHY_SCREENSHOT_DIR: shots } }), shots)
  assert.equal(dir({ omasnap: true, conf, env: { OMARCHY_SCREENSHOT_DIR: "/nowhere", OMASNAP_SCREENSHOT_DIR: shots } }), shots)
})

test("omasnap.conf values read as Omasnap's QSettings reads them", () => {
  const read = (value) => dir({ omasnap: true, conf: `[output]\ndirectory = ${value}\n` })
  assert.equal(read('"~/Pictures/My Captures"'), "~/Pictures/My Captures")
  assert.equal(read("~/Pictures/Captures ; a comment"), "~/Pictures/Captures")
  assert.equal(read('"~/Pictures/a, b ; c"'), "~/Pictures/a, b ; c")
  assert.equal(read('"~/Pictures/\\"q\\""'), '~/Pictures/"q"')
  assert.equal(read("~/Pictures/a, b"), "~/Pictures/Screenshots", "a list is no value")
})
