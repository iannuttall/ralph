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

const buildPrompt = readFileSync(path.join(repoRoot, ".agents", "ralph", "PROMPT_build.txt"), "utf-8");
if (!buildPrompt.includes("$use-gpt55-subagents")) {
  console.error("Build prompt missing use-gpt55-subagents instruction.");
  process.exit(1);
}
if (!buildPrompt.includes("<promise>BLOCKED</promise>")) {
  console.error("Build prompt missing blocked promise instruction.");
  process.exit(1);
}
if (!buildPrompt.includes("OPEN or MERGED")) {
  console.error("Build prompt missing PR open/merged acceptance guidance.");
  process.exit(1);
}
const cliContents = readFileSync(cliPath, "utf-8");

const reviewPromptPath = path.join(repoRoot, ".agents", "ralph", "PROMPT_review.txt");
const deployFixPromptPath = path.join(repoRoot, ".agents", "ralph", "PROMPT_deploy_fix.txt");
const reviewPrompt = readFileSync(reviewPromptPath, "utf-8");
const deployFixPrompt = readFileSync(deployFixPromptPath, "utf-8");

for (const [label, contents] of [
  ["review prompt", reviewPrompt],
  ["deploy fix prompt", deployFixPrompt],
]) {
  if (!contents.includes("$use-gpt55-subagents")) {
    console.error(`${label} missing use-gpt55-subagents instruction.`);
    process.exit(1);
  }
}

if (!reviewPrompt.includes("$superpowers:requesting-code-review")) {
  console.error("Review prompt missing requesting-code-review instruction.");
  process.exit(1);
}
if (!reviewPrompt.includes("$superpowers:receiving-code-review")) {
  console.error("Review prompt missing receiving-code-review instruction.");
  process.exit(1);
}
if (!reviewPrompt.includes("<review>MERGEABLE</review>")) {
  console.error("Review prompt missing mergeable review signal.");
  process.exit(1);
}
if (!deployFixPrompt.includes("<deploy-fix>COMPLETE</deploy-fix>")) {
  console.error("Deploy fix prompt missing completion signal.");
  process.exit(1);
}
if (!cliContents.includes("review [n]")) {
  console.error("CLI help missing review command.");
  process.exit(1);
}
if (!cliContents.includes("deploy [n]")) {
  console.error("CLI help missing deploy command.");
  process.exit(1);
}
if (!cliContents.includes("--base <ref>")) {
  console.error("CLI help missing base option.");
  process.exit(1);
}
if (!cliContents.includes("--skip-review")) {
  console.error("CLI help missing skip-review option.");
  process.exit(1);
}
if (!cliContents.includes("PROMPT_review.txt")) {
  console.error("CLI does not point bundled reviews at PROMPT_review.txt.");
  process.exit(1);
}
if (!cliContents.includes("PROMPT_deploy_fix.txt")) {
  console.error("CLI does not point bundled deploy fixes at PROMPT_deploy_fix.txt.");
  process.exit(1);
}

if (!cliContents.includes("PROMPT_build.txt")) {
  console.error("CLI does not point bundled builds at PROMPT_build.txt.");
  process.exit(1);
}

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
