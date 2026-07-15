#!/usr/bin/env node
// Reduce Codex hook events into one atomic state file per session.

const fs = require("fs");
const os = require("os");
const path = require("path");

const root = path.join(os.homedir(), ".codex", "statusbar");
const stateDir = path.join(root, "state.d");
const event = process.argv[2] || "";

const TOOL_LABELS = {
  Bash: "Running command", shell: "Running command", apply_patch: "Editing",
  Edit: "Editing", Write: "Writing", Read: "Reading", Grep: "Searching",
  Glob: "Searching", WebFetch: "Browsing web", WebSearch: "Searching web",
  web_search: "Searching web", computer_use: "Using computer",
  browser: "Using browser", request_user_input: "Needs input",
};

const safeId = (value) => String(value || "unknown")
  .replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 96) || "unknown";
const now = () => Math.floor(Date.now() / 1000);
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function readJSON(file, fallback = {}) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return fallback; }
}

function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value));
  fs.renameSync(tmp, file);
}

function withLock(file, fn) {
  const lock = `${file}.lock`;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  for (let i = 0; i < 30; i += 1) {
    try {
      fs.mkdirSync(lock);
      try { return fn(); } finally { fs.rmSync(lock, { recursive: true, force: true }); }
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      sleep(10);
    }
  }
  // A crashed hook may leave a lock. State updates are preferable to a frozen indicator.
  try { fs.rmSync(lock, { recursive: true, force: true }); } catch {}
  return fn();
}

function toolParts(name) {
  const raw = String(name || "");
  const match = raw.match(/^mcp__([^_]+(?:_[^_]+)*)__([^].+)$/);
  if (!match) return { kind: "builtin", server: "", tool: raw };
  return { kind: "mcp", server: match[1], tool: match[2] };
}

function labelFor(name, parts) {
  if (parts.kind === "mcp") return `${parts.server} · ${parts.tool}`;
  return TOOL_LABELS[name] || "Using tool";
}

let raw = "";
process.stdin.on("data", (chunk) => { raw += chunk; });
process.stdin.on("end", () => {
  let input = {};
  try { input = JSON.parse(raw || "{}"); } catch {}

  const sid = safeId(input.session_id);
  const statePath = path.join(stateDir, `${sid}.json`);
  withLock(statePath, () => {
    const previous = readJSON(statePath);
    const ts = now();
    const turnId = input.turn_id || previous.turnId || "";
    const entrypoint = process.env.CODEX_ENTRYPOINT || previous.entrypoint ||
      (process.env.TERM_PROGRAM ? "cli" : "codex-app");
    const state = {
      state: previous.state || "idle",
      label: previous.label || "",
      tool: previous.tool || "",
      toolKind: previous.toolKind || "",
      mcpServer: previous.mcpServer || "",
      mcpTool: previous.mcpTool || "",
      activeTools: previous.activeTools || {},
      activeAgents: previous.activeAgents || {},
      project: input.cwd ? path.basename(input.cwd) : previous.project || "",
      cwd: input.cwd || previous.cwd || "",
      sessionId: input.session_id || previous.sessionId || sid,
      turnId,
      model: input.model || previous.model || "",
      permissionMode: input.permission_mode || previous.permissionMode || "",
      transcript: input.transcript_path || previous.transcript || "",
      entrypoint,
      term_program: process.env.TERM_PROGRAM || previous.term_program || "",
      pid: previous.pid || (entrypoint == "cli" ? process.ppid : 0),
      started: true,
      startedAt: previous.startedAt || 0,
      ts,
      lastEvent: input.hook_event_name || event,
    };

    switch (event) {
      case "prompt":
        state.state = "thinking";
        state.label = "Thinking…";
        state.startedAt = ts;
        state.activeTools = {};
        state.activeAgents = {};
        state.tool = state.toolKind = state.mcpServer = state.mcpTool = "";
        break;
      case "pre": {
        const name = input.tool_name || "";
        const parts = toolParts(name);
        const key = safeId(input.tool_use_id || input.tool_call_id || `${name}-${ts}-${process.pid}`);
        state.activeTools[key] = { name, ...parts, startedAt: ts };
        state.state = "tool";
        state.label = labelFor(name, parts);
        state.tool = name;
        state.toolKind = parts.kind;
        state.mcpServer = parts.server;
        state.mcpTool = parts.tool;
        if (!state.startedAt) state.startedAt = ts;
        break;
      }
      case "post": {
        const name = input.tool_name || "";
        const exact = safeId(input.tool_use_id || input.tool_call_id || "");
        if (exact && state.activeTools[exact]) delete state.activeTools[exact];
        else {
          const hit = Object.keys(state.activeTools).find((key) => state.activeTools[key]?.name === name);
          if (hit) delete state.activeTools[hit];
        }
        const remaining = Object.values(state.activeTools);
        if (remaining.length) {
          const active = remaining[remaining.length - 1];
          state.state = "tool";
          state.label = labelFor(active.name, active);
          state.tool = active.name;
          state.toolKind = active.kind;
          state.mcpServer = active.server;
          state.mcpTool = active.tool;
        } else {
          state.state = "thinking";
          state.label = "Thinking…";
          state.tool = state.toolKind = state.mcpServer = state.mcpTool = "";
        }
        break;
      }
      case "permission":
        state.state = "permission";
        state.label = "Needs approval";
        state.startedAt = 0;
        break;
      case "agent-start": {
        const key = safeId(input.agent_id || `${input.agent_type || "agent"}-${process.pid}`);
        state.activeAgents[key] = { type: input.agent_type || "agent", startedAt: ts };
        state.state = "tool";
        state.label = `Delegating · ${input.agent_type || "agent"}`;
        if (!state.startedAt) state.startedAt = ts;
        break;
      }
      case "agent-stop": {
        const key = safeId(input.agent_id || "");
        if (key) delete state.activeAgents[key];
        state.state = Object.keys(state.activeTools).length ? "tool" : "thinking";
        state.label = state.state === "tool" ? state.label : "Thinking…";
        break;
      }
      case "stop":
        state.state = "done";
        state.label = "Done";
        state.startedAt = 0;
        state.activeTools = {};
        state.activeAgents = {};
        state.tool = state.toolKind = state.mcpServer = state.mcpTool = "";
        break;
      default:
        return;
    }
    writeAtomic(statePath, state);
  });
});
