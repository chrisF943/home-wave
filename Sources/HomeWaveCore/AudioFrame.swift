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
