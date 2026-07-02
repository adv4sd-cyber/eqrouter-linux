import Foundation
import Atomics

/// RBJ audio cookbook biquad. Coefficient updates happen off the render thread;
/// `process` only reads the currently-published `Coefficients` value, so it stays
/// allocation-free and lock-free for real-time use.
public enum BiquadKind {
    case peaking
    case lowShelf
    case highShelf
}

public struct BiquadCoefficients {
    public var b0: Double = 1
    public var b1: Double = 0
    public var b2: Double = 0
    public var a1: Double = 0
    public var a2: Double = 0

    public static let identity = BiquadCoefficients()

    public init() {}

    public init(kind: BiquadKind, sampleRate: Double, frequencyHz: Double, gainDb: Double, q: Double) {
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * frequencyHz / sampleRate
        let cosw0 = cos(w0)
        let sinw0 = sin(w0)
        let alpha = sinw0 / (2 * q)

        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0

        switch kind {
        case .peaking:
            b0 = 1 + alpha * a
            b1 = -2 * cosw0
            b2 = 1 - alpha * a
            a0 = 1 + alpha / a
            a1 = -2 * cosw0
            a2 = 1 - alpha / a

        case .lowShelf:
            let sqrtA = sqrt(a)
            b0 = a * ((a + 1) - (a - 1) * cosw0 + 2 * sqrtA * alpha)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosw0)
            b2 = a * ((a + 1) - (a - 1) * cosw0 - 2 * sqrtA * alpha)
            a0 = (a + 1) + (a - 1) * cosw0 + 2 * sqrtA * alpha
            a1 = -2 * ((a - 1) + (a + 1) * cosw0)
            a2 = (a + 1) + (a - 1) * cosw0 - 2 * sqrtA * alpha

        case .highShelf:
            let sqrtA = sqrt(a)
            b0 = a * ((a + 1) + (a - 1) * cosw0 + 2 * sqrtA * alpha)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosw0)
            b2 = a * ((a + 1) + (a - 1) * cosw0 - 2 * sqrtA * alpha)
            a0 = (a + 1) - (a - 1) * cosw0 + 2 * sqrtA * alpha
            a1 = 2 * ((a - 1) - (a + 1) * cosw0)
            a2 = (a + 1) - (a - 1) * cosw0 - 2 * sqrtA * alpha
        }

        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }
}

/// Single biquad section. Holds two parallel state pairs (left/right) so
/// stereo content can be processed without spinning up two filter
/// instances. Coefficients are shared between channels — that's the
/// point of a stereo EQ — only delay lines are per-channel.
///
/// Direct Form I per channel:
///   y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] − a1*y[n-1] − a2*y[n-2]
///
/// Coefficients are double-buffered with an atomic index. The audio
/// thread reads the index once at the top of `process` and uses that
/// slot for the rest of the call; the UI thread writes the inactive
/// slot and atomically swaps the index. This eliminates torn reads
/// (a 40-byte struct can't be loaded atomically on ARM64), which were
/// the cause of audible clicks during slider drags.
public final class BiquadFilter {
    private var coefficientsA: BiquadCoefficients = .identity
    private var coefficientsB: BiquadCoefficients = .identity
    private let coefficientsIndex = ManagedAtomic<Int>(0)
    public let channelCount: Int

    /// Snapshot of the currently-active coefficients. Convenience for
    /// non-RT code (UI, tests, response measurements). The audio thread
    /// does NOT go through this — it reads the live double-buffer slots
    /// directly inside `process` / `processStereo`.
    public var coefficients: BiquadCoefficients {
        get {
            coefficientsIndex.load(ordering: .acquiring) == 0 ? coefficientsA : coefficientsB
        }
        set {
            setCoefficients(newValue)
        }
    }

    private var x1: [Double]
    private var x2: [Double]
    private var y1: [Double]
    private var y2: [Double]

    public init(channelCount: Int = 2) {
        self.channelCount = max(channelCount, 1)
        self.x1 = Array(repeating: 0, count: self.channelCount)
        self.x2 = Array(repeating: 0, count: self.channelCount)
        self.y1 = Array(repeating: 0, count: self.channelCount)
        self.y2 = Array(repeating: 0, count: self.channelCount)
    }

    /// Atomic coefficient update. Writer-only — must not be called from
    /// the audio thread. Writes the inactive slot in full, then releases
    /// the new index. The audio thread reads index with acquire ordering
    /// so it sees the fully-written slot whenever it sees the new index.
    public func setCoefficients(_ newValue: BiquadCoefficients) {
        let current = coefficientsIndex.load(ordering: .relaxed)
        let next = 1 - current
        if next == 0 {
            coefficientsA = newValue
        } else {
            coefficientsB = newValue
        }
        coefficientsIndex.store(next, ordering: .releasing)
    }

    @inline(__always)
    public func process(_ input: Double) -> Double {
        process(input, channel: 0)
    }

    @inline(__always)
    public func process(_ input: Double, channel: Int) -> Double {
        let idx = coefficientsIndex.load(ordering: .acquiring)
        let c = idx == 0 ? coefficientsA : coefficientsB
        let output = c.b0 * input + c.b1 * x1[channel] + c.b2 * x2[channel] - c.a1 * y1[channel] - c.a2 * y2[channel]
        x2[channel] = x1[channel]
        x1[channel] = input
        y2[channel] = y1[channel]
        y1[channel] = output
        return output
    }

    @inline(__always)
    public func processStereo(left: Double, right: Double) -> (Double, Double) {
        precondition(channelCount >= 2)
        return (process(left, channel: 0), process(right, channel: 1))
    }

    public func reset() {
        for channel in 0..<channelCount {
            x1[channel] = 0
            x2[channel] = 0
            y1[channel] = 0
            y2[channel] = 0
        }
    }
}
