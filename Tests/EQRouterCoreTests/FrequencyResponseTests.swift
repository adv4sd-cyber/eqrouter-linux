import Testing
import Foundation
import Atomics
@testable import EQRouterCore

/// "Accurate to the dot" suite. These tests ground out the EQ against
/// closed-form magnitude responses and against measured sine-sweep
/// amplitudes. They're the contract the EQ must meet.
struct FrequencyResponseTests {

    // MARK: - Single-biquad accuracy

    @Test func peakingBiquadHitsExactGainAtCenterFrequency() {
        // RBJ peaking filter at center frequency Fc with gain G should
        // produce |H(Fc)| = G — that's the *definition* of the design.
        // Any deviation is a math bug.
        for fs in [44100.0, 48000.0, 88200.0, 96000.0] {
            for centerHz in [50.0, 250.0, 1000.0, 4000.0, 12000.0] {
                guard centerHz < fs / 2 else { continue }
                for gainDb in [-12.0, -6.0, -3.0, 3.0, 6.0, 12.0] {
                    for q in [0.5, 0.707, 1.0, 2.0, 4.0] {
                        let c = BiquadCoefficients(
                            kind: .peaking,
                            sampleRate: fs,
                            frequencyHz: centerHz,
                            gainDb: gainDb,
                            q: q
                        )
                        let measuredDb = FrequencyResponse.magnitudeDb(of: c, atHz: centerHz, sampleRate: fs)
                        let err = abs(measuredDb - gainDb)
                        #expect(
                            err < 0.05,
                            "peaking @ fs=\(fs) Fc=\(centerHz) gain=\(gainDb) Q=\(q): expected \(gainDb) dB, got \(measuredDb) dB"
                        )
                    }
                }
            }
        }
    }

    @Test func peakingBiquadHasZeroGainFarFromCenter() {
        // Far below the center frequency (one decade down) a peaking
        // filter with Q ≥ 0.5 should be within ~0.5 dB of unity gain.
        let fs = 48000.0
        let c = BiquadCoefficients(kind: .peaking, sampleRate: fs, frequencyHz: 1000, gainDb: 12, q: 2)
        let lowDb = FrequencyResponse.magnitudeDb(of: c, atHz: 50, sampleRate: fs)
        #expect(abs(lowDb) < 0.5)
    }

    @Test func analyticalMatchesMeasuredForOneBand() {
        // Pull a sine through an actual filter, measure peak amplitude,
        // confirm it matches the analytical formula. If these disagree the
        // filter implementation and the math model don't match.
        let fs = 48000.0
        let band = BiquadFilter()
        band.coefficients = BiquadCoefficients(kind: .peaking, sampleRate: fs, frequencyHz: 1000, gainDb: 6, q: 1)

        let measuredDb = FrequencyResponse.measureGainDb(
            freqHz: 1000, sampleRate: fs, process: { Double(band.process($0)) }
        )
        let analyticalDb = FrequencyResponse.magnitudeDb(of: band.coefficients, atHz: 1000, sampleRate: fs)

        #expect(abs(measuredDb - analyticalDb) < 0.05)
        #expect(abs(measuredDb - 6) < 0.05)
    }

    // MARK: - Ten-band chain accuracy

    @Test func tenBandChainBoostsExactlyAtBandCenter() {
        // Each band, boosted alone, should produce its designed gain at
        // its center frequency — that's the user-facing contract.
        let fs = 48000.0
        let eq = TenBandEQ(sampleRate: fs)
        for (idx, fc) in TenBandLayout.centerFrequenciesHz.enumerated() {
            guard fc < fs / 2 else { continue }
            eq.reset()
            eq.setGain(6, forBandID: idx)
            let measuredDb = FrequencyResponse.measureGainDb(
                freqHz: fc, sampleRate: fs, process: { Double(eq.process($0)) }
            )
            #expect(
                abs(measuredDb - 6) < 0.30,
                "band \(idx) (\(fc) Hz): expected 6 dB, got \(measuredDb) dB"
            )
        }
    }

    @Test func tenBandChainDoesNotColorOtherFrequencies() {
        // Boost the 1 kHz band — the 16 kHz band should remain near unity.
        let fs = 48000.0
        let eq = TenBandEQ(sampleRate: fs)
        eq.setGain(12, forBandID: 5) // 1 kHz
        let highDb = FrequencyResponse.measureGainDb(
            freqHz: 16000, sampleRate: fs, process: { Double(eq.process($0)) }
        )
        #expect(abs(highDb) < 1.0)
    }

    // MARK: - Sample rate sensitivity (the "broken EQ" bug)

    // MARK: - Atomic coefficient publish

    @Test func concurrentCoefficientUpdatesNeverProduceTornReads() {
        // Hammer a BiquadFilter from a writer thread that alternates
        // between two distinguishable coefficient sets; meanwhile a reader
        // (simulating the audio thread) reads coefficients repeatedly.
        // Every read must produce one of the two whole sets — never a
        // mixed (torn) value where some fields are from set A and others
        // from set B.
        //
        // The two sets are chosen so any field-level mixing produces a
        // value that doesn't match either set on at least one field.
        let setA = BiquadCoefficients(kind: .peaking, sampleRate: 48000, frequencyHz: 100,  gainDb: -12, q: 0.5)
        let setB = BiquadCoefficients(kind: .peaking, sampleRate: 48000, frequencyHz: 8000, gainDb: 12,  q: 4.0)

        let filter = BiquadFilter()
        filter.setCoefficients(setA)

        let stopWriting = ManagedAtomic<Bool>(false)
        let tornReads = ManagedAtomic<Int>(0)

        let writer = Thread {
            var flip = true
            while !stopWriting.load(ordering: .relaxed) {
                filter.setCoefficients(flip ? setA : setB)
                flip.toggle()
            }
        }
        writer.start()

        // Reader runs on the test thread; that's the closest analogue to a
        // hot audio callback. We sample the coefficients many times in a
        // tight loop and check every read for consistency with either set.
        for _ in 0..<200_000 {
            let c = filter.coefficients
            let matchesA = c.b0 == setA.b0 && c.b1 == setA.b1 && c.b2 == setA.b2 && c.a1 == setA.a1 && c.a2 == setA.a2
            let matchesB = c.b0 == setB.b0 && c.b1 == setB.b1 && c.b2 == setB.b2 && c.a1 == setB.a1 && c.a2 == setB.a2
            if !matchesA && !matchesB {
                tornReads.wrappingIncrement(ordering: .relaxed)
            }
        }
        stopWriting.store(true, ordering: .relaxed)
        while writer.isExecuting { Thread.sleep(forTimeInterval: 0.001) }

        let torn = tornReads.load(ordering: .relaxed)
        #expect(torn == 0, "saw \(torn) torn coefficient reads under concurrent updates")
    }

    // MARK: - Stereo correctness

    @Test func stereoPathDoesNotBleedLeftIntoRight() {
        // Feed a sine on L and silence on R. The EQ boost should affect L
        // only; R must stay silent. If the biquad state pairs were
        // accidentally shared, R would pick up filtered L content.
        let fs = 48000.0
        let eq = TenBandEQ(sampleRate: fs)
        eq.setGain(12, forBandID: 5) // 1 kHz

        let warmupFrames = Int(0.05 * fs)
        let measureFrames = Int(0.1 * fs)
        let omega = 2 * Double.pi * 1000.0 / fs

        for n in 0..<warmupFrames {
            _ = eq.processStereo(left: sin(omega * Double(n)), right: 0)
        }
        var maxAbsRight = 0.0
        for n in 0..<measureFrames {
            let i = warmupFrames + n
            let (_, R) = eq.processStereo(left: sin(omega * Double(i)), right: 0)
            if abs(R) > maxAbsRight { maxAbsRight = abs(R) }
        }
        #expect(maxAbsRight < 1e-9,
                "right channel had \(maxAbsRight) of leak from left")
    }

    @Test func stereoPathMatchesMonoForEqualLAndR() {
        // With identical L and R input, the stereo result must match the
        // mono process() exactly on both channels — verifies the new
        // stereo path doesn't drift from the audited mono math.
        let fs = 48000.0
        let mono = TenBandEQ(sampleRate: fs)
        let stereo = TenBandEQ(sampleRate: fs)
        mono.setGain(8, forBandID: 5)
        stereo.setGain(8, forBandID: 5)

        let omega = 2 * Double.pi * 1000.0 / fs
        var maxErr = 0.0
        for n in 0..<4096 {
            let input = sin(omega * Double(n))
            let monoOut = mono.process(input)
            let (L, R) = stereo.processStereo(left: input, right: input)
            maxErr = max(maxErr, abs(L - monoOut))
            maxErr = max(maxErr, abs(R - monoOut))
        }
        #expect(maxErr < 1e-12, "stereo path drifted from mono by \(maxErr)")
    }

    @Test func chainStereoPreservesPanning() {
        // Pan content fully to L (R = 0). The chain output's R should be
        // essentially 0 — preserving the original panning instead of
        // collapsing to center-mono.
        let fs = 48000.0
        let chain = RouteDSPChain(sampleRate: fs)
        chain.customEQ.setGain(6, forBandID: 5)

        let omega = 2 * Double.pi * 1000.0 / fs
        var maxAbsRight = 0.0
        for n in 0..<8192 {
            let input = sin(omega * Double(n)) * 0.5
            let (_, R) = chain.processStereo(left: input, right: 0)
            if abs(R) > maxAbsRight { maxAbsRight = abs(R) }
        }
        #expect(maxAbsRight < 1e-6,
                "right output picked up \(maxAbsRight) from left input — stereo image not preserved")
    }

    @Test func rebuildAtNewSampleRateRestoresCorrectBandCenters() {
        // Chain starts at the "wrong" 48k design, then is rebuilt at 44.1k.
        // After rebuild, the 1 kHz band's peak should be at 1 kHz on 44.1k
        // audio — not at the shifted 919 Hz.
        let actualFs = 44100.0
        let eq = TenBandEQ(sampleRate: 48000)
        eq.setGain(12, forBandID: 5)
        eq.rebuild(at: actualFs)

        let measured = FrequencyResponse.measureGainDb(
            freqHz: 1000, sampleRate: actualFs,
            process: { Double(eq.process($0)) }
        )
        #expect(abs(measured - 12) < 0.30,
                "after rebuild at 44.1k, gain at 1 kHz is \(measured), expected ~12 dB")
    }

    @Test func usingChainAtWrongSampleRateShiftsBandCenters() {
        // Documents the architectural bug: a chain designed for 48k,
        // analyzed against 44.1k normalized frequencies, has all its band
        // centers shifted by 44.1/48 = 0.919 — "1 kHz" actually peaks at
        // ~919 Hz, etc. Demonstrated via the analytical magnitude formula
        // (no audio rendering needed: the math itself shifts).
        let designFs = 48000.0
        let actualFs = 44100.0
        let eq = TenBandEQ(sampleRate: designFs)
        eq.setGain(12, forBandID: 5) // "1 kHz" band

        let coeffs = eq.currentCoefficients
        let scan = FrequencyResponse.logSpacedFrequencies(from: 200, to: 5000, count: 200)
        var bestF = 0.0
        var bestDb = -Double.infinity
        for f in scan {
            let g = FrequencyResponse.magnitudeDb(ofCascade: coeffs, atHz: f, sampleRate: actualFs)
            if g > bestDb { bestDb = g; bestF = f }
        }
        let shiftedPeakHz = 1000.0 * actualFs / designFs
        #expect(
            abs(bestF - shiftedPeakHz) < 50,
            "peak Hz when interpreting 48k-designed chain at 44.1k is \(bestF), expected near \(shiftedPeakHz)"
        )
    }

    // MARK: - Safety ceiling accuracy

    @Test func safetyCeilingDoesNotOverAttenuateWidelySeparatedBoosts() {
        // Two bands at opposite ends of the spectrum, each boosted +6 dB.
        // Their peak responses are at 125 Hz and 8 kHz — they DO NOT add.
        // The actual chain peak is ~6 dB (at either band), not +12 dB.
        // A correct ceiling attenuates by ~6 dB, not 12 dB.
        let fs = 48000.0
        let eq = TenBandEQ(sampleRate: fs)
        eq.setGain(6, forBandID: 2) // 125 Hz
        eq.setGain(6, forBandID: 8) // 8 kHz

        let actualPeakDb = FrequencyResponse.peakMagnitudeDb(
            ofCascade: eq.currentCoefficients,
            sampleRate: fs,
            frequencies: FrequencyResponse.logSpacedFrequencies()
        )
        #expect(actualPeakDb > 5.5 && actualPeakDb < 7.5,
                "actual peak gain is \(actualPeakDb) dB — expected ~6 dB")

        // What the current ceiling estimator says — it should agree with
        // reality to within ~1 dB. If it doesn't, ceiling is over-clamping.
        let estimatedPeakDb = OutputSafetyCeiling.estimatedPeakGainDb(
            routeGainDb: 0,
            outputTrimDb: 0,
            customEQBands: eq.bands,
            customEQSampleRate: fs,
            correctionPreampDb: 0,
            correctionFilters: [],
            correctionSampleRate: fs,
            userParametricPreampDb: 0,
            userParametricFilters: [],
            userParametricSampleRate: fs
        )
        #expect(abs(estimatedPeakDb - actualPeakDb) < 1.0,
                "ceiling estimator says \(estimatedPeakDb) dB but reality is \(actualPeakDb) dB")
    }

    @Test func ceilingMakeupBringsChainPeakUnderUnity() {
        // After the safety ceiling applies its makeup attenuation, the
        // chain's actual peak should be ≤ 0 dB. Anything else means the
        // ceiling is broken (over- or under-attenuating).
        let fs = 48000.0
        let chain = RouteDSPChain(sampleRate: fs)
        chain.safetyCeilingEnabled = true
        chain.customEQ.setGain(6, forBandID: 2)
        chain.customEQ.setGain(6, forBandID: 8)

        let scan = FrequencyResponse.logSpacedFrequencies()
        var peakDb = -Double.infinity
        for f in scan {
            chain.customEQ.resetStateOnly()
            // Use a low input so the soft saturator does NOT kick in — we
            // want to measure the linear chain peak, not the curve at
            // extremes.
            let g = FrequencyResponse.measureGainDb(
                freqHz: f, sampleRate: fs,
                process: { Double(chain.process(0.01 * $0)) }
            )
            let normalized = g - 20 * log10(0.01)
            if normalized > peakDb { peakDb = normalized }
        }
        #expect(peakDb < 0.5,
                "chain peak after ceiling makeup is \(peakDb) dB — expected ≤ 0 dB")
    }
}
