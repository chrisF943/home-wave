# HomeWave — working notes

macOS music visualizer. Swift/AppKit host + WKWebView frontend. See `README.md` for what it does and how to run it; this file covers what you need to know before changing it.

## Environment constraints (these have bitten before)

- **No Xcode on this machine** — Command Line Tools only. `XCTest` and `swift-testing` do not exist here; `import XCTest` will not compile. Swift tests are a plain-assert executable, `Sources/HomeWaveChecks/`, run with `swift run HomeWaveChecks` (exit 0 = pass). Don't reintroduce XCTest.
- **No npm, no build step** for the frontend. `web/` is vanilla ES modules loaded directly. `web/package.json` exists only to set `"type": "module"` so `node --test` can parse the test file.
- **Node 24 mishandles `node --test <dir>`** — pass files explicitly: `node --test web/tests/palette.test.js`.
- **`NSLog` output does not surface via `log stream`** on this machine. To read app logs: `open --stdout /tmp/hw.log --stderr /tmp/hw.log build/HomeWave.app`.
- **Always test the bundled app**, never `swift run HomeWave` — TCC permissions are attributed to the bundle. `bash scripts/bundle.sh && open build/HomeWave.app`.
- macOS floor is **14.2** (Core Audio process-tap API). Package.swift pins it.
- Zero external Swift dependencies. Keep it that way.

## Architecture

Swift does what the web layer can't; everything visual is JS.

```
AudioTap (process tap) → RingBuffer → SpectrumAnalyzer (vDSP FFT)
                                            ↓ AudioFrame {bands[64], level, beat} @60fps
SpotifyWatcher (distributed notification + AppleScript artwork)
                                            ↓ TrackInfo + base64 art
                              AppDelegate bridge → WKWebView → app.js
```

**`Sources/HomeWaveCore/`** — library, all testable logic:
- `AudioTap.swift` — Core Audio process tap + private aggregate device. Fragile, hardware-dependent, not unit-testable; verify by ear/log.
- `RingBuffer.swift` — uses `OSAllocatedUnfairLock`, **not** `NSLock`: it's taken on the realtime IOProc thread and unfair locks donate priority.
- `SpectrumAnalyzer.swift` — 2048-point FFT → 64 log-spaced bands (40 Hz–16 kHz), RMS level, spectral-flux beat flag. Fast attack / slow decay smoothing.
- `AudioEngine.swift` — owns the tap + a 60 Hz timer. `start()` **must** be called on the main thread (has a `dispatchPrecondition`); the timer schedules on the caller's run loop.
- `SpotifyWatcher.swift` — observes `com.spotify.client.PlaybackStateChanged`. Artwork is fetched only on track-*id* change and cached; a stale-fetch guard drops out-of-order results on rapid skips.

**`Sources/HomeWave/`** — `AppDelegate.swift` is window + webview + bridge. Includes `WindowDragStrip`, an invisible top-edge view calling `performDrag` — the webview covers the full window (`.fullSizeContentView`) and would otherwise swallow every click, leaving no way to move the window.

**`web/js/`** — `app.js` (bridge glue, rAF loop, idle fade, accent sync), `palette.js` (median-cut extraction + `ThemeEngine` crossfade), `settings.js` (localStorage + panel binding), `patterns/*.js`.

## Contracts — don't break these silently

**Swift → JS:** `window.homewave.onAudioFrame(frame)`, `.onTrack(evt)`, `.onAudioStatus('ok'|'denied')`
**JS → Swift:** `webkit.messageHandlers.homewave.postMessage({cmd})`, `cmd ∈ {retryAudioPermission, openSystemSettings}`
**Frame:** `{ bands: number[64] (0–1), level: number (0–1), beat: boolean }`
**Track event:** `{ title, artist, album, playing, artDataURL? }`
**Theme:** `{ background: [r,g,b], colors: [[r,g,b]] × 4 }`
**Pattern module:** `{ id, name, init(canvas), render(frame, theme, settings, tMs), destroy() }`
**Settings keys:** `pattern, chameleon, colors[3 hex], background, sensitivity, speed` under localStorage `homewave-settings`

`index.html` and `harness.html` must stay byte-identical except their script tags — the harness is the only way to iterate on UI without rebuilding, and it silently rots if they drift. Verify with:

```bash
diff <(grep -v 'script type="module"' web/index.html) <(grep -v 'script type="module"' web/harness.html)
```

## Adding a pattern

Create `web/js/patterns/<name>.js` exporting the pattern interface, then add it to the array in `patterns/index.js`. Colors must come from the passed `theme` — never hardcode any, or the Chameleon stops working for that pattern. Respect `settings.sensitivity` and `settings.speed`. Patterns paint a translucent background fill each frame for motion trails; `init()` must reset all per-pattern state since it re-runs on every switch.

## Verify before claiming done

```bash
swift run HomeWaveChecks
node --test web/tests/palette.test.js
bash scripts/bundle.sh && open build/HomeWave.app
```

Rendering correctness can't be asserted from code — check it in the harness or the running app. Both permissions are already granted on this machine, so a launch that produces `audio status: ok` and visible reaction to playing audio is the real signal.

## Conventions

- Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `polish:`).
- Frontend design work goes through the `impeccable` skill.
- `.claude/`, `.claudeignore`, `.superpowers/`, `build/`, `.build/` are gitignored.
