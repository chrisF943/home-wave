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
    private var framesSinceBeat = 0

    public init(sampleRate: Float) {
        self.sampleRate = sampleRate
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        let minHz: Float = 40, maxHz: Float = 16_000
        let binHz = sampleRate / Float(Self.fftSize)
        // A 2048-point FFT resolves ~23 Hz per bin, but the bottom of a 64-band
        // log sweep from 40 Hz steps by only ~4 Hz — so several bands used to
        // floor onto the same bin and then move in perfect lockstep, reading as
        // a clump of spokes stuck at one length. Force each edge at least one
        // bin past the last so every band owns distinct spectrum.
        let maxBin = Self.fftSize / 2 - 1
        var previous = 0
        for i in 0...Self.bandCount {
            let hz = minHz * pow(maxHz / minHz, Float(i) / Float(Self.bandCount))
            previous = min(maxBin, max(previous + 1, min(maxBin, Int(hz / binHz))))
            bandEdges.append(previous)
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
            // Soft knee instead of a hard clamp: deep bass routinely drove the
            // old min(1, ...) flat, freezing those spokes at full length. tanh
            // approaches 1 without reaching it, so loud bands stay near the top
            // of their range but keep moving.
            bands[b] = tanh(log10(1 + sum / Float(hi - lo)) / 3.5 * 1.3)
        }

        // Beat: spectral flux over the low bands vs. its recent moving average.
        var flux: Float = 0
        for b in 0..<8 { flux += max(0, bands[b] - prevBands[b]) }
        prevBands = bands
        let avg = fluxHistory.reduce(0, +) / Float(fluxHistory.count)
        // The old absolute floor (0.08) sat below the median flux of real music,
        // so most frames cleared it and `beat` was near-permanently true — the
        // ring pulse never decayed and particles streamed instead of bursting.
        // Require a clear spike over the moving average, and enforce a refractory
        // gap so one transient cannot retrigger on consecutive frames: 12 frames
        // at 60 Hz caps the rate at 300 BPM, above any real tempo.
        framesSinceBeat += 1
        let beat = flux > 0.15 && flux > avg * 2.2 && framesSinceBeat >= 12
        if beat { framesSinceBeat = 0 }
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
