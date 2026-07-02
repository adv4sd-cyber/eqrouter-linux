import Foundation

/// Stateless soft saturator. Replaces the previous envelope-based peak
/// limiter, which pumped audibly: a transient over threshold would hold
/// gain reduction for the release window even after the signal dipped
/// below threshold, smearing the EQ shape with dynamic level changes
/// that felt like "the EQ does nothing at extremes".
///
/// Soft-knee shape:
///   |y| = |x|                              for |x| ≤ kneeStart
///   |y| = kneeStart + (ceiling − kneeStart) · tanh(scale · (|x| − kneeStart))
///                                          for |x| > kneeStart
///
/// Properties chosen so the user can hear their EQ exactly through ±0.7
/// (unity slope, zero alteration), and so even unboundedly loud input
/// is asymptotically clamped to ±0.98 with no harmonic distortion sting
/// and no envelope state that could pump.
///
/// Init takes a sample rate purely so the call sites don't have to
/// change; it's unused by the math.
public final class Limiter {
    public static let kneeStart: Double = 0.7
    public static let ceiling: Double  = 0.98
    public static let scale: Double    = 3.0

    public var thresholdLinear: Double { Self.ceiling }
    public private(set) var isClipping: Bool = false

    public init(releaseMs: Double = 50, sampleRate: Double) {
        _ = releaseMs; _ = sampleRate // signature kept; soft saturator is stateless
    }

    @inline(__always)
    public func process(_ input: Double) -> Double {
        Self.saturate(input, clippingFlag: &isClipping)
    }

    /// Stereo soft-saturator. Same curve applied independently to L and R.
    /// Unlike the envelope limiter, applying the same curve per channel
    /// does NOT smear the stereo image: the curve is stateless and
    /// transfer-function-only, so identical input frames produce identical
    /// output frames regardless of what came before.
    @inline(__always)
    public func processStereo(left: Double, right: Double) -> (Double, Double) {
        var clipping = false
        let L = Self.saturate(left,  clippingFlag: &clipping)
        let R = Self.saturate(right, clippingFlag: &clipping)
        isClipping = clipping
        return (L, R)
    }

    @inline(__always)
    private static func saturate(_ input: Double, clippingFlag: inout Bool) -> Double {
        let absIn = abs(input)
        if absIn <= kneeStart {
            return input
        }
        clippingFlag = true
        let sign = input >= 0 ? 1.0 : -1.0
        let excess = absIn - kneeStart
        return sign * (kneeStart + (ceiling - kneeStart) * tanh(scale * excess))
    }
}

/// Running peak meter for input/output metering in the route row UI.
public final class PeakMeter {
    private var peak: Double = 0
    private let decayCoefficient: Double

    public init(decayMs: Double = 300, sampleRate: Double) {
        decayCoefficient = exp(-1.0 / (sampleRate * decayMs / 1000))
    }

    @inline(__always)
    public func update(_ sample: Double) {
        let absSample = abs(sample)
        peak = max(absSample, peak * decayCoefficient)
    }

    @inline(__always)
    public func updateBlockPeak(_ blockPeak: Double, frameCount: Int) {
        guard frameCount > 0 else { return }
        peak = max(abs(blockPeak), peak * pow(decayCoefficient, Double(frameCount)))
    }

    public var currentPeak: Double { peak }
}
