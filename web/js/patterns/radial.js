import { rgba, lerpRgb } from '../color-utils.js';

export default {
  id: 'radial',
  name: 'Radial Bloom',

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.rotation = 0;
    this.pulse = 0;
  },

  render(frame, theme, settings, tMs) {
    const { ctx } = this;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    ctx.fillStyle = rgba(theme.background, 0.28);
    ctx.fillRect(0, 0, w, h);

    if (frame.beat) this.pulse = 1;
    this.pulse *= 0.93;
    const energy = Math.max(frame.level, 0.05); // ambient floor keeps idle drift alive
    this.rotation += (0.0012 + energy * 0.004) * settings.speed;

    const cx = w / 2, cy = h / 2;
    const r0 = Math.min(w, h) * (0.16 + this.pulse * 0.03);
    const maxLen = Math.min(w, h) * 0.30;
    const n = frame.bands.length;
    ctx.lineCap = 'round';
    for (let i = 0; i < n; i++) {
      const v = Math.min(1, frame.bands[i] * settings.sensitivity);
      const angle = this.rotation + (i / n) * Math.PI * 2;
      const len = 4 + v * maxLen;
      const pos = i / (n - 1) * (theme.colors.length - 1);
      const c = lerpRgb(theme.colors[Math.floor(pos)],
                        theme.colors[Math.min(theme.colors.length - 1, Math.ceil(pos))],
                        pos % 1);
      ctx.strokeStyle = rgba(c, 0.9);
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(angle) * r0, cy + Math.sin(angle) * r0);
      ctx.lineTo(cx + Math.cos(angle) * (r0 + len), cy + Math.sin(angle) * (r0 + len));
      ctx.stroke();
    }
    ctx.strokeStyle = rgba(theme.colors[0], 0.35 + this.pulse * 0.5);
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(cx, cy, Math.max(1, r0 - 6), 0, Math.PI * 2);
    ctx.stroke();
  },

  destroy() {},
};
