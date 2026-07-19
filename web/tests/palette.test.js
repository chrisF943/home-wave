import test from 'node:test';
import assert from 'node:assert/strict';
import { extractPalette, deriveTheme } from '../js/palette.js';

function solidPixels(colors, perColor = 200) {
  const arr = new Uint8ClampedArray(colors.length * perColor * 4);
  let o = 0;
  for (const [r, g, b] of colors) {
    for (let i = 0; i < perColor; i++) {
      arr[o] = r; arr[o + 1] = g; arr[o + 2] = b; arr[o + 3] = 255;
      o += 4;
    }
  }
  return arr;
}

test('extractPalette finds the dominant colors', () => {
  const palette = extractPalette(solidPixels([[255, 0, 0], [0, 0, 255]]), 4);
  const near = (c, t) => c.every((v, i) => Math.abs(v - t[i]) < 30);
  assert.ok(palette.some(c => near(c, [255, 0, 0])), `no red in ${JSON.stringify(palette)}`);
  assert.ok(palette.some(c => near(c, [0, 0, 255])), `no blue in ${JSON.stringify(palette)}`);
});

test('extractPalette handles empty input', () => {
  assert.deepEqual(extractPalette(new Uint8ClampedArray(0)), [[128, 128, 128]]);
});

test('deriveTheme picks darkest swatch as background and pads colors to 4', () => {
  const theme = deriveTheme([[10, 10, 20], [200, 40, 90], [240, 200, 60]]);
  assert.deepEqual(theme.background, [3, 3, 5]); // darkest * 0.25, rounded
  assert.equal(theme.colors.length, 4);
});
