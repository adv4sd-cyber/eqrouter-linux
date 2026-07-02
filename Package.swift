// swift-tools-version:5.10
import PackageDescription

// Linux port of EQRouter.
//
// The DSP core (`EQRouterCore`) is a byte-for-byte-portable subset of the
// macOS app's core — every file here is pure Swift + Foundation + Atomics,
// with the CoreAudio `Audio/` folder deliberately left out. Everything
// macOS-specific (CoreAudio process taps, the SwiftUI UI) is replaced by
// `EQRouterLinux`: a PipeWire/PulseAudio real-time engine, a WAV file
// processor, and a self-hosted web control panel served over HTTP.
//
// The manifest itself never keys off `#if os(...)` — the manifest always
// runs on the host (macOS here, even when cross-compiling to Linux), so
// platform gating lives in the *source files* (`#if canImport(Glibc)`),
// never here.
let package = Package(
    name: "EQRouter",
    platforms: [.macOS("13.0")],
    products: [
        .library(name: "EQRouterCore", targets: ["EQRouterCore"]),
        .library(name: "EQRouterLinux", targets: ["EQRouterLinux"]),
        .executable(name: "eqrouter", targets: ["eqrouter"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "EQRouterCore",
            dependencies: [.product(name: "Atomics", package: "swift-atomics")],
            resources: [.process("Resources")]
        ),
        .target(
            name: "EQRouterLinux",
            dependencies: ["EQRouterCore"]
        ),
        .executableTarget(
            name: "eqrouter",
            dependencies: ["EQRouterLinux"]
        ),
        .testTarget(name: "EQRouterCoreTests", dependencies: ["EQRouterCore"]),
        .testTarget(name: "EQRouterLinuxTests", dependencies: ["EQRouterLinux"])
    ]
)
