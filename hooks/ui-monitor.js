#!/usr/bin/env node
// Fallback monitor for Codex Desktop, which may not dispatch user lifecycle hooks.
// It reads only local rollout event types/metadata; prompt and response content is never persisted.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const home = os.homedir();
const sessionsRoot = process.env.CODEX_STATUSBAR_SESSIONS_ROOT || path.join(home, ".codex", "sessions");
const statusRoot = path.join(home, ".codex", "statusbar");
const stateDir = path.join(statusRoot, "state.d");
const pidPath = path.join(statusRoot, "ui-monitor.pid");
const logPath = path.join(statusRoot, "ui-monitor.log");
const once = process.argv.includes("--once");
const tracked = new Map();
let shuttingDown = false;

const safeId = (value) => String(value || "unknown").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 96) || "unknown";
const unixTime = (value) => Math.floor((Date.parse(value || "") || Date.now()) / 1000);

function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value));
  fs.renameSync(tmp, file);
}

function rolloutFiles(dir, output = []) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return output; }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) rolloutFiles(full, output);
    else if (entry.isFile() && entry.name.startsWith("rollout-") && entry.name.endsWith(".jsonl")) output.push(full);
  }
  return output;
}

function parseLines(text, skipPartial = false) {
  const lines = text.split("\n");
  if (skipPartial) lines.shift();
  return lines.flatMap((line) => {
    if (!line) return [];
    try { return [JSON.parse(line)]; } catch { return []; }
  });
}

function toolParts(rawName, rawInput) {
  let name = String(rawName || "");
  if (name === "exec" && typeof rawInput === "string") {
    try {
      const input = JSON.parse(rawInput);
      const hit = String(input.code || "").match(/tools\.(mcp__[A-Za-z0-9_-]+__[A-Za-z0-9_-]+|[A-Za-z0-9_]+)/);
      if (hit) name = hit[1];
    } catch {}
  }
  const mcp = name.match(/^mcp__(.+)__(.+)$/);
  if (mcp) return { name, kind: "mcp", server: mcp[1], tool: mcp[2], label: `${mcp[1]} · ${mcp[2]}` };
  const labels = { exec: "Running command", exec_command: "Running command", apply_patch: "Editing", view_image: "Viewing image", web__run: "Browsing web" };
  return { name, kind: "builtin", server: "", tool: name, label: labels[name] || "Using tool" };
}

function blankState(meta) {
  return {
    state: "idle", label: "", tool: "", toolKind: "", mcpServer: "", mcpTool: "",
    activeTools: {}, activeAgents: {}, project: meta.cwd ? path.basename(meta.cwd) : "",
    cwd: meta.cwd || "", sessionId: meta.sessionId || "", turnId: "", model: meta.model || "",
    permissionMode: "", transcript: meta.file || "", entrypoint: "codex-app", term_program: "",
    pid: 0, started: false, startedAt: 0, ts: Math.floor(Date.now() / 1000), lastEvent: "ui-monitor",
  };
}

function applyEvent(record, context) {
  const payload = record.payload || {};
  const ts = unixTime(record.timestamp);
  if (record.type === "session_meta") {
    context.desktop = payload.originator === "Codex Desktop";
    context.meta.sessionId = payload.session_id || payload.id || context.meta.sessionId;
    context.meta.cwd = payload.cwd || context.meta.cwd;
    context.meta.file = context.file;
    return false;
  }
  if (!context.desktop) return false;
  if (!context.state) context.state = blankState(context.meta);
  const state = context.state;
  if (record.type === "turn_context") {
    state.turnId = payload.turn_id || state.turnId;
    state.cwd = payload.cwd || state.cwd;
    state.project = state.cwd ? path.basename(state.cwd) : state.project;
    state.model = payload.model || state.model;
    return false;
  }
  if (record.type === "event_msg" && (payload.type === "task_started" || payload.type === "user_message")) {
    state.state = "thinking"; state.label = "Thinking…"; state.started = true;
    state.startedAt = ts; state.ts = ts; state.lastEvent = payload.type;
    state.activeTools = {}; state.tool = state.toolKind = state.mcpServer = state.mcpTool = "";
    return true;
  }
  if (record.type === "response_item" && payload.type === "custom_tool_call") {
    const tool = toolParts(payload.name, payload.input);
    const key = safeId(payload.call_id || payload.id || `${tool.name}-${ts}`);
    state.activeTools[key] = { name: tool.name, kind: tool.kind, server: tool.server, tool: tool.tool, startedAt: ts };
    state.state = "tool"; state.label = tool.label; state.tool = tool.name; state.toolKind = tool.kind;
    state.mcpServer = tool.server; state.mcpTool = tool.tool; state.started = true; state.ts = ts;
    if (!state.startedAt) state.startedAt = ts;
    return true;
  }
  if (record.type === "response_item" && payload.type === "custom_tool_call_output") {
    state.activeTools = {}; state.state = "thinking"; state.label = "Thinking…";
    state.tool = state.toolKind = state.mcpServer = state.mcpTool = ""; state.ts = ts;
    return true;
  }
  if (record.type === "event_msg" && ["task_complete", "turn_aborted", "task_cancelled"].includes(payload.type)) {
    state.state = "done"; state.label = "Done"; state.startedAt = 0; state.ts = ts;
    state.activeTools = {}; state.activeAgents = {};
    state.tool = state.toolKind = state.mcpServer = state.mcpTool = "";
    state.lastEvent = payload.type;
    return true;
  }
  return false;
}

function processFile(file) {
  let stat;
  try { stat = fs.statSync(file); } catch { return; }
  let context = tracked.get(file);
  let records = [];
  if (!context || stat.size < context.offset) {
    context = { file, offset: 0, desktop: false, meta: { file }, state: null };
    const start = Math.max(0, stat.size - 1024 * 1024);
    const fd = fs.openSync(file, "r");
    const headBuffer = Buffer.alloc(Math.min(stat.size, 131072));
    fs.readSync(fd, headBuffer, 0, headBuffer.length, 0);
    // The head is only for stable session metadata. Replaying an ancient task_started here can
    // produce a multi-day timer when a long current turn began before the 1 MiB tail window.
    for (const record of parseLines(headBuffer.toString("utf8"))) {
      if (record.type === "session_meta") applyEvent(record, context);
    }
    const buffer = Buffer.alloc(stat.size - start);
    fs.readSync(fd, buffer, 0, buffer.length, start); fs.closeSync(fd);
    records = parseLines(buffer.toString("utf8"), start > 0);
  } else if (stat.size > context.offset) {
    const fd = fs.openSync(file, "r");
    const buffer = Buffer.alloc(stat.size - context.offset);
    fs.readSync(fd, buffer, 0, buffer.length, context.offset); fs.closeSync(fd);
    records = parseLines(buffer.toString("utf8"));
  }
  let changed = false;
  for (const record of records) changed = applyEvent(record, context) || changed;
  context.offset = stat.size;
  tracked.set(file, context);
  const active = context.state && ["thinking", "tool", "permission"].includes(context.state.state);
  const recent = context.state && Math.floor(Date.now() / 1000) - context.state.ts < 900;
  if (changed && context.desktop && context.state?.sessionId && (active || recent)) {
    writeAtomic(path.join(stateDir, `${safeId(context.state.sessionId)}.json`), context.state);
  }
}

function scan() {
  for (const file of rolloutFiles(sessionsRoot)) processFile(file);
}

function safeScan() {
  try { scan(); }
  catch (error) {
    const line = `${new Date().toISOString()} ${error?.stack || error}\n`;
    try { fs.appendFileSync(logPath, line); } catch {}
  }
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  cleanupPid();
  process.exit(0);
}

function cleanupPid() {
  try {
    if (Number(fs.readFileSync(pidPath, "utf8").trim()) === process.pid) fs.rmSync(pidPath, { force: true });
  } catch {}
}

function monitorAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); } catch { return false; }
  const result = cp.spawnSync("ps", ["-p", String(pid), "-o", "command="], { encoding: "utf8" });
  return result.status === 0 && String(result.stdout || "").includes("ui-monitor.js");
}

fs.mkdirSync(statusRoot, { recursive: true });
try {
  const existing = Number(fs.readFileSync(pidPath, "utf8").trim());
  if (existing !== process.pid && monitorAlive(existing)) process.exit(0);
} catch {}
fs.writeFileSync(pidPath, String(process.pid));
safeScan();
if (once) shutdown();
// Keep this timer referenced: it is the monitor's primary event loop.
setInterval(safeScan, 500);
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
process.on("exit", cleanupPid);
