#!/usr/bin/env bash
set -euo pipefail

repo="${RALPH_REPO:-aslaii/ralph}"
ref="${RALPH_REF:-feat/codex-review-loop}"
install_dir="${RALPH_INSTALL_DIR:-$HOME/.local/share/ralph}"
bin_dir="${RALPH_BIN_DIR:-$HOME/.local/bin}"
source_dir="${RALPH_SOURCE_DIR:-}"
skip_npm_install="${RALPH_SKIP_NPM_INSTALL:-0}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ralph install: missing required command: $1" >&2
    exit 1
  fi
}

copy_source() {
  local src="$1"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  cp -R "$src"/. "$install_dir"/
  rm -rf "$install_dir/.git"
}

if [ -n "$source_dir" ]; then
  if [ ! -f "$source_dir/package.json" ]; then
    echo "ralph install: RALPH_SOURCE_DIR must point to repo root" >&2
    exit 1
  fi
  copy_source "$source_dir"
else
  need_cmd curl
  need_cmd tar
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  archive_url="${RALPH_ARCHIVE_URL:-https://github.com/${repo}/archive/refs/heads/${ref}.tar.gz}"

  echo "Downloading ralph from $archive_url"
  curl -fsSL "$archive_url" -o "$tmp_dir/ralph.tar.gz"
  tar -xzf "$tmp_dir/ralph.tar.gz" -C "$tmp_dir"
  src_dir="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$src_dir" ] || [ ! -f "$src_dir/package.json" ]; then
    echo "ralph install: downloaded archive did not contain package.json" >&2
    exit 1
  fi
  copy_source "$src_dir"
fi

chmod +x "$install_dir/bin/ralph"

if [ "$skip_npm_install" != "1" ]; then
  need_cmd npm
  echo "Installing npm dependencies"
  npm install --omit=dev --no-audit --no-fund --prefix "$install_dir"
fi

mkdir -p "$bin_dir"
ln -sfn "$install_dir/bin/ralph" "$bin_dir/ralph"

echo "ralph installed to $install_dir"
echo "binary linked at $bin_dir/ralph"
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
  echo "Add this to PATH if needed: export PATH=\"$bin_dir:\$PATH\""
fi
