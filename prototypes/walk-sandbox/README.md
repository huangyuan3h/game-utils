# Walk Sandbox

Minimal Godot 4.6 prototype for natural on-foot movement.

## What you get

- **Quaternius AnimatedHuman** (CC0) with **Idle / Walk / Run** clips
- **Shift** toggles run (faster + Run clip + quicker footfalls)
- Soft footstep “da-da” WAVs under `assets/sfx/` (placeholder Foley; swap later)
- **Day/night time system**: sun disc, moon, stars, drifting clouds, weather
  - **T** — cycle time speed (`1× → 30× → 120× → 600×`)
  - **Y** — cycle weather (`Clear → Cloudy → Overcast → Rain`)
- Smooth acceleration + yaw turn
- 8-direction move (WASD / arrows)
- **Zoom**: trackpad two-finger scroll (or pinch); mouse wheel / `+` `-` also work
- Larger ground (**120×120**) with more walk spots
- **Realistic terrain map** (procedural heightfield with stronger relief):
  - Biomes: **Sand / Dirt / Grass / Mountain / River**
  - **Flowing rivers**: downhill flow field + animated water shader (ripples, bank foam, Fresnel)
  - **All cells walkable** — height-follow (no mesh trapping)
  - **`MapGenerator.generate_random(seed, opts)`** — abstract random map API
  - **G** calls `TerrainMap.generate_random()` for a new map
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
