import Foundation
import EQRouterCore

/// Owns the lifetime of the live `PipeEngine` so the control server can
/// start/stop it and report status without knowing the audio details.
public final class EngineController {
    private let state: EQState
    private let lock = NSLock()
    private var engine: PipeEngine?
    private var nullSinkModule: Int?

    public init(state: EQState) { self.state = state }

    public struct Status: Codable {
        public var running: Bool
        public var error: String?
        public var source: String?
        public var sink: String?
    }

    private var currentSource: String?
    private var currentSink: String?

    public func start(source: String?, sink: String?, sampleRate: Int = 48_000, channels: Int = 2) throws {
        lock.lock(); defer { lock.unlock() }
        if let engine, engine.isRunning { engine.stop() }
        let cfg = PipeEngine.Configuration(
            source: source, sink: sink, sampleRate: sampleRate, channels: channels)
        let newEngine = PipeEngine(state: state, configuration: cfg)
        try newEngine.start()
        engine = newEngine
        currentSource = source
        currentSink = sink
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        engine?.stop()
    }

    public var status: Status {
        lock.lock(); defer { lock.unlock() }
        return Status(
            running: engine?.isRunning ?? false,
            error: engine?.lastError,
            source: currentSource,
            sink: currentSink)
    }

    /// Creates the `EQRouter` null sink and points the default at it, so
    /// applications feed the EQ. Returns the monitor source name to capture.
    public func setupNullSink() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard nullSinkModule == nil else { return "EQRouter.monitor" }
        guard let module = PulseAudio.loadNullSink() else { return nil }
        nullSinkModule = module
        return "EQRouter.monitor"
    }

    public func teardownNullSink() {
        lock.lock(); defer { lock.unlock() }
        if let module = nullSinkModule {
            PulseAudio.unloadModule(index: module)
            nullSinkModule = nil
        }
    }
}
