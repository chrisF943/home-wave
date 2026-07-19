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
