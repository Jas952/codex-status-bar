#!/usr/bin/env node

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const repo = path.resolve(__dirname, "..");
const monitor = path.join(repo, "hooks", "ui-monitor.js");
const home = fs.mkdtempSync(path.join(os.tmpdir(), "codex-status-bar-ui-test-"));
const sessions = path.join(home, "sessions", "2026", "07", "16");
const rollout = path.join(sessions, "rollout-test.jsonl");
fs.mkdirSync(sessions, { recursive: true });
fs.mkdirSync(path.join(home, ".codex", "statusbar"), { recursive: true });
fs.writeFileSync(path.join(home, ".codex", "statusbar", "threads.json"), JSON.stringify({ threads: [
  { id: "desktop-ui-test", name: "Refactor status menu" },
  { id: "large-desktop-test", name: "Large rollout task" },
] }));

const records = [
  { timestamp: new Date().toISOString(), type: "session_meta", payload: {
    session_id: "desktop-ui-test", originator: "Codex Desktop", cwd: repo,
  } },
  { timestamp: new Date().toISOString(), type: "event_msg", payload: { type: "task_started" } },
  { timestamp: new Date().toISOString(), type: "turn_context", payload: {
    turn_id: "turn-ui-test", cwd: repo, model: "gpt-test",
  } },
  { timestamp: new Date().toISOString(), type: "event_msg", payload: {
    type: "user_message", message: "private prompt that must not be persisted",
  } },
  { timestamp: new Date().toISOString(), type: "response_item", payload: {
    type: "custom_tool_call", id: "tool-ui-test", name: "exec",
    input: JSON.stringify({ code: "await tools.mcp__github__search_issues({})" }),
  } },
];
fs.writeFileSync(rollout, records.map(JSON.stringify).join("\n") + "\n");

function run() {
  const result = cp.spawnSync(process.execPath, [monitor, "--once"], {
    env: { ...process.env, HOME: home, CODEX_STATUSBAR_SESSIONS_ROOT: path.join(home, "sessions") },
    encoding: "utf8",
  });
  assert.strictEqual(result.status, 0, result.stderr);
  return JSON.parse(fs.readFileSync(path.join(home, ".codex", "statusbar", "state.d", "desktop-ui-test.json"), "utf8"));
}

let state = run();
assert.strictEqual(state.state, "tool");
assert.strictEqual(state.entrypoint, "codex-app");
assert.strictEqual(state.pid, 0);
assert.strictEqual(state.mcpServer, "github");
assert.strictEqual(state.mcpTool, "search_issues");
assert.strictEqual(state.chatTitle, "Refactor status menu");
assert.ok(!JSON.stringify(state).includes("private prompt"));

fs.appendFileSync(rollout, [
  { timestamp: new Date().toISOString(), type: "response_item", payload: {
    type: "custom_tool_call_output", call_id: "tool-ui-test",
  } },
  { timestamp: new Date().toISOString(), type: "event_msg", payload: { type: "task_complete" } },
].map(JSON.stringify).join("\n") + "\n");
state = run();
assert.strictEqual(state.state, "done");
assert.deepStrictEqual(state.activeTools, {});

// A large active rollout may have its current task_started outside the 1 MiB tail. The monitor
// must not reuse an ancient task_started from the file head and display a multi-day timer.
const largeRollout = path.join(sessions, "rollout-large-test.jsonl");
const recentToolTimestamp = new Date().toISOString();
fs.writeFileSync(largeRollout, [
  JSON.stringify({ timestamp: "2020-01-01T00:00:00Z", type: "session_meta", payload: {
    session_id: "large-desktop-test", originator: "Codex Desktop", cwd: repo,
  } }),
  JSON.stringify({ timestamp: "2020-01-01T00:00:01Z", type: "event_msg", payload: { type: "task_started" } }),
  JSON.stringify({ timestamp: "2020-01-01T00:00:02Z", type: "response_item", payload: {
    type: "reasoning", encrypted_content: "x".repeat(1_100_000),
  } }),
  JSON.stringify({ timestamp: recentToolTimestamp, type: "response_item", payload: {
    type: "custom_tool_call", id: "large-tool", name: "exec",
    input: JSON.stringify({ code: "await tools.exec_command({})" }),
  } }),
].join("\n") + "\n");
run();
const largeState = JSON.parse(fs.readFileSync(
  path.join(home, ".codex", "statusbar", "state.d", "large-desktop-test.json"), "utf8",
));
assert.strictEqual(largeState.state, "tool");
assert.strictEqual(largeState.chatTitle, "Large rollout task");
assert.ok(largeState.startedAt >= Math.floor(Date.parse(recentToolTimestamp) / 1000));

fs.rmSync(home, { recursive: true, force: true });
console.log("ui-monitor.test.js: ok");
