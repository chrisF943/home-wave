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
