#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");

const root = path.join(os.homedir(), ".codex", "statusbar");
const hooksPath = path.join(os.homedir(), ".codex", "hooks.json");
if (fs.existsSync(hooksPath)) {
  const config = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
  config.hooks = config.hooks || {};
  for (const event of Object.keys(config.hooks)) {
    config.hooks[event] = (config.hooks[event] || []).map((entry) => ({
      ...entry,
      hooks: (entry.hooks || []).filter((hook) => !(hook.command || "").includes(root)),
    })).filter((entry) => entry.hooks.length);
    if (!config.hooks[event].length) delete config.hooks[event];
  }
  fs.writeFileSync(hooksPath, `${JSON.stringify(config, null, 2)}\n`);
}
fs.rmSync(root, { recursive: true, force: true });
console.log("Removed Codex Status Bar hooks and local state.");
