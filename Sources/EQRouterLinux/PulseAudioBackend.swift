#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#endif

import Foundation
import EQRouterCore

/// A PulseAudio / PipeWire sink or source, as reported by `pactl`.
public struct PulseDevice: Equatable, Codable {
    public let index: Int
    public let name: String
    public var description: String
    public let isMonitor: Bool
}

/// Thin wrapper over the `pactl` control tool and the `parec`/`pacat`
/// streaming tools. Works against both a native PulseAudio server and a
/// PipeWire server running the pulse compatibility layer (the default on
/// modern desktops), because both ship these binaries.
public enum PulseAudio {
    /// Result of running an external command.
    struct CommandResult { let status: Int32; let stdout: String; let stderr: String }

    /// Runs a command by name (PATH-resolved via `/usr/bin/env`) and
    /// captures its output. Returns nil if the process couldn't be spawned
    /// at all (e.g. the tool isn't installed).
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 5) -> CommandResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }

    /// True when a Pulse/PipeWire server is reachable.
    public static var isServerAvailable: Bool {
        guard let r = run("pactl", ["info"]) else { return false }
        return r.status == 0
    }

    /// One-line server summary (server name + default sink), for diagnostics.
    public static func serverInfo() -> String? {
        guard let r = run("pactl", ["info"]), r.status == 0 else { return nil }
        return r.stdout
    }

    public static func defaultSink() -> String? {
        guard let r = run("pactl", ["get-default-sink"]), r.status == 0 else { return nil }
        let s = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    public static func listSinks() -> [PulseDevice] { parseShort(kind: "sinks") }
    public static func listSources() -> [PulseDevice] { parseShort(kind: "sources") }

    private static func parseShort(kind: String) -> [PulseDevice] {
        guard let r = run("pactl", ["list", "short", kind]), r.status == 0 else { return [] }
        var devices: [PulseDevice] = []
        for line in r.stdout.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2, let idx = Int(cols[0]) else { continue }
            let name = String(cols[1])
            devices.append(PulseDevice(
                index: idx, name: name, description: name,
                isMonitor: name.hasSuffix(".monitor")))
        }
        return devices
    }

    // MARK: - Null sink (per-app / clean routing helper)

    /// Loads a null sink named `EQRouter` that applications can be pointed
    /// at; its `.monitor` becomes the capture source for the engine. Returns
    /// the module index (needed to unload), or nil on failure.
    @discardableResult
    public static func loadNullSink(name: String = "EQRouter",
                                    description: String = "EQRouter EQ Input") -> Int? {
        let r = run("pactl", [
            "load-module", "module-null-sink",
            "sink_name=\(name)",
            "sink_properties=device.description=\(description.replacingOccurrences(of: " ", with: "\\ "))"
        ])
        guard let r, r.status == 0, let idx = Int(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return idx
    }

    public static func unloadModule(index: Int) {
        _ = run("pactl", ["unload-module", "\(index)"])
    }

    /// Unloads every `module-null-sink` whose sink is named `EQRouter` —
    /// used by the standalone `teardown-sink` command, which has no module
    /// index from a prior process. Returns how many were removed.
    @discardableResult
    public static func unloadEQRouterSinks() -> Int {
        guard let r = run("pactl", ["list", "short", "modules"]), r.status == 0 else { return 0 }
        var removed = 0
        for line in r.stdout.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2, cols[1] == "module-null-sink" else { continue }
            let argField = cols.count >= 3 ? String(cols[2]) : ""
            guard argField.contains("sink_name=EQRouter"), let idx = Int(cols[0]) else { continue }
            unloadModule(index: idx); removed += 1
        }
        return removed
    }

    public static func setDefaultSink(_ name: String) {
        _ = run("pactl", ["set-default-sink", name])
    }
}

/// Real-time system-audio EQ: `parec` captures a source, each buffer is run
/// through the shared `EQState` DSP chain, and the result is written to
/// `pacat` playing to an output sink.
///
///     parec --raw ─▶ [pump: EQState.process] ─▶ pacat --raw
///
/// This deliberately shells out rather than linking libpulse/libpipewire so
/// the binary stays free of native C dependencies and cross-compiles with
/// the Swift static-Linux SDK. The OS pipe buffers between the three
/// processes absorb scheduling jitter, so the pump is not hard-real-time.
public final class PipeEngine {
    public struct Configuration {
        public var source: String?      // capture device (nil = server default monitor)
        public var sink: String?        // playback device (nil = server default)
        public var sampleRate: Int
        public var channels: Int
        public var bufferFrames: Int
        public var latencyMsec: Int

        public init(source: String? = nil, sink: String? = nil, sampleRate: Int = 48_000,
                    channels: Int = 2, bufferFrames: Int = 512, latencyMsec: Int = 30) {
            self.source = source
            self.sink = sink
            self.sampleRate = sampleRate
            self.channels = channels
            self.bufferFrames = bufferFrames
            self.latencyMsec = latencyMsec
        }
    }

    public enum EngineError: Error, CustomStringConvertible {
        case toolsUnavailable
        case spawnFailed(String)
        case alreadyRunning

        public var description: String {
            switch self {
            case .toolsUnavailable:
                return "PulseAudio/PipeWire tools (parec/pacat) not found. Install pulseaudio-utils (or pipewire-pulse)."
            case .spawnFailed(let s): return "failed to start audio pipe: \(s)"
            case .alreadyRunning: return "engine already running"
            }
        }
    }

    private let state: EQState
    public let configuration: Configuration
    private var parec: Process?
    private var pacat: Process?
    private var pumpThread: Thread?
    private var stopFlag = false
    private let controlLock = NSLock()

    public private(set) var isRunning = false
    /// Set when the pump exits unexpectedly (e.g. a tool died); surfaced to the UI.
    public private(set) var lastError: String?

    public init(state: EQState, configuration: Configuration) {
        self.state = state
        self.configuration = configuration
    }

    public func start() throws {
        controlLock.lock(); defer { controlLock.unlock() }
        guard !isRunning else { throw EngineError.alreadyRunning }

        // Writing to a dead `pacat` would otherwise deliver SIGPIPE and kill us.
        signal(SIGPIPE, SIG_IGN)

        let cfg = configuration
        let parecArgs = rawStreamArgs(device: cfg.source, isCapture: true)
        let pacatArgs = rawStreamArgs(device: cfg.sink, isCapture: false)

        let parecOut = Pipe()
        let pacatIn = Pipe()

        let parecProc = Process()
        parecProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        parecProc.arguments = ["parec"] + parecArgs
        parecProc.standardOutput = parecOut
        parecProc.standardError = FileHandle.nullDevice

        let pacatProc = Process()
        pacatProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        pacatProc.arguments = ["pacat"] + pacatArgs
        pacatProc.standardInput = pacatIn
        pacatProc.standardError = FileHandle.nullDevice

        do {
            try parecProc.run()
            try pacatProc.run()
        } catch {
            parecProc.terminate(); pacatProc.terminate()
            throw EngineError.spawnFailed("\(error)")
        }

        // Parent keeps only the ends it actually uses, so EOF propagates
        // cleanly when either child exits.
        try? parecOut.fileHandleForWriting.close()
        try? pacatIn.fileHandleForReading.close()

        let readFD = parecOut.fileHandleForReading.fileDescriptor
        let writeFD = pacatIn.fileHandleForWriting.fileDescriptor

        self.parec = parecProc
        self.pacat = pacatProc
        self.stopFlag = false
        self.lastError = nil
        self.isRunning = true

        let thread = Thread { [weak self] in
            self?.pump(readFD: readFD, writeFD: writeFD)
        }
        thread.name = "eqrouter.pump"
        thread.stackSize = 1 << 20
        self.pumpThread = thread
        thread.start()
    }

    public func stop() {
        controlLock.lock()
        guard isRunning else { controlLock.unlock(); return }
        stopFlag = true
        let p = parec, c = pacat
        controlLock.unlock()

        p?.terminate()
        c?.terminate()
        p?.waitUntilExit()
        c?.waitUntilExit()

        controlLock.lock()
        isRunning = false
        parec = nil; pacat = nil; pumpThread = nil
        controlLock.unlock()
    }

    private func rawStreamArgs(device: String?, isCapture: Bool) -> [String] {
        var args = [
            "--raw",
            "--format=float32le",
            "--rate=\(configuration.sampleRate)",
            "--channels=\(configuration.channels)",
            "--latency-msec=\(configuration.latencyMsec)",
            "--client-name=EQRouter\(isCapture ? "-in" : "-out")",
        ]
        if let device { args.append("--device=\(device)") }
        return args
    }

    /// The pump loop: read a buffer of interleaved float PCM, EQ it in place,
    /// write it out. Runs until stopped or a child pipe closes.
    private func pump(readFD: Int32, writeFD: Int32) {
        let channels = configuration.channels
        let frameBytes = configuration.bufferFrames * channels * MemoryLayout<Float>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: frameBytes, alignment: 16)
        defer { buffer.deallocate() }

        while true {
            controlLock.lock(); let stop = stopFlag; controlLock.unlock()
            if stop { break }

            let bytesRead = readFull(readFD, buffer, frameBytes)
            if bytesRead <= 0 { // EOF or error from parec
                setPumpError("audio capture stream ended")
                break
            }
            let wholeFrames = bytesRead / (channels * MemoryLayout<Float>.size)
            if wholeFrames > 0 {
                let floats = buffer.assumingMemoryBound(to: Float.self)
                state.process(interleaved: floats, frameCount: wholeFrames)
            }
            if !writeFull(writeFD, buffer, bytesRead) {
                setPumpError("audio output stream closed")
                break
            }
        }
        // Best-effort: closing our write end signals EOF to pacat.
        _ = close(writeFD)
    }

    private func setPumpError(_ message: String) {
        controlLock.lock()
        if !stopFlag { lastError = message }
        controlLock.unlock()
    }

    /// Reads exactly `count` bytes unless EOF is hit first. Returns bytes read.
    private func readFull(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ count: Int) -> Int {
        var total = 0
        while total < count {
            let n = read(fd, buf.advanced(by: total), count - total)
            if n > 0 { total += n; continue }
            if n == 0 { break } // EOF
            if errno == EINTR { continue }
            return total > 0 ? total : -1
        }
        return total
    }

    private func writeFull(_ fd: Int32, _ buf: UnsafeMutableRawPointer, _ count: Int) -> Bool {
        var total = 0
        while total < count {
            let n = write(fd, buf.advanced(by: total), count - total)
            if n > 0 { total += n; continue }
            if n < 0 && errno == EINTR { continue }
            return false
        }
        return true
    }
}
