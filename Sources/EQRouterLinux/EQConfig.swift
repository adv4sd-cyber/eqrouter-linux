import Foundation
import EQRouterCore

/// The full user-facing EQ configuration — the Linux port's single route.
///
/// The macOS app is multi-route (one per captured process); on Linux the
/// pipe engine processes one system-wide stream, so there is exactly one
/// live configuration. It is serializable to `~/.config/eqrouter/config.json`
/// and is the payload behind every web-UI control.
public struct EQConfig: Codable, Equatable {
    /// 10 band gains in dB, indexed by `TenBandLayout.centerFrequenciesHz`.
    public var bandGains: [Double]
    public var customEQBypassed: Bool
    public var genre: GenrePreset

    /// Bundled headphone-correction profile id (see `HeadphoneProfile.bundled(id:)`),
    /// or nil for none.
    public var correctionProfileID: String?
    public var correctionBypassed: Bool

    /// User-imported AutoEq / EqualizerAPO parametric preset, applied in a
    /// stage separate from the vetted correction profiles.
    public var importedProfileName: String?
    public var importedFilters: [ParametricFilterSpec]
    public var importedPreampDb: Double

    public var outputTrimDb: Double
    public var routeGainDb: Double
    public var isMuted: Bool
    public var safetyCeilingEnabled: Bool

    public init(
        bandGains: [Double] = Array(repeating: 0, count: TenBandLayout.centerFrequenciesHz.count),
        customEQBypassed: Bool = false,
        genre: GenrePreset = .flat,
        correctionProfileID: String? = nil,
        correctionBypassed: Bool = false,
        importedProfileName: String? = nil,
        importedFilters: [ParametricFilterSpec] = [],
        importedPreampDb: Double = 0,
        outputTrimDb: Double = 0,
        routeGainDb: Double = 0,
        isMuted: Bool = false,
        safetyCeilingEnabled: Bool = false
    ) {
        let n = TenBandLayout.centerFrequenciesHz.count
        // Tolerate short/long saved arrays rather than crashing on a stale file.
        var gains = bandGains
        if gains.count < n { gains += Array(repeating: 0, count: n - gains.count) }
        if gains.count > n { gains = Array(gains.prefix(n)) }
        self.bandGains = gains
        self.customEQBypassed = customEQBypassed
        self.genre = genre
        self.correctionProfileID = correctionProfileID
        self.correctionBypassed = correctionBypassed
        self.importedProfileName = importedProfileName
        self.importedFilters = importedFilters
        self.importedPreampDb = importedPreampDb
        self.outputTrimDb = outputTrimDb
        self.routeGainDb = routeGainDb
        self.isMuted = isMuted
        self.safetyCeilingEnabled = safetyCeilingEnabled
    }

    public var hasImportedProfile: Bool { !importedFilters.isEmpty }

    /// The imported parametric preset expressed as a `HeadphoneProfile` so
    /// it can be loaded into a `CorrectionEQ` stage.
    public var importedProfileAsHeadphone: HeadphoneProfile? {
        guard hasImportedProfile else { return nil }
        return HeadphoneProfile(
            id: "imported:\(importedProfileName ?? "custom")",
            modelName: importedProfileName ?? "Imported",
            sourceProject: "User import",
            type: .parametric,
            preampDb: importedPreampDb,
            filters: importedFilters
        )
    }

    /// The resolved correction profile, or nil.
    public var correctionProfile: HeadphoneProfile? {
        correctionProfileID.flatMap(HeadphoneProfile.bundled(id:))
    }
}
