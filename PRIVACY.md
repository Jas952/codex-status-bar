# Privacy

Codex Status Bar runs locally and has no analytics or developer-operated server.

It stores only local session status and a redacted MCP inventory under `~/.codex/statusbar/`.
MCP transport configuration, URLs, headers, environment values, credentials, tool arguments,
prompts, command output, and transcript contents are not copied into the status files.

The app makes one direct network request per day to GitHub's public API to check the latest release.
Codex and configured MCP servers have their own network and privacy behavior outside this app.
