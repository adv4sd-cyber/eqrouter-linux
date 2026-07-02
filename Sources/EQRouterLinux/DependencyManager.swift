#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Musl)
import Musl
#endif

import Foundation

/// Detects and installs the one runtime dependency the live engine needs —
/// the PulseAudio client tools `parec` / `pacat` / `pactl` — using whatever
/// package manager the host Linux distribution ships.
///
/// The offline WAV mode and the web control panel need nothing extra; only
/// real-time routing shells out to these tools. `pulseaudio-utils` (or the
/// per-distro equivalent) provides them and works against both a native
/// PulseAudio server and a PipeWire server via its pulse layer.
///
/// The command construction is factored into pure functions so it can be
/// unit-tested without touching the system.
public enum DependencyManager {

    /// Tools the live engine invokes.
    public static let requiredTools = ["parec", "pacat", "pactl"]

    // MARK: - Supported package managers

    public enum PackageManager: String, CaseIterable, Codable {
        case apt, dnf, yum, zypper, pacman, apk, xbps, emerge

        /// Binary probed on `PATH` to detect this manager.
        public var probeBinary: String {
            switch self {
            case .apt: return "apt-get"
            case .dnf: return "dnf"
            case .yum: return "yum"
            case .zypper: return "zypper"
            case .pacman: return "pacman"
            case .apk: return "apk"
            case .xbps: return "xbps-install"
            case .emerge: return "emerge"
            }
        }

        public var displayName: String {
            switch self {
            case .apt: return "APT (Debian/Ubuntu)"
            case .dnf: return "DNF (Fedora/RHEL)"
            case .yum: return "YUM (RHEL/CentOS)"
            case .zypper: return "Zypper (openSUSE)"
            case .pacman: return "pacman (Arch)"
            case .apk: return "apk (Alpine)"
            case .xbps: return "XBPS (Void)"
            case .emerge: return "Portage (Gentoo)"
            }
        }

        /// Package(s) providing parec/pacat/pactl on this distro family.
        public var pulsePackages: [String] {
            switch self {
            case .pacman: return ["libpulse"]        // Arch ships the CLI tools in libpulse
            case .emerge: return ["media-sound/pulseaudio"]
            default:      return ["pulseaudio-utils"] // apt/dnf/yum/zypper/apk/xbps
            }
        }

        /// The install step(s), *without* privilege elevation. Some managers
        /// want an index refresh first; that is modelled as an extra command.
        public func installCommands(packages: [String], assumeYes: Bool) -> [[String]] {
            switch self {
            case .apt:
                let yes = assumeYes ? ["-y"] : []
                return [["apt-get", "update"], ["apt-get", "install"] + yes + packages]
            case .dnf:
                return [["dnf", "install"] + (assumeYes ? ["-y"] : []) + packages]
            case .yum:
                return [["yum", "install"] + (assumeYes ? ["-y"] : []) + packages]
            case .zypper:
                return [["zypper"] + (assumeYes ? ["--non-interactive"] : []) + ["install"] + packages]
            case .pacman:
                return [["pacman", "-S", "--needed"] + (assumeYes ? ["--noconfirm"] : []) + packages]
            case .apk:
                return [["apk", "add"] + packages]
            case .xbps:
                return [["xbps-install"] + (assumeYes ? ["-y"] : []) + packages]
            case .emerge:
                return [["emerge"] + (assumeYes ? [] : ["--ask"]) + packages]
            }
        }
    }

    // MARK: - PATH probing

    /// True if `name` resolves to an executable on `PATH`.
    public static func toolAvailable(_ name: String) -> Bool {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return false }
        let fm = FileManager.default
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) { return true }
        }
        return false
    }

    public static func missingTools() -> [String] {
        requiredTools.filter { !toolAvailable($0) }
    }

    public static func detectPackageManager() -> PackageManager? {
        PackageManager.allCases.first { toolAvailable($0.probeBinary) }
    }

    // MARK: - Privilege elevation

    public enum Elevation: Equatable {
        case none      // already root
        case sudo
        case pkexec
        case unavailable

        var prefix: [String] {
            switch self {
            case .none: return []
            case .sudo: return ["sudo"]
            case .pkexec: return ["pkexec"]
            case .unavailable: return []
            }
        }

        /// Can this elevation method run without a controlling terminal for a
        /// password? Root needs none; `pkexec` shows its own graphical prompt;
        /// `sudo` normally needs a TTY password, so it can't run over HTTP.
        public var canElevateNonInteractively: Bool {
            switch self {
            case .none, .pkexec: return true
            case .sudo, .unavailable: return false
            }
        }
    }

    public static func detectElevation() -> Elevation {
        if geteuid() == 0 { return .none }
        if toolAvailable("sudo") { return .sudo }
        if toolAvailable("pkexec") { return .pkexec }
        return .unavailable
    }

    // MARK: - Plan (pure, testable)

    public struct InstallPlan: Equatable {
        public let packageManager: PackageManager
        public let packages: [String]
        public let elevation: Elevation
        /// Fully-formed argv commands, elevation prefix already applied.
        public let commands: [[String]]

        /// A copy-pasteable shell rendering, for display / manual fallback.
        public var shellString: String {
            commands.map { $0.joined(separator: " ") }.joined(separator: " && ")
        }
    }

    /// Builds the elevated install commands. Pure — every input is passed in,
    /// nothing is read from the environment, so it is unit-testable.
    public static func buildPlan(
        packageManager: PackageManager,
        elevation: Elevation,
        assumeYes: Bool
    ) -> InstallPlan {
        let packages = packageManager.pulsePackages
        let base = packageManager.installCommands(packages: packages, assumeYes: assumeYes)
        let prefix = elevation.prefix
        let commands = base.map { prefix + $0 }
        return InstallPlan(
            packageManager: packageManager,
            packages: packages,
            elevation: elevation,
            commands: commands)
    }

    // MARK: - Status

    public struct Status {
        public let satisfied: Bool
        public let missingTools: [String]
        public let packageManager: PackageManager?
        public let elevation: Elevation
        public let plan: InstallPlan?
        /// Can the app run the install itself (a package manager exists and we
        /// can elevate, or already root)?
        public var canAutoInstall: Bool {
            plan != nil && elevation != .unavailable
        }
    }

    public static func status(assumeYes: Bool = true) -> Status {
        let missing = missingTools()
        let pm = detectPackageManager()
        let elevation = detectElevation()
        let plan = pm.map { buildPlan(packageManager: $0, elevation: elevation, assumeYes: assumeYes) }
        return Status(
            satisfied: missing.isEmpty,
            missingTools: missing,
            packageManager: pm,
            elevation: elevation,
            plan: plan)
    }

    // MARK: - Execution

    public enum InstallResult {
        case alreadySatisfied
        case success
        case noPackageManager
        case cannotElevate(command: String)
        case failed(command: String, exitCode: Int32)
        case unsupportedPlatform
    }

    /// Installs the missing tools. `interactive` controls whether elevation
    /// may prompt on the terminal (sudo/pkexec inherit our stdio when true).
    /// `log` receives human-readable progress lines.
    @discardableResult
    public static func install(
        assumeYes: Bool = true,
        interactive: Bool = true,
        log: (String) -> Void = { print($0) }
    ) -> InstallResult {
        #if !os(Linux)
        // parec/pacat are Linux-only; nothing to do on the dev host.
        if missingTools().isEmpty { return .alreadySatisfied }
        return .unsupportedPlatform
        #else
        if missingTools().isEmpty { return .alreadySatisfied }
        guard let pm = detectPackageManager() else { return .noPackageManager }
        let elevation = detectElevation()
        let plan = buildPlan(packageManager: pm, elevation: elevation, assumeYes: assumeYes)

        // Without a terminal (e.g. triggered from the web panel), only
        // passwordless elevation can work — otherwise `sudo` blocks on a
        // password we can't supply. Surface the command for the user instead.
        if elevation == .unavailable || (!interactive && !elevation.canElevateNonInteractively) {
            return .cannotElevate(command: plan.shellString)
        }

        log("Installing \(plan.packages.joined(separator: ", ")) via \(pm.displayName)…")
        for command in plan.commands {
            log("  $ \(command.joined(separator: " "))")
            let code = runInherit(command, interactive: interactive)
            if code != 0 {
                return .failed(command: command.joined(separator: " "), exitCode: code)
            }
        }

        // Confirm the tools are actually present now.
        return missingTools().isEmpty
            ? .success
            : .failed(command: plan.shellString, exitCode: -1)
        #endif
    }

    /// Runs a command with inherited stdio (so a sudo password prompt and the
    /// package manager's own output reach the user's terminal). Returns exit code.
    private static func runInherit(_ argv: [String], interactive: Bool) -> Int32 {
        guard let first = argv.first else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        _ = first
        if !interactive {
            // No TTY (e.g. web-triggered): don't let sudo block on a password.
            process.standardInput = FileHandle.nullDevice
        }
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
