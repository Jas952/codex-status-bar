#!/usr/bin/env node

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const repo = path.resolve(__dirname, "..");
const hook = path.join(repo, "hooks", "update.js");
const home = fs.mkdtempSync(path.join(os.tmpdir(), "codex-status-bar-test-"));
const base = {
  session_id: "session-test",
  turn_id: "turn-1",
  cwd: repo,
  model: "gpt-test",
  permission_mode: "default",
};

function send(event, extra = {}) {
  const result = cp.spawnSync(process.execPath, [hook, event], {
    input: JSON.stringify({ ...base, ...extra }),
    env: { ...process.env, HOME: home, TERM_PROGRAM: "TestTerminal" },
    encoding: "utf8",
  });
  assert.strictEqual(result.status, 0, result.stderr);
  return JSON.parse(fs.readFileSync(path.join(home, ".codex", "statusbar", "state.d", "session-test.json"), "utf8"));
}

let state = send("prompt");
assert.strictEqual(state.state, "thinking");
assert.strictEqual(state.model, "gpt-test");

state = send("pre", { tool_name: "mcp__github__search_issues", tool_use_id: "tool-1" });
assert.strictEqual(state.state, "tool");
assert.strictEqual(state.toolKind, "mcp");
assert.strictEqual(state.mcpServer, "github");
assert.strictEqual(state.mcpTool, "search_issues");

state = send("pre", { tool_name: "Bash", tool_use_id: "tool-2" });
assert.strictEqual(Object.keys(state.activeTools).length, 2);

state = send("post", { tool_name: "Bash", tool_use_id: "tool-2" });
assert.strictEqual(state.state, "tool");
assert.strictEqual(state.mcpServer, "github");

state = send("permission", { tool_name: "Bash" });
assert.strictEqual(state.state, "permission");

state = send("agent-start", { agent_id: "agent-1", agent_type: "reviewer" });
assert.strictEqual(state.activeAgents["agent-1"].type, "reviewer");

state = send("agent-stop", { agent_id: "agent-1", agent_type: "reviewer" });
assert.strictEqual(Object.keys(state.activeAgents).length, 0);

state = send("stop");
assert.strictEqual(state.state, "done");
assert.strictEqual(Object.keys(state.activeTools).length, 0);

fs.rmSync(home, { recursive: true, force: true });
console.log("hooks.test.js: ok");
