// Cross-platform primitives shared by the Linux backend.
//
// Everything in `EQRouterLinux` builds on both Linux (Glibc / static-musl)
// and macOS (Darwin) so the web control panel and the WAV file processor
// can be exercised on a Mac during development; only the live
// PipeWire/PulseAudio pipe (`parec`/`pacat`) is genuinely Linux-only, and
// that degrades to a clear error when the tools are absent.

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#endif

import Foundation

/// True when running on Linux — used to gate advice/log text, never to
/// change DSP behaviour.
public let isLinux: Bool = {
    #if os(Linux)
    return true
    #else
    return false
    #endif
}()

enum Platform {
    /// `htons` is a C macro with no Swift import; do the network byte-order
    /// swap explicitly so it works identically on every libc.
    static func hostToNetwork(_ value: UInt16) -> UInt16 { value.bigEndian }

    /// Directory for persisted config: `$XDG_CONFIG_HOME/eqrouter` or
    /// `~/.config/eqrouter`, matching the Linux desktop convention.
    static var configDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("eqrouter", isDirectory: true)
    }
}
