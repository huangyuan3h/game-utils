# game-utils CLI (`gu`)

Python CLI behind the repo-root `./start.sh`. Use the root script unless you are already in this directory.

```bash
./start.sh play            # from the repo root
uv run gu play             # equivalent, from shell/
```

Setup, if you call `uv` yourself:

```bash
cd shell
uv sync --group dev
```

## Commands

### Test Game

```bash
uv run gu play                                   # run prototypes/walk-sandbox
uv run gu play --editor                          # open it in the Godot editor
uv run gu play --dry-run                         # print the Godot command
```

With no subcommand, `gu` opens the home menu (play test game / audio tools). `gu menu` is the audio menu only.

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
