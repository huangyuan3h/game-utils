# Walk Sandbox

Reference Godot 4.6 3D prototype integrating `gu_core` and `gu_gameplay` on top of procedural terrain, weather, locomotion, quests, and resource harvesting.

## Controls

- **WASD / Arrows**: 8-direction movement
- **Shift**: toggle run
- **E**: interact with world beacons and harvestable resource nodes
- **1 / 2 / 3 / 4** (`F` repeat, `X` cancel): Gather / Mine / Chop / Build actions
- **Scroll / Pinch / `+` `-`**: camera zoom
- **T / Y / L**: cycle time speed / weather / trigger lightning
- **G / V**: generate new random map / cycle landform archetype
- **F3**: toggle tactical HUD overlay
- **`` ` `` (Backtick)**: toggle `DevConsole` (`tp_spawn`, `light_all`, `time`, `weather`, `give_item`)
- **ESC**: pause menu / save & load slots / settings & keybindings

## Architecture Highlights

- **Shared Plugins**: `addons/gu_core` and `addons/gu_gameplay` synced from `godot/addons/` via `./start.sh addons sync`.
- **World & Terrain**: `MapGenerator`, `MapData`, `WorldLocator`, `TerrainBuildContext`, and `WorldSpawner` / `WorldCommands`.
- **Gameplay Loop**: `WorldBeacon` + `EventBus` -> `QuestTracker` + `FlagStore`; `ResourceNode` -> `HealthComponent` -> `PoolService`-backed `WorldPickup` -> `InventoryContainer` + `SaveService`.

## Run & Test

From the repository root:

```bash
./start.sh play
# headless quality gate (addon parity, pytest, Godot tests, smoke):
./start.sh check
```
