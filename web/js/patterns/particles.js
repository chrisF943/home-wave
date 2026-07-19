import { rgba } from '../color-utils.js';

export default {
  id: 'particles',
  name: 'Particle Field',

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.parts = [];
    this.lastT = 0;
  },

  spawn(count, w, h, level) {
    for (let i = 0; i < count && this.parts.length < 600; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 0.4 + Math.random() * 2.4 * (0.3 + level);
      this.parts.push({
        x: w / 2, y: h / 2,
        vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
        life: 1, ci: Math.floor(Math.random() * 4),
      });
    }
  },

  render(frame, theme, settings, tMs) {
    const { ctx } = this;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    const dt = Math.min(50, (tMs - this.lastT) || 16);
    this.lastT = tMs;
    ctx.fillStyle = rgba(theme.background, 0.22);
    ctx.fillRect(0, 0, w, h);

    const level = Math.max(frame.level, 0.04); // idle trickle
    const bass = frame.bands.slice(0, 7).reduce((a, b) => a + b, 0) / 7;
    if (frame.beat) this.spawn(36, w, h, level);
    if (Math.random() < level * 0.9) this.spawn(2, w, h, level);

    const k = dt * 0.06 * settings.speed;
    for (const p of this.parts) {
      p.x += p.vx * k;
      p.y += p.vy * k;
      p.vx *= 0.988;
      p.vy *= 0.988;
      p.life -= dt * 0.00045;
      const r = Math.max(0.5, (1.5 + bass * 5 * settings.sensitivity) * p.life);
      ctx.fillStyle = rgba(theme.colors[p.ci % theme.colors.length], Math.max(0, p.life) * 0.9);
      ctx.beginPath();
      ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
      ctx.fill();
    }
    this.parts = this.parts.filter(p =>
      p.life > 0 && p.x > -20 && p.x < w + 20 && p.y > -20 && p.y < h + 20);
  },

  destroy() { this.parts = []; },
};
