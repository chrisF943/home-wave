const KEY = 'homewave-settings';

export const DEFAULTS = {
  pattern: 'radial',
  chameleon: true,
  colors: ['#ff5470', '#3bceac', '#ffd23f'],
  background: '#0b0b12',
  sensitivity: 1,
  speed: 1,
};

export class Settings {
  constructor() {
    let saved = {};
    try { saved = JSON.parse(localStorage.getItem(KEY)) ?? {}; } catch { /* corrupt = defaults */ }
    this.values = { ...DEFAULTS, ...saved };
  }

  set(key, value) {
    this.values[key] = value;
    localStorage.setItem(KEY, JSON.stringify(this.values));
  }
}

export function bindPanel(settings, { onPattern }) {
  const panel = document.getElementById('settings-panel');
  document.getElementById('settings-toggle')
    .addEventListener('click', () => panel.classList.toggle('hidden'));
  document.addEventListener('mousedown', (e) => {
    if (panel.classList.contains('hidden')) return;
    if (panel.contains(e.target) || e.target.closest('#settings-toggle')) return;
    panel.classList.add('hidden');
  });

  const patternSel = document.getElementById('set-pattern');
  patternSel.value = settings.values.pattern;
  patternSel.addEventListener('change', () => {
    settings.set('pattern', patternSel.value);
    onPattern(patternSel.value);
  });

  const chameleon = document.getElementById('set-chameleon');
  const manualColors = document.getElementById('manual-colors');
  const syncManual = () => manualColors.classList.toggle('is-disabled', chameleon.checked);
  chameleon.checked = settings.values.chameleon;
  syncManual();
  chameleon.addEventListener('change', () => {
    settings.set('chameleon', chameleon.checked);
    syncManual();
  });

  settings.values.colors.forEach((hex, i) => {
    const input = document.getElementById(`set-color-${i}`);
    input.value = hex;
    input.addEventListener('input', () => {
      const colors = [...settings.values.colors];
      colors[i] = input.value;
      settings.set('colors', colors);
    });
  });

  const bg = document.getElementById('set-background');
  bg.value = settings.values.background;
  bg.addEventListener('input', () => settings.set('background', bg.value));

  for (const key of ['sensitivity', 'speed']) {
    const input = document.getElementById(`set-${key}`);
    input.value = settings.values[key];
    input.addEventListener('input', () => settings.set(key, parseFloat(input.value)));
  }
}
