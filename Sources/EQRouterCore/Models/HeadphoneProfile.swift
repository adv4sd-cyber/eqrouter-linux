import Foundation

/// A downloaded (or bundled) headphone/earphone correction profile.
/// v1 supports fixed-band and parametric data; convolution is out of scope.
public enum HeadphoneWearStyle: String, Equatable, Codable {
    case inEar = "in-ear"
    case overEar = "over-ear"
    case onEar = "on-ear"
    case earbud

    public var displayLabel: String {
        switch self {
        case .inEar: return "IEM"
        case .overEar: return "Over-ear"
        case .onEar: return "On-ear"
        case .earbud: return "Earbud"
        }
    }
}

public struct HeadphoneProfile: Identifiable, Equatable, Codable {
    public enum ProfileType: String, Equatable, Codable {
        case fixedBand
        case parametric
    }

    public let id: String
    public var modelName: String
    public var sourceProject: String
    public var measurementProvider: String?
    public var type: ProfileType
    public var preampDb: Double
    public var filters: [ParametricFilterSpec]
    public var sourceURL: String?
    public var downloadTimestamp: Date?
    public var wearStyle: HeadphoneWearStyle?
    public var isFeatured: Bool

    public init(
        id: String,
        modelName: String,
        sourceProject: String,
        measurementProvider: String? = nil,
        type: ProfileType,
        preampDb: Double,
        filters: [ParametricFilterSpec],
        sourceURL: String? = nil,
        downloadTimestamp: Date? = nil,
        wearStyle: HeadphoneWearStyle? = nil,
        isFeatured: Bool = false
    ) {
        self.id = id
        self.modelName = modelName
        self.sourceProject = sourceProject
        self.measurementProvider = measurementProvider
        self.type = type
        self.preampDb = preampDb
        self.filters = filters
        self.sourceURL = sourceURL
        self.downloadTimestamp = downloadTimestamp
        self.wearStyle = wearStyle
        self.isFeatured = isFeatured
    }

    /// Lookup for known bundled profiles by id. Used when applying a
    /// saved preset: the preset stores the profile id (not the full
    /// filter set), and this maps id back to the live profile. Returns
    /// nil if the id is unknown — preset application then proceeds
    /// without correction rather than failing outright.
    public static func bundled(id: String) -> HeadphoneProfile? {
        BundledProfileCatalog.shared.idIndex[id]
    }
}
