# game-utils

Shared Godot 4.6 game skeleton, reusable gameplay addons, and Python asset/engineering CLI.

## Repository Layout

| Path | Purpose |
|------|---------|
| `godot/addons/gu_core/` | Core runtime plugin: `GameFlow`, `UIRouter` (Toast / Modal / Transition / SaveSlots / KeybindList), `InputRouter` (stack + rebinding), `AudioManager` (3D SFX pool), `SaveService` (Saveables + migrations + `.bak`), `SettingsStore`, `EventBus`, `PoolService`, `SceneLoader`, `DataTableLoader`, `GuLog`, `DevConsole` |
| `godot/addons/gu_gameplay/` | Reusable gameplay plugin: `Interactable` / `Interactor`, `CameraRig`, `CharacterAction*`, `SurfaceResolver` / `SurfaceAudioBank`, `StatSet`, `InventoryContainer` / `ItemDef`, `FlagStore` / `QuestTracker`, `HealthComponent` / `WorldPickup` / `ResourceNode` |
| `godot/templates/starter/` | Full Godot 4.6 starter template scaffolded by `gu init` |
| `prototypes/walk-sandbox/` | Reference 3D sandbox integrating procedural terrain, weather, beacons, quests, resource harvesting, and full UI |
| `shell/` | Unified Python CLI (`gu` / `gu-audio`) for SFX/BGM, asset sync & audit, data pipelines, starter scaffolding, and CI checks |
| `docs/` | Architecture notes, audio direction, and concept docs |

## Quick Start

**Create a new Godot game from the shared skeleton**

```bash
cd shell && uv sync --group dev
uv run gu init ~/Projects/my-game --name "My Game"
```

**Sync shared addons & run full quality checks**

```bash
cd shell
uv run gu addons sync --prune
uv run gu check
```

**Launch Walk Sandbox** (requires Godot 4.6+)

```bash
./start-walk.sh
```

**Audio Shell**

```bash
./start-audio.sh
```
