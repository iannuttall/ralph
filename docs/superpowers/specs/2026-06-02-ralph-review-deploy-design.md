# Ralph Review And Deploy Design

Date: 2026-06-02

## Summary

Add two Ralph commands with separate responsibilities:

- `ralph review`: local branch review loop. It does not use GitHub APIs and does not require an existing PR.
- `ralph deploy`: remote PR and CI loop. It uses `gh` to create a PR to `main`, watch CI, and repair CI failures until green.

The split keeps review usable inside an unpublished worktree while reserving GitHub operations for deployment.

## Goals

- Run a local Codex review/fix loop for the current branch until the branch is mergeable.
- Use GPT-5.5 with xhigh reasoning and priority service tier for all Ralph review/deploy Codex sessions.
- Require Superpowers review discipline inside the review loop:
  - `$use-gpt55-subagents`
  - `$superpowers:requesting-code-review`
  - `$superpowers:receiving-code-review`
- Provide a final report before each Ralph session terminates.
- Keep `ralph deploy` aligned with the existing `$superpowers:finishing-a-development-branch` and `$pr` workflows.
- Preserve worktrees during deploy so the user can continue PR iteration.

## Non-Goals

- Do not create a PR during `ralph review`.
- Do not call GitHub APIs during `ralph review`.
- Do not merge PRs automatically.
- Do not clean up or delete worktrees from `ralph deploy`.
- Do not use review loops as a replacement for CI.
- Do not broaden `ralph build` behavior beyond its current story execution role.

## Current Repository Context

Ralph currently exposes `build`, `prd`, `overview`, `ping`, `log`, and `install` through `bin/ralph`. Build execution is delegated to `.agents/ralph/loop.sh`.

The fork already has post-build review plumbing in `.agents/ralph/loop.sh`:

- `REVIEW_CMD` and `REVIEW_MAX_ROUNDS` defaults.
- `run_review_agent`.
- `render_review_prompt`.
- `run_review_gate`.
- tests that assert the review prompt includes `$use-gpt55-subagents`, `$superpowers:requesting-code-review`, and `$superpowers:receiving-code-review`.

However, there is no separate `ralph review` command, and `loop.sh` currently accepts only `build` and `prd` modes.

## Command Architecture

### `ralph review`

`ralph review` performs local branch review only.

It must:

- Refuse to run on `main`, `master`, or `staging`.
- Refuse to run on detached HEAD.
- Resolve a local base ref without GitHub API:
  - prefer local `main`;
  - fallback to `origin/main`;
  - fail if neither exists.
- Refuse to run when the current branch has no diff against the base ref.
- Run up to 25 review/fix rounds by default.
- Write `.ralph/review-report.md` before exit.
- Exit `0` only when the latest review verdict is mergeable.

### `ralph deploy`

`ralph deploy` performs remote PR and CI completion.

It must:

- Refuse to run on `main`, `master`, or `staging`.
- Refuse to run on detached HEAD.
- Require an authenticated `gh` CLI.
- Run `ralph review` first by default.
- Push the current branch.
- Create a PR to `main`.
- Watch CI until green or blocked.
- When CI fails, collect failed job logs, run a Codex CI-fix loop, push fixes, and watch CI again.
- Run up to 25 deploy iterations by default.
- Write `.ralph/deploy-report.md` before exit.
- Exit `0` only when the PR exists and the latest CI state is green.

## Review Loop Details

### Base Selection

The review loop compares the current branch against a local base ref.

Base selection:

1. Use `main` when `git show-ref --verify refs/heads/main` succeeds.
2. Otherwise use `origin/main` when `git show-ref --verify refs/remotes/origin/main` succeeds.
3. Otherwise fail with a clear message.

The diff range should use merge-base semantics:

```bash
BASE_SHA="$(git merge-base HEAD "$BASE_REF")"
git diff "$BASE_SHA"..HEAD
```

`git diff --quiet "$BASE_SHA"..HEAD` means there is no reviewable branch diff and `ralph review` should fail before launching Codex.

### Review Rounds

Each round creates a prompt under `.ralph/.tmp/` and a log under `.ralph/runs/`.

The review agent command defaults to:

```bash
codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort="xhigh" -c service_tier="priority" -
```

The prompt instructs Codex to:

- act as the orchestrator, not self-review casually;
- use `$use-gpt55-subagents`;
- use `$superpowers:requesting-code-review`;
- use `$superpowers:receiving-code-review` before applying accepted review feedback;
- inspect the branch diff from base to HEAD;
- fix valid Critical and Important findings;
- run focused verification for any fixes;
- preserve scope to the current branch changes;
- output exactly one final signal:
  - `<review>MERGEABLE</review>`
  - `<review>BLOCKED</review>`

Minor-only findings do not block if the final report explains why they were left.

### Stop Conditions

`ralph review` stops successfully when the latest review log contains the final signal:

```text
<review>MERGEABLE</review>
```

It stops unsuccessfully when:

- Codex exits nonzero;
- the latest review signal is `<review>BLOCKED</review>`;
- no review signal is present;
- max rounds are reached;
- a safety preflight fails.

## Deploy Loop Details

### Finish Branch Checks

`ralph deploy` follows the noninteractive equivalent of `$superpowers:finishing-a-development-branch` option 2: push and create a PR.

It must:

- verify tests or configured validation before PR creation;
- detect the workspace state;
- avoid merge, discard, or cleanup paths;
- preserve the worktree.

If the repository does not define a clear test command, deploy records that no project test command was detected and continues only if `ralph review` passed.

### PR Creation

`ralph deploy` follows the `$pr` workflow:

- run `git status --short`;
- confirm the branch is not protected base branch;
- fetch `origin main`;
- verify there are commits or a diff against `origin/main`;
- respect `PR_STANDARDS.md` when present;
- respect `.github/pull_request_template.md` when present;
- run docs artifact guard unless docs are explicitly allowed for the current run;
- push the branch;
- create the PR with `gh pr create --base main --head <branch>`.

The PR title/body must not include AI attribution.

### CI Watch And Repair

After PR creation, deploy watches CI using `gh`.

Expected commands may include:

```bash
gh pr view --json url,headRefName,baseRefName,statusCheckRollup
gh run list --branch "$BRANCH" --limit 10
gh run watch "$RUN_ID"
gh run view "$RUN_ID" --log-failed
```

If CI fails:

1. Save failed logs to `.ralph/runs/`.
2. Generate a CI-fix prompt.
3. Run Codex GPT-5.5 xhigh priority.
4. Require focused local verification for any fix.
5. Commit and push fixes when the worktree changed.
6. Watch CI again.

Deploy exits unsuccessfully if:

- `gh` is missing or unauthenticated;
- PR creation fails;
- CI remains red after 25 iterations;
- Codex cannot fix a failure;
- pushing fixes fails.

## Reports

### `.ralph/review-report.md`

The review report should be written before termination, successful or blocked.

Required fields:

- command: `ralph review`;
- branch;
- base ref;
- base SHA;
- head SHA;
- max rounds;
- rounds run;
- final verdict: `MERGEABLE` or `BLOCKED`;
- changed files reviewed;
- accepted findings fixed;
- findings rejected with brief reasons;
- verification commands and outcomes;
- final review log path;
- blockers, if any.

### `.ralph/deploy-report.md`

The deploy report should be written before termination, successful or blocked.

Required fields:

- command: `ralph deploy`;
- branch;
- PR URL;
- base branch;
- review report path;
- deploy iterations run;
- CI runs watched;
- failed jobs inspected;
- fixes committed and pushed;
- final CI status;
- final verdict: `CI_GREEN` or `BLOCKED`;
- final logs path;
- blockers, if any.

## Configuration

Defaults:

```bash
REVIEW_MAX_ROUNDS=25
DEPLOY_MAX_ROUNDS=25
REVIEW_CMD='codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort="xhigh" -c service_tier="priority" -'
DEPLOY_FIX_CMD='codex exec --yolo --skip-git-repo-check -m gpt-5.5 -c model_reasoning_effort="xhigh" -c service_tier="priority" -'
```

CLI flags:

- `ralph review [n]`
- `ralph review --base <ref>`
- `ralph deploy [n]`
- `ralph deploy --skip-review`
- `ralph deploy --base main`

The numeric argument mirrors `ralph build 1` style and overrides max rounds for that run.

## Prompt Templates

Add separate templates rather than embedding large prompt bodies in shell logic:

- `.agents/ralph/PROMPT_review.txt`
- `.agents/ralph/PROMPT_deploy_fix.txt`

The shell should render templates with placeholders, following the existing build prompt approach.

## Testing Strategy

Add smoke tests around the new commands without invoking real agents:

- `ralph review` refuses `main`.
- `ralph review` refuses detached HEAD.
- `ralph review` refuses no diff against base.
- `ralph review` sends the required Superpowers skill names to the fake review agent.
- `ralph review` writes `.ralph/review-report.md` on mergeable.
- `ralph review` exits nonzero and writes report on blocked/no signal/nonzero agent.
- `ralph deploy` refuses `main`.
- `ralph deploy` requires `gh`.
- `ralph deploy` invokes review unless `--skip-review`.
- `ralph deploy` creates a PR through a fake `gh`.
- `ralph deploy` watches fake CI and exits green.
- `ralph deploy` collects fake failed CI logs and invokes a fake fix agent.
- `ralph deploy` writes `.ralph/deploy-report.md` on success and failure.

Existing tests in `tests/agent-loops.mjs` can be extended because they already fake build and review agents.

## Rollout Plan

1. Add CLI usage and mode parsing for `review` and `deploy`.
2. Extract review prompt body to `PROMPT_review.txt`.
3. Implement `review` mode in `loop.sh`.
4. Add report writing for `review`.
5. Add tests for `ralph review`.
6. Implement `deploy` command orchestration.
7. Add report writing for `deploy`.
8. Add fake-`gh` CI tests for `ralph deploy`.
9. Update README and examples.

## Open Questions Resolved

- `ralph review` should avoid GitHub API: yes.
- `ralph review` should work before a PR exists: yes.
- `ralph review` should block on `main`: yes.
- Default iterations should mirror `ralph build`: yes, 25.
- `ralph deploy` may use `gh`: yes.
- `ralph deploy` should use `$superpowers:finishing-a-development-branch` and `$pr`: yes.
- `ralph deploy` should write a final report before termination: yes.

## References

- Ralph Loop: https://ralphloop.sh/
- Ralph loop docs: https://ralph-cli.dev/docs/core-concepts/ralph-loop/
- Codex review skill pattern: https://raw.githubusercontent.com/steipete/agent-scripts/refs/heads/main/skills/codex-review/SKILL.md
- Codex review loop discussion: https://www.reddit.com/r/codex/comments/1sqf4a0/automating_review_and_fixing_loop/
