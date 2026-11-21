# game-utils — current architecture (for agents)

Read this before editing. It describes the repo as it is. `docs/architecture.md` is an older language-choice note, not the current tree. `docs/concept.md` is product intent.

## What this repo is

A Godot 4.6 shared game skeleton plus a Python CLI that scaffolds projects, syncs addons, checks quality, and drives audio asset tooling.

The only user entry is `./start.sh` at the repo root. It forwards every argument to `gu` (`shell/` via `uv`). `start.command` is only the macOS Finder double-click of that same script. Do not add another root launcher.

```bash
./start.sh                 # home menu: 1 play test game, 2 audio tools
./start.sh play            # run prototypes/walk-sandbox (manual test)
./start.sh play --editor   # open that project in the Godot editor
./start.sh check           # addon parity + pytest + Godot headless
./start.sh addons sync --prune
```

Direct equivalent, from `shell/`: `uv run gu <same args>`.

## Layout and source of truth

| Path | Role | Edit? |
|------|------|--------|
| `godot/addons/gu_core/` | Shared runtime plugin. Source of truth. | Yes |
| `godot/addons/gu_gameplay/` | Shared gameplay classes. Source of truth. No autoloads. | Yes |
| `godot/templates/starter/` | Files copied by `gu init` into a new game. Playable plane with `GuPlayer` + `CameraRig`, a content-driven sample quest, guide dialogue, interaction prompt, and HUD. | Yes, when the scaffold should change |
| `prototypes/walk-sandbox/` | Reference 3D game and the default test target. | Yes, for game-specific behavior |
| `prototypes/walk-sandbox/addons/` | Generated copy of `godot/addons/`. | No. Sync it. |
| `shell/src/game_utils_audio/` | Python CLI package. Name is historical; the command is `gu`. | Yes |
| `shell/tests/` | pytest for the CLI. | Yes |
| `output/` | Generated / imported audio. Gitignored. | No |
| `shell/vendors/` | Cloned tools (ACE-Step). Gitignored. | No |
| `docs/` | Product and research notes. | Only when the decision itself changes |

After changing `godot/addons/`, run `./start.sh addons sync --prune`. `./start.sh check` fails if the walk-sandbox copy has drifted (`shell/tests/test_quality.py`).

## Godot runtime

Engine: Godot 4.6, Forward Plus. Binary resolution (`find_godot_binary`): `--godot`, else `$GODOT_BIN`, else `godot` / `godot4` on `PATH`, else `/Applications/Godot.app/Contents/MacOS/Godot`.

`gu_core` registers these autoloads when the plugin is enabled (`godot/addons/gu_core/gu_core_plugin.gd`). Walk Sandbox also lists them in `project.godot`:

`SettingsStore`, `InputRouter`, `AudioManager`, `SaveService`, `UIRouter`, `GameFlow`, `GameClock`, `EventBus`, `PoolService`, `DevConsole`.

| Area | Files | Job |
|------|--------|-----|
| Flow | `gu_core/flow/game_flow.gd`, `game_clock.gd`, `scene_loader.gd` | Title / pause / world registration, gameplay time |
| UI | `gu_core/ui/ui_router.gd`, `save_slots_panel.gd`, `keybind_list.gd` | Toasts, modals, transitions, save slots, keybinds |
| Input | `gu_core/input/input_router.gd` | Action stack and rebinding |
| Audio | `gu_core/audio/audio_manager.gd` | 3D SFX pool and buses |
| Save | `gu_core/save/save_service.gd` | Saveables, migrations, `.bak` |
| Settings | `gu_core/settings/settings_store.gd` | Persisted settings, including locale |
| Events / pools / debug | `events/event_bus.gd`, `pool/pool_service.gd`, `debug/dev_console.gd`, `debug/gu_log.gd` | Bus, node pool, backtick console |
| Data | `gu_core/data/data_table_loader.gd`, `gu_core/data/content_database.gd`, `gu_core/i18n/translation_catalog.gd` | JSON tables, indexed content rows, CSV locales |
| Interaction | `gu_gameplay/interaction/` | `Interactable`, `Interactor` |
| Character | `gu_gameplay/character/` | `GuPlayer`, locomotion, IK, tools, character audio. Art/audio paths are injected by the scene |
| Camera / actions | `camera/camera_rig.gd`, `actions/character_action_*.gd` | Follow camera, Gather/Mine/Chop/Build/Strike |
| Surface audio | `audio/surface_resolver.gd`, `surface_audio_bank.gd` | Footstep surface → clip |
| Stats / inventory | `stats/stat_set.gd`, `inventory/` | Stats, items, container |
| Quests | `quests/flag_store.gd`, `quest_def.gd`, `quest_tracker.gd` | Flags and quest state |
| Content | `content/game_content.gd` | Builds `QuestDef`, `DialogueDef`, `ItemDef`, and resource specs from `data/content/` |
| Dialogue | `dialogue/dialogue_def.gd`, `dialogue_runner.gd`, `dialogue_box.gd`, `dialogue_interactable.gd` | Data, runner, UI |
| AI | `ai/agent.gd`, `ai/enemy_body.gd`, `ai/navmesh_baker.gd` | Patrol/chase/leash state, navmesh-driven enemy sample, runtime ground bake |
| World entities | `world/health_component.gd`, `world_pickup.gd`, `resource_node.gd` | Damage, drops, harvest nodes |
| HUD | `ui/gameplay_hud.gd`, `stat_bar.gd`, `inventory_panel.gd`, `quest_hud.gd` | In-game panels |

`gu_gameplay` does not register autoloads. Game scenes instance or `preload` its classes.

## Walk Sandbox (the test game)

`prototypes/walk-sandbox`, main scene `res://scenes/main.tscn`, script `scripts/main.gd`.

`main.gd` is the world coordinator: terrain, sky/weather, player, camera rig, title/pause/settings, quests, dialogue, saves. It calls `GameFlow.register_world` and `GameFlow.enter_title`.

Game-specific code lives under `prototypes/walk-sandbox/scripts/`, not in the addons (the shared character stack lives in `gu_gameplay/character/`):

| Dir | Owns |
|-----|------|
| `scripts/map/`, `scripts/terrain/`, `scripts/map_generator.gd`, `scripts/terrain_map.gd` | Procedural heightfield, rivers, lakes, landforms, meshes |
| `scripts/world/` | Beacon, spawner, dev-console world commands |
| `data/content/` | Quests, dialogue, items, and resource nodes as JSON tables, built into typed definitions by `gu_gameplay/content/game_content.gd`. Text is authored in English and translated by `data/ui_i18n.csv` |
| `scripts/ui/` | Title, pause, settings, debug overlay |
| `scripts/sky_time.gd`, `weather_*.gd` | Time of day, weather, lightning |

Controls are documented in `prototypes/walk-sandbox/README.md`. Headless gameplay tests: `prototypes/walk-sandbox/tests/test_runner.gd` (run by `gu check`, not by `gu play`). The runner orders suites from `tests/suites/`; shared fixtures live in `tests/support/test_suite_base.gd`. Add new assertions to the matching suite, not to the runner.

`./start.sh play` resolves that project, runs a best-effort headless `--import`, then replaces the process with Godot `--path` (the game). `--editor` opens the editor. Implementation: `shell/src/game_utils_audio/play.py`.

## Python CLI

Package: `shell/src/game_utils_audio/`. Console script: `gu` only. Entry: `cli.py` → `main`. With no subcommand, `gu` runs `launcher.py` (home). `menu` is audio-only (`menu.py`).

| Command | Module | What it does |
|---------|--------|----------------|
| `play` | `play.py` | Launch Walk Sandbox for manual testing |
| (none) / home menu | `launcher.py` | Play game, or enter audio menu |
| `menu` | `menu.py` | SFX collections, import, ACE-Step |
| `doctor` | `cli.py` | Backend availability JSON |
| `sfx` | `sfx/` | Collections and library first. `generate` is a placeholder beep |
| `bgm` | `bgm/acestep.py` | Clone ACE-Step, start UI/API, generate |
| `sync` | `sync.py` | Copy `output/` audio into the Godot project and write attribution |
| `addons sync` | `godot_project.py` | Copy `godot/addons/{gu_core,gu_gameplay}` into a project. `--prune` deletes stale files |
| `init` | `godot_project.py` | Copy `godot/templates/starter` + addons into a new directory |
| `assets audit` / `assets credits` | `assets_audit.py` | License scan, `CREDITS.md` |
| `data validate` / `data build` | `data_pipeline.py` | CSV/JSON tables and `*_i18n.csv`. Schema `refs` catch orphan ids, `i18n` columns must exist as translation keys, and `{token}` sets must match across locales. Build writes JSON, `i18n_manifest.json`, and a keep `.import` beside each localization CSV. Locale columns are the languages Settings shows |
| `check` | `quality.py` | Addon parity, pytest, data validation, Godot import, `tests/test_runner.gd`, 30-frame smoke |
| `export` | `quality.py` | Headless export from `export_presets.cfg` (`--preset macOS` or `--preset Linux` in Walk Sandbox) |

Paths (`paths.py`): repo root is two parents above the package file. Default Godot project is `prototypes/walk-sandbox`. Audio output is `output/sfx` and `output/bgm`.

Audio policy (`docs/sfx-direction.md`): prefer imported realistic packs. Builtin / jsfxr / rFXGen are placeholder synths. Do not grow that UX unless asked.

## Task router

| Task | Touch |
|------|--------|
| Shared singleton, save, input, UI shell, audio bus | `godot/addons/gu_core/`, then addon sync |
| Reusable interaction, inventory, quest, dialogue, HUD widget | `godot/addons/gu_gameplay/`, then addon sync |
| Enemy AI or navigation | `godot/addons/gu_gameplay/ai/`, then addon sync |
| Terrain, player, weather, sandbox UI | `prototypes/walk-sandbox/scripts/` and its `scenes/` |
| New empty game or starter content | `godot/templates/starter/`, then `./start.sh init` |
| Launch / CLI flags | `play.py`, `launcher.py`, `cli.py`, `start.sh` |
| Data tables or languages | `data_pipeline.py` and the project's `data/` |
| Quest, dialogue, item, or resource content | the project's `data/content/*.json`; add UI text keys to `data/ui_i18n.csv` |
| Release verification or packaging | `docs/stability.md`, then the project's `export_presets.cfg` |
| Failing `gu check` | parity → sync addons; pytest → `shell/tests/`; Godot script error → the `.gd` named in the log |

## Invariants

- One shell entry: `start.sh`. Do not restore `start-walk.sh`, `start-audio.sh`, or a second `.command`.
- Addon edits happen in `godot/addons/`, then sync. Never patch only the prototype copy.
- Walk Sandbox is the manual test bed (`play`) and the default target of `check`, `sync`, and `addons sync`.
- `gu play` is for a human in the editor/player. Automated coverage stays in `gu check`.
- Code, comments, and commit messages stay in English.
- Do not commit `output/`, `shell/vendors/`, `.godot/`, or secrets.
