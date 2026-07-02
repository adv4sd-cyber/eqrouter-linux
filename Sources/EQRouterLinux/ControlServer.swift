import Foundation
import EQRouterCore

/// Maps the HTTP control panel's requests onto `EQState` and `EngineController`.
/// Serves the embedded web UI at `/` and a small JSON API under `/api`.
public final class ControlServer {
    private let state: EQState
    private let engine: EngineController
    private let server: HTTPServer
    public let host: String
    public let port: UInt16

    public init(state: EQState, engine: EngineController, host: String = "127.0.0.1", port: UInt16 = 8080) {
        self.state = state
        self.engine = engine
        self.host = host
        self.port = port
        self.server = HTTPServer(host: host, port: port)
        self.server.setHandler { [weak self] req in
            self?.route(req) ?? HTTPServer.Response(status: 500)
        }
    }

    public var url: String { "http://\(host == "0.0.0.0" ? "localhost" : host):\(port)/" }

    public func run() throws { try server.run() }
    public func stop() { server.stop() }

    // MARK: - Router

    private func route(_ req: HTTPServer.Request) -> HTTPServer.Response {
        switch (req.method, req.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return .html(WebUI.page)
        case ("GET", "/api/state"):
            return .json(stateJSON())
        case ("GET", "/api/curve"):
            return .json(curveJSON())
        case ("GET", "/api/meters"):
            return .json(metersJSON())
        case ("GET", "/api/devices"):
            return .json(devicesJSON())
        case ("GET", "/api/deps"):
            return .json(depsJSON())
        case ("POST", "/api/deps/install"):
            return installDeps()

        case ("POST", "/api/band"):
            if let i = req.query["index"].flatMap({ Int($0) }),
               let db = req.query["db"].flatMap({ Double($0) }) {
                state.setBandGain(index: i, db: clampGain(db))
                return .json(curveJSON())
            }
            return badRequest("index and db required")

        case ("POST", "/api/bands"):
            if let raw = req.query["gains"] {
                let gains = raw.split(separator: ",").compactMap { Double($0) }.map(clampGain)
                state.setAllBandGains(gains)
                return .json(curveJSON())
            }
            return badRequest("gains=comma,separated required")

        case ("POST", "/api/genre"):
            if let v = req.query["value"], let g = GenrePreset(rawValue: v) {
                state.setGenre(g); return .json(curveJSON())
            }
            return badRequest("unknown genre")

        case ("POST", "/api/correction"):
            let id = req.query["id"].flatMap { $0.isEmpty ? nil : $0 }
            state.setCorrectionProfile(id: id)
            return .json(curveJSON())

        case ("POST", "/api/trim"):
            if let db = req.query["db"].flatMap({ Double($0) }) {
                state.setOutputTrim(db: max(-24, min(24, db))); return .json(curveJSON())
            }
            return badRequest("db required")

        case ("POST", "/api/gain"):
            if let db = req.query["db"].flatMap({ Double($0) }) {
                state.setRouteGain(db: max(-24, min(24, db))); return .json(curveJSON())
            }
            return badRequest("db required")

        case ("POST", "/api/mute"):
            state.setMuted(boolParam(req, "on")); return okJSON()
        case ("POST", "/api/bypass/custom"):
            state.setCustomBypassed(boolParam(req, "on")); return .json(curveJSON())
        case ("POST", "/api/bypass/correction"):
            state.setCorrectionBypassed(boolParam(req, "on")); return .json(curveJSON())
        case ("POST", "/api/ceiling"):
            state.setSafetyCeiling(boolParam(req, "on")); return okJSON()
        case ("POST", "/api/reset"):
            state.resetBands(); return .json(curveJSON())

        case ("POST", "/api/import"):
            let name = req.query["name"] ?? "Imported"
            let text = String(decoding: req.body, as: UTF8.self)
            do {
                let imported = try AutoEqParser.parseParametric(text, modelName: name)
                state.setImportedProfile(name: imported.modelName,
                                         filters: imported.filters,
                                         preampDb: imported.preampDb)
                return .json(stateJSON())
            } catch {
                return badRequest("no valid filters found in imported text")
            }
        case ("POST", "/api/import/clear"):
            state.clearImportedProfile(); return .json(stateJSON())

        case ("POST", "/api/engine/start"):
            let source = req.query["source"].flatMap { $0.isEmpty ? nil : $0 }
            let sink = req.query["sink"].flatMap { $0.isEmpty ? nil : $0 }
            do {
                try engine.start(source: source, sink: sink,
                                 sampleRate: Int(state.sampleRate), channels: state.channelCount)
                return okJSON()
            } catch {
                return badRequest("\(error)")
            }
        case ("POST", "/api/engine/stop"):
            engine.stop(); return okJSON()
        case ("POST", "/api/engine/setup-sink"):
            if let monitor = engine.setupNullSink() {
                return .json(jsonData(["monitor": monitor]))
            }
            return badRequest("could not create null sink (is a Pulse/PipeWire server running?)")
        case ("POST", "/api/engine/teardown-sink"):
            engine.teardownNullSink(); return okJSON()

        default:
            return HTTPServer.Response(status: 404, body: Data("not found".utf8))
        }
    }

    // MARK: - Helpers

    private func clampGain(_ db: Double) -> Double {
        max(TenBandLayout.gainRangeDb.lowerBound, min(TenBandLayout.gainRangeDb.upperBound, db))
    }
    private func boolParam(_ req: HTTPServer.Request, _ key: String) -> Bool {
        let v = req.query[key]?.lowercased()
        return v == "1" || v == "true" || v == "on"
    }
    private func badRequest(_ message: String) -> HTTPServer.Response {
        .json(jsonData(["error": message]), status: 400)
    }
    private func okJSON() -> HTTPServer.Response { .json(jsonData(["ok": true])) }

    private func jsonData(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }

    // MARK: - JSON payloads

    private func curveJSON() -> Data {
        let curve = state.responseCurve()
        let points = curve.map { [$0.hz, $0.db] }
        return jsonData(["curve": points, "ceilingActive": state.isSafetyCeilingActive])
    }

    private func metersJSON() -> Data {
        let m = state.meterLevelsDb
        let s = engine.status
        return jsonData([
            "input": m.input, "output": m.output,
            "ceilingActive": state.isSafetyCeilingActive,
            "running": s.running, "engineError": s.error as Any,
        ])
    }

    private func depsJSON() -> Data {
        let s = DependencyManager.status()
        return jsonData([
            "satisfied": s.satisfied,
            "missing": s.missingTools,
            "packageManager": s.packageManager?.displayName as Any,
            "command": s.plan?.shellString as Any,
            "canAutoInstall": s.canAutoInstall,
            "isLinux": isLinux,
        ])
    }

    /// Runs the install non-interactively (no TTY over HTTP). This can only
    /// succeed when we are root or `pkexec` is available (it shows a
    /// graphical prompt); plain `sudo` would need a password we can't supply,
    /// so the UI falls back to showing the command for the user to run.
    private func installDeps() -> HTTPServer.Response {
        var logLines: [String] = []
        let result = DependencyManager.install(assumeYes: true, interactive: false) { logLines.append($0) }
        switch result {
        case .success, .alreadySatisfied:
            return .json(jsonData(["ok": true, "log": logLines]))
        case .cannotElevate(let cmd):
            return .json(jsonData(["ok": false, "needsTerminal": true,
                                   "error": "Run this in a terminal: \(cmd)", "command": cmd]), status: 400)
        case .failed(let cmd, let code):
            return .json(jsonData(["ok": false, "error": "Install failed (exit \(code))",
                                   "command": cmd, "log": logLines]), status: 500)
        case .noPackageManager:
            return .json(jsonData(["ok": false, "error": "No supported package manager detected."]), status: 400)
        case .unsupportedPlatform:
            return .json(jsonData(["ok": false, "error": "Automatic install is only supported on Linux."]), status: 400)
        }
    }

    private func devicesJSON() -> Data {
        let available = PulseAudio.isServerAvailable
        func encode(_ d: [PulseDevice]) -> [[String: Any]] {
            d.map { ["index": $0.index, "name": $0.name, "description": $0.description, "isMonitor": $0.isMonitor] }
        }
        return jsonData([
            "serverAvailable": available,
            "sinks": encode(PulseAudio.listSinks()),
            "sources": encode(PulseAudio.listSources()),
            "defaultSink": PulseAudio.defaultSink() as Any,
        ])
    }

    private func stateJSON() -> Data {
        let cfg = state.config
        let curve = state.responseCurve()
        let genres = GenrePreset.allCases.map { ["id": $0.rawValue, "name": $0.displayName] }
        func encodeProfile(_ p: HeadphoneProfile) -> [String: Any] {
            [
                "id": p.id, "modelName": p.modelName, "sourceProject": p.sourceProject,
                "wearStyle": p.wearStyle?.displayLabel as Any, "isFeatured": p.isFeatured,
            ]
        }
        let s = engine.status
        let payload: [String: Any] = [
            "config": [
                "bandGains": cfg.bandGains,
                "customEQBypassed": cfg.customEQBypassed,
                "genre": cfg.genre.rawValue,
                "correctionProfileID": cfg.correctionProfileID as Any,
                "correctionBypassed": cfg.correctionBypassed,
                "importedProfileName": cfg.importedProfileName as Any,
                "importedPreampDb": cfg.importedPreampDb,
                "outputTrimDb": cfg.outputTrimDb,
                "routeGainDb": cfg.routeGainDb,
                "isMuted": cfg.isMuted,
                "safetyCeilingEnabled": cfg.safetyCeilingEnabled,
            ],
            "centerFrequencies": TenBandLayout.centerFrequenciesHz,
            "gainRange": [TenBandLayout.gainRangeDb.lowerBound, TenBandLayout.gainRangeDb.upperBound],
            "genres": genres,
            "profiles": HeadphoneProfile.allBundled.map(encodeProfile),
            "featuredProfiles": HeadphoneProfile.featuredBundledProfiles.map(encodeProfile),
            "curve": curve.map { [$0.hz, $0.db] },
            "engine": [
                "running": s.running,
                "error": s.error as Any,
                "serverAvailable": PulseAudio.isServerAvailable,
                "isLinux": isLinux,
            ],
        ]
        return jsonData(payload)
    }
}
