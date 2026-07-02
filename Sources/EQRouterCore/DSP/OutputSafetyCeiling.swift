import Foundation

/// Enforces that a route can never make a signal *louder* than its
/// unprocessed input, regardless of how the user sets gain, EQ bands,
/// trim, or a correction profile's preamp. The app does not read or touch
/// the system volume curve — it has no API to do that reliably — so the
/// only ceiling it can honestly claim is relative: net applied gain stays
/// at or below 0 dB (unity).
///
/// The estimate computes the actual peak magnitude response of the EQ
/// cascade at the route's sample rate. This is the true worst-case gain
/// any sine input could see at any frequency. The older "sum of positive
/// band gains" approximation over-attenuated by 6–24 dB when boosts were
/// at widely separated frequencies — replacing it fixed the symptom
/// where "EQ does nothing audible when I boost".
public struct OutputSafetyCeiling {
    public static let maxCombinedGainDb: Double = 0

    /// Actual peak gain in dB this route can produce at *any* frequency,
    /// given its current controls. Adds linear (gain/trim/preamp) stages
    /// to the frequency-dependent EQ cascade peak.
    public static func estimatedPeakGainDb(
        routeGainDb: Double,
        outputTrimDb: Double,
        customEQBands: [EQBandState],
        customEQSampleRate: Double,
        correctionPreampDb: Double,
        correctionFilters: [ParametricFilterSpec],
        correctionSampleRate: Double,
        userParametricPreampDb: Double,
        userParametricFilters: [ParametricFilterSpec],
        userParametricSampleRate: Double
    ) -> Double {
        let scan = FrequencyResponse.logSpacedFrequencies()

        let customCoeffs = customEQBands.map {
            BiquadCoefficients(
                kind: .peaking,
                sampleRate: customEQSampleRate,
                frequencyHz: $0.frequencyHz,
                gainDb: $0.gainDb,
                q: $0.q
            )
        }
        let correctionCoeffs = correctionFilters.map { spec -> BiquadCoefficients in
            let kind: BiquadKind = {
                switch spec.shape {
                case .peaking:   return .peaking
                case .lowShelf:  return .lowShelf
                case .highShelf: return .highShelf
                }
            }()
            return BiquadCoefficients(
                kind: kind,
                sampleRate: correctionSampleRate,
                frequencyHz: spec.frequencyHz,
                gainDb: spec.gainDb,
                q: spec.q
            )
        }
        let userParametricCoeffs = userParametricFilters.map { spec -> BiquadCoefficients in
            BiquadCoefficients(
                kind: spec.shape.biquadKind,
                sampleRate: userParametricSampleRate,
                frequencyHz: spec.frequencyHz,
                gainDb: spec.gainDb,
                q: spec.q
            )
        }

        // Sample the cascade response at every grid frequency and take
        // the peak. Sections within a cascade share the same sample rate;
        // custom + correction can in principle differ if they're set up
        // separately, so we evaluate each at its own rate and add in dB.
        var peakDb = -Double.infinity
        for f in scan {
            var db = 0.0
            for c in customCoeffs {
                db += FrequencyResponse.magnitudeDb(of: c, atHz: f, sampleRate: customEQSampleRate)
            }
            for c in correctionCoeffs {
                db += FrequencyResponse.magnitudeDb(of: c, atHz: f, sampleRate: correctionSampleRate)
            }
            for c in userParametricCoeffs {
                db += FrequencyResponse.magnitudeDb(of: c, atHz: f, sampleRate: userParametricSampleRate)
            }
            if db > peakDb { peakDb = db }
        }
        if peakDb == -Double.infinity { peakDb = 0 }

        return routeGainDb + outputTrimDb + correctionPreampDb + userParametricPreampDb + peakDb
    }

    /// Linear makeup attenuation. Returns 1.0 if the chain is already at
    /// or below the ceiling; otherwise the exact amount of attenuation
    /// needed to clamp the peak to 0 dB. Never amplifies.
    public static func makeupAttenuationLinear(forEstimatedPeakGainDb peakDb: Double) -> Double {
        let excessDb = peakDb - maxCombinedGainDb
        guard excessDb > 0 else { return 1.0 }
        return pow(10, -excessDb / 20)
    }
}
