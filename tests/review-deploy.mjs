import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
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

function requireNotIncludes(name, text, unexpected) {
  if (text.includes(unexpected)) {
    console.error(`${name} failed: unexpected ${JSON.stringify(unexpected)}.`);
    console.error(text);
    process.exit(1);
  }
}

function requireCount(name, text, expected, count) {
  const actual = text.split(expected).length - 1;
  if (actual !== count) {
    console.error(`${name} failed: expected ${JSON.stringify(expected)} ${count} time(s), got ${actual}.`);
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
  const fakeRoot = path.join(root, ".ralph", "test");
  mkdirSync(fakeRoot, { recursive: true });
  const promptPath = path.join(fakeRoot, "review-prompt.md");
  const fakeReview = path.join(fakeRoot, "fake-review-agent.sh");
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

function writeFakeDeployFix(root) {
  const fakeRoot = path.join(root, ".ralph", "test");
  mkdirSync(fakeRoot, { recursive: true });
  const promptPath = path.join(fakeRoot, "deploy-fix-prompt.md");
  const fakeFix = path.join(fakeRoot, "fake-deploy-fix-agent.sh");
  writeFileSync(
    fakeFix,
    [
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      `cat > ${JSON.stringify(promptPath)}`,
      `echo 'ci fixed' >> ${JSON.stringify(path.join(root, "app.txt"))}`,
      "echo '<deploy-fix>COMPLETE</deploy-fix>'",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { fakeFix, promptPath };
}

function writeFakeGh(root, { ciState = "green" } = {}) {
  const fakeBin = path.join(root, ".ralph", "fakebin");
  const logPath = path.join(root, ".ralph", "gh.log");
  const statePath = path.join(root, ".ralph", "gh-state");
  const initialHead = spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: root,
    encoding: "utf-8",
  }).stdout.trim();
  const fakePrUrl = "https://github.example.com/owner/repo/pull/123";
  const fakeGh = path.join(fakeBin, "gh");
  mkdirSync(fakeBin, { recursive: true });
  writeFileSync(statePath, ciState);
  writeFileSync(
    fakeGh,
    [
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      `printf 'cwd=%s\\n' "$PWD" >> ${JSON.stringify(logPath)}`,
      `printf '%s\\n' "$*" >> ${JSON.stringify(logPath)}`,
      `state_path=${JSON.stringify(statePath)}`,
      `initial_head=${JSON.stringify(initialHead)}`,
      'state="$(cat "$state_path")"',
      'if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then',
      "  echo 'Logged in to github.com'",
      "  exit 0",
      "fi",
      'if [ "${1:-}" = "pr" ] && [ "${2:-}" = "create" ]; then',
      `  echo ${JSON.stringify(fakePrUrl)}`,
      "  exit 0",
      "fi",
      'if [ "${1:-}" = "run" ] && [ "${2:-}" = "list" ]; then',
      '  current_head="$(git rev-parse HEAD)"',
      '  if [ "$state" = "green" ]; then',
      '    printf \'[{"databaseId":"run-%s","headSha":"%s","status":"completed","conclusion":"success"}]\\n\' "$current_head" "$current_head"',
      '  elif [ "$current_head" = "$initial_head" ]; then',
      '    printf \'[{"databaseId":"run-%s","headSha":"%s","status":"completed","conclusion":"failure"}]\\n\' "$initial_head" "$initial_head"',
      "  else",
      '    printf \'[{"databaseId":"run-%s","headSha":"%s","status":"completed","conclusion":"failure"},{"databaseId":"run-%s","headSha":"%s","status":"completed","conclusion":"success"}]\\n\' "$initial_head" "$initial_head" "$current_head" "$current_head"',
      "  fi",
      "  exit 0",
      "fi",
      'if [ "${1:-}" = "run" ] && [ "${2:-}" = "watch" ]; then',
      "  exit 0",
      "fi",
      'if [ "${1:-}" = "run" ] && [ "${2:-}" = "view" ]; then',
      "  echo 'Error: expected green but found red'",
      "  exit 0",
      "fi",
      'echo "unsupported fake gh: $*" >&2',
      "exit 1",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { fakeBin, logPath, fakePrUrl, statePath };
}

function pathWithoutGh(root) {
  const fakeBin = path.join(root, ".ralph", "no-gh-bin");
  mkdirSync(fakeBin, { recursive: true });
  for (const name of ["cat", "chmod", "date", "dirname", "git", "mkdir", "pwd", "sed"]) {
    const found = spawnSync("sh", ["-lc", `command -v ${name}`], { encoding: "utf-8" });
    if (found.status !== 0) continue;
    const target = found.stdout.trim();
    if (!target) continue;
    symlinkSync(target, path.join(fakeBin, name));
  }
  return fakeBin;
}

function makeBranchPushable(root) {
  const remote = mkdtempSync(path.join(tmpdir(), "ralph-origin-"));
  rmSync(remote, { recursive: true, force: true });
  const currentBranch = spawnSync("git", ["branch", "--show-current"], {
    cwd: root,
    encoding: "utf-8",
  }).stdout.trim();
  for (const args of [
    ["init", "--bare", "-b", "main", remote],
    ["remote", "add", "origin", remote],
    ["push", "origin", "main"],
    ["push", "-u", "origin", currentBranch],
  ]) {
    const result = spawnSync("git", args, { cwd: root, stdio: "inherit" });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
  return remote;
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

function assertReportSectionIncludes(root, reportPath, section, expected) {
  if (!existsSync(reportPath)) {
    console.error(`Missing report: ${reportPath}`);
    process.exit(1);
  }
  const report = readFileSync(reportPath, "utf-8");
  const sectionStart = report.indexOf(section);
  if (sectionStart === -1) {
    console.error(`report failed: missing section ${JSON.stringify(section)}.`);
    console.error(report);
    process.exit(1);
  }
  const nextSection = report.indexOf("\n## ", sectionStart + section.length);
  const sectionText = report.slice(sectionStart, nextSection === -1 ? undefined : nextSection);
  requireIncludes("report section", sectionText, expected);
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
  const root = setupReviewProject();
  try {
    const result = runRalph(root, ["deploy", "1", "--skip-review"], { PATH: pathWithoutGh(root) });
    requireStatus("deploy requires gh", result, 1);
    requireIncludes("deploy requires gh", `${result.stdout}\n${result.stderr}`, "GitHub CLI not found");
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: BLOCKED",
      "GitHub CLI not found",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const remote = makeBranchPushable(root);
  const { fakeReview } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'"]);
  const { fakeBin, logPath, fakePrUrl } = writeFakeGh(root);
  const outsideCwd = mkdtempSync(path.join(tmpdir(), "ralph-outside-"));
  try {
    const result = run(loopPath, ["deploy", "1"], {
      cwd: outsideCwd,
      env: {
        ...process.env,
        RALPH_ROOT: root,
        RALPH_SKIP_UPDATE_CHECK: "1",
        PATH: `${fakeBin}:${process.env.PATH}`,
        REVIEW_CMD: fakeReview,
        PROMPT_REVIEW: path.join(repoRoot, ".agents", "ralph", "PROMPT_review.txt"),
        PROMPT_DEPLOY_FIX: path.join(repoRoot, ".agents", "ralph", "PROMPT_deploy_fix.txt"),
      },
    });
    requireStatus("deploy creates PR", result, 0);
    const ghLog = readFileSync(logPath, "utf-8");
    requireIncludes("gh log", ghLog, `cwd=${root}`);
    requireIncludes("gh log", ghLog, "auth status");
    requireIncludes("gh log", ghLog, "pr create");
    requireIncludes("gh log", ghLog, "--title");
    requireIncludes("gh log", ghLog, "--body");
    requireIncludes("gh log", ghLog, "## Summary");
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: CI_GREEN",
      "Final CI status: green",
      "Review report:",
      "Deploy rounds run: 1",
      "Final logs path:",
      "CI runs watched: 1",
      "Failed runs: 0",
      "Fixes pushed: 0",
      fakePrUrl,
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(remote, { recursive: true, force: true });
    rmSync(outsideCwd, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const remote = makeBranchPushable(root);
  const { fakeBin, logPath, fakePrUrl } = writeFakeGh(root);
  try {
    const result = runRalph(root, ["deploy", "1", "--skip-review"], {
      PATH: `${fakeBin}:${process.env.PATH}`,
    });
    requireStatus("deploy creates PR with skip review", result, 0);
    const ghLog = readFileSync(logPath, "utf-8");
    requireIncludes("gh log", ghLog, "auth status");
    requireIncludes("gh log", ghLog, "pr create");
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: CI_GREEN",
      fakePrUrl,
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(remote, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const remote = makeBranchPushable(root);
  const { fakeReview } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'"]);
  const { fakeFix, promptPath } = writeFakeDeployFix(root);
  const { fakeBin, logPath, fakePrUrl } = writeFakeGh(root, { ciState: "red" });
  try {
    const result = runRalph(root, ["deploy", "2"], {
      PATH: `${fakeBin}:${process.env.PATH}`,
      REVIEW_CMD: fakeReview,
      DEPLOY_FIX_CMD: fakeFix,
    });
    requireStatus("deploy fixes ci", result, 0);
    if (!existsSync(promptPath)) {
      console.error("deploy fixes ci failed: fix prompt was not captured.");
      process.exit(1);
    }
    const prompt = readFileSync(promptPath, "utf-8");
    requireIncludes("deploy fix prompt", prompt, "$use-gpt55-subagents");
    requireIncludes("deploy fix prompt", prompt, "Failed CI Log");
    const log = spawnSync("git", ["log", "--oneline", "-1"], { cwd: root, encoding: "utf-8" });
    requireIncludes("deploy fixes ci commit", log.stdout, "fix(ci): address CI failure");
    const ghLog = readFileSync(logPath, "utf-8");
    requireCount("deploy fixes ci", ghLog, "run view", 1);
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: CI_GREEN",
      "Final CI status: green",
      fakePrUrl,
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(remote, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const remote = makeBranchPushable(root);
  const { fakeReview } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'"]);
  const { fakeBin } = writeFakeGh(root, { ciState: "red" });
  try {
    const result = runRalph(root, ["deploy", "1"], {
      PATH: `${fakeBin}:${process.env.PATH}`,
      REVIEW_CMD: fakeReview,
      DEPLOY_FIX_CMD: "missing-deploy-fix-agent",
    });
    requireStatus("deploy missing fix agent", result, 1);
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: BLOCKED",
      "Deploy fix command unavailable",
      "missing-deploy-fix-agent",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(remote, { recursive: true, force: true });
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
  const { fakeReview } = writeFakeReview(root, [
    "mkdir -p 'dir with spaces' .ralph .agents/tasks",
    "printf 'review fix\\n' > 'dir with spaces/fix file.txt'",
    "printf 'ralph artifact\\n' > .ralph/review.tmp",
    "printf 'task artifact\\n' > .agents/tasks/review-task.json",
    "echo '<review>MERGEABLE</review>'",
  ]);
  try {
    const result = runRalph(root, ["review", "1"], { REVIEW_CMD: fakeReview });
    requireStatus("review mergeable with uncommitted file", result, 0);
    const reportPath = path.join(root, ".ralph", "review-report.md");
    assertReportSectionIncludes(root, reportPath, "## Uncommitted Changes", "- dir with spaces/fix file.txt");
    const report = readFileSync(reportPath, "utf-8");
    requireNotIncludes("review report", report, ".agents/tasks");
    requireNotIncludes("review report", report, ".ralph/review.tmp");
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
