// Camera resolution: which connected camera a saved choice means.
// Run: node --test .github/test-devices.mjs
import { test } from "node:test"
import assert from "node:assert/strict"
import { resolveDevice, serialPath } from "../devices.mjs"

const cam = (id, serial, name) => ({ id, serial, name })
const A = (id) => cam(id, "SERIAL-A", "Camera A")
const B = (id) => cam(id, "SERIAL-B", "Camera B")

test("auto, or nothing saved, is the system default", () => {
  assert.equal(resolveDevice([A("/dev/video0")], { id: "auto", serial: "SERIAL-A" }), -1)
  assert.equal(resolveDevice([A("/dev/video0")], {}), -1)
  assert.equal(resolveDevice([A("/dev/video0")], null), -1)
})

test("the saved camera at its saved id", () => {
  const devices = [A("/dev/video0"), B("/dev/video2")]
  assert.equal(resolveDevice(devices, { id: "/dev/video2", serial: "SERIAL-B", name: "Camera B" }), 1)
})

test("renumbered: the saved camera at a new id, another camera at its old id", () => {
  const devices = [B("/dev/video0"), A("/dev/video2")]
  assert.equal(resolveDevice(devices, { id: "/dev/video2", serial: "SERIAL-B", name: "Camera B" }), 0)
})

test("not connected: the default, even with another camera at the saved id", () => {
  const devices = [A("/dev/video2")]
  assert.equal(resolveDevice(devices, { id: "/dev/video2", serial: "SERIAL-B", name: "Camera B" }), -1)
  assert.equal(resolveDevice([], { id: "/dev/video2", serial: "SERIAL-B", name: "Camera B" }), -1)
})

test("same model, two units: the serial tells them apart", () => {
  const devices = [cam("/dev/video0", "UNIT-2", "Model"), cam("/dev/video2", "UNIT-1", "Model")]
  assert.equal(resolveDevice(devices, { id: "/dev/video0", serial: "UNIT-1", name: "Model" }), 1)
})

test("one camera, two inputs sharing its serial: the name tells them apart", () => {
  const devices = [cam("/dev/video0", "S", "Camera IR"), cam("/dev/video2", "S", "Camera RGB")]
  assert.equal(resolveDevice(devices, { id: "/dev/video0", serial: "S", name: "Camera RGB" }), 1)
})

test("same model, saved unit gone: never falls back to its twin", () => {
  const devices = [cam("/dev/video0", "UNIT-2", "Model")]
  assert.equal(resolveDevice(devices, { id: "/dev/video0", serial: "UNIT-1", name: "Model" }), -1)
})

test("no serial: the name finds a renumbered camera", () => {
  const devices = [cam("/dev/video0", "", "Camera B"), cam("/dev/video2", "", "Camera A")]
  assert.equal(resolveDevice(devices, { id: "/dev/video2", serial: "", name: "Camera B" }), 0)
})

test("no serial, two units of one name: the one at the saved id, else the first", () => {
  const devices = [cam("/dev/video0", "", "Model"), cam("/dev/video2", "", "Model")]
  assert.equal(resolveDevice(devices, { id: "/dev/video2", serial: "", name: "Model" }), 1)
  assert.equal(resolveDevice(devices, { id: "/dev/video4", serial: "", name: "Model" }), 0)
})

test("a choice saved before names were: matched by id alone", () => {
  const devices = [A("/dev/video0"), B("/dev/video2")]
  assert.equal(resolveDevice(devices, { id: "/dev/video2" }), 1)
  assert.equal(resolveDevice(devices, { id: "/dev/video4" }), -1)
})

test("serial path: only for /dev/videoN ids", () => {
  assert.equal(serialPath("/dev/video2"), "/sys/class/video4linux/video2/device/../serial")
  assert.equal(serialPath("/dev/video10"), "/sys/class/video4linux/video10/device/../serial")
  assert.equal(serialPath("auto"), "")
  assert.equal(serialPath("/dev/video2/../sda"), "")
  assert.equal(serialPath(""), "")
})
