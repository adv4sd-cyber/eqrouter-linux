import Foundation

/// Fixed 10-band layout for the always-present custom EQ bar.
/// Internally each band is a peaking biquad; the band set is fixed for v1
/// but nothing here prevents adding parametric bands later — a route's
/// custom EQ is just an ordered list of `EQBandState`.
public enum TenBandLayout {
    public static let centerFrequenciesHz: [Double] = [
        31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]
    /// √2 makes octave-spaced bands cleanly cover one octave each, with
    /// −3 dB skirts at half-octave from center. The old Q = 1.0 had
    /// adjacent bands' −3 dB points overlapping, causing constructive
    /// build-up between adjacent boosts. See `octaveCleanQ` below.
    public static let defaultQ: Double = 1.4142135623730951
    public static let gainRangeDb: ClosedRange<Double> = -12...12
}

public struct EQBandState: Identifiable, Equatable, Codable {
    public let id: Int
    public var frequencyHz: Double
    public var gainDb: Double
    public var q: Double

    public init(id: Int, frequencyHz: Double, gainDb: Double = 0, q: Double = TenBandLayout.defaultQ) {
        self.id = id
        self.frequencyHz = frequencyHz
        self.gainDb = gainDb
        self.q = q
    }
}

public struct ParametricFilterSpec: Equatable, Codable {
    public enum Shape: String, Equatable, Codable {
        case peaking
        case lowShelf
        case highShelf
    }

    public var shape: Shape
    public var frequencyHz: Double
    public var gainDb: Double
    public var q: Double

    public init(shape: Shape, frequencyHz: Double, gainDb: Double, q: Double) {
        self.shape = shape
        self.frequencyHz = frequencyHz
        self.gainDb = gainDb
        self.q = q
    }
}
