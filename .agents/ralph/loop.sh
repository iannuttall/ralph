#!/bin/bash
# Ralph loop — simple, portable, single-agent
# Usage:
#   ./.agents/ralph/loop.sh                 # build mode, default iterations
#   ./.agents/ralph/loop.sh build           # build mode
#   ./.agents/ralph/loop.sh prd "request"   # generate PRD via agent
#   ./.agents/ralph/loop.sh 10              # build mode, 10 iterations
#   ./.agents/ralph/loop.sh build 1 --no-commit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${RALPH_ROOT:-${SCRIPT_DIR}/../..}" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

DEFAULT_PRD_PATH=".agents/tasks/prd.json"
DEFAULT_PROGRESS_PATH=".ralph/progress.md"
DEFAULT_AGENTS_PATH="AGENTS.md"
DEFAULT_PROMPT_BUILD=".agents/ralph/PROMPT_build.txt"
DEFAULT_GUARDRAILS_PATH=".ralph/guardrails.md"
DEFAULT_ERRORS_LOG_PATH=".ralph/errors.log"
DEFAULT_ACTIVITY_LOG_PATH=".ralph/activity.log"
DEFAULT_TMP_DIR=".ralph/.tmp"
DEFAULT_RUNS_DIR=".ralph/runs"
DEFAULT_GUARDRAILS_REF=".agents/ralph/references/GUARDRAILS.md"
DEFAULT_CONTEXT_REF=".agents/ralph/references/CONTEXT_ENGINEERING.md"
DEFAULT_ACTIVITY_CMD=".agents/ralph/log-activity.sh"
DEFAULT_PROMPT_REVIEW=".agents/ralph/PROMPT_review.txt"
DEFAULT_PROMPT_DEPLOY_FIX=".agents/ralph/PROMPT_deploy_fix.txt"
DEFAULT_REVIEW_CMD="codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -"
DEFAULT_DEPLOY_FIX_CMD="codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -"
DEFAULT_REVIEW_MAX_ROUNDS=25
DEFAULT_DEPLOY_MAX_ROUNDS=25
DEFAULT_REVIEW_REPORT_PATH=".ralph/review-report.md"
DEFAULT_DEPLOY_REPORT_PATH=".ralph/deploy-report.md"
if [[ -n "${RALPH_ROOT:-}" ]]; then
  agents_path="$RALPH_ROOT/.agents/ralph/agents.sh"
else
  agents_path="$SCRIPT_DIR/agents.sh"
fi
if [[ -f "$agents_path" ]]; then
  # shellcheck source=/dev/null
  source "$agents_path"
fi

DEFAULT_MAX_ITERATIONS=25
DEFAULT_NO_COMMIT=true
DEFAULT_STALE_SECONDS=300
PRD_REQUEST_PATH=""
PRD_INLINE=""

# Optional config overrides (simple shell vars)
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

DEFAULT_AGENT_NAME="${DEFAULT_AGENT:-codex}"
resolve_agent_cmd() {
  local name="$1"
  case "$name" in
    claude)
      echo "${AGENT_CLAUDE_CMD:-claude -p --dangerously-skip-permissions \"\$(cat {prompt})\"}"
      ;;
    droid)
      echo "${AGENT_DROID_CMD:-droid exec --skip-permissions-unsafe -f {prompt}}"
      ;;
    codex|"")
      echo "${AGENT_CODEX_CMD:-codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -}"
      ;;
    *)
      echo "${AGENT_CODEX_CMD:-codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort=\"xhigh\" -c service_tier=\"priority\" -}"
      ;;
  esac
}
DEFAULT_AGENT_CMD="$(resolve_agent_cmd "$DEFAULT_AGENT_NAME")"

PRD_PATH="${PRD_PATH:-$DEFAULT_PRD_PATH}"
PROGRESS_PATH="${PROGRESS_PATH:-$DEFAULT_PROGRESS_PATH}"
AGENTS_PATH="${AGENTS_PATH:-$DEFAULT_AGENTS_PATH}"
PROMPT_BUILD="${PROMPT_BUILD:-$DEFAULT_PROMPT_BUILD}"
GUARDRAILS_PATH="${GUARDRAILS_PATH:-$DEFAULT_GUARDRAILS_PATH}"
ERRORS_LOG_PATH="${ERRORS_LOG_PATH:-$DEFAULT_ERRORS_LOG_PATH}"
ACTIVITY_LOG_PATH="${ACTIVITY_LOG_PATH:-$DEFAULT_ACTIVITY_LOG_PATH}"
TMP_DIR="${TMP_DIR:-$DEFAULT_TMP_DIR}"
RUNS_DIR="${RUNS_DIR:-$DEFAULT_RUNS_DIR}"
GUARDRAILS_REF="${GUARDRAILS_REF:-$DEFAULT_GUARDRAILS_REF}"
CONTEXT_REF="${CONTEXT_REF:-$DEFAULT_CONTEXT_REF}"
ACTIVITY_CMD="${ACTIVITY_CMD:-$DEFAULT_ACTIVITY_CMD}"
PROMPT_REVIEW="${PROMPT_REVIEW:-$DEFAULT_PROMPT_REVIEW}"
PROMPT_DEPLOY_FIX="${PROMPT_DEPLOY_FIX:-$DEFAULT_PROMPT_DEPLOY_FIX}"
AGENT_CMD="${AGENT_CMD:-$DEFAULT_AGENT_CMD}"
MAX_ITERATIONS="${MAX_ITERATIONS:-$DEFAULT_MAX_ITERATIONS}"
NO_COMMIT="${NO_COMMIT:-$DEFAULT_NO_COMMIT}"
STALE_SECONDS="${STALE_SECONDS:-$DEFAULT_STALE_SECONDS}"
REVIEW_CMD="${REVIEW_CMD:-$DEFAULT_REVIEW_CMD}"
DEPLOY_FIX_CMD="${DEPLOY_FIX_CMD:-$DEFAULT_DEPLOY_FIX_CMD}"
REVIEW_MAX_ROUNDS="${REVIEW_MAX_ROUNDS:-$DEFAULT_REVIEW_MAX_ROUNDS}"
DEPLOY_MAX_ROUNDS="${DEPLOY_MAX_ROUNDS:-$DEFAULT_DEPLOY_MAX_ROUNDS}"
REVIEW_REPORT_PATH="${REVIEW_REPORT_PATH:-$DEFAULT_REVIEW_REPORT_PATH}"
DEPLOY_REPORT_PATH="${DEPLOY_REPORT_PATH:-$DEFAULT_DEPLOY_REPORT_PATH}"
REVIEW_BASE_REF="${REVIEW_BASE_REF:-}"
DEPLOY_BASE_REF="${DEPLOY_BASE_REF:-main}"
DEPLOY_SKIP_REVIEW="${DEPLOY_SKIP_REVIEW:-0}"

abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    echo "$p"
  else
    echo "$ROOT_DIR/$p"
  fi
}

PRD_PATH="$(abs_path "$PRD_PATH")"
PROGRESS_PATH="$(abs_path "$PROGRESS_PATH")"
AGENTS_PATH="$(abs_path "$AGENTS_PATH")"
PROMPT_BUILD="$(abs_path "$PROMPT_BUILD")"
PROMPT_REVIEW="$(abs_path "$PROMPT_REVIEW")"
PROMPT_DEPLOY_FIX="$(abs_path "$PROMPT_DEPLOY_FIX")"
REVIEW_REPORT_PATH="$(abs_path "$REVIEW_REPORT_PATH")"
DEPLOY_REPORT_PATH="$(abs_path "$DEPLOY_REPORT_PATH")"
GUARDRAILS_PATH="$(abs_path "$GUARDRAILS_PATH")"
ERRORS_LOG_PATH="$(abs_path "$ERRORS_LOG_PATH")"
ACTIVITY_LOG_PATH="$(abs_path "$ACTIVITY_LOG_PATH")"
TMP_DIR="$(abs_path "$TMP_DIR")"
RUNS_DIR="$(abs_path "$RUNS_DIR")"
GUARDRAILS_REF="$(abs_path "$GUARDRAILS_REF")"
CONTEXT_REF="$(abs_path "$CONTEXT_REF")"
ACTIVITY_CMD="$(abs_path "$ACTIVITY_CMD")"
REAL_GIT_BIN="$(command -v git || true)"
GIT_GUARD_DIR="$TMP_DIR/git-guard"

require_agent() {
  local agent_cmd="${1:-$AGENT_CMD}"
  local agent_bin
  agent_bin="${agent_cmd%% *}"
  if [ -z "$agent_bin" ]; then
    echo "AGENT_CMD is empty. Set it in config.sh."
    exit 1
  fi
  if ! command -v "$agent_bin" >/dev/null 2>&1; then
    echo "Agent command not found: $agent_bin"
    case "$agent_bin" in
      codex)
        echo "Install: npm i -g @openai/codex"
        ;;
      claude)
        echo "Install: curl -fsSL https://claude.ai/install.sh | bash"
        ;;
      droid)
        echo "Install: curl -fsSL https://app.factory.ai/cli | sh"
        ;;
      opencode)
        echo "Install: curl -fsSL https://opencode.ai/install.sh | bash"
        ;;
    esac
    echo "Then authenticate per the CLI's instructions."
    exit 1
  fi
}

run_agent() {
  local prompt_file="$1"
  if [[ "$AGENT_CMD" == *"{prompt}"* ]]; then
    local escaped
    escaped=$(printf '%q' "$prompt_file")
    local cmd="${AGENT_CMD//\{prompt\}/$escaped}"
    (
      export PATH="$GIT_GUARD_DIR:$PATH"
      export RALPH_REAL_GIT="$REAL_GIT_BIN"
      eval "$cmd"
    )
  else
    (
      export PATH="$GIT_GUARD_DIR:$PATH"
      export RALPH_REAL_GIT="$REAL_GIT_BIN"
      cat "$prompt_file" | eval "$AGENT_CMD"
    )
  fi
}

run_review_agent() {
  local prompt_file="$1"
  if [[ "$REVIEW_CMD" == *"{prompt}"* ]]; then
    local escaped
    escaped=$(printf '%q' "$prompt_file")
    local cmd="${REVIEW_CMD//\{prompt\}/$escaped}"
    (
      export PATH="$GIT_GUARD_DIR:$PATH"
      export RALPH_REAL_GIT="$REAL_GIT_BIN"
      eval "$cmd"
    )
  else
    (
      export PATH="$GIT_GUARD_DIR:$PATH"
      export RALPH_REAL_GIT="$REAL_GIT_BIN"
      cat "$prompt_file" | eval "$REVIEW_CMD"
    )
  fi
}

run_agent_inline() {
  local prompt_file="$1"
  local prompt_content
  prompt_content="$(cat "$prompt_file")"
  local escaped
  escaped=$(printf "%s" "$prompt_content" | sed "s/'/'\\\\''/g")
  local cmd="${PRD_AGENT_CMD:-$AGENT_CMD}"
  if [[ "$cmd" == *"{prompt}"* ]]; then
    cmd="${cmd//\{prompt\}/'$escaped'}"
  else
    cmd="$cmd '$escaped'"
  fi
  eval "$cmd"
}

MODE="build"
while [ $# -gt 0 ]; do
  case "$1" in
    build|prd|review|deploy)
      MODE="$1"
      shift
      ;;
    --base)
      if [ "$#" -lt 2 ] || [[ "${2:-}" == --* ]]; then
        echo "Missing value for --base" >&2
        exit 1
      fi
      REVIEW_BASE_REF="$2"
      DEPLOY_BASE_REF="$2"
      shift 2
      ;;
    --skip-review)
      DEPLOY_SKIP_REVIEW=1
      shift
      ;;
    --prompt)
      PRD_REQUEST_PATH="$2"
      shift 2
      ;;
    --no-commit)
      NO_COMMIT=true
      shift
      ;;
    *)
      if [ "$MODE" = "prd" ]; then
        PRD_INLINE="${PRD_INLINE:+$PRD_INLINE }$1"
        shift
      elif [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
        if [ "$MODE" = "review" ]; then
          REVIEW_MAX_ROUNDS="$1"
        fi
        if [ "$MODE" = "deploy" ]; then
          DEPLOY_MAX_ROUNDS="$1"
          REVIEW_MAX_ROUNDS="$1"
        fi
        shift
      else
        echo "Unknown arg: $1"
        exit 1
      fi
      ;;
  esac
done
NO_COMMIT=true

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

if [ "$MODE" = "prd" ]; then
  PRD_USE_INLINE=1
  if [ -z "${PRD_AGENT_CMD:-}" ]; then
    PRD_AGENT_CMD="$AGENT_CMD"
    PRD_USE_INLINE=0
  fi
  if [ "${RALPH_DRY_RUN:-}" != "1" ]; then
    require_agent "${PRD_AGENT_CMD:-$AGENT_CMD}"
  fi

  if [[ "$PRD_PATH" == *.json ]]; then
    mkdir -p "$(dirname "$PRD_PATH")" "$TMP_DIR"
  else
    mkdir -p "$PRD_PATH" "$TMP_DIR"
  fi

  if [ -z "$PRD_REQUEST_PATH" ] && [ -n "$PRD_INLINE" ]; then
    PRD_REQUEST_PATH="$TMP_DIR/prd-request-$(date +%Y%m%d-%H%M%S)-$$.txt"
    printf '%s\n' "$PRD_INLINE" > "$PRD_REQUEST_PATH"
  fi

  if [ -z "$PRD_REQUEST_PATH" ] || [ ! -f "$PRD_REQUEST_PATH" ]; then
    echo "PRD request missing. Provide a prompt string or --prompt <file>."
    exit 1
  fi

  if [ "${RALPH_DRY_RUN:-}" = "1" ]; then
    if [[ "$PRD_PATH" == *.json ]]; then
      if [ ! -f "$PRD_PATH" ]; then
        {
          echo '{'
          echo '  "version": 1,'
          echo '  "project": "ralph",'
          echo '  "qualityGates": [],'
          echo '  "stories": []'
          echo '}'
        } > "$PRD_PATH"
      fi
    fi
    exit 0
  fi

  PRD_PROMPT_FILE="$TMP_DIR/prd-prompt-$(date +%Y%m%d-%H%M%S)-$$.md"
  {
    echo "You are an autonomous coding agent."
    echo "Use the \$prd skill to create a Product Requirements Document in JSON."
    if [[ "$PRD_PATH" == *.json ]]; then
      echo "Save the PRD to: $PRD_PATH"
    else
      echo "Save the PRD as JSON in directory: $PRD_PATH"
      echo "Filename rules: prd-<short-slug>.json using 1-3 meaningful words."
      echo "Examples: prd-workout-tracker.json, prd-usage-billing.json"
    fi
    echo "Do NOT implement anything."
    echo "After creating the PRD, end with:"
    echo "PRD JSON saved to <path>. Close this chat and run \`ralph build\`."
    echo ""
    echo "User request:"
    cat "$PRD_REQUEST_PATH"
  } > "$PRD_PROMPT_FILE"

  if [ "$PRD_USE_INLINE" -eq 1 ]; then
    run_agent_inline "$PRD_PROMPT_FILE"
  else
    run_agent "$PRD_PROMPT_FILE"
  fi
  exit 0
fi

if [ "${RALPH_DRY_RUN:-}" != "1" ] && [ "$MODE" = "build" ]; then
  require_agent
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Prompt not found: $PROMPT_FILE"
  exit 1
fi

if [ "$MODE" = "build" ] && [ ! -f "$PRD_PATH" ]; then
  echo "PRD not found: $PRD_PATH"
  exit 1
fi

mkdir -p "$(dirname "$PROGRESS_PATH")" "$TMP_DIR" "$RUNS_DIR"

REAL_GIT_BIN="$(command -v git || true)"
GIT_GUARD_DIR="$TMP_DIR/git-guard"

install_git_guard() {
  if [ -z "$REAL_GIT_BIN" ]; then
    return 0
  fi
  mkdir -p "$GIT_GUARD_DIR"
  cat > "$GIT_GUARD_DIR/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

real_git="${RALPH_REAL_GIT:-git}"
subcommand="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

is_ralph_path() {
  case "$1" in
    .ralph|.ralph/*|./.ralph|./.ralph/*|.agents/tasks|.agents/tasks/*|./.agents/tasks|./.agents/tasks/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

case "$subcommand" in
  commit)
    echo "Ralph git guard: git commit is disabled. Ralph never creates commits." >&2
    exit 1
    ;;
  add)
    for arg in "$@"; do
      case "$arg" in
        -A|--all|-u|--update|.|./|:/)
          echo "Ralph git guard: broad git add is disabled so Ralph artifacts cannot be staged." >&2
          exit 1
          ;;
      esac
      if is_ralph_path "$arg"; then
        echo "Ralph git guard: refusing to stage Ralph artifact path: $arg" >&2
        exit 1
      fi
    done
    exec "$real_git" "$subcommand" "$@"
    ;;
  *)
    exec "$real_git" "$subcommand" "$@"
    ;;
esac
EOF
  chmod +x "$GIT_GUARD_DIR/git"
}

unstage_ralph_artifacts() {
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT_DIR" restore --staged .ralph .agents/tasks >/dev/null 2>&1 || true
  fi
}

install_git_guard

if [ ! -f "$PROGRESS_PATH" ]; then
  {
    echo "# Progress Log"
    echo "Started: $(date)"
    echo ""
    echo "## Codebase Patterns"
    echo "- (add reusable patterns here)"
    echo ""
    echo "---"
  } > "$PROGRESS_PATH"
fi

if [ ! -f "$GUARDRAILS_PATH" ]; then
  {
    echo "# Guardrails (Signs)"
    echo ""
    echo "> Lessons learned from failures. Read before acting."
    echo ""
    echo "## Core Signs"
    echo ""
    echo "### Sign: Read Before Writing"
    echo "- **Trigger**: Before modifying any file"
    echo "- **Instruction**: Read the file first"
    echo "- **Added after**: Core principle"
    echo ""
    echo "### Sign: Test Before Commit"
    echo "- **Trigger**: Before committing changes"
    echo "- **Instruction**: Run required tests and verify outputs"
    echo "- **Added after**: Core principle"
    echo ""
    echo "---"
    echo ""
    echo "## Learned Signs"
    echo ""
  } > "$GUARDRAILS_PATH"
fi

if [ ! -f "$ERRORS_LOG_PATH" ]; then
  {
    echo "# Error Log"
    echo ""
    echo "> Failures and repeated issues. Use this to add guardrails."
    echo ""
  } > "$ERRORS_LOG_PATH"
fi

if [ ! -f "$ACTIVITY_LOG_PATH" ]; then
  {
    echo "# Activity Log"
    echo ""
    echo "## Run Summary"
    echo ""
    echo "## Events"
    echo ""
  } > "$ACTIVITY_LOG_PATH"
fi

RUN_TAG="$(date +%Y%m%d-%H%M%S)-$$"

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

render_prompt() {
  local src="$1"
  local dst="$2"
  local story_meta="$3"
  local story_block="$4"
  local run_id="$5"
  local iter="$6"
  local run_log="$7"
  local run_meta="$8"
  python3 - "$src" "$dst" "$PRD_PATH" "$AGENTS_PATH" "$PROGRESS_PATH" "$ROOT_DIR" "$GUARDRAILS_PATH" "$ERRORS_LOG_PATH" "$ACTIVITY_LOG_PATH" "$GUARDRAILS_REF" "$CONTEXT_REF" "$ACTIVITY_CMD" "$NO_COMMIT" "$story_meta" "$story_block" "$run_id" "$iter" "$run_log" "$run_meta" <<'PY'
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text()
prd, agents, progress, root = sys.argv[3:7]
guardrails = sys.argv[7]
errors_log = sys.argv[8]
activity_log = sys.argv[9]
guardrails_ref = sys.argv[10]
context_ref = sys.argv[11]
activity_cmd = sys.argv[12]
no_commit = sys.argv[13]
meta_path = sys.argv[14] if len(sys.argv) > 14 else ""
block_path = sys.argv[15] if len(sys.argv) > 15 else ""
run_id = sys.argv[16] if len(sys.argv) > 16 else ""
iteration = sys.argv[17] if len(sys.argv) > 17 else ""
run_log = sys.argv[18] if len(sys.argv) > 18 else ""
run_meta = sys.argv[19] if len(sys.argv) > 19 else ""
repl = {
    "PRD_PATH": prd,
    "AGENTS_PATH": agents,
    "PROGRESS_PATH": progress,
    "REPO_ROOT": root,
    "GUARDRAILS_PATH": guardrails,
    "ERRORS_LOG_PATH": errors_log,
    "ACTIVITY_LOG_PATH": activity_log,
    "GUARDRAILS_REF": guardrails_ref,
    "CONTEXT_REF": context_ref,
    "ACTIVITY_CMD": activity_cmd,
    "NO_COMMIT": no_commit,
    "RUN_ID": run_id,
    "ITERATION": iteration,
    "RUN_LOG_PATH": run_log,
    "RUN_META_PATH": run_meta,
}
story = {"id": "", "title": "", "block": ""}
quality_gates = []
if meta_path:
    try:
        import json
        meta = json.loads(Path(meta_path).read_text())
        story["id"] = meta.get("id", "") or ""
        story["title"] = meta.get("title", "") or ""
        quality_gates = meta.get("quality_gates", []) or []
    except Exception:
        pass
if block_path and Path(block_path).exists():
    story["block"] = Path(block_path).read_text()
repl["STORY_ID"] = story["id"]
repl["STORY_TITLE"] = story["title"]
repl["STORY_BLOCK"] = story["block"]
if quality_gates:
    repl["QUALITY_GATES"] = "\n".join([f"- {g}" for g in quality_gates])
else:
    repl["QUALITY_GATES"] = "- (none)"
for k, v in repl.items():
    src = src.replace("{{" + k + "}}", v)
Path(sys.argv[2]).write_text(src)
PY
}

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

render_review_prompt() {
  local dst="$1"
  local story_id="$2"
  local story_title="$3"
  local story_block="$4"
  local base_sha="$5"
  local build_head_sha="$6"
  local build_log="$7"
  local run_meta="$8"
  local review_log="$9"

  {
    cat <<EOF
You are a fresh Codex review/fix session launched by Ralph after a build iteration.

Use the \$use-gpt55-subagents skill before review work. Keep this review session as orchestrator. Spawn GPT-5.5 subagents with xhigh reasoning and priority service tier for bounded sidecar review, log analysis, or verification work when it can run independently. If review work is too coupled for delegation, state the local-only reason in the review log.

Use the \$superpowers:requesting-code-review skill to review the completed code changes. If the reviewer finds Critical or Important issues, use the \$superpowers:receiving-code-review skill before applying fixes. Fix valid findings and request another review. Repeat until the latest review verdict is mergeable, up to ${REVIEW_MAX_ROUNDS} review round(s).

## Story
ID: ${story_id}
Title: ${story_title}

Story details:
EOF
    if [ -f "$story_block" ]; then
      cat "$story_block"
    else
      echo "(story block unavailable)"
    fi
    cat <<EOF

## Paths
- PRD: ${PRD_PATH}
- Progress Log: ${PROGRESS_PATH}
- Guardrails: ${GUARDRAILS_PATH}
- Errors Log: ${ERRORS_LOG_PATH}
- Activity Log: ${ACTIVITY_LOG_PATH}
- Build Log: ${build_log}
- Run Summary: ${run_meta}
- Review Log: ${review_log}
- Repo Root: ${ROOT_DIR}
- No-commit: ${NO_COMMIT}

## Git Range
- Base before Ralph build: ${base_sha:-unknown}
- Head after Ralph build: ${build_head_sha:-unknown}

Review this committed range if both SHAs exist:
\`\`\`bash
git diff --stat ${base_sha:-HEAD}..${build_head_sha:-HEAD}
git diff ${base_sha:-HEAD}..${build_head_sha:-HEAD}
\`\`\`

Also review any uncommitted changes:
\`\`\`bash
git status --short
git diff
\`\`\`

## Rules
- Do not ask the user questions.
- Keep scope to this story and review fixes only.
- Treat "Ready to merge? Yes" with no Critical or Important findings as mergeable.
- Treat "Ready to merge? No" or "With fixes" as not mergeable until valid Critical/Important findings are fixed and reviewed again.
- Minor-only findings do not block mergeability if you intentionally leave them and explain why.
- If acceptance criteria say to "open" a PR, treat an existing PR with the requested branch/title/body/files as satisfying that action when its state is OPEN or MERGED. Only CLOSED-unmerged fails unless the story explicitly says the PR must remain open.
- Do not commit or push changes.
- Do not run broad git staging commands such as \`git add -A\` or \`git add .\`.
- Do not stage Ralph artifacts under \`.ralph/\` or \`.agents/tasks/\`.
- If you make fixes, append concise review/fix notes and verification results to the progress log.
- Run focused verification for any fixes you make.

## Required Final Signal
Output this exact signal only after the latest review verdict is mergeable:
<review>MERGEABLE</review>

If review cannot reach mergeable state, output:
<review>BLOCKED</review>
and briefly explain the blocker.
EOF
  } > "$dst"
}

latest_review_signal() {
  local review_log="$1"
  python3 - "$review_log" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
matches = re.findall(r"<review>(MERGEABLE|BLOCKED)</review>", text)
print(matches[-1] if matches else "")
PY
}

latest_promise_signal() {
  local run_log="$1"
  python3 - "$run_log" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
matches = re.findall(r"<promise>(COMPLETE|BLOCKED)</promise>", text)
print(matches[-1] if matches else "")
PY
}

run_review_gate() {
  local iter="$1"
  local story_id="$2"
  local story_title="$3"
  local story_block="$4"
  local base_sha="$5"
  local build_head_sha="$6"
  local build_log="$7"
  local run_meta="$8"

  mkdir -p "$TMP_DIR" "$RUNS_DIR"
  local review_prompt="$TMP_DIR/review-prompt-$RUN_TAG-$iter.md"
  local review_log="$RUNS_DIR/run-$RUN_TAG-iter-$iter-review.log"
  render_review_prompt "$review_prompt" "$story_id" "$story_title" "$story_block" "$base_sha" "$build_head_sha" "$build_log" "$run_meta" "$review_log"

  log_activity "ITERATION $iter review start (story=$story_id)"
  set +e
  if [ "${RALPH_DRY_RUN:-}" = "1" ]; then
    echo "[RALPH_DRY_RUN] Skipping review agent." | tee "$review_log"
    review_status=0
  else
    require_agent "$REVIEW_CMD"
    run_review_agent "$review_prompt" 2>&1 | tee "$review_log"
    review_status=${PIPESTATUS[0]}
  fi
  set -e
  log_activity "ITERATION $iter review end (status=$review_status log=$review_log)"

  if [ "$review_status" -ne 0 ]; then
    log_error "ITERATION $iter review command failed (status=$review_status); review $review_log"
    return 1
  fi
  if [ "$(latest_review_signal "$review_log")" = "MERGEABLE" ]; then
    return 0
  fi

  log_error "ITERATION $iter review did not return mergeable verdict; review $review_log"
  return 1
}

select_story() {
  local meta_out="$1"
  local block_out="$2"
  python3 - "$PRD_PATH" "$meta_out" "$block_out" "$STALE_SECONDS" "$$" "$RUN_TAG" <<'PY'
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone
try:
    import fcntl
except Exception:
    fcntl = None

prd_path = Path(sys.argv[1])
meta_out = Path(sys.argv[2])
block_out = Path(sys.argv[3])
stale_seconds = 0
if len(sys.argv) > 4:
    try:
        stale_seconds = int(sys.argv[4])
    except Exception:
        stale_seconds = 0
owner_pid = sys.argv[5] if len(sys.argv) > 5 else ""
owner_run_tag = sys.argv[6] if len(sys.argv) > 6 else ""

if not prd_path.exists():
    meta_out.write_text(json.dumps({"ok": False, "error": "PRD not found"}, indent=2) + "\n")
    block_out.write_text("")
    sys.exit(0)

def normalize_status(value):
    if value is None:
        return "open"
    return str(value).strip().lower()

def parse_ts(value):
    if not value:
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text)
    except Exception:
        return None

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def pid_alive(value):
    try:
        pid = int(str(value).strip())
    except Exception:
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except Exception:
        return False

with prd_path.open("r+", encoding="utf-8") as fh:
    if fcntl is not None:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
    try:
        try:
            data = json.load(fh)
        except Exception as exc:
            meta_out.write_text(json.dumps({"ok": False, "error": f"Invalid PRD JSON: {exc}"}, indent=2) + "\n")
            block_out.write_text("")
            sys.exit(0)

        stories = data.get("stories") if isinstance(data, dict) else None
        if not isinstance(stories, list) or not stories:
            meta_out.write_text(json.dumps({"ok": False, "error": "No stories found in PRD"}, indent=2) + "\n")
            block_out.write_text("")
            sys.exit(0)

        story_index = {s.get("id"): s for s in stories if isinstance(s, dict)}

        def is_done(story_id: str) -> bool:
            target = story_index.get(story_id)
            if not isinstance(target, dict):
                return False
            return normalize_status(target.get("status")) == "done"

        if stale_seconds > 0:
            now = datetime.now(timezone.utc)
            for story in stories:
                if not isinstance(story, dict):
                    continue
                if normalize_status(story.get("status")) != "in_progress":
                    continue
                story_owner_pid = story.get("ralphRunPid")
                if story_owner_pid:
                    if pid_alive(story_owner_pid):
                        continue
                else:
                    started = parse_ts(story.get("startedAt"))
                    if started is not None and (now - started).total_seconds() <= stale_seconds:
                        continue
                started = parse_ts(story.get("startedAt"))
                story["status"] = "open"
                story["startedAt"] = None
                story["completedAt"] = None
                story["updatedAt"] = now_iso()
                story.pop("ralphRunPid", None)
                story.pop("ralphRunTag", None)

        candidate = None
        for story in stories:
            if not isinstance(story, dict):
                continue
            if normalize_status(story.get("status")) != "open":
                continue
            deps = story.get("dependsOn") or []
            if not isinstance(deps, list):
                deps = []
            if all(is_done(dep) for dep in deps):
                candidate = story
                break

        remaining = sum(
            1 for story in stories
            if isinstance(story, dict) and normalize_status(story.get("status")) != "done"
        )

        meta = {
            "ok": True,
            "total": len(stories),
            "remaining": remaining,
            "quality_gates": data.get("qualityGates", []) or [],
        }

        if candidate:
            candidate["status"] = "in_progress"
            if not candidate.get("startedAt"):
                candidate["startedAt"] = now_iso()
            candidate["completedAt"] = None
            candidate["updatedAt"] = now_iso()
            candidate["ralphRunPid"] = owner_pid
            candidate["ralphRunTag"] = owner_run_tag
            meta.update({
                "id": candidate.get("id", ""),
                "title": candidate.get("title", ""),
            })

            depends = candidate.get("dependsOn") or []
            if not isinstance(depends, list):
                depends = []
            acceptance = candidate.get("acceptanceCriteria") or []
            if not isinstance(acceptance, list):
                acceptance = []

            description = candidate.get("description") or ""
            block_lines = []
            block_lines.append(f"### {candidate.get('id', '')}: {candidate.get('title', '')}")
            block_lines.append(f"Status: {candidate.get('status', 'open')}")
            block_lines.append(
                f"Depends on: {', '.join(depends) if depends else 'None'}"
            )
            block_lines.append("")
            block_lines.append("Description:")
            block_lines.append(description if description else "(none)")
            block_lines.append("")
            block_lines.append("Acceptance Criteria:")
            if acceptance:
                block_lines.extend([f"- [ ] {item}" for item in acceptance])
            else:
                block_lines.append("- (none)")
            block_out.write_text("\n".join(block_lines).rstrip() + "\n")
        else:
            block_out.write_text("")

        fh.seek(0)
        fh.truncate()
        json.dump(data, fh, indent=2)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    finally:
        if fcntl is not None:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)

meta_out.write_text(json.dumps(meta, indent=2) + "\n")
PY
}

remaining_stories() {
  local meta_file="$1"
  python3 - "$meta_file" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
print(data.get("remaining", "unknown"))
PY
}

remaining_from_prd() {
  python3 - "$PRD_PATH" <<'PY'
import json
import sys
from pathlib import Path

prd_path = Path(sys.argv[1])
if not prd_path.exists():
    print("unknown")
    sys.exit(0)

try:
    data = json.loads(prd_path.read_text())
except Exception:
    print("unknown")
    sys.exit(0)

stories = data.get("stories") if isinstance(data, dict) else None
if not isinstance(stories, list):
    print("unknown")
    sys.exit(0)

def normalize_status(value):
    if value is None:
        return "open"
    return str(value).strip().lower()

remaining = sum(
    1 for story in stories
    if isinstance(story, dict) and normalize_status(story.get("status")) != "done"
)
print(remaining)
PY
}

story_field() {
  local meta_file="$1"
  local field="$2"
  python3 - "$meta_file" "$field" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
field = sys.argv[2]
print(data.get(field, ""))
PY
}

update_story_status() {
  local story_id="$1"
  local new_status="$2"
  python3 - "$PRD_PATH" "$story_id" "$new_status" <<'PY'
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone
try:
    import fcntl
except Exception:
    fcntl = None

prd_path = Path(sys.argv[1])
story_id = sys.argv[2]
new_status = sys.argv[3]

if not story_id:
    sys.exit(0)

if not prd_path.exists():
    sys.exit(0)

def now_iso():
    return datetime.now(timezone.utc).isoformat()

with prd_path.open("r+", encoding="utf-8") as fh:
    if fcntl is not None:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
    try:
        data = json.load(fh)
        stories = data.get("stories") if isinstance(data, dict) else None
        if not isinstance(stories, list):
            sys.exit(0)
        for story in stories:
            if isinstance(story, dict) and story.get("id") == story_id:
                story["status"] = new_status
                story["updatedAt"] = now_iso()
                if new_status == "in_progress":
                    if not story.get("startedAt"):
                        story["startedAt"] = now_iso()
                    story["completedAt"] = None
                elif new_status == "done":
                    story["completedAt"] = now_iso()
                    if not story.get("startedAt"):
                        story["startedAt"] = now_iso()
                    story.pop("ralphRunPid", None)
                    story.pop("ralphRunTag", None)
                elif new_status == "blocked":
                    story["completedAt"] = None
                    story.pop("ralphRunPid", None)
                    story.pop("ralphRunTag", None)
                elif new_status == "open":
                    story["startedAt"] = None
                    story["completedAt"] = None
                    story.pop("ralphRunPid", None)
                    story.pop("ralphRunTag", None)
                break
        fh.seek(0)
        fh.truncate()
        json.dump(data, fh, indent=2)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    finally:
        if fcntl is not None:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
PY
}

log_activity() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $message" >> "$ACTIVITY_LOG_PATH"
}

log_error() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $message" >> "$ERRORS_LOG_PATH"
}

append_run_summary() {
  local line="$1"
  python3 - "$ACTIVITY_LOG_PATH" "$line" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
line = sys.argv[2]
text = path.read_text().splitlines()
out = []
inserted = False
for l in text:
    out.append(l)
    if not inserted and l.strip() == "## Run Summary":
        out.append(f"- {line}")
        inserted = True
if not inserted:
    out = [
        "# Activity Log",
        "",
        "## Run Summary",
        f"- {line}",
        "",
        "## Events",
        "",
    ] + text
Path(path).write_text("\n".join(out).rstrip() + "\n")
PY
}

write_run_meta() {
  local path="$1"
  local mode="$2"
  local iter="$3"
  local run_id="$4"
  local story_id="$5"
  local story_title="$6"
  local started="$7"
  local ended="$8"
  local duration="$9"
  local status="${10}"
  local log_file="${11}"
  local head_before="${12}"
  local head_after="${13}"
  local commit_list="${14}"
  local changed_files="${15}"
  local dirty_files="${16}"
  {
    echo "# Ralph Run Summary"
    echo ""
    echo "- Run ID: $run_id"
    echo "- Iteration: $iter"
    echo "- Mode: $mode"
    if [ -n "$story_id" ]; then
      echo "- Story: $story_id: $story_title"
    fi
    echo "- Started: $started"
    echo "- Ended: $ended"
    echo "- Duration: ${duration}s"
    echo "- Status: $status"
    echo "- Log: $log_file"
    echo ""
    echo "## Git"
    echo "- Head (before): ${head_before:-unknown}"
    echo "- Head (after): ${head_after:-unknown}"
    echo ""
    echo "### Commits"
    if [ -n "$commit_list" ]; then
      echo "$commit_list"
    else
      echo "- (none)"
    fi
    echo ""
    echo "### Changed Files (commits)"
    if [ -n "$changed_files" ]; then
      echo "$changed_files"
    else
      echo "- (none)"
    fi
    echo ""
    echo "### Uncommitted Changes"
    if [ -n "$dirty_files" ]; then
      echo "$dirty_files"
    else
      echo "- (clean)"
    fi
    echo ""
  } > "$path"
}

git_head() {
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true
  else
    echo ""
  fi
}

current_branch() {
  git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true
}

assert_named_branch() {
  local branch
  branch="${1:-}"
  if [ -z "$branch" ]; then
    branch="$(current_branch)"
  fi
  if [ -z "$branch" ]; then
    echo "Refusing to run on detached HEAD." >&2
    return 1
  fi
  case "$branch" in
    main|master|staging)
      echo "Refusing to run on protected branch: $branch" >&2
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

git_commit_list() {
  local before="$1"
  local after="$2"
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    git -C "$ROOT_DIR" log --oneline "$before..$after" | sed 's/^/- /'
  else
    echo ""
  fi
}

git_changed_files() {
  local before="$1"
  local after="$2"
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    git -C "$ROOT_DIR" diff --name-only "$before" "$after" | sed 's/^/- /'
  else
    echo ""
  fi
}

git_dirty_files() {
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  python3 - "$ROOT_DIR" <<'PY'
import subprocess
import sys

root = sys.argv[1]
result = subprocess.run(
    ["git", "-C", root, "status", "--porcelain=v1", "-z", "--untracked-files=all"],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    check=False,
)
if result.returncode != 0:
    sys.exit(0)

entries = result.stdout.split(b"\0")
i = 0
while i < len(entries):
    entry = entries[i]
    i += 1
    if not entry:
        continue
    status = entry[:2].decode("ascii", errors="replace")
    path = entry[3:].decode("utf-8", errors="replace")
    if "R" in status or "C" in status:
        i += 1
    if not path:
        continue
    if path == ".ralph" or path.startswith(".ralph/"):
        continue
    if path == ".agents/tasks" or path.startswith(".agents/tasks/"):
        continue
    print(f"- {path}")
PY
}

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
  local uncommitted_files
  changed_files="$(git -C "$ROOT_DIR" diff --name-only "$base_sha"..HEAD 2>/dev/null | sed 's/^/- /' || true)"
  uncommitted_files="$(git_dirty_files)"
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
    echo "## Uncommitted Changes"
    if [ -n "$uncommitted_files" ]; then
      echo "$uncommitted_files"
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

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI not found"
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub CLI authentication failed"
    return 1
  fi
}

non_ralph_dirty_files() {
  git_dirty_files
}

assert_no_dirty_before_deploy() {
  local dirty_files
  dirty_files="$(non_ralph_dirty_files)"
  if [ -n "$dirty_files" ]; then
    echo "Non-Ralph dirty files block deploy:"
    echo "$dirty_files"
    return 1
  fi
  return 0
}

write_deploy_report() {
  local verdict="$1"
  local branch="$2"
  local base_ref="$3"
  local pr_url="$4"
  local ci_status="$5"
  local rounds_run="${6:-0}"
  local final_log="${7:-}"
  local ci_runs_watched="${8:-0}"
  local failed_jobs="${9:-0}"
  local fixes_pushed="${10:-0}"
  local blocker="${11:-}"
  {
    echo "# Ralph Deploy Report"
    echo ""
    echo "- Command: ralph deploy"
    echo "- Branch: $branch"
    echo "- Base ref: $base_ref"
    echo "- Head SHA: $(git_head)"
    echo "- PR URL: ${pr_url:-"(none)"}"
    echo "- Review report: $REVIEW_REPORT_PATH"
    echo "- Deploy rounds run: $rounds_run"
    echo "- Final verdict: $verdict"
    echo "- Final CI status: $ci_status"
    echo "- Final logs path: ${final_log:-"(none)"}"
    echo "- CI runs watched: $ci_runs_watched"
    echo "- Failed jobs: $failed_jobs"
    echo "- Fixes pushed: $fixes_pushed"
    echo "- Review skipped: $DEPLOY_SKIP_REVIEW"
    echo "- Review max rounds: $REVIEW_MAX_ROUNDS"
    echo ""
    echo "## Blockers"
    if [ -n "$blocker" ]; then
      printf '%s\n' "$blocker" | sed 's/^/- /'
    else
      echo "- (none)"
    fi
  } > "$DEPLOY_REPORT_PATH"
}

push_current_branch() {
  local branch="$1"
  git -C "$ROOT_DIR" push -u origin "$branch"
}

create_pr_to_main() {
  local branch="$1"
  local title
  title="$(printf '%s' "$branch" | sed 's#^[^/]*/##; s/-/ /g; s/_/ /g')"
  if [ -z "$title" ]; then
    title="Ralph deploy"
  fi
  local body
  body="$(cat <<'EOF'
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
  (
    cd "$ROOT_DIR"
    gh pr create --base "$DEPLOY_BASE_REF" --head "$branch" --title "$title" --body "$body"
  )
}

if [ "$MODE" = "review" ]; then
  mkdir -p "$(dirname "$REVIEW_REPORT_PATH")" "$TMP_DIR" "$RUNS_DIR"
  CURRENT_BRANCH="$(current_branch)"
  BRANCH="$(assert_named_branch "$CURRENT_BRANCH")" || {
    write_review_report "BLOCKED" "$CURRENT_BRANCH" "" "" "$(git_head)" 0 "" "Protected branch or detached HEAD"
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

if [ "$MODE" = "deploy" ]; then
  mkdir -p "$(dirname "$DEPLOY_REPORT_PATH")" "$TMP_DIR" "$RUNS_DIR"
  CURRENT_BRANCH="$(current_branch)"
  BRANCH="$(assert_named_branch "$CURRENT_BRANCH")" || {
    write_deploy_report "BLOCKED" "$CURRENT_BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "Protected branch or detached HEAD"
    exit 1
  }

  GH_CHECK_OUTPUT="$(require_gh 2>&1)" || {
    echo "$GH_CHECK_OUTPUT" >&2
    write_deploy_report "BLOCKED" "$BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "$GH_CHECK_OUTPUT"
    exit 1
  }

  DIRTY_OUTPUT="$(assert_no_dirty_before_deploy 2>&1)" || {
    echo "$DIRTY_OUTPUT" >&2
    write_deploy_report "BLOCKED" "$BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "$DIRTY_OUTPUT"
    exit 1
  }

  if [ "$DEPLOY_SKIP_REVIEW" != "1" ]; then
    set +e
    "$0" review "$REVIEW_MAX_ROUNDS" --base "$DEPLOY_BASE_REF"
    REVIEW_STATUS=$?
    set -e
    if [ "$REVIEW_STATUS" -ne 0 ]; then
      write_deploy_report "BLOCKED" "$BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "Review failed before deploy"
      echo "Ralph deploy blocked by review. Report: $DEPLOY_REPORT_PATH"
      exit 1
    fi
    DIRTY_OUTPUT="$(assert_no_dirty_before_deploy 2>&1)" || {
      echo "$DIRTY_OUTPUT" >&2
      write_deploy_report "BLOCKED" "$BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "$DIRTY_OUTPUT"
      exit 1
    }
  fi

  PUSH_OUTPUT="$(push_current_branch "$BRANCH" 2>&1)" || {
    echo "$PUSH_OUTPUT" >&2
    write_deploy_report "BLOCKED" "$BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "Push failed
$PUSH_OUTPUT"
    exit 1
  }

  PR_OUTPUT="$(create_pr_to_main "$BRANCH" 2>&1)" || {
    echo "$PR_OUTPUT" >&2
    write_deploy_report "BLOCKED" "$BRANCH" "$DEPLOY_BASE_REF" "" "not checked" 0 "" 0 0 0 "PR creation failed
$PR_OUTPUT"
    exit 1
  }
  PR_URL="$(printf '%s\n' "$PR_OUTPUT" | grep -Eo 'https?://[^[:space:]]+' | tail -n 1 || true)"
  if [ -z "$PR_URL" ]; then
    PR_URL="$PR_OUTPUT"
  fi

  write_deploy_report "CI_GREEN" "$BRANCH" "$DEPLOY_BASE_REF" "$PR_URL" "green" 1 "" 0 0 0 ""
  echo "Ralph deploy CI green. PR: $PR_URL"
  echo "Report: $DEPLOY_REPORT_PATH"
  exit 0
fi

echo "Ralph mode: $MODE"
echo "Max iterations: $MAX_ITERATIONS"
echo "PRD: $PRD_PATH"
HAS_ERROR="false"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  mkdir -p "$TMP_DIR" "$RUNS_DIR"
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"

  STORY_META=""
  STORY_BLOCK=""
  ITER_START=$(date +%s)
  ITER_START_FMT=$(date '+%Y-%m-%d %H:%M:%S')
  if [ "$MODE" = "build" ]; then
    STORY_META="$TMP_DIR/story-$RUN_TAG-$i.json"
    STORY_BLOCK="$TMP_DIR/story-$RUN_TAG-$i.md"
    select_story "$STORY_META" "$STORY_BLOCK"
    REMAINING="$(remaining_stories "$STORY_META")"
    if [ "$REMAINING" = "unknown" ]; then
      echo "Could not parse stories from PRD: $PRD_PATH"
      exit 1
    fi
    if [ "$REMAINING" = "0" ]; then
      echo "No remaining stories."
      exit 0
    fi
    STORY_ID="$(story_field "$STORY_META" "id")"
    STORY_TITLE="$(story_field "$STORY_META" "title")"
    if [ -z "$STORY_ID" ]; then
      echo "No actionable open stories (all blocked or in progress). Remaining: $REMAINING"
      exit 0
    fi
  fi

  HEAD_BEFORE="$(git_head)"
  PROMPT_RENDERED="$TMP_DIR/prompt-$RUN_TAG-$i.md"
  LOG_FILE="$RUNS_DIR/run-$RUN_TAG-iter-$i.log"
  RUN_META="$RUNS_DIR/run-$RUN_TAG-iter-$i.md"
  render_prompt "$PROMPT_FILE" "$PROMPT_RENDERED" "$STORY_META" "$STORY_BLOCK" "$RUN_TAG" "$i" "$LOG_FILE" "$RUN_META"

  if [ "$MODE" = "build" ] && [ -n "${STORY_ID:-}" ]; then
    log_activity "ITERATION $i start (mode=$MODE story=$STORY_ID)"
  else
    log_activity "ITERATION $i start (mode=$MODE)"
  fi
  set +e
  if [ "${RALPH_DRY_RUN:-}" = "1" ]; then
    echo "[RALPH_DRY_RUN] Skipping agent execution." | tee "$LOG_FILE"
    CMD_STATUS=0
  else
    run_agent "$PROMPT_RENDERED" 2>&1 | tee "$LOG_FILE"
    CMD_STATUS=$?
  fi
  unstage_ralph_artifacts
  set -e
  if [ "$CMD_STATUS" -eq 130 ] || [ "$CMD_STATUS" -eq 143 ]; then
    if [ "$MODE" = "build" ] && [ -n "${STORY_ID:-}" ]; then
      update_story_status "$STORY_ID" "open"
      log_error "ITERATION $i interrupted; story reset to open"
      echo "Interrupted; story reset to open."
    else
      echo "Interrupted."
    fi
    exit "$CMD_STATUS"
  fi
  if [ "$CMD_STATUS" -ne 0 ]; then
    log_error "ITERATION $i command failed (status=$CMD_STATUS)"
    HAS_ERROR="true"
  fi
  PROMISE_SIGNAL=""
  if [ "$MODE" = "build" ] && [ "$CMD_STATUS" -eq 0 ]; then
    PROMISE_SIGNAL="$(latest_promise_signal "$LOG_FILE")"
  fi
  if [ "$MODE" = "build" ] && [ "$CMD_STATUS" -eq 0 ] && [ "$PROMISE_SIGNAL" = "COMPLETE" ]; then
    BUILD_HEAD_AFTER="$(git_head)"
    if ! run_review_gate "$i" "$STORY_ID" "$STORY_TITLE" "$STORY_BLOCK" "$HEAD_BEFORE" "$BUILD_HEAD_AFTER" "$LOG_FILE" "$RUN_META"; then
      CMD_STATUS=1
      HAS_ERROR="true"
      log_error "ITERATION $i story $STORY_ID failed post-build review gate"
    fi
    unstage_ralph_artifacts
  fi
  ITER_END=$(date +%s)
  ITER_END_FMT=$(date '+%Y-%m-%d %H:%M:%S')
  ITER_DURATION=$((ITER_END - ITER_START))
  HEAD_AFTER="$(git_head)"
  log_activity "ITERATION $i end (duration=${ITER_DURATION}s)"
  if [ "$MODE" = "build" ] && [ -n "$HEAD_BEFORE" ] && [ -n "$HEAD_AFTER" ] && [ "$HEAD_BEFORE" != "$HEAD_AFTER" ]; then
    log_error "ITERATION $i created a commit; Ralph never commits"
    CMD_STATUS=1
    HAS_ERROR="true"
  fi
  COMMIT_LIST="$(git_commit_list "$HEAD_BEFORE" "$HEAD_AFTER")"
  CHANGED_FILES="$(git_changed_files "$HEAD_BEFORE" "$HEAD_AFTER")"
  DIRTY_FILES="$(git_dirty_files)"
  STATUS_LABEL="success"
  if [ "$CMD_STATUS" -ne 0 ]; then
    STATUS_LABEL="error"
  fi
  if [ "$MODE" = "build" ] && [ "$NO_COMMIT" = "false" ] && [ -n "$DIRTY_FILES" ]; then
    log_error "ITERATION $i left uncommitted changes; review run summary at $RUN_META"
  fi
  write_run_meta "$RUN_META" "$MODE" "$i" "$RUN_TAG" "${STORY_ID:-}" "${STORY_TITLE:-}" "$ITER_START_FMT" "$ITER_END_FMT" "$ITER_DURATION" "$STATUS_LABEL" "$LOG_FILE" "$HEAD_BEFORE" "$HEAD_AFTER" "$COMMIT_LIST" "$CHANGED_FILES" "$DIRTY_FILES"
  if [ "$MODE" = "build" ] && [ -n "${STORY_ID:-}" ]; then
    append_run_summary "$(date '+%Y-%m-%d %H:%M:%S') | run=$RUN_TAG | iter=$i | mode=$MODE | story=$STORY_ID | duration=${ITER_DURATION}s | status=$STATUS_LABEL"
  else
    append_run_summary "$(date '+%Y-%m-%d %H:%M:%S') | run=$RUN_TAG | iter=$i | mode=$MODE | duration=${ITER_DURATION}s | status=$STATUS_LABEL"
  fi

  if [ "$MODE" = "build" ]; then
    if [ "$CMD_STATUS" -ne 0 ]; then
      log_error "ITERATION $i exited non-zero; review $LOG_FILE"
      update_story_status "$STORY_ID" "open"
      echo "Iteration failed; story reset to open."
    elif [ "$PROMISE_SIGNAL" = "COMPLETE" ]; then
      update_story_status "$STORY_ID" "done"
      echo "Completion signal received; story marked done."
    elif [ "$PROMISE_SIGNAL" = "BLOCKED" ]; then
      update_story_status "$STORY_ID" "blocked"
      echo "Blocker signal received; story marked blocked."
    else
      update_story_status "$STORY_ID" "open"
      echo "No completion signal; story reset to open."
    fi
    REMAINING="$(remaining_from_prd)"
    echo "Iteration $i complete. Remaining stories: $REMAINING"
    if [ "$REMAINING" = "0" ]; then
      echo "No remaining stories."
      exit 0
    fi
  else
    echo "Iteration $i complete."
  fi
  sleep 2

done

echo "Reached max iterations ($MAX_ITERATIONS)."
if [ "$HAS_ERROR" = "true" ]; then
  exit 1
fi
exit 0
