import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = path.join(repoRoot, "bin", "ralph");

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    console.error(`Command failed: ${cmd} ${args.join(" ")}`);
    process.exit(result.status ?? 1);
  }
}

const agents = [
  { name: "codex", bin: "codex" },
  { name: "claude", bin: "claude" },
  { name: "droid", bin: "droid" },
  { name: "opencode", bin: "opencode" },
  { name: "copilot", bin: "copilot" },
];
const runnable = [];
const skipped = [];
for (const agent of agents) {
  const check = spawnSync(`command -v ${agent.bin}`, { shell: true, stdio: "ignore" });
  if (check.status === 0) {
    runnable.push(agent.name);
  } else {
    skipped.push(agent.name);
  }
}
if (skipped.length) {
  console.log(`Skipping ping for missing agents: ${skipped.join(", ")}`);
}
for (const agent of runnable) {
  run(process.execPath, [cliPath, "ping", `--agent=${agent}`]);
}

console.log("Agent ping tests passed.");
