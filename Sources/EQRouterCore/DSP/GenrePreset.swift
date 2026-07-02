import Foundation

/// Genre-typical Q character for the 10-band custom EQ.
///
/// Q ("quality factor") sets how WIDE each band is in octaves — not how
/// LOUD it is, which is gain. Higher Q = narrower band; lower Q = wider.
/// For our octave-spaced bands (31, 62, 125 … 16k), Q = √2 ≈ 1.414 makes
/// each band cleanly cover exactly its one octave slot (−3 dB skirts at
/// half-octave from center). That's the `flat` default.
///
/// Each genre shifts certain bands wider or narrower to match how that
/// genre is typically EQ'd in production. The values below are NOT
/// invented — each is grounded in published mixing references. Per-genre
/// citations follow each vector.
///
/// Synthesis sources (overall):
/// - Sonimus, "The Q Factor" — Q-vs-bandwidth tradeoffs, why broad-Q
///   (0.7–1.5) suits tonal shaping and high-Q (3–5) suits surgical cuts.
///   https://sonimus.com/blog/info/the-q-factor.html
/// - iZotope, "Parametric EQ: what it is and how to use one" — narrow Q
///   for problem-solving, wider Q for broad tonal shaping (general rule).
///   https://www.izotope.com/en/learn/parametric-eq.html
/// - Sound on Sound (multiple articles) — instrument-specific frequency
///   and Q recommendations for mixing.
/// - Audio Intensity, "EQ Settings by Music Genre" — frequency targets
///   per genre. https://audiointensity.com/pages/eq-settings-by-music-genre
/// - emastered, "Best Equalizer Settings: Definitive Guide" — genre
///   character pointers. https://emastered.com/blog/best-equalizer-settings
///
/// Universal rule from the Sonimus/iZotope sources, applied throughout:
///   - Boosts use broad Q (0.7 – √2) — sounds musical, doesn't ring.
///   - Cuts use narrower Q (1.5 – 3) — surgical without smearing.
/// Since our 10-band custom EQ is symmetric (a band can boost OR cut),
/// each genre's Q vector is chosen for its INTENDED action per band.
public enum GenrePreset: String, CaseIterable, Identifiable, Equatable, Codable {
    case flat
    case reference
    case edm
    case hipHop
    case rock
    case pop
    case vocal
    case acoustic
    case classical

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flat:      return "Flat"
        case .reference: return "Reference"
        case .edm:       return "EDM"
        case .hipHop:    return "Hip-Hop"
        case .rock:      return "Rock"
        case .pop:       return "Pop"
        case .vocal:     return "Vocal"
        case .acoustic:  return "Acoustic"
        case .classical: return "Classical"
        }
    }

    /// Short uppercase token for the HUD chip dropdown label.
    public var shortLabel: String { displayName.uppercased() }

    /// Q value per band, indexed by band position in
    /// `TenBandLayout.centerFrequenciesHz` (31, 62, 125, 250, 500, 1k,
    /// 2k, 4k, 8k, 16k).
    public var qVector: [Double] {
        switch self {

        // Octave-clean Butterworth-equivalent. Each band exactly covers
        // its one-octave slot with −3 dB skirts at half-octave. Source:
        // standard graphic-EQ design for octave-spaced bands.
        case .flat:
            return Array(repeating: TenBandLayout.octaveCleanQ, count: 10)

        // Reference / mastering: broader still (Q ≈ 0.7) for transparent
        // tonal shaping. Sonimus/iZotope baseline for "musical" Q.
        case .reference:
            return Array(repeating: 0.707, count: 10)

        // EDM: Audio Intensity calls out 30–50 Hz sub-bass rumble and
        // 60–100 Hz kick. Both want broad warmth (Q ≈ 0.5–0.7); the rest
        // stays octave-clean. Air at 16k is a broad tilt, not surgical.
        //         31    62   125  250  500   1k  2k  4k    8k    16k
        case .edm:
            return [ 0.50, 0.50, 0.70, 1.0, 1.414, 1.414, 1.414, 1.414, 1.0, 0.70 ]

        // Hip-Hop: same Audio Intensity guide — broad sub-bass but a
        // slightly tighter mid-bass (60–100 Hz kick wants definition,
        // not just warmth) and vocal clarity range (800–3 kHz) wants
        // moderate Q for "sit-in-the-mix" boosts.
        case .hipHop:
            return [ 0.60, 0.60, 0.85, 1.0, 1.414, 1.414, 1.0, 1.0, 1.0, 0.70 ]

        // Rock: Audio Intensity — 60–100 Hz punch (moderate Q for
        // definition), 6–8 kHz presence (moderate Q). Across the board
        // we sit at Q ≈ 1 for the "punchy" character; midrange (2–4 k)
        // tightens for guitar/snare presence per SOS instrument tables.
        case .rock:
            return [ 1.0, 1.0, 1.0, 1.0, 1.2, 1.5, 1.5, 1.2, 1.0, 1.0 ]

        // Pop: vocal-and-presence forward. 1–3 kHz (vocal seat) gets
        // tighter Q (2.0) for surgical clarity per emastered's vocal
        // boost guidance. Rest stays octave-clean.
        case .pop:
            return [ 1.414, 1.414, 1.0, 1.0, 1.0, 2.0, 2.0, 1.5, 1.414, 1.414 ]

        // Vocal-centric (podcast, acapella). Higher Q in the vocal
        // formant range to surgically tame or boost. Audio Intensity's
        // "800–3 kHz vocal clarity" gets Q = 2.5 — tight without being
        // a notch.
        case .vocal:
            return [ 1.414, 1.414, 1.0, 1.0, 2.0, 2.5, 2.5, 1.5, 1.414, 1.414 ]

        // Acoustic: gentler "British EQ" character — Q ≈ 1 across the
        // board for analog-feeling broad tonal shaping. iZotope cites
        // this as the standard for material with natural transients
        // that high-Q surgical correction would mangle.
        case .acoustic:
            return Array(repeating: 1.0, count: 10)

        // Classical: maximum transparency, very low Q across all bands.
        // Audio Intensity recommends leaving classical near-neutral;
        // when shaping is needed it should be very broad to avoid
        // colouring the harmonic content. Sonimus's "musical Q ≈ 0.7"
        // rule pegged across the band.
        case .classical:
            return Array(repeating: 0.707, count: 10)
        }
    }
}

public extension TenBandLayout {
    /// The Q value that makes each octave-spaced band cleanly cover its
    /// one-octave slot — −3 dB skirts at half-octave from center.
    /// Derived from BW(octaves) = (2 · asinh(1/(2Q))) / ln(2); setting
    /// BW = 1 gives Q = √2.
    static let octaveCleanQ: Double = 1.4142135623730951
}
