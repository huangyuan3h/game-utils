extends Node3D
## Sandbox: realistic terrain biomes + walk/run + sky/time + zoom.

@onready var _player: CharacterBody3D = $Player
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _hud: Label = $CanvasLayer/HUD
@onready var _markers_root: Node3D = $Markers
@onready var _sky_time: Node3D = $SkyTime
@onready var _terrain: Node3D = $TerrainMap

const MAP_SIZE := 120.0
const CAM_OFFSET := Vector3(0, 7.5, 9.5)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.12

const MARKER_COLORS := [
	Color(0.9, 0.25, 0.25),
	Color(0.25, 0.75, 0.35),
	Color(0.25, 0.45, 0.95),
	Color(0.95, 0.75, 0.2),
	Color(0.85, 0.35, 0.85),
	Color(0.35, 0.85, 0.85),
]

const MARKER_POS := [
	Vector3(18, 0, 0),
	Vector3(-18, 0, 0),
	Vector3(0, 0, 18),
	Vector3(0, 0, -18),
	Vector3(28, 0, 28),
	Vector3(-28, 0, -28),
]

const REACH_DIST := 1.6

var _zoom: float = 1.0


func _ready() -> void:
	# Wait one frame so TerrainMap._ready has rebuilt heights
	await get_tree().process_frame
	_player.terrain = _terrain
	_place_player_on_terrain()
	_spawn_markers()
	_bind_zoom_keys()
	_bind_regen()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		_set_zoom(_zoom + pan.delta.y * 0.045)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		_set_zoom(_zoom / maxf(mag.factor, 0.01))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom - ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom + ZOOM_STEP)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_in"):
		_set_zoom(_zoom - ZOOM_STEP)
	elif event.is_action_pressed("zoom_out"):
		_set_zoom(_zoom + ZOOM_STEP)
	elif event.is_action_pressed("regen_terrain"):
		_regen_terrain()


func _process(delta: float) -> void:
	var target := _player.global_position + CAM_OFFSET * _zoom
	$CameraPivot.global_position = $CameraPivot.global_position.lerp(target, 1.0 - exp(-6.0 * delta))
	_camera.look_at(_player.global_position + Vector3(0, 0.9, 0), Vector3.UP)
	_clamp_player_to_map()
	_update_hud()


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)


func _bind_zoom_keys() -> void:
	_bind("zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_bind("zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])


func _bind_regen() -> void:
	_bind("regen_terrain", [KEY_G])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _terrain_height(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("sample_height"):
		return float(_terrain.call("sample_height", x, z))
	return 0.0


func _place_player_on_terrain() -> void:
	var h := _terrain_height(0.0, 0.0)
	_player.global_position = Vector3(0.0, h + 0.02, 0.0)
	_player.velocity = Vector3.ZERO


func _spawn_markers() -> void:
	for c in _markers_root.get_children():
		c.queue_free()
	for i in MARKER_POS.size():
		var pos: Vector3 = MARKER_POS[i]
		var h := _terrain_height(pos.x, pos.z)
		var marker := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.45
		cyl.height = 0.12
		marker.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = MARKER_COLORS[i % MARKER_COLORS.size()]
		mat.emission_enabled = true
		mat.emission = MARKER_COLORS[i % MARKER_COLORS.size()] * 0.35
		marker.material_override = mat
		marker.position = Vector3(pos.x, h + 0.08, pos.z)
		marker.name = "Marker_%d" % (i + 1)

		var label := Label3D.new()
		var bname := "?"
		if _terrain != null and _terrain.has_method("biome_name_at"):
			bname = str(_terrain.call("biome_name_at", pos.x, pos.z))
		label.text = "Spot %d\n%s" % [i + 1, bname]
		label.position = Vector3(0, 0.95, 0)
		label.font_size = 42
		label.modulate = Color(1, 1, 1)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.add_child(label)
		_markers_root.add_child(marker)


func _regen_terrain() -> void:
	## Random map via abstracted MapGenerator entry on TerrainMap.
	if _terrain != null and _terrain.has_method("generate_random"):
		var data: Dictionary = _terrain.call("generate_random", -1, {"relief": 1.0})
		print("Generated map seed=", data.get("seed"), " h=[", data.get("h_min"), ",", data.get("h_max"), "]")
		_place_player_on_terrain()
		_spawn_markers()


func _clamp_player_to_map() -> void:
	var half := MAP_SIZE * 0.5 - 1.0
	var p := _player.global_position
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	_player.global_position = p


func _update_hud() -> void:
	var reached: Array[String] = []
	for i in MARKER_POS.size():
		var mp: Vector3 = MARKER_POS[i]
		var h := _terrain_height(mp.x, mp.z)
		var d := _player.global_position.distance_to(Vector3(mp.x, h, mp.z))
		if d <= REACH_DIST:
			reached.append("Spot %d" % (i + 1))
	var status := "Spot: " + (", ".join(reached) if reached else "—")
	var biome := "?"
	if _terrain != null and _terrain.has_method("biome_name_at"):
		biome = str(_terrain.call(
			"biome_name_at",
			_player.global_position.x,
			_player.global_position.z
		))
	var sky_line := ""
	if _sky_time != null and _sky_time.has_method("get_hud_line"):
		sky_line = str(_sky_time.call("get_hud_line"))
	_hud.text = (
		"Terrain (all walkable, more relief) · G = random map\n"
		+ "WASD · Shift toggle run · trackpad zoom (%.0f%%)\n" % round(_zoom * 100.0)
		+ "Biome: %s · %s\n" % [biome, status]
		+ sky_line
	)
