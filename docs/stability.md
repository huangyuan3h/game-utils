# Stability and release verification

Verified on 2026-11-21 · macOS 26.6.2 arm64 · Godot 4.6.2.stable.

Current release: **v0.2.0**. This is a hand-maintained ledger for the shared base. Update it whenever a check or package result changes.

## Status

| Surface | Result |
|---------|--------|
| Quality gate (`./start.sh check`) | Pass: 96 addon files in sync, 34 pytest, 4 content tables + 1 localization CSV, 661 Godot assertions across 9 suites, 30-frame smoke |
| CI (GitHub Actions, Linux headless) | Pass: run `44877053861` on `main` |
| Scaffold (`gu init`) | Pass: generated project validates 3 content tables, 62 starter assertions, 30-frame smoke |
| macOS package | Pass: `build/macos/walk-sandbox.zip`, 61 MB, ad-hoc signed `com.example.walksandbox` |
| Packaged content | Pass: exported app reports `tables=dialogue,items,quests,resources rows=10` |
| Packaged smoke | Pass: 60 headless frames, no script errors |

## Reproduce

```bash
./start.sh check

# New project: scaffold, then run the same gate against it.
./start.sh init /tmp/guest --name "Guest"
(cd shell && uv run gu check --project /tmp/guest)

# macOS package. --out is resolved against the repo root.
./start.sh export --preset macOS --out build/macos/walk-sandbox.zip
unzip -q build/macos/walk-sandbox.zip -d build/macos/unpacked
BIN="build/macos/unpacked/Walk Sandbox.app/Contents/MacOS/Walk Sandbox"
"$BIN" --headless -- --content-check
"$BIN" --headless --quit-after 60
```

Without export templates, the project data pack can still be verified:

```bash
godot --headless --path prototypes/walk-sandbox --export-pack macOS build/pck/game.pck
godot --headless --main-pack build/pck/game.pck -- --content-check
```

`--content-check` is handled by `prototypes/walk-sandbox/scripts/main.gd`, prints the loaded tables and row counts, and quits. It is the regression test for JSON tables surviving `export_filter="all_resources"`.

## What is verified

- Shared addons and the walk-sandbox copy are byte-identical.
- Every quest, dialogue, item, and resource row loads from `data/content/`, including nested objectives and dialogue nodes.
- Every authored content string has a `zh` translation; the content suite fails on a missing key.
- The player, camera, interaction, quest, dialogue, save, and HUD paths run headless without script errors.
- The starter scene contains a playable `GuPlayer`, camera rig, guide NPC, quest HUD, and interaction prompt; interacting with the guide completes the sample quest.
- Runtime navmesh baking works from the real terrain mesh, and the enemy sample patrols, chases, attacks, takes player strikes, dies, and respawns.
- A release macOS build starts, reads its packaged content, and survives a 60-frame headless smoke.

## Known boundaries

- NavMesh bakes the ground mesh only. Props, rocks, and trees do not carve holes, and enemy avoidance is disabled.
- The enemy is a reference loop (patrol / chase / attack / death / respawn) without loot, XP, or an animation state machine.
- Combat and AI tuning has unit coverage, not a long manual playtest.
- The macOS build is ad-hoc signed and not notarized. `com.example.walksandbox` is a placeholder bundle id.
- Export templates live in the local Godot install (`~/Library/Application Support/Godot/export_templates/4.6.2.stable/`), not in this repo.
- `build/` is gitignored; produced packages are not archived.

## Release checklist

- [x] Quality gate green
- [x] CI green on Linux headless
- [x] `gu init` starter passes the same gate
- [x] macOS package exports and reads packaged content
- [x] Manual playtest of combat, navigation, and saves
- [x] Version bump and git tag (`v0.2.0`)
- [ ] Real bundle id and signing identity (only needed for distribution)
