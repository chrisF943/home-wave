# HomeWave

A macOS music visualizer that reacts to whatever audio your Mac is playing — and re-themes itself to match the album art of the Spotify track that's on.

Four curated patterns, tweakable colors and motion, no browser tab and no menu-bar clutter. Just a window you can fullscreen and leave running.

## The twist: Album-Art Chameleon

When Spotify is playing, HomeWave picks up each track change instantly, pulls the album artwork, extracts its dominant colors, and crossfades the entire visualization — patterns, background, even the UI accents — to match. Skip to a different album and the whole app changes color with it.

Turn it off and you get manual color pickers instead. Either way the visualizer reacts to *all* system audio, not just Spotify — YouTube, games, anything.

## Requirements

- macOS 14.2 or later (uses the Core Audio process-tap API)
- Swift toolchain (Xcode **not** required — Command Line Tools are enough)
- Spotify desktop app, only if you want the Chameleon

## Build and run

```bash
git clone https://github.com/chrisF943/home-wave.git
cd home-wave
bash scripts/bundle.sh      # compile, assemble HomeWave.app, sign it
open build/HomeWave.app
```

That's the whole build — no dependencies to install, no configuration. It takes about a minute on first run and the script checks your macOS version and toolchain up front, so if something's missing you'll hear about it immediately rather than after a failed compile. Once built, you can launch it from Finder or the Dock like any other app — Terminal is only needed when the code changes.

On first launch macOS asks for two permissions:

1. **Audio capture** — required; the visualizer has nothing to react to without it. Grant it under System Settings → Privacy & Security → Screen & System Audio Recording.
2. **Automation (Spotify)** — optional; only needed for the Album-Art Chameleon. Denying it leaves everything else working.

If audio access is denied, the app shows an explainer with a button that jumps straight to the right System Settings pane, plus a retry that recovers without relaunching.

## Using it

- **Gear icon (top right)** — pattern picker, Chameleon toggle, manual colors, sensitivity and speed
- **Idle fade** — leave the mouse alone for a few seconds and the chrome and cursor disappear; move it and they come back
- **Fullscreen** — the green traffic-light button, or drag the window by its top edge to move it
- Settings persist across launches

### Patterns

| Pattern | What it does |
|---|---|
| Radial Bloom | Mirrored spectrum spokes around a pulsing ring, bass at the poles |
| Waveform Ribbons | Layered flowing lines, one per palette color |
| Particle Field | Beat-triggered bursts from the center, sized by bass |
| Bar Wall | Classic spectrum bars with falling peak caps |

## Development

The frontend lives in `web/` and is plain ES modules — no build step, no npm dependencies. For UI work you don't need to rebuild the app at all:

```bash
python3 -m http.server 8400 --directory web
# open http://localhost:8400/harness.html
```

The harness drives the same code with synthetic audio and fake track changes, so you can edit and refresh. Note that changes to `web/` **do** require re-running `bundle.sh` before they show up in the real app, since those files get copied into the bundle.

### Tests

```bash
swift run HomeWaveChecks              # FFT analysis, Spotify notification parsing
node --test web/tests/palette.test.js # album-art color extraction
```

There's no XCTest here — this project is built without Xcode, so the Swift tests are a plain-assert executable that exits non-zero on failure.

### Changing the icon

Replace `icon/AppIcon.png` with new square artwork, then:

```bash
swift scripts/make-icon.swift icon/AppIcon.png icon/AppIcon.icns
bash scripts/bundle.sh
```

## How it works

```
Core Audio process tap  →  ring buffer  →  vDSP FFT  →  64 log-spaced bands
                                                              ↓
Spotify notification  →  AppleScript artwork  →  base64  →  WKWebView
                                                              ↓
                                          palette extraction, theme crossfade,
                                          Canvas 2D pattern rendering at 60fps
```

A Swift/AppKit host does the work the web layer can't: it taps the system audio output mix, runs the FFT with Accelerate, and listens for Spotify's `PlaybackStateChanged` notifications. Audio frames and track events are pushed into a `WKWebView`, where vanilla JS renders everything.

| Path | Responsibility |
|---|---|
| `Sources/HomeWaveCore/` | Audio tap, FFT analysis, Spotify watcher — all the testable logic |
| `Sources/HomeWave/` | App shell: window, webview, JS bridge |
| `Sources/HomeWaveChecks/` | Plain-assert test executable |
| `web/js/patterns/` | The four visualizers |
| `web/js/palette.js` | Median-cut color extraction and theme crossfading |
| `scripts/bundle.sh` | The build |

## Notes

- The app is ad-hoc signed and not notarized — it's a personal build, not distributed.
- Moving the `.app` to a new location makes macOS ask for audio permission once more.

## License

MIT — see [LICENSE](LICENSE).
