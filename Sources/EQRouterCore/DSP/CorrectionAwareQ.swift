import Foundation

/// Computes per-band effective Q for the 10-band custom EQ.
///
/// Two signals only — by design, the correction profile's *filter Qs*
/// are NOT used here:
///   1. The octave-clean baseline Q (= √2 for our band spacing)
///   2. The genre-typical Q vector for the band's frequency
///
/// When NO correction profile is loaded, the genre's Q vector applies
/// at full strength (100%).
///
/// When a correction profile IS loaded, the genre's Q is gently nudged
/// (25% blend toward the octave-clean baseline).
///
/// **The custom EQ Q does NOT track the correction profile's per-filter
/// Qs.** An earlier version did track them — making custom bands near
/// surgical correction filters jump to high Q so they'd "match" the
/// correction's narrow shape. Empirically that compounded with the
/// correction itself (user boost at high Q right next to a surgical
/// correction filter at the same frequency = the correction effect
/// being applied twice).
///
/// The canonical headphone-EQ workflow (AutoEq + Wavelet, Equalizer APO
/// + Peace) keeps the two layers independent: correction applies its
/// surgical filters, user adds broad (Q ≈ 0.7–1.4) tonal adjustments on
/// top. Broad-Q user bands at the same frequency as surgical correction
/// don't stack the way narrow-Q would — their energy is spread across
/// the band rather than concentrated at the correction's center.
///
/// Sources for the broad-Q-on-top rule:
/// - "Headphone EQ Guide: Tuning for Perfect Audio & Clarity" — wide Q
///   for preference shaping on top of a correction profile.
///   https://www.iwantek.com/blogs/news/headphone-eq-guide-tuning-for-perfect-audio-clarity
/// - AutoEq wiki, "Choosing an Equalizer App" — separation of correction
///   filters and user filters; users add their own bands with their own
///   Q values, never derived from the profile.
///   https://github.com/jaakkopasanen/AutoEq/wiki/Choosing-an-Equalizer-App
/// - Wavelet docs, "Import custom AutoEq data" — same layering model.
///   https://pittvandewitt.github.io/Wavelet/Import/
public enum CorrectionAwareQ {
    /// Strength applied to the genre's Q vector when a correction
    /// profile is loaded. 1.0 = genre fully applies; 0.0 = genre
    /// ignored. A gentle nudge with correction lets the user keep their
    /// genre flavour without dramatically reshaping bands the correction
    /// is already touching.
    public static let blendStrengthWithCorrection: Double = 0.25

    /// Strength applied when no correction is loaded — genre fully on.
    public static let blendStrengthNoCorrection: Double = 1.0

    /// Per-band effective Q. Pure blend of baseline and genre — no
    /// dependency on the correction profile's filter Qs.
    public static func effectiveQ(
        bandIdx: Int,
        baselineQ: Double,
        genre: GenrePreset,
        hasCorrection: Bool
    ) -> Double {
        let genreQ = genre.qVector[bandIdx]
        let strength = hasCorrection
            ? blendStrengthWithCorrection
            : blendStrengthNoCorrection
        return baselineQ * (1 - strength) + genreQ * strength
    }

    /// Full Q vector for all 10 bands. Convenience wrapper used by
    /// `RouteDSPChain.recomputeEffectiveQs(...)`.
    public static func qVector(
        for genre: GenrePreset,
        correctionProfile: HeadphoneProfile?,
        baselineQ: Double = TenBandLayout.octaveCleanQ
    ) -> [Double] {
        let hasCorrection = correctionProfile != nil
        return TenBandLayout.centerFrequenciesHz.enumerated().map { idx, _ in
            effectiveQ(
                bandIdx: idx,
                baselineQ: baselineQ,
                genre: genre,
                hasCorrection: hasCorrection
            )
        }
    }
}
