# HomeWave — macOS Music Visualizer — Design Spec

**Date:** 2026-07-19
**Status:** Approved by user (pending written-spec review)

## Overview

HomeWave is a macOS desktop app that visualizes whatever audio the Mac is playing. Visuals are curated patterns with user-tweakable colors, backgrounds, and motion settings. The twist is the **Album-Art Chameleon**: when Spotify is playing, HomeWave detects the current track, extracts a color palette from its album art, and auto-themes the visuals to match the song.

The app is a normal window the user can fullscreen — no wallpaper takeover.

## Goals

- React in real time (~60fps) to system audio output — not the microphone.
- Ship 4 curated visualizer patterns that look good out of the box.
- Per-pattern tweaks: colors, background, sensitivity, speed.
- Album-Art Chameleon for Spotify: instant track-change detection, palette extracted from artwork, smooth crossfade between themes.
- Frontend designed with the impeccable skill.

## Non-Goals

- No App Store distribution (local build; avoids sandbox restrictions on audio capture).
- No wallpaper/desktop takeover mode.
- No support for players other than Spotify (manual colors work with any audio source).
- No full layer-based scene editor — curated presets + tweaks only.
- No microphone input.

## Architecture

Single `.app` bundle. A Swift/AppKit host window contains one WKWebView that renders the entire UI and visuals. Swift handles everything the web layer cannot: audio capture, Spotify integration, and artwork download.

```
┌─────────────────────────── HomeWave.app ───────────────────────────┐
│  Swift host (AppKit)                                               │
│  ├── AudioEngine    — Core Audio process tap → FFT → frames        │
│  ├── SpotifyWatcher — distributed notifications + artwork fetch    │
│  └── Bridge         — WKWebView plumbing, both directions          │
│                          │ evaluateJavaScript (60fps frames,       │
│                          │ track events)                           │
│                          ▼                                         │
│  WKWebView frontend (vanilla JS ES modules, WebGL2/Canvas)         │
│  ├── Pattern modules (4)     ├── Palette engine                    │
│  ├── Settings panel          └── Now-playing chip                  │
└────────────────────────────────────────────────────────────────────┘
```

### AudioEngine (Swift)

- Captures the system output mix using a Core Audio process tap (`AudioHardwareCreateProcessTap` + aggregate device, macOS 14.2+). Triggers the one-time system audio-capture permission prompt (`NSAudioCaptureUsageDescription`).
- PCM buffers go into a ring buffer. On a display-link cadence (~60fps), Accelerate/vDSP computes an FFT, reduced to:
  - `bands`: 64 log-spaced frequency bins, normalized 0–1
  - `level`: overall RMS loudness
  - `beat`: boolean onset flag from spectral flux
- Emits one frame object per tick to the Bridge.

### SpotifyWatcher (Swift)

- Observes the `com.spotify.client.PlaybackStateChanged` distributed notification — Spotify broadcasts track name, artist, album, and play state on every change. No polling.
- On track change, runs AppleScript (`tell application "Spotify" to get artwork url of current track`) to get the artwork URL, downloads the image with URLSession, and base64-encodes it. Requires one-time Automation permission (`NSAppleEventsUsageDescription`).
- Emits a track event: `{ title, artist, album, playing, artDataURL }`.

### Bridge (Swift)

- Loads the frontend from the app bundle's Resources via `loadFileURL`.
- Swift → JS: `evaluateJavaScript` calling `window.homewave.onAudioFrame(frame)` and `window.homewave.onTrack(event)`. Frame payloads are small (64 floats + 2 scalars) so 60fps over this channel is fine.
- JS → Swift: one `WKScriptMessageHandler` accepting small commands. MVP commands: `retryAudioPermission`, `openSystemSettings`.

### Frontend (vanilla JS + WebGL2/Canvas)

No node build step — plain ES modules served from the bundle. This keeps the toolchain minimal and lets the impeccable skill iterate on the real files live in a browser.

- **Pattern modules.** Common interface: `init(canvas)`, `render(frame, palette, settings)`, `destroy()`. MVP ships 4: radial spectrum, waveform ribbons, particle field, bar wall. Exact visual direction comes from the impeccable design pass.
- **Palette engine.** Quantizes the album art (canvas-based median-cut or similar) into 4–5 dominant colors plus a background tone. Base64 data URLs from Swift avoid canvas CORS tainting. Palette changes crossfade over ~1s.
- **Settings panel.** Pattern picker, Chameleon toggle (auto art-palette vs manual), manual color pickers, background choice, sensitivity and speed sliders. Persisted in `localStorage`.
- **Now-playing chip.** Artwork thumbnail + track/artist. Fades out after a few seconds of no interaction; hidden entirely when Spotify isn't playing.
- **Dev harness.** A standalone page that drives patterns with synthetic audio (fake FFT frames, fake track events) so the frontend is fully designable and testable in a normal browser without the Swift host.

## Data Flow

1. Core Audio tap → ring buffer → FFT → `{bands, level, beat}` → `evaluateJavaScript` → active pattern's `render()`.
2. Spotify notification → AppleScript artwork URL → URLSession download → base64 → `onTrack` → palette engine extracts colors → theme crossfades.
3. Settings panel writes to `localStorage` and applies live; patterns read settings each frame.

## Error Handling

- **Audio permission denied:** frontend shows an explainer state with an "Open System Settings" button (JS → Swift command) and a retry button. Visualizer idles until permission granted.
- **Spotify not running / not installed:** no track events; chip hidden; manual colors active. Visualizer still reacts to any system audio.
- **Artwork fetch fails:** keep the previous palette (or manual colors). Track text still updates.
- **Silence:** patterns drift slowly in an idle ambient state rather than freezing.

## Testing

- **Swift unit tests:** FFT binning against synthetic sine waves (energy lands in the expected band); notification userInfo parsing; artwork-URL AppleScript result handling (mocked).
- **JS tests:** palette extraction against known fixture images; pattern interface conformance.
- **Dev harness:** manual and impeccable-driven iteration on patterns/UI with synthetic audio in a browser.
- **Manual end-to-end:** Spotify playing → permission prompts → visuals react → track change re-themes.

## Constraints & Tooling

- **macOS 14.2+** (process-tap API floor). Development machine runs macOS 26.
- **Xcode project generated with XcodeGen** if available; fallback is SPM executable + an app-bundling script. Settled during implementation planning.
- **Info.plist:** `NSAudioCaptureUsageDescription`, `NSAppleEventsUsageDescription`.
- Not sandboxed, not notarized for MVP — personal local build.
- GitNexus (`gitnexus analyze --skip-agents-md`) runs once the code is scaffolded, then stays current during development.
