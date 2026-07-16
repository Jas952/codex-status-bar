#!/usr/bin/env node
// Refresh a deliberately redacted MCP inventory. Never persist transports, headers, or env values.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const root = path.join(os.homedir(), ".codex", "statusbar");
const output = path.join(root, "mcp.json");
let codex = process.env.CODEX_BINARY || "";
if (!codex) {
  const candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex",
    path.join(os.homedir(), ".local", "bin", "codex")];
  codex = candidates.find((candidate) => {
    try { fs.accessSync(candidate, fs.constants.X_OK); return true; } catch { return false; }
  }) || "codex";
}

try {
  const stdout = cp.execFileSync(codex, ["mcp", "list", "--json"], {
    timeout: 15000,
    maxBuffer: 2 * 1024 * 1024,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  const entries = JSON.parse(stdout);
  const servers = (Array.isArray(entries) ? entries : []).map((server) => ({
    name: String(server.name || ""),
    enabled: Boolean(server.enabled),
    authStatus: String(server.auth_status || "unsupported"),
    disabledReason: server.disabled_reason ? String(server.disabled_reason) : "",
    status: server.enabled ? (server.auth_status === "not_logged_in" ? "authRequired" : "configured") : "disabled",
  })).filter((server) => server.name);
  fs.mkdirSync(root, { recursive: true });
  const tmp = `${output}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ servers, ts: Math.floor(Date.now() / 1000) }));
  fs.renameSync(tmp, output);
} catch {}
