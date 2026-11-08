# game-utils

Indie game asset entry point — docs, audio tooling shell, and small Godot prototypes.

## What's in this repo

| Path | Purpose |
|------|---------|
| `docs/` | Concepts, research, architecture notes |
| `shell/` | `gu-audio` CLI — realistic SFX collections + BGM (ACE-Step) launcher |
| `prototypes/walk-sandbox/` | Godot 4.6 walk demo (8-direction character control) |
| `start-audio.sh` | Launch audio interactive menu |
| `start-walk.sh` | Open Walk Sandbox in Godot |

## Quick start

**Audio shell**

```bash
./start-audio.sh
# or
cd shell && uv sync && uv run gu-audio
```

**Walk sandbox** (requires Godot 4.6+)

```bash
./start-walk.sh
```

## Notes

- Generated audio packs go under `output/` (gitignored).
- SFX focus is curated realistic libraries, not procedural beeps.
- Character GLBs in the walk sandbox are copied from the author's `civ-iso-godot` project for prototyping.
