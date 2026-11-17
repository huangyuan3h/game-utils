class_name WorldBeacon
extends Interactable
## Interactive world beacon / campfire landmark that can be lit or extinguished and saved.

signal lit_changed(beacon: WorldBeacon, lit: bool)

const SFX_LIT_PATH := "res://addons/gu_core/audio/sfx/protoss_open.wav"
const SFX_UNLIT_PATH := "res://addons/gu_core/audio/sfx/protoss_back.wav"

@export var is_lit: bool = false
@export var beacon_index: int = 1
@export var biome_name: String = ""
@export var accent_color: Color = Color(0.24, 0.88, 1.0)

var _crystal_mat: StandardMaterial3D = null
var _crystal_mesh: MeshInstance3D = null
var _light: OmniLight3D = null
var _label: Label3D = null
var _sfx_player: AudioStreamPlayer3D = null
var _bob_time: float = 0.0
var _visuals_ready: bool = false


func _ready() -> void:
	interaction_radius = 1.9
	super._ready()
	_ensure_visuals()
	_apply_lit_visuals()


func _process(delta: float) -> void:
	if _crystal_mesh == null:
		return
	_bob_time += delta
	var bob := sin(_bob_time * 2.4 + float(beacon_index)) * (0.06 if is_lit else 0.015)
	_crystal_mesh.position.y = 1.02 + bob
	_crystal_mesh.rotation.y += delta * (1.2 if is_lit else 0.25)


func configure(p_id: String, p_index: int, p_biome_name: String, p_color: Color) -> void:
	interaction_id = p_id
	beacon_index = p_index
	biome_name = p_biome_name
	accent_color = p_color
	name = "Beacon_%d" % p_index
	_ensure_visuals()
	_apply_lit_visuals()


func set_lit(lit: bool, play_sfx: bool = false) -> void:
	var changed := (is_lit != lit)
	is_lit = lit
	_ensure_visuals()
	_apply_lit_visuals()
	if play_sfx:
		_play_toggle_sfx(is_lit)
	if changed:
		lit_changed.emit(self, is_lit)


func _on_interact(_actor: Node) -> void:
	set_lit(not is_lit, true)


func _ensure_visuals() -> void:
	if _visuals_ready:
		return
	_visuals_ready = true

	var base := MeshInstance3D.new()
	base.name = "Pedestal"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.56
	cyl.height = 0.62
	cyl.radial_segments = 8
	base.mesh = cyl
	base.position = Vector3(0.0, 0.31, 0.0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.26, 0.28, 0.32)
	base_mat.roughness = 0.85
	base.material_override = base_mat
	add_child(base)

	_crystal_mesh = MeshInstance3D.new()
	_crystal_mesh.name = "BeaconCore"
	var prism := SphereMesh.new()
	prism.radius = 0.22
	prism.height = 0.48
	prism.radial_segments = 6
	prism.rings = 2
	_crystal_mesh.mesh = prism
	_crystal_mesh.position = Vector3(0.0, 1.02, 0.0)
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.roughness = 0.35
	_crystal_mat.metallic = 0.15
	_crystal_mesh.material_override = _crystal_mat
	add_child(_crystal_mesh)

	_light = OmniLight3D.new()
	_light.name = "BeaconLight"
	_light.position = Vector3(0.0, 1.15, 0.0)
	_light.omni_range = 9.0
	_light.omni_attenuation = 1.4
	add_child(_light)

	_label = Label3D.new()
	_label.name = "BeaconLabel"
	_label.position = Vector3(0.0, 1.65, 0.0)
	_label.font_size = 38
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

	_sfx_player = AudioStreamPlayer3D.new()
	_sfx_player.name = "BeaconSfx"
	_sfx_player.bus = &"SFX"
	_sfx_player.max_distance = 30.0
	add_child(_sfx_player)


func _apply_lit_visuals() -> void:
	prompt_text = "Extinguish Beacon %d" % beacon_index if is_lit else "Light Beacon %d" % beacon_index
	if _crystal_mat != null:
		if is_lit:
			_crystal_mat.albedo_color = accent_color.lightened(0.2)
			_crystal_mat.emission_enabled = true
			_crystal_mat.emission = accent_color
			_crystal_mat.emission_energy_multiplier = 2.4
		else:
			_crystal_mat.albedo_color = Color(0.38, 0.40, 0.44)
			_crystal_mat.emission_enabled = true
			_crystal_mat.emission = accent_color * 0.14
			_crystal_mat.emission_energy_multiplier = 0.5

	if _light != null:
		_light.light_color = accent_color
		_light.light_energy = 2.4 if is_lit else 0.0
		_light.visible = is_lit

	if _label != null:
		var status := "LIT" if is_lit else "UNLIT"
		var b_txt := biome_name if biome_name != "" else "?"
		_label.text = "Beacon %d (%s)\n[%s]" % [beacon_index, b_txt, status]
		_label.modulate = accent_color.lightened(0.45) if is_lit else Color(0.84, 0.87, 0.92)


func _play_toggle_sfx(lit: bool) -> void:
	if _sfx_player == null:
		return
	var path := SFX_LIT_PATH if lit else SFX_UNLIT_PATH
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx_3d"):
		am.call("play_sfx_3d", _sfx_player, stream, -4.0, 0.96, 1.04)
	else:
		_sfx_player.bus = &"SFX"
		_sfx_player.stream = stream
		_sfx_player.volume_db = -4.0
		_sfx_player.play()
