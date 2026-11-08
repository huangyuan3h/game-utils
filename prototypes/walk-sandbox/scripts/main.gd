extends Node3D
## Sandbox world: ground + walk targets + follow camera.

@onready var _player: CharacterBody3D = $Player
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _hud: Label = $CanvasLayer/HUD
@onready var _markers_root: Node3D = $Markers

const MARKER_COLORS := [
	Color(0.9, 0.25, 0.25),
	Color(0.25, 0.75, 0.35),
	Color(0.25, 0.45, 0.95),
	Color(0.95, 0.75, 0.2),
]

const MARKER_POS := [
	Vector3(6, 0, 0),
	Vector3(-6, 0, 0),
	Vector3(0, 0, 6),
	Vector3(0, 0, -6),
]

const REACH_DIST := 1.35


func _ready() -> void:
	_spawn_markers()
	_update_hud()


func _process(_delta: float) -> void:
	# Soft follow
	var target := _player.global_position + Vector3(0, 10, 12)
	$CameraPivot.global_position = $CameraPivot.global_position.lerp(target, 0.08)
	_camera.look_at(_player.global_position + Vector3(0, 0.8, 0), Vector3.UP)
	_update_hud()


func _spawn_markers() -> void:
	for i in MARKER_POS.size():
		var marker := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.45
		cyl.height = 0.15
		marker.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = MARKER_COLORS[i]
		mat.emission_enabled = true
		mat.emission = MARKER_COLORS[i] * 0.35
		marker.material_override = mat
		marker.position = MARKER_POS[i] + Vector3(0, 0.08, 0)
		marker.name = "Marker_%d" % (i + 1)

		var label := Label3D.new()
		label.text = "Spot %d" % (i + 1)
		label.position = Vector3(0, 0.7, 0)
		label.font_size = 48
		label.modulate = Color(1, 1, 1)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.add_child(label)

		_markers_root.add_child(marker)


func _update_hud() -> void:
	var reached: Array[String] = []
	for i in MARKER_POS.size():
		var d := _player.global_position.distance_to(MARKER_POS[i])
		if d <= REACH_DIST:
			reached.append("Spot %d" % (i + 1))
	var status := "Standing on: " + (", ".join(reached) if reached else "—")
	_hud.text = "Walk Sandbox\nWASD / Arrow keys · 8 directions\nWalk onto the colored spots\n%s" % status
