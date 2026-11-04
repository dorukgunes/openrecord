import AVFoundation
import AppKit
import ScreenCaptureKit
import Synchronization

public struct DisplayOption: Sendable, Hashable, Identifiable {
    public let id: CGDirectDisplayID
    public let name: String
    public let pixelWidth: Int
    public let pixelHeight: Int
}

public enum RecorderError: LocalizedError {
    case screenRecordingDenied
    case microphoneDenied
    case displayNotFound
    case alreadyRecording
    case notRecording
    case startTimedOut
    case interrupted

    public var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            "OpenRecord needs Screen Recording permission (System Settings › Privacy & Security › Screen & System Audio Recording)."
        case .microphoneDenied:
            "OpenRecord needs Microphone permission (System Settings › Privacy & Security › Microphone)."
        case .displayNotFound: "That display is no longer connected."
        case .alreadyRecording: "A recording is already in progress."
        case .notRecording: "No recording is in progress."
        case .startTimedOut: "Screen capture didn't start within 5 seconds."
        case .interrupted: "OpenRecord quit while this recording was in progress."
        }
    }
}

/// Records one display plus the default microphone into a single MP4 using ScreenCaptureKit.
public final class ScreenRecorder: NSObject, Sendable {
    public struct Started: Sendable {
        public let display: DisplayOption
        public let microphone: String?
    }

    // SCStream isn't annotated Sendable, but ScreenCaptureKit drives it from arbitrary queues itself.
    private struct Session: @unchecked Sendable {
        var stream: SCStream
        var started = Completion()
        var finished = Completion()
    }

    private let session = Mutex<Session?>(nil)
    private let onUnexpectedStop: @Sendable (Error) -> Void

    /// `onUnexpectedStop` fires when capture ends without `stop()`, e.g. the display was unplugged.
    public init(onUnexpectedStop: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.onUnexpectedStop = onUnexpectedStop
    }

    /// Reads NSScreen rather than ScreenCaptureKit so listing displays never triggers the permission prompt.
    @MainActor
    public static func availableDisplays() -> [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplayOption(
                id: number.uint32Value,
                name: screen.localizedName,
                pixelWidth: Int(screen.frame.width * screen.backingScaleFactor),
                pixelHeight: Int(screen.frame.height * screen.backingScaleFactor)
            )
        }
    }

    @MainActor
    public func start(display displayID: CGDirectDisplayID, to url: URL, captureMicrophone: Bool = true) async throws -> Started {
        guard session.withLock({ $0 == nil }) else { throw RecorderError.alreadyRecording }
        // Ask for the microphone first: the screen prompt sends the user off to System Settings,
        // and asking in this order gets both prompts out of the way on the first attempt.
        let microphone = captureMicrophone ? AVCaptureDevice.default(for: .audio) : nil
        if captureMicrophone {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecorderError.microphoneDenied }
        }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw RecorderError.screenRecordingDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let option = Self.availableDisplays().first(where: { $0.id == displayID })
        else { throw RecorderError.displayNotFound }

        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = option.pixelWidth
        config.height = option.pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        config.captureMicrophone = microphone != nil
        config.microphoneCaptureDeviceID = microphone?.uniqueID

        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        // H.264 tops out at 4096 px; larger (5K/6K) displays need HEVC.
        recordingConfig.videoCodecType = max(option.pixelWidth, option.pixelHeight) > 4096 ? .hevc : .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recordingConfig, delegate: self))
        let current = Session(stream: stream)
        session.withLock { $0 = current }
        do {
            try await stream.startCapture()
            // Stopping before the first frame is written fails the whole file, so only report
            // "recording" once ScreenCaptureKit says the file has started.
            Task { [started = current.started] in
                try? await Task.sleep(for: .seconds(5))
                started.complete(.failure(RecorderError.startTimedOut))
            }
            try await current.started.wait()
        } catch {
            try? await stream.stopCapture()
            session.withLock { $0 = nil }
            throw error
        }
        return Started(display: option, microphone: microphone?.localizedName)
    }

    /// Returns once the MP4 is fully written.
    public func stop() async throws {
        guard let current = session.withLock({ $0 }) else { throw RecorderError.notRecording }
        defer { session.withLock { $0 = nil } }
        try await current.stream.stopCapture()
        try await current.finished.wait()
    }
}

extension ScreenRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard let current = session.withLock({ state in defer { state = nil }; return state }) else { return }
        current.started.complete(.failure(error))
        current.finished.complete(.failure(error))
        onUnexpectedStop(error)
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        session.withLock { $0 }?.started.complete(.success(()))
    }

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        session.withLock { $0 }?.finished.complete(.success(()))
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        guard let current = session.withLock({ $0 }) else { return }
        current.started.complete(.failure(error))
        current.finished.complete(.failure(error))
    }
}

/// A one-shot result that can be awaited before or after it arrives; later results are ignored.
final class Completion: Sendable {
    private struct State {
        var result: Result<Void, Error>?
        var waiter: CheckedContinuation<Void, Error>?
    }

    private let state = Mutex(State())

    func complete(_ result: Result<Void, Error>) {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Error>? in
            guard state.result == nil else { return nil }
            state.result = result
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(with: result)
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let result = state.withLock { state -> Result<Void, Error>? in
                if state.result == nil { state.waiter = continuation }
                return state.result
            }
            if let result { continuation.resume(with: result) }
        }
    }
}
