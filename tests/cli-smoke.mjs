import { spawnSync } from "node:child_process";
import { mkdtempSync, existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    console.error(`Command failed: ${cmd} ${args.join(" ")}`);
    process.exit(result.status ?? 1);
  }
}

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = path.join(repoRoot, "bin", "ralph");

function assertCodexCommandPinned(file) {
  const contents = readFileSync(file, "utf-8");
  if (!contents.includes("-m gpt-5.5")) {
    console.error(`${file} missing gpt-5.5 Codex pin.`);
    process.exit(1);
  }
  if (!/model_reasoning_effort=\\?"xhigh\\?"/.test(contents)) {
    console.error(`${file} missing xhigh Codex reasoning pin.`);
    process.exit(1);
  }
  if (!/service_tier=\\?"priority\\?"/.test(contents)) {
    console.error(`${file} missing priority Codex service tier pin.`);
    process.exit(1);
  }
  if (/service_tier=\\?"fast\\?"/.test(contents)) {
    console.error(`${file} uses invalid fast Codex service tier.`);
    process.exit(1);
  }
}

assertCodexCommandPinned(cliPath);
assertCodexCommandPinned(path.join(repoRoot, ".agents", "ralph", "agents.sh"));
assertCodexCommandPinned(path.join(repoRoot, ".agents", "ralph", "loop.sh"));

run(process.execPath, [cliPath, "--help"]);

const projectRoot = mkdtempSync(path.join(tmpdir(), "ralph-cli-"));
try {
  const outPath = path.join(projectRoot, "prd.json");
  run(process.execPath, [cliPath, "prd", "Smoke test PRD", "--out", outPath], {
    cwd: projectRoot,
    env: { ...process.env, RALPH_DRY_RUN: "1" },
  });

  if (!existsSync(outPath)) {
    console.error("PRD smoke test failed: output not created.");
    process.exit(1);
  }

  run(process.execPath, [cliPath, "overview", "--prd", outPath], {
    cwd: projectRoot,
    env: { ...process.env },
  });

  const overviewPath = outPath.replace(/\.json$/i, ".overview.md");
  if (!existsSync(overviewPath)) {
    console.error("Overview smoke test failed: output not created.");
    process.exit(1);
  }
} finally {
  rmSync(projectRoot, { recursive: true, force: true });
}

console.log("CLI smoke test passed.");
