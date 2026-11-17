class_name TerrainBuildContext
extends RefCounted
## Explicit build context passed from TerrainMap to terrain/water/prop mesh builders.
## Eliminates direct private-field coupling on the TerrainMap node.

var data: MapData
var height_tex: ImageTexture
var field_tex: ImageTexture
var mouths: Array[Dictionary] = []
var clear_spots: Array[Vector2] = []


func _init(p_data: MapData = null) -> void:
	data = p_data


func sample_height(x: float, z: float) -> float:
	return data.sample_height(x, z) if data != null else 0.0


func sample_biome(x: float, z: float) -> int:
	return data.sample_biome(x, z) if data != null else 0


func sample_slope(x: float, z: float) -> float:
	return data.sample_slope(x, z) if data != null else 0.0


func idx(x: int, z: int) -> int:
	return data.idx(x, z) if data != null else 0


func pack_mouth_uniforms(target: String) -> Dictionary:
	## Pack up to 8 river mouth / spillway descriptors for sea or lake shaders.
	const MAX_MOUTHS := 8
	var pos_dir: Array[Vector4] = []
	var info: Array[Vector4] = []
	var count := 0
	for m in mouths:
		if str(m.get("target", "")) != target:
			continue
		if count >= MAX_MOUTHS:
			break
		var p: Vector2 = m["pos"]
		var d: Vector2 = m["dir"]
		pos_dir.append(Vector4(p.x, p.y, d.x, d.y))
		info.append(Vector4(
			float(m.get("half_w", 1.5)),
			float(m.get("plume_len", 5.5)),
			float(m.get("mode", 1.0)),
			float(m.get("strength", 1.0))
		))
		count += 1
	while pos_dir.size() < MAX_MOUTHS:
		pos_dir.append(Vector4.ZERO)
		info.append(Vector4.ZERO)
	return {
		"count": count,
		"pos_dir": pos_dir,
		"info": info,
	}
