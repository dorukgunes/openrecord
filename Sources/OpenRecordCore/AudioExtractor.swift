import AVFoundation
import Foundation

enum AudioExtractor {
    static let sampleRate = 16_000

    /// Mixes every audio track of `media` down to the 16 kHz mono 16-bit WAV whisper.cpp expects.
    /// Returns false when the media has no audio track.
    static func extractWAV(from media: URL, to wav: URL) async throws -> Bool {
        let asset = AVURLAsset(url: media)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return false }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }

        FileManager.default.createFile(atPath: wav.path, contents: nil)
        let handle = try FileHandle(forWritingTo: wav)
        defer { try? handle.close() }
        try handle.write(contentsOf: wavHeader(dataSize: 0))

        var dataSize = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = Data(count: length)
            let status = chunk.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw CocoaError(.fileReadCorruptFile) }
            try handle.write(contentsOf: chunk)
            dataSize += length
        }
        if reader.status == .failed {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }

        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: wavHeader(dataSize: dataSize))
        return true
    }

    private static func wavHeader(dataSize: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(channels)
        append(UInt32(sampleRate))
        append(byteRate)
        append(channels * bitsPerSample / 8)
        append(bitsPerSample)
        header.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        return header
    }
}
