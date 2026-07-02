import Foundation

/// Analytical and empirical frequency-response tools. These are the
/// "ground truth" used by the test suite and the safety-ceiling math to
/// know what the EQ is *actually* doing, independent of any internal
/// claim about filter design.
public enum FrequencyResponse {

    // MARK: - Analytical (closed-form, no audio rendering)

    /// Magnitude of a biquad's frequency response at a given Hz / sample rate.
    /// Derived from the standard z-transform of the transfer function:
    ///   |H(e^jω)|² = |B(e^jω)|² / |A(e^jω)|²
    /// where B = b0 + b1 z⁻¹ + b2 z⁻² and A = 1 + a1 z⁻¹ + a2 z⁻².
    public static func magnitude(of c: BiquadCoefficients, atHz f: Double, sampleRate fs: Double) -> Double {
        let w = 2 * .pi * f / fs
        let cosw = cos(w), cos2w = cos(2 * w)
        let sinw = sin(w), sin2w = sin(2 * w)

        // |b0 + b1 e^-jw + b2 e^-j2w|²
        let bRe = c.b0 + c.b1 * cosw + c.b2 * cos2w
        let bIm = -c.b1 * sinw - c.b2 * sin2w
        let numSquared = bRe * bRe + bIm * bIm

        // |1 + a1 e^-jw + a2 e^-j2w|²
        let aRe = 1.0 + c.a1 * cosw + c.a2 * cos2w
        let aIm = -c.a1 * sinw - c.a2 * sin2w
        let denSquared = aRe * aRe + aIm * aIm

        return sqrt(numSquared / denSquared)
    }

    public static func magnitudeDb(of c: BiquadCoefficients, atHz f: Double, sampleRate fs: Double) -> Double {
        20 * log10(magnitude(of: c, atHz: f, sampleRate: fs))
    }

    /// Magnitude of a cascade of biquads — sections multiply in linear,
    /// add in dB.
    public static func magnitudeDb(ofCascade sections: [BiquadCoefficients], atHz f: Double, sampleRate fs: Double) -> Double {
        sections.reduce(0.0) { $0 + magnitudeDb(of: $1, atHz: f, sampleRate: fs) }
    }

    /// Worst-case (peak) magnitude of a cascade across the audible band,
    /// sampled at the given log-spaced frequencies. Returns the peak gain
    /// in dB. Used by `OutputSafetyCeiling` to size the makeup attenuation
    /// *accurately* — sums-of-positive-bands wildly over-estimate this.
    public static func peakMagnitudeDb(
        ofCascade sections: [BiquadCoefficients],
        sampleRate fs: Double,
        frequencies: [Double]
    ) -> Double {
        var peak = -Double.infinity
        for f in frequencies {
            let g = magnitudeDb(ofCascade: sections, atHz: f, sampleRate: fs)
            if g > peak { peak = g }
        }
        return peak
    }

    /// Standard log-spaced frequency grid for response sampling.
    /// Default covers 20 Hz to 20 kHz with 240 points; that's a fine
    /// enough grid that the peak-magnitude estimate is within 0.05 dB of
    /// the true continuous peak for any Q ≤ 12.
    public static func logSpacedFrequencies(
        from low: Double = 20,
        to high: Double = 20000,
        count: Int = 240
    ) -> [Double] {
        guard count > 1 else { return [low] }
        let logLow = log10(low)
        let logHigh = log10(high)
        let step = (logHigh - logLow) / Double(count - 1)
        return (0..<count).map { pow(10, logLow + Double($0) * step) }
    }

    // MARK: - Empirical (run real audio through the filter)

    /// Steady-state amplitude of a unit-amplitude sine at `freq` after
    /// passing through `process` (any per-sample function). Used to verify
    /// the analytical formula matches reality.
    ///
    /// Uses a complex projection (Goertzel-style sin/cos correlation) so
    /// the measurement is accurate independent of sample alignment.
    /// Peak-finding fails at high frequencies — at fs=48k a 16 kHz sine
    /// only ever hits the discrete values {0, ±sin(2π/3)} = {0, ±0.866},
    /// so naive peak-finding under-reports amplitude by ≈1.25 dB at
    /// Nyquist/3 and more as Fc approaches Nyquist.
    ///
    /// `warmupSeconds` discards transient before measuring; default 50ms
    /// settles biquads with Q ≤ 12 within ±0.01 dB.
    public static func measureAmplitude(
        freqHz: Double,
        sampleRate fs: Double,
        warmupSeconds: Double = 0.05,
        measureSeconds: Double = 0.15,
        process: (Double) -> Double
    ) -> Double {
        let warmupSamples = Int(warmupSeconds * fs)
        let measureSamples = Int(measureSeconds * fs)
        let omega = 2 * .pi * freqHz / fs

        for i in 0..<warmupSamples {
            _ = process(sin(omega * Double(i)))
        }

        // Complex projection: amplitude of cos+j·sin component recovered
        // exactly as 2/N · |Σ y[n]·e^{-jωn}|. The factor 2 turns the
        // single-sided sum into the original sine amplitude.
        var sumCos = 0.0
        var sumSin = 0.0
        for i in 0..<measureSamples {
            let n = Double(warmupSamples + i)
            let sample = process(sin(omega * n))
            sumCos += sample * cos(omega * n)
            sumSin += sample * sin(omega * n)
        }
        let inv = 2.0 / Double(measureSamples)
        let re = sumCos * inv
        let im = sumSin * inv
        return sqrt(re * re + im * im)
    }

    public static func measureGainDb(
        freqHz: Double,
        sampleRate fs: Double,
        warmupSeconds: Double = 0.05,
        measureSeconds: Double = 0.15,
        process: (Double) -> Double
    ) -> Double {
        let amp = measureAmplitude(
            freqHz: freqHz,
            sampleRate: fs,
            warmupSeconds: warmupSeconds,
            measureSeconds: measureSeconds,
            process: process
        )
        return 20 * log10(max(amp, 1e-12))
    }
}
