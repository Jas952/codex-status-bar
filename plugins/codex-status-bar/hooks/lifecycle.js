#!/usr/bin/env node
// Seed a Codex session and refresh the privacy-safe MCP inventory.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const root = path.join(os.homedir(), ".codex", "statusbar");
const stateDir = path.join(root, "state.d");
const bundleID = "com.jas952.codexstatusbar";
const safeId = (value) => String(value || "unknown").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 96) || "unknown";

function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value));
  fs.renameSync(tmp, file);
}

let raw = "";
process.stdin.on("data", (chunk) => { raw += chunk; });
process.stdin.on("end", () => {
  let input = {};
  try { input = JSON.parse(raw || "{}"); } catch {}
  const id = safeId(input.session_id);
  const cwd = input.cwd || process.cwd();
  writeAtomic(path.join(stateDir, `${id}.json`), {
    state: "idle", label: "", tool: "", toolKind: "", mcpServer: "", mcpTool: "",
    activeTools: {}, activeAgents: {}, project: cwd ? path.basename(cwd) : "", cwd,
    sessionId: input.session_id || id, turnId: input.turn_id || "", model: input.model || "",
    permissionMode: input.permission_mode || "", transcript: input.transcript_path || "",
    entrypoint: process.env.TERM_PROGRAM ? "cli" : "codex-app",
    term_program: process.env.TERM_PROGRAM || "", pid: process.ppid, started: false,
    startedAt: 0, ts: Math.floor(Date.now() / 1000), lastEvent: "SessionStart",
  });
  try {
    cp.spawn(process.execPath, [path.join(__dirname, "mcp-monitor.js")], {
      detached: true, stdio: "ignore",
    }).unref();
  } catch {}
  try { cp.spawn("open", ["-g", "-b", bundleID], { detached: true, stdio: "ignore" }).unref(); } catch {}
  process.exit(0);
});
