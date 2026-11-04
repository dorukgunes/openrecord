import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    public static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
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
