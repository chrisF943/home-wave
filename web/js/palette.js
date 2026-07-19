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
