# HomeWave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS app that visualizes system audio with 4 curated patterns, user tweaks, and an Album-Art Chameleon that auto-themes visuals from the current Spotify track's artwork.

**Architecture:** Swift/AppKit host (SPM: `HomeWaveCore` library + `HomeWave` executable) captures system audio via a Core Audio process tap, runs FFT with Accelerate, and watches Spotify's distributed notifications. It pushes JSON audio frames (~60fps) and track events into a WKWebView. The frontend is vanilla-JS ES modules rendering with Canvas 2D; a dev harness page drives it with synthetic audio so all frontend work is testable in a plain browser.

**Tech Stack:** Swift 6 toolchain (language mode 5 via tools-version 5.9), SPM, CoreAudio process tap, Accelerate/vDSP, WKWebView, NSAppleScript, vanilla JS ES modules, Canvas 2D, plain-assert Swift checks executable, `node --test`.

## Global Constraints

- macOS floor: **14.2** — `platforms: [.macOS("14.2")]` in Package.swift (process-tap API floor; dev machine runs macOS 26.5).
- Swift: `// swift-tools-version: 5.9`, **zero external Swift dependencies**.
- Swift checks: this machine has **no Xcode** — XCTest and swift-testing are unavailable. Swift tests live in a plain-assert executable target `HomeWaveChecks`; run with `swift run HomeWaveChecks` (exit 0 = all pass). Never `import XCTest` or `import Testing` anywhere.
- Frontend: vanilla ES modules only, **no build step, no npm dependencies**. Node used solely to run `node --test web/tests/`.
- Bundle ID: `com.homewave.app`. Ad-hoc codesign (`codesign --force --sign -`). Not sandboxed, not notarized.
- The app MUST be run as a bundled `.app` (via `scripts/bundle.sh` then `open build/HomeWave.app`) for TCC permission prompts to attribute correctly. `swift run` will not prompt properly.
- Audio frame shape (Swift `AudioFrame` == JS frame): `{ bands: [Float] × 64 (0–1), level: Float (0–1), beat: Bool }`.
- Track event shape: `{ title: String, artist: String, album: String, playing: Bool, artDataURL: String? }`.
- Commits: per-task commits approved by the user — run each task's commit step as written.
- JS tests import from `web/js/` — those modules must stay DOM-free (pure functions) except where noted.

## File Structure

```
HomeWave/
├── Package.swift
├── scripts/bundle.sh                     # swift build → .app bundle → codesign
├── Sources/
│   ├── HomeWaveCore/                     # library: all testable logic
│   │   ├── AudioFrame.swift
│   │   ├── SpectrumAnalyzer.swift        # FFT → bands/level/beat
│   │   ├── RingBuffer.swift
│   │   ├── AudioTap.swift                # Core Audio process tap + aggregate device
│   │   ├── AudioEngine.swift             # tap + ring buffer + 60Hz analysis timer
│   │   ├── TrackInfo.swift
│   │   ├── SpotifyNotificationParser.swift
│   │   └── SpotifyWatcher.swift          # distributed notifications + artwork fetch
│   ├── HomeWave/                         # thin executable
│   │   ├── main.swift
│   │   ├── AppDelegate.swift             # window + WKWebView + bridge
│   │   └── Info.plist                    # copied into bundle by bundle.sh
│   └── HomeWaveChecks/                   # plain-assert checks (no Xcode → no XCTest on this machine)
│       ├── main.swift                    # harness: check() helpers, exit 1 on any failure
│       ├── SpectrumAnalyzerChecks.swift
│       └── SpotifyParsingChecks.swift    # added in Task 4
└── web/
    ├── package.json                      # {"type": "module"} so node --test works
    ├── index.html
    ├── harness.html                      # index + synthetic audio driver
    ├── css/main.css
    ├── js/
    │   ├── app.js                        # boot, bridge glue, rAF loop, chip, overlay
    │   ├── settings.js                   # values + localStorage + panel binding
    │   ├── palette.js                    # ThemeEngine, manualTheme; Task 6 adds extractPalette/deriveTheme
    │   ├── color-utils.js                # hexToRgb, rgba, lerpRgb (pure)
    │   └── patterns/
    │       ├── index.js                  # registry
    │       ├── bars.js
    │       ├── radial.js                 # Task 7
    │       ├── ribbons.js                # Task 7
    │       └── particles.js              # Task 7
    ├── dev/synthetic.js                  # fake frames + fake tracks for harness
    └── tests/palette.test.js             # node --test
```

---

### Task 1: Project scaffold — SPM package, empty window app, bundle script, GitNexus

**Files:**
- Create: `Package.swift`
- Create: `Sources/HomeWaveCore/AudioFrame.swift`
- Create: `Sources/HomeWave/main.swift`
- Create: `Sources/HomeWave/AppDelegate.swift`
- Create: `Sources/HomeWave/Info.plist`
- Create: `scripts/bundle.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: `AudioFrame` (public struct, see code below) — used by Tasks 2, 3, 5.
- Produces: `scripts/bundle.sh` — every later task's manual verification uses `bash scripts/bundle.sh && open build/HomeWave.app`.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HomeWave",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "HomeWaveCore"),
        .executableTarget(
            name: "HomeWave",
            dependencies: ["HomeWaveCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "HomeWaveCoreTests", dependencies: ["HomeWaveCore"]),
    ]
)
```

- [ ] **Step 2: Write `Sources/HomeWaveCore/AudioFrame.swift`**

(The Core target needs at least one file to compile; AudioFrame is needed by Tasks 2/3/5 anyway.)

```swift
import Foundation

public struct AudioFrame: Codable, Equatable {
    public var bands: [Float]   // 64 log-spaced bands, 0...1
    public var level: Float     // overall loudness, 0...1
    public var beat: Bool       // onset flag

    public init(bands: [Float], level: Float, beat: Bool) {
        self.bands = bands
        self.level = level
        self.beat = beat
    }
}
```

- [ ] **Step 3: Write `Sources/HomeWave/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "Quit HomeWave",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

app.run()
```

- [ ] **Step 4: Write `Sources/HomeWave/AppDelegate.swift`** (window only — Task 5 replaces this file with the full bridge version)

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "HomeWave"
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

- [ ] **Step 5: Write `Sources/HomeWave/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.homewave.app</string>
    <key>CFBundleName</key><string>HomeWave</string>
    <key>CFBundleExecutable</key><string>HomeWave</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.2</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>HomeWave visualizes the audio your Mac is playing.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>HomeWave asks Spotify for the current track and its album artwork.</string>
</dict>
</plist>
```

- [ ] **Step 6: Write `scripts/bundle.sh`** and `chmod +x scripts/bundle.sh`

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/HomeWave.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HomeWave "$APP/Contents/MacOS/HomeWave"
cp Sources/HomeWave/Info.plist "$APP/Contents/Info.plist"
if [ -d web ]; then cp -R web "$APP/Contents/Resources/web"; fi
codesign --force --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 7: Write `.gitignore`**

```
.build/
build/
.DS_Store
*.xcodeproj
xcuserdata/
```

- [ ] **Step 8: Build and launch**

Run: `bash scripts/bundle.sh && open build/HomeWave.app`
Expected: build succeeds; an empty window titled "HomeWave" appears; Cmd+Q quits; green traffic-light button enters fullscreen.

- [ ] **Step 9: Initialize GitNexus** (user-requested at build start)

Run: `gitnexus analyze --skip-agents-md`
Expected: index created without errors (small codebase, fast).

- [ ] **Step 10: Commit** (only if user has re-enabled commits — see Global Constraints)

```bash
git add Package.swift Sources scripts .gitignore
git commit -m "feat: scaffold HomeWave SPM app with bundle script"
```

---

### Task 2: SpectrumAnalyzer — FFT → bands/level/beat (TDD)

**Files:**
- Create: `Sources/HomeWaveCore/SpectrumAnalyzer.swift`
- Create: `Sources/HomeWaveChecks/main.swift` (checks harness)
- Create: `Sources/HomeWaveChecks/SpectrumAnalyzerChecks.swift`
- Modify: `Package.swift` (swap the test target for the `HomeWaveChecks` executable target)
- Delete: `Tests/` (placeholder XCTest target — XCTest is unavailable without Xcode)

**Interfaces:**
- Consumes: `AudioFrame` from Task 1.
- Produces: `public final class SpectrumAnalyzer` — `init(sampleRate: Float)`, `func analyze(_ samples: [Float]) -> AudioFrame` (requires exactly `SpectrumAnalyzer.fftSize` samples), `static let fftSize = 2048`, `static let bandCount = 64`. Task 3's AudioEngine calls this.
- Produces: checks harness — `check(_ condition: Bool, _ label: String)`, `checkLess(_ a: Float, _ b: Float, _ label: String)`, `checkGreater(_ a: Float, _ b: Float, _ label: String)` in `Sources/HomeWaveChecks/main.swift`. Task 4 adds its own checks file to this target and a `runSpotifyParsingChecks()` call to main.swift.

- [ ] **Step 1: Replace the test target with the checks target in `Package.swift`**

Full new contents:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HomeWave",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "HomeWaveCore"),
        .executableTarget(
            name: "HomeWave",
            dependencies: ["HomeWaveCore"],
            exclude: ["Info.plist"]
        ),
        .executableTarget(name: "HomeWaveChecks", dependencies: ["HomeWaveCore"]),
    ]
)
```

Then delete the `Tests/` directory (`git rm -r Tests` if tracked).

- [ ] **Step 2: Write the failing checks (RED)**

`Sources/HomeWaveChecks/main.swift`:

```swift
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS: \(label)")
    } else {
        failures += 1
        print("FAIL: \(label)")
    }
}

func checkLess(_ a: Float, _ b: Float, _ label: String) {
    check(a < b, "\(label) (\(a) < \(b))")
}

func checkGreater(_ a: Float, _ b: Float, _ label: String) {
    check(a > b, "\(label) (\(a) > \(b))")
}

runSpectrumAnalyzerChecks()

if failures > 0 {
    print("\(failures) check(s) FAILED")
    exit(1)
}
print("All checks passed")
```

`Sources/HomeWaveChecks/SpectrumAnalyzerChecks.swift`:

```swift
import Foundation
import HomeWaveCore

private func sine(freq: Float, sampleRate: Float, count: Int, amp: Float = 0.5) -> [Float] {
    (0..<count).map { amp * sin(2 * .pi * freq * Float($0) / sampleRate) }
}

func runSpectrumAnalyzerChecks() {
    // Bands are log-spaced 40 Hz – 16 kHz over 64 bands:
    // band(1 kHz) = 64 * ln(1000/40) / ln(16000/40) ≈ 34
    let sr: Float = 48_000
    let analyzer = SpectrumAnalyzer(sampleRate: sr)
    let frame = analyzer.analyze(sine(freq: 1_000, sampleRate: sr, count: SpectrumAnalyzer.fftSize))
    let maxBand = frame.bands.firstIndex(of: frame.bands.max()!)!
    check((32...36).contains(maxBand), "1 kHz sine peaks in band 32...36 (got \(maxBand))")
    checkGreater(frame.level, 0.5, "sine level is loud")

    let quiet = SpectrumAnalyzer(sampleRate: 48_000)
    let silent = quiet.analyze([Float](repeating: 0, count: SpectrumAnalyzer.fftSize))
    checkLess(silent.level, 0.01, "silence level")
    checkLess(silent.bands.max()!, 0.01, "silence bands")
    check(!silent.beat, "silence has no beat")
    check(silent.bands.count == SpectrumAnalyzer.bandCount, "band count is 64")
}
```

Run: `swift run HomeWaveChecks`
Expected: BUILD FAILURE — `cannot find 'SpectrumAnalyzer' in scope`. The checks reference the class before it exists; this build failure is the RED step.

- [ ] **Step 3: Write `Sources/HomeWaveCore/SpectrumAnalyzer.swift` (GREEN implementation)**

```swift
import Accelerate
import Foundation

public final class SpectrumAnalyzer {
    public static let fftSize = 2048
    public static let bandCount = 64

    private let sampleRate: Float
    private let log2n = vDSP_Length(11) // 2^11 = 2048
    private let fftSetup: FFTSetup
    private var window = [Float](repeating: 0, count: SpectrumAnalyzer.fftSize)
    private var bandEdges: [Int] = []   // fft-bin index per band edge, bandCount + 1 entries
    private var smoothed = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var prevBands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var fluxHistory = [Float](repeating: 0, count: 43) // ~0.7s at 60fps
    private var fluxIndex = 0

    public init(sampleRate: Float) {
        self.sampleRate = sampleRate
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        let minHz: Float = 40, maxHz: Float = 16_000
        let binHz = sampleRate / Float(Self.fftSize)
        for i in 0...Self.bandCount {
            let hz = minHz * pow(maxHz / minHz, Float(i) / Float(Self.bandCount))
            bandEdges.append(min(Self.fftSize / 2 - 1, max(1, Int(hz / binHz))))
        }
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    public func analyze(_ samples: [Float]) -> AudioFrame {
        precondition(samples.count == Self.fftSize)

        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        var real = [Float](repeating: 0, count: Self.fftSize / 2)
        var imag = [Float](repeating: 0, count: Self.fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBytes {
                    vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &split, 1, vDSP_Length(Self.fftSize / 2))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(Self.fftSize / 2))
            }
        }

        var bands = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let lo = bandEdges[b], hi = max(lo + 1, bandEdges[b + 1])
            var sum: Float = 0
            for i in lo..<hi { sum += magnitudes[i] }
            bands[b] = min(1, log10(1 + sum / Float(hi - lo)) / 3.5)
        }

        // Beat: spectral flux over the low bands vs. its recent moving average.
        var flux: Float = 0
        for b in 0..<8 { flux += max(0, bands[b] - prevBands[b]) }
        prevBands = bands
        let avg = fluxHistory.reduce(0, +) / Float(fluxHistory.count)
        let beat = flux > 0.08 && flux > avg * 1.6
        fluxHistory[fluxIndex] = flux
        fluxIndex = (fluxIndex + 1) % fluxHistory.count

        // Fast attack, slow decay so visuals feel snappy but not jittery.
        for b in 0..<Self.bandCount {
            smoothed[b] = bands[b] > smoothed[b] ? bands[b] : smoothed[b] * 0.82
        }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(Self.fftSize))

        return AudioFrame(bands: smoothed, level: min(1, rms * 4), beat: beat)
    }
}
```

- [ ] **Step 4: Run checks to verify they pass**

Run: `swift run HomeWaveChecks`
Expected: exit 0; six `PASS:` lines ending with `All checks passed`. If the band-index check fails, print `frame.bands` and check the log-spacing math before touching tolerances.

- [ ] **Step 5: Commit**

```bash
git rm -r Tests
git add Package.swift Sources
git commit -m "feat: add FFT spectrum analyzer with beat detection"
```

---

### Task 3: AudioTap + AudioEngine — capture system audio

**Files:**
- Create: `Sources/HomeWaveCore/AudioTap.swift`
- Create: `Sources/HomeWaveCore/RingBuffer.swift`
- Create: `Sources/HomeWaveCore/AudioEngine.swift`
- Modify: `Sources/HomeWave/AppDelegate.swift` (temporary debug logging, removed in Task 5)

**Interfaces:**
- Consumes: `SpectrumAnalyzer` (Task 2), `AudioFrame` (Task 1).
- Produces: `public final class AudioEngine` — `init()`, `start()`, `stop()`, `var onFrame: ((AudioFrame) -> Void)?` (fires ~60Hz on main thread), `var onStatus: ((String) -> Void)?` (fires `"ok"` or `"denied"`). Task 5's AppDelegate consumes exactly this.

Hardware capture can't be unit-tested; this task is verified manually with real audio. The pieces around it (RingBuffer) are trivial and covered by the analyzer tests transitively.

- [ ] **Step 1: Write `Sources/HomeWaveCore/RingBuffer.swift`**

```swift
import os

final class RingBuffer {
    private var storage: [Float]
    private var writeIndex = 0
    // Unfair lock donates priority to the holder — safe to take on the
    // realtime Core Audio IOProc thread without inversion risk.
    private let lock = OSAllocatedUnfairLock()

    init(capacity: Int) {
        storage = [Float](repeating: 0, count: capacity)
    }

    func write(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        for s in samples {
            storage[writeIndex] = s
            writeIndex = (writeIndex + 1) % storage.count
        }
    }

    func latest(_ n: Int) -> [Float] {
        precondition(n <= storage.count)
        lock.lock(); defer { lock.unlock() }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = storage[(writeIndex - n + i + storage.count) % storage.count]
        }
        return out
    }
}
```

- [ ] **Step 2: Write `Sources/HomeWaveCore/AudioTap.swift`**

Core Audio process tap (macOS 14.2+): create a system-wide tap, wrap it in a private aggregate device anchored to the default output device, and read tapped buffers in an IOProc. First `AudioHardwareCreateProcessTap` call triggers the TCC audio-capture prompt (bundled app only).

```swift
import CoreAudio
import Foundation

enum AudioTapError: Error {
    case tapCreation(OSStatus)
    case format(OSStatus)
    case outputDevice(OSStatus)
    case aggregateCreation(OSStatus)
    case ioProc(OSStatus)
    case start(OSStatus)
}

final class AudioTap {
    private(set) var sampleRate: Float = 48_000
    var onSamples: (([Float]) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    func start() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &newTapID)
        guard status == noErr else { throw AudioTapError.tapCreation(status) }
        tapID = newTapID

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &asbd)
        guard status == noErr else { stop(); throw AudioTapError.format(status) }
        sampleRate = Float(asbd.mSampleRate)
        let channels = max(1, Int(asbd.mChannelsPerFrame))

        let outputUID = try defaultOutputDeviceUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "HomeWave-Tap",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [[
                kAudioSubTapUIDKey as String: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey as String: true,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else { stop(); throw AudioTapError.aggregateCreation(status) }

        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) {
            [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            for buffer in abl {
                guard let data = buffer.mData else { continue }
                let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                guard frameCount > 0 else { continue }
                let ptr = data.assumingMemoryBound(to: Float.self)
                var mono = [Float](repeating: 0, count: frameCount)
                for f in 0..<frameCount {
                    var sum: Float = 0
                    for c in 0..<channels { sum += ptr[f * channels + c] }
                    mono[f] = sum / Float(channels)
                }
                self.onSamples?(mono)
            }
        }
        guard status == noErr else { stop(); throw AudioTapError.ioProc(status) }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { stop(); throw AudioTapError.start(status) }
    }

    func stop() {
        if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw AudioTapError.outputDevice(status) }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &size, $0)
        }
        guard status == noErr else { throw AudioTapError.outputDevice(status) }
        return uid as String
    }
}
```

- [ ] **Step 3: Write `Sources/HomeWaveCore/AudioEngine.swift`**

```swift
import Foundation

public final class AudioEngine {
    public var onFrame: ((AudioFrame) -> Void)?
    public var onStatus: ((String) -> Void)?   // "ok" | "denied"

    private let tap = AudioTap()
    private let buffer = RingBuffer(capacity: 8192)
    private var analyzer: SpectrumAnalyzer?
    private var timer: Timer?

    public init() {}

    /// Must be called on the main thread: the 60Hz analysis timer is
    /// scheduled on the caller's run loop, and `onFrame` fires there.
    public func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        stop()
        do {
            tap.onSamples = { [buffer] samples in buffer.write(samples) }
            try tap.start()
            let analyzer = SpectrumAnalyzer(sampleRate: tap.sampleRate)
            self.analyzer = analyzer
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self, let analyzer = self.analyzer else { return }
                self.onFrame?(analyzer.analyze(self.buffer.latest(SpectrumAnalyzer.fftSize)))
            }
            onStatus?("ok")
        } catch {
            NSLog("AudioEngine start failed: \(error)")
            onStatus?("denied")
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        tap.stop()
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build`
Expected: succeeds, no warnings about missing CoreAudio symbols. If `CATapDescription` or `kAudioSubTapUIDKey` is unresolved, check the macOS SDK — these require the 14.2+ SDK (present on this machine).

- [ ] **Step 5: Add temporary debug logging to `Sources/HomeWave/AppDelegate.swift`**

Replace the whole file with:

```swift
import AppKit
import HomeWaveCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let engine = AudioEngine()
    private var frameCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "HomeWave"
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        engine.onStatus = { NSLog("audio status: \($0)") }
        engine.onFrame = { [weak self] frame in
            guard let self else { return }
            self.frameCount += 1
            if self.frameCount % 30 == 0 {
                NSLog("level=%.3f beat=%@ maxBand=%.3f",
                      frame.level, frame.beat ? "Y" : "n", frame.bands.max() ?? 0)
            }
        }
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

- [ ] **Step 6: Manual verification with real audio**

Run: `bash scripts/bundle.sh && open build/HomeWave.app`, then in another terminal: `log stream --predicate 'process == "HomeWave"' --style compact`
Expected:
1. On first launch macOS shows the audio-capture permission prompt ("HomeWave visualizes the audio your Mac is playing."). Allow it. (If the app was launched before the prompt plumbing worked, reset with `tccutil reset AudioCapture com.homewave.app`.)
2. `audio status: ok` appears in the log.
3. Play any music. Log shows `level=` values clearly > 0.05 moving with the music, occasional `beat=Y` on drum hits.
4. Pause music. `level` drops to ~0.000.

- [ ] **Step 7: Commit** (only if commits re-enabled)

```bash
git add Sources
git commit -m "feat: capture system audio via Core Audio process tap"
```

---

### Task 4: Spotify — notification parsing (TDD) + watcher with artwork fetch

**Files:**
- Create: `Sources/HomeWaveCore/TrackInfo.swift`
- Create: `Sources/HomeWaveCore/SpotifyNotificationParser.swift`
- Create: `Sources/HomeWaveCore/SpotifyWatcher.swift`
- Create: `Sources/HomeWaveChecks/SpotifyParsingChecks.swift`
- Modify: `Sources/HomeWaveChecks/main.swift` (add `runSpotifyParsingChecks()` call)

**Interfaces:**
- Produces: `public struct TrackInfo { id, title, artist, album: String; playing: Bool }` (memberwise public init).
- Produces: `SpotifyNotificationParser.parse(_ userInfo: [AnyHashable: Any]) -> TrackInfo?`.
- Produces: `public final class SpotifyWatcher` — `init()`, `start()`, `var onTrack: ((TrackInfo, String?) -> Void)?` (second arg = artwork data-URL or nil, fired on main thread). Task 5 consumes this.

- [ ] **Step 1: Write the failing checks** — `Sources/HomeWaveChecks/SpotifyParsingChecks.swift`

```swift
import Foundation
import HomeWaveCore

func runSpotifyParsingChecks() {
    let playing = SpotifyNotificationParser.parse([
        "Name": "Song", "Artist": "Artist", "Album": "Album",
        "Player State": "Playing", "Track ID": "spotify:track:abc",
    ])
    check(playing == TrackInfo(id: "spotify:track:abc", title: "Song",
                               artist: "Artist", album: "Album", playing: true),
          "playing notification parsed")

    let paused = SpotifyNotificationParser.parse([
        "Name": "Song", "Player State": "Paused", "Track ID": "spotify:track:abc",
    ])
    check(paused?.playing == false, "paused state parsed")
    check(paused?.artist == "", "missing artist defaults to empty")

    check(SpotifyNotificationParser.parse(["Name": "x"]) == nil,
          "missing player state returns nil")
}
```

And in `Sources/HomeWaveChecks/main.swift`, add the call after the analyzer checks:

```swift
// old
runSpectrumAnalyzerChecks()
// new
runSpectrumAnalyzerChecks()
runSpotifyParsingChecks()
```

- [ ] **Step 2: Run checks to verify they fail (RED)**

Run: `swift run HomeWaveChecks`
Expected: BUILD FAILURE — `cannot find 'SpotifyNotificationParser' in scope`

- [ ] **Step 3: Write `Sources/HomeWaveCore/TrackInfo.swift`**

```swift
public struct TrackInfo: Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var playing: Bool

    public init(id: String, title: String, artist: String, album: String, playing: Bool) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.playing = playing
    }
}
```

- [ ] **Step 4: Write `Sources/HomeWaveCore/SpotifyNotificationParser.swift`**

```swift
public enum SpotifyNotificationParser {
    public static func parse(_ userInfo: [AnyHashable: Any]) -> TrackInfo? {
        guard let state = userInfo["Player State"] as? String else { return nil }
        return TrackInfo(
            id: userInfo["Track ID"] as? String ?? "",
            title: userInfo["Name"] as? String ?? "",
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            playing: state == "Playing")
    }
}
```

- [ ] **Step 5: Run checks to verify they pass**

Run: `swift run HomeWaveChecks`
Expected: exit 0; the six analyzer checks plus four new parser checks all `PASS:`, ending `All checks passed`

- [ ] **Step 6: Write `Sources/HomeWaveCore/SpotifyWatcher.swift`**

Artwork is fetched only when the track id changes; repeat notifications for the same track reuse the cached data-URL. AppleScript runs on the main thread (NSAppleScript is not thread-safe); the image download is async.

```swift
import AppKit
import Foundation

public final class SpotifyWatcher {
    public var onTrack: ((TrackInfo, String?) -> Void)?

    private var lastTrackID = ""
    private var cachedArtDataURL: String?

    public init() {}

    public func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let info = SpotifyNotificationParser.parse(note.userInfo ?? [:]) else { return }
            if !info.id.isEmpty, info.id != self.lastTrackID {
                self.lastTrackID = info.id
                self.cachedArtDataURL = nil
                self.fetchArtwork { [weak self] dataURL in
                    guard let self else { return }
                    // A rapid skip can start a newer fetch before this one
                    // returns — drop the stale result.
                    guard info.id == self.lastTrackID else { return }
                    self.cachedArtDataURL = dataURL
                    self.onTrack?(info, dataURL)
                }
            } else {
                self.onTrack?(info, self.cachedArtDataURL)
            }
        }
    }

    private func fetchArtwork(completion: @escaping (String?) -> Void) {
        // First run triggers the Automation ("Apple Events") permission prompt for Spotify.
        let source = "tell application \"Spotify\" to get artwork url of current track"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let urlString = script.executeAndReturnError(&errorInfo).stringValue,
              let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let dataURL = data.map { "data:image/jpeg;base64," + $0.base64EncodedString() }
            DispatchQueue.main.async { completion(dataURL) }
        }.resume()
    }
}
```

- [ ] **Step 7: Manual verification**

Add two lines to `AppDelegate.applicationDidFinishLaunching` (temporary, replaced in Task 5) after `engine.start()`:

```swift
        let spotify = SpotifyWatcher()
        spotify.onTrack = { info, art in
            NSLog("track: %@ — %@ (playing=%@) art=%@", info.artist, info.title,
                  info.playing ? "Y" : "n", art == nil ? "none" : "\(art!.count) chars")
        }
        spotify.start()
        self.spotifyRef = spotify
```

And add the property `var spotifyRef: SpotifyWatcher?` to AppDelegate (the watcher must be retained).

Run: `bash scripts/bundle.sh && open build/HomeWave.app` with `log stream --predicate 'process == "HomeWave"' --style compact` in another terminal. In Spotify: play a song, skip to another.
Expected:
1. On first track change, macOS shows the Automation prompt for Spotify ("HomeWave asks Spotify for the current track..."). Allow.
2. Log shows `track: <artist> — <title> (playing=Y) art=<N> chars` with N in the tens of thousands.
3. Pause in Spotify → log line with `playing=n`.

- [ ] **Step 8: Commit** (only if commits re-enabled)

```bash
git add Sources
git commit -m "feat: add Spotify track watcher with artwork fetch"
```

---

### Task 5: Bridge + frontend skeleton — end-to-end visualizer

**Files:**
- Create: `web/package.json`, `web/index.html`, `web/harness.html`, `web/css/main.css`
- Create: `web/js/app.js`, `web/js/settings.js`, `web/js/palette.js`, `web/js/color-utils.js`
- Create: `web/js/patterns/index.js`, `web/js/patterns/bars.js`
- Create: `web/dev/synthetic.js`
- Modify: `Sources/HomeWave/AppDelegate.swift` (full replacement — final form)

**Interfaces:**
- Consumes: `AudioEngine` (Task 3), `SpotifyWatcher` + `TrackInfo` (Task 4).
- Produces (JS globals the Swift side calls): `window.homewave.onAudioFrame(frame)`, `window.homewave.onTrack(evt)`, `window.homewave.onAudioStatus('ok'|'denied')`.
- Produces (JS→Swift): `webkit.messageHandlers.homewave.postMessage({cmd})` with cmd ∈ `retryAudioPermission`, `openSystemSettings`.
- Produces (JS internal, used by Tasks 6–7): pattern interface `{ id, name, init(canvas), render(frame, theme, settings, tMs), destroy() }`; theme shape `{ background: [r,g,b], colors: [[r,g,b]] × 4 }`; `Settings.values` = `{ pattern, chameleon, colors: [hex × 3], background: hex, sensitivity, speed }`; exports `ThemeEngine`, `manualTheme` from `palette.js`; `hexToRgb`, `rgba`, `lerpRgb` from `color-utils.js`.

- [ ] **Step 1: Write `web/package.json`**

```json
{
  "name": "homewave-web",
  "private": true,
  "type": "module"
}
```

- [ ] **Step 2: Write `web/js/color-utils.js`**

```js
export function hexToRgb(hex) {
  const v = hex.replace('#', '');
  const full = v.length === 3 ? v.split('').map(c => c + c).join('') : v;
  const n = parseInt(full, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function rgba([r, g, b], a = 1) {
  return `rgba(${r}, ${g}, ${b}, ${a})`;
}

export function lerpRgb(a, b, t) {
  return [0, 1, 2].map(i => Math.round(a[i] + (b[i] - a[i]) * t));
}
```

- [ ] **Step 3: Write `web/js/palette.js`** (Task 6 appends `extractPalette`/`deriveTheme` to this file)

```js
import { hexToRgb, lerpRgb } from './color-utils.js';

export function manualTheme(values) {
  const colors = values.colors.map(hexToRgb);
  while (colors.length < 4) colors.push(colors[colors.length % values.colors.length]);
  return { background: hexToRgb(values.background), colors };
}

export class ThemeEngine {
  constructor() {
    this.from = null;
    this.to = null;
    this.key = '';
    this.startMs = 0;
    this.durationMs = 1000;
  }

  setTargetIfChanged(theme, nowMs) {
    const key = JSON.stringify(theme);
    if (key === this.key) return;
    this.from = this.current(nowMs) ?? theme;
    this.to = theme;
    this.key = key;
    this.startMs = nowMs;
  }

  current(nowMs) {
    if (!this.to) return null;
    const t = Math.min(1, (nowMs - this.startMs) / this.durationMs);
    return {
      background: lerpRgb(this.from.background, this.to.background, t),
      colors: this.to.colors.map((c, i) =>
        lerpRgb(this.from.colors[i % this.from.colors.length], c, t)),
    };
  }
}
```

- [ ] **Step 4: Write `web/js/settings.js`**

```js
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
```

- [ ] **Step 5: Write `web/js/patterns/bars.js`**

```js
import { rgba, lerpRgb } from '../color-utils.js';

export default {
  id: 'bars',
  name: 'Bar Wall',

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.peaks = null;
  },

  render(frame, theme, settings, tMs) {
    const { ctx } = this;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    const n = frame.bands.length;
    if (!this.peaks || this.peaks.length !== n) this.peaks = new Array(n).fill(0);

    ctx.fillStyle = rgba(theme.background, 1);
    ctx.fillRect(0, 0, w, h);

    const bw = w / n;
    for (let i = 0; i < n; i++) {
      const v = Math.min(1, frame.bands[i] * settings.sensitivity);
      this.peaks[i] = Math.max(this.peaks[i] - 0.007 * settings.speed, v);
      const pos = i / (n - 1) * (theme.colors.length - 1);
      const c = lerpRgb(theme.colors[Math.floor(pos)],
                        theme.colors[Math.min(theme.colors.length - 1, Math.ceil(pos))],
                        pos % 1);
      const bh = v * h * 0.85;
      ctx.fillStyle = rgba(c, 0.95);
      ctx.fillRect(i * bw + 1, h - bh, Math.max(1, bw - 2), bh);
      ctx.fillStyle = rgba(c, 0.6);
      ctx.fillRect(i * bw + 1, h - this.peaks[i] * h * 0.85 - 3, Math.max(1, bw - 2), 2);
    }
  },

  destroy() {},
};
```

- [ ] **Step 6: Write `web/js/patterns/index.js`** (Task 7 replaces this with the full registry)

```js
import bars from './bars.js';

export const patterns = [bars];
```

- [ ] **Step 7: Write `web/js/app.js`**

```js
import { patterns } from './patterns/index.js';
import { Settings, bindPanel } from './settings.js';
import { ThemeEngine, manualTheme } from './palette.js';

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

window.homewave = {
  onAudioFrame(frame) { latestFrame = frame; },
  onTrack(evt) {
    updateChip(evt);
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
```

- [ ] **Step 8: Write `web/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>HomeWave</title>
<link rel="stylesheet" href="css/main.css">
</head>
<body>
<canvas id="viz"></canvas>

<div id="now-playing" class="chip hidden">
  <img id="np-art" alt="">
  <div>
    <div id="np-title"></div>
    <div id="np-artist"></div>
  </div>
</div>

<button id="settings-toggle" aria-label="Settings">⚙</button>

<aside id="settings-panel" class="hidden">
  <h2>Settings</h2>
  <label>Pattern <select id="set-pattern"></select></label>
  <label><input type="checkbox" id="set-chameleon"> Album-art colors</label>
  <label>Color 1 <input type="color" id="set-color-0"></label>
  <label>Color 2 <input type="color" id="set-color-1"></label>
  <label>Color 3 <input type="color" id="set-color-2"></label>
  <label>Background <input type="color" id="set-background"></label>
  <label>Sensitivity <input type="range" id="set-sensitivity" min="0.4" max="2.5" step="0.05"></label>
  <label>Speed <input type="range" id="set-speed" min="0.3" max="2.5" step="0.05"></label>
</aside>

<div id="permission-overlay" class="overlay hidden">
  <div class="overlay-card">
    <h1>HomeWave needs audio access</h1>
    <p>macOS blocks system-audio capture until you allow it. Enable HomeWave under
       System Settings → Privacy &amp; Security → Screen &amp; System Audio Recording,
       then retry.</p>
    <button id="open-settings">Open System Settings</button>
    <button id="retry-audio">Retry</button>
  </div>
</div>

<script type="module" src="js/app.js"></script>
</body>
</html>
```

- [ ] **Step 9: Write `web/css/main.css`** (functional baseline — Task 8's impeccable pass owns the real design)

```css
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { height: 100%; overflow: hidden; background: #000; }
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #eee; }
#viz { position: fixed; inset: 0; width: 100vw; height: 100vh; display: block; }
.hidden { display: none !important; }

.chip { position: fixed; top: 16px; left: 16px; display: flex; gap: 10px; align-items: center;
  background: rgba(10, 10, 14, 0.72); padding: 10px 14px; border-radius: 12px;
  backdrop-filter: blur(12px); }
.chip img { width: 44px; height: 44px; border-radius: 8px; }
#np-title { font-size: 14px; font-weight: 600; }
#np-artist { font-size: 12px; opacity: 0.7; }

#settings-toggle { position: fixed; top: 16px; right: 16px; width: 36px; height: 36px;
  border-radius: 50%; border: none; background: rgba(10, 10, 14, 0.72); color: #eee;
  font-size: 16px; cursor: pointer; }
#settings-panel { position: fixed; top: 0; right: 0; bottom: 0; width: 280px;
  padding: 24px 20px; background: rgba(12, 12, 16, 0.92); backdrop-filter: blur(18px);
  overflow-y: auto; }
#settings-panel h2 { font-size: 15px; margin-bottom: 16px; }
#settings-panel label { display: flex; justify-content: space-between; align-items: center;
  font-size: 13px; margin-bottom: 14px; gap: 8px; }

.overlay { position: fixed; inset: 0; display: flex; align-items: center;
  justify-content: center; background: rgba(0, 0, 0, 0.75); }
.overlay-card { max-width: 380px; padding: 28px; border-radius: 16px; background: #16161c;
  text-align: center; }
.overlay-card h1 { font-size: 18px; margin-bottom: 10px; }
.overlay-card p { font-size: 13px; opacity: 0.8; margin-bottom: 18px; line-height: 1.5; }
.overlay-card button { margin: 0 6px; padding: 8px 14px; border-radius: 8px; border: none;
  cursor: pointer; background: #3b3b46; color: #fff; font-size: 13px; }
```

- [ ] **Step 10: Write `web/dev/synthetic.js`**

```js
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
```

- [ ] **Step 11: Write `web/harness.html`** — identical to `index.html` except the closing scripts:

```html
<script type="module" src="js/app.js"></script>
<script type="module" src="dev/synthetic.js"></script>
```

(Copy `index.html`, replace the single script tag with these two lines. Everything else byte-identical.)

- [ ] **Step 12: Verify the harness in a browser**

Run: `python3 -m http.server 8400 --directory web` (fallback: `npx serve web`), open `http://localhost:8400/harness.html`
Expected: bars pattern pulsing to the synthetic beat; now-playing chip cycling fake tracks every 12s with gradient artwork; gear opens settings; changing colors changes bar colors (Chameleon toggle off — artTheme wiring lands in Task 6, so with it on colors stay manual for now); sensitivity/speed sliders have visible effect; settings survive reload.

- [ ] **Step 13: Replace `Sources/HomeWave/AppDelegate.swift` with the final bridge version**

```swift
import AppKit
import HomeWaveCore
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let engine = AudioEngine()
    let spotify = SpotifyWatcher()
    private let frameEncoder = JSONEncoder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "HomeWave"
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary]

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "homewave")
        // file:// pages need these to import ES modules and read canvas pixels.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(webView)

        let dir = webDirectoryURL()
        webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Start feeds only once the page is ready to receive them.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        engine.onStatus = { [weak self] status in
            self?.push("window.homewave && window.homewave.onAudioStatus('\(status)')")
        }
        engine.onFrame = { [weak self] frame in self?.pushFrame(frame) }
        engine.start()

        spotify.onTrack = { [weak self] info, art in self?.pushTrack(info, artDataURL: art) }
        spotify.start()
    }

    private func webDirectoryURL() -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) {
            return bundled
        }
        // Dev fallback for `swift run` from the repo root.
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("web")
    }

    private func push(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func pushFrame(_ frame: AudioFrame) {
        guard let data = try? frameEncoder.encode(frame),
              let json = String(data: data, encoding: .utf8) else { return }
        push("window.homewave && window.homewave.onAudioFrame(\(json))")
    }

    private func pushTrack(_ info: TrackInfo, artDataURL: String?) {
        var dict: [String: Any] = [
            "title": info.title, "artist": info.artist,
            "album": info.album, "playing": info.playing,
        ]
        if let artDataURL { dict["artDataURL"] = artDataURL }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return }
        push("window.homewave && window.homewave.onTrack(\(json))")
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "homewave",
              let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "retryAudioPermission":
            engine.start()
        case "openSystemSettings":
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) { engine.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

- [ ] **Step 14: End-to-end manual verification**

Run: `bash scripts/bundle.sh && open build/HomeWave.app`
Expected:
1. App opens showing the bars pattern (black background until audio flows).
2. Play music in Spotify: bars react in real time; now-playing chip shows artwork + title/artist.
3. Skip track: chip updates within ~1s.
4. Toggle fullscreen (green button): canvas fills the screen, still reactive.
5. Settings: pattern list shows "Bar Wall"; color changes apply live (Chameleon toggle has no effect yet — Task 6).
6. If audio permission was denied: overlay appears; "Open System Settings" jumps to Privacy; "Retry" recovers after granting.

- [ ] **Step 15: Commit** (only if commits re-enabled)

```bash
git add Sources web
git commit -m "feat: bridge audio + Spotify into web frontend with bars pattern"
```

---

### Task 6: Palette engine — Album-Art Chameleon (TDD)

**Files:**
- Modify: `web/js/palette.js` (append two functions)
- Modify: `web/js/app.js` (wire art → theme)
- Test: `web/tests/palette.test.js`

**Interfaces:**
- Consumes: `color-utils.js` helpers, `ThemeEngine` (Task 5).
- Produces: `extractPalette(pixels: Uint8ClampedArray, count = 5) -> [[r,g,b]]` (sorted by dominance) and `deriveTheme(swatches: [[r,g,b]]) -> { background, colors[4] }` — both pure, node-testable.

- [ ] **Step 1: Write the failing tests** — `web/tests/palette.test.js`

```js
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test web/tests/`
Expected: FAIL — `extractPalette` is not exported

- [ ] **Step 3: Append to `web/js/palette.js`**

```js
// --- Album-Art Chameleon ---------------------------------------------------

function widestAxis(box) {
  let best = 0, bestRange = -1;
  for (let axis = 0; axis < 3; axis++) {
    let lo = 255, hi = 0;
    for (const p of box) {
      if (p[axis] < lo) lo = p[axis];
      if (p[axis] > hi) hi = p[axis];
    }
    if (hi - lo > bestRange) { bestRange = hi - lo; best = axis; }
  }
  return best;
}

function spread(box) {
  let total = 0;
  for (let axis = 0; axis < 3; axis++) {
    let lo = 255, hi = 0;
    for (const p of box) {
      if (p[axis] < lo) lo = p[axis];
      if (p[axis] > hi) hi = p[axis];
    }
    total = Math.max(total, hi - lo);
  }
  return total;
}

function average(box) {
  const sum = [0, 0, 0];
  for (const p of box) { sum[0] += p[0]; sum[1] += p[1]; sum[2] += p[2]; }
  return sum.map(v => Math.round(v / box.length));
}

// Median-cut quantization over RGBA pixel data. Returns swatches sorted by
// population (most dominant first).
export function extractPalette(pixels, count = 5) {
  const pts = [];
  for (let i = 0; i < pixels.length; i += 16) { // sample every 4th pixel
    if (pixels[i + 3] < 128) continue;
    pts.push([pixels[i], pixels[i + 1], pixels[i + 2]]);
  }
  if (pts.length === 0) return [[128, 128, 128]];

  let boxes = [pts];
  while (boxes.length < count) {
    boxes.sort((a, b) => spread(b) - spread(a));
    const box = boxes[0];
    if (box.length < 2 || spread(box) === 0) break;
    boxes.shift();
    const axis = widestAxis(box);
    box.sort((p, q) => p[axis] - q[axis]);
    const mid = box.length >> 1;
    boxes.push(box.slice(0, mid), box.slice(mid));
  }
  return boxes
    .sort((a, b) => b.length - a.length)
    .map(average);
}

export function deriveTheme(swatches) {
  const luma = c => 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2];
  const sat = c => Math.max(...c) - Math.min(...c);
  const darkest = [...swatches].sort((a, b) => luma(a) - luma(b))[0];
  const background = darkest.map(v => Math.round(v * 0.25));
  let colors = swatches
    .filter(c => c !== darkest)
    .sort((a, b) => (sat(b) + luma(b) * 0.3) - (sat(a) + luma(a) * 0.3))
    .slice(0, 4);
  if (colors.length === 0) colors = [swatches[0]];
  const n = colors.length;
  while (colors.length < 4) colors.push(colors[colors.length % n]);
  return { background, colors };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test web/tests/`
Expected: PASS (3 tests)

- [ ] **Step 5: Wire artwork → theme in `web/js/app.js`**

Edit 1 — extend the palette import:

```js
// old
import { ThemeEngine, manualTheme } from './palette.js';
// new
import { ThemeEngine, manualTheme, extractPalette, deriveTheme } from './palette.js';
```

Edit 2 — replace the `onTrack` handler inside `window.homewave`:

```js
// old
  onTrack(evt) {
    updateChip(evt);
  },
// new
  onTrack(evt) {
    updateChip(evt);
    if (evt.artDataURL) loadArtTheme(evt.artDataURL);
  },
```

Edit 3 — add below `updateChip`:

```js
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
```

(On decode/extract failure nothing runs, so `artTheme` keeps its previous value — spec's "artwork fetch fails → keep previous palette" behavior.)

- [ ] **Step 6: Verify in the harness**

Run: `python3 -m http.server 8400 --directory web`, open `http://localhost:8400/harness.html`
Expected: with Chameleon toggle ON, every 12s the fake track changes and the entire visualization crossfades (~1s) to colors clearly derived from the gradient artwork; toggle OFF → snaps back to manual colors.

- [ ] **Step 7: Verify in the app**

Run: `bash scripts/bundle.sh && open build/HomeWave.app`, play Spotify, skip between albums with different artwork.
Expected: visuals re-theme to each album's colors within ~1–2s of the skip.

- [ ] **Step 8: Commit** (only if commits re-enabled)

```bash
git add web
git commit -m "feat: add album-art chameleon palette extraction"
```

---

### Task 7: Remaining patterns — radial, ribbons, particles

**Files:**
- Create: `web/js/patterns/radial.js`
- Create: `web/js/patterns/ribbons.js`
- Create: `web/js/patterns/particles.js`
- Modify: `web/js/patterns/index.js`

**Interfaces:**
- Consumes: pattern interface, theme shape, `settings.values`, `color-utils.js` (all Task 5).
- Produces: pattern ids `radial`, `ribbons`, `particles` in the registry (radial first — it's the `DEFAULTS.pattern`).

- [ ] **Step 1: Write `web/js/patterns/radial.js`**

```js
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
```

- [ ] **Step 2: Write `web/js/patterns/ribbons.js`**

```js
import { rgba } from '../color-utils.js';

export default {
  id: 'ribbons',
  name: 'Waveform Ribbons',

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
  },

  render(frame, theme, settings, tMs) {
    const { ctx } = this;
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    ctx.fillStyle = rgba(theme.background, 0.18);
    ctx.fillRect(0, 0, w, h);

    const layers = Math.min(4, theme.colors.length);
    const n = frame.bands.length;
    const t = tMs * 0.001 * settings.speed;
    ctx.lineJoin = 'round';
    for (let k = 0; k < layers; k++) {
      const baseY = h * (0.28 + 0.15 * k);
      const steps = 90;
      ctx.beginPath();
      for (let s = 0; s <= steps; s++) {
        const f = s / steps;
        const v = Math.min(1, frame.bands[Math.floor(f * (n - 1))] * settings.sensitivity);
        const y = baseY
          + Math.sin(f * 5 + t * (0.6 + k * 0.2) + k * 1.7) * h * 0.03
          + v * h * 0.16 * (k % 2 ? -1 : 1);
        if (s === 0) ctx.moveTo(f * w, y); else ctx.lineTo(f * w, y);
      }
      // glow pass + core pass
      ctx.strokeStyle = rgba(theme.colors[k], 0.14);
      ctx.lineWidth = 7;
      ctx.stroke();
      ctx.strokeStyle = rgba(theme.colors[k], 0.85);
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  },

  destroy() {},
};
```

- [ ] **Step 3: Write `web/js/patterns/particles.js`**

```js
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
```

- [ ] **Step 4: Replace `web/js/patterns/index.js`**

```js
import radial from './radial.js';
import ribbons from './ribbons.js';
import particles from './particles.js';
import bars from './bars.js';

export const patterns = [radial, ribbons, particles, bars];
```

- [ ] **Step 5: Verify in the harness**

Run: `python3 -m http.server 8400 --directory web`, open `http://localhost:8400/harness.html`
Expected: pattern dropdown lists all four; each renders and reacts to the synthetic beat (radial: rotating spokes + beat pulse; ribbons: flowing layered lines; particles: beat bursts from center; bars: unchanged). Switching patterns doesn't leak trails or throw in the console. With no audio (comment out the `setInterval` feeding frames, reload) radial still rotates slowly and particles still trickle — idle drift.

- [ ] **Step 6: Verify in the app**

Run: `bash scripts/bundle.sh && open build/HomeWave.app`, play music, cycle all four patterns.
Expected: all four react to real audio at fullscreen without stutter (Activity Monitor: HomeWave GPU/CPU not pegged).

- [ ] **Step 7: Commit** (only if commits re-enabled)

```bash
git add web/js/patterns
git commit -m "feat: add radial, ribbons, and particle patterns"
```

---

### Task 8: Impeccable design pass (main session — not a subagent)

**Files:**
- Modify: `web/css/main.css`, `web/index.html`, `web/harness.html`, and any `web/js/` files the design pass touches.

**Interfaces:**
- Consumes: the complete working frontend (Tasks 5–7).
- Produces: the shipped visual design. Must NOT change: the `window.homewave.*` API, the JS→Swift command names, the pattern interface, the settings keys, or file locations (bundle.sh copies `web/` wholesale).

This task runs in the **main session** because it invokes a skill. Per the user's global CLAUDE.md, frontend design from scratch goes through the impeccable skill.

- [ ] **Step 1: Start the harness server**

Run: `python3 -m http.server 8400 --directory web`
Expected: `http://localhost:8400/harness.html` serves the app with synthetic audio.

- [ ] **Step 2: Invoke the impeccable skill** (`impeccable:impeccable`) with this scope:

> Design the HomeWave visualizer frontend at `web/` (live at http://localhost:8400/harness.html — synthetic audio + fake tracks drive it, no backend needed). In scope: settings panel, now-playing chip (including a fade-out after a few seconds of no mouse movement, per spec), permission overlay, settings-toggle button, typography, spacing, motion polish, and aesthetic refinement of the four canvas patterns (colors always come from the active theme — keep the theme/palette pipeline intact). Out of scope / must not change: `window.homewave.*` API shape, `webkit.messageHandlers.homewave` command names, pattern module interface (`id/name/init/render/destroy`), `Settings` keys, file paths. The UI ships inside a WKWebView on macOS — target that rendering engine; hover states allowed.

- [ ] **Step 3: Re-run frontend checks after the pass**

Run: `node --test web/tests/`
Expected: PASS — the design pass must not break palette logic.

- [ ] **Step 4: Verify in the app**

Run: `bash scripts/bundle.sh && open build/HomeWave.app`
Expected: redesigned UI renders correctly in the WKWebView (backdrop-filter, fonts, layout all intact); everything from Task 5 Step 14 still works; chip fades out after a few seconds without mouse movement and returns on movement.

- [ ] **Step 5: Commit** (only if commits re-enabled)

```bash
git add web
git commit -m "feat: impeccable design pass on visualizer UI"
```

---

### Task 9: Final verification

**Files:** none created — verification only, fixes as needed.

- [ ] **Step 1: Full automated test suite**

Run: `swift run HomeWaveChecks && node --test web/tests/*.test.js`
Expected: all PASS (checks exit 0, node tests green). (Node 24 mishandles bare directory args to `--test` — pass the files explicitly.)

- [ ] **Step 2: Clean-build the bundle**

Run: `rm -rf .build build && bash scripts/bundle.sh`
Expected: builds from scratch without errors; `build/HomeWave.app` exists and is signed (`codesign -dv build/HomeWave.app` shows adhoc signature).

- [ ] **Step 3: Full manual acceptance checklist**

Run: `open build/HomeWave.app` and walk through:
1. Fresh launch → visuals idle-drift on the default radial pattern.
2. Play Spotify → visuals react; chip shows track + artwork; Chameleon re-themes visuals.
3. Skip through 3+ tracks with different artwork → theme crossfades each time, no flashes of wrong color, no console errors (Develop menu → Web Inspector).
4. Chameleon OFF → manual colors apply immediately; color pickers live-update; ON → back to art colors.
5. All four patterns react; switching is clean.
6. Sensitivity + speed sliders visibly change behavior; settings survive app relaunch.
7. Fullscreen works; visuals fill screen without stutter.
8. Quit Spotify → chip disappears (paused state) and visuals continue on any other audio (play a YouTube video — visuals react; Chameleon keeps last/manual palette).
9. Permission flow: `tccutil reset AudioCapture com.homewave.app`, relaunch → prompt appears; deny → overlay shows; System Settings button opens Privacy pane; allow + Retry → recovers without relaunch.

- [ ] **Step 4: Reindex GitNexus**

Run: `gitnexus analyze --skip-agents-md`
Expected: index updated over the full codebase.

- [ ] **Step 5: Report** — summarize checklist results to the user; list any deviations.
