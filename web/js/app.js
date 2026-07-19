import { patterns } from './patterns/index.js';
import { Settings, bindPanel } from './settings.js';
import { ThemeEngine, manualTheme, extractPalette, deriveTheme } from './palette.js';

const canvas = document.getElementById('viz');
const settings = new Settings();
const themes = new ThemeEngine();
let artTheme = null; // set by the Chameleon (Task 6)
let pattern = null;
let latestFrame = { bands: new Array(64).fill(0), level: 0, beat: false };

function sendCommand(cmd) {
  window.webkit?.messageHandlers?.homewave?.postMessage({ cmd });
}

function fitCanvas(c) {
  const dpr = window.devicePixelRatio || 1;
  const w = Math.round(c.clientWidth * dpr), h = Math.round(c.clientHeight * dpr);
  if (c.width !== w || c.height !== h) {
    c.width = w;
    c.height = h;
  }
  c.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0);
}

function setPattern(id) {
  pattern?.destroy();
  pattern = patterns.find(p => p.id === id) ?? patterns[0];
  pattern.init(canvas);
}

function updateChip(evt) {
  const chip = document.getElementById('now-playing');
  chip.classList.toggle('hidden', !evt.playing);
  document.getElementById('np-title').textContent = evt.title;
  document.getElementById('np-artist').textContent = evt.artist;
  const img = document.getElementById('np-art');
  if (evt.artDataURL) {
    img.src = evt.artDataURL;
    img.hidden = false;
  } else {
    img.hidden = true;
  }
}

let artLoadSeq = 0;

function loadArtTheme(artDataURL) {
  const seq = ++artLoadSeq;
  const img = new Image();
  img.onload = () => {
    if (seq !== artLoadSeq) return; // a newer track's art superseded this load
    const size = 64;
    const c = document.createElement('canvas');
    c.width = c.height = size;
    const ctx = c.getContext('2d');
    ctx.drawImage(img, 0, 0, size, size);
    const pixels = ctx.getImageData(0, 0, size, size).data;
    artTheme = deriveTheme(extractPalette(pixels, 5));
  };
  img.src = artDataURL;
}

window.homewave = {
  onAudioFrame(frame) { latestFrame = frame; },
  onTrack(evt) {
    updateChip(evt);
    if (evt.artDataURL) loadArtTheme(evt.artDataURL);
  },
  onAudioStatus(status) {
    document.getElementById('permission-overlay')
      .classList.toggle('hidden', status === 'ok');
  },
};

document.getElementById('retry-audio')
  .addEventListener('click', () => sendCommand('retryAudioPermission'));
document.getElementById('open-settings')
  .addEventListener('click', () => sendCommand('openSystemSettings'));

const sel = document.getElementById('set-pattern');
for (const p of patterns) {
  const opt = document.createElement('option');
  opt.value = p.id;
  opt.textContent = p.name;
  sel.appendChild(opt);
}
bindPanel(settings, { onPattern: setPattern });
setPattern(settings.values.pattern);

function loop(tMs) {
  fitCanvas(canvas);
  const target = settings.values.chameleon && artTheme ? artTheme : manualTheme(settings.values);
  themes.setTargetIfChanged(target, tMs);
  pattern.render(latestFrame, themes.current(tMs), settings.values, tMs);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
