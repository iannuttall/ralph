# Ralph Test Coverage Audit

## Scope reviewed
- `bin/ralph`
- `.agents/ralph/loop.sh`
- `.agents/ralph/PROMPT_build.md`
- `.agents/ralph/log-activity.sh`
- `.agents/ralph/references/*`
- `skills/*`
- `tests/*`

## Current test coverage

### CLI
- `tests/cli-smoke.mjs`
  - Verifies `--help` output
  - Verifies `ralph prd ... --out` creates a PRD JSON file (dry-run)
  - Verifies `ralph overview --prd ...` creates an overview file

### Loop (dry-run)
- `tests/agent-loops.mjs`
  - Runs `ralph build 1 --no-commit` with all agents using `RALPH_DRY_RUN=1`
  - Confirms loops execute and log to stdout without real agent execution

### Agent ping (fast, real)
- `tests/agent-ping.mjs`
  - Runs `ralph ping` for codex/claude/droid/opencode/copilot
  - Verifies each agent responds with `<end>pong</end>`

### Real integration (new)
- `tests/real-agents.mjs`
  - Creates a temp repo with a 2‑story JSON PRD and minimal AGENTS instructions
  - Runs `ralph build 2 --agent=<codex|claude|droid>`
  - Verifies:
    - PRD stories are all marked `done`
    - At least one git commit was created
    - Progress log exists
  - Cleans up the temp repo and logs after each agent run (pass or fail)

## Gaps identified
- **Interactive installs**: `ralph install` and `ralph install --skills` require prompts and are not exercised in automated tests.
- **Skill installation paths**: Local vs global skill locations are not validated in tests.
- **Failure logging**: `.ralph/errors.log` contents are not asserted.
- **Activity logging**: Activity log presence is not asserted (only implied via run completion).
- **Guardrails**: No test verifies that guardrails are created/updated.

## Recommendations
1. Keep default tests deterministic (`npm test`) and provide a separate real‑agent test (`npm run test:real`).
2. Add a non‑interactive flag for skill install if you want it testable in CI.
3. Add assertions for `.ralph/activity.log` and `.ralph/guardrails.md` creation in `tests/real-agents.mjs`.
4. Consider adding coverage for PRD selection when multiple JSON files exist.

## How to run
- **Deterministic:** `npm test`
- **Fast real agent check:** `npm run test:ping`
- **Real agents:** `npm run test:real` (requires codex/claude/droid installed and authenticated)
