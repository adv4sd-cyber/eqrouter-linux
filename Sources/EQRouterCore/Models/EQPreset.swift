import Foundation

/// A saved snapshot of the user's EQ tuning. Designed to be cross-route
/// portable — a preset captured on "Music" can be applied to "Safari".
///
/// Captures only the *user-meaningful* state:
///   - 10 band gains (Q is derived from genre + correction, not stored)
///   - Selected genre
///   - Correction profile reference (by id, not embedded — lets new
///     versions of a profile reach saved presets)
///   - Output trim
///
/// Intentionally *not* captured:
///   - Bypass states (transport-level toggles, not preset content)
///   - Mute, route gain, target output device (live transport)
///   - Sample rate (recomputed when audio engine starts)
public struct EQPreset: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var bandGains: [Double]
    public var selectedGenre: GenrePreset
    public var correctionProfileID: String?
    public var outputTrimDb: Double

    /// Parametric filters carried by *imported* presets (e.g. an
    /// AutoEq community file). When non-empty, the chain loads them
    /// into a dedicated `userParametricEQ` stage at apply time.
    ///
    /// For slider-based "Save current as..." presets these stay
    /// empty — the band gains alone reproduce the user's tuning.
    public var parametricFilters: [ParametricFilterSpec]
    public var parametricPreampDb: Double

    public var hasParametricFilters: Bool { !parametricFilters.isEmpty }

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        bandGains: [Double],
        selectedGenre: GenrePreset,
        correctionProfileID: String?,
        outputTrimDb: Double,
        parametricFilters: [ParametricFilterSpec] = [],
        parametricPreampDb: Double = 0
    ) {
        precondition(bandGains.count == TenBandLayout.centerFrequenciesHz.count,
                     "EQPreset must have exactly \(TenBandLayout.centerFrequenciesHz.count) band gains")
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.bandGains = bandGains
        self.selectedGenre = selectedGenre
        self.correctionProfileID = correctionProfileID
        self.outputTrimDb = outputTrimDb
        self.parametricFilters = parametricFilters
        self.parametricPreampDb = parametricPreampDb
    }

    // Allow older saved presets (written before the parametric fields
    // were added) to decode cleanly — missing keys default to empty.
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, bandGains, selectedGenre,
             correctionProfileID, outputTrimDb,
             parametricFilters, parametricPreampDb
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.bandGains = try c.decode([Double].self, forKey: .bandGains)
        self.selectedGenre = try c.decode(GenrePreset.self, forKey: .selectedGenre)
        self.correctionProfileID = try c.decodeIfPresent(String.self, forKey: .correctionProfileID)
        self.outputTrimDb = try c.decode(Double.self, forKey: .outputTrimDb)
        self.parametricFilters = (try? c.decode([ParametricFilterSpec].self, forKey: .parametricFilters)) ?? []
        self.parametricPreampDb = (try? c.decode(Double.self, forKey: .parametricPreampDb)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(bandGains, forKey: .bandGains)
        try c.encode(selectedGenre, forKey: .selectedGenre)
        try c.encodeIfPresent(correctionProfileID, forKey: .correctionProfileID)
        try c.encode(outputTrimDb, forKey: .outputTrimDb)
        if !parametricFilters.isEmpty {
            try c.encode(parametricFilters, forKey: .parametricFilters)
            try c.encode(parametricPreampDb, forKey: .parametricPreampDb)
        }
    }
}
