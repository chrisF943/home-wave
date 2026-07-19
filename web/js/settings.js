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

  const patternSel = document.getElementById('set-pattern');
  patternSel.value = settings.values.pattern;
  patternSel.addEventListener('change', () => {
    settings.set('pattern', patternSel.value);
    onPattern(patternSel.value);
  });

  const chameleon = document.getElementById('set-chameleon');
  chameleon.checked = settings.values.chameleon;
  chameleon.addEventListener('change', () => settings.set('chameleon', chameleon.checked));

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
