import Foundation

/// Optional headphone/earphone correction bar. Variable band count
/// (whatever the loaded profile specifies), applied after the custom EQ.
public final class CorrectionEQ {
    public let channelCount: Int
    public var isBypassed: Bool = false {
        didSet { onChange?() }
    }
    public private(set) var profile: HeadphoneProfile?

    /// Fired on a control thread whenever a profile loads, unloads, or
    /// bypass changes — used by `RouteDSPChain` to recompute its safety
    /// ceiling. Never invoked from `process`.
    public var onChange: (() -> Void)?

    private var filters: [BiquadFilter] = []
    private var preampLinear: Double = 1.0
    public private(set) var sampleRate: Double

    public init(channelCount: Int = 2, sampleRate: Double) {
        self.channelCount = max(channelCount, 1)
        self.sampleRate = sampleRate
    }

    /// Clears delay lines without dropping the loaded profile. Used when
    /// switching the audio source mid-flight or sweeping in tests.
    public func resetStateOnly() {
        for filter in filters { filter.reset() }
    }

    /// Recomputes every loaded filter's coefficients for a new sample
    /// rate. Mirrors `TenBandEQ.rebuild(at:)` — called once we know the
    /// real audio rate at engine start.
    public func rebuild(at newSampleRate: Double) {
        guard newSampleRate > 0, newSampleRate != sampleRate else { return }
        sampleRate = newSampleRate
        guard let profile else { return }
        for (idx, spec) in profile.filters.enumerated() {
            filters[idx].coefficients = BiquadCoefficients(
                kind: spec.shape.biquadKind,
                sampleRate: sampleRate,
                frequencyHz: spec.frequencyHz,
                gainDb: spec.gainDb,
                q: spec.q
            )
        }
        resetStateOnly()
        onChange?()
    }

    public func loadProfile(_ profile: HeadphoneProfile) {
        self.profile = profile
        self.preampLinear = pow(10, profile.preampDb / 20)
        self.filters = profile.filters.map { spec in
            let filter = BiquadFilter(channelCount: channelCount)
            filter.coefficients = BiquadCoefficients(
                kind: spec.shape.biquadKind,
                sampleRate: sampleRate,
                frequencyHz: spec.frequencyHz,
                gainDb: spec.gainDb,
                q: spec.q
            )
            return filter
        }
        onChange?()
    }

    public func removeProfile() {
        profile = nil
        filters = []
        preampLinear = 1.0
        onChange?()
    }

    @inline(__always)
    public func process(_ input: Double) -> Double {
        guard !isBypassed, profile != nil else { return input }
        var sample = input * preampLinear
        for filter in filters {
            sample = filter.process(sample)
        }
        return sample
    }

    @inline(__always)
    public func processStereo(left: Double, right: Double) -> (Double, Double) {
        guard !isBypassed, profile != nil else { return (left, right) }
        var L = left * preampLinear
        var R = right * preampLinear
        for filter in filters {
            let pair = filter.processStereo(left: L, right: R)
            L = pair.0
            R = pair.1
        }
        return (L, R)
    }

    @inline(__always)
    public func processChannels(_ channels: UnsafeMutableBufferPointer<Double>) {
        guard !isBypassed, profile != nil else { return }
        precondition(channels.count == channelCount)
        for channel in 0..<channelCount {
            channels[channel] *= preampLinear
        }
        for filter in filters {
            for channel in 0..<channelCount {
                channels[channel] = filter.process(channels[channel], channel: channel)
            }
        }
    }
}

public extension ParametricFilterSpec.Shape {
    var biquadKind: BiquadKind {
        switch self {
        case .peaking: return .peaking
        case .lowShelf: return .lowShelf
        case .highShelf: return .highShelf
        }
    }
}
