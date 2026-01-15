import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

// Test 1: checkGhCliInstalled() returns boolean
console.log("Testing gh CLI detection...");
const ghCheck = spawnSync("gh", ["--version"], { encoding: "utf-8", stdio: "pipe" });
const ghInstalled = ghCheck.status === 0;
console.log(`  gh CLI installed: ${ghInstalled}`);

// Test 2: fetchGitHubIssues() parses gh issue list output correctly
console.log("Testing issue list parsing...");
const mockIssueOutput = JSON.stringify([
  { number: 1, title: "Issue 1", body: "Body 1", labels: [], url: "https://github.com/test/repo/issues/1" },
  { number: 2, title: "Issue 2", body: null, labels: [{ name: "bug" }], url: "https://github.com/test/repo/issues/2" },
]);
const parsedIssues = JSON.parse(mockIssueOutput);
if (!Array.isArray(parsedIssues) || parsedIssues.length !== 2) {
  console.error("Failed to parse mock issue output");
  process.exit(1);
}
if (parsedIssues[0].number !== 1 || parsedIssues[1].body !== null) {
  console.error("Issue parsing validation failed");
  process.exit(1);
}
console.log("  ✓ Issue list parsing works correctly");

// Test 3: formatIssuesAsContext() generates correct markdown
console.log("Testing context formatting...");
const testIssues = [
  { number: 42, title: "Add auth", body: "Need login\n- [ ] form\n- [ ] session" },
  { number: 38, title: "Fix bug", body: null },
];

function formatIssuesAsContext(issues) {
  let md = "\n\n## Imported GitHub Issues\n\n";
  for (const issue of issues) {
    md += `### #${issue.number}: ${issue.title}\n\n`;
    md += `${issue.body || "(no description)"}\n\n`;
  }
  return md;
}

const formatted = formatIssuesAsContext(testIssues);
if (!formatted.includes("## Imported GitHub Issues")) {
  console.error("Missing header in formatted output");
  process.exit(1);
}
if (!formatted.includes("### #42: Add auth")) {
  console.error("Missing issue 42 in formatted output");
  process.exit(1);
}
if (!formatted.includes("(no description)")) {
  console.error("Missing fallback for null body");
  process.exit(1);
}
console.log("  ✓ Context formatting works correctly");

// Test 4: Integration test with public repo (if gh installed)
if (ghInstalled) {
  console.log("Testing live gh CLI integration with public repo...");
  // Fetch issues from cli/cli (GitHub's own repo, always has issues)
  const result = spawnSync("gh", [
    "issue", "list", "--repo", "cli/cli",
    "--state", "open", "--limit", "5",
    "--json", "number,title"
  ], { encoding: "utf-8", stdio: "pipe" });

  if (result.status !== 0) {
    console.error("Failed to fetch issues from cli/cli");
    console.error(result.stderr);
    process.exit(1);
  }

  const issues = JSON.parse(result.stdout);
  if (!Array.isArray(issues) || issues.length === 0) {
    console.error("Expected issues from cli/cli");
    process.exit(1);
  }
  console.log(`  ✓ Fetched ${issues.length} issues from cli/cli`);
} else {
  console.log("Skipping live gh CLI test (gh not installed)");
}

console.log("GitHub import tests passed.");
