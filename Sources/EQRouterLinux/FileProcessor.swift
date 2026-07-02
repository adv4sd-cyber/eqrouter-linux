import Foundation
import EQRouterCore

/// Offline WAV → EQ → WAV processing. This is the path that can be verified
/// end-to-end without any audio hardware (the DSP is deterministic), so it
/// doubles as the proof that the ported core produces correct output on the
/// Linux build.
public enum FileProcessor {
    public struct Result {
        public let frameCount: Int
        public let channelCount: Int
        public let sampleRate: Double
        public let inputPeakDb: Double
        public let outputPeakDb: Double
    }

    /// Applies `state`'s current EQ config to `input`, writing the processed
    /// audio to `output`. The DSP chain is built at the file's own sample
    /// rate so the filter frequencies land where the user expects.
    @discardableResult
    public static func process(input: URL, output: URL, state: EQState) throws -> Result {
        var audio = try WavAudio.read(contentsOf: input)
        let chain = state.makeConfiguredChain(
            sampleRate: audio.sampleRate,
            channelCount: max(audio.channelCount, 1))

        let inputPeak = audio.samples.reduce(Float(0)) { max($0, abs($1)) }
        let frameCount = audio.frameCount

        audio.samples.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            chain.processInterleaved(base, frameCount: frameCount)
        }

        let outputPeak = audio.samples.reduce(Float(0)) { max($0, abs($1)) }
        try audio.write(to: output)

        func db(_ linear: Float) -> Double {
            linear <= 1e-6 ? -120 : max(-120, 20 * log10(Double(linear)))
        }
        return Result(
            frameCount: audio.frameCount,
            channelCount: audio.channelCount,
            sampleRate: audio.sampleRate,
            inputPeakDb: db(inputPeak),
            outputPeakDb: db(outputPeak))
    }
}
