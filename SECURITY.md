# Security policy

OpenRecord records your screen and voice, and its MCP server hands that content to AI agents, so security reports
matter a lot here.

## Reporting a vulnerability

**Please don't open a public issue.** Report privately through
[GitHub's private vulnerability reporting](https://github.com/dorukgunes/openrecord/security/advisories/new).

Please include the version or commit, your macOS version, steps to reproduce, and the impact you expect. You'll get an
acknowledgement within 7 days. Fixes ship in the next release, and with your permission you'll be credited in the
advisory.

## Supported versions

Only the latest release and `main` get security fixes.

## In scope

- The MCP server reading or exposing files outside the recordings folder, or accepting input that escapes validation
- The app or server making network requests, or leaking recording content anywhere other than the requesting MCP client
- Recording without a visible indication, or recording more than the chosen display and microphone
- Code-signing, entitlement or permission-handling issues

## Out of scope

- Content an MCP client sends to its own model provider. That's the client's job, as described in the README.
- Prompt injection that lives inside your own recordings, beyond the mitigations the README documents. Reports that
  improve those mitigations are still welcome.
