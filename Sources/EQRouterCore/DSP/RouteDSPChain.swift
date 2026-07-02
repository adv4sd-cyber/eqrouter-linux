import Foundation

/// Per-route DSP chain, processing order matches the design doc:
/// route gain/mute -> custom EQ -> correction EQ -> output safety ceiling
/// -> limiter, with input/output metering at the edges. One instance per
/// channel (caller fans out for stereo).
public final class RouteDSPChain {
    public let channelCount: Int
    public let customEQ: TenBandEQ
    public let correctionEQ: CorrectionEQ
    /// Parametric stage dedicated to *user-imported* presets (e.g. an
    /// AutoEq community file loaded via SAVED → Import). Reuses the
    /// `CorrectionEQ` engine but is conceptually separate from
    /// `correctionEQ`, which stays reserved for vetted hardware
    /// correction profiles like the bundled OD200.
    public let userParametricEQ: CorrectionEQ
    public let limiter: Limiter
    public let inputMeter: PeakMeter
    public let outputMeter: PeakMeter

    public private(set) var routeGainDb: Double = 0
    public private(set) var outputTrimDb: Double = 0
    public var isMuted: Bool = false

    /// When true, the chain auto-attenuates so the worst-case post-EQ peak
    /// can never exceed unity gain. When false (default), per-band ±12 dB
    /// clamps + the soft saturator are the only safeguards — the user
    /// hears exactly the EQ shape they dial in, without an invisible
    /// makeup attenuation cancelling out their boosts.
    ///
    /// Off by default because automatic makeup felt like the EQ "did
    /// nothing" at extremes — every boost was being silently cancelled
    /// by an equal-and-opposite ceiling attenuation.
    public var safetyCeilingEnabled: Bool = false {
        didSet { recomputeSafetyCeiling() }
    }

    /// True when the ceiling is enabled AND currently attenuating this
    /// route. Surfaced to the UI as a small status indicator.
    public private(set) var isSafetyCeilingActive: Bool = false

    private var gainLinear: Double = 1.0
    private var outputTrimLinear: Double = 1.0
    private var ceilingAttenuationLinear: Double = 1.0
    private let frameScratch: UnsafeMutablePointer<Double>

    public init(channelCount: Int = 2, sampleRate: Double) {
        self.channelCount = max(channelCount, 1)
        customEQ = TenBandEQ(channelCount: self.channelCount, sampleRate: sampleRate)
        correctionEQ = CorrectionEQ(channelCount: self.channelCount, sampleRate: sampleRate)
        userParametricEQ = CorrectionEQ(channelCount: self.channelCount, sampleRate: sampleRate)
        limiter = Limiter(sampleRate: sampleRate)
        inputMeter = PeakMeter(sampleRate: sampleRate)
        outputMeter = PeakMeter(sampleRate: sampleRate)
        frameScratch = UnsafeMutablePointer<Double>.allocate(capacity: self.channelCount)
        frameScratch.initialize(repeating: 0, count: self.channelCount)

        customEQ.onChange = { [weak self] in self?.recomputeSafetyCeiling() }
        correctionEQ.onChange = { [weak self] in self?.recomputeSafetyCeiling() }
        userParametricEQ.onChange = { [weak self] in self?.recomputeSafetyCeiling() }
    }

    deinit {
        frameScratch.deinitialize(count: channelCount)
        frameScratch.deallocate()
    }

    public func setRouteGain(_ db: Double) {
        routeGainDb = db
        gainLinear = pow(10, db / 20)
        recomputeSafetyCeiling()
    }

    public func setOutputTrim(_ db: Double) {
        outputTrimDb = db
        outputTrimLinear = pow(10, db / 20)
        recomputeSafetyCeiling()
    }

    /// Updates every stage to a new sample rate, keeping user settings.
    /// Called by the audio engine when capture starts and the tap's
    /// actual rate becomes known — the chain is otherwise constructed
    /// before any audio path exists, with a guessed default rate.
    public func rebuild(at newSampleRate: Double) {
        customEQ.rebuild(at: newSampleRate)
        correctionEQ.rebuild(at: newSampleRate)
        userParametricEQ.rebuild(at: newSampleRate)
        recomputeSafetyCeiling()
    }

    /// Recomputes per-band effective Q from the genre + correction
    /// profile (see `CorrectionAwareQ.qVector`) and pushes the new Q
    /// values through the atomic-publish path. Glitch-free during live
    /// playback. Called when the user changes genre or loads/removes a
    /// correction profile.
    public func recomputeEffectiveQs(genre: GenrePreset, correctionProfile: HeadphoneProfile?) {
        let qs = CorrectionAwareQ.qVector(for: genre, correctionProfile: correctionProfile)
        customEQ.applyQVector(qs)
    }

    /// Recomputes the worst-case nominal gain across the chain and updates
    /// the cached makeup attenuation. Called from control-thread setters
    /// only — `process` always reads the cached `ceilingAttenuationLinear`,
    /// never recomputes it, so the render thread stays allocation-free.
    private func recomputeSafetyCeiling() {
        guard safetyCeilingEnabled else {
            // Ceiling off: no makeup attenuation, no "EQ does nothing"
            // surprise. The soft saturator still clamps actual clipping
            // before the output device.
            ceilingAttenuationLinear = 1.0
            isSafetyCeilingActive = false
            return
        }
        let effectiveCustomBands = customEQ.isBypassed ? [] : customEQ.bands
        let effectiveCorrectionFilters = (correctionEQ.isBypassed ? nil : correctionEQ.profile)?.filters ?? []
        let effectivePreampDb = (correctionEQ.isBypassed ? nil : correctionEQ.profile)?.preampDb ?? 0
        let effectiveUserParametricFilters = (userParametricEQ.isBypassed ? nil : userParametricEQ.profile)?.filters ?? []
        let effectiveUserParametricPreampDb = (userParametricEQ.isBypassed ? nil : userParametricEQ.profile)?.preampDb ?? 0

        let peakDb = OutputSafetyCeiling.estimatedPeakGainDb(
            routeGainDb: routeGainDb,
            outputTrimDb: outputTrimDb,
            customEQBands: effectiveCustomBands,
            customEQSampleRate: customEQ.sampleRate,
            correctionPreampDb: effectivePreampDb,
            correctionFilters: effectiveCorrectionFilters,
            correctionSampleRate: correctionEQ.sampleRate,
            userParametricPreampDb: effectiveUserParametricPreampDb,
            userParametricFilters: effectiveUserParametricFilters,
            userParametricSampleRate: userParametricEQ.sampleRate
        )
        ceilingAttenuationLinear = OutputSafetyCeiling.makeupAttenuationLinear(forEstimatedPeakGainDb: peakDb)
        isSafetyCeilingActive = ceilingAttenuationLinear < 1.0
    }

    @inline(__always)
    public func process(_ input: Double) -> Double {
        inputMeter.update(input)

        guard !isMuted else {
            outputMeter.update(0)
            return 0
        }

        var sample = input * gainLinear
        sample = customEQ.process(sample)
        sample = correctionEQ.process(sample)
        sample = userParametricEQ.process(sample)
        sample *= outputTrimLinear
        sample *= ceilingAttenuationLinear
        sample = limiter.process(sample)

        outputMeter.update(sample)
        return sample
    }

    /// Stereo per-sample path. Same chain order as `process(_:)` but
    /// keeps L and R independent through every biquad — the audible
    /// improvement is that stereo content stays stereo instead of
    /// collapsing to phantom-center mono.
    @inline(__always)
    public func processStereo(left: Double, right: Double) -> (Double, Double) {
        precondition(channelCount >= 2)
        // Meter on the loudest channel — gives an honest "how loud is the
        // source" reading whether L = R (mono) or panned.
        inputMeter.update(max(abs(left), abs(right)))

        guard !isMuted else {
            outputMeter.update(0)
            return (0, 0)
        }

        var L = left * gainLinear
        var R = right * gainLinear
        let eq = customEQ.processStereo(left: L, right: R)
        L = eq.0; R = eq.1
        let corr = correctionEQ.processStereo(left: L, right: R)
        L = corr.0; R = corr.1
        let user = userParametricEQ.processStereo(left: L, right: R)
        L = user.0; R = user.1
        L *= outputTrimLinear * ceilingAttenuationLinear
        R *= outputTrimLinear * ceilingAttenuationLinear
        L = limiter.process(L)
        R = limiter.process(R)

        outputMeter.update(max(abs(L), abs(R)))
        return (L, R)
    }

    @inline(__always)
    public func processInterleaved(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        let frame = UnsafeMutableBufferPointer(start: frameScratch, count: channelCount)
        var inputBlockPeak = 0.0

        for frameIndex in 0..<frameCount {
            let frameBase = frameIndex * channelCount
            for channel in 0..<channelCount {
                let value = Double(samples[frameBase + channel])
                frame[channel] = value
                inputBlockPeak = max(inputBlockPeak, abs(value))
            }
        }
        inputMeter.updateBlockPeak(inputBlockPeak, frameCount: frameCount)

        if isMuted {
            memset(samples, 0, frameCount * channelCount * MemoryLayout<Float>.size)
            outputMeter.updateBlockPeak(0, frameCount: frameCount)
            return
        }

        var outputBlockPeak = 0.0
        let trim = outputTrimLinear * ceilingAttenuationLinear
        for frameIndex in 0..<frameCount {
            let frameBase = frameIndex * channelCount
            for channel in 0..<channelCount {
                frame[channel] = Double(samples[frameBase + channel]) * gainLinear
            }
            customEQ.processChannels(frame)
            correctionEQ.processChannels(frame)
            userParametricEQ.processChannels(frame)

            for channel in 0..<channelCount {
                let limited = limiter.process(frame[channel] * trim)
                outputBlockPeak = max(outputBlockPeak, abs(limited))
                samples[frameBase + channel] = Float(limited)
            }
        }

        outputMeter.updateBlockPeak(outputBlockPeak, frameCount: frameCount)
    }
}
