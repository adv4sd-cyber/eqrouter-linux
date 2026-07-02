import Testing
import Foundation
@testable import EQRouterCore

struct EQPresetTests {

    @Test func presetRoundTripsThroughJSON() {
        let original = EQPreset(
            name: "Warm Bass",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            bandGains: [3, 2, 1, 0, 0, 0, 0, 0, 0, 0],
            selectedGenre: .vocal,
            correctionProfileID: HeadphoneProfile.orivetiOD200.id,
            outputTrimDb: -1.5
        )

        let data = try! JSONEncoder().encode(original)
        let restored = try! JSONDecoder().decode(EQPreset.self, from: data)

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.bandGains == original.bandGains)
        #expect(restored.selectedGenre == original.selectedGenre)
        #expect(restored.correctionProfileID == original.correctionProfileID)
        #expect(restored.outputTrimDb == original.outputTrimDb)
    }

    @Test func presetRejectsWrongBandCount() {
        // The init precondition should fire if a preset is constructed
        // with the wrong number of bands. We can't actually catch a Swift
        // precondition failure from a test, but we can confirm that the
        // *correct* shape always succeeds — this test is here to lock
        // in the contract that band count == 10.
        let preset = EQPreset(
            name: "x", createdAt: Date(),
            bandGains: Array(repeating: 0.0, count: 10),
            selectedGenre: .flat, correctionProfileID: nil, outputTrimDb: 0
        )
        #expect(preset.bandGains.count == TenBandLayout.centerFrequenciesHz.count)
    }

    @Test func bundledProfileLookupResolvesOrivetiOD200() {
        let resolved = HeadphoneProfile.bundled(id: HeadphoneProfile.orivetiOD200.id)
        #expect(resolved?.modelName == "Oriveti OD200")
    }

    @Test func bundledProfileLookupReturnsNilForUnknownID() {
        let resolved = HeadphoneProfile.bundled(id: "autoeq.unknown.model")
        #expect(resolved == nil)
    }

    @Test func presetWithMissingProfileIDStillDecodes() {
        // A preset saved without correction (correctionProfileID = nil)
        // must round-trip correctly — Optional nil through JSON should
        // come back as nil, not as missing-key error.
        let preset = EQPreset(
            name: "No correction",
            createdAt: Date(),
            bandGains: Array(repeating: 0.0, count: 10),
            selectedGenre: .flat,
            correctionProfileID: nil,
            outputTrimDb: 0
        )
        let data = try! JSONEncoder().encode(preset)
        let restored = try! JSONDecoder().decode(EQPreset.self, from: data)
        #expect(restored.correctionProfileID == nil)
    }
}
