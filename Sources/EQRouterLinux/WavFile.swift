import Foundation

/// Minimal, dependency-free RIFF/WAVE reader and writer.
///
/// Supports the formats a desktop audio tool actually meets: PCM 16/24/32-bit
/// integer and 32-bit IEEE float, mono or multichannel, little-endian (the
/// only endianness real-world WAV files use). Unknown chunks are skipped, so
/// files with `LIST`/`fact`/`bext` metadata still read.
///
/// Everything is decoded to normalized interleaved `Float` in [−1, 1] — the
/// exact layout `RouteDSPChain.processInterleaved` consumes — and re-encoded
/// back to the source bit depth on write so a round trip is format-preserving.
public struct WavAudio {
    public var sampleRate: Double
    public var channelCount: Int
    /// Interleaved samples, normalized to [−1, 1].
    public var samples: [Float]
    /// Preserved so a processed file writes back in the same format.
    public var sourceBitsPerSample: Int
    public var sourceIsFloat: Bool

    public var frameCount: Int { channelCount > 0 ? samples.count / channelCount : 0 }

    public init(sampleRate: Double, channelCount: Int, samples: [Float],
                sourceBitsPerSample: Int = 32, sourceIsFloat: Bool = true) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples = samples
        self.sourceBitsPerSample = sourceBitsPerSample
        self.sourceIsFloat = sourceIsFloat
    }

    public enum WavError: Error, CustomStringConvertible {
        case notRIFF, notWAVE, missingFmt, missingData, unsupportedFormat(String), truncated

        public var description: String {
            switch self {
            case .notRIFF: return "not a RIFF file"
            case .notWAVE: return "not a WAVE file"
            case .missingFmt: return "missing 'fmt ' chunk"
            case .missingData: return "missing 'data' chunk"
            case .unsupportedFormat(let s): return "unsupported WAV format: \(s)"
            case .truncated: return "file is truncated"
            }
        }
    }

    // MARK: - Read

    public static func read(contentsOf url: URL) throws -> WavAudio {
        try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> WavAudio {
        let bytes = [UInt8](data)
        func u32(_ o: Int) -> UInt32 {
            UInt32(bytes[o]) | UInt32(bytes[o+1]) << 8 | UInt32(bytes[o+2]) << 16 | UInt32(bytes[o+3]) << 24
        }
        func u16(_ o: Int) -> UInt16 { UInt16(bytes[o]) | UInt16(bytes[o+1]) << 8 }
        func tag(_ o: Int) -> String { String(bytes: bytes[o..<o+4], encoding: .ascii) ?? "" }

        guard bytes.count >= 12 else { throw WavError.truncated }
        guard tag(0) == "RIFF" else { throw WavError.notRIFF }
        guard tag(8) == "WAVE" else { throw WavError.notWAVE }

        var offset = 12
        var format: UInt16 = 0
        var channels = 0
        var rate: Double = 0
        var bits = 0
        var dataRange: Range<Int>?

        while offset + 8 <= bytes.count {
            let id = tag(offset)
            let size = Int(u32(offset + 4))
            let body = offset + 8
            guard body + size <= bytes.count else {
                // Some encoders pad the final data chunk size; clamp instead of failing.
                if id == "data" { dataRange = body..<bytes.count; break }
                throw WavError.truncated
            }
            switch id {
            case "fmt ":
                format = u16(body)
                channels = Int(u16(body + 2))
                rate = Double(u32(body + 4))
                bits = Int(u16(body + 14))
                if format == 0xFFFE, size >= 40 { // WAVE_FORMAT_EXTENSIBLE
                    format = u16(body + 24) // sub-format tag
                }
            case "data":
                dataRange = body..<(body + size)
            default:
                break
            }
            // Chunks are word-aligned: an odd size is followed by a pad byte.
            offset = body + size + (size & 1)
        }

        guard channels > 0, rate > 0, bits > 0 else { throw WavError.missingFmt }
        guard let range = dataRange else { throw WavError.missingData }

        let isFloat = (format == 3)
        let isPCM = (format == 1)
        guard isFloat || isPCM else {
            throw WavError.unsupportedFormat("audioFormat=\(format)")
        }

        let samples = try decodeSamples(bytes: bytes, range: range, bits: bits, isFloat: isFloat)
        return WavAudio(sampleRate: rate, channelCount: channels, samples: samples,
                        sourceBitsPerSample: bits, sourceIsFloat: isFloat)
    }

    private static func decodeSamples(bytes: [UInt8], range: Range<Int>, bits: Int, isFloat: Bool) throws -> [Float] {
        let bytesPerSample = bits / 8
        guard bytesPerSample > 0 else { throw WavError.unsupportedFormat("bits=\(bits)") }
        let count = range.count / bytesPerSample
        var out = [Float](repeating: 0, count: count)
        var o = range.lowerBound
        if isFloat {
            switch bits {
            case 32:
                for i in 0..<count {
                    let u = UInt32(bytes[o]) | UInt32(bytes[o+1]) << 8 | UInt32(bytes[o+2]) << 16 | UInt32(bytes[o+3]) << 24
                    out[i] = Float(bitPattern: u); o += 4
                }
            case 64:
                for i in 0..<count {
                    var u: UInt64 = 0
                    for b in 0..<8 { u |= UInt64(bytes[o+b]) << (8*b) }
                    out[i] = Float(Double(bitPattern: u)); o += 8
                }
            default: throw WavError.unsupportedFormat("float\(bits)")
            }
        } else {
            switch bits {
            case 16:
                for i in 0..<count {
                    let s = Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o+1]) << 8)
                    out[i] = Float(s) / 32768.0; o += 2
                }
            case 24:
                for i in 0..<count {
                    var v = Int32(bytes[o]) | Int32(bytes[o+1]) << 8 | Int32(bytes[o+2]) << 16
                    if v & 0x800000 != 0 { v |= ~0xFFFFFF } // sign-extend
                    out[i] = Float(v) / 8388608.0; o += 3
                }
            case 32:
                for i in 0..<count {
                    let s = Int32(bitPattern: UInt32(bytes[o]) | UInt32(bytes[o+1]) << 8 | UInt32(bytes[o+2]) << 16 | UInt32(bytes[o+3]) << 24)
                    out[i] = Float(Double(s) / 2147483648.0); o += 4
                }
            default: throw WavError.unsupportedFormat("pcm\(bits)")
            }
        }
        return out
    }

    // MARK: - Write

    public func write(to url: URL) throws {
        try encode().write(to: url, options: .atomic)
    }

    public func encode() -> Data {
        let bits = sourceIsFloat ? max(sourceBitsPerSample, 32) : sourceBitsPerSample
        let isFloat = sourceIsFloat
        let bytesPerSample = bits / 8
        let audioFormat: UInt16 = isFloat ? 3 : 1
        let blockAlign = channelCount * bytesPerSample
        let byteRate = Int(sampleRate) * blockAlign
        let dataSize = samples.count * bytesPerSample

        var out = [UInt8]()
        out.reserveCapacity(44 + dataSize)
        func put32(_ v: UInt32) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v>>8) & 0xFF)); out.append(UInt8((v>>16) & 0xFF)); out.append(UInt8((v>>24) & 0xFF)) }
        func put16(_ v: UInt16) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v>>8) & 0xFF)) }
        func putTag(_ s: String) { out.append(contentsOf: Array(s.utf8)) }

        putTag("RIFF"); put32(UInt32(36 + dataSize)); putTag("WAVE")
        putTag("fmt "); put32(16)
        put16(audioFormat); put16(UInt16(channelCount))
        put32(UInt32(sampleRate)); put32(UInt32(byteRate))
        put16(UInt16(blockAlign)); put16(UInt16(bits))
        putTag("data"); put32(UInt32(dataSize))

        if isFloat {
            for s in samples {
                let u = s.bitPattern
                out.append(UInt8(u & 0xFF)); out.append(UInt8((u>>8) & 0xFF)); out.append(UInt8((u>>16) & 0xFF)); out.append(UInt8((u>>24) & 0xFF))
            }
        } else {
            switch bits {
            case 16:
                for s in samples {
                    let v = Int16(max(-32768, min(32767, (Double(s) * 32768.0).rounded())))
                    let u = UInt16(bitPattern: v)
                    out.append(UInt8(u & 0xFF)); out.append(UInt8((u>>8) & 0xFF))
                }
            case 24:
                for s in samples {
                    let v = Int32(max(-8388608, min(8388607, (Double(s) * 8388608.0).rounded())))
                    out.append(UInt8(UInt32(bitPattern: v) & 0xFF))
                    out.append(UInt8((UInt32(bitPattern: v) >> 8) & 0xFF))
                    out.append(UInt8((UInt32(bitPattern: v) >> 16) & 0xFF))
                }
            default: // 32-bit int
                for s in samples {
                    let v = Int32(max(-2147483648, min(2147483647, (Double(s) * 2147483648.0).rounded())))
                    let u = UInt32(bitPattern: v)
                    out.append(UInt8(u & 0xFF)); out.append(UInt8((u>>8) & 0xFF)); out.append(UInt8((u>>16) & 0xFF)); out.append(UInt8((u>>24) & 0xFF))
                }
            }
        }
        return Data(out)
    }
}
