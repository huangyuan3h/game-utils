extends RefCounted
## Shared map constants and biome ids. No other map scripts depend on this file.
class_name MapTypes

enum Biome { SEA, LAKE, RIVER, SAND, DIRT, GRASS, MOUNTAIN }

const DEFAULT_SIZE := 120.0
const DEFAULT_GRID := 96
const DEFAULT_BASE := 1.0
const DEFAULT_MAX_H := 11.0
const DEFAULT_MAX_STEP := 1.15
const DEFAULT_WATER_Y := 0.95

## River scale: ~3.4 m wide at source, ~9.6 m at mouth.
const RIVER_HALF_W_SRC := 1.7
const RIVER_HALF_W_MOUTH := 4.8
const RIVER_DEPTH_SRC := 0.55
const RIVER_DEPTH_MOUTH := 1.25
const RIVER_BANK_MUL := 3.4
## Keep sea-bound rivers clear of lake shores (world units beyond lake radius).
const LAKE_RIVER_GAP := 16.0
