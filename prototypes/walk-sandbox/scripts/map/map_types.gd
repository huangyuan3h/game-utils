extends RefCounted
## Shared map constants and biome ids. No other map scripts depend on this file.
class_name MapTypes

enum Biome { SEA, LAKE, RIVER, SAND, DIRT, GRASS, MOUNTAIN, MEADOW, FOREST, CLIFF, ALPINE }

enum Landform { COASTAL_VALLEY, TERRACED_HIGHLANDS, FJORD_HEADLAND, ROLLING_ARCHIPELAGO }

const DEFAULT_SIZE := 120.0
const DEFAULT_GRID := 144
const DEFAULT_BASE := 1.0
const DEFAULT_MAX_H := 11.5
const DEFAULT_MAX_STEP := 0.78
const DEFAULT_WATER_Y := 0.95

## Human-scale streams: ~1.3 m at spring, ~4.4 m at mouth (wadeable creek -> small river)
## with a deeper central thalweg so channels read as real flowing depth.
const RIVER_HALF_W_SRC := 0.65
const RIVER_HALF_W_MOUTH := 2.2
const RIVER_DEPTH_SRC := 0.52
const RIVER_DEPTH_MOUTH := 1.12
const RIVER_BANK_MUL := 2.4
## Keep sea-bound rivers clear of lake shores (world units beyond lake radius).
const LAKE_RIVER_GAP := 12.0


static func biome_name(b: int) -> String:
	match b:
		Biome.SEA:
			return "Sea"
		Biome.LAKE:
			return "Lake"
		Biome.RIVER:
			return "River"
		Biome.SAND:
			return "Sand"
		Biome.DIRT:
			return "Dirt"
		Biome.GRASS:
			return "Grass"
		Biome.MOUNTAIN:
			return "Mountain"
		Biome.MEADOW:
			return "Meadow"
		Biome.FOREST:
			return "Forest"
		Biome.CLIFF:
			return "Cliff"
		Biome.ALPINE:
			return "Alpine"
		_:
			return "?"


static func landform_name(lf: int) -> String:
	match lf:
		Landform.COASTAL_VALLEY:
			return "Coastal Valley"
		Landform.TERRACED_HIGHLANDS:
			return "Terraced Highlands"
		Landform.FJORD_HEADLAND:
			return "Fjord Headland"
		Landform.ROLLING_ARCHIPELAGO:
			return "Rolling Archipelago"
		_:
			return "Coastal Valley"
