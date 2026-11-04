import OpenRecordCore
import SwiftUI

@main
struct OpenRecordApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            if model.isRecording {
                Label(model.elapsed, systemImage: "record.circle.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "record.circle")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        recordButton
        if !model.displays.isEmpty {
            Picker("Display", selection: Binding(get: { model.selectedDisplayID }, set: { model.selectedDisplayID = $0 })) {
                ForEach(model.displays) { display in
                    Text(verbatim: "\(display.name) (\(display.pixelWidth)×\(display.pixelHeight))")
                        .tag(Optional(display.id))
                }
            }
            .disabled(model.state != .idle)
        }
        if let error = model.lastError {
            Button("⚠︎ \(error)") { model.clearError() }
        }

        Divider()

        Menu("Recent Recordings") {
            if model.recent.isEmpty {
                Text("No recordings yet")
            }
            ForEach(model.recent) { recording in
                Menu("\(recording.title) — \(subtitle(for: recording))") {
                    Button("Play") { model.open(recording) }
                    Button("Show in Finder") { model.reveal(recording) }
                    Button("Copy ID") { model.copyToClipboard(recording.id) }
                    if recording.status == .ready, [.failed, .pending].contains(recording.transcriptStatus) {
                        Button("Transcribe Again") { model.retryTranscription(recording) }
                    }
                }
            }
        }
        Button("Open Recordings Folder") { model.openLibraryFolder() }

        Divider()

        if model.transcribingCount > 0 {
            Text("Transcribing \(model.transcribingCount) recording\(model.transcribingCount == 1 ? "" : "s")…")
        }
        if let setupError = model.transcriptionSetupError {
            Text("Transcription is off: \(setupError)")
            Button("Set Up Transcription…") { model.runTranscriptionSetup() }
            Button("Check Again") { model.checkTranscriptionSetup() }
        }
        Menu("Connect via MCP") {
            Button("Copy Claude Code Command") {
                model.copyToClipboard("claude mcp add --scope user openrecord -- \"\(model.mcpServerPath)\"")
            }
            Button("Copy JSON Config") {
                model.copyToClipboard("""
                    {"mcpServers": {"openrecord": {"command": "\(model.mcpServerPath)"}}}
                    """)
            }
        }

        Divider()

        Button("Quit OpenRecord") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var recordButton: some View {
        switch model.state {
        case .idle:
            Button("Start Recording") { model.toggleRecording() }
                .keyboardShortcut("r", modifiers: [.control, .option, .command])
        case .starting:
            Text("Starting…")
        case .recording:
            Button("Stop Recording (\(model.elapsed))") { model.toggleRecording() }
                .keyboardShortcut("r", modifiers: [.control, .option, .command])
        case .stopping:
            Text("Saving…")
        }
    }

    private func subtitle(for recording: Recording) -> String {
        let duration = recording.duration.map(formatTimestamp) ?? "—"
        let status: String = switch (recording.status, recording.transcriptStatus) {
        case (.recording, _): "recording"
        case (.failed, _): "failed"
        case (_, .done): "transcribed"
        case (_, .pending), (_, .transcribing): "transcribing"
        case (_, .noAudio): "no audio"
        case (_, .failed): "transcription failed"
        }
        return "\(duration) · \(status)"
    }
}
