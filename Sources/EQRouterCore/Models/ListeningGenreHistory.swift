import Foundation

/// Tally of music genres encountered while the app is running.
/// Persisted to UserDefaults. After enough tracks have been observed
/// (`suggestThreshold`), the dominant Apple Music genre maps to one
/// of our `GenrePreset` values and surfaces as a suggested preset
/// in the UI.
public struct ListeningGenreHistory: Codable, Equatable {
    /// Total tracks observed across all sessions.
    public var trackCount: Int
    /// Apple Music genre string (e.g. "Rock", "Hip-Hop/Rap") → count.
    public var genreCounts: [String: Int]
    /// Last update timestamp — purely informational.
    public var lastUpdate: Date?
    /// IDs of suggestions the user has dismissed (so we don't pester).
    public var dismissedGenres: Set<String>

    public init(
        trackCount: Int = 0,
        genreCounts: [String: Int] = [:],
        lastUpdate: Date? = nil,
        dismissedGenres: Set<String> = []
    ) {
        self.trackCount = trackCount
        self.genreCounts = genreCounts
        self.lastUpdate = lastUpdate
        self.dismissedGenres = dismissedGenres
    }

    /// Minimum number of distinct tracks before we'll suggest a preset.
    public static let suggestThreshold: Int = 10

    /// Records one observed Apple Music track. `genre` is the raw
    /// string Music.app gives us (sometimes empty for older tracks).
    public mutating func record(genre: String, at when: Date = Date()) {
        let cleaned = genre.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        trackCount += 1
        genreCounts[cleaned, default: 0] += 1
        lastUpdate = when
    }

    /// The most-played genre, or nil if nothing recorded.
    public var dominantGenre: String? {
        genreCounts.max(by: { $0.value < $1.value })?.key
    }

    /// The preset we'd suggest right now. Nil when:
    ///   - Fewer than `suggestThreshold` tracks have been recorded.
    ///   - The dominant genre's mapped preset has been dismissed.
    public var suggestedPreset: (GenrePreset, source: String)? {
        guard trackCount >= Self.suggestThreshold else { return nil }
        guard let dom = dominantGenre else { return nil }
        guard !dismissedGenres.contains(dom) else { return nil }
        let mapped = GenrePreset.fromAppleMusicGenre(dom)
        return (mapped, source: dom)
    }
}

public extension GenrePreset {
    /// Maps an Apple Music genre string to the closest EQK genre preset.
    /// Apple's strings come straight from the iTunes catalogue; matching
    /// is case-insensitive substring so variants like "Hip-Hop/Rap",
    /// "Alternative Rock" etc. land on the right preset.
    static func fromAppleMusicGenre(_ raw: String) -> GenrePreset {
        let g = raw.lowercased()
        if g.contains("rap") || g.contains("hip-hop") || g.contains("hip hop") {
            return .hipHop
        }
        if g.contains("electronic") || g.contains("dance") || g.contains("edm") || g.contains("house") || g.contains("techno") {
            return .edm
        }
        if g.contains("classical") || g.contains("opera") {
            return .classical
        }
        if g.contains("jazz") || g.contains("blues") {
            return .reference
        }
        if g.contains("acoustic") || g.contains("folk") || g.contains("country") {
            return .acoustic
        }
        if g.contains("spoken") || g.contains("audiobook") || g.contains("podcast") {
            return .vocal
        }
        if g.contains("rock") || g.contains("metal") || g.contains("punk") {
            return .rock
        }
        if g.contains("pop") || g.contains("r&b") || g.contains("soul") {
            return .pop
        }
        return .flat
    }
}
