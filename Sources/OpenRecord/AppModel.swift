import AppKit
import Observation
import OpenRecordCore
import ServiceManagement
import os

let log = Logger(subsystem: "io.github.dorukgunes.openrecord", category: "app")

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case idle
        case starting
        case recording(id: String, since: Date)
        case stopping
    }

    private(set) var state: State = .idle
    private(set) var now = Date()
    private(set) var displays: [DisplayOption] = []
    private(set) var recent: [Recording] = []
    private(set) var lastError: String?
    /// System Settings pane that fixes `lastError`, when it's a missing permission.
    private(set) var privacySettingsURL: URL?
    private(set) var transcriptionSetupError: String?
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let repositoryURL = URL(string: "https://github.com/dorukgunes/openrecord")!

    var selectedDisplayID: CGDirectDisplayID? {
        didSet { UserDefaults.standard.set(selectedDisplayID.map { Int($0) }, forKey: "displayID") }
    }

    let library = RecordingLibrary()
    @ObservationIgnored private var recorder: ScreenRecorder!
    @ObservationIgnored private var transcriptions: TranscriptionQueue!
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init() {
        selectedDisplayID = (UserDefaults.standard.object(forKey: "displayID") as? Int).map(CGDirectDisplayID.init)
        recorder = ScreenRecorder { [weak self] error in
            Task { @MainActor in self?.recordingEndedUnexpectedly(error) }
        }
        transcriptions = TranscriptionQueue(library: library, onChange: { [weak self] in
            Task { @MainActor in self?.refreshRecordings() }
        })
        hotKey = HotKey(keyCode: HotKey.keyR, modifiers: HotKey.controlOptionCommand) { [weak self] in
            log.info("Hotkey pressed")
            self?.toggleRecording()
        }
        if hotKey == nil { log.error("Couldn't register ⌃⌥⌘R; another app may own it") }
        log.info("OpenRecord started, library: \(self.library.root.path, privacy: .public)")
        refreshDisplays()
        refreshRecordings()
        checkTranscriptionSetup()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }
        Task {
            await recoverInterruptedRecordings()
            await transcriptions.enqueueUnfinished()
        }
    }

    var isRecording: Bool {
        if case .recording = state { true } else { false }
    }

    var elapsed: String {
        guard case .recording(_, let since) = state else { return "" }
        return formatTimestamp(now.timeIntervalSince(since))
    }

    var transcribingCount: Int {
        recent.filter { $0.status == .ready && $0.transcriptError == nil && [.pending, .transcribing].contains($0.transcriptStatus) }.count
    }

    var mcpServerPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/openrecord-mcp").path
    }

    func toggleRecording() {
        switch state {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        case .starting, .stopping: break
        }
    }

    func refreshDisplays() {
        displays = ScreenRecorder.availableDisplays()
        if selectedDisplayID == nil || !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id
        }
    }

    func refreshRecordings() {
        recent = Array(library.recordings().prefix(10))
    }

    func checkTranscriptionSetup() {
        let wasMissing = transcriptionSetupError != nil
        do {
            _ = try WhisperTranscriber.locate()
            transcriptionSetupError = nil
            if wasMissing { Task { await transcriptions.enqueueUnfinished() } }
        } catch {
            transcriptionSetupError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
        privacySettingsURL = nil
    }

    func openPrivacySettings() {
        if let privacySettingsURL { NSWorkspace.shared.open(privacySettingsURL) }
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func open(_ recording: Recording) {
        NSWorkspace.shared.open(library.videoURL(for: recording))
    }

    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([library.videoURL(for: recording)])
    }

    func openLibraryFolder() {
        try? FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(library.root)
    }

    func runTranscriptionSetup() {
        guard let script = Bundle.main.url(forResource: "setup-whisper", withExtension: "sh") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: configuration)
    }

    func retryTranscription(_ recording: Recording) {
        checkTranscriptionSetup()
        Task { await transcriptions.enqueue(recording.id) }
    }

    func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func start() async {
        guard state == .idle, let displayID = selectedDisplayID else { return }
        state = .starting
        clearError()
        defer { refreshRecordings() }

        var recording: Recording
        do {
            recording = try library.createRecording()
        } catch {
            return failedToStart(error)
        }
        do {
            let started = try await recorder.start(display: displayID, to: library.videoURL(for: recording))
            recording.displayName = started.display.name
            recording.width = started.display.pixelWidth
            recording.height = started.display.pixelHeight
            recording.microphone = started.microphone
        } catch {
            try? FileManager.default.removeItem(at: library.folder(for: recording.id))
            return failedToStart(error)
        }
        // Capture is already running, so a failed metadata write must not abort it.
        try? library.save(recording)
        state = .recording(id: recording.id, since: .now)
        log.info("Recording \(recording.id, privacy: .public) on \(recording.displayName ?? "", privacy: .public)")
        startTicker()
    }

    private func failedToStart(_ error: Error) {
        lastError = error.localizedDescription
        privacySettingsURL = switch error as? RecorderError {
        case .screenRecordingDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .microphoneDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        default: nil
        }
        log.error("Couldn't start recording: \(error.localizedDescription, privacy: .public)")
        state = .idle
    }

    private func stop() async {
        guard case .recording(let id, _) = state else { return }
        state = .stopping
        var stopError: Error?
        do {
            try await recorder.stop()
        } catch {
            stopError = error
        }
        await finish(id: id, error: stopError)
    }

    private func recordingEndedUnexpectedly(_ error: Error) {
        guard case .recording(let id, _) = state else { return }
        state = .stopping
        Task { await finish(id: id, error: error) }
    }

    /// Recordings still marked as recording at launch were cut off by a quit or crash.
    private func recoverInterruptedRecordings() async {
        for recording in library.recordings() where recording.status == .recording {
            await finish(id: recording.id, error: RecorderError.interrupted)
        }
    }

    private func finish(id: String, error: Error?) async {
        ticker?.cancel()
        guard var recording = try? library.recording(id: id) else {
            state = .idle
            return
        }
        // A capture error can still leave a playable file behind (e.g. the display was unplugged).
        if let duration = try? await FrameExtractor.duration(of: library.videoURL(for: recording)), duration > 0 {
            recording.status = .ready
            recording.duration = duration
        } else {
            recording.status = .failed
            recording.transcriptStatus = .failed
        }
        recording.error = error?.localizedDescription
        lastError = error?.localizedDescription
        log.info("Recording \(id, privacy: .public) finished: \(recording.status.rawValue, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
        try? library.save(recording)
        state = .idle
        refreshRecordings()
        if recording.status == .ready {
            await transcriptions.enqueue(id)
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
