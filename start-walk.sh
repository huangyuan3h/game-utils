#!/usr/bin/env bash
# Launch the Walk Sandbox Godot prototype.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/prototypes/walk-sandbox"
GODOT_APP="/Applications/Godot.app"
GODOT_BIN="$GODOT_APP/Contents/MacOS/Godot"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "error: Godot not found at $GODOT_APP"
  echo "Install Godot 4.6+ or update GODOT_BIN in start-walk.sh"
  exit 1
fi

# First run: import assets (GLB) headlessly, then open editor/play.
echo "Importing project assets..."
"$GODOT_BIN" --path "$PROJECT" --headless --import --quit-after 3 >/tmp/walk-sandbox-import.log 2>&1 || true

echo "Starting Walk Sandbox (F5 in editor also works)..."
exec "$GODOT_BIN" --path "$PROJECT"
