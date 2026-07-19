import { rgba, lerpRgb } from '../color-utils.js';

export default {
  id: 'bars',
  name: 'Bar Wall',

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.peaks = null;
  },

  render(frame, theme, settings, tMs) {
    const { ctx } = this;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    const n = frame.bands.length;
    if (!this.peaks || this.peaks.length !== n) this.peaks = new Array(n).fill(0);

    ctx.fillStyle = rgba(theme.background, 1);
    ctx.fillRect(0, 0, w, h);

    const bw = w / n;
    for (let i = 0; i < n; i++) {
      const v = Math.min(1, frame.bands[i] * settings.sensitivity);
      this.peaks[i] = Math.max(this.peaks[i] - 0.007 * settings.speed, v);
      const pos = i / (n - 1) * (theme.colors.length - 1);
      const c = lerpRgb(theme.colors[Math.floor(pos)],
                        theme.colors[Math.min(theme.colors.length - 1, Math.ceil(pos))],
                        pos % 1);
      const bh = v * h * 0.85;
      ctx.fillStyle = rgba(c, 0.95);
      ctx.fillRect(i * bw + 1, h - bh, Math.max(1, bw - 2), bh);
      ctx.fillStyle = rgba(c, 0.6);
      ctx.fillRect(i * bw + 1, h - this.peaks[i] * h * 0.85 - 3, Math.max(1, bw - 2), 2);
    }
  },

  destroy() {},
};
