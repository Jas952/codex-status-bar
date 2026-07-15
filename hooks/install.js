#!/usr/bin/env node
// Install user-level Codex hooks without replacing unrelated hook definitions.

const fs = require("fs");
const os = require("os");
const path = require("path");

const home = os.homedir();
const root = path.join(home, ".codex", "statusbar");
const hooksPath = path.join(home, ".codex", "hooks.json");
const marker = root;
const node = process.execPath;
const updateDest = path.join(root, "update.js");
const lifecycleDest = path.join(root, "lifecycle.js");
const inventoryDest = path.join(root, "mcp-inventory.js");
const monitorDest = path.join(root, "mcp-monitor.js");

fs.mkdirSync(root, { recursive: true });
fs.copyFileSync(path.join(__dirname, "update.js"), updateDest);
fs.copyFileSync(path.join(__dirname, "lifecycle.js"), lifecycleDest);
fs.copyFileSync(path.join(__dirname, "mcp-inventory.js"), inventoryDest);
fs.copyFileSync(path.join(__dirname, "mcp-monitor.js"), monitorDest);

let config = { hooks: {} };
if (fs.existsSync(hooksPath)) {
  config = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
  config.hooks = config.hooks || {};
  const backup = `${hooksPath}.bak-codex-status-bar`;
  if (!fs.existsSync(backup)) fs.copyFileSync(hooksPath, backup);
}

function stripOurs(entries) {
  return (entries || []).map((entry) => ({
    ...entry,
    hooks: (entry.hooks || []).filter((hook) => !(hook.command || "").includes(marker)),
  })).filter((entry) => entry.hooks.length);
}

function add(event, script, arg, matcher) {
  config.hooks[event] = stripOurs(config.hooks[event]);
  const entry = {
    hooks: [{
      type: "command",
      command: `${JSON.stringify(node)} ${JSON.stringify(script)} ${arg}`,
      timeout: 10,
    }],
  };
  if (matcher) entry.matcher = matcher;
  config.hooks[event].push(entry);
}

add("SessionStart", lifecycleDest, "start", "startup|resume|clear");
add("UserPromptSubmit", updateDest, "prompt");
add("PreToolUse", updateDest, "pre", "*");
add("PostToolUse", updateDest, "post", "*");
add("PermissionRequest", updateDest, "permission", "*");
add("SubagentStart", updateDest, "agent-start", "*");
add("SubagentStop", updateDest, "agent-stop", "*");
add("Stop", updateDest, "stop");

fs.mkdirSync(path.dirname(hooksPath), { recursive: true });
fs.writeFileSync(hooksPath, `${JSON.stringify(config, null, 2)}\n`);
console.log(`Installed Codex Status Bar hooks into ${hooksPath}`);
console.log("Open /hooks in Codex and trust the new definitions before testing.");
