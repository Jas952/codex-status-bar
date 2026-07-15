#!/usr/bin/env node
// Monitor MCP startup through Codex App Server and persist only presentation-safe status.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");
const readline = require("readline");

const root = path.join(os.homedir(), ".codex", "statusbar");
const output = path.join(root, "mcp.json");
const pidPath = path.join(root, "mcp-monitor.pid");
function locateCodex() {
  if (process.env.CODEX_BINARY) return process.env.CODEX_BINARY;
  const candidates = [
    "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex",
    path.join(os.homedir(), ".local", "bin", "codex"),
    path.join(os.homedir(), ".npm-global", "bin", "codex"),
  ];
  const direct = candidates.find((candidate) => {
    try { fs.accessSync(candidate, fs.constants.X_OK); return true; } catch { return false; }
  });
  if (direct) return direct;
  try { return cp.execFileSync("/bin/zsh", ["-ilc", "command -v codex"], { encoding: "utf8" }).trim(); }
  catch { return "codex"; }
}
const codex = locateCodex();
const servers = new Map();
let appServer;
let shuttingDown = false;

fs.mkdirSync(root, { recursive: true });
try {
  const oldPid = Number(fs.readFileSync(pidPath, "utf8"));
  if (oldPid > 0) {
    try { process.kill(oldPid, 0); process.exit(0); } catch { fs.rmSync(pidPath, { force: true }); }
  }
} catch {}
try { fs.writeFileSync(pidPath, String(process.pid), { flag: "wx" }); }
catch { process.exit(0); }

function writeState() {
  const safe = [...servers.values()].map((server) => ({
    name: server.name,
    enabled: server.enabled,
    authStatus: server.authStatus,
    disabledReason: server.disabledReason,
    status: server.status,
    toolCount: server.toolCount || 0,
    error: server.error || "",
  }));
  const tmp = `${output}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ servers: safe, ts: Math.floor(Date.now() / 1000) }));
  fs.renameSync(tmp, output);
}

function loadConfigured() {
  try {
    const data = JSON.parse(cp.execFileSync(codex, ["mcp", "list", "--json"], {
      encoding: "utf8", timeout: 15000, maxBuffer: 2 * 1024 * 1024,
      stdio: ["ignore", "pipe", "ignore"],
    }));
    for (const row of Array.isArray(data) ? data : []) {
      const auth = String(row.auth_status || "unsupported");
      servers.set(String(row.name), {
        name: String(row.name), enabled: Boolean(row.enabled), authStatus: auth,
        disabledReason: row.disabled_reason ? String(row.disabled_reason) : "",
        status: !row.enabled ? "disabled" : auth === "not_logged_in" ? "authRequired" : "starting",
        toolCount: 0, error: "",
      });
    }
    writeState();
  } catch {}
}

function send(message) {
  if (appServer?.stdin?.writable) appServer.stdin.write(`${JSON.stringify(message)}\n`);
}

function mergeReady(row) {
  const name = String(row.name || "");
  if (!name) return;
  const prior = servers.get(name) || { name, enabled: true, disabledReason: "", toolCount: 0, error: "" };
  servers.set(name, {
    ...prior,
    enabled: true,
    authStatus: String(row.authStatus || prior.authStatus || "unsupported"),
    status: row.authStatus === "notLoggedIn" ? "authRequired" : "ready",
    toolCount: row.tools && typeof row.tools === "object" ? Object.keys(row.tools).length : prior.toolCount || 0,
  });
}

function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  try { appServer?.kill("SIGTERM"); } catch {}
  try { fs.rmSync(pidPath, { force: true }); } catch {}
  setTimeout(() => process.exit(0), 100).unref();
}

loadConfigured();
try {
  appServer = cp.spawn(codex, ["app-server"], { stdio: ["pipe", "pipe", "ignore"] });
  const lines = readline.createInterface({ input: appServer.stdout });
  lines.on("line", (line) => {
    let message;
    try { message = JSON.parse(line); } catch { return; }
    if (message.id === 1 && message.result) {
      send({ method: "initialized", params: {} });
      send({ method: "mcpServerStatus/list", id: 2, params: { detail: "toolsAndAuthOnly" } });
    } else if (message.id === 2 && message.result) {
      for (const row of message.result.data || []) mergeReady(row);
      writeState();
    } else if (message.method === "mcpServer/startupStatus/updated") {
      const update = message.params || {};
      const name = String(update.name || "");
      if (!name) return;
      const prior = servers.get(name) || { name, enabled: true, authStatus: "unsupported", disabledReason: "", toolCount: 0 };
      const authRequired = update.failureReason === "reauthenticationRequired";
      servers.set(name, {
        ...prior,
        status: authRequired ? "authRequired" : String(update.status || "starting"),
        error: update.error ? String(update.error).slice(0, 240) : "",
      });
      writeState();
    }
  });
  appServer.on("exit", shutdown);
  send({
    method: "initialize", id: 1,
    params: { clientInfo: { name: "codex_status_bar", title: "Codex Status Bar", version: "0.1.1" } },
  });
} catch { shutdown(); }

let misses = 0;
setInterval(() => {
  const running = cp.spawnSync("pgrep", ["-x", "CodexStatusBar"], { stdio: "ignore" }).status === 0;
  misses = running ? 0 : misses + 1;
  if (misses >= 3) shutdown();
}, 10000).unref();

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
process.on("exit", () => { try { fs.rmSync(pidPath, { force: true }); } catch {} });
