import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname);
const cliPath = path.join(repoRoot, "bin", "ralph");
const loopPath = path.join(repoRoot, ".agents", "ralph", "loop.sh");

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { encoding: "utf-8", ...options });
  return result;
}

function requireStatus(name, result, expectedStatus) {
  if (result.status !== expectedStatus) {
    console.error(`${name} failed: expected exit ${expectedStatus}, got ${result.status}.`);
    console.error(result.stdout);
    console.error(result.stderr);
    process.exit(1);
  }
}

function requireIncludes(name, text, expected) {
  if (!text.includes(expected)) {
    console.error(`${name} failed: missing ${JSON.stringify(expected)}.`);
    console.error(text);
    process.exit(1);
  }
}

function initGit(cwd) {
  for (const args of [
    ["init", "-b", "main"],
    ["config", "user.email", "ralph@example.com"],
    ["config", "user.name", "ralph"],
  ]) {
    const result = spawnSync("git", args, { cwd, stdio: "inherit" });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
}

function commitAll(cwd, message) {
  for (const args of [
    ["add", "."],
    ["-c", "core.hooksPath=/dev/null", "commit", "-m", message],
  ]) {
    const result = spawnSync("git", args, { cwd, stdio: "inherit" });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
}

function setupReviewProject({ branch = "feature/review", diff = true } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), "ralph-review-"));
  initGit(root);
  writeFileSync(path.join(root, "app.txt"), "base\n");
  commitAll(root, "initial commit");
  if (branch) {
    const checkout = spawnSync("git", ["checkout", "-b", branch], { cwd: root, stdio: "inherit" });
    if (checkout.status !== 0) process.exit(checkout.status ?? 1);
  }
  if (diff) {
    writeFileSync(path.join(root, "app.txt"), "base\nfeature\n");
    commitAll(root, "feature change");
  }
  return root;
}

function writeFakeReview(root, lines = ["echo '<review>MERGEABLE</review>'"]) {
  const promptPath = path.join(root, "review-prompt.md");
  const fakeReview = path.join(root, "fake-review-agent.sh");
  writeFileSync(
    fakeReview,
    [
      "#!/usr/bin/env bash",
      `cat > ${JSON.stringify(promptPath)}`,
      ...lines,
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { fakeReview, promptPath };
}

function runRalph(root, args, env = {}) {
  return run(process.execPath, [cliPath, ...args], {
    cwd: root,
    env: {
      ...process.env,
      RALPH_SKIP_UPDATE_CHECK: "1",
      ...env,
    },
  });
}

function runLoop(root, args, env = {}) {
  return run(loopPath, args, {
    cwd: root,
    env: {
      ...process.env,
      RALPH_ROOT: root,
      RALPH_SKIP_UPDATE_CHECK: "1",
      ...env,
    },
  });
}

function assertReport(root, reportPath, expected) {
  if (!existsSync(reportPath)) {
    console.error(`Missing report: ${reportPath}`);
    process.exit(1);
  }
  const report = readFileSync(reportPath, "utf-8");
  for (const text of expected) requireIncludes("report", report, text);
}

{
  const root = mkdtempSync(path.join(tmpdir(), "ralph-review-"));
  try {
    const result = runLoop(root, ["review", "--base"]);
    requireStatus("loop missing base value", result, 1);
    requireIncludes("loop missing base value", `${result.stdout}\n${result.stderr}`, "Missing value for --base");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = mkdtempSync(path.join(tmpdir(), "ralph-review-"));
  try {
    const result = runRalph(root, ["review", "--base"]);
    requireStatus("cli missing base value", result, 1);
    requireIncludes("cli missing base value", `${result.stdout}\n${result.stderr}`, "Missing value for --base");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = mkdtempSync(path.join(tmpdir(), "ralph-review-"));
  try {
    const result = runRalph(root, ["review", "--base="]);
    requireStatus("cli empty base value", result, 1);
    requireIncludes("cli empty base value", `${result.stdout}\n${result.stderr}`, "Missing value for --base");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject({ branch: null, diff: false });
  try {
    const result = runRalph(root, ["review"]);
    requireStatus("review refuses main", result, 1);
    requireIncludes("review refuses main", `${result.stdout}\n${result.stderr}`, "Refusing to run on protected branch: main");
    assertReport(root, path.join(root, ".ralph", "review-report.md"), ["- Branch: main"]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  try {
    const detach = spawnSync("git", ["checkout", "--detach", "HEAD"], { cwd: root, stdio: "inherit" });
    if (detach.status !== 0) process.exit(detach.status ?? 1);
    const result = runRalph(root, ["review"]);
    requireStatus("review refuses detached", result, 1);
    requireIncludes("review refuses detached", `${result.stdout}\n${result.stderr}`, "Refusing to run on detached HEAD");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject({ diff: false });
  try {
    const result = runRalph(root, ["review"]);
    requireStatus("review refuses no diff", result, 1);
    requireIncludes("review refuses no diff", `${result.stdout}\n${result.stderr}`, "No reviewable branch diff");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const { fakeReview, promptPath } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'"]);
  try {
    const result = runRalph(root, ["review", "1"], { REVIEW_CMD: fakeReview });
    requireStatus("review mergeable", result, 0);
    if (!existsSync(promptPath)) {
      console.error("review mergeable failed: prompt was not captured.");
      process.exit(1);
    }
    const prompt = readFileSync(promptPath, "utf-8");
    for (const text of [
      "$use-gpt55-subagents",
      "$superpowers:requesting-code-review",
      "$superpowers:receiving-code-review",
      "<review>MERGEABLE</review>",
    ]) {
      requireIncludes("review prompt", prompt, text);
    }
    assertReport(root, path.join(root, ".ralph", "review-report.md"), [
      "Final verdict: MERGEABLE",
      "Command: ralph review",
      "app.txt",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const { fakeReview } = writeFakeReview(root, ["echo '<review>BLOCKED</review>'"]);
  try {
    const result = runRalph(root, ["review", "1"], { REVIEW_CMD: fakeReview });
    requireStatus("review blocked", result, 1);
    assertReport(root, path.join(root, ".ralph", "review-report.md"), [
      "Final verdict: BLOCKED",
      "Review did not reach mergeable verdict",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const { fakeReview } = writeFakeReview(root, ["echo 'review complete but no signal'"]);
  try {
    const result = runRalph(root, ["review", "1"], { REVIEW_CMD: fakeReview });
    requireStatus("review no signal", result, 1);
    assertReport(root, path.join(root, ".ralph", "review-report.md"), [
      "Final verdict: BLOCKED",
      "Review did not return a final signal",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const { fakeReview } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'", "exit 2"]);
  try {
    const result = runRalph(root, ["review", "1"], { REVIEW_CMD: fakeReview });
    requireStatus("review nonzero", result, 1);
    assertReport(root, path.join(root, ".ralph", "review-report.md"), [
      "Final verdict: BLOCKED",
      "Review command failed",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

console.log("Review/deploy smoke tests passed.");
