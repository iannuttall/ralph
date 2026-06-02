# Ralph CLI Examples

Basic usage:

```bash
ralph prd "A lightweight uptime monitor (Hono app), deployed on Cloudflare, with email alerts via AWS SES"
ralph build 1 # one Ralph run
ralph build 1 --no-commit # one Ralph run
ralph overview
```

Review current branch:

```bash
ralph review
ralph review 5 --base main
cat .ralph/review-report.md
```

Deploy current branch:

```bash
ralph deploy
ralph deploy 25 --base main
ralph deploy 1 --skip-review
cat .ralph/deploy-report.md
```

Agent override:

```bash
ralph ping --agent=codex # check agent is installed + responsive
ralph build 1 --agent=codex # one Ralph run
ralph build 1 --agent=claude # one Ralph run
ralph build 1 --agent=droid # one Ralph run
```

PRD overrides:

```bash
ralph prd "..." --out .agents/tasks/prd-api.json
ralph build 1 --prd .agents/tasks/prd-api.json # one Ralph run
ralph overview --prd .agents/tasks/prd-api.json
```

Progress override:

```bash
ralph build 1 --progress .ralph/progress-api.md # one Ralph run
```

Install templates:

```bash
ralph install
ralph install --force
```

Install skills:

```bash
ralph install --skills
```
