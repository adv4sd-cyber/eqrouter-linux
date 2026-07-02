import Foundation

/// Plain value type returned by the parser. Represents a freshly-read
/// parametric EQ file with no opinion about whether it ends up as a
/// correction profile, a saved user preset, or something else entirely
/// — that's the caller's call.
///
/// The bundled-correction `HeadphoneProfile` slot is intentionally NOT
/// what we produce here: that slot is reserved for vetted, credible
/// measurement-derived profiles (Oriveti OD200, etc.) and shouldn't
/// be polluted with arbitrary community-submitted files.
public struct ImportedEQ: Equatable {
    public var modelName: String
    public var preampDb: Double
    public var filters: [ParametricFilterSpec]

    public init(modelName: String, preampDb: Double, filters: [ParametricFilterSpec]) {
        self.modelName = modelName
        self.preampDb = preampDb
        self.filters = filters
    }
}

/// Parser for the de-facto standard parametric-EQ text formats used by
/// AutoEq (`*ParametricEQ.txt`) and EqualizerAPO (config snippets). The
/// two formats are syntactically identical line-for-line, which is why
/// one parser handles both.
///
/// Reference syntax (this matches the OD200 profile shipped in
/// `OrivetiOD200.swift`):
/// ```
/// Preamp: -6.7 dB
/// Filter 1: ON LSC Fc 105 Hz Gain 12.2 dB Q 0.70
/// Filter 2: ON PK Fc 61 Hz Gain -10.1 dB Q 0.34
/// Filter 6: ON HSC Fc 10000 Hz Gain 1.3 dB Q 0.70
/// ```
///
/// Filter type tokens:
///   - `PK`           → peaking
///   - `LS` / `LSC`   → low shelf  (cookbook variant; both spellings seen)
///   - `HS` / `HSC`   → high shelf
///
/// Unknown filter types (e.g. `NO` for "no filter", or any new tokens)
/// and unrecognised lines are silently skipped — the parser is forgiving
/// so partial files still produce a usable result. Only a file with no
/// recognisable filters at all errors out.
public enum AutoEqParser {
    public enum ParseError: Error, Equatable {
        case noFiltersFound
    }

    private static let filterRegex = try? NSRegularExpression(
        pattern: #"^Filter\s+\d+:\s+ON\s+(\w+)\s+Fc\s+([\d.]+)\s+Hz\s+Gain\s+(-?[\d.]+)\s+dB\s+Q\s+([\d.]+)"#,
        options: [.caseInsensitive]
    )

    /// Parses an AutoEq / EqualizerAPO parametric text file into an
    /// `ImportedEQ` value. The caller assigns its meaning (saved preset,
    /// curve preview, etc.). `modelName` is what the user will see;
    /// typically the file name minus extension.
    public static func parseParametric(
        _ text: String,
        modelName: String
    ) throws -> ImportedEQ {
        var preamp = 0.0
        var filters: [ParametricFilterSpec] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if let p = preampValue(line: line) {
                preamp = p
                continue
            }
            if let spec = filterSpec(line: line) {
                filters.append(spec)
                continue
            }
            // Anything else (notes, blank lines, headers) is ignored.
        }

        guard !filters.isEmpty else { throw ParseError.noFiltersFound }
        return ImportedEQ(modelName: modelName, preampDb: preamp, filters: filters)
    }

    // MARK: - Line parsers

    /// Matches `Preamp: -6.7 dB`. Returns the dB value or nil.
    private static func preampValue(line: String) -> Double? {
        guard line.hasPrefix("Preamp") else { return nil }
        let trimmed = line
            .replacingOccurrences(of: "Preamp:", with: "")
            .replacingOccurrences(of: "dB", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(trimmed)
    }

    /// Matches `Filter 1: ON LSC Fc 105 Hz Gain 12.2 dB Q 0.70`.
    /// Handles signed gains and decimal Qs.
    private static func filterSpec(line: String) -> ParametricFilterSpec? {
        guard line.lowercased().hasPrefix("filter") else { return nil }

        guard let regex = filterRegex,
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 5,
              let typeRange = Range(match.range(at: 1), in: line),
              let fcRange   = Range(match.range(at: 2), in: line),
              let gainRange = Range(match.range(at: 3), in: line),
              let qRange    = Range(match.range(at: 4), in: line),
              let fc   = Double(line[fcRange]),
              let gain = Double(line[gainRange]),
              let q    = Double(line[qRange])
        else { return nil }

        let typeToken = String(line[typeRange]).uppercased()
        let shape: ParametricFilterSpec.Shape
        switch typeToken {
        case "PK":          shape = .peaking
        case "LS", "LSC":   shape = .lowShelf
        case "HS", "HSC":   shape = .highShelf
        default:            return nil // skip unknown filter types
        }
        return ParametricFilterSpec(shape: shape, frequencyHz: fc, gainDb: gain, q: q)
    }
}
