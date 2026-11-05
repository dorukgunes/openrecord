# Changelog

All notable changes to OpenRecord are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-05

First public version.

### Added

- Menu bar app that records a chosen display plus the microphone into an MP4 with ScreenCaptureKit, started and
  stopped from the menu or with the global hotkey ⌃⌥⌘R.
- On-device transcription with whisper.cpp (`large-v3-turbo`, voice-activity detection, automatic language detection).
  Recordings made before whisper is installed get transcribed once it is.
- `openrecord-mcp`, a read-only stdio MCP server bundled in the app, with `list_recordings`, `get_recording`,
  `get_transcript`, `search_recordings` and `get_frames`.
- Recovery for recordings cut off by a quit or crash, links to System Settings when a permission is missing, and
  Launch at Login.
- A signed and notarized download on GitHub Releases, built by `scripts/release.sh` with checksums.

[Unreleased]: https://github.com/dorukgunes/openrecord/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dorukgunes/openrecord/releases/tag/v0.1.0
