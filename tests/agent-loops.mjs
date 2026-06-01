import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname);
const cliPath = path.join(repoRoot, "bin", "ralph");

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    console.error(`Command failed: ${cmd} ${args.join(" ")}`);
    process.exit(result.status ?? 1);
  }
}

function readJson(file) {
  return JSON.parse(readFileSync(file, "utf-8"));
}

function commandExists(cmd) {
  const result = spawnSync(`command -v ${cmd}`, { shell: true, stdio: "ignore" });
  return result.status === 0;
}

function initGit(cwd) {
  run("git", ["init"], { cwd });
  run("git", ["config", "user.email", "ralph@example.com"], { cwd });
  run("git", ["config", "user.name", "ralph"], { cwd });
}

function setupTempProject() {
  const base = mkdtempSync(path.join(tmpdir(), "ralph-smoke-"));
  mkdirSync(path.join(base, ".agents", "tasks"), { recursive: true });
  mkdirSync(path.join(base, ".ralph"), { recursive: true });
  const prd = {
    version: 1,
    project: "Smoke Test",
    qualityGates: [],
    stories: [
      {
        id: "US-001",
        title: "Smoke Test Story",
        status: "open",
        dependsOn: [],
        acceptanceCriteria: [
          "Example: input -> output",
          "Negative case: bad input -> error",
        ],
      },
    ],
  };
  writeFileSync(
    path.join(base, ".agents", "tasks", "prd.json"),
    `${JSON.stringify(prd, null, 2)}\n`,
  );
  return base;
}

function runReviewGateCase({ name, reviewLines, expectedExit, expectedStoryStatus, env = {}, expectPrompt = false }) {
  const projectRoot = setupTempProject();
  const fakeBuild = path.join(projectRoot, "fake-build-agent.sh");
  const fakeReview = path.join(projectRoot, "fake-review-agent.sh");
  const reviewPrompt = path.join(projectRoot, "review-prompt.md");
  const prdPath = path.join(projectRoot, ".agents", "tasks", "prd.json");

  writeFileSync(
    fakeBuild,
    [
      "#!/usr/bin/env bash",
      "cat >/dev/null",
      "echo '<promise>COMPLETE</promise>'",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  writeFileSync(
    fakeReview,
    [
      "#!/usr/bin/env bash",
      `cat > ${JSON.stringify(reviewPrompt)}`,
      ...reviewLines,
      "",
    ].join("\n"),
    { mode: 0o755 },
  );

  try {
    const result = spawnSync(process.execPath, [cliPath, "build", "1", "--no-commit", "--prd", prdPath], {
      cwd: projectRoot,
      encoding: "utf-8",
      env: {
        ...process.env,
        AGENT_CMD: fakeBuild,
        REVIEW_CMD: fakeReview,
        ...env,
      },
    });

    if (result.status !== expectedExit) {
      console.error(`${name} failed: expected exit ${expectedExit}, got ${result.status}.`);
      console.error(result.stdout);
      console.error(result.stderr);
      process.exit(1);
    }

    if (expectPrompt && !existsSync(reviewPrompt)) {
      console.error(`${name} failed: review agent was not invoked.`);
      process.exit(1);
    }

    if (existsSync(reviewPrompt)) {
      const prompt = readFileSync(reviewPrompt, "utf-8");
      if (!prompt.includes("$superpowers:requesting-code-review")) {
        console.error(`${name} failed: missing requesting-code-review instruction.`);
        process.exit(1);
      }
      if (!prompt.includes("$superpowers:receiving-code-review")) {
        console.error(`${name} failed: missing receiving-code-review instruction.`);
        process.exit(1);
      }
    }

    const story = readJson(prdPath).stories[0];
    if (story.status !== expectedStoryStatus) {
      console.error(`${name} failed: expected story ${expectedStoryStatus}, got ${story.status}.`);
      console.error(result.stdout);
      console.error(result.stderr);
      process.exit(1);
    }
  } finally {
    rmSync(projectRoot, { recursive: true, force: true });
  }
}

function runGitGuardCase({ name, buildLines, expectedMessage }) {
  const projectRoot = setupTempProject();
  const fakeBuild = path.join(projectRoot, "fake-build-agent.sh");
  const fakeReview = path.join(projectRoot, "fake-review-agent.sh");
  const prdPath = path.join(projectRoot, ".agents", "tasks", "prd.json");

  initGit(projectRoot);
  writeFileSync(
    fakeBuild,
    [
      "#!/usr/bin/env bash",
      "set -e",
      "cat >/dev/null",
      ...buildLines,
      "",
    ].join("\n"),
    { mode: 0o755 },
  );
  writeFileSync(
    fakeReview,
    [
      "#!/usr/bin/env bash",
      "cat >/dev/null",
      "echo '<review>MERGEABLE</review>'",
      "",
    ].join("\n"),
    { mode: 0o755 },
  );

  try {
    const result = spawnSync(process.execPath, [cliPath, "build", "1", "--prd", prdPath], {
      cwd: projectRoot,
      encoding: "utf-8",
      env: {
        ...process.env,
        AGENT_CMD: fakeBuild,
        REVIEW_CMD: fakeReview,
      },
    });
    const output = `${result.stdout}\n${result.stderr}`;
    if (result.status !== 1) {
      console.error(`${name} failed: expected exit 1, got ${result.status}.`);
      console.error(output);
      process.exit(1);
    }
    if (!output.includes(expectedMessage)) {
      console.error(`${name} failed: missing guard output ${JSON.stringify(expectedMessage)}.`);
      console.error(output);
      process.exit(1);
    }
    const story = readJson(prdPath).stories[0];
    if (story.status !== "open") {
      console.error(`${name} failed: expected story open, got ${story.status}.`);
      process.exit(1);
    }
    const staged = spawnSync("git", ["diff", "--cached", "--name-only"], {
      cwd: projectRoot,
      encoding: "utf-8",
    });
    if (/^\.ralph\/|^\.agents\/tasks\//m.test(staged.stdout)) {
      console.error(`${name} failed: staged Ralph artifact.`);
      console.error(staged.stdout);
      process.exit(1);
    }
  } finally {
    rmSync(projectRoot, { recursive: true, force: true });
  }
}

const agents = ["codex", "claude", "droid"];
const integration = process.env.RALPH_INTEGRATION === "1";

for (const agent of agents) {
  const projectRoot = setupTempProject();
  try {
    const env = { ...process.env };
    if (!integration) {
      env.RALPH_DRY_RUN = "1";
    } else if (agent === "codex" && !commandExists("codex")) {
      console.log(`Skipping codex integration test (missing codex).`);
      continue;
    } else if (agent === "claude" && !commandExists("claude")) {
      console.log(`Skipping claude integration test (missing claude).`);
      continue;
    } else if (agent === "droid" && !commandExists("droid")) {
      console.log(`Skipping droid integration test (missing droid).`);
      continue;
    }

    run(process.execPath, [cliPath, "build", "1", "--no-commit", `--agent=${agent}`], {
      cwd: projectRoot,
      env,
    });
  } finally {
    rmSync(projectRoot, { recursive: true, force: true });
  }
}

runReviewGateCase({
  name: "Review gate mergeable",
  reviewLines: ["echo '<review>MERGEABLE</review>'"],
  expectedExit: 0,
  expectedStoryStatus: "done",
  expectPrompt: true,
});

runReviewGateCase({
  name: "Review gate final signal wins",
  reviewLines: ["echo '<review>MERGEABLE</review>'", "echo '<review>BLOCKED</review>'"],
  expectedExit: 1,
  expectedStoryStatus: "open",
  expectPrompt: true,
});

runReviewGateCase({
  name: "Review gate blocked",
  reviewLines: ["echo '<review>BLOCKED</review>'"],
  expectedExit: 1,
  expectedStoryStatus: "open",
  expectPrompt: true,
});

runReviewGateCase({
  name: "Review gate no signal",
  reviewLines: ["echo 'review complete but no signal'"],
  expectedExit: 1,
  expectedStoryStatus: "open",
  expectPrompt: true,
});

runReviewGateCase({
  name: "Review gate nonzero",
  reviewLines: ["echo '<review>MERGEABLE</review>'", "exit 2"],
  expectedExit: 1,
  expectedStoryStatus: "open",
  expectPrompt: true,
});

runReviewGateCase({
  name: "Review gate cannot be disabled",
  reviewLines: ["echo '<review>MERGEABLE</review>'"],
  expectedExit: 0,
  expectedStoryStatus: "done",
  env: { REVIEW_AFTER_BUILD: "false" },
  expectPrompt: true,
});

runGitGuardCase({
  name: "Git guard blocks commits",
  buildLines: [
    "echo example > app.txt",
    "git add app.txt",
    "git commit -m 'should not commit'",
    "echo '<promise>COMPLETE</promise>'",
  ],
  expectedMessage: "git commit is disabled",
});

runGitGuardCase({
  name: "Git guard blocks Ralph artifact staging",
  buildLines: [
    "git add .ralph/progress.md",
    "echo '<promise>COMPLETE</promise>'",
  ],
  expectedMessage: "refusing to stage Ralph artifact path",
});

runGitGuardCase({
  name: "Git guard blocks broad staging",
  buildLines: [
    "git add -A",
    "echo '<promise>COMPLETE</promise>'",
  ],
  expectedMessage: "broad git add is disabled",
});

console.log("Agent loop smoke tests passed.");
