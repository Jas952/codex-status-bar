# Changelog

## Unreleased — Documentation

- Add a Codex Desktop demonstration to the README.
- Document chat-title separation, MCP visibility, Codex Cloud motion, and color options.
- Remove inherited Claude-specific contributor guidance and collapse the upstream changelog.

## 0.1.9 — Faithful terminal mark

- Keep the `>_` mark fixed and faithful to the original logo in every state.
- Remove the alert-mark cross-fade and cursor deformation that could resemble a stray vertical line.
- Continue expressing state through cloud geometry and color only.

## 0.1.8 — Original and system white

- Simplify the visible color choices to `Original` and fixed `System White`.
- Keep the terminal prompt legible as negative space in the white cloud.
- Migrate the previous blue and adaptive-system settings to the closest new palette.

## 0.1.7 — Semantic cloud motion

- Replace the cloud's frame sequence with continuously evaluated vector geometry and damped springs.
- Give `thinking`, `tool`, `permission`, and `idle` distinct motion targets with uninterrupted transitions.
- Morph the terminal prompt into an alert mark while the original gradient flows smoothly to amber.
- Stop the animation clock at rest and decouple text refreshes from geometry updates.

## 0.1.6 — Original Codex palette

- Add an `Original` color option with the app icon's blue-to-violet cloud gradient and white terminal prompt.
- Preserve the existing solid `Blue` and adaptive `System` palettes.
- Migrate legacy color preferences without resetting existing users.

## 0.1.5 — Codex Cloud icon system

- Replace the generic arrow/dot states with a menu-bar-native Codex cloud and terminal prompt.
- Animate active work with a restrained lobe-breathing wave and cursor pulse.
- Show permission requests as the same cloud in amber with a negative-space exclamation mark.
- Keep the original arrow animation available as `Terminal Pulse`.

## 0.1.4 — Distinct chat titles

- Resolve Codex Desktop thread names through the official App Server `thread/list` API.
- Show the chat title as the primary session label while retaining branch, project, timer, and APP badge.
- Keep the project and full title available in the row tooltip.

## 0.1.3 — Accurate resumed-turn timer

- Prevent large rollout files from reusing an ancient session-start timestamp after monitor restart.
- Fall back to the first recent tool event when the active turn start is outside the tail window.

## 0.1.2 — Codex Desktop UI monitor

- Add a privacy-limited rollout event monitor for Codex Desktop environments that do not dispatch user hooks.
- Detect real desktop task, tool, MCP, and completion transitions without persisting prompt or response content.
- Start the monitor with the menu bar app and keep it alive for continuous updates.

## 0.1.1 — Codex UI liveness fix

- Keep Codex desktop sessions alive using the desktop app process rather than the short-lived hook runner PID.
- Add a regression test for desktop hook state and clearer empty-state diagnostics.
- Refresh MCP inventory whenever the menu opens.

## 0.1.0 — Codex fork

- Forked the AppKit status bar and per-session aggregation design for Codex.
- Added Codex `SessionStart`, `UserPromptSubmit`, tool, approval, subagent, and stop hooks.
- Added concurrency-safe active tool and subagent tracking.
- Added active MCP server/tool labels.
- Added redacted configured MCP inventory and live App Server health states with tool counts.
- Added a marketplace-ready Codex plugin and user-level app installer.
- Rebranded the app, bundle, release URLs, runtime paths, menu, and build artifacts.
- Added hook reducer tests and a Codex Run action.

The fork starts at `0.1.0`. Earlier releases belong to the inherited Claude Status Bar foundation;
their complete history remains available in the
[upstream changelog](https://github.com/m1ckc3s/claude-status-bar/blob/main/CHANGELOG.md).
