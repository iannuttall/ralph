# Ralph CLI Examples

Basic usage:

```bash
ralph prd "A lightweight uptime monitor (Hono app), deployed on Cloudflare, with email alerts via AWS SES"
ralph build 1 # one Ralph run
ralph build 1 --no-commit # one Ralph run
ralph overview
```

Agent override:

```bash
ralph ping --agent=codex # check agent is installed + responsive
ralph build 1 --agent=codex # one Ralph run
ralph build 1 --agent=claude # one Ralph run
ralph build 1 --agent=droid # one Ralph run
ralph build 1 --agent=opencode # one Ralph run
ralph build 1 --agent=copilot # one Ralph run
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
