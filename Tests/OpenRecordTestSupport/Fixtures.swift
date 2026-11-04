import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import OpenRecordCore

public struct RGB: Sendable, Equatable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { (self.r, self.g, self.b) = (r, g, b) }

    public static let red = RGB(220, 30, 30)
    public static let green = RGB(30, 200, 60)
    public static let blue = RGB(30, 60, 220)
}

public enum Fixtures {
    public static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openrecord-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var whisperAvailable: Bool {
        (try? WhisperTranscriber.locate()) != nil
    }

    /// H.264 MP4 showing `colors[i]` during second `i`.
    public static func makeColorVideo(at url: URL, colors: [RGB], width: Int = 320, height: Int = 180, fps: Int32 = 10) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (second, color) in colors.enumerated() {
            for frame in 0..<Int(fps) {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                let buffer = try solidPixelBuffer(color, width: width, height: height)
                let time = CMTime(value: CMTimeValue(second * Int(fps) + frame), timescale: fps)
                adaptor.append(buffer, withPresentationTime: time)
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(colors.count * Int(fps)), timescale: fps))
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    /// Speaks `text` with the system voice into an AIFF file.
    public static func makeSpeech(_ text: String, at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, text]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Muxes a video file and an audio file (starting at `audioOffset` seconds) into an MP4.
    public static func mux(video: URL, audio: URL, audioOffset: Double, to output: URL) async throws {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let offset = CMTime(seconds: audioOffset, preferredTimescale: 600)

        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: try await videoAsset.loadTracks(withMediaType: .video)[0],
            at: .zero
        )
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTimeMinimum(audioDuration, videoDuration - offset)),
            of: try await audioAsset.loadTracks(withMediaType: .audio)[0],
            at: offset
        )

        // The async `export(to:as:)` crashes resuming its continuation on macOS 15.6 (SIGBUS in swift_retain).
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        export.outputURL = output
        export.outputFileType = .mp4
        nonisolated(unsafe) let session = export
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        if let error = session.error { throw error }
    }

    /// A finished recording in `library` whose video is `video`, optionally with a transcript.
    @discardableResult
    public static func addRecording(
        to library: RecordingLibrary,
        createdAt: Date,
        video: URL? = nil,
        transcript: Transcript? = nil
    ) throws -> Recording {
        var recording = try library.createRecording(at: createdAt)
        recording.status = .ready
        recording.duration = 3
        if let video {
            try FileManager.default.copyItem(at: video, to: library.videoURL(for: recording))
        }
        if let transcript {
            try library.saveTranscript(transcript, for: recording.id)
            recording.transcriptStatus = .done
            recording.transcriptLanguage = transcript.language
        }
        try library.save(recording)
        return recording
    }

    /// Color of the center pixel of an encoded image.
    public static func centerColor(ofImage data: Data) -> RGB? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
            return true
        }
        return drawn ? RGB(pixel[0], pixel[1], pixel[2]) : nil
    }

    /// Video and JPEG encoding shift colors, so compare which channel dominates rather than exact values.
    public static func looksLike(_ actual: RGB, _ expected: RGB) -> Bool {
        func dominant(_ c: RGB) -> Int {
            [Int(c.r), Int(c.g), Int(c.b)].enumerated().max { $0.element < $1.element }!.offset
        }
        return dominant(actual) == dominant(expected)
    }

    private static func solidPixelBuffer(_ color: RGB, width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = base + y * bytesPerRow + x * 4
                (pixel[0], pixel[1], pixel[2], pixel[3]) = (color.b, color.g, color.r, 255)
            }
        }
        return buffer
    }
}
