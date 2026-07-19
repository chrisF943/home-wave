// Synthetic driver for the browser harness: fake musical frames + fake tracks.
const BPM = 118;

function synthFrame(tMs) {
  const beatPeriod = 60000 / BPM;
  const phase = (tMs % beatPeriod) / beatPeriod;
  const kick = Math.pow(1 - phase, 3);
  const bands = Array.from({ length: 64 }, (_, i) => {
    const f = i / 64;
    const bass = f < 0.15 ? kick * (1 - f / 0.15) : 0;
    const melody = Math.max(0, Math.sin(tMs / 900 + i * 0.4)) * 0.5
      * Math.exp(-Math.abs(f - 0.45) * 6);
    const sparkle = f > 0.7 ? Math.random() * 0.25 * (0.5 + kick) : 0;
    return Math.min(1, bass + melody + sparkle);
  });
  return { bands, level: 0.25 + kick * 0.5, beat: phase < 0.04 };
}

setInterval(() => window.homewave.onAudioFrame(synthFrame(performance.now())), 1000 / 60);

const TRACKS = [
  { title: 'Neon Drift', artist: 'Synthetic FM', album: 'Harness', hues: [340, 200] },
  { title: 'Glasshouse', artist: 'Test Signal', album: 'Harness', hues: [140, 60] },
  { title: 'Blue Hour', artist: 'Mock Audio', album: 'Harness', hues: [220, 280] },
];
let idx = 0;

function fakeArt(hues) {
  const c = document.createElement('canvas');
  c.width = c.height = 300;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 300, 300);
  grad.addColorStop(0, `hsl(${hues[0]} 80% 55%)`);
  grad.addColorStop(1, `hsl(${hues[1]} 70% 30%)`);
  g.fillStyle = grad;
  g.fillRect(0, 0, 300, 300);
  g.fillStyle = 'hsl(0 0% 95%)';
  g.fillRect(40, 220, 220, 12);
  return c.toDataURL('image/png');
}

function nextTrack() {
  const t = TRACKS[idx++ % TRACKS.length];
  window.homewave.onTrack({ title: t.title, artist: t.artist, album: t.album,
    playing: true, artDataURL: fakeArt(t.hues) });
}

window.homewave.onAudioStatus('ok');
nextTrack();
setInterval(nextTrack, 12_000);
