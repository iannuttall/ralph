# Ralph Review Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ralph review` for local mergeability review and `ralph deploy` for PR creation plus CI repair.

**Architecture:** Keep `bin/ralph` as the thin CLI/router and put command behavior in `.agents/ralph/loop.sh`, matching existing `build` and `prd` execution. Add prompt templates for review and CI-fix sessions, plus smoke tests with fake agents and fake `gh` so default tests never call real Codex or GitHub. Ship `ralph review` as an independently testable slice before `ralph deploy`.

**Tech Stack:** Node CLI, Bash loop runner, Git, GitHub CLI (`gh`), Codex CLI, npm smoke tests.

---

## File Structure

- Modify `bin/ralph`: add help text for `review`/`deploy`, parse `--base` and `--skip-review`, pass template paths and env values to `loop.sh`.
- Modify `.agents/ralph/loop.sh`: add review/deploy modes, local git preflights, report writers, review loop, deploy PR/CI loop.
- Modify `.agents/ralph/config.sh`: document review/deploy config overrides.
- Create `.agents/ralph/PROMPT_review.txt`: local branch review/fix prompt using required Superpowers skills.
- Create `.agents/ralph/PROMPT_deploy_fix.txt`: CI failure fix prompt using failed logs and focused verification.
- Create `tests/review-deploy.mjs`: fake-agent and fake-`gh` coverage for `review` and `deploy`.
- Modify `tests/cli-smoke.mjs`: assert command help, prompt files, and GPT-5.5/xhigh/priority pins.
- Modify `package.json`: include `tests/review-deploy.mjs` in `npm test`.
- Modify `README.md` and `examples/commands.md`: document the new commands after implementation.

## Implementation Notes

- Keep `ralph build` behavior intact.
- `ralph review` must not require a PR or `gh`.
- `ralph deploy` may require `gh`.
- `ralph deploy` should block on pre-existing dirty non-Ralph files before review. If `ralph review` or the CI-fix loop creates new non-Ralph changes during deploy, deploy may commit those changes because the deploy command explicitly owns push/PR/CI repair.
- Preserve `.ralph/` and `.agents/tasks/` as runtime artifacts and never stage them.
- Use `--no-verify` only for docs commits if docs artifact guard blocks and the user has explicitly allowed docs for this feature.

### Task 1: CLI Flags, Config, And Prompt Files

**Files:**
- Modify: `bin/ralph`
- Modify: `.agents/ralph/config.sh`
- Modify: `tests/cli-smoke.mjs`
- Create: `.agents/ralph/PROMPT_review.txt`
- Create: `.agents/ralph/PROMPT_deploy_fix.txt`
- Modify: `package.json`

- [ ] **Step 1: Write failing CLI smoke assertions**

Add these assertions to `tests/cli-smoke.mjs` after the existing `buildPrompt` checks:

```js
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
```

- [ ] **Step 2: Run the smoke test to verify it fails**

Run:

```bash
node tests/cli-smoke.mjs
```

Expected: FAIL because `PROMPT_review.txt` does not exist or CLI help lacks `review`/`deploy`.

- [ ] **Step 3: Add CLI flags and help text**

In `bin/ralph`, add state variables near the existing globals:

```js
let baseRefOverride = null;
let skipReview = false;
```

Update `usage()` command and option text:

```text
  review [n] [--base ref]             Review current branch until mergeable
  deploy [n] [--base ref]             Create PR to main and repair CI until green
```

```text
  --base <ref>                        Override review/deploy base ref
  --skip-review                       For deploy only: skip the pre-deploy review loop
```

Add parsing in the raw arg loop before `args.push(arg)`:

```js
  if (arg.startsWith("--base=")) {
    baseRefOverride = arg.split("=").slice(1).join("=");
    continue;
  }
  if (arg === "--base") {
    baseRefOverride = rawArgs[i + 1];
    i += 1;
    continue;
  }
  if (arg === "--skip-review") {
    skipReview = true;
    continue;
  }
```

After `const env = { ...process.env, RALPH_ROOT: cwd };`, add:

```js
  if (baseRefOverride) {
    env.REVIEW_BASE_REF = baseRefOverride;
    env.DEPLOY_BASE_REF = baseRefOverride;
  }
  if (skipReview) {
    env.DEPLOY_SKIP_REVIEW = "1";
  }
```

Inside the `if (templateDir === globalDir)` block, add:

```js
    env.PROMPT_REVIEW = path.join(templateDir, "PROMPT_review.txt");
    env.PROMPT_DEPLOY_FIX = path.join(templateDir, "PROMPT_deploy_fix.txt");
```

- [ ] **Step 4: Add loop defaults and config comments**

In `.agents/ralph/loop.sh`, add defaults near the existing defaults:

```bash
DEFAULT_PROMPT_REVIEW=".agents/ralph/PROMPT_review.txt"
DEFAULT_PROMPT_DEPLOY_FIX=".agents/ralph/PROMPT_deploy_fix.txt"
DEFAULT_REVIEW_CMD="codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -"
DEFAULT_DEPLOY_FIX_CMD="codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -"
DEFAULT_REVIEW_MAX_ROUNDS=25
DEFAULT_DEPLOY_MAX_ROUNDS=25
DEFAULT_REVIEW_REPORT_PATH=".ralph/review-report.md"
DEFAULT_DEPLOY_REPORT_PATH=".ralph/deploy-report.md"
```

Replace the existing `DEFAULT_REVIEW_MAX_ROUNDS=3` with `DEFAULT_REVIEW_MAX_ROUNDS=25`.

Add variables near the current `PROMPT_BUILD`, `REVIEW_CMD`, and `REVIEW_MAX_ROUNDS` assignments:

```bash
PROMPT_REVIEW="${PROMPT_REVIEW:-$DEFAULT_PROMPT_REVIEW}"
PROMPT_DEPLOY_FIX="${PROMPT_DEPLOY_FIX:-$DEFAULT_PROMPT_DEPLOY_FIX}"
REVIEW_CMD="${REVIEW_CMD:-$DEFAULT_REVIEW_CMD}"
DEPLOY_FIX_CMD="${DEPLOY_FIX_CMD:-$DEFAULT_DEPLOY_FIX_CMD}"
REVIEW_MAX_ROUNDS="${REVIEW_MAX_ROUNDS:-$DEFAULT_REVIEW_MAX_ROUNDS}"
DEPLOY_MAX_ROUNDS="${DEPLOY_MAX_ROUNDS:-$DEFAULT_DEPLOY_MAX_ROUNDS}"
REVIEW_REPORT_PATH="${REVIEW_REPORT_PATH:-$DEFAULT_REVIEW_REPORT_PATH}"
DEPLOY_REPORT_PATH="${DEPLOY_REPORT_PATH:-$DEFAULT_DEPLOY_REPORT_PATH}"
REVIEW_BASE_REF="${REVIEW_BASE_REF:-}"
DEPLOY_BASE_REF="${DEPLOY_BASE_REF:-main}"
DEPLOY_SKIP_REVIEW="${DEPLOY_SKIP_REVIEW:-0}"
```

Add absolute path conversion after `PROMPT_BUILD="$(abs_path "$PROMPT_BUILD")"`:

```bash
PROMPT_REVIEW="$(abs_path "$PROMPT_REVIEW")"
PROMPT_DEPLOY_FIX="$(abs_path "$PROMPT_DEPLOY_FIX")"
REVIEW_REPORT_PATH="$(abs_path "$REVIEW_REPORT_PATH")"
DEPLOY_REPORT_PATH="$(abs_path "$DEPLOY_REPORT_PATH")"
```

Update `.agents/ralph/config.sh` comments:

```bash
# PROMPT_REVIEW=".agents/ralph/PROMPT_review.txt"
# PROMPT_DEPLOY_FIX=".agents/ralph/PROMPT_deploy_fix.txt"
# REVIEW_CMD="codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -"
# DEPLOY_FIX_CMD="codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -"
# REVIEW_MAX_ROUNDS=25
# DEPLOY_MAX_ROUNDS=25
# REVIEW_REPORT_PATH=".ralph/review-report.md"
# DEPLOY_REPORT_PATH=".ralph/deploy-report.md"
# REVIEW_BASE_REF=""
# DEPLOY_BASE_REF="main"
# DEPLOY_SKIP_REVIEW=0
```

- [ ] **Step 5: Add prompt template files**

Create `.agents/ralph/PROMPT_review.txt`:

```markdown
# Ralph Review

You are a fresh Codex review/fix session launched by Ralph for local branch review.

Use the $use-gpt55-subagents skill before review work. Keep this review session as orchestrator. Spawn GPT-5.5 subagents with xhigh reasoning and priority service tier for bounded sidecar review, log analysis, or verification work when it can run independently. If review work is too coupled for delegation, state the local-only reason in the review log.

Use the $superpowers:requesting-code-review skill to review the current branch changes. If the reviewer finds Critical or Important issues, use the $superpowers:receiving-code-review skill before applying fixes. Fix valid findings and request another review. Repeat until the latest review verdict is mergeable, up to {{REVIEW_MAX_ROUNDS}} review round(s).

## Paths
- Repo Root: {{REPO_ROOT}}
- Review Log: {{REVIEW_LOG_PATH}}
- Review Report: {{REVIEW_REPORT_PATH}}
- Base Ref: {{BASE_REF}}
- Base SHA: {{BASE_SHA}}
- Head SHA: {{HEAD_SHA}}
- Round: {{ROUND}}
- Max Rounds: {{REVIEW_MAX_ROUNDS}}

## Review Range

Review committed branch changes:

```bash
git diff --stat {{BASE_SHA}}..HEAD
git diff {{BASE_SHA}}..HEAD
```

Also inspect working tree state:

```bash
git status --short
git diff
```

## Rules
- Do not ask the user questions.
- Keep scope to review fixes for this branch.
- Treat "Ready to merge? Yes" with no Critical or Important findings as mergeable.
- Treat "Ready to merge? No" or "With fixes" as not mergeable until valid Critical/Important findings are fixed and reviewed again.
- Minor-only findings do not block mergeability if you intentionally leave them and explain why.
- Run focused verification for any fixes you make.
- Do not commit, push, merge, or create a PR.
- Do not stage Ralph artifacts under `.ralph/` or `.agents/tasks/`.

## Required Final Signal

Output this exact signal only after the latest review verdict is mergeable:

<review>MERGEABLE</review>

If review cannot reach mergeable state, output:

<review>BLOCKED</review>

and briefly explain the blocker.
```

Create `.agents/ralph/PROMPT_deploy_fix.txt`:

```markdown
# Ralph Deploy CI Fix

You are a fresh Codex CI-fix session launched by Ralph after a pull request CI failure.

Use the $use-gpt55-subagents skill before CI investigation. Spawn GPT-5.5 subagents with xhigh reasoning and priority service tier for bounded log analysis or verification work when it can run independently.

## Paths
- Repo Root: {{REPO_ROOT}}
- Deploy Log: {{DEPLOY_LOG_PATH}}
- Deploy Report: {{DEPLOY_REPORT_PATH}}
- Failed CI Log: {{FAILED_CI_LOG_PATH}}
- PR URL: {{PR_URL}}
- Branch: {{BRANCH}}
- Round: {{ROUND}}
- Max Rounds: {{DEPLOY_MAX_ROUNDS}}

## Failed CI Log

Read this log file:

```bash
cat {{FAILED_CI_LOG_PATH}}
```

## Rules
- Do not ask the user questions.
- Fix only the CI failure shown in the failed log.
- Read the related code before editing.
- Run focused verification for your fix.
- Do not commit, push, merge, or create a PR.
- Do not stage Ralph artifacts under `.ralph/` or `.agents/tasks/`.

## Required Final Signal

Output this exact signal when your local fix and verification are complete:

<deploy-fix>COMPLETE</deploy-fix>

If you cannot fix the CI failure, output:

<deploy-fix>BLOCKED</deploy-fix>

and briefly explain the blocker.
```

- [ ] **Step 6: Register the new test file in `package.json`**

Change the `test` script to:

```json
"test": "node tests/cli-smoke.mjs && node tests/agent-loops.mjs && node tests/review-deploy.mjs && node tests/install-smoke.mjs"
```

- [ ] **Step 7: Run smoke test and full suite**

Run:

```bash
node tests/cli-smoke.mjs
npm test
```

Expected after implementation: both PASS.

- [ ] **Step 8: Commit Task 1**

```bash
git add bin/ralph .agents/ralph/config.sh .agents/ralph/loop.sh .agents/ralph/PROMPT_review.txt .agents/ralph/PROMPT_deploy_fix.txt tests/cli-smoke.mjs package.json package-lock.json
git commit -m "feat(cli): add review deploy command plumbing"
```

### Task 2: Review Preflight And Report Scaffolding

**Files:**
- Create: `tests/review-deploy.mjs`
- Modify: `.agents/ralph/loop.sh`

- [ ] **Step 1: Add review test harness and preflight tests**

Create `tests/review-deploy.mjs` with this base harness and first tests:

```js
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname);
const cliPath = path.join(repoRoot, "bin", "ralph");

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
    ["commit", "-m", message],
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

function assertReport(root, reportPath, expected) {
  if (!existsSync(reportPath)) {
    console.error(`Missing report: ${reportPath}`);
    process.exit(1);
  }
  const report = readFileSync(reportPath, "utf-8");
  for (const text of expected) requireIncludes("report", report, text);
}

{
  const root = setupReviewProject({ branch: null, diff: false });
  try {
    const result = runRalph(root, ["review"]);
    requireStatus("review refuses main", result, 1);
    requireIncludes("review refuses main", `${result.stdout}\n${result.stderr}`, "Refusing to run on protected branch: main");
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

console.log("Review/deploy smoke tests passed.");
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
node tests/review-deploy.mjs
```

Expected: FAIL because `review` mode is currently unknown.

- [ ] **Step 3: Add mode parsing and mode-specific prompt validation**

In `.agents/ralph/loop.sh`, update mode parser:

```bash
    build|prd|review|deploy)
      MODE="$1"
      shift
      ;;
    --base)
      REVIEW_BASE_REF="$2"
      DEPLOY_BASE_REF="$2"
      shift 2
      ;;
    --skip-review)
      DEPLOY_SKIP_REVIEW=1
      shift
      ;;
```

Set `PROMPT_FILE` by mode after parsing:

```bash
case "$MODE" in
  build)
    PROMPT_FILE="$PROMPT_BUILD"
    ;;
  review)
    PROMPT_FILE="$PROMPT_REVIEW"
    MAX_ITERATIONS="$REVIEW_MAX_ROUNDS"
    ;;
  deploy)
    PROMPT_FILE="$PROMPT_DEPLOY_FIX"
    MAX_ITERATIONS="$DEPLOY_MAX_ROUNDS"
    ;;
esac
```

Change the PRD existence check so only build needs a PRD:

```bash
if [ "$MODE" = "build" ] && [ ! -f "$PRD_PATH" ]; then
  echo "PRD not found: $PRD_PATH"
  exit 1
fi
```

- [ ] **Step 4: Add git preflight helpers**

Add these functions near existing git helpers:

```bash
current_branch() {
  git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true
}

assert_named_branch() {
  local branch
  branch="$(current_branch)"
  if [ -z "$branch" ]; then
    echo "Refusing to run on detached HEAD."
    return 1
  fi
  case "$branch" in
    main|master|staging)
      echo "Refusing to run on protected branch: $branch"
      return 1
      ;;
  esac
  echo "$branch"
}

resolve_review_base_ref() {
  if [ -n "$REVIEW_BASE_REF" ]; then
    if git -C "$ROOT_DIR" rev-parse --verify "$REVIEW_BASE_REF" >/dev/null 2>&1; then
      echo "$REVIEW_BASE_REF"
      return 0
    fi
    echo "Base ref not found: $REVIEW_BASE_REF" >&2
    return 1
  fi
  if git -C "$ROOT_DIR" show-ref --verify refs/heads/main >/dev/null 2>&1; then
    echo "main"
    return 0
  fi
  if git -C "$ROOT_DIR" show-ref --verify refs/remotes/origin/main >/dev/null 2>&1; then
    echo "origin/main"
    return 0
  fi
  echo "Base ref not found: main or origin/main" >&2
  return 1
}

merge_base_sha() {
  local base_ref="$1"
  git -C "$ROOT_DIR" merge-base HEAD "$base_ref" 2>/dev/null || true
}

assert_reviewable_diff() {
  local base_sha="$1"
  if [ -z "$base_sha" ]; then
    echo "Could not determine merge base."
    return 1
  fi
  if git -C "$ROOT_DIR" diff --quiet "$base_sha"..HEAD; then
    echo "No reviewable branch diff against base."
    return 1
  fi
  return 0
}
```

- [ ] **Step 5: Add review report writer**

Add:

```bash
write_review_report() {
  local verdict="$1"
  local branch="$2"
  local base_ref="$3"
  local base_sha="$4"
  local head_sha="$5"
  local rounds_run="$6"
  local review_log="$7"
  local blocker="$8"
  local changed_files
  changed_files="$(git -C "$ROOT_DIR" diff --name-only "$base_sha"..HEAD 2>/dev/null | sed 's/^/- /' || true)"
  {
    echo "# Ralph Review Report"
    echo ""
    echo "- Command: ralph review"
    echo "- Branch: $branch"
    echo "- Base ref: $base_ref"
    echo "- Base SHA: $base_sha"
    echo "- Head SHA: $head_sha"
    echo "- Max rounds: $REVIEW_MAX_ROUNDS"
    echo "- Rounds run: $rounds_run"
    echo "- Final verdict: $verdict"
    echo "- Final review log: $review_log"
    echo ""
    echo "## Changed Files Reviewed"
    if [ -n "$changed_files" ]; then
      echo "$changed_files"
    else
      echo "- (none)"
    fi
    echo ""
    echo "## Verification"
    echo "- See review log: $review_log"
    echo ""
    echo "## Blockers"
    if [ -n "$blocker" ]; then
      echo "- $blocker"
    else
      echo "- (none)"
    fi
  } > "$REVIEW_REPORT_PATH"
}
```

- [ ] **Step 6: Add review preflight mode**

Before the existing build iteration loop starts, add:

```bash
if [ "$MODE" = "review" ]; then
  mkdir -p "$(dirname "$REVIEW_REPORT_PATH")" "$TMP_DIR" "$RUNS_DIR"
  BRANCH="$(assert_named_branch)" || {
    write_review_report "BLOCKED" "" "" "" "$(git_head)" 0 "" "Protected branch or detached HEAD"
    exit 1
  }
  BASE_REF="$(resolve_review_base_ref)" || {
    write_review_report "BLOCKED" "$BRANCH" "" "" "$(git_head)" 0 "" "Base ref not found"
    exit 1
  }
  BASE_SHA="$(merge_base_sha "$BASE_REF")"
  if ! assert_reviewable_diff "$BASE_SHA"; then
    write_review_report "BLOCKED" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" 0 "" "No reviewable branch diff"
    exit 1
  fi
  echo "Review preflight passed for $BRANCH against $BASE_REF."
  write_review_report "BLOCKED" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" 0 "" "Review loop not implemented yet"
  exit 1
fi
```

This temporary block makes preflight tests pass while mergeable tests still fail until Task 3.

- [ ] **Step 7: Run the new test**

Run:

```bash
node tests/review-deploy.mjs
```

Expected after implementation: PASS for the three preflight tests.

- [ ] **Step 8: Commit Task 2**

```bash
git add .agents/ralph/loop.sh tests/review-deploy.mjs
git commit -m "feat(review): add local branch preflight"
```

### Task 3: Review Loop, Prompt Rendering, And Reports

**Files:**
- Modify: `tests/review-deploy.mjs`
- Modify: `.agents/ralph/loop.sh`
- Modify: `.agents/ralph/PROMPT_review.txt`

- [ ] **Step 1: Add review loop tests**

Append these cases before the final `console.log` in `tests/review-deploy.mjs`:

```js
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
node tests/review-deploy.mjs
```

Expected: FAIL because the temporary Task 2 review block exits before running the fake review agent.

- [ ] **Step 3: Add generic template renderer for review/deploy prompts**

Add this shell helper near `render_prompt()`:

```bash
render_template_file() {
  local src="$1"
  local dst="$2"
  shift 2
  python3 - "$src" "$dst" "$@" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text()
dst = Path(sys.argv[2])
pairs = sys.argv[3:]
repl = {}
for pair in pairs:
    key, _, value = pair.partition("=")
    repl[key] = value
for key, value in repl.items():
    src = src.replace("{{" + key + "}}", value)
dst.write_text(src)
PY
}
```

- [ ] **Step 4: Add review prompt rendering**

Add:

```bash
render_branch_review_prompt() {
  local dst="$1"
  local round="$2"
  local review_log="$3"
  local branch="$4"
  local base_ref="$5"
  local base_sha="$6"
  local head_sha="$7"
  render_template_file "$PROMPT_REVIEW" "$dst" \
    "REPO_ROOT=$ROOT_DIR" \
    "REVIEW_LOG_PATH=$review_log" \
    "REVIEW_REPORT_PATH=$REVIEW_REPORT_PATH" \
    "BASE_REF=$base_ref" \
    "BASE_SHA=$base_sha" \
    "HEAD_SHA=$head_sha" \
    "BRANCH=$branch" \
    "ROUND=$round" \
    "REVIEW_MAX_ROUNDS=$REVIEW_MAX_ROUNDS"
}
```

- [ ] **Step 5: Replace temporary preflight block with review loop**

Replace the temporary `if [ "$MODE" = "review" ]; then ... exit 1` block from Task 2 with:

```bash
if [ "$MODE" = "review" ]; then
  mkdir -p "$(dirname "$REVIEW_REPORT_PATH")" "$TMP_DIR" "$RUNS_DIR"
  BRANCH="$(assert_named_branch)" || {
    write_review_report "BLOCKED" "" "" "" "$(git_head)" 0 "" "Protected branch or detached HEAD"
    exit 1
  }
  BASE_REF="$(resolve_review_base_ref)" || {
    write_review_report "BLOCKED" "$BRANCH" "" "" "$(git_head)" 0 "" "Base ref not found"
    exit 1
  }
  BASE_SHA="$(merge_base_sha "$BASE_REF")"
  if ! assert_reviewable_diff "$BASE_SHA"; then
    write_review_report "BLOCKED" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" 0 "" "No reviewable branch diff"
    exit 1
  fi

  FINAL_LOG=""
  for round in $(seq 1 "$REVIEW_MAX_ROUNDS"); do
    REVIEW_PROMPT="$TMP_DIR/review-prompt-$RUN_TAG-$round.md"
    REVIEW_LOG="$RUNS_DIR/review-$RUN_TAG-round-$round.log"
    FINAL_LOG="$REVIEW_LOG"
    HEAD_SHA="$(git_head)"
    render_branch_review_prompt "$REVIEW_PROMPT" "$round" "$REVIEW_LOG" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$HEAD_SHA"
    log_activity "REVIEW round $round start (branch=$BRANCH base=$BASE_REF)"
    set +e
    if [ "${RALPH_DRY_RUN:-}" = "1" ]; then
      echo "[RALPH_DRY_RUN] Skipping review agent." | tee "$REVIEW_LOG"
      REVIEW_STATUS=0
    else
      require_agent "$REVIEW_CMD"
      run_review_agent "$REVIEW_PROMPT" 2>&1 | tee "$REVIEW_LOG"
      REVIEW_STATUS=${PIPESTATUS[0]}
    fi
    set -e
    unstage_ralph_artifacts
    log_activity "REVIEW round $round end (status=$REVIEW_STATUS log=$REVIEW_LOG)"
    if [ "$REVIEW_STATUS" -ne 0 ]; then
      write_review_report "BLOCKED" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" "$round" "$REVIEW_LOG" "Review command failed"
      echo "Review command failed. Report: $REVIEW_REPORT_PATH"
      exit 1
    fi
    REVIEW_SIGNAL="$(latest_review_signal "$REVIEW_LOG")"
    if [ "$REVIEW_SIGNAL" = "MERGEABLE" ]; then
      write_review_report "MERGEABLE" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" "$round" "$REVIEW_LOG" ""
      echo "Ralph review mergeable. Report: $REVIEW_REPORT_PATH"
      exit 0
    fi
    if [ "$REVIEW_SIGNAL" = "BLOCKED" ]; then
      write_review_report "BLOCKED" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" "$round" "$REVIEW_LOG" "Review did not reach mergeable verdict"
      echo "Ralph review blocked. Report: $REVIEW_REPORT_PATH"
      exit 1
    fi
  done

  write_review_report "BLOCKED" "$BRANCH" "$BASE_REF" "$BASE_SHA" "$(git_head)" "$REVIEW_MAX_ROUNDS" "$FINAL_LOG" "Review did not return a final signal"
  echo "Ralph review blocked. Report: $REVIEW_REPORT_PATH"
  exit 1
fi
```

- [ ] **Step 6: Run review tests**

Run:

```bash
node tests/review-deploy.mjs
npm test
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add .agents/ralph/loop.sh .agents/ralph/PROMPT_review.txt tests/review-deploy.mjs
git commit -m "feat(review): run local mergeability loop"
```

### Task 4: Deploy PR Creation Path

**Files:**
- Modify: `tests/review-deploy.mjs`
- Modify: `.agents/ralph/loop.sh`

- [ ] **Step 1: Add fake `gh` helper and deploy PR tests**

Add these helpers to `tests/review-deploy.mjs`:

```js
function writeFakeGh(root, { ciState = "green" } = {}) {
  const fakeBin = path.join(root, "fakebin");
  mkdirSync(fakeBin, { recursive: true });
  const ghLog = path.join(root, "gh.log");
  const statePath = path.join(root, "gh-state");
  writeFileSync(statePath, ciState);
  const ghPath = path.join(fakeBin, "gh");
  writeFileSync(
    ghPath,
    [
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      `echo "$@" >> ${JSON.stringify(ghLog)}`,
      "case \"$1 $2\" in",
      "  'auth status') exit 0 ;;",
      "  'pr create') echo 'https://github.com/aslaii/example/pull/1'; exit 0 ;;",
      "  'pr view') echo '{\"url\":\"https://github.com/aslaii/example/pull/1\",\"headRefName\":\"feature/review\",\"baseRefName\":\"main\"}'; exit 0 ;;",
      "  'run list') echo '[{\"databaseId\":123,\"status\":\"completed\",\"conclusion\":\"success\"}]'; exit 0 ;;",
      "  'run watch') exit 0 ;;",
      "  'run view') echo 'no failed logs'; exit 0 ;;",
      "esac",
      "echo \"unexpected gh args: $@\" >&2",
      "exit 1",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { fakeBin, ghLog };
}

function makeBranchPushable(root) {
  const remote = mkdtempSync(path.join(tmpdir(), "ralph-remote-"));
  const init = spawnSync("git", ["init", "--bare"], { cwd: remote, stdio: "inherit" });
  if (init.status !== 0) process.exit(init.status ?? 1);
  for (const args of [
    ["remote", "add", "origin", remote],
    ["push", "-u", "origin", "main"],
    ["push", "-u", "origin", "HEAD"],
  ]) {
    const result = spawnSync("git", args, { cwd: root, stdio: "inherit" });
    if (result.status !== 0) process.exit(result.status ?? 1);
  }
  return remote;
}
```

Add these tests before the final `console.log`:

```js
{
  const root = setupReviewProject();
  try {
    const result = runRalph(root, ["deploy", "1", "--skip-review"], { PATH: "/usr/bin:/bin" });
    requireStatus("deploy requires gh", result, 1);
    requireIncludes("deploy requires gh", `${result.stdout}\n${result.stderr}`, "GitHub CLI not found");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const root = setupReviewProject();
  const { fakeReview } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'"]);
  const { fakeBin, ghLog } = writeFakeGh(root);
  let remote = "";
  try {
    remote = makeBranchPushable(root);
    const result = runRalph(root, ["deploy", "1"], {
      REVIEW_CMD: fakeReview,
      PATH: `${fakeBin}:${process.env.PATH}`,
    });
    requireStatus("deploy creates pr", result, 0);
    const ghCalls = readFileSync(ghLog, "utf-8");
    requireIncludes("deploy creates pr", ghCalls, "auth status");
    requireIncludes("deploy creates pr", ghCalls, "pr create");
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: CI_GREEN",
      "https://github.com/aslaii/example/pull/1",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
    if (remote) rmSync(remote, { recursive: true, force: true });
  }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
node tests/review-deploy.mjs
```

Expected: FAIL because `deploy` mode is not implemented.

- [ ] **Step 3: Add deploy helper functions**

Add near git helpers:

```bash
require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI not found: gh"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI is not authenticated."
    return 1
  fi
}

non_ralph_dirty_files() {
  git -C "$ROOT_DIR" status --porcelain | awk '
    {
      path = substr($0, 4)
      if (path ~ /^\.ralph(\/|$)/ || path ~ /^\.agents\/tasks(\/|$)/) {
        next
      }
      print path
    }
  '
}

assert_no_dirty_before_deploy() {
  local dirty
  dirty="$(non_ralph_dirty_files)"
  if [ -n "$dirty" ]; then
    echo "Refusing to deploy with pre-existing uncommitted changes:"
    echo "$dirty"
    return 1
  fi
  return 0
}

write_deploy_report() {
  local verdict="$1"
  local branch="$2"
  local pr_url="$3"
  local rounds_run="$4"
  local ci_status="$5"
  local final_log="$6"
  local blocker="$7"
  {
    echo "# Ralph Deploy Report"
    echo ""
    echo "- Command: ralph deploy"
    echo "- Branch: $branch"
    echo "- Base branch: $DEPLOY_BASE_REF"
    echo "- PR URL: ${pr_url:-none}"
    echo "- Review report: $REVIEW_REPORT_PATH"
    echo "- Deploy rounds run: $rounds_run"
    echo "- Final CI status: $ci_status"
    echo "- Final verdict: $verdict"
    echo "- Final logs path: ${final_log:-none}"
    echo ""
    echo "## Blockers"
    if [ -n "$blocker" ]; then
      echo "- $blocker"
    else
      echo "- (none)"
    fi
  } > "$DEPLOY_REPORT_PATH"
}
```

- [ ] **Step 4: Add PR creation helpers**

Add:

```bash
push_current_branch() {
  local branch="$1"
  if git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git -C "$ROOT_DIR" push
  else
    git -C "$ROOT_DIR" push -u origin "$branch"
  fi
}

create_pr_to_main() {
  local branch="$1"
  local title
  title="$(printf '%s' "$branch" | sed 's#^[^/]*/##; s/-/ /g; s/_/ /g')"
  if [ -z "$title" ]; then
    title="Ralph deploy"
  fi
  gh pr create --base "$DEPLOY_BASE_REF" --head "$branch" --title "$title" --body "$(cat <<'EOF'
## Summary

## Changes
- Added:
- Updated:
- Removed:

## Reason

## Testing
- [ ] Ralph review passed
- [ ] CI watched by Ralph deploy
EOF
)"
}
```

- [ ] **Step 5: Add initial deploy mode**

Before the build loop, after the review mode block, add:

```bash
if [ "$MODE" = "deploy" ]; then
  mkdir -p "$(dirname "$DEPLOY_REPORT_PATH")" "$TMP_DIR" "$RUNS_DIR"
  BRANCH="$(assert_named_branch)" || {
    write_deploy_report "BLOCKED" "" "" 0 "unknown" "" "Protected branch or detached HEAD"
    exit 1
  }
  if ! require_gh; then
    write_deploy_report "BLOCKED" "$BRANCH" "" 0 "unknown" "" "GitHub CLI unavailable"
    exit 1
  fi
  if ! assert_no_dirty_before_deploy; then
    write_deploy_report "BLOCKED" "$BRANCH" "" 0 "unknown" "" "Pre-existing uncommitted changes"
    exit 1
  fi
  if [ "$DEPLOY_SKIP_REVIEW" != "1" ]; then
    REVIEW_CMD="$REVIEW_CMD" REVIEW_BASE_REF="$DEPLOY_BASE_REF" "$0" review "$REVIEW_MAX_ROUNDS"
  fi
  push_current_branch "$BRANCH" || {
    write_deploy_report "BLOCKED" "$BRANCH" "" 0 "unknown" "" "Push failed"
    exit 1
  }
  PR_URL="$(create_pr_to_main "$BRANCH")" || {
    write_deploy_report "BLOCKED" "$BRANCH" "" 0 "unknown" "" "PR creation failed"
    exit 1
  }
  write_deploy_report "CI_GREEN" "$BRANCH" "$PR_URL" 1 "green" "" ""
  echo "Ralph deploy complete. PR: $PR_URL"
  echo "Report: $DEPLOY_REPORT_PATH"
  exit 0
fi
```

- [ ] **Step 6: Run deploy PR tests**

Run:

```bash
node tests/review-deploy.mjs
npm test
```

Expected: PASS for current review tests and initial deploy PR creation tests.

- [ ] **Step 7: Commit Task 4**

```bash
git add .agents/ralph/loop.sh tests/review-deploy.mjs
git commit -m "feat(deploy): create pull requests with gh"
```

### Task 5: Deploy CI Watch And Repair Loop

**Files:**
- Modify: `tests/review-deploy.mjs`
- Modify: `.agents/ralph/loop.sh`
- Modify: `.agents/ralph/PROMPT_deploy_fix.txt`

- [ ] **Step 1: Extend fake `gh` for fail-then-green CI**

Replace `writeFakeGh` with this complete version:

```js
function writeFakeGh(root, { ciState = "green" } = {}) {
  const fakeBin = path.join(root, "fakebin");
  mkdirSync(fakeBin, { recursive: true });
  const ghLog = path.join(root, "gh.log");
  const statePath = path.join(root, "gh-state");
  writeFileSync(statePath, ciState);
  const ghPath = path.join(fakeBin, "gh");
  writeFileSync(
    ghPath,
    [
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      `echo "$@" >> ${JSON.stringify(ghLog)}`,
      `state_path=${JSON.stringify(statePath)}`,
      "state=$(cat \"$state_path\")",
      "case \"$1 $2\" in",
      "  'auth status') exit 0 ;;",
      "  'pr create') echo 'https://github.com/aslaii/example/pull/1'; exit 0 ;;",
      "  'pr view') echo '{\"url\":\"https://github.com/aslaii/example/pull/1\",\"headRefName\":\"feature/review\",\"baseRefName\":\"main\"}'; exit 0 ;;",
      "  'run list')",
      "    if [ \"$state\" = green ]; then",
      "      echo '[{\"databaseId\":123,\"status\":\"completed\",\"conclusion\":\"success\"}]'",
      "    else",
      "      echo '[{\"databaseId\":123,\"status\":\"completed\",\"conclusion\":\"failure\"}]'",
      "    fi",
      "    exit 0",
      "    ;;",
      "  'run watch') exit 0 ;;",
      "  'run view')",
      "    echo 'Error: expected green but found red'",
      "    echo green > \"$state_path\"",
      "    exit 0",
      "    ;;",
      "esac",
      "echo \"unexpected gh args: $@\" >&2",
      "exit 1",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { fakeBin, ghLog, statePath };
}
```

- [ ] **Step 2: Add CI repair test**

Add:

```js
function writeFakeDeployFix(root) {
  const promptPath = path.join(root, "deploy-fix-prompt.md");
  const fakeFix = path.join(root, "fake-deploy-fix-agent.sh");
  writeFileSync(
    fakeFix,
    [
      "#!/usr/bin/env bash",
      "set -euo pipefail",
      `cat > ${JSON.stringify(promptPath)}`,
      "echo 'ci fixed' >> app.txt",
      "echo '<deploy-fix>COMPLETE</deploy-fix>'",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  return { fakeFix, promptPath };
}

{
  const root = setupReviewProject();
  const { fakeReview } = writeFakeReview(root, ["echo '<review>MERGEABLE</review>'"]);
  const { fakeFix, promptPath } = writeFakeDeployFix(root);
  const { fakeBin } = writeFakeGh(root, { ciState: "red" });
  let remote = "";
  try {
    remote = makeBranchPushable(root);
    const result = runRalph(root, ["deploy", "2"], {
      REVIEW_CMD: fakeReview,
      DEPLOY_FIX_CMD: fakeFix,
      PATH: `${fakeBin}:${process.env.PATH}`,
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
    assertReport(root, path.join(root, ".ralph", "deploy-report.md"), [
      "Final verdict: CI_GREEN",
      "Final CI status: green",
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
    if (remote) rmSync(remote, { recursive: true, force: true });
  }
}
```

- [ ] **Step 3: Run test to verify failure**

Run:

```bash
node tests/review-deploy.mjs
```

Expected: FAIL because deploy does not inspect CI or run the fix agent.

- [ ] **Step 4: Add deploy signal parser and fix agent runner**

Add to `.agents/ralph/loop.sh`:

```bash
latest_deploy_fix_signal() {
  local fix_log="$1"
  python3 - "$fix_log" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
matches = re.findall(r"<deploy-fix>(COMPLETE|BLOCKED)</deploy-fix>", text)
print(matches[-1] if matches else "")
PY
}

run_deploy_fix_agent() {
  local prompt_file="$1"
  if [[ "$DEPLOY_FIX_CMD" == *"{prompt}"* ]]; then
    local escaped
    escaped=$(printf '%q' "$prompt_file")
    local cmd="${DEPLOY_FIX_CMD//\{prompt\}/$escaped}"
    eval "$cmd"
  else
    cat "$prompt_file" | eval "$DEPLOY_FIX_CMD"
  fi
}
```

- [ ] **Step 5: Add CI helpers**

Add:

```bash
latest_ci_run_id() {
  gh run list --branch "$1" --limit 10 --json databaseId,status,conclusion 2>/dev/null | python3 - <<'PY'
import json
import sys

try:
    runs = json.load(sys.stdin)
except Exception:
    runs = []
if runs:
    print(runs[0].get("databaseId", ""))
PY
}

latest_ci_conclusion() {
  gh run list --branch "$1" --limit 10 --json databaseId,status,conclusion 2>/dev/null | python3 - <<'PY'
import json
import sys

try:
    runs = json.load(sys.stdin)
except Exception:
    runs = []
if not runs:
    print("unknown")
else:
    run = runs[0]
    print(run.get("conclusion") or run.get("status") or "unknown")
PY
}

collect_failed_ci_log() {
  local run_id="$1"
  local out="$2"
  gh run view "$run_id" --log-failed > "$out" 2>&1 || true
}

render_deploy_fix_prompt() {
  local dst="$1"
  local deploy_log="$2"
  local failed_ci_log="$3"
  local pr_url="$4"
  local branch="$5"
  local round="$6"
  render_template_file "$PROMPT_DEPLOY_FIX" "$dst" \
    "REPO_ROOT=$ROOT_DIR" \
    "DEPLOY_LOG_PATH=$deploy_log" \
    "DEPLOY_REPORT_PATH=$DEPLOY_REPORT_PATH" \
    "FAILED_CI_LOG_PATH=$failed_ci_log" \
    "PR_URL=$pr_url" \
    "BRANCH=$branch" \
    "ROUND=$round" \
    "DEPLOY_MAX_ROUNDS=$DEPLOY_MAX_ROUNDS"
}
```

- [ ] **Step 6: Add safe commit/push for deploy-generated fixes**

Add:

```bash
commit_and_push_deploy_fixes() {
  local dirty
  dirty="$(non_ralph_dirty_files)"
  if [ -z "$dirty" ]; then
    return 0
  fi
  printf '%s\n' "$dirty" | while IFS= read -r file; do
    [ -n "$file" ] && git -C "$ROOT_DIR" add -- "$file"
  done
  git -C "$ROOT_DIR" commit -m "fix(ci): address CI failure"
  git -C "$ROOT_DIR" push
}
```

- [ ] **Step 7: Replace deploy one-shot success with CI loop**

In deploy mode, after `PR_URL="$(create_pr_to_main "$BRANCH")"`, replace the immediate `CI_GREEN` report with:

```bash
FINAL_LOG=""
for round in $(seq 1 "$DEPLOY_MAX_ROUNDS"); do
  RUN_ID="$(latest_ci_run_id "$BRANCH")"
  if [ -n "$RUN_ID" ]; then
    gh run watch "$RUN_ID" || true
  fi
  CI_STATUS="$(latest_ci_conclusion "$BRANCH")"
  if [ "$CI_STATUS" = "success" ]; then
    write_deploy_report "CI_GREEN" "$BRANCH" "$PR_URL" "$round" "green" "$FINAL_LOG" ""
    echo "Ralph deploy complete. PR: $PR_URL"
    echo "Report: $DEPLOY_REPORT_PATH"
    exit 0
  fi

  FAILED_CI_LOG="$RUNS_DIR/deploy-$RUN_TAG-round-$round-ci-failed.log"
  FINAL_LOG="$FAILED_CI_LOG"
  if [ -n "$RUN_ID" ]; then
    collect_failed_ci_log "$RUN_ID" "$FAILED_CI_LOG"
  else
    echo "No CI run found for branch $BRANCH" > "$FAILED_CI_LOG"
  fi

  FIX_PROMPT="$TMP_DIR/deploy-fix-prompt-$RUN_TAG-$round.md"
  FIX_LOG="$RUNS_DIR/deploy-$RUN_TAG-round-$round-fix.log"
  render_deploy_fix_prompt "$FIX_PROMPT" "$FIX_LOG" "$FAILED_CI_LOG" "$PR_URL" "$BRANCH" "$round"

  set +e
  if [ "${RALPH_DRY_RUN:-}" = "1" ]; then
    echo "[RALPH_DRY_RUN] Skipping deploy fix agent." | tee "$FIX_LOG"
    FIX_STATUS=0
  else
    require_agent "$DEPLOY_FIX_CMD"
    run_deploy_fix_agent "$FIX_PROMPT" 2>&1 | tee "$FIX_LOG"
    FIX_STATUS=${PIPESTATUS[0]}
  fi
  set -e
  unstage_ralph_artifacts

  if [ "$FIX_STATUS" -ne 0 ]; then
    write_deploy_report "BLOCKED" "$BRANCH" "$PR_URL" "$round" "$CI_STATUS" "$FIX_LOG" "Deploy fix command failed"
    exit 1
  fi
  FIX_SIGNAL="$(latest_deploy_fix_signal "$FIX_LOG")"
  if [ "$FIX_SIGNAL" != "COMPLETE" ]; then
    write_deploy_report "BLOCKED" "$BRANCH" "$PR_URL" "$round" "$CI_STATUS" "$FIX_LOG" "Deploy fix did not complete"
    exit 1
  fi
  commit_and_push_deploy_fixes || {
    write_deploy_report "BLOCKED" "$BRANCH" "$PR_URL" "$round" "$CI_STATUS" "$FIX_LOG" "Commit or push of deploy fixes failed"
    exit 1
  }
done

write_deploy_report "BLOCKED" "$BRANCH" "$PR_URL" "$DEPLOY_MAX_ROUNDS" "red" "$FINAL_LOG" "CI remained red after max rounds"
exit 1
```

- [ ] **Step 8: Run deploy CI tests**

Run:

```bash
node tests/review-deploy.mjs
npm test
```

Expected: PASS.

- [ ] **Step 9: Commit Task 5**

```bash
git add .agents/ralph/loop.sh .agents/ralph/PROMPT_deploy_fix.txt tests/review-deploy.mjs
git commit -m "feat(deploy): repair failing ci"
```

### Task 6: Documentation, Examples, And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `examples/commands.md`
- Modify: `docs/superpowers/specs/2026-06-02-ralph-review-deploy-design.md` only if implementation changed the approved behavior

- [ ] **Step 1: Add README command docs**

In `README.md`, add a section after the build quick start:

```markdown
3) Review a completed branch locally:
```

```bash
ralph review
ralph review 5 --base main
```

```markdown
`ralph review` compares the current branch to `main` or `origin/main`, runs a Codex GPT-5.5 xhigh priority review/fix loop, and writes `.ralph/review-report.md`. It refuses protected base branches, detached HEAD, and branches with no reviewable diff.

4) Deploy by PR and CI:
```

```bash
ralph deploy
ralph deploy 5 --base main
ralph deploy --skip-review
```

```markdown
`ralph deploy` requires an authenticated `gh` CLI. It runs `ralph review` by default, pushes the current branch, creates a PR to `main`, watches CI, fixes failing CI logs, and writes `.ralph/deploy-report.md`.
```

- [ ] **Step 2: Add examples**

In `examples/commands.md`, add:

```markdown
Review and deploy:

```bash
ralph review # local branch review, no GitHub required
ralph review 5 --base main
ralph deploy # review, push, PR to main, watch/fix CI
ralph deploy --skip-review # create/watch PR without rerunning local review
```
```

- [ ] **Step 3: Run docs/search checks**

Run:

```bash
rg -n "ralph review|ralph deploy|review-report|deploy-report" README.md examples/commands.md .agents/ralph
```

Expected: output includes README, examples, prompt files, and loop references.

- [ ] **Step 4: Run full verification**

Run:

```bash
npm test
git status --short
```

Expected:

- `npm test` exits `0`.
- `git status --short` shows only intentional documentation changes before commit.

- [ ] **Step 5: Commit Task 6**

Because this task intentionally commits docs and the user approved docs for this Superpowers flow, use a normal commit first:

```bash
git add README.md examples/commands.md docs/superpowers/specs/2026-06-02-ralph-review-deploy-design.md
git commit -m "docs: document ralph review deploy"
```

If the docs artifact guard blocks the commit, use:

```bash
git commit --no-verify -m "docs: document ralph review deploy"
```

- [ ] **Step 6: Final implementation verification**

Run:

```bash
npm test
git log --oneline -6
git status --short
```

Expected:

- `npm test` exits `0`.
- Recent log includes Task 1 through Task 6 commits.
- Working tree is clean or contains only user-approved untracked runtime artifacts.

## Self-Review Checklist

- Spec coverage:
  - `ralph review` local-only behavior: Tasks 2 and 3.
  - GPT-5.5/xhigh/priority pins: Task 1 and existing CLI smoke.
  - Required Superpowers review skills: Tasks 1 and 3.
  - Final review report: Tasks 2 and 3.
  - `ralph deploy` with `gh`: Tasks 4 and 5.
  - PR creation to `main`: Task 4.
  - CI watch and repair: Task 5.
  - Final deploy report: Tasks 4 and 5.
  - Docs/examples: Task 6.
- Red-flag scan: passed for incomplete markers and unresolved design slots.
- Type consistency:
  - `REVIEW_MAX_ROUNDS` and `DEPLOY_MAX_ROUNDS` are the config names.
  - `PROMPT_REVIEW` and `PROMPT_DEPLOY_FIX` match template file names.
  - `REVIEW_REPORT_PATH` and `DEPLOY_REPORT_PATH` match report paths.
  - Review signals are `<review>MERGEABLE</review>` and `<review>BLOCKED</review>`.
  - Deploy fix signals are `<deploy-fix>COMPLETE</deploy-fix>` and `<deploy-fix>BLOCKED</deploy-fix>`.
