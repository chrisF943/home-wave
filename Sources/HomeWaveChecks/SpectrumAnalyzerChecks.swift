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
