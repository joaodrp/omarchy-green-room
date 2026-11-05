// The snapshot's notification: which editor it opens, and in which form it
// hands that to omarchy-notification-send.
// Run: node --test .github/test-snapshot.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { mkdtempSync, writeFileSync, readFileSync, symlinkSync, chmodSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const script = resolve(import.meta.dirname, "../snapshot.sh")
const OLD_ARGS = "# omarchy:args=[--image <path-or-uri>] <headline> [description] [--exec <program> [args...]]"
const NEW_ARGS = "# omarchy:args=[--image <path-or-uri>] <headline> [description] [--exec <program> [args...] | --action <label> <program> [words...]... [--with <args...>]]"

// A PATH holding only stubs, so the machine's own editors never leak in.
// The notification stub records its argv, one word per line.
function run({ args = OLD_ARGS, programs = [], env = {} } = {}) {
  const bin = mkdtempSync(join(tmpdir(), "gr-snapshot-"))
  const out = join(bin, "argv")
  const stub = (name, body) => {
    writeFileSync(join(bin, name), `#!/bin/bash\n${body}\n`)
    chmodSync(join(bin, name), 0o755)
  }
  for (const tool of ["grep", "cat"]) {
    const real = ["/usr/bin", "/bin"].map((d) => join(d, tool)).find(existsSync)
    symlinkSync(real, join(bin, tool))
  }
  stub("magick", "")
  stub("wl-copy", "cat >/dev/null")
  stub("omarchy-notification-send", `${args}\nprintf '%s\\n' "$@" >"${out}"`)
  for (const name of programs) stub(name, "")
  const shot = join(bin, "green-room-2026-11-05_10-00-00.png")
  writeFileSync(shot, "")
  execFileSync("/bin/bash", [script, shot], { env: { PATH: bin, HOME: bin, ...env } })
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
