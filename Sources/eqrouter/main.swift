#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#endif

import Foundation
import EQRouterCore
import EQRouterLinux

// EQRouter — Linux edition CLI.
//
//   eqrouter serve   [--port N] [--host H] [--no-open]   web control panel
//   eqrouter run     [--source S] [--sink K]             headless routing
//   eqrouter file    --in a.wav --out b.wav [options]    offline WAV EQ
//   eqrouter devices                                     list sinks/sources
//   eqrouter setup-sink | teardown-sink                  manage EQRouter sink
//
// The DSP core is shared verbatim with the macOS app; only capture/render
// and the UI are reimplemented for Linux.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "serve"
let rest = Array(arguments.dropFirst())

/// Parses `--flag value` / `--flag=value` / bare `--flag` options.
struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--") {
                let body = String(a.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    values[String(body[..<eq])] = String(body[body.index(after: eq)...])
                } else if i + 1 < args.count, !args[i+1].hasPrefix("--") {
                    values[body] = args[i+1]; i += 1
                } else {
                    flags.insert(body)
                }
            }
            i += 1
        }
    }
    func string(_ k: String) -> String? { values[k] }
    func int(_ k: String) -> Int? { values[k].flatMap { Int($0) } }
    func double(_ k: String) -> Double? { values[k].flatMap { Double($0) } }
    func has(_ k: String) -> Bool { flags.contains(k) || values[k] != nil }
}

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func printUsage() {
    print("""
    EQRouter — Linux edition

    USAGE:
      eqrouter serve [--host 127.0.0.1] [--port 8080] [--no-open]
          Launch the web control panel (the GUI). Open the printed URL.

      eqrouter run [--source NAME] [--sink NAME] [--setup-sink]
          Headless real-time routing using the saved config.
          --setup-sink creates an "EQRouter" sink and captures its monitor.

      eqrouter file --in INPUT.wav --out OUTPUT.wav [--genre G] [--correction ID]
                    [--band i=dB ...] [--trim dB] [--gain dB] [--preamp-file f.txt]
          Apply EQ to a WAV file offline (no audio server needed).

      eqrouter devices
          List available PulseAudio/PipeWire sinks and sources.

      eqrouter doctor
          Check runtime dependencies and print how to install them.

      eqrouter install-deps [--yes]
          Install the PulseAudio client tools (parec/pacat/pactl) using the
          system package manager. --yes skips the confirmation prompt.

      eqrouter setup-sink | teardown-sink
          Create / remove the EQRouter null sink for per-app routing.

    Genres: \(GenrePreset.allCases.map(\.rawValue).joined(separator: ", "))
    Config: \(EQState.defaultPersistenceURL().path)
    """)
}

// MARK: - Commands

func runServe() {
    let opts = Options(rest)
    let host = opts.string("host") ?? "127.0.0.1"
    let port = UInt16(opts.int("port") ?? 8080)
    let state = EQState.loadPersisted()
    let engine = EngineController(state: state)
    let server = ControlServer(state: state, engine: engine, host: host, port: port)

    // Stop the engine cleanly on Ctrl-C.
    installSignalHandler { engine.stop(); exit(0) }

    print("EQRouter control panel → \(server.url)")
    if PulseAudio.isServerAvailable {
        print("Audio server detected. Use the Live Engine section to start routing.")
    } else {
        print("No PulseAudio/PipeWire server detected — EQ editing + file processing still work.")
    }
    let deps = DependencyManager.status()
    if !deps.satisfied {
        print("Missing audio tools (\(deps.missingTools.joined(separator: ", "))) — the panel offers a one-click install, or run `eqrouter install-deps`.")
    }
    do {
        try server.run()
    } catch {
        stderr("eqrouter: \(error)")
        exit(1)
    }
}

func runHeadless() {
    let opts = Options(rest)
    // Live routing needs parec/pacat/pactl — install them first if missing.
    ensureDependencies(assumeYes: opts.has("yes"), noInstall: opts.has("no-install"))

    let state = EQState.loadPersisted()
    let engine = EngineController(state: state)

    var source = opts.string("source")
    if opts.has("setup-sink") {
        if let monitor = engine.setupNullSink() {
            source = monitor
            PulseAudio.setDefaultSink("EQRouter")
            print("Created EQRouter sink and set it as default output. Capturing \(monitor).")
        } else {
            stderr("eqrouter: could not create null sink (no audio server?)"); exit(1)
        }
    }

    do {
        try engine.start(source: source, sink: opts.string("sink"))
    } catch {
        stderr("eqrouter: \(error)"); exit(1)
    }
    print("Routing live. Press Ctrl-C to stop.")
    installSignalHandler {
        engine.stop()
        if opts.has("setup-sink") { engine.teardownNullSink() }
        exit(0)
    }
    // Park the main thread while the pump runs.
    while true { Thread.sleep(forTimeInterval: 3600) }
}

func runFile() {
    let opts = Options(rest)
    guard let input = opts.string("in"), let output = opts.string("out") else {
        stderr("eqrouter file: --in and --out are required"); exit(1)
    }
    // Build an ephemeral (non-persisted) config from flags.
    var config = EQConfig()
    if let g = opts.string("genre"), let genre = GenrePreset(rawValue: g) { config.genre = genre }
    if let id = opts.string("correction") { config.correctionProfileID = id }
    if let trim = opts.double("trim") { config.outputTrimDb = trim }
    if let gain = opts.double("gain") { config.routeGainDb = gain }
    parseBandFlags(rest, into: &config) // repeated --band i=dB
    if let presetPath = opts.string("preamp-file") ?? opts.string("import") {
        if let text = try? String(contentsOfFile: presetPath, encoding: .utf8),
           let imported = try? AutoEqParser.parseParametric(text, modelName: (presetPath as NSString).lastPathComponent) {
            config.importedProfileName = imported.modelName
            config.importedFilters = imported.filters
            config.importedPreampDb = imported.preampDb
        } else {
            stderr("eqrouter file: could not parse preset at \(presetPath)")
        }
    }

    let state = EQState(config: config, persistenceURL: nil)
    do {
        let result = try FileProcessor.process(
            input: URL(fileURLWithPath: input),
            output: URL(fileURLWithPath: output),
            state: state)
        print("""
        Processed \(result.frameCount) frames · \(result.channelCount)ch · \(Int(result.sampleRate)) Hz
          input peak:  \(String(format: "%.1f", result.inputPeakDb)) dBFS
          output peak: \(String(format: "%.1f", result.outputPeakDb)) dBFS
        Wrote \(output)
        """)
    } catch {
        stderr("eqrouter file: \(error)"); exit(1)
    }
}

/// Applies repeated `--band i=dB` flags (Options collapses duplicate keys,
/// so parse them straight from argv here).
func parseBandFlags(_ args: [String], into config: inout EQConfig) {
    var i = 0
    while i < args.count {
        if args[i] == "--band", i + 1 < args.count {
            applyBandToken(args[i+1], &config); i += 2; continue
        }
        if args[i].hasPrefix("--band=") {
            applyBandToken(String(args[i].dropFirst("--band=".count)), &config)
        }
        i += 1
    }
}
func applyBandToken(_ token: String, _ config: inout EQConfig) {
    let parts = token.split(separator: "=")
    guard parts.count == 2, let idx = Int(parts[0]), let db = Double(parts[1]),
          idx >= 0, idx < config.bandGains.count else { return }
    config.bandGains[idx] = max(-12, min(12, db))
}

// MARK: - Dependencies

func isInteractive() -> Bool { isatty(fileno(stdin)) != 0 }

func promptYesNo(_ question: String, default defaultYes: Bool = true) -> Bool {
    guard isInteractive() else { return defaultYes }
    let suffix = defaultYes ? "[Y/n]" : "[y/N]"
    FileHandle.standardOutput.write(Data("\(question) \(suffix) ".utf8))
    guard let line = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return defaultYes }
    if line.isEmpty { return defaultYes }
    return line.hasPrefix("y")
}

/// Ensures the PulseAudio client tools are present before starting the engine.
/// Installs them (with confirmation, unless `assumeYes`) when possible.
func ensureDependencies(assumeYes: Bool, noInstall: Bool) {
    let status = DependencyManager.status()
    if status.satisfied { return }

    stderr("Missing audio tools: \(status.missingTools.joined(separator: ", ")) (needed for live routing).")

    guard !noInstall else {
        stderr("Skipping install (--no-install). Install them manually, e.g. \(status.plan?.shellString ?? "your package manager").")
        exit(1)
    }
    guard status.canAutoInstall, let plan = status.plan else {
        if let plan = status.plan {
            stderr("Cannot elevate privileges automatically. Run:\n  \(plan.shellString)")
        } else {
            stderr("No supported package manager detected. Install 'pulseaudio-utils' (or your distro's equivalent) manually.")
        }
        exit(1)
    }

    if !assumeYes {
        print("EQRouter can install them now via \(plan.packageManager.displayName):")
        print("  \(plan.shellString)")
        guard promptYesNo("Install now?") else {
            stderr("Aborted. Install manually with the command above."); exit(1)
        }
    }

    switch DependencyManager.install(assumeYes: true, interactive: isInteractive()) {
    case .success, .alreadySatisfied:
        print("Dependencies installed.")
    case .failed(let cmd, let code):
        stderr("Install failed (exit \(code)): \(cmd)"); exit(1)
    case .cannotElevate(let cmd):
        stderr("Could not elevate privileges. Run:\n  \(cmd)"); exit(1)
    case .noPackageManager:
        stderr("No supported package manager found."); exit(1)
    case .unsupportedPlatform:
        stderr("Automatic install is only supported on Linux."); exit(1)
    }
}

func runDoctor() {
    let status = DependencyManager.status()
    print("EQRouter environment check\n")
    print("Audio server (Pulse/PipeWire): \(PulseAudio.isServerAvailable ? "available" : "not detected")")
    print("Required tools:")
    for tool in DependencyManager.requiredTools {
        let ok = DependencyManager.toolAvailable(tool)
        print("  \(ok ? "[ok]  " : "[miss]") \(tool)")
    }
    if status.satisfied {
        print("\nAll runtime dependencies satisfied.")
        return
    }
    print("\nMissing: \(status.missingTools.joined(separator: ", "))")
    if let pm = status.packageManager {
        print("Package manager: \(pm.displayName)")
        print("Install with:")
        print("  eqrouter install-deps")
        if let plan = status.plan { print("  (runs: \(plan.shellString))") }
    } else {
        print("No supported package manager detected — install 'pulseaudio-utils' (or equivalent) manually.")
    }
}

func runInstallDeps() {
    let opts = Options(rest)
    let status = DependencyManager.status()
    if status.satisfied { print("All dependencies already installed."); return }
    guard let plan = status.plan else {
        stderr("No supported package manager detected. Install 'pulseaudio-utils' (or equivalent) manually."); exit(1)
    }
    if !opts.has("yes") {
        print("Will install \(plan.packages.joined(separator: ", ")) via \(plan.packageManager.displayName):")
        print("  \(plan.shellString)")
        guard promptYesNo("Proceed?") else { print("Aborted."); return }
    }
    switch DependencyManager.install(assumeYes: true, interactive: isInteractive()) {
    case .success: print("Done — dependencies installed.")
    case .alreadySatisfied: print("Already installed.")
    case .failed(let cmd, let code): stderr("Install failed (exit \(code)): \(cmd)"); exit(1)
    case .cannotElevate(let cmd): stderr("Could not elevate privileges. Run:\n  \(cmd)"); exit(1)
    case .noPackageManager: stderr("No supported package manager found."); exit(1)
    case .unsupportedPlatform: stderr("Automatic install is only supported on Linux."); exit(1)
    }
}

func runDevices() {
    guard PulseAudio.isServerAvailable else {
        stderr("No PulseAudio/PipeWire server detected."); exit(1)
    }
    print("Default sink: \(PulseAudio.defaultSink() ?? "(unknown)")\n")
    print("SINKS (playback devices):")
    for d in PulseAudio.listSinks() { print("  [\(d.index)] \(d.name)") }
    print("\nSOURCES (capture — use a .monitor to EQ what plays on that sink):")
    for d in PulseAudio.listSources() { print("  [\(d.index)] \(d.name)\(d.isMonitor ? "  (monitor)" : "")") }
}

func installSignalHandler(_ handler: @escaping () -> Void) {
    globalSignalHandler = handler
    signal(SIGINT) { _ in globalSignalHandler?() }
    signal(SIGTERM) { _ in globalSignalHandler?() }
}
var globalSignalHandler: (() -> Void)?

// MARK: - Dispatch

switch command {
case "serve":                runServe()
case "run":                  runHeadless()
case "file":                 runFile()
case "devices":              runDevices()
case "doctor":               runDoctor()
case "install-deps":         runInstallDeps()
case "setup-sink":
    let engine = EngineController(state: EQState(persistenceURL: nil))
    if let m = engine.setupNullSink() { print("Created EQRouter sink. Capture source: \(m)") }
    else { stderr("Failed to create null sink."); exit(1) }
case "teardown-sink":
    let removed = PulseAudio.unloadEQRouterSinks()
    print(removed > 0 ? "Removed \(removed) EQRouter sink(s)." : "No EQRouter sink to remove.")
case "help", "--help", "-h":  printUsage()
default:
    stderr("Unknown command: \(command)\n"); printUsage(); exit(1)
}
