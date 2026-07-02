import Testing
import Foundation
@testable import EQRouterCore

struct TenBandEQTests {
    let sampleRate = 48000.0

    @Test func flatEQPassesSignalThroughNearIdentically() {
        let eq = TenBandEQ(sampleRate: sampleRate)
        var maxDiff = 0.0
        for n in 0..<2000 {
            let input = sin(2 * Double.pi * 440 * Double(n) / sampleRate)
            let output = eq.process(input)
            maxDiff = max(maxDiff, abs(output - input))
        }
        #expect(maxDiff < 1e-6)
    }

    @Test func bandBoostIncreasesEnergyNearItsFrequency() {
        func rmsAtTone(_ freq: Double) -> Double {
            let eq = TenBandEQ(sampleRate: sampleRate)
            eq.setGain(12, forBandID: 5) // 1000 Hz band
            var sumSquares = 0.0
            let n = 4096
            for i in 0..<n {
                let input = sin(2 * Double.pi * freq * Double(i) / sampleRate)
                let output = eq.process(input)
                sumSquares += output * output
            }
            return sqrt(sumSquares / Double(n))
        }

        let boosted = rmsAtTone(1000)
        let untouched = rmsAtTone(60)
        #expect(boosted > untouched)
    }

    @Test func resetReturnsAllBandsToZeroGain() {
        let eq = TenBandEQ(sampleRate: sampleRate)
        eq.setGain(8, forBandID: 0)
        eq.setGain(-5, forBandID: 9)
        eq.reset()
        #expect(eq.bands.allSatisfy { $0.gainDb == 0 })
    }

    @Test func gainIsClampedToDesignRange() {
        let eq = TenBandEQ(sampleRate: sampleRate)
        eq.setGain(99, forBandID: 0)
        #expect(eq.bands[0].gainDb == TenBandLayout.gainRangeDb.upperBound)
    }
}

struct CorrectionEQTests {
    let sampleRate = 48000.0

    @Test func orivetiOD200PresetHasNoPreampDampening() {
        // Locked-in contract: the bundled OD200 profile must not bake in
        // a preamp attenuation. The user is the safeguard via the per-band
        // ±12 dB clamp; adding −6.7 dB of pre-attenuation would silently
        // cancel out their boosts and make "test extremes" impossible.
        #expect(HeadphoneProfile.orivetiOD200.preampDb == 0)
    }

    @Test func correctionEqRespectsProfilePreampWhenSet() {
        // The CorrectionEQ class itself still applies whatever preamp the
        // loaded profile specifies — that mechanism exists for profiles
        // that genuinely need it. We just don't ship one that uses it.
        let preampedProfile = HeadphoneProfile(
            id: "test", modelName: "Test", sourceProject: "Test",
            type: .parametric, preampDb: -12, filters: []
        )
        let correction = CorrectionEQ(sampleRate: sampleRate)
        correction.loadProfile(preampedProfile)
        // -12 dB preamp = 0.2512× linear; input 1.0 should come out ~0.25.
        let out = correction.process(1.0)
        #expect(abs(out - 0.2512) < 0.01)
    }

    @Test func bypassReturnsInputUnchanged() {
        let correction = CorrectionEQ(sampleRate: sampleRate)
        correction.loadProfile(.orivetiOD200)
        correction.isBypassed = true
        #expect(correction.process(0.5) == 0.5)
    }

    @Test func removeProfileFallsBackToPassthrough() {
        let correction = CorrectionEQ(sampleRate: sampleRate)
        correction.loadProfile(.orivetiOD200)
        correction.removeProfile()
        #expect(correction.process(0.42) == 0.42)
    }
}

struct AppRoutePersistenceTests {
    @Test func appRouteRoundTripsImportedAndCorrectionState() throws {
        var route = AppRoute(bundleID: "com.spotify.client", displayName: "Spotify")
        route.targetOutputDeviceID = "BuiltInSpeakerDevice"
        route.gainDb = -1.5
        route.isMuted = true
        route.customEQBands[2].gainDb = 4
        route.customEQBypassed = true
        route.outputTrimDb = -3
        route.correctionProfile = .orivetiOD200
        route.correctionBypassed = true
        route.selectedGenre = .rock
        route.importedProfileName = "My Imported EQ"
        route.importedParametricFilters = [
            ParametricFilterSpec(shape: .peaking, frequencyHz: 1000, gainDb: 6, q: 1.1)
        ]
        route.importedParametricPreampDb = -4

        let data = try JSONEncoder().encode(route)
        let restored = try JSONDecoder().decode(AppRoute.self, from: data)

        #expect(restored.bundleID == route.bundleID)
        #expect(restored.displayName == route.displayName)
        #expect(restored.targetOutputDeviceID == route.targetOutputDeviceID)
        #expect(restored.gainDb == route.gainDb)
        #expect(restored.isMuted == route.isMuted)
        #expect(restored.customEQBands == route.customEQBands)
        #expect(restored.customEQBypassed == route.customEQBypassed)
        #expect(restored.outputTrimDb == route.outputTrimDb)
        #expect(restored.correctionProfile?.id == HeadphoneProfile.orivetiOD200.id)
        #expect(restored.correctionBypassed == route.correctionBypassed)
        #expect(restored.selectedGenre == route.selectedGenre)
        #expect(restored.importedProfileName == route.importedProfileName)
        #expect(restored.importedParametricFilters == route.importedParametricFilters)
        #expect(restored.importedParametricPreampDb == route.importedParametricPreampDb)
    }
}

struct RouteDSPChainTests {
    let sampleRate = 48000.0

    @Test func muteForcesZeroOutput() {
        let chain = RouteDSPChain(sampleRate: sampleRate)
        chain.isMuted = true
        #expect(chain.process(1.0) == 0.0)
    }

    @Test func customEQRemainsActiveWhenCorrectionDisabled() {
        let chain = RouteDSPChain(sampleRate: sampleRate)
        chain.customEQ.setGain(12, forBandID: 5)
        chain.correctionEQ.loadProfile(.orivetiOD200)
        chain.correctionEQ.isBypassed = true

        var withCustomOnly = 0.0
        for n in 0..<4096 {
            let input = sin(2 * Double.pi * 1000 * Double(n) / sampleRate)
            withCustomOnly = max(withCustomOnly, abs(chain.process(input)))
        }
        #expect(withCustomOnly > 0)
    }

    @Test func limiterPreventsClippingAfterStackedBoosts() {
        let chain = RouteDSPChain(sampleRate: sampleRate)
        for bandID in 0..<10 {
            chain.customEQ.setGain(12, forBandID: bandID)
        }
        var maxOutput = 0.0
        for n in 0..<8192 {
            let input = sin(2 * Double.pi * 1000 * Double(n) / sampleRate)
            maxOutput = max(maxOutput, abs(chain.process(input)))
        }
        #expect(maxOutput <= chain.limiter.thresholdLinear + 1e-9)
    }

    @Test func safetyCeilingWhenEnabledKeepsOutputUnderUnity() {
        // Opt-in ceiling path: same maxed-out boost configuration, but the
        // user has explicitly enabled the ceiling. The chain must keep
        // output at or below the unprocessed source.
        let chain = RouteDSPChain(sampleRate: sampleRate)
        chain.safetyCeilingEnabled = true
        chain.setRouteGain(0)
        for bandID in 0..<10 {
            chain.customEQ.setGain(12, forBandID: bandID)
        }
        chain.correctionEQ.loadProfile(.orivetiOD200)

        #expect(chain.isSafetyCeilingActive)

        var maxOutput = 0.0
        for n in 0..<8192 {
            let input = sin(2 * Double.pi * 1000 * Double(n) / sampleRate)
            maxOutput = max(maxOutput, abs(chain.process(input)))
        }
        #expect(maxOutput <= 1.0 + 1e-6)
    }

    @Test func softSaturatorPreventsOutputFromClipping() {
        // Default (ceiling off) path: extreme boosts let through, but the
        // stateless soft saturator must still clamp output to the safe
        // ceiling so we never deliver out-of-range samples to the DAC.
        let chain = RouteDSPChain(sampleRate: sampleRate)
        // ceiling stays off (default)
        for bandID in 0..<10 {
            chain.customEQ.setGain(12, forBandID: bandID)
        }
        var maxOutput = 0.0
        for n in 0..<8192 {
            let input = sin(2 * Double.pi * 1000 * Double(n) / sampleRate)
            maxOutput = max(maxOutput, abs(chain.process(input)))
        }
        #expect(maxOutput <= Limiter.ceiling + 1e-9)
        #expect(!chain.isSafetyCeilingActive)
    }

    @Test func safetyCeilingIsInactiveWhenControlsOnlyAttenuate() {
        let chain = RouteDSPChain(sampleRate: sampleRate)
        chain.setRouteGain(-6)
        chain.customEQ.setGain(-3, forBandID: 0)
        #expect(!chain.isSafetyCeilingActive)
    }

    @Test func safetyCeilingAccountsForImportedParametricProfiles() {
        let chain = RouteDSPChain(sampleRate: sampleRate)
        chain.safetyCeilingEnabled = true

        let imported = HeadphoneProfile(
            id: "imported",
            modelName: "Imported",
            sourceProject: "Imported preset",
            type: .parametric,
            preampDb: 0,
            filters: [ParametricFilterSpec(shape: .peaking, frequencyHz: 1000, gainDb: 9, q: 1.0)]
        )
        chain.userParametricEQ.loadProfile(imported)

        #expect(chain.isSafetyCeilingActive)

        var maxOutput = 0.0
        for n in 0..<8192 {
            let input = sin(2 * Double.pi * 1000 * Double(n) / sampleRate)
            maxOutput = max(maxOutput, abs(chain.process(input)))
        }
        #expect(maxOutput <= 1.0 + 1e-6)
    }
}
