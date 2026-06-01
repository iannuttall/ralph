import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = path.join(repoRoot, "bin", "ralph");

function run(cmd, args, options = {}) {
  const result = spawnSync(cmd, args, { stdio: "inherit", ...options });
  if (result.status !== 0) {
    throw new Error(`Command failed: ${cmd} ${args.join(" ")}`);
  }
}

function setupTempProject() {
  const base = mkdtempSync(path.join(tmpdir(), "ralph-real-"));
  mkdirSync(path.join(base, ".agents", "tasks"), { recursive: true });
  mkdirSync(path.join(base, ".ralph"), { recursive: true });

  const prd = {
    version: 1,
    project: "Real Agent Smoke Test",
    qualityGates: [],
    stories: [
      {
        id: "US-001",
        title: "Create baseline file",
        status: "open",
        dependsOn: [],
        description:
          "As a user, I want a baseline file so the repo has an artifact.",
        acceptanceCriteria: [
          "File \"docs/US-001.txt\" exists with the exact text \"US-001 complete\"",
          "Example: open docs/US-001.txt -> \"US-001 complete\"",
          "Negative case: missing file -> failure",
        ],
      },
      {
        id: "US-002",
        title: "Add second artifact",
        status: "open",
        dependsOn: ["US-001"],
        description:
          "As a user, I want a second artifact to verify multi-story iteration.",
        acceptanceCriteria: [
          "File \"docs/US-002.txt\" exists with the exact text \"US-002 complete\"",
          "Example: open docs/US-002.txt -> \"US-002 complete\"",
          "Negative case: missing file -> failure",
        ],
      },
    ],
  };

  writeFileSync(
    path.join(base, ".agents", "tasks", "prd.json"),
    `${JSON.stringify(prd, null, 2)}\n`,
  );

  const agents = `# AGENTS\n\n## Validation\n- For this repo, verify changes with shell checks only.\n- Use commands like: test -f <file>, grep -q \"text\" <file>\n- Do NOT run package manager tests.\n`;

  writeFileSync(path.join(base, "AGENTS.md"), agents);

  run("git", ["init"], { cwd: base });
  run("git", ["config", "user.email", "ralph@example.com"], { cwd: base });
  run("git", ["config", "user.name", "ralph"], { cwd: base });

  return base;
}

function assertAllStoriesComplete(prdPath) {
  const prd = JSON.parse(readFileSync(prdPath, "utf-8"));
  const stories = Array.isArray(prd.stories) ? prd.stories : [];
  const remaining = stories.filter(
    (story) => String(story.status || "open").toLowerCase() !== "done",
  );
  if (remaining.length > 0) {
    throw new Error(
      `Some stories remain incomplete: ${remaining.map((s) => s.id).join(", ")}`,
    );
  }
}

function assertNoCommits(cwd) {
  const result = spawnSync("git", ["rev-list", "--count", "HEAD"], { cwd, encoding: "utf-8" });
  if (result.status !== 0) {
    return;
  }
  const count = Number(result.stdout.trim() || "0");
  if (count > 0) {
    throw new Error(`Expected no commits, found ${count}.`);
  }
}

function runForAgent(agent) {
  console.log(`\n=== Real agent test: ${agent} ===`);
  const projectRoot = setupTempProject();
  const env = { ...process.env };

  try {
    run(process.execPath, [cliPath, "build", "2", `--agent=${agent}`], {
      cwd: projectRoot,
      env,
    });

    const prdPath = path.join(projectRoot, ".agents", "tasks", "prd.json");
    assertAllStoriesComplete(prdPath);
    assertNoCommits(projectRoot);

    const progressPath = path.join(projectRoot, ".ralph", "progress.md");
    if (!existsSync(progressPath)) {
      throw new Error("Progress log not created.");
    }

    console.log(`Agent ${agent} passed.`);
  } finally {
    rmSync(projectRoot, { recursive: true, force: true });
  }
}

const agents = ["codex", "claude", "droid"];
for (const agent of agents) {
  runForAgent(agent);
}

console.log("Real agent integration tests passed.");
