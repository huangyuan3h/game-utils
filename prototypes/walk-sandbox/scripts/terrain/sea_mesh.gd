extends RefCounted
## Coastal sea plane and its shader parameters.


func build(ctx: TerrainBuildContext) -> Dictionary:
	if ctx == null or ctx.data == null:
		return {"mesh": null, "material": null, "position": Vector3.ZERO}
	var data := ctx.data
	var plane := PlaneMesh.new()
	plane.size = Vector2(data.size * 1.05, data.size * 1.05)
	plane.subdivide_width = 64
	plane.subdivide_depth = 64

	var shader := load("res://shaders/water_sea.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("half_world", Vector2(data.size * 0.5, data.size * 0.5))
	mat.set_shader_parameter("sea_edge", data.sea_edge)
	mat.set_shader_parameter("height_tex", ctx.height_tex)
	mat.set_shader_parameter("water_y", data.water_y)
	mat.set_shader_parameter("height_min", data.h_min)
	mat.set_shader_parameter("height_span", maxf(data.h_max - data.h_min, 0.001))
	mat.set_shader_parameter("shallow_col", Vector3(0.28, 0.66, 0.60))
	mat.set_shader_parameter("deep_col", Vector3(0.04, 0.23, 0.39))
	mat.set_shader_parameter("foam_col", Vector3(0.95, 0.98, 0.97))
	mat.set_shader_parameter("river_shallow_col", Vector3(0.24, 0.60, 0.54))
	mat.set_shader_parameter("river_deep_col", Vector3(0.04, 0.21, 0.31))

	var packed: Dictionary = ctx.pack_mouth_uniforms("sea")
	mat.set_shader_parameter("mouth_count", int(packed["count"]))
	mat.set_shader_parameter("mouth_pos_dir", packed["pos_dir"])
	mat.set_shader_parameter("mouth_info", packed["info"])

	return {
		"mesh": plane,
		"material": mat,
		"position": Vector3(0.0, data.water_y, 0.0),
	}
