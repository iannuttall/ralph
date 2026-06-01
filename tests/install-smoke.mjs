import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const repoRoot = path.resolve(new URL("..", import.meta.url).pathname);
const tempRoot = mkdtempSync(path.join(tmpdir(), "ralph-install-"));

try {
  const installDir = path.join(tempRoot, "share", "ralph");
  const binDir = path.join(tempRoot, "bin");
  const install = spawnSync("bash", [path.join(repoRoot, "install.sh")], {
    cwd: repoRoot,
    stdio: "inherit",
    env: {
      ...process.env,
      RALPH_SOURCE_DIR: repoRoot,
      RALPH_INSTALL_DIR: installDir,
      RALPH_BIN_DIR: binDir,
      RALPH_SKIP_NPM_INSTALL: "1",
    },
  });
  if (install.status !== 0) {
    process.exit(install.status ?? 1);
  }

  const help = spawnSync(path.join(binDir, "ralph"), ["--help"], {
    cwd: tempRoot,
    stdio: "inherit",
  });
  if (help.status !== 0) {
    process.exit(help.status ?? 1);
  }
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}

console.log("Install smoke test passed.");
