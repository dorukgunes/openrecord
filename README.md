# OpenRecord

A local, open-source take on [Supercut](https://supercut.ai) for macOS: record your screen while you talk, get an
on-device transcript, and let AI agents read your recordings over [MCP](https://modelcontextprotocol.io).
Nothing leaves your Mac.

- **Menu bar recorder**: records a whole display plus your microphone into one MP4. Start and stop from the menu bar
  or with **⌃⌥⌘R** from anywhere.
- **Local transcription**: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (large-v3-turbo, Metal-accelerated)
  with voice-activity detection. Language is auto-detected and segments are timestamped.
- **MCP server** (`openrecord-mcp`): read-only tools for listing recordings, reading transcripts, searching what you said,
  and pulling screenshots at any timestamp.

## Requirements

- macOS 15 (Sequoia) or later, Apple silicon recommended
- Xcode 16+ / Swift 6.2 toolchain
- [Homebrew](https://brew.sh) (for whisper.cpp)

## Install

```sh
git clone <this repo> openrecord && cd openrecord
make whisper        # brew install whisper-cpp + download models (~575 MB) to ~/Library/Application Support/OpenRecord/models
make app            # builds build/OpenRecord.app
open build/OpenRecord.app
```

`make install` copies the app to `/Applications`.

On the first recording macOS asks for **Microphone** and **Screen Recording** access. Screen Recording is granted in
System Settings › Privacy & Security › Screen & System Audio Recording, and macOS may ask you to reopen OpenRecord.

> macOS ties these permissions to the app's code signature. `make app` signs with your Apple Development / Developer ID
> certificate when one is installed, so permissions survive rebuilds. Override with `CODESIGN_IDENTITY=...`. Without a
> certificate it falls back to an ad-hoc signature, and you'll need to re-grant access after each rebuild.

## Recording

Click the ◉ menu bar icon › **Start Recording**, or press **⌃⌥⌘R**. Press it again to stop. While recording, the menu
bar shows the elapsed time. Pick which display to record under **Display**.

When you stop, OpenRecord finalizes the video and transcribes it in the background. Each recording is a folder in
`~/Movies/OpenRecord`:

```
~/Movies/OpenRecord/2026-11-04_22-09-48/
├── recording.mp4      # H.264 (HEVC above 4096 px), display + microphone
├── meta.json          # title, duration, resolution, mic, transcript status
└── transcript.json    # [{start, end, text}] in seconds, plus detected language
```

## Connect an agent over MCP

The server ships inside the app bundle. The menu's **Connect via MCP** item copies the right command for you.

**Claude Code**

```sh
claude mcp add --scope user openrecord -- "/Applications/OpenRecord.app/Contents/MacOS/openrecord-mcp"
```

**Claude Desktop, Cursor, and other JSON-configured clients**

```json
{ "mcpServers": { "openrecord": { "command": "/Applications/OpenRecord.app/Contents/MacOS/openrecord-mcp" } } }
```

| Tool | What it does |
| --- | --- |
| `list_recordings` | Newest first, with duration, transcript status and a preview of what was said |
| `get_recording` | Metadata and the local video path for one recording |
| `get_transcript` | `[m:ss] text` lines, optionally limited by `start_seconds` / `end_seconds` |
| `search_recordings` | Find moments where you said something across all recordings (case- and accent-insensitive) |
| `get_frames` | JPEG screenshots at given `timestamps`, or `count` evenly spaced ones |

Every tool takes `id: "latest"` for the most recent recording. Try asking your agent: *"Watch my latest OpenRecord
recording and file a bug for what I described"*.

All tools are read-only. Transcripts and frames go to whichever model your MCP client uses, so that is the only point
where recording content leaves your machine.

## Configuration

| Environment variable | Default |
| --- | --- |
| `OPENRECORD_LIBRARY` | `~/Movies/OpenRecord`, read by both the app and the MCP server |
| `OPENRECORD_WHISPER_CLI` | `whisper-cli` from Homebrew or `PATH` |
| `OPENRECORD_WHISPER_MODEL` | `~/Library/Application Support/OpenRecord/models/ggml-large-v3-turbo-q5_0.bin` |

## Development

```sh
swift build
make test           # unit + MCP protocol tests; transcription tests run when whisper is set up
make test-capture   # also records the real screen (needs Screen Recording permission for your terminal)
make smoke          # drives build/OpenRecord.app's openrecord-mcp over stdio and prints every tool's output
```

`scripts/menu.swift` drives the running app's menu and hotkey through the Accessibility API, for end-to-end checks:
`swift scripts/menu.swift list | press "Start Recording" | hotkey`.

App logs: `log stream --info --predicate 'subsystem == "io.github.dorukgunes.openrecord"'`.

| Target | Role |
| --- | --- |
| `OpenRecordCore` | Recording library on disk, ScreenCaptureKit recorder, whisper.cpp transcription, frame extraction, search |
| `OpenRecord` | SwiftUI menu bar app |
| `OpenRecordMCPServer` / `openrecord-mcp` | MCP tools over stdio ([swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)) |

## License

MIT
