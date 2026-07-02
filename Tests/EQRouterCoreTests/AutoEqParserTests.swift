import Testing
import Foundation
@testable import EQRouterCore

struct AutoEqParserTests {

    /// Verbatim text from AutoEq's "Oriveti OD200 ParametricEQ.txt"
    /// (Jaytiss measurement). Parsing this MUST produce exactly the
    /// values we ship hardcoded in `HeadphoneProfile.orivetiOD200` —
    /// that's how we know the parser is correct.
    private let od200Text = """
    Preamp: -6.7 dB
    Filter 1: ON LSC Fc 105 Hz Gain 12.2 dB Q 0.70
    Filter 2: ON PK Fc 61 Hz Gain -10.1 dB Q 0.34
    Filter 3: ON PK Fc 6252 Hz Gain 5.2 dB Q 1.94
    Filter 4: ON PK Fc 768 Hz Gain 2.2 dB Q 1.01
    Filter 5: ON PK Fc 5292 Hz Gain 2.0 dB Q 3.85
    Filter 6: ON HSC Fc 10000 Hz Gain 1.3 dB Q 0.70
    Filter 7: ON PK Fc 2732 Hz Gain -1.0 dB Q 2.39
    Filter 8: ON PK Fc 1935 Hz Gain 0.7 dB Q 3.43
    Filter 9: ON PK Fc 9178 Hz Gain 0.5 dB Q 3.51
    Filter 10: ON PK Fc 7529 Hz Gain -1.0 dB Q 6.00
    """

    @Test func parsesPreampAndAllTenFiltersFromOD200() throws {
        let imported = try AutoEqParser.parseParametric(od200Text, modelName: "OD200")
        #expect(imported.modelName == "OD200")
        #expect(abs(imported.preampDb - (-6.7)) < 1e-9)
        #expect(imported.filters.count == 10)
    }

    @Test func parsedFiltersMatchBundledOD200ExactValues() throws {
        let imported = try AutoEqParser.parseParametric(od200Text, modelName: "OD200")
        let bundled  = HeadphoneProfile.orivetiOD200.filters

        for (idx, spec) in imported.filters.enumerated() {
            let expected = bundled[idx]
            #expect(spec.shape == expected.shape,
                    "filter \(idx): shape mismatch")
            #expect(abs(spec.frequencyHz - expected.frequencyHz) < 1e-9,
                    "filter \(idx): freq mismatch")
            #expect(abs(spec.gainDb - expected.gainDb) < 1e-9,
                    "filter \(idx): gain mismatch")
            #expect(abs(spec.q - expected.q) < 1e-9,
                    "filter \(idx): Q mismatch")
        }
    }

    @Test func recognisesAllStandardFilterTypeTokens() throws {
        // PK, LS, LSC, HS, HSC must all parse. LS / HS are seen in
        // EqualizerAPO output; LSC / HSC in AutoEq output.
        let text = """
        Preamp: 0.0 dB
        Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.41
        Filter 2: ON LS Fc 100 Hz Gain 4.0 dB Q 0.70
        Filter 3: ON LSC Fc 200 Hz Gain 5.0 dB Q 0.70
        Filter 4: ON HS Fc 8000 Hz Gain 6.0 dB Q 0.70
        Filter 5: ON HSC Fc 12000 Hz Gain 7.0 dB Q 0.70
        """
        let imported = try AutoEqParser.parseParametric(text, modelName: "Mixed")
        #expect(imported.filters.count == 5)
        #expect(imported.filters[0].shape == .peaking)
        #expect(imported.filters[1].shape == .lowShelf)
        #expect(imported.filters[2].shape == .lowShelf)
        #expect(imported.filters[3].shape == .highShelf)
        #expect(imported.filters[4].shape == .highShelf)
    }

    @Test func unknownFilterTokensAreSilentlySkipped() throws {
        // Real-world AutoEq output occasionally includes `NO` (no
        // filter) lines or hand-edited gibberish. The parser must
        // skip those rather than fail outright.
        let text = """
        Preamp: -1.0 dB
        Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.41
        Filter 2: ON NO Fc 0 Hz Gain 0 dB Q 0
        Filter 3: ON PK Fc 2000 Hz Gain 2.0 dB Q 1.0
        Filter 4: garbage line that doesn't match anything
        """
        let imported = try AutoEqParser.parseParametric(text, modelName: "x")
        #expect(imported.filters.count == 2)
        #expect(imported.filters[0].frequencyHz == 1000)
        #expect(imported.filters[1].frequencyHz == 2000)
    }

    @Test func filesWithNoRecognisableFiltersThrow() {
        let text = """
        Preamp: 0.0 dB
        # This is just a comment.
        Some other garbage.
        """
        do {
            _ = try AutoEqParser.parseParametric(text, modelName: "empty")
            Issue.record("expected ParseError.noFiltersFound")
        } catch AutoEqParser.ParseError.noFiltersFound {
            // expected
        } catch {
            Issue.record("expected ParseError.noFiltersFound, got \(error)")
        }
    }

    @Test func commentsAndBlankLinesAreIgnored() throws {
        let text = """
        # A leading comment line
        Preamp: -3.0 dB

        # Another comment
        Filter 1: ON PK Fc 500 Hz Gain 4.0 dB Q 1.0

        """
        let imported = try AutoEqParser.parseParametric(text, modelName: "c")
        #expect(imported.preampDb == -3.0)
        #expect(imported.filters.count == 1)
    }

    @Test func signedAndDecimalNumbersParseCorrectly() throws {
        // Negative gains and decimal Qs (`0.70`, `12.2`) are the common
        // forms — make sure both parse without surprises.
        let text = """
        Preamp: -12.5 dB
        Filter 1: ON PK Fc 1234.5 Hz Gain -7.75 dB Q 0.500
        """
        let imported = try AutoEqParser.parseParametric(text, modelName: "x")
        #expect(imported.preampDb == -12.5)
        #expect(imported.filters[0].frequencyHz == 1234.5)
        #expect(imported.filters[0].gainDb == -7.75)
        #expect(imported.filters[0].q == 0.5)
    }
}
