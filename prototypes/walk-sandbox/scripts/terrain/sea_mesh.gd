extends RefCounted
## Coastal sea plane and its shader parameters.

var _map: Node


func build(map: Node) -> void:
	_map = map
	_build_sea()


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(_map.map_size * 1.05, _map.map_size * 1.05)
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
	_map._water.mesh = plane
	_map._water.position = Vector3(0.0, _map.water_y, 0.0)
	_map._water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := load("res://shaders/water_sea.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("half_world", Vector2(_map.map_size * 0.5, _map.map_size * 0.5))
	mat.set_shader_parameter("height_tex", _map._height_tex)
	mat.set_shader_parameter("water_y", _map.water_y)
	mat.set_shader_parameter("height_min", _map._h_min)
	mat.set_shader_parameter("height_span", maxf(_map._h_max - _map._h_min, 0.001))
	mat.set_shader_parameter("shallow_col", Vector3(0.30, 0.70, 0.65))
	mat.set_shader_parameter("deep_col", Vector3(0.03, 0.22, 0.40))
	mat.set_shader_parameter("foam_col", Vector3(0.97, 0.99, 0.97))
	_map._water.material_override = mat


