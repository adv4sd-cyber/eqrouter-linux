import Foundation

/// Bundled correction profile sourced from AutoEq (Jaytiss measurement).
/// AutoEq's "LSC"/"HSC" filter types are RBJ low/high shelf filters
/// parametrized by Q (cookbook variant); "PK" is a standard peaking filter.
///
/// Source: jaakkopasanen/AutoEq, results/Jaytiss/in-ear/Oriveti OD200/Oriveti OD200 ParametricEQ.txt
///
/// Preamp deliberately set to 0 dB rather than AutoEq's recommended
/// −6.7 dB. The per-band ±12 dB clamp on the custom EQ is enough of a
/// safeguard; pre-attenuating the source before it reaches the user's
/// EQ would make it impossible to test extremes audibly.
public extension HeadphoneProfile {
    static let orivetiOD200 = HeadphoneProfile(
        id: "autoeq.jaytiss.oriveti-od200",
        modelName: "Oriveti OD200",
        sourceProject: "AutoEq",
        measurementProvider: "Jaytiss",
        type: .parametric,
        preampDb: 0,
        filters: [
            ParametricFilterSpec(shape: .lowShelf, frequencyHz: 105, gainDb: 12.2, q: 0.70),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 61, gainDb: -10.1, q: 0.34),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 6252, gainDb: 5.2, q: 1.94),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 768, gainDb: 2.2, q: 1.01),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 5292, gainDb: 2.0, q: 3.85),
            ParametricFilterSpec(shape: .highShelf, frequencyHz: 10000, gainDb: 1.3, q: 0.70),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 2732, gainDb: -1.0, q: 2.39),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 1935, gainDb: 0.7, q: 3.43),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 9178, gainDb: 0.5, q: 3.51),
            ParametricFilterSpec(shape: .peaking, frequencyHz: 7529, gainDb: -1.0, q: 6.00)
        ],
        sourceURL: "https://github.com/jaakkopasanen/AutoEq/blob/master/results/Jaytiss/in-ear/Oriveti%20OD200/Oriveti%20OD200%20ParametricEQ.txt",
        wearStyle: .inEar,
        isFeatured: true
    )
}
