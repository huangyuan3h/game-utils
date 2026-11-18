#!/usr/bin/env bash
# Single entry point for game-utils.
#
#   ./start.sh                 home menu (play test game / audio tools)
#   ./start.sh play            launch the Walk Sandbox test game
#   ./start.sh play --editor   open that project in the Godot editor
#   ./start.sh <gu args>       any other gu command (check, addons sync, init, ...)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SHELL_DIR="$ROOT/shell"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv not found. Install: https://docs.astral.sh/uv/"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi

cd "$SHELL_DIR"
exec uv run gu "$@"
