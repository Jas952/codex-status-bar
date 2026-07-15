# Codex Status Bar

A native macOS menu bar companion for local Codex work. It shows live turns, tools, approvals,
subagents, Git branches, models, and MCP health without opening a dashboard.

This project is a fork of [m1ckc3s/claude-status-bar](https://github.com/m1ckc3s/claude-status-bar).
The original AppKit menu and atomic per-session state design are retained under the MIT license;
the integration, branding, state reducer, plugin packaging, and MCP monitor have been adapted for Codex.

## Statuses

- **Thinking / working** — animated terminal pulse and optional elapsed timer.
- **Using a tool** — Reading, Editing, Running command, Browsing, and other tool labels.
- **Using MCP** — active server and tool, for example `github · search_issues`.
- **Needs approval** — amber indicator when Codex is waiting for permission.
- **Subagents** — active delegated agent count and state.
- **Done / idle** — resting terminal glyph.

Multiple local sessions are aggregated. Approval takes priority over working, which takes priority
over idle. The dropdown keeps each session separate and includes its project, branch, surface,
model, active MCP tool, and subagent count.

## MCP panel

The menu lists configured MCP servers and reports:

- starting, ready, failed, cancelled, disabled, or authentication required;
- the number of tools advertised by each ready server;
- the MCP server/tool currently used by a Codex turn.

Live health comes from a local `codex app-server` sidecar. The persisted inventory is deliberately
redacted: it never stores transports, URLs, headers, environment values, credentials, or tool arguments.

## Codex desktop app and CLI

Codex desktop tasks are supported directly; you do not need to work in a terminal. Hooks are loaded
when a task starts, so after the first Codex Status Bar installation restart Codex and create a new
task. A task that was already open before installation cannot replay earlier hook events.

The standalone Codex CLI is optional for session tracking. It is currently used by the MCP health
sidecar (`codex app-server`), so without a `codex` executable the app still shows desktop task state
but cannot probe live MCP server health.

## Requirements

- macOS 12 or newer;
- Codex desktop app or Codex CLI with stable hooks support (tested with `codex-cli 0.144.2`);
- Node.js;
- Swift toolchain for source builds.

## Build and run

```bash
./script/build_and_run.sh --verify
```

The universal app bundle is written to `build/CodexStatusBar.app`. To build a DMG:

```bash
./build.sh --dmg
```

Without a matching Developer ID certificate, the script creates an ad-hoc signed development build.

On first launch the app merges its user-level hooks into `~/.codex/hooks.json` and saves a one-time
backup at `~/.codex/hooks.json.bak-codex-status-bar`. Review/trust the new hook definitions when Codex
asks. Then restart Codex and begin a new task so the desktop app loads them. In the CLI, `/hooks`
shows the same definitions and trust state.

## Install as a Codex plugin

The repository also contains a marketplace-ready plugin:

```bash
codex plugin marketplace add Jas952/codex-status-bar
codex plugin add codex-status-bar@codex-status-bar
```

The plugin installs hooks, not the macOS app bundle. Install or build `CodexStatusBar.app` once,
then use either the app-managed hooks or the plugin hooks, not both. Codex runs all matching hook
sources concurrently, so enabling both produces duplicate updates.

## State and privacy

Runtime files live under `~/.codex/statusbar/`:

```text
state.d/<session-id>.json   per-session state
mcp.json                    redacted MCP status
mcp-monitor.pid             local sidecar liveness
```

The only network request made directly by the app is the once-a-day GitHub release check. Codex
and configured MCP servers retain their own network and privacy behavior.

## Uninstall

```bash
node "/Applications/CodexStatusBar.app/Contents/Resources/uninstall.js"
```

Then remove the app. If installed through the plugin marketplace, remove or disable that plugin too.

## Development checks

```bash
node tests/hooks.test.js
python3 /path/to/plugin-creator/scripts/validate_plugin.py plugins/codex-status-bar
./build.sh
```

## Attribution and license

MIT licensed. See [LICENSE](LICENSE) and [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md). This is an
unofficial community project and is not affiliated with or endorsed by OpenAI.
