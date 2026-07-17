# Codex Status Bar

A native macOS menu bar companion for Codex Desktop and Codex CLI. See every active task,
what Codex is doing, how long the turn has been running, and whether it needs you—without
bringing the app back to the foreground.

<p align="center">
  <img src="assets/codex-status-bar-demo.webp" alt="Codex Status Bar showing a live Codex Desktop task and MCP server health" width="600">
</p>

The recording above shows a real Codex Desktop task, its chat title, live timer, current action,
and the MCP servers available to that task.

This project is a fork of [m1ckc3s/claude-status-bar](https://github.com/m1ckc3s/claude-status-bar).
The native AppKit menu and atomic per-session state foundation are retained under the MIT license;
the integration, branding, state reducer, desktop monitor, plugin packaging, and MCP monitor have
been rebuilt for Codex.

## What it shows

- **Thinking / working** — an animated Codex Cloud and optional elapsed timer.
- **Using a tool** — Reading, Editing, Running command, Browsing web, and other live labels.
- **Using MCP** — the active server and tool, for example `github · search_issues`.
- **Needs approval** — an amber cloud when Codex is waiting for permission.
- **Subagents** — the number and state of active delegated agents.
- **Done / idle** — the cloud returns smoothly to its resting shape.

Every active task keeps its own row. Codex Status Bar resolves the real chat title and also shows
the Git branch, project, surface (`APP` or `CLI`), model, active MCP tool, and subagent count.
When several tasks are active, approval takes priority over working, and working takes priority
over idle in the menu bar.

## Codex Cloud

The default icon is a vector recreation of the Codex cloud rather than a sequence of image frames.
Its geometry moves continuously between idle, thinking, tool, and permission states with damped
spring motion, while the `>_` terminal mark remains faithful to the original logo.

The menu includes:

- **Animation:** `Codex Cloud` or the compact `Terminal Pulse` alternative;
- **Color:** the original blue-violet gradient or fixed `System White`;
- **Show timer:** display or hide the elapsed turn time;
- **Thinking words:** rotate lightweight working labels in the menu bar.

## MCP servers

The dropdown lists every configured MCP server and reports:

- starting, ready, failed, cancelled, disabled, or authentication required;
- the number of tools advertised by each ready server;
- the MCP server and tool currently used by a Codex turn.

Live health comes from a local `codex app-server` sidecar. The persisted inventory is deliberately
redacted: transports, URLs, headers, environment values, credentials, tool arguments, prompts, and
responses are never written to the status files.

## Codex Desktop and CLI

Codex Desktop tasks are supported directly. You do not need to run your work in a terminal.
After the first installation, restart Codex and create a new task so the desktop app loads the
status hooks. A task that was already open before installation cannot replay earlier hook events.

The standalone Codex CLI is optional for task tracking. It is currently used by the live MCP health
sidecar (`codex app-server`), so without a `codex` executable the menu still shows desktop task state
but cannot probe live MCP server health.

When Codex Desktop does not dispatch user hooks, the app starts a privacy-limited local monitor. It
reads only rollout event types and session metadata needed for status transitions; prompt and response
content is not copied into the status files.

## Requirements

- macOS 12 or newer;
- Codex Desktop or Codex CLI with stable hooks support (tested with `codex-cli 0.144.2`);
- Node.js;
- the Swift toolchain only when building from source.

## Install and run

There is not yet a published binary release for this fork. Build, install, and launch the app with:

```bash
./script/build_and_run.sh --verify
```

The universal app bundle is written to `build/CodexStatusBar.app`. To create a DMG:

```bash
./build.sh --dmg
```

Without a matching Developer ID certificate, the script creates an ad-hoc signed development build.

On first launch, the app merges its user-level hooks into `~/.codex/hooks.json` and saves a one-time
backup at `~/.codex/hooks.json.bak-codex-status-bar`. Review and trust the new definitions if Codex
asks, restart Codex, and begin a new task. In the CLI, `/hooks` shows the same definitions and trust
state.

## Install as a Codex plugin

The repository also contains a marketplace-ready Codex plugin:

```bash
codex plugin marketplace add Jas952/codex-status-bar
codex plugin add codex-status-bar@codex-status-bar
```

The plugin installs the hooks, not the macOS app bundle. Install or build `CodexStatusBar.app` once,
then use either the app-managed hooks or the plugin hooks—not both. Codex runs all matching hook
sources concurrently, so enabling both produces duplicate updates.

## State and privacy

Runtime files live under `~/.codex/statusbar/`:

```text
state.d/<session-id>.json   per-task state
mcp.json                    redacted MCP status
mcp-monitor.pid             local sidecar liveness
```

The app has no analytics or developer-operated server. Its only direct network request is the
once-a-day GitHub release check. See [PRIVACY.md](PRIVACY.md) for the complete boundary.

## Troubleshooting

If the app is open but no task appears, hooks run twice, MCP servers remain on `Starting`, or a closed
task stays visible, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Uninstall

```bash
node "/Applications/CodexStatusBar.app/Contents/Resources/uninstall.js"
```

Then remove the app. If you installed the plugin too, remove or disable it separately.

## Development

```bash
node tests/hooks.test.js
node tests/ui-monitor.test.js
python3 /path/to/plugin-creator/scripts/validate_plugin.py plugins/codex-status-bar
./build.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change.

## Attribution and license

MIT licensed. See [LICENSE](LICENSE) and [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md). This is an
unofficial community project and is not affiliated with or endorsed by OpenAI.
