# Walk Sandbox

Minimal Godot 4.6 prototype for natural on-foot movement.

## What you get

- **Quaternius AnimatedHuman** (CC0) with **Idle / Walk / Run** clips
- Hold **Shift** to run (faster + Run clip + quicker footfalls)
- Soft footstep “da-da” WAVs under `assets/sfx/` (placeholder Foley; swap later)
- Smooth acceleration + yaw turn
- 8-direction move (WASD / arrows)
- Four colored spots to walk onto
- Fallback: static `walker.glb` + light bob if FBX import fails

## Run

```bash
./start-walk.sh
```

Or open this folder in Godot 4.6+ and press **F5**.

## Assets

| File | Source | License |
|------|--------|---------|
| `assets/models/quaternius/AnimatedHuman.fbx` | Quaternius via civ-iso-godot | CC0 |
| `assets/models/walker.glb` / `settler.glb` | Blender scripts in civ-iso-godot | project art |

## Goal

Control one person and walk naturally across the ground to different spots.
