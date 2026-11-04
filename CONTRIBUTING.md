# Contributing to OpenRecord

Thanks for helping! OpenRecord is deliberately small: record a display while you talk, transcribe locally, and expose
it over MCP. Please open an issue before large changes or new features so we can agree on scope first.

## Setup

You need macOS 15+, Xcode 26.1+ (Swift 6.2) and Homebrew.

```sh
make whisper    # whisper.cpp + models, needed for transcription and its tests
make app        # build/OpenRecord.app
open build/OpenRecord.app
```

Grant Screen Recording and Microphone access on first use. Signing with your own Apple Development or Developer ID
certificate (picked up automatically) keeps those grants across rebuilds.

## Tests

| Command | What runs |
| --- | --- |
| `make test` | Unit tests plus MCP protocol tests over an in-memory transport. The Whisper tests run when `make whisper` has been done, and skip otherwise. |
| `make test-capture` | Also records your real screen for a few seconds. Your terminal needs Screen Recording permission. Add `OPENRECORD_CAPTURE_MIC=1` to cover the microphone too. |
| `make smoke` | Builds the app and drives `openrecord-mcp` over stdio, printing every tool's response. Point it at test data with `OPENRECORD_LIBRARY=...`. |

The tests use real media, not mocks: fixtures generate H.264 video and `say` speech
(`Tests/OpenRecordTestSupport`).

### Checking the whole app end to end

`scripts/menu.swift` drives the running app the way a person would. It needs Accessibility permission for your
terminal.

```sh
open --env OPENRECORD_LIBRARY=/tmp/or-test build/OpenRecord.app
swift scripts/menu.swift hotkey          # start recording (⌃⌥⌘R)
say "The export button on the reports page does nothing."
swift scripts/menu.swift hotkey          # stop
OPENRECORD_LIBRARY=/tmp/or-test python3 scripts/mcp_smoke_test.py
```

`swift scripts/menu.swift list` prints the live menu, and `press "<title>"` clicks an item.

## Code style

- Match the code around you. `.editorconfig` covers whitespace.
- Comments explain *why*, never *what*. Leave out comments that restate the code.
- Logging goes through `os.Logger` with the `io.github.dorukgunes.openrecord` subsystem. Never log transcript text.
- The MCP server stays read-only and offline. Tool inputs are untrusted, so validate ids and clamp sizes.

## Pull requests

- Keep them focused. Describe what changed and why in a sentence or two.
- Add or update tests for behavior changes.
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.

## Releasing (maintainers)

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. The MCP server reads its version
   from there.
2. Move the **Unreleased** notes in `CHANGELOG.md` under the new version.
3. One time only, store notarization credentials:
   `xcrun notarytool store-credentials openrecord-notary --apple-id <id> --team-id <team>`
4. `NOTARY_PROFILE=openrecord-notary make release`. This writes a signed, notarized and stapled zip plus
   `SHA256SUMS.txt` to `dist/`.
5. `git tag vX.Y.Z && git push --tags && gh release create vX.Y.Z dist/* --notes-from-tag`

If you change `docs/assets/logo.svg`, regenerate the app icon with `swift scripts/make-icon.swift`.
