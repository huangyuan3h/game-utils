# game-utils

Shared Godot 4.6 game skeleton, reusable gameplay addons, and Python asset/engineering CLI.

## Repository Layout

| Path | Purpose |
|------|---------|
| `godot/addons/gu_core/` | Core runtime plugin: `GameFlow`, `UIRouter` (Toast / Modal / Transition / SaveSlots / KeybindList), `InputRouter` (stack + rebinding), `AudioManager` (3D SFX pool), `SaveService` (Saveables + migrations + `.bak`), `SettingsStore`, `EventBus`, `PoolService`, `SceneLoader`, `DataTableLoader`, `GuLog`, `DevConsole` |
| `godot/addons/gu_gameplay/` | Reusable gameplay plugin: `Interactable` / `Interactor`, `CameraRig`, `CharacterAction*`, `SurfaceResolver` / `SurfaceAudioBank`, `StatSet`, `InventoryContainer` / `ItemDef`, `FlagStore` / `QuestTracker`, `DialogueDef` / `DialogueRunner` / `DialogueBox`, `HealthComponent` / `WorldPickup` / `ResourceNode` |
| `godot/templates/starter/` | Full Godot 4.6 starter template scaffolded by `gu init` |
| `prototypes/walk-sandbox/` | Reference 3D sandbox integrating procedural terrain, weather, beacons, quests, resource harvesting, and full UI |
| `shell/` | Python CLI (`gu`) for the test-game launcher, SFX/BGM, asset sync and audit, data pipelines, starter scaffolding, and CI checks |
| `docs/` | Architecture notes, audio direction, and concept docs |
| `AGENTS.md` | Current architecture map for agents and contributors |

## Quick Start

One entry point. Requires `uv` and, for the game, Godot 4.6+.

```bash
./start.sh                 # home menu: play the test game, or open audio tools
./start.sh play            # launch Walk Sandbox immediately
./start.sh play --editor   # open Walk Sandbox in the Godot editor
```

**Create a new Godot game from the shared skeleton**

```bash
./start.sh init ~/Projects/my-game --name "My Game"
```

**Sync shared addons and run quality checks**

```bash
./start.sh addons sync --prune
./start.sh check
```

Agents and contributors: read `AGENTS.md` before editing. It is the current architecture. `docs/architecture.md` is an older language-choice note.
