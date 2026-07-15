# Troubleshooting

## The app opens but no session appears

Open `/hooks` in Codex, review the Codex Status Bar definitions, and trust them. Changed hook files
receive a new trust hash and must be reviewed again. Start a new session after trusting hooks.

## Hooks run twice

Do not enable both the app-installed user hooks and the marketplace plugin hooks. Codex merges hook
sources and runs every match. Remove one installation path.

## MCP servers stay on Starting

Run `codex mcp list --json` and verify that Codex sees the server. Servers requiring OAuth should be
authenticated from Codex. Select **Refresh MCP status** after changing MCP configuration.

The live monitor uses `codex app-server`; an older Codex CLI may not expose `mcpServerStatus/list`.

## A closed session remains temporarily

Codex does not currently expose a documented `SessionEnd` hook. CLI sessions are reaped when their
parent process exits; other stale rows are hidden by the idle timeout and active states have safety caps.

## Build fails

Run `./build.sh` and inspect the first compiler or signing error. A Developer ID certificate is only
required for distributable signed/notarized builds; local builds fall back to ad-hoc signing.
