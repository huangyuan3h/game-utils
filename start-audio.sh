#!/usr/bin/env bash
# Launch the game-utils audio interactive menu.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SHELL_DIR="$ROOT/shell"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv not found. Install: https://docs.astral.sh/uv/"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  exit 1
fi

cd "$SHELL_DIR"
uv sync --quiet
exec uv run gu-audio menu
