# game-utils CLI (`gu` / `gu-audio`)

Unified Python CLI for game audio pipelines, Godot shared addon/project management, data table validation, and headless CI checks.

## Setup

```bash
cd shell
uv sync --group dev
```

## Commands

### Godot Project & Addon Scaffolding

```bash
uv run gu init ~/Projects/my-game --name "My Game"   # scaffold starter Godot 4.6 project
uv run gu addons sync --prune                        # sync godot/addons/ -> prototypes/walk-sandbox/addons/
uv run gu check                                      # run addons parity + pytest + Godot import/tests/smoke
uv run gu export --preset macOS --out dist/game.dmg --dry-run
```

### Assets Sync, Audit & Credits

```bash
uv run gu sync --dry-run                             # preview output/ audio sync -> Godot assets/audio/
uv run gu sync                                       # copy audio + update ATTRIBUTION.json
uv run gu assets audit --target ../prototypes/walk-sandbox --write
uv run gu assets credits --target ../prototypes/walk-sandbox
```

### Data Tables & Localization

```bash
uv run gu data validate path/to/data
uv run gu data build path/to/data --out path/to/godot/data
```

`gu data build` also writes `i18n_manifest.json` and a keep `.import` next to each localization CSV. The locale columns in those CSVs are the languages shown in Settings.

### SFX & BGM

```bash
uv run gu sfx needs
uv run gu sfx collections
uv run gu sfx import ~/Downloads/some-pack.zip --name sonniss-demo
uv run gu bgm status
```
