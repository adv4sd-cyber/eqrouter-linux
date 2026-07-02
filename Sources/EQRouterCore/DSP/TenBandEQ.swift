import Foundation

/// The always-present custom EQ bar. Fixed 10-band peaking design for v1;
/// each band is one biquad processed in series.
public final class TenBandEQ {
    public private(set) var bands: [EQBandState]
    public let channelCount: Int
    public var isBypassed: Bool = false {
        didSet { onChange?() }
    }

    /// Fired on a control thread whenever gain, reset, or bypass changes —
    /// used by `RouteDSPChain` to recompute its safety ceiling. Never
    /// invoked from `process`.
    public var onChange: (() -> Void)?

    private var filters: [BiquadFilter]
    public private(set) var sampleRate: Double

    /// Coefficient snapshot for the current band gains. Computed on demand
    /// from `bands` + `sampleRate`; not the same object as the filters'
    /// internal coefficients (which are what's actually used for audio).
    /// Used by the safety ceiling and frequency-response tests.
    public var currentCoefficients: [BiquadCoefficients] {
        bands.map {
            BiquadCoefficients(
                kind: .peaking,
                sampleRate: sampleRate,
                frequencyHz: $0.frequencyHz,
                gainDb: $0.gainDb,
                q: $0.q
            )
        }
    }

    public init(channelCount: Int = 2, sampleRate: Double) {
        let resolvedChannelCount = max(channelCount, 1)
        self.channelCount = resolvedChannelCount
        self.sampleRate = sampleRate
        self.bands = TenBandLayout.centerFrequenciesHz.enumerated().map { index, freq in
            EQBandState(id: index, frequencyHz: freq)
        }
        self.filters = bands.map { _ in BiquadFilter(channelCount: resolvedChannelCount) }
        rebuildAllCoefficients()
    }

    /// Rebuilds every biquad's coefficients for a new sample rate, keeping
    /// the user's gain/Q settings. Called when audio capture starts and
    /// the actual tap sample rate becomes known (it can differ from the
    /// rate the chain was constructed with). Clears delay lines so the
    /// new coefficients don't mix with state designed for the old rate.
    public func rebuild(at newSampleRate: Double) {
        guard newSampleRate > 0, newSampleRate != sampleRate else { return }
        sampleRate = newSampleRate
        rebuildAllCoefficients()
        resetStateOnly()
        onChange?()
    }

    /// Applies a fresh per-band Q vector and rebuilds coefficients via
    /// the existing atomic-publish path. Used by
    /// `RouteDSPChain.recomputeEffectiveQs(...)` when the loaded
    /// correction profile or selected genre changes.
    public func applyQVector(_ qValues: [Double]) {
        precondition(qValues.count == bands.count)
        for index in bands.indices {
            bands[index].q = qValues[index]
            filters[index].coefficients = BiquadCoefficients(
                kind: .peaking,
                sampleRate: sampleRate,
                frequencyHz: bands[index].frequencyHz,
                gainDb: bands[index].gainDb,
                q: bands[index].q
            )
        }
        onChange?()
    }

    /// Call from a non-render thread (UI / controller). Publishes new
    /// coefficients for one band; render thread only ever reads
    /// `BiquadFilter.coefficients`, never recomputes it.
    public func setGain(_ gainDb: Double, forBandID bandID: Int) {
        guard let index = bands.firstIndex(where: { $0.id == bandID }) else { return }
        let clamped = min(max(gainDb, TenBandLayout.gainRangeDb.lowerBound), TenBandLayout.gainRangeDb.upperBound)
        bands[index].gainDb = clamped
        filters[index].coefficients = BiquadCoefficients(
            kind: .peaking,
            sampleRate: sampleRate,
            frequencyHz: bands[index].frequencyHz,
            gainDb: clamped,
            q: bands[index].q
        )
        onChange?()
    }

    public func reset() {
        for index in bands.indices {
            bands[index].gainDb = 0
            filters[index].coefficients = BiquadCoefficients(
                kind: .peaking,
                sampleRate: sampleRate,
                frequencyHz: bands[index].frequencyHz,
                gainDb: 0,
                q: bands[index].q
            )
            filters[index].reset()
        }
        onChange?()
    }

    /// Clears the biquad delay lines without changing gains. Used when
    /// switching the audio source mid-flight (a fresh process tap), or by
    /// the offline measurement harness between frequency sweeps. The
    /// audible filter shape is preserved.
    public func resetStateOnly() {
        for filter in filters { filter.reset() }
    }

    private func rebuildAllCoefficients() {
        for index in bands.indices {
            filters[index].coefficients = BiquadCoefficients(
                kind: .peaking,
                sampleRate: sampleRate,
                frequencyHz: bands[index].frequencyHz,
                gainDb: bands[index].gainDb,
                q: bands[index].q
            )
        }
    }

    @inline(__always)
    public func process(_ input: Double) -> Double {
        guard !isBypassed else { return input }
        var sample = input
        for filter in filters {
            sample = filter.process(sample)
        }
        return sample
    }

    @inline(__always)
    public func processStereo(left: Double, right: Double) -> (Double, Double) {
        guard !isBypassed else { return (left, right) }
        var L = left
        var R = right
        for filter in filters {
            let pair = filter.processStereo(left: L, right: R)
            L = pair.0
            R = pair.1
        }
        return (L, R)
    }

    @inline(__always)
    public func processChannels(_ channels: UnsafeMutableBufferPointer<Double>) {
        guard !isBypassed else { return }
        precondition(channels.count == channelCount)
        for filter in filters {
            for channel in 0..<channelCount {
                channels[channel] = filter.process(channels[channel], channel: channel)
            }
        }
    }
}
