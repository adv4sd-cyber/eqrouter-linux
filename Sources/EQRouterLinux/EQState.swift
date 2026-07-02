import Foundation
import EQRouterCore

/// Live, thread-safe EQ state shared between the web control panel (which
/// mutates it from HTTP handler threads) and the audio pipe engine (which
/// reads it from its pump thread).
///
/// Concurrency model: one `NSLock` guards both the config and the live
/// `RouteDSPChain`. The audio pump takes the lock once per *buffer* (not
/// per sample) around `processInterleaved`; control mutations take it
/// briefly. Buffers are ~10–40 ms apart, so per-buffer locking against
/// microsecond-scale control mutations is uncontended in practice — the
/// pipe engine already has OS pipe buffering, so it is not hard-real-time.
/// Structural changes (loading a correction profile, which reallocates the
/// filter array) are therefore safe: they cannot race an in-flight buffer.
public final class EQState {
    private let lock = NSLock()
    private var _config: EQConfig
    private let chain: RouteDSPChain
    public let sampleRate: Double
    public let channelCount: Int

    /// Where config is persisted. nil disables persistence (tests).
    private let persistenceURL: URL?

    public init(
        config: EQConfig = EQConfig(),
        sampleRate: Double = 48_000,
        channelCount: Int = 2,
        persistenceURL: URL? = EQState.defaultPersistenceURL()
    ) {
        self._config = config
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.persistenceURL = persistenceURL
        self.chain = RouteDSPChain(channelCount: channelCount, sampleRate: sampleRate)
        applyFullConfig(config, to: chain)
    }

    // MARK: - Persistence

    public static func defaultPersistenceURL() -> URL {
        Platform.configDirectory.appendingPathComponent("config.json")
    }

    /// Loads persisted config from disk, falling back to defaults.
    public static func loadPersisted(
        sampleRate: Double = 48_000,
        channelCount: Int = 2
    ) -> EQState {
        let url = defaultPersistenceURL()
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(EQConfig.self, from: data) {
            return EQState(config: config, sampleRate: sampleRate,
                           channelCount: channelCount, persistenceURL: url)
        }
        return EQState(sampleRate: sampleRate, channelCount: channelCount, persistenceURL: url)
    }

    private func persistLocked() {
        guard let url = persistenceURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(_config)
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(
                Data("eqrouter: failed to persist config: \(error)\n".utf8))
        }
    }

    // MARK: - Snapshot

    public var config: EQConfig {
        lock.lock(); defer { lock.unlock() }
        return _config
    }

    /// Current input/output peak levels in dBFS (−∞ clamped to −120), for
    /// the UI meters. Read without mutating the chain.
    public var meterLevelsDb: (input: Double, output: Double) {
        lock.lock(); defer { lock.unlock() }
        func db(_ linear: Double) -> Double {
            linear <= 1e-6 ? -120 : max(-120, 20 * log10(linear))
        }
        return (db(chain.inputMeter.currentPeak), db(chain.outputMeter.currentPeak))
    }

    public var isSafetyCeilingActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return chain.isSafetyCeilingActive
    }

    // MARK: - Audio hot path

    /// Process one interleaved `Float` buffer in place. Called once per
    /// audio buffer by the pipe engine's pump thread.
    public func process(interleaved buffer: UnsafeMutablePointer<Float>, frameCount: Int) {
        lock.lock()
        chain.processInterleaved(buffer, frameCount: frameCount)
        lock.unlock()
    }

    // MARK: - Mutations (called from control threads)

    public func setBandGain(index: Int, db: Double) {
        lock.lock()
        guard index >= 0, index < _config.bandGains.count else { lock.unlock(); return }
        _config.bandGains[index] = db
        chain.customEQ.setGain(db, forBandID: index)
        persistLocked()
        lock.unlock()
    }

    public func setAllBandGains(_ gains: [Double]) {
        lock.lock()
        for (i, g) in gains.enumerated() where i < _config.bandGains.count {
            _config.bandGains[i] = g
            chain.customEQ.setGain(g, forBandID: i)
        }
        persistLocked()
        lock.unlock()
    }

    public func setGenre(_ genre: GenrePreset) {
        lock.lock()
        _config.genre = genre
        chain.recomputeEffectiveQs(genre: genre, correctionProfile: _config.correctionProfile)
        persistLocked()
        lock.unlock()
    }

    public func setCorrectionProfile(id: String?) {
        lock.lock()
        _config.correctionProfileID = id
        if let profile = _config.correctionProfile {
            chain.correctionEQ.loadProfile(profile)
        } else {
            chain.correctionEQ.removeProfile()
        }
        // Q blend depends on whether correction is loaded.
        chain.recomputeEffectiveQs(genre: _config.genre, correctionProfile: _config.correctionProfile)
        persistLocked()
        lock.unlock()
    }

    public func setImportedProfile(name: String, filters: [ParametricFilterSpec], preampDb: Double) {
        lock.lock()
        _config.importedProfileName = name
        _config.importedFilters = filters
        _config.importedPreampDb = preampDb
        if let profile = _config.importedProfileAsHeadphone {
            chain.userParametricEQ.loadProfile(profile)
        }
        persistLocked()
        lock.unlock()
    }

    public func clearImportedProfile() {
        lock.lock()
        _config.importedProfileName = nil
        _config.importedFilters = []
        _config.importedPreampDb = 0
        chain.userParametricEQ.removeProfile()
        persistLocked()
        lock.unlock()
    }

    public func setOutputTrim(db: Double) {
        lock.lock(); _config.outputTrimDb = db; chain.setOutputTrim(db); persistLocked(); lock.unlock()
    }

    public func setRouteGain(db: Double) {
        lock.lock(); _config.routeGainDb = db; chain.setRouteGain(db); persistLocked(); lock.unlock()
    }

    public func setMuted(_ muted: Bool) {
        lock.lock(); _config.isMuted = muted; chain.isMuted = muted; persistLocked(); lock.unlock()
    }

    public func setCustomBypassed(_ bypassed: Bool) {
        lock.lock(); _config.customEQBypassed = bypassed; chain.customEQ.isBypassed = bypassed; persistLocked(); lock.unlock()
    }

    public func setCorrectionBypassed(_ bypassed: Bool) {
        lock.lock(); _config.correctionBypassed = bypassed; chain.correctionEQ.isBypassed = bypassed; persistLocked(); lock.unlock()
    }

    public func setSafetyCeiling(_ enabled: Bool) {
        lock.lock(); _config.safetyCeilingEnabled = enabled; chain.safetyCeilingEnabled = enabled; persistLocked(); lock.unlock()
    }

    /// Zero every custom band, keep genre/correction. Mirrors the app's
    /// "reset EQ" affordance.
    public func resetBands() {
        lock.lock()
        for i in _config.bandGains.indices { _config.bandGains[i] = 0 }
        chain.customEQ.reset()
        persistLocked()
        lock.unlock()
    }

    /// Replace the whole config atomically (e.g. applying a saved preset).
    public func replaceConfig(_ config: EQConfig) {
        lock.lock()
        _config = config
        applyFullConfig(config, to: chain)
        persistLocked()
        lock.unlock()
    }

    // MARK: - Fresh chain for offline (file) processing

    /// Builds an independent DSP chain configured from the current config
    /// at an arbitrary sample rate. Used by the WAV file processor, which
    /// must match the file's own rate rather than the live 48 kHz path.
    public func makeConfiguredChain(sampleRate: Double, channelCount: Int) -> RouteDSPChain {
        let snapshot = config
        let chain = RouteDSPChain(channelCount: channelCount, sampleRate: sampleRate)
        applyFullConfig(snapshot, to: chain)
        return chain
    }

    // MARK: - Response curve (for the UI)

    /// Combined magnitude response of the whole EQ chain (custom + correction
    /// + imported + preamps + trim/gain), in dB, sampled at log-spaced
    /// frequencies. This is exactly what the on-screen curve draws.
    public func responseCurve(points: Int = 160, from low: Double = 20, to high: Double = 20_000)
        -> [(hz: Double, db: Double)]
    {
        let snapshot = config
        let freqs = FrequencyResponse.logSpacedFrequencies(from: low, to: high, count: points)

        var sections: [BiquadCoefficients] = []
        var constantDb = snapshot.outputTrimDb + snapshot.routeGainDb

        if !snapshot.customEQBypassed {
            for (i, freq) in TenBandLayout.centerFrequenciesHz.enumerated() {
                let q = CorrectionAwareQ.effectiveQ(
                    bandIdx: i,
                    baselineQ: TenBandLayout.octaveCleanQ,
                    genre: snapshot.genre,
                    hasCorrection: snapshot.correctionProfile != nil
                )
                sections.append(BiquadCoefficients(
                    kind: .peaking, sampleRate: sampleRate,
                    frequencyHz: freq, gainDb: snapshot.bandGains[i], q: q))
            }
        }
        if !snapshot.correctionBypassed, let profile = snapshot.correctionProfile {
            constantDb += profile.preampDb
            for spec in profile.filters {
                sections.append(BiquadCoefficients(
                    kind: spec.shape.biquadKind, sampleRate: sampleRate,
                    frequencyHz: spec.frequencyHz, gainDb: spec.gainDb, q: spec.q))
            }
        }
        if snapshot.hasImportedProfile {
            constantDb += snapshot.importedPreampDb
            for spec in snapshot.importedFilters {
                sections.append(BiquadCoefficients(
                    kind: spec.shape.biquadKind, sampleRate: sampleRate,
                    frequencyHz: spec.frequencyHz, gainDb: spec.gainDb, q: spec.q))
            }
        }

        return freqs.map { f in
            let db = constantDb + FrequencyResponse.magnitudeDb(
                ofCascade: sections, atHz: f, sampleRate: sampleRate)
            return (hz: f, db: db)
        }
    }

    // MARK: - Apply

    private func applyFullConfig(_ config: EQConfig, to chain: RouteDSPChain) {
        // Correction / imported first so the Q blend sees the right state.
        if let profile = config.correctionProfile {
            chain.correctionEQ.loadProfile(profile)
        } else {
            chain.correctionEQ.removeProfile()
        }
        chain.correctionEQ.isBypassed = config.correctionBypassed

        if let profile = config.importedProfileAsHeadphone {
            chain.userParametricEQ.loadProfile(profile)
        } else {
            chain.userParametricEQ.removeProfile()
        }

        chain.recomputeEffectiveQs(genre: config.genre, correctionProfile: config.correctionProfile)

        for (i, gain) in config.bandGains.enumerated() {
            chain.customEQ.setGain(gain, forBandID: i)
        }
        chain.customEQ.isBypassed = config.customEQBypassed

        chain.setRouteGain(config.routeGainDb)
        chain.setOutputTrim(config.outputTrimDb)
        chain.isMuted = config.isMuted
        chain.safetyCeilingEnabled = config.safetyCeilingEnabled
    }
}
