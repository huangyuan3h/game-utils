extends Node
## Multi-bus audio manager handling bus volume mapping, BGM crossfades, and pooled UI / 3D SFX playback.

const BUS_MASTER := &"Master"
const BUS_BGM := &"BGM"
const BUS_SFX := &"SFX"
const BUS_AMBIENCE := &"Ambience"
const BUS_UI := &"UI"

const REQUIRED_BUSES := [BUS_BGM, BUS_SFX, BUS_AMBIENCE, BUS_UI]
const SETTING_TO_BUS := {
	"master_volume": BUS_MASTER,
	"bgm_volume": BUS_BGM,
	"sfx_volume": BUS_SFX,
	"ambience_volume": BUS_AMBIENCE,
	"ui_volume": BUS_UI,
}

const UI_POOL_SIZE := 4
const SFX3D_POOL_SIZE := 8
const MUTE_THRESHOLD := 0.001

var _linear_volumes: Dictionary = {
	BUS_MASTER: 1.0,
	BUS_BGM: 0.75,
	BUS_SFX: 0.90,
	BUS_AMBIENCE: 0.85,
	BUS_UI: 0.90,
}

var _bgm_players: Array[AudioStreamPlayer] = []
var _active_bgm_idx: int = 0
var _bgm_tween: Tween = null
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_cursor: int = 0
var _sfx3d_players: Array[AudioStreamPlayer3D] = []
var _sfx3d_cursor: int = 0
var _rng := RandomNumberGenerator.new()
var _shutting_down: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	ensure_buses()
	_setup_players()
	_sync_from_settings_store()


func ensure_buses() -> void:
	for bus_name: StringName in REQUIRED_BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, String(bus_name))
			AudioServer.set_bus_send(idx, String(BUS_MASTER))


func set_bus_volume(bus_name: StringName, linear: float) -> void:
	ensure_buses()
	var clamped := clampf(linear, 0.0, 1.0)
	_linear_volumes[bus_name] = clamped
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var muted := clamped <= MUTE_THRESHOLD
	AudioServer.set_bus_mute(idx, muted)
	AudioServer.set_bus_volume_db(idx, -80.0 if muted else linear_to_db(clamped))


func get_bus_volume(bus_name: StringName) -> float:
	return float(_linear_volumes.get(bus_name, 1.0))


func get_sfx3d_pool_size() -> int:
	return _sfx3d_players.size()


func is_shutting_down() -> bool:
	return _shutting_down


func prepare_shutdown() -> void:
	_shutting_down = true
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	for p in _bgm_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _ui_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _sfx3d_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	var tree := get_tree()
	if tree != null and tree.root != null:
		_stop_audio_recursive(tree.root)


func _stop_audio_recursive(node: Node) -> void:
	if node is AudioStreamPlayer:
		var p := node as AudioStreamPlayer
		p.stop()
		p.stream = null
	elif node is AudioStreamPlayer2D:
		var p2 := node as AudioStreamPlayer2D
		p2.stop()
		p2.stream = null
	elif node is AudioStreamPlayer3D:
		var p3 := node as AudioStreamPlayer3D
		p3.stop()
		p3.stream = null
	for child in node.get_children():
		_stop_audio_recursive(child)


func play_bgm(stream: AudioStream, fade_s: float = 1.0) -> void:
	if _shutting_down:
		return
	if stream == null:
		stop_bgm(fade_s)
		return
	if AudioServer.get_driver_name() == "Dummy":
		return
	if _bgm_players.size() < 2:
		return
	var current := _bgm_players[_active_bgm_idx]
	if current.playing and current.stream == stream:
		return
	var next_idx := 1 - _active_bgm_idx
	var next_player := _bgm_players[next_idx]
	next_player.stream = stream
	next_player.volume_db = -80.0 if fade_s > 0.01 else 0.0
	next_player.play()

	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if fade_s <= 0.01:
		current.stop()
		_active_bgm_idx = next_idx
		return

	_bgm_tween = create_tween()
	_bgm_tween.set_parallel(true)
	_bgm_tween.tween_property(next_player, "volume_db", 0.0, fade_s)
	if current.playing:
		_bgm_tween.tween_property(current, "volume_db", -80.0, fade_s)
	_bgm_tween.set_parallel(false)
	_bgm_tween.tween_callback(func() -> void:
		if is_instance_valid(current):
			current.stop()
	)
	_active_bgm_idx = next_idx


func stop_bgm(fade_s: float = 0.8) -> void:
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	for p in _bgm_players:
		if not p.playing:
			continue
		if fade_s <= 0.01:
			p.stop()
		else:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -80.0, fade_s)
			tw.tween_callback(func() -> void:
				if is_instance_valid(p):
					p.stop()
			)


func play_ui(stream: AudioStream, pitch_jitter: float = 0.0) -> void:
	if _shutting_down or stream == null or _ui_players.is_empty():
		return
	if AudioServer.get_driver_name() == "Dummy":
		return
	var p := _ui_players[_ui_cursor]
	_ui_cursor = (_ui_cursor + 1) % _ui_players.size()
	p.stream = stream
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	p.play()


func play_sfx_3d(
	player: AudioStreamPlayer3D,
	stream: AudioStream,
	volume_db: float = 0.0,
	pitch_min: float = 0.94,
	pitch_max: float = 1.06
) -> void:
	if _shutting_down or player == null or stream == null:
		return
	if AudioServer.get_driver_name() == "Dummy":
		return
	player.bus = BUS_SFX
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = _rng.randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
	player.play()


func play_sfx_at(
	world_pos: Vector3,
	stream: AudioStream,
	volume_db: float = 0.0,
	pitch_min: float = 0.94,
	pitch_max: float = 1.06,
	max_distance: float = 30.0
) -> AudioStreamPlayer3D:
	if _shutting_down or stream == null:
		return null
	_ensure_sfx3d_pool()
	if _sfx3d_players.is_empty():
		return null

	var chosen: AudioStreamPlayer3D = null
	for offset in _sfx3d_players.size():
		var idx := (_sfx3d_cursor + offset) % _sfx3d_players.size()
		var cand := _sfx3d_players[idx]
		if is_instance_valid(cand) and not cand.playing:
			chosen = cand
			_sfx3d_cursor = (idx + 1) % _sfx3d_players.size()
			break

	if chosen == null:
		chosen = _sfx3d_players[_sfx3d_cursor]
		_sfx3d_cursor = (_sfx3d_cursor + 1) % _sfx3d_players.size()

	if chosen.is_inside_tree():
		chosen.global_position = world_pos
	else:
		chosen.position = world_pos
	chosen.bus = BUS_SFX
	chosen.max_distance = maxf(max_distance, 0.5)
	chosen.stream = stream
	chosen.volume_db = volume_db
	chosen.pitch_scale = _rng.randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
	if chosen.is_inside_tree() and AudioServer.get_driver_name() != "Dummy":
		chosen.play()
	return chosen


func _setup_players() -> void:
	if _bgm_players.is_empty():
		for i in 2:
			var bgm := AudioStreamPlayer.new()
			bgm.name = "BGM_%d" % i
			bgm.bus = BUS_BGM
			bgm.volume_db = -80.0
			add_child(bgm)
			_bgm_players.append(bgm)

	if _ui_players.is_empty():
		for i in UI_POOL_SIZE:
			var ui := AudioStreamPlayer.new()
			ui.name = "UI_%d" % i
			ui.bus = BUS_UI
			add_child(ui)
			_ui_players.append(ui)

	_ensure_sfx3d_pool()


func _ensure_sfx3d_pool() -> void:
	if not _sfx3d_players.is_empty():
		return
	for i in SFX3D_POOL_SIZE:
		var sfx := AudioStreamPlayer3D.new()
		sfx.name = "SFX3D_%d" % i
		sfx.bus = BUS_SFX
		sfx.max_distance = 30.0
		sfx.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(sfx)
		_sfx3d_players.append(sfx)


func _sync_from_settings_store() -> void:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		for bus_name: StringName in _linear_volumes:
			set_bus_volume(bus_name, float(_linear_volumes[bus_name]))
		return
	for key: String in SETTING_TO_BUS:
		set_bus_volume(SETTING_TO_BUS[key], float(store.call("get_value", key, 1.0)))
	if store.has_signal("setting_changed") and not store.is_connected("setting_changed", Callable(self, "_on_setting_changed")):
		store.connect("setting_changed", Callable(self, "_on_setting_changed"))
	if store.has_signal("settings_loaded") and not store.is_connected("settings_loaded", Callable(self, "_on_settings_loaded")):
		store.connect("settings_loaded", Callable(self, "_on_settings_loaded"))


func _on_setting_changed(key: String, value: Variant) -> void:
	if SETTING_TO_BUS.has(key):
		set_bus_volume(SETTING_TO_BUS[key], float(value))


func _on_settings_loaded() -> void:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return
	for key: String in SETTING_TO_BUS:
		set_bus_volume(SETTING_TO_BUS[key], float(store.call("get_value", key, 1.0)))
