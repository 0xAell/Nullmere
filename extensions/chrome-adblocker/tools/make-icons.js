#!/usr/bin/env node
// Draws the extension's icons: a full moon over a black lake, mirrored in
// still water. Original art, made here from a few shapes; nothing is
// traced or taken from anywhere. `off` is the same lake under a new moon,
// shown where Stillwater is letting a site through.
//
//   node tools/make-icons.js     writes src/icons/*.png, the same bytes every time

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodePNG } from './lib/png.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const mix = (a, b, t) => a + (b - a) * t;
const clamp = (v) => Math.min(1, Math.max(0, v));
const smooth = (edge0, edge1, x) => {
  const t = clamp((x - edge0) / (edge1 - edge0));
  return t * t * (3 - 2 * t);
};

// The palette is the game's: its night, its ink, its glow.
const NIGHT_TOP = [9, 14, 26];
const NIGHT_LOW = [2, 3, 6];
const MOON = [233, 238, 246];
const GLOW = [150, 180, 225];

/**
 * The colour and cover of the icon at a point of the unit square
 * (0,0 top left), as [r, g, b, a] with a in 0...1.
 */
function shade(x, y, { size, off }) {
  // A rounded square, a little inset so the corners are not clipped hard.
  const radius = 0.23;
  const dx = Math.max(Math.abs(x - 0.5) - (0.5 - radius), 0);
  const dy = Math.max(Math.abs(y - 0.5) - (0.5 - radius), 0);
  const cover = 1 - smooth(radius - 0.004, radius + 0.004, Math.hypot(dx, dy));
  if (cover <= 0) return [0, 0, 0, 0];

  const horizon = 0.6;
  const moon = { x: 0.5, y: 0.355, r: size <= 16 ? 0.2 : 0.17 };
  let colour = NIGHT_TOP.map((c, i) => mix(c, NIGHT_LOW[i], smooth(0.1, 0.95, y)));
  const add = (rgb, alpha) => {
    colour = colour.map((c, i) => mix(c, rgb[i], clamp(alpha)));
  };

  const distance = Math.hypot(x - moon.x, y - moon.y);
  const edge = 0.006;
  if (y < horizon) {
    // The sky: a few stars (not at the smallest sizes), the moon's halo.
    if (size >= 48) {
      for (const [sx, sy, sr] of [[0.2, 0.2, 0.011], [0.8, 0.26, 0.009], [0.74, 0.12, 0.007], [0.3, 0.44, 0.007], [0.14, 0.5, 0.006]]) {
        add(MOON, (off ? 0.5 : 0.85) * (1 - smooth(sr * 0.4, sr, Math.hypot(x - sx, y - sy))));
      }
    }
    if (!off) add(GLOW, 0.34 * (1 - smooth(moon.r, moon.r * 2.3, distance)) ** 2);
  }
  if (off) {
    // A new moon: only its rim, faint.
    const rim = size <= 16 ? 0.035 : 0.02;
    add(GLOW, 0.75 * (1 - smooth(rim * 0.5, rim * 0.5 + edge, Math.abs(distance - moon.r))));
  } else {
    // The full moon, a shade darker toward one limb.
    const lit = mix(1, 0.86, smooth(-moon.r, moon.r, (x - moon.x) * 0.8 + (y - moon.y) * 0.6));
    add(MOON.map((c) => c * lit), 1 - smooth(moon.r - edge, moon.r + edge, distance));
  }

  // The far shore: one faint line where the water begins.
  add(GLOW, (off ? 0.2 : 0.32) * (1 - smooth(0.004, 0.012, Math.abs(y - horizon))) * (1 - smooth(0.3, 0.46, Math.abs(x - 0.5))));

  // The moon on the water: strokes that shorten and fade with depth.
  if (!off && y > horizon) {
    const strokes = size <= 16 ? [[0.71, 0.17, 0.034, 0.95], [0.84, 0.09, 0.028, 0.6]] : [[0.675, 0.155, 0.017, 0.95], [0.735, 0.118, 0.014, 0.78], [0.79, 0.082, 0.012, 0.58], [0.84, 0.05, 0.01, 0.4], [0.885, 0.026, 0.009, 0.26]];
    for (const [sy, halfWidth, halfHeight, alpha] of strokes) {
      const ex = (x - 0.5) / halfWidth;
      const ey = (y - sy) / halfHeight;
      add(MOON, alpha * (1 - smooth(0.75, 1.05, Math.hypot(ex, ey))));
    }
  }
  return [...colour, cover];
}

/** The icon at a size in pixels, as RGBA bytes: sixteen samples a pixel. */
export function draw(size, off = false) {
  const samples = 4;
  const rgba = new Uint8Array(size * size * 4);
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      const sum = [0, 0, 0, 0];
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          const [r, g, b, a] = shade((px + (sx + 0.5) / samples) / size, (py + (sy + 0.5) / samples) / size, { size, off });
          sum[0] += r * a;
          sum[1] += g * a;
          sum[2] += b * a;
          sum[3] += a;
        }
      }
      const at = (py * size + px) * 4;
      const alpha = sum[3] / (samples * samples);
      rgba[at] = sum[3] ? Math.round(sum[0] / sum[3]) : 0;
      rgba[at + 1] = sum[3] ? Math.round(sum[1] / sum[3]) : 0;
      rgba[at + 2] = sum[3] ? Math.round(sum[2] / sum[3]) : 0;
      rgba[at + 3] = Math.round(alpha * 255);
    }
  }
  return rgba;
}

/** Every icon file: [name, size, off]. */
export const ICONS = [
  ['icon-16.png', 16, false],
  ['icon-32.png', 32, false],
  ['icon-48.png', 48, false],
  ['icon-128.png', 128, false],
  ['off-16.png', 16, true],
  ['off-32.png', 32, true],
  ['off-48.png', 48, true],
];

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = join(root, 'src', 'icons');
  mkdirSync(out, { recursive: true });
  for (const [name, size, off] of ICONS) {
    writeFileSync(join(out, name), encodePNG(size, size, draw(size, off)));
    console.log(`src/icons/${name}`);
  }
}
