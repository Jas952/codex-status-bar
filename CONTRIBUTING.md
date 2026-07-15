# Contributing

Codex Status Bar is intentionally local and lightweight. Changes should preserve the native menu
bar experience, atomic state files, privacy boundary, and compatibility with current Codex hooks.

## Validate a change

```bash
node tests/hooks.test.js
python3 /path/to/plugin-creator/scripts/validate_plugin.py plugins/codex-status-bar
./script/build_and_run.sh --verify
```

Do not commit credentials, raw MCP configuration, tool arguments, prompts, transcript content, or
generated state from `~/.codex/statusbar/`.

The app targets macOS 12+ and builds as a universal arm64/x86_64 binary. Signing and notarization
use the maintainer's Developer ID; source builds fall back to ad-hoc signing.

When changing hooks, test prompt, parallel tool, MCP tool, permission, subagent, and stop transitions.
When changing the plugin bundle, run the plugin validator and remember that users must review a new
hook hash through `/hooks`.
