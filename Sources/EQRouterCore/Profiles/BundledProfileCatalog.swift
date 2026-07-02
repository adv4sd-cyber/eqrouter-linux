import Foundation

public extension HeadphoneProfile {
    static var allBundled: [HeadphoneProfile] {
        BundledProfileCatalog.shared.allProfiles
    }

    static var featuredBundledProfiles: [HeadphoneProfile] {
        BundledProfileCatalog.shared.featuredProfiles
    }
}

enum BundledProfileCatalog {
    static let shared = load()

    /// Locates `BundledProfiles.json` without going through SwiftPM's
    /// generated `Bundle.module` accessor — that accessor's lazy
    /// initializer calls `fatalError` directly if it can't resolve the
    /// resource bundle, which a `guard let` here can't protect against.
    /// Checked in order:
    ///   1. Flattened directly into a real .app's Contents/Resources —
    ///      where the packaging script places it.
    ///   2. The SwiftPM resource bundle sitting next to the executable —
    ///      covers running `.build/.../EQRouterUI` directly (dev/debug).
    /// Returns nil (never crashes) if neither exists, so callers fall
    /// back to the single built-in profile below.
    private static func resolveResourceURL() -> URL? {
        let fm = FileManager.default

        // 1. Standard SwiftPM resource accessor — resolves for `swift run`
        //    and installed layouts where the .bundle sits next to the binary.
        if let url = Bundle.module.url(forResource: "BundledProfiles", withExtension: "json") {
            return url
        }
        // 2. Main bundle (macOS .app path, or any host that flattens it in).
        if let url = Bundle.main.url(forResource: "BundledProfiles", withExtension: "json") {
            return url
        }
        // 3. Scan the executable directory for any `*.bundle/BundledProfiles.json`
        //    — covers Linux `.build/<config>/` layouts where the generated
        //    bundle name is `EQRouter_EQRouterCore.bundle` but we don't want
        //    to hard-code it. Never crashes: falls through to the built-in
        //    OD200 profile if nothing is found.
        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            // SwiftPM names the resource container `<Pkg>_<Target>.bundle` on
            // macOS but `<Pkg>_<Target>.resources` on Linux — accept either.
            for suffix in ["EQRouter_EQRouterCore.bundle", "EQRouter_EQRouterCore.resources"] {
                let direct = executableDir
                    .appendingPathComponent(suffix)
                    .appendingPathComponent("BundledProfiles.json")
                if fm.fileExists(atPath: direct.path) { return direct }
            }

            if let entries = try? fm.contentsOfDirectory(
                at: executableDir, includingPropertiesForKeys: nil
            ) {
                for entry in entries where entry.pathExtension == "bundle" || entry.pathExtension == "resources" {
                    let candidate = entry.appendingPathComponent("BundledProfiles.json")
                    if fm.fileExists(atPath: candidate.path) { return candidate }
                }
            }
        }
        // 4. Explicit override for packaged installs (e.g. /usr/share/eqrouter).
        if let override = ProcessInfo.processInfo.environment["EQROUTER_PROFILES"],
           fm.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        return nil
    }

    static func load() -> LoadedCatalog {
        // 1. External file first (SPM resource bundle, or an EQROUTER_PROFILES
        //    override) — lets the catalog be updated without recompiling.
        if let profiles = decodeFromResourceFile() {
            return makeCatalog(profiles)
        }
        // 2. Compiled-in fallback. Guarantees the full catalog is present even
        //    when the binary runs WITHOUT its resource bundle adjacent (a bare
        //    or moved executable) — the exact case that otherwise collapsed
        //    the picker to just the single built-in profile below.
        if let profiles = try? JSONDecoder().decode(
            [HeadphoneProfile].self, from: EmbeddedProfilesData.jsonData),
           !profiles.isEmpty {
            return makeCatalog(profiles)
        }
        // 3. Last resort — a single known-good profile so the app still runs.
        return LoadedCatalog(
            allProfiles: [HeadphoneProfile.orivetiOD200],
            featuredProfiles: [HeadphoneProfile.orivetiOD200],
            idIndex: [HeadphoneProfile.orivetiOD200.id: HeadphoneProfile.orivetiOD200]
        )
    }

    private static func decodeFromResourceFile() -> [HeadphoneProfile]? {
        guard let url = resolveResourceURL(),
              let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([HeadphoneProfile].self, from: data),
              !profiles.isEmpty else { return nil }
        return profiles
    }

    private static func makeCatalog(_ profiles: [HeadphoneProfile]) -> LoadedCatalog {
        let uniqueProfiles = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values
            .sorted { lhs, rhs in
                lhs.modelName.localizedCaseInsensitiveCompare(rhs.modelName) == .orderedAscending
            }
        let featuredProfiles = uniqueProfiles
            .filter(\.isFeatured)
            .sorted { lhs, rhs in
                lhs.modelName.localizedCaseInsensitiveCompare(rhs.modelName) == .orderedAscending
            }

        return LoadedCatalog(
            allProfiles: uniqueProfiles,
            featuredProfiles: featuredProfiles,
            idIndex: Dictionary(uniqueProfiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )
    }
}

struct LoadedCatalog {
    let allProfiles: [HeadphoneProfile]
    let featuredProfiles: [HeadphoneProfile]
    let idIndex: [String: HeadphoneProfile]
}
