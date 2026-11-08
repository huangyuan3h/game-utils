# game-utils audio shell

Unified CLI to generate **SFX** and **BGM** for games.

## Quick start

From the **repo root** (recommended):

```bash
./start-audio.sh
```

On macOS you can also double-click `start-audio.command` in Finder.

Or from `shell/`:

```bash
cd shell
uv sync
uv run gu-audio          # interactive menu
uv run gu-audio doctor
uv run gu-audio sfx generate coin
uv run gu-audio bgm status
```

## Commands

### SFX (realistic collections — preferred)

```bash
uv run gu-audio sfx needs
uv run gu-audio sfx collections
uv run gu-audio sfx open --need footsteps
uv run gu-audio sfx open --collection sonniss-gdc
# after you download a zip:
uv run gu-audio sfx import ~/Downloads/some-pack.zip --name sonniss-demo
uv run gu-audio sfx library
```

Procedural beeps (`sfx generate`) are kept only as placeholders.

### BGM (ACE-Step 1.5)

```bash
uv run gu-audio bgm setup          # clone + uv sync (large download)
uv run gu-audio bgm ui             # Gradio on http://localhost:7860
uv run gu-audio bgm api            # REST API on http://localhost:8001
uv run gu-audio bgm generate --prompt "calm 8-bit adventure loop, 90 BPM"
```

## Backends

| Area | Backend | Needs |
|------|---------|-------|
| SFX | `builtin` (default) | Python only |
| SFX | `jsfxr` | Node.js + npm |
| SFX | `rfxgen` | `rfxgen` binary on PATH |
| BGM | `acestep` | `uv`, GPU recommended, disk for models |
