import Testing
@testable import EQRouterCore

struct RealtimePerformanceTests {
    @Test func blockMeterUpdateMatchesSamplewisePeakWithinTolerance() {
        let sampleRate = 48_000.0
        let samples = [0.1, -0.4, 0.3, -0.9, 0.2, -0.1]

        let samplewise = PeakMeter(sampleRate: sampleRate)
        for sample in samples {
            samplewise.update(sample)
        }

        let blockwise = PeakMeter(sampleRate: sampleRate)
        blockwise.updateBlockPeak(0.9, frameCount: samples.count)

        #expect(abs(samplewise.currentPeak - blockwise.currentPeak) < 0.001)
    }

    @Test func realtimeWorkDefaultsToCaptureSideDSP() {
        #expect(RouteRealtimeWorkStrategy.defaultDSPStage == .capture)
    }
}
