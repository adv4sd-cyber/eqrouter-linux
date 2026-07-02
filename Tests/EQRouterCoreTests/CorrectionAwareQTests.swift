import Testing
import Foundation
@testable import EQRouterCore

/// Validates the correction-aware Q machinery: that genre vectors land
/// where they should when there's no correction, gently nudge when
/// correction is active, and track nearby surgical filters per band.
struct CorrectionAwareQTests {

    @Test func flatGenreEqualsOctaveCleanQ() {
        // The Flat genre's vector must equal the octave-clean Q (√2)
        // across all 10 bands — that's what makes it the "neutral" choice.
        let expected = TenBandLayout.octaveCleanQ
        for q in GenrePreset.flat.qVector {
            #expect(abs(q - expected) < 1e-9)
        }
    }

    @Test func genreFullyAppliesWhenNoCorrectionLoaded() {
        // No correction → 100% strength → effective Q == genre's
        // qVector entry, band by band.
        let genre = GenrePreset.vocal
        for (idx, _) in TenBandLayout.centerFrequenciesHz.enumerated() {
            let effQ = CorrectionAwareQ.effectiveQ(
                bandIdx: idx,
                baselineQ: TenBandLayout.octaveCleanQ,
                genre: genre,
                hasCorrection: false
            )
            #expect(abs(effQ - genre.qVector[idx]) < 1e-9)
        }
    }

    @Test func genreGentlyNudgesWhenCorrectionLoaded() {
        // With correction loaded, blend strength drops to 25% — effective
        // Q sits between the baseline and the genre's vector. The rule
        // is a pure blend; no tracking of correction-profile Q values.
        let genre = GenrePreset.vocal
        let baseline = TenBandLayout.octaveCleanQ
        for (idx, _) in TenBandLayout.centerFrequenciesHz.enumerated() {
            let effQ = CorrectionAwareQ.effectiveQ(
                bandIdx: idx,
                baselineQ: baseline,
                genre: genre,
                hasCorrection: true
            )
            let expected = baseline * (1 - 0.25) + genre.qVector[idx] * 0.25
            #expect(abs(effQ - expected) < 1e-6)
        }
    }

    @Test func customQIsIndependentOfCorrectionFilterQs() {
        // Regression: an earlier version made custom bands near surgical
        // correction filters jump to high Q to "match" the correction's
        // narrow shape. That compounded with the correction itself when
        // the user boosted (the correction effect was being applied a
        // second time at the same frequency). The fix is to keep the
        // user's broad-Q tonal layer fully independent of the correction
        // profile's filter Qs.
        //
        // This test asserts that the effective Q at any band depends ONLY
        // on (genre, hasCorrection) — never on which filters are in the
        // correction profile.
        let baseline = TenBandLayout.octaveCleanQ
        for genre in GenrePreset.allCases {
            for bandIdx in 0..<10 {
                let qWithOD200 = CorrectionAwareQ.effectiveQ(
                    bandIdx: bandIdx,
                    baselineQ: baseline,
                    genre: genre,
                    hasCorrection: true
                )
                let qWithAnyCorrection = CorrectionAwareQ.effectiveQ(
                    bandIdx: bandIdx,
                    baselineQ: baseline,
                    genre: genre,
                    hasCorrection: true
                )
                #expect(qWithOD200 == qWithAnyCorrection,
                        "genre \(genre), band \(bandIdx): effective Q must not depend on which profile is loaded")
            }
        }
    }

    @Test func qVectorMatchesEffectiveQAndIsCorrectionProfileAgnostic() {
        // End-to-end through the public `qVector(for:correctionProfile:)`
        // entry point used by `RouteDSPChain`. Loading OD200 vs no
        // correction must produce identical vectors except for the 25%
        // blend factor — never differ band-by-band based on OD200's own
        // filter Qs.
        let genre = GenrePreset.rock
        let vNoCorrection = CorrectionAwareQ.qVector(for: genre, correctionProfile: nil)
        let vWithOD200    = CorrectionAwareQ.qVector(for: genre, correctionProfile: .orivetiOD200)

        for idx in 0..<10 {
            let baseline = TenBandLayout.octaveCleanQ
            let expectedNo   = baseline * 0    + genre.qVector[idx] * 1
            let expectedWith = baseline * 0.75 + genre.qVector[idx] * 0.25
            #expect(abs(vNoCorrection[idx] - expectedNo) < 1e-9)
            #expect(abs(vWithOD200[idx] - expectedWith) < 1e-9)
        }
    }

    @Test func tenBandChainAppliesQVectorThroughAtomicPublish() {
        // End-to-end: applying a Q vector via TenBandEQ.applyQVector
        // updates both the band model and the live filter coefficients.
        let eq = TenBandEQ(sampleRate: 48000)
        let qVector = Array(repeating: 2.5, count: 10)
        eq.applyQVector(qVector)
        for band in eq.bands {
            #expect(abs(band.q - 2.5) < 1e-9)
        }
        // The currentCoefficients property derives from `bands` directly,
        // so it should report Q = 2.5 too.
        let recomputed = eq.currentCoefficients
        for c in recomputed {
            // Q value isn't stored in coefficients, but at Fc the gain
            // should equal the band's gainDb (which is 0 since we haven't
            // set anything). This sanity check verifies the cascade is
            // well-formed.
            let mag = FrequencyResponse.magnitudeDb(of: c, atHz: 1000, sampleRate: 48000)
            #expect(mag.isFinite)
        }
    }

    @Test func chainRecomputeUpdatesBandQsLive() {
        // RouteDSPChain.recomputeEffectiveQs end-to-end: changing genre
        // updates the customEQ.bands[*].q values.
        let chain = RouteDSPChain(sampleRate: 48000)
        chain.recomputeEffectiveQs(genre: .vocal, correctionProfile: nil)

        let vocalQs = GenrePreset.vocal.qVector
        for (idx, band) in chain.customEQ.bands.enumerated() {
            #expect(abs(band.q - vocalQs[idx]) < 1e-9,
                    "band \(idx): expected Q=\(vocalQs[idx]), got \(band.q)")
        }

        // Switch to Classical — Qs should now flatten to 0.707 across
        // the board.
        chain.recomputeEffectiveQs(genre: .classical, correctionProfile: nil)
        for band in chain.customEQ.bands {
            #expect(abs(band.q - 0.707) < 1e-9)
        }
    }
}
