// Animated README hero: docs/images/hero-light.gif and hero-dark.gif.
//
// The story runs on the same model as the static figure (CAL, BOUNDARY, HYST,
// DWELL in build.mjs):
//   1. The head faces the MacBook (-4°); the MacBook holds focus.
//   2. A quick glance past the band and back: the dwell gauge starts to fill,
//      empties again, and nothing switches.
//   3. The head turns to +27° (0.8 s, ease-in-out). It crosses the band, the
//      dwell fills over DWELL seconds, and only then focus moves to the LG.
//   4. Hold, turn back, the dwell fills again, and the MacBook relights.
//
// Each frame is rendered by build.mjs's heroSvg(), rasterised in headless
// Chrome over the DevTools protocol (no npm packages), and encoded with ffmpeg.
//
//   node docs/figure/animate.mjs [--fps 20] [--keep]
//
// Needs Node 22+ (global WebSocket), Chrome or Chromium (CHROME_PATH to
// override), and ffmpeg on PATH (FFMPEG to override).

import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync, copyFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { heroSvg, CAL, BOUNDARY, HYST, DWELL, YAW } from "./build.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "images");
const arg = (name, fallback) => {
  const at = process.argv.indexOf(name);
  return at > 0 ? process.argv[at + 1] : fallback;
};
const FPS = Number(arg("--fps", 20));
const KEEP = process.argv.includes("--keep");
const WIDTH = 880;
const HEIGHT = 540;
const RENDER_SCALE = 2; // rasterise at 1760 px wide, then downscale for clean edges

// ---------------------------------------------------------------- the story
const GLANCE = BOUNDARY + HYST + 3; // just past the band, held too briefly to switch
// [time s, yaw °]; the head eases in and out between consecutive keys.
const KEYS = [
  [0, CAL.mac],
  [1.0, CAL.mac],
  [1.45, GLANCE],
  [1.5, GLANCE],
  [1.95, CAL.mac],
  [2.8, CAL.mac],
  [3.6, YAW],
  [5.4, YAW],
  [6.2, CAL.mac],
  [7.6, CAL.mac],
];
const LENGTH = KEYS[KEYS.length - 1][0];
const SHOW_FULL = 0.4; // seconds the full gauge stays up after a switch

const ease = (t) => 0.5 - 0.5 * Math.cos(Math.PI * t);
function yawAt(t) {
  for (let i = 1; i < KEYS.length; i++) {
    const [t0, y0] = KEYS[i - 1];
    const [t1, y1] = KEYS[i];
    if (t <= t1) return y0 + (y1 - y0) * ease(t1 > t0 ? (t - t0) / (t1 - t0) : 1);
  }
  return KEYS[KEYS.length - 1][1];
}

// Glazer's rule: the other display becomes the candidate once the yaw is past
// the band on its side (boundary ± hysteresis); the candidate must hold for
// DWELL seconds before focus moves. Any return resets the dwell.
function story() {
  const frames = [];
  const dt = 1 / FPS;
  let focus = "mac";
  let dwell = 0;
  let full = 0;
  const count = Math.round(LENGTH * FPS);
  for (let i = 0; i < count; i++) {
    const t = i * dt;
    const yaw = yawAt(t);
    if (i > 0) {
      const candidate = focus === "mac" ? (yaw > BOUNDARY + HYST ? "lg" : "mac") : yaw < BOUNDARY - HYST ? "mac" : "lg";
      if (candidate !== focus) {
        dwell = Math.min(1, dwell + dt / DWELL);
        if (dwell >= 1 - 1e-9) {
          focus = candidate;
          dwell = 1;
          full = SHOW_FULL;
        }
      } else if (full > 0) {
        full -= dt;
        dwell = 1;
      } else dwell = 0;
    }
    const shown = Math.round(yaw);
    const sign = shown > 0 ? "+" : shown < 0 ? "−" : "";
    const readout = `yaw ${sign}${Math.abs(shown)}° → ${focus === "lg" ? "LG" : "Built-in"}`;
    frames.push({ t, yaw, dwell, focus, readout });
  }
  return frames;
}

// ---------------------------------------------------------------- Chrome
function chromePath() {
  const list = [
    process.env.CHROME_PATH,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
  ];
  return list.find((path) => path && existsSync(path));
}

async function openChrome() {
  const binary = chromePath();
  if (!binary) throw new Error("No Chrome found. Set CHROME_PATH.");
  const profile = mkdtempSync(join(tmpdir(), "glazer-hero-"));
  const chrome = spawn(binary, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`, "--no-first-run", "--no-default-browser-check", "--hide-scrollbars", ...(process.platform === "linux" ? ["--no-sandbox"] : []), "about:blank"]);
  const port = await new Promise((done, fail) => {
    let text = "";
    const timer = setTimeout(() => fail(new Error("Chrome did not start")), 20000);
    chrome.stderr.on("data", (chunk) => {
      text += chunk;
      const match = text.match(/DevTools listening on ws:\/\/[^:]+:(\d+)\//);
      if (match) {
        clearTimeout(timer);
        done(Number(match[1]));
      }
    });
    chrome.on("exit", (code) => fail(new Error(`Chrome exited: ${code}`)));
  });
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })).json();
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((done) => (socket.onopen = done));
  let id = 0;
  const pending = new Map();
  socket.onmessage = (message) => {
    const data = JSON.parse(message.data);
    if (data.id && pending.has(data.id)) {
      pending.get(data.id)(data);
      pending.delete(data.id);
    }
  };
  const send = (method, params = {}) =>
    new Promise((done, fail) => {
      const call = ++id;
      pending.set(call, (data) => (data.error ? fail(new Error(`${method}: ${data.error.message}`)) : done(data.result)));
      socket.send(JSON.stringify({ id: call, method, params }));
    });
  const close = () => {
    socket.close();
    chrome.kill("SIGKILL");
    rmSync(profile, { recursive: true, force: true });
  };
  return { send, close };
}

// ---------------------------------------------------------------- main
const ffmpeg = process.env.FFMPEG || "ffmpeg";
if (spawnSync(ffmpeg, ["-version"]).status !== 0) {
  console.error("ffmpeg not found. Install it or set FFMPEG.");
  process.exit(1);
}

const frames = story();
const work = mkdtempSync(join(tmpdir(), "glazer-gif-"));
const { send, close } = await openChrome();
try {
  await send("Emulation.setDeviceMetricsOverride", { width: WIDTH, height: HEIGHT, deviceScaleFactor: RENDER_SCALE, mobile: false });
  await send("Runtime.evaluate", { expression: `document.documentElement.style.margin=document.body.style.margin="0";document.body.innerHTML='<div id="f" style="width:${WIDTH}px;height:${HEIGHT}px"></div>'` });
  for (const theme of ["light", "dark"]) {
    const dir = join(work, theme);
    mkdirSync(dir, { recursive: true });
    const seen = new Map(); // identical states (the holds) are rasterised once
    for (const [index, frame] of frames.entries()) {
      const file = join(dir, `f${String(index).padStart(4, "0")}.png`);
      const state = { yaw: frame.yaw, dwell: frame.dwell, focus: frame.focus, readout: frame.readout };
      const key = JSON.stringify(state);
      if (seen.has(key)) {
        copyFileSync(seen.get(key), file);
        continue;
      }
      const svg = heroSvg(theme, state, "Glazer: head direction picks the display");
      await send("Runtime.evaluate", {
        expression: `document.getElementById("f").innerHTML=${JSON.stringify(svg)};new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))`,
        awaitPromise: true,
      });
      const shot = await send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT, scale: 1 } });
      writeFileSync(file, Buffer.from(shot.data, "base64"));
      seen.set(key, file);
    }
    console.log(`${theme}: ${frames.length} frames (${seen.size} distinct)`);
  }
} finally {
  close();
}

for (const theme of ["light", "dark"]) {
  const gif = join(OUT, `hero-${theme}.gif`);
  // One palette for the whole loop (the drawing is near-monochrome), no
  // dithering so flat faces stay flat, and only changed rectangles stored.
  const filter =
    `[0:v]scale=${WIDTH}:-1:flags=lanczos,split[a][b];` +
    `[a]palettegen=max_colors=48:reserve_transparent=0:stats_mode=full[p];` +
    `[b][p]paletteuse=dither=none:diff_mode=rectangle`;
  const run = spawnSync(ffmpeg, ["-y", "-v", "error", "-framerate", String(FPS), "-i", join(work, theme, "f%04d.png"), "-filter_complex", filter, "-loop", "0", gif], { stdio: "inherit" });
  if (run.status !== 0) process.exit(run.status ?? 1);
  console.log(`wrote ${gif} (${(statSync(gif).size / 1024).toFixed(0)} KB, ${LENGTH}s at ${FPS} fps)`);
}
if (KEEP) console.log(`frames kept in ${work}`);
else rmSync(work, { recursive: true, force: true });
