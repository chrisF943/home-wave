import { rgba } from '../color-utils.js';

export default {
  id: 'ribbons',
  name: 'Waveform Ribbons',

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
  },

  render(frame, theme, settings, tMs) {
    const { ctx } = this;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    ctx.fillStyle = rgba(theme.background, 0.18);
    ctx.fillRect(0, 0, w, h);

    const layers = Math.min(4, theme.colors.length);
    const n = frame.bands.length;
    const t = tMs * 0.001 * settings.speed;
    ctx.lineJoin = 'round';
    for (let k = 0; k < layers; k++) {
      const baseY = h * (0.28 + 0.15 * k);
      const steps = 90;
      ctx.beginPath();
      for (let s = 0; s <= steps; s++) {
        const f = s / steps;
        const v = Math.min(1, frame.bands[Math.floor(f * (n - 1))] * settings.sensitivity);
        const y = baseY
          + Math.sin(f * 5 + t * (0.6 + k * 0.2) + k * 1.7) * h * 0.03
          + v * h * 0.16 * (k % 2 ? -1 : 1);
        if (s === 0) ctx.moveTo(f * w, y); else ctx.lineTo(f * w, y);
      }
      // glow pass + core pass
      ctx.strokeStyle = rgba(theme.colors[k], 0.14);
      ctx.lineWidth = 7;
      ctx.stroke();
      ctx.strokeStyle = rgba(theme.colors[k], 0.85);
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  },

  destroy() {},
};
