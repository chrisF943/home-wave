import { hexToRgb, lerpRgb } from './color-utils.js';

export function manualTheme(values) {
  const colors = values.colors.map(hexToRgb);
  while (colors.length < 4) colors.push(colors[colors.length % values.colors.length]);
  return { background: hexToRgb(values.background), colors };
}

export class ThemeEngine {
  constructor() {
    this.from = null;
    this.to = null;
    this.key = '';
    this.startMs = 0;
    this.durationMs = 1000;
  }

  setTargetIfChanged(theme, nowMs) {
    const key = JSON.stringify(theme);
    if (key === this.key) return;
    this.from = this.current(nowMs) ?? theme;
    this.to = theme;
    this.key = key;
    this.startMs = nowMs;
  }

  current(nowMs) {
    if (!this.to) return null;
    const t = Math.min(1, (nowMs - this.startMs) / this.durationMs);
    return {
      background: lerpRgb(this.from.background, this.to.background, t),
      colors: this.to.colors.map((c, i) =>
        lerpRgb(this.from.colors[i % this.from.colors.length], c, t)),
    };
  }
}

// --- Album-Art Chameleon ---------------------------------------------------

function widestAxis(box) {
  let best = 0, bestRange = -1;
  for (let axis = 0; axis < 3; axis++) {
    let lo = 255, hi = 0;
    for (const p of box) {
      if (p[axis] < lo) lo = p[axis];
      if (p[axis] > hi) hi = p[axis];
    }
    if (hi - lo > bestRange) { bestRange = hi - lo; best = axis; }
  }
  return best;
}

function spread(box) {
  let total = 0;
  for (let axis = 0; axis < 3; axis++) {
    let lo = 255, hi = 0;
    for (const p of box) {
      if (p[axis] < lo) lo = p[axis];
      if (p[axis] > hi) hi = p[axis];
    }
    total = Math.max(total, hi - lo);
  }
  return total;
}

function average(box) {
  const sum = [0, 0, 0];
  for (const p of box) { sum[0] += p[0]; sum[1] += p[1]; sum[2] += p[2]; }
  return sum.map(v => Math.round(v / box.length));
}

// Median-cut quantization over RGBA pixel data. Returns swatches sorted by
// population (most dominant first).
export function extractPalette(pixels, count = 5) {
  const pts = [];
  for (let i = 0; i < pixels.length; i += 16) { // sample every 4th pixel
    if (pixels[i + 3] < 128) continue;
    pts.push([pixels[i], pixels[i + 1], pixels[i + 2]]);
  }
  if (pts.length === 0) return [[128, 128, 128]];

  let boxes = [pts];
  while (boxes.length < count) {
    boxes.sort((a, b) => spread(b) - spread(a));
    const box = boxes[0];
    if (box.length < 2 || spread(box) === 0) break;
    boxes.shift();
    const axis = widestAxis(box);
    box.sort((p, q) => p[axis] - q[axis]);
    const mid = box.length >> 1;
    boxes.push(box.slice(0, mid), box.slice(mid));
  }
  return boxes
    .sort((a, b) => b.length - a.length)
    .map(average);
}

export function deriveTheme(swatches) {
  const luma = c => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
  const sat = c => Math.max(...c) - Math.min(...c);
  const darkest = [...swatches].sort((a, b) => luma(a) - luma(b))[0];
  const background = darkest.map(v => Math.round(v * 0.25));
  let colors = swatches
    .filter(c => c !== darkest)
    .sort((a, b) => (sat(b) + luma(b) * 0.3) - (sat(a) + luma(a) * 0.3))
    .slice(0, 4);
  if (colors.length === 0) colors = [swatches[0]];
  const n = colors.length;
  while (colors.length < 4) colors.push(colors[colors.length % n]);
  return { background, colors };
}
