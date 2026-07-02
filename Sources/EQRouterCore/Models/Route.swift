import Foundation

public enum RouteHealth: String, Equatable, Codable {
    case idle
    case active
    case lost
    case verifying
    case verified
    case attention
    case paused
    case blocked
}

public enum RouteCaptureMode: String, Equatable, Codable {
    case multichannelStream
    case stereoFallback
}

/// A persistent app route. Keyed by bundle ID + a stable internal ID rather
/// than PID, since PIDs are only valid for the lifetime of one process run.
public struct AppRoute: Identifiable, Equatable, Codable {
    public let id: UUID
    public var bundleID: String
    public var displayName: String
    public var targetOutputDeviceID: String?
    public var targetOutputStreamIndex: UInt?
    public var gainDb: Double
    public var isMuted: Bool
    public var customEQBands: [EQBandState]
    public var customEQBypassed: Bool
    public var outputTrimDb: Double
    public var correctionProfile: HeadphoneProfile?
    public var correctionBypassed: Bool
    public var selectedGenre: GenrePreset
    public var health: RouteHealth
    public var effectiveOutputChannelCount: Int
    public var effectiveOutputLayoutDescription: String
    public var lastCaptureMode: RouteCaptureMode
    public var importedProfileName: String?
    public var importedParametricFilters: [ParametricFilterSpec]
    public var importedParametricPreampDb: Double

    public var hasImportedParametricProfile: Bool { !importedParametricFilters.isEmpty }
    public var effectiveFormatBadge: String {
        lastCaptureMode == .stereoFallback ? "Stereo Fallback" : effectiveOutputLayoutDescription
    }

    public init(
        id: UUID = UUID(),
        bundleID: String,
        displayName: String,
        targetOutputDeviceID: String? = nil,
        targetOutputStreamIndex: UInt? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.targetOutputDeviceID = targetOutputDeviceID
        self.targetOutputStreamIndex = targetOutputStreamIndex
        self.gainDb = 0
        self.isMuted = false
        self.customEQBands = TenBandLayout.centerFrequenciesHz.enumerated().map { index, freq in
            EQBandState(id: index, frequencyHz: freq)
        }
        self.customEQBypassed = false
        self.outputTrimDb = 0
        self.correctionProfile = nil
        self.correctionBypassed = false
        self.selectedGenre = .flat
        self.health = .idle
        self.effectiveOutputChannelCount = 2
        self.effectiveOutputLayoutDescription = "Stereo"
        self.lastCaptureMode = .stereoFallback
        self.importedProfileName = nil
        self.importedParametricFilters = []
        self.importedParametricPreampDb = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleID
        case displayName
        case targetOutputDeviceID
        case targetOutputStreamIndex
        case gainDb
        case isMuted
        case customEQBands
        case customEQBypassed
        case outputTrimDb
        case correctionProfileID
        case correctionBypassed
        case selectedGenre
        case health
        case effectiveOutputChannelCount
        case effectiveOutputLayoutDescription
        case lastCaptureMode
        case importedProfileName
        case importedParametricFilters
        case importedParametricPreampDb
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        displayName = try c.decode(String.self, forKey: .displayName)
        targetOutputDeviceID = try c.decodeIfPresent(String.self, forKey: .targetOutputDeviceID)
        targetOutputStreamIndex = try c.decodeIfPresent(UInt.self, forKey: .targetOutputStreamIndex)
        gainDb = try c.decode(Double.self, forKey: .gainDb)
        isMuted = try c.decode(Bool.self, forKey: .isMuted)
        customEQBands = try c.decode([EQBandState].self, forKey: .customEQBands)
        customEQBypassed = try c.decode(Bool.self, forKey: .customEQBypassed)
        outputTrimDb = try c.decode(Double.self, forKey: .outputTrimDb)
        let correctionProfileID = try c.decodeIfPresent(String.self, forKey: .correctionProfileID)
        correctionProfile = correctionProfileID.flatMap(HeadphoneProfile.bundled(id:))
        correctionBypassed = try c.decode(Bool.self, forKey: .correctionBypassed)
        selectedGenre = try c.decode(GenrePreset.self, forKey: .selectedGenre)
        health = try c.decodeIfPresent(RouteHealth.self, forKey: .health) ?? .idle
        effectiveOutputChannelCount =
            (try? c.decode(Int.self, forKey: .effectiveOutputChannelCount)) ?? 2
        effectiveOutputLayoutDescription =
            (try? c.decode(String.self, forKey: .effectiveOutputLayoutDescription)) ?? "Stereo"
        lastCaptureMode =
            (try? c.decode(RouteCaptureMode.self, forKey: .lastCaptureMode)) ?? .stereoFallback
        importedProfileName = try c.decodeIfPresent(String.self, forKey: .importedProfileName)
        importedParametricFilters =
            (try? c.decode([ParametricFilterSpec].self, forKey: .importedParametricFilters)) ?? []
        importedParametricPreampDb =
            (try? c.decode(Double.self, forKey: .importedParametricPreampDb)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(targetOutputDeviceID, forKey: .targetOutputDeviceID)
        try c.encodeIfPresent(targetOutputStreamIndex, forKey: .targetOutputStreamIndex)
        try c.encode(gainDb, forKey: .gainDb)
        try c.encode(isMuted, forKey: .isMuted)
        try c.encode(customEQBands, forKey: .customEQBands)
        try c.encode(customEQBypassed, forKey: .customEQBypassed)
        try c.encode(outputTrimDb, forKey: .outputTrimDb)
        try c.encodeIfPresent(correctionProfile?.id, forKey: .correctionProfileID)
        try c.encode(correctionBypassed, forKey: .correctionBypassed)
        try c.encode(selectedGenre, forKey: .selectedGenre)
        try c.encode(health, forKey: .health)
        try c.encode(effectiveOutputChannelCount, forKey: .effectiveOutputChannelCount)
        try c.encode(effectiveOutputLayoutDescription, forKey: .effectiveOutputLayoutDescription)
        try c.encode(lastCaptureMode, forKey: .lastCaptureMode)
        try c.encodeIfPresent(importedProfileName, forKey: .importedProfileName)
        if hasImportedParametricProfile {
            try c.encode(importedParametricFilters, forKey: .importedParametricFilters)
            try c.encode(importedParametricPreampDb, forKey: .importedParametricPreampDb)
        }
    }
}
