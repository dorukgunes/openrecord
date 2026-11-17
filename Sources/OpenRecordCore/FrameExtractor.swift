import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Synchronization

public enum FrameExtractor {
    public struct Frame: Sendable {
        /// Seconds from the start of the recording.
        public let time: Double
        public let jpeg: Data
        public let width: Int
        public let height: Int
    }

    public enum Error: LocalizedError {
        case noVideoTrack
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: "The recording has no video track"
            case .encodingFailed: "Could not encode the frame as JPEG"
            }
        }
    }

    public static func duration(of url: URL, timeout: Duration? = nil) async throws -> Double {
        guard let timeout else { return try await AVURLAsset(url: url).load(.duration).seconds }
        let result = DurationResult()
        Task {
            do { result.complete(.success(try await AVURLAsset(url: url).load(.duration).seconds)) }
            catch { result.complete(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: timeout)
            result.complete(.failure(DurationProbeError.timedOut))
        }
        return try await result.wait()
    }

    private enum DurationProbeError: Swift.Error { case timedOut }

    private final class DurationResult: Sendable {
        private struct State {
            var result: Result<Double, Swift.Error>?
            var waiter: CheckedContinuation<Double, Swift.Error>?
        }
        private let state = Mutex(State())

        func complete(_ result: Result<Double, Swift.Error>) {
            let waiter = state.withLock { state -> CheckedContinuation<Double, Swift.Error>? in
                guard state.result == nil else { return nil }
                state.result = result
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(with: result)
        }

        func wait() async throws -> Double {
            try await withCheckedThrowingContinuation { continuation in
                let result = state.withLock { state -> Result<Double, Swift.Error>? in
                    if state.result == nil { state.waiter = continuation }
                    return state.result
                }
                if let result { continuation.resume(with: result) }
            }
        }
    }

    /// `count` frames spread evenly across the video, skipping the very first and last moments.
    public static func evenlySpacedTimes(count: Int, duration: Double) -> [Double] {
        guard count > 0, duration > 0 else { return [0] }
        return (0..<count).map { duration * (Double($0) + 0.5) / Double(count) }
    }

    public static func frames(
        from url: URL,
        at times: [Double],
        maxWidth: Int = 1280,
        quality: Double = 0.7
    ) async throws -> [Frame] {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw Error.noVideoTrack }
        let duration = try await asset.load(.duration).seconds

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var frames: [Frame] = []
        for time in times {
            let clamped = min(max(0, time), max(0, duration - 0.05))
            let (image, actual) = try await generator.image(at: CMTime(seconds: clamped, preferredTimescale: 600))
            frames.append(Frame(
                time: actual.seconds,
                jpeg: try jpegData(image, quality: quality),
                width: image.width,
                height: image.height
            ))
        }
        return frames
    }

    private static func jpegData(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Error.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Error.encodingFailed }
        return data as Data
    }
}
