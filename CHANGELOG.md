# Changelog

## 0.2.0 — 2026-11-21

First tagged development baseline of the shared game skeleton.

### Added

- Playable starter scaffold: `GuPlayer`, camera rig, guide NPC, quest HUD, interaction prompt, and save wiring.
- Content tables under `data/content/` for quests, dialogue, items, and resource nodes, with schemas, localization keys, and a validation step in `gu check`.
- Runtime navmesh baking from the terrain ground mesh and a navmesh-driven enemy sample with patrol, chase, attack, death, and respawn.
- Player combat loop: health, hurtbox/hitbox, `Space` strike, death and respawn.
- Export presets for macOS and Linux, plus a packaged-build `--content-check`.
- `docs/stability.md` verification ledger.

### Changed

- Character controller, locomotion, IK, tools, and character audio moved from the prototype into `gu_gameplay/character/`.
- Headless test runner split into per-domain suites under `prototypes/walk-sandbox/tests/suites/`.
- `gu init` renders every `*.tmpl` with the project name and bundle id.

### Fixed

- Player stats now save and restore with the player saveables.
- `gu export --out` resolves relative paths from the repository root.
- Export presets enable ETC2 ASTC for macOS universal builds.

## 0.1.0

Initial development snapshot (untagged).
