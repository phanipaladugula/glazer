// Glazer README hero figure: "Head direction picks the display".
//
// A sighting turret (a small theodolite) stands in for the user's head. Its
// alidade turns over an engraved yaw circle that carries two calibration index
// stops, one per display, and a faint hysteresis band at their midpoint. The
// MacBook and the external monitor stand on a desk board at exactly the yaw
// angles the circle marks. The turret is turned to +27°, past the band, so the
// monitor's screen is the one lit part, with the pointer drawn on it.
//
// Built with the Anatomy kit (kit/ in this folder, copied from the Anatomy
// skill, MIT). Regenerate both SVGs with:  node docs/figure/build.mjs

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as k from "./kit/iso-kit.mjs";
import * as G from "./kit/lathe.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "images");

// ---------------------------------------------------------------- the model
// Yaw in degrees, positive = head turned right. These are Glazer's example
// calibration values; the decision boundary is their midpoint.
const CAL = { mac: -4, lg: 28 };
const BOUNDARY = (CAL.mac + CAL.lg) / 2; // +12°
const HYST = 3; // ± degrees of hysteresis around the boundary
const YAW = 27; // the head's current yaw
const DWELL = 0.5; // seconds the yaw must stay past the band
const target = Math.abs(YAW - CAL.lg) < Math.abs(YAW - CAL.mac) && YAW > BOUNDARY + HYST ? "LG" : "MacBook";
const READOUT = `yaw ${YAW >= 0 ? "+" : ""}${YAW}° → ${target === "LG" ? "LG" : "MacBook"}`;

// ---------------------------------------------------------------- the world
const WIDTH = 880;
const HEIGHT = 540;
const DEG = Math.PI / 180;
// Floor direction the head faces at a yaw (0 = -y, +90 = +x): the same
// convention as k.radialTicks, so the engraved circle and the parts agree.
const dir = (yaw) => [Math.sin(yaw * DEG), -Math.cos(yaw * DEG)];
const right = (yaw) => [Math.cos(yaw * DEG), Math.sin(yaw * DEG)];

const PLATE = { x: -86, y: -228, w: 260, d: 318, r: 10 };
const PLATE_H = 12;
const FOOT_H = 5;
const DESK = { x: -68, y: -214, w: 228, d: 112, r: 6 };
const DESK_H = 5;

const DIAL_R = 64; // the engraved yaw circle
const DIAL_Z = 4;
const DIAL_TOP = 9;
const SCALE_R = 62; // tick roots
const ALI_R = 40; // alidade disc
const ALI_TOP = 12;
const HOUSE_R = 12;
const HOUSE_TOP = 24;
const STD_TOP = 38;
const SCOPE_Z = 33; // telescope axis height

const MAC = { yaw: CAL.mac, dist: 142, w: 78, d: 55, h: 3.4, lidH: 53, tilt: 16 };
const LG = { yaw: CAL.lg, dist: 182, w: 152, z0: 44, z1: 132, t: 5 };

const P = k.fitProjection(
  [
    ...k.boxCorners(PLATE, -PLATE_H - FOOT_H, 0),
    [LG.dist * dir(LG.yaw)[0] - 76 * right(LG.yaw)[0], LG.dist * dir(LG.yaw)[1] - 76 * right(LG.yaw)[1], DESK_H + LG.z1],
    [LG.dist * dir(LG.yaw)[0] + 76 * right(LG.yaw)[0], LG.dist * dir(LG.yaw)[1] + 76 * right(LG.yaw)[1], DESK_H + LG.z1],
  ],
  WIDTH,
  HEIGHT,
  { pad: 58, azimuth: 64 },
);

const at = (point) => k.iso(point, P);
const S = (paths, style) => k.solidSvg(paths, style);
const L = (d, style) => k.lineSvg(d, style);
const D = (points, style) => k.dotsSvg(points, style);
const depth2 = ([x, y]) => k.depthOf([x, y, 0], P);
const byDepth = (points) => [...points].sort((a, b) => depth2(a) - depth2(b));
const polar = (yaw, r, c = [0, 0]) => [c[0] + dir(yaw)[0] * r, c[1] + dir(yaw)[1] * r];
const thou = (v) => (Math.round(v * 1000) / 1000).toString();

// A local frame on the floor: u to the right of `yaw`, v along `yaw` (away
// from the turret). A rounded rectangle in it becomes a ring for k.extrude.
const frame2 = (c, yaw) => (u, v) => [c[0] + right(yaw)[0] * u + dir(yaw)[0] * v, c[1] + right(yaw)[1] * u + dir(yaw)[1] * v];
const ringIn = (to, u0, u1, v0, v1, r, steps = 4) =>
  k.roundedPlan({ x: u0, y: v0, w: u1 - u0, d: v1 - v0, r }, steps).map(([u, v]) => to(u, v));
const box = (to, u0, u1, v0, v1, r, z, h, steps = 4, bevel = 0) => k.extrude(ringIn(to, u0, u1, v0, v1, r, steps), z, h, P, { bevel });
const outlineIn = (to, u0, u1, v0, v1, r, z, steps = 3) => k.onTop(ringIn(to, u0, u1, v0, v1, r, steps), z, P, true);

// An SVG transform that maps local (x, y) onto a plane through `o` spanned by
// `ex` (local x) and `ey` (local y, pointing down the face).
function planeMatrix(o, ex, ey) {
  const O = at(o);
  const X = at([o[0] + ex[0], o[1] + ex[1], o[2] + ex[2]]);
  const Y = at([o[0] + ey[0], o[1] + ey[1], o[2] + ey[2]]);
  return `matrix(${thou(X[0] - O[0])} ${thou(X[1] - O[1])} ${thou(Y[0] - O[0])} ${thou(Y[1] - O[1])} ${thou(O[0])} ${thou(O[1])})`;
}
const flatRect = (x0, y0, x1, y1, r, steps = 4) => k.pathOf(k.roundedPlan({ x: x0, y: y0, w: x1 - x0, d: y1 - y0, r }, steps), true);

let count = 0; // solids drawn, for the report
const solid = (paths, style) => {
  count++;
  return S(paths, style);
};

// ---------------------------------------------------------------- base
function plate() {
  const out = [`<path class="iso-halo" d="${k.haloOf(PLATE, -PLATE_H - FOOT_H, PLATE_H, P)}"/>`];
  for (const [x, y] of byDepth(k.corners(PLATE, 24))) {
    out.push(solid(k.cylinder(x, y, 7.5, -PLATE_H - FOOT_H, 1.6, P, 28), { tone: "lo" }));
    out.push(solid(k.cylinder(x, y, 5.6, -PLATE_H - FOOT_H + 1.6, FOOT_H - 1.6, P, 28), { tone: "mid" }));
  }
  out.push(solid(k.slabOf(PLATE, -PLATE_H, PLATE_H, P, 8, 1.6), { tone: "mid", inner: L(k.sideSeam(PLATE, -PLATE_H + 3.2, P, 8), { tone: "faint" }) }));
  out.push(L(k.planOutline(k.insetPlan(PLATE, 5), 0, P), { tone: "lo" }));
  const screws = k.corners(PLATE, 11);
  out.push(L(screws.map(([x, y]) => k.ring(x, y, 2.3, 0, P, 16)).join(""), { tone: "lo" }));
  out.push(D(screws.map(([x, y]) => at([x, y, 0])), { size: 0.55 }));

  // ruler strip along the right edge, ticks rooted on its inner edge
  const strip = { x: PLATE.x + PLATE.w - 17, y: -84, w: 7, d: 152, r: 1 };
  out.push(solid(k.slabOf(strip, 0, 0.6, P, 3), { tone: "lo", crease: "none" }));
  const ticks = k.topTicks(strip.y + 3, strip.y + strip.d - 3, 4, 5, strip.x + 0.8, 0.6, [2, 3.8], P, "y");
  out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
  out.push(D([at([strip.x + 4.6, strip.y + 1.8, 0.6]), at([strip.x + 4.6, strip.y + strip.d - 1.8, 0.6])], { size: 0.42 }));

  // label plate, front right: one engraved word and two rule lines
  const label = { x: 86, y: 36, w: 56, d: 20, r: 1.4 };
  out.push(solid(k.slabOf(label, 0, 0.9, P, 3, 0.4), { tone: "lo", crease: "faint" }));
  out.push(L(k.planOutline(k.insetPlan(label, 1.6), 0.9, P, 3), { tone: "faint" }));
  out.push(k.faceTextSvg(k.topMatrix([label.x + 5, label.y + 8.4], 0.9, P, "x"), "GLAZER", { size: 4.6, tone: "mid" }));
  out.push(L([30, 20].map((w, i) => k.lineOnTop([label.x + 5, label.y + 12 + i * 3.2], [label.x + 5 + w, label.y + 12 + i * 3.2], 0.9, P)).join(""), { tone: "lo", free: true }));
  out.push(D([at([label.x + label.w - 4, label.y + 4, 0.9]), at([label.x + label.w - 4, label.y + label.d - 4, 0.9])], { size: 0.45 }));
  return out.join("");
}

function desk() {
  const out = [`<path class="iso-halo" d="${k.haloOf(DESK, 0, DESK_H, P)}" style="opacity:.5"/>`];
  out.push(solid(k.slabOf(DESK, 0, DESK_H, P, 6, 1), { tone: "mid" }));
  out.push(L(k.planOutline(k.insetPlan(DESK, 4), DESK_H, P, 6), { tone: "faint" }));
  const screws = k.corners(DESK, 8);
  out.push(L(screws.map(([x, y]) => k.ring(x, y, 1.8, DESK_H, P, 14)).join(""), { tone: "lo" }));
  out.push(D(screws.map(([x, y]) => at([x, y, DESK_H])), { size: 0.45 }));
  return out.join("");
}

// ---------------------------------------------------------------- MacBook
function macbook() {
  const c = polar(MAC.yaw, MAC.dist);
  const to = frame2(c, MAC.yaw);
  const hw = MAC.w / 2;
  const hd = MAC.d / 2;
  const z0 = DESK_H + 0.9;
  const top = z0 + MAC.h;
  const out = [`<path class="iso-halo" d="${k.extrude(ringIn(to, -hw, hw, -hd, hd, 4, 6), DESK_H, 1, P).fill}" style="opacity:.55"/>`];
  // rubber feet
  const feet = [[-hw + 7, -hd + 6], [hw - 7, -hd + 6], [-hw + 7, hd - 6], [hw - 7, hd - 6]].map(([u, v]) => to(u, v));
  for (const [x, y] of byDepth(feet)) out.push(solid(k.cylinder(x, y, 2.4, DESK_H, 0.9, P, 16), { tone: "lo", crease: "none" }));
  // the deck, with its seam and a thumb notch on the front edge
  const deck = ringIn(to, -hw, hw, -hd, hd, 4, 6);
  out.push(solid(k.extrude(deck, z0, MAC.h, P, { bevel: 0.6 }), { tone: "mid", inner: L(k.ringSeam(deck, z0 + 1.2, P), { tone: "faint" }) }));
  // keyboard well and key grid (near-flush keys: closed outlines)
  const kv0 = -3;
  const kv1 = hd - 4;
  out.push(L(outlineIn(to, -hw + 5, hw - 5, kv0, kv1, 1.6, top), { tone: "lo" }));
  const cols = 14;
  const rows = 6;
  const pitchU = (MAC.w - 12) / cols;
  const pitchV = (kv1 - kv0 - 1) / rows;
  const keys = [];
  for (let r = 0; r < rows; r++) {
    const v0 = kv0 + 0.5 + r * pitchV;
    const fn = r === rows - 1; // the function row is half height
    const vh = fn ? pitchV * 0.62 : pitchV;
    if (r === 0) {
      // bottom row: cmd keys and a long space bar
      const plan = [[0, 1.5], [1.5, 2.8], [2.8, 4.3], [4.3, 9.6], [9.6, 11.1], [11.1, 12.4], [12.4, 14]];
      for (const [a, b] of plan) keys.push(outlineIn(to, -hw + 6 + a * pitchU + 0.35, -hw + 6 + b * pitchU - 0.35, v0 + 0.35, v0 + vh - 0.35, 0.6, top, 2));
      continue;
    }
    for (let i = 0; i < cols; i++) keys.push(outlineIn(to, -hw + 6 + i * pitchU + 0.35, -hw + 6 + (i + 1) * pitchU - 0.35, v0 + 0.35, v0 + vh - 0.35, 0.6, top, 2));
  }
  out.push(L(keys.join(""), { tone: "faint" }));
  // trackpad
  out.push(L(outlineIn(to, -15, 15, -hd + 3.5, kv0 - 3.5, 1.6, top), { tone: "lo" }));
  // hinge barrel along the back edge
  const right3 = [right(MAC.yaw)[0], right(MAC.yaw)[1], 0];
  const back3 = [dir(MAC.yaw)[0], dir(MAC.yaw)[1], 0];
  const hingeAt = [...to(0, hd - 1.6), top + 0.4];
  out.push(solid(G.disc(-hw + 8, hw - 8, 1.8, G.frameAlong(hingeAt, right3), P), { tone: "mid" }));
  // lid: a prism along its own normal, opened 90° + tilt
  const t = MAC.tilt * DEG;
  const up = [back3[0] * Math.sin(t), back3[1] * Math.sin(t), Math.cos(t)];
  const normal = [-back3[0] * Math.cos(t), -back3[1] * Math.cos(t), Math.sin(t)];
  const lidO = [...to(0, hd - 0.4), top + 0.6];
  const F = G.frameOf(lidO, normal, right3, up);
  const lidRing = k.roundedPlan({ x: -hw, y: 0, w: MAC.w, d: MAC.lidH, r: 3.4 }, 6);
  out.push(solid(G.prismOf(F, lidRing, -2.2, 0, P), { tone: "mid" }));
  // the screen in the lid plane: unlit glass inside a bezel, camera in the top bezel
  const face = (x, y) => [lidO[0] + right3[0] * x + up[0] * y, lidO[1] + right3[1] * x + up[1] * y, lidO[2] + up[2] * y];
  const M = planeMatrix(lidO, right3, [-up[0], -up[1], -up[2]]);
  const glass = flatRect(-hw + 2.8, -(MAC.lidH - 4.2), hw - 2.8, -3.2, 1.4);
  out.push(`<g transform="${M}"><path class="hero-glass" d="${glass}"/>${L(glass, { tone: "lo" })}${L(flatRect(-hw + 1.2, -(MAC.lidH - 1.2), hw - 1.2, -1.2, 2.4, 6), { tone: "faint" })}</g>`);
  out.push(L(k.pathOf(Array.from({ length: 16 }, (_, i) => { const a = (i / 16) * Math.PI * 2; return at(face(Math.cos(a) * 1, MAC.lidH - 2.2 + Math.sin(a) * 1)); }), true), { tone: "faint" }));
  out.push(D([at(face(0, MAC.lidH - 2.2))], { size: 0.55, tone: "hi" }));
  return out.join("");
}

// ---------------------------------------------------------------- monitor
function monitor() {
  const c = polar(LG.yaw, LG.dist);
  const to = frame2(c, LG.yaw);
  const hw = LG.w / 2;
  const z = DESK_H;
  const out = [];
  // stand base
  const base = ringIn(to, -30, 30, -16, 22, 8, 8);
  out.push(`<path class="iso-halo" d="${k.extrude(base, z, 1, P).fill}" style="opacity:.6"/>`);
  out.push(solid(k.extrude(base, z, 2.6, P, { bevel: 0.6 }), { tone: "mid" }));
  out.push(L(k.onTop(ringIn(to, -26, 26, -12, 18, 6, 8), z + 2.6, P, true), { tone: "faint" }));
  // neck, hinge block, back housing
  out.push(solid(box(to, -6, 6, 10, 16, 1.6, z + 2.6, 86, 3, 0.4), { tone: "mid" }));
  out.push(solid(box(to, -9, 9, 9, 17.2, 2, z + 80, 13, 3, 0.4), { tone: "mid" }));
  out.push(D([to(-5.5, 13.1), to(5.5, 13.1)].map(([x, y]) => at([x, y, z + 93])), { size: 0.45 }));
  out.push(solid(box(to, -50, 50, 2.5, 9, 6, z + 58, 60, 6, 0.4), { tone: "mid" }));
  // the panel
  const panel = ringIn(to, -hw, hw, -2.5, 2.5, 2, 4);
  out.push(solid(k.extrude(panel, z + LG.z0, LG.z1 - LG.z0, P, { bevel: 0.4 }), { tone: "mid" }));
  // the screen: the one lit part, a thin glass proud of the bezel
  const sx0 = -hw + 2.4;
  const sx1 = hw - 2.4;
  const sz0 = z + LG.z0 + 4.2;
  const sz1 = z + LG.z1 - 2.4;
  out.push(solid(box(to, sx0, sx1, -3.1, -2.5, 1, sz0, sz1 - sz0, 3), { tone: "hi", lit: true }));
  // content in the glass plane: local x to the user's right, y down from the top edge
  const right3 = [right(LG.yaw)[0], right(LG.yaw)[1], 0];
  const o = [...to(0, -3.1), sz1];
  const M = planeMatrix(o, right3, [0, 0, -1]);
  const H = sz1 - sz0;
  const W = sx1 - sx0;
  const menu = `M${thou(sx0)} 4.4H${thou(sx1)}`;
  const win = flatRect(-W * 0.3, 12, W * 0.24, H - 16, 1.6);
  const bar = `M${thou(-W * 0.3)} 17H${thou(W * 0.24)}`;
  const lights = [0, 2.6, 5.2].map((dx) => `M${thou(-W * 0.3 + 3 + dx)} 14.5h0`).join("");
  const dock = flatRect(-W * 0.18, H - 7, W * 0.18, H - 2.4, 1.6);
  const icons = Array.from({ length: 8 }, (_, i) => flatRect(-W * 0.18 + 2.2 + i * ((W * 0.36 - 4.4) / 8) + 0.5, H - 6.2, -W * 0.18 + 2.2 + (i + 1) * ((W * 0.36 - 4.4) / 8) - 0.5, H - 3.2, 0.6, 2)).join("");
  // the pointer, landed near the middle of the screen
  const px = 14;
  const py = H * 0.46;
  const arrow = [[0, 0], [0, 11], [2.6, 8.4], [4.6, 12.8], [6.2, 12.1], [4.3, 7.8], [8, 7.8]].map(([x, y]) => [px + x * 0.9, py + y * 0.9]);
  out.push(
    `<g transform="${M}">` +
      `<path class="hero-screen" d="${flatRect(sx0 + 0.3, 0.3, sx1 - 0.3, H - 0.3, 0.8)}"/>` +
      L(menu, { tone: "lo" }) +
      L(win, { tone: "lo" }) +
      L(bar, { tone: "lo" }) +
      `<path class="iso-line" data-tone="mid" data-free="" d="${lights}" style="stroke-width:1.6"/>` +
      L(dock, { tone: "lo" }) +
      L(icons, { tone: "lo" }) +
      `<path class="hero-pointer" d="${k.pathOf(arrow, true)}"/>` +
      `</g>`,
  );
  // power LED under the bottom bezel
  out.push(D([at([...to(hw - 10, -2.5), z + LG.z0 + 1.6])], { size: 0.5, tone: "hi" }));
  return out.join("");
}

// ---------------------------------------------------------------- turret
function scaleArc(yaw0, yaw1, r, z, steps = 24) {
  return Array.from({ length: steps + 1 }, (_, i) => [...polar(yaw0 + ((yaw1 - yaw0) * i) / steps, r), z]);
}

function turret() {
  const back = [];
  const front = [];
  const viewYaw = Math.atan2(k.towardViewer(P)[0], -k.towardViewer(P)[1]) / DEG; // yaw that faces the viewer
  // leveling screws on lugs, outside the circle
  for (const yaw of [viewYaw - 62, viewYaw + 62, viewYaw + 180]) {
    const to = frame2([0, 0], yaw);
    const parts = [
      solid(box(to, -3.2, 3.2, 50, 66, 1.2, 0, 3.6, 3, 0.3), { tone: "lo" }),
      solid(k.cylinder(...polar(yaw, 69), 4.6, 0, 7.2, P, 24), { tone: "mid" }),
      L(k.knurl(...polar(yaw, 69), 4.6, 0, 7.2, 22, P), { tone: "lo" }),
      solid(k.cylinder(...polar(yaw, 69), 2, 7.2, 1.2, P, 16), { tone: "mid" }),
    ].join("");
    (depth2(polar(yaw, 60)) < 0 ? back : front).push(parts);
  }
  // calibration index stops: a post outside the circle, a cap reaching over the scale
  const caps = [];
  for (const yaw of [CAL.mac, CAL.lg]) {
    const to = frame2([0, 0], yaw);
    back.push(solid(box(to, -3.4, 3.4, DIAL_R + 1, DIAL_R + 8, 1, 0, DIAL_TOP, 3, 0.3), { tone: "mid" }));
    const nose = [to(0, SCALE_R + 0.6), to(-2.6, DIAL_R + 1.8), to(-3.4, DIAL_R + 3), to(-3.4, DIAL_R + 8), to(3.4, DIAL_R + 8), to(3.4, DIAL_R + 3), to(2.6, DIAL_R + 1.8)];
    caps.push(solid(k.extrude(nose, DIAL_TOP, 1.8, P, { bevel: 0.3 }), { tone: "hi", crease: "lo" }));
    caps.push(L(k.onTop([to(0, SCALE_R + 1.2), to(0, DIAL_R + 6)], DIAL_TOP + 1.8, P), { tone: "hi" }));
    caps.push(D([at([...to(0, DIAL_R + 6), DIAL_TOP + 1.8])], { size: 0.5, tone: "hi" }));
  }

  const out = [];
  out.push(`<path class="iso-halo" d="${k.cylinder(0, 0, DIAL_R, 0, DIAL_TOP, P, 64).fill}"/>`);
  out.push(...back);
  out.push(solid(k.cylinder(0, 0, 54, 0, DIAL_Z, P, 72), { tone: "lo" }));
  // the yaw circle
  out.push(solid(k.cylinder(0, 0, DIAL_R, DIAL_Z, DIAL_TOP - DIAL_Z, P, 96, 0.8), { tone: "hi", crease: "lo", inner: L(k.sideArc(0, 0, DIAL_R, DIAL_Z + 1.8, P, 48), { tone: "faint" }) }));
  out.push(L(k.ring(0, 0, SCALE_R, DIAL_TOP, P, 120), { tone: "lo" }));
  const ticks = k.radialTicks(0, 0, SCALE_R, 180, 5, DIAL_TOP, [2.6, 5], P);
  out.push(L(ticks.minor, { tone: "lo" }), L(ticks.major, { tone: "mid" }));
  out.push(L(k.ring(0, 0, SCALE_R - 5, DIAL_TOP, P, 120), { tone: "faint" }));
  out.push(L(k.onTop([polar(0, SCALE_R - 5), polar(0, SCALE_R)], DIAL_TOP, P), { tone: "hi" }));
  // hysteresis band: an engraved closed slot between the two calibrations
  const r0 = SCALE_R - 13.5;
  const r1 = SCALE_R - 9.5;
  const slot = [...scaleArc(BOUNDARY - HYST, BOUNDARY + HYST, r1, DIAL_TOP, 12), ...scaleArc(BOUNDARY + HYST, BOUNDARY - HYST, r0, DIAL_TOP, 12)];
  out.push(L(k.pathOf(slot.map(at), true), { tone: "lo" }));
  out.push(L(k.onTop([polar(BOUNDARY, r0), polar(BOUNDARY, r1)], DIAL_TOP, P), { tone: "faint" }));
  out.push(...front);
  out.push(...caps);

  // alidade: index pointer arm, disc, and what stands on it
  const toA = frame2([0, 0], YAW);
  const arm = [toA(-4, ALI_R - 3), toA(4, ALI_R - 3), toA(1.2, SCALE_R - 4.6), toA(0, SCALE_R - 2.4), toA(-1.2, SCALE_R - 4.6)];
  out.push(solid(k.extrude(arm, DIAL_TOP, 1.4, P, { bevel: 0.3 }), { tone: "mid" }));
  out.push(L(k.onTop([toA(0, ALI_R - 2), toA(0, SCALE_R - 2.4)], DIAL_TOP + 1.4, P), { tone: "hi" }));
  out.push(`<path class="iso-halo" d="${k.cylinder(0, 0, ALI_R - 4, DIAL_TOP, 1, P, 48).fill}" style="opacity:.45"/>`);
  out.push(solid(k.cylinder(0, 0, ALI_R, DIAL_TOP, ALI_TOP - DIAL_TOP, P, 72, 0.6), { tone: "mid" }));
  out.push(L(k.ring(0, 0, ALI_R - 3, ALI_TOP, P, 72), { tone: "faint" }));
  const aliScrews = [YAW + 45, YAW + 135, YAW + 225, YAW + 315].map((y) => polar(y, ALI_R - 6));
  out.push(D(aliScrews.map(([x, y]) => at([x, y, ALI_TOP])), { size: 0.45 }));

  const onAli = [];
  // knurled lock knob on a lug
  {
    const yaw = YAW + 90;
    const to = frame2([0, 0], yaw);
    const [kx, ky] = polar(yaw, ALI_R + 6);
    onAli.push({
      at: polar(yaw, ALI_R),
      svg:
        solid(box(to, -2.4, 2.4, ALI_R - 4, ALI_R + 4, 1, ALI_TOP, 3, 3, 0.3), { tone: "mid" }) +
        solid(k.cylinder(kx, ky, 4.4, ALI_TOP, 7, P, 28, 0.4), { tone: "mid" }) +
        L(k.knurl(kx, ky, 4.4, ALI_TOP, ALI_TOP + 7, 26, P), { tone: "lo" }) +
        L(k.onTop([[kx, ky], polar(yaw, ALI_R + 9.6)], ALI_TOP + 7, P), { tone: "hi" }) +
        D([at([kx, ky, ALI_TOP + 7])], { size: 0.5, tone: "hi" }),
    });
  }
  // dwell indicator: a small round gauge, segments all filled (0.5 s held)
  {
    const [gx, gy] = polar(YAW + 168, 27);
    const segs = Array.from({ length: 12 }, (_, i) => {
      const a0 = i * 30 + 4;
      const a1 = a0 + 22;
      const arc = (r, from, to) => Array.from({ length: 5 }, (_, j) => [...polar(from + ((to - from) * j) / 4, r, [gx, gy]), ALI_TOP + 2.2]);
      return k.pathOf([...arc(5.2, a0, a1), ...arc(3.6, a1, a0)].map(at), true);
    });
    onAli.push({
      at: [gx, gy],
      svg:
        solid(k.cylinder(gx, gy, 7, ALI_TOP, 2.2, P, 40, 0.4), { tone: "mid" }) +
        `<path class="hero-seg" d="${segs.join("")}"/>` +
        L(segs.join(""), { tone: "hi" }) +
        L(k.ring(gx, gy, 1.5, ALI_TOP + 2.2, P, 16), { tone: "lo" }),
    });
  }
  // level vial
  {
    const yaw = YAW + 220;
    const to = frame2(polar(yaw, 26), yaw + 90);
    onAli.push({
      at: polar(yaw, 26),
      svg:
        solid(box(to, -8, 8, -2.6, 2.6, 1.2, ALI_TOP, 2.6, 3, 0.4), { tone: "mid" }) +
        L(outlineIn(to, -6, 6, -1.2, 1.2, 1.2, ALI_TOP + 2.6, 4), { tone: "lo" }) +
        L(outlineIn(to, -1.6, 1.6, -0.8, 0.8, 0.8, ALI_TOP + 2.6, 4), { tone: "mid" }) +
        D([to(-7, 0), to(7, 0)].map(([x, y]) => at([x, y, ALI_TOP + 2.6])), { size: 0.35 }),
    });
  }

  // housing, standards, telescope
  const right3 = [right(YAW)[0], right(YAW)[1], 0];
  const fwd3 = [dir(YAW)[0], dir(YAW)[1], 0];
  const head = [];
  head.push(solid(k.cylinder(0, 0, HOUSE_R + 2, ALI_TOP, 2.4, P, 48), { tone: "mid" }));
  head.push(solid(k.cylinder(0, 0, HOUSE_R, ALI_TOP + 2.4, HOUSE_TOP - ALI_TOP - 2.4, P, 48, 0.5), { tone: "hi", crease: "lo", inner: L(k.sideArc(0, 0, HOUSE_R, ALI_TOP + 7, P, 32), { tone: "faint" }) }));
  const stdAt = (side) => box(toA, side - 1.6, side + 1.6, -6.5, 6.5, 1, HOUSE_TOP, STD_TOP - HOUSE_TOP, 3, 0.4);
  const scopeF = G.frameAlong([0, 0, SCOPE_Z], fwd3);
  const scope = G.solidOf([[-19, 2.3], [-15.5, 2.3], [-15.5, 2.9], [-14, 2.9], [-14, 3.6], [9, 3.6], [9, 4.6], [18, 4.6]], scopeF, P);
  const eye = G.frameAlong([0, 0, SCOPE_Z], fwd3);
  const near = depth2(right(YAW)) > 0 ? 7.4 : -7.4;
  head.push(solid(stdAt(-near), { tone: "mid" }));
  head.push(solid(scope, { tone: "hi", crease: "lo", inner: L(G.arcOf(scopeF, 0, 3.6, P), { tone: "faint" }) + L(G.arcOf(scopeF, 13.5, 4.6, P), { tone: "faint" }) }));
  head.push(`<path class="hero-glass" d="${G.circleOf(eye, -19, 1.5, P, 24)}"/>` + L(G.circleOf(eye, -19, 1.5, P, 24), { tone: "lo" }));
  head.push(solid(stdAt(near), { tone: "mid" }));
  const trunnionAt = [right3[0] * (near + 1.6 * Math.sign(near)), right3[1] * (near + 1.6 * Math.sign(near)), SCOPE_Z];
  const tF = G.frameAlong(trunnionAt, Math.sign(near) > 0 ? right3 : right3.map((v) => -v));
  head.push(solid(G.disc(0, 1.4, 3.2, tF, P), { tone: "mid" }));
  head.push(D([at(G.pointOf(tF, 1.4, 0, 0))], { size: 0.5, tone: "hi" }));

  const sorted = onAli.sort((a, b) => depth2(a.at) - depth2(b.at));
  out.push(...sorted.filter((p) => depth2(p.at) < 0).map((p) => p.svg));
  out.push(...head);
  out.push(...sorted.filter((p) => depth2(p.at) >= 0).map((p) => p.svg));
  return out.join("");
}

// ---------------------------------------------------------------- card
const CARD_CSS = `
.iso{--hero-glass:#0a0a0a;--hero-screen:#2b2b2b;--hero-seg:#d4d4d4}
.iso[data-theme="light"]{--hero-glass:#dcdcd9;--hero-screen:#ffffff;--hero-seg:#26262a}
.hero-card{fill:var(--anatomy-card);stroke:var(--anatomy-mid);stroke-width:1}
.hero-corner{font-family:var(--anatomy-mono);font-size:11.5px;letter-spacing:.04em;fill:var(--anatomy-muted)}
.hero-corner[data-corner="fig"],.hero-corner[data-corner="readout"]{fill:var(--anatomy-text)}
.hero-corner[data-corner="title"],.hero-corner[data-corner="hint"]{letter-spacing:.1em;text-transform:uppercase}
.hero-glass{fill:var(--hero-glass);stroke:none}
.hero-seg{fill:var(--hero-seg);stroke:none}
.hero-screen{fill:var(--hero-screen);stroke:none}
.hero-pointer{fill:var(--anatomy-lit);stroke:var(--anatomy-card);stroke-width:.5;stroke-linejoin:round}
.iso-halo{filter:url(#hero-blur)}
`;

function card() {
  const inset = 22;
  const base = HEIGHT - inset;
  const text = (corner, x, y, anchor, value) => `<text class="hero-corner" data-corner="${corner}" x="${x}" y="${y}" text-anchor="${anchor}">${value}</text>`;
  return [
    `<defs><filter id="hero-blur" filterUnits="userSpaceOnUse" x="0" y="0" width="${WIDTH}" height="${HEIGHT}"><feGaussianBlur stdDeviation="9"/></filter></defs>`,
    `<rect class="hero-card" x="0.5" y="0.5" width="${WIDTH - 1}" height="${HEIGHT - 1}"/>`,
    text("fig", inset, inset + 9, "start", "Fig 1"),
    text("title", WIDTH - inset, inset + 9, "end", "Head direction picks the display"),
    text("hint", inset, base, "start", "Glazer · head-pose focus"),
    text("readout", WIDTH - inset, base, "end", READOUT),
  ].join("");
}

const label =
  `Fig 1, head direction picks the display. A sighting turret on a rotary base stands in for the user's head. ` +
  `Its yaw circle is engraved every 2 degrees and carries two calibration stops, the MacBook at ${CAL.mac} degrees and the LG monitor at +${CAL.lg} degrees, ` +
  `with a hysteresis band around the +${BOUNDARY} degree midpoint. The turret is turned to +${YAW} degrees and its dwell gauge is full, ` +
  `so the LG monitor's screen is lit and holds the pointer, while the MacBook's screen stays dark.`;

// The monitor stands behind the MacBook's right edge, so it is painted first.
const body = [card(), plate(), desk(), monitor(), macbook(), turret()];

mkdirSync(OUT, { recursive: true });
for (const theme of ["light", "dark"]) {
  let svg = k.figureSvg({ width: WIDTH, height: HEIGHT, label, body, standalone: theme });
  svg = svg.replace("</style>", `${CARD_CSS}</style>`);
  // Unused kit rules (cards, legend, React page) are dropped to keep the file small.
  svg = svg.replace(/\.iso-figure\{[\s\S]*?(?=@media \(prefers-reduced-motion)/, "").replace(/@media \(max-width:560px\)\{[^}]*\}[^}]*\}\}/, "");
  const file = join(OUT, `hero-${theme}.svg`);
  writeFileSync(file, svg);
  console.log(`wrote ${file} (${(svg.length / 1024).toFixed(1)} KB)`);
}
console.log(`${count} solids · ${READOUT} · dwell ${DWELL}s`);
