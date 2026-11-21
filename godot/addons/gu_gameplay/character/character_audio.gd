class_name CharacterAudio
extends Node
## Drives surface-aware character footsteps and nearby water ambience based on locomotion and terrain.

const WALK_STEP_INTERVAL := 0.42
const RUN_STEP_INTERVAL := 0.26
const WATER_NEAR := 14.0
const WATER_FULL := 2.2
const WATER_VOL_DB := -22.0

var surface_bank: SurfaceAudioBank = null
var current_surface: int = SurfaceResolver.SurfaceType.GRASS
var snow_cover: float = 0.0
var _water_loop_path: String = ""

var _feet: AudioStreamPlayer3D = null
var _action_player: AudioStreamPlayer3D = null
var _water_amb: AudioStreamPlayer = null
var _action_streams: Dictionary = {} ## StringName -> AudioStreamWAV
var _step_timer: float = 0.0
var _water_vol: float = 0.0
var _rng := RandomNumberGenerator.new()
var _shutting_down: bool = false


func _exit_tree() -> void:
	_shutting_down = true
	if is_instance_valid(_water_amb):
		_water_amb.stop()
		_water_amb.stream = null
	if is_instance_valid(_feet):
		_feet.stop()
		_feet.stream = null
	if is_instance_valid(_action_player):
		_action_player.stop()
		_action_player.stream = null


func setup(feet_player: AudioStreamPlayer3D, water_loop_path: String = "") -> void:
	_rng.randomize()
	_feet = feet_player
	_water_loop_path = water_loop_path
	_ensure_surface_bank()
	if _feet != null:
		_feet.bus = &"SFX"
		_feet.max_distance = 28.0
		_feet.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_setup_action_sfx()
	_setup_water_ambience()


func play_action_beat(action_id: StringName) -> void:
	if _is_shutting_down() or _action_player == null:
		return
	var stream := _action_streams.get(action_id, null) as AudioStream
	if stream == null:
		return
	var vol_db := -7.5 + _rng.randf_range(-1.0, 0.8)
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx_3d"):
		am.call("play_sfx_3d", _action_player, stream, vol_db, 0.90, 1.12)
	elif AudioServer.get_driver_name() != "Dummy":
		_action_player.bus = &"SFX"
		_action_player.stream = stream
		_action_player.pitch_scale = _rng.randf_range(0.90, 1.12)
		_action_player.volume_db = vol_db
		_action_player.play()


func update_audio(
	loco: CharacterLocomotion,
	terrain: Object,
	world_pos: Vector3,
	delta: float,
	p_snow_cover: float = -1.0
) -> void:
	if loco == null or _is_shutting_down():
		return
	if p_snow_cover >= 0.0:
		snow_cover = p_snow_cover
	current_surface = SurfaceResolver.resolve_at(terrain, world_pos, loco.water_depth, snow_cover)
	_update_footsteps(loco, delta)
	_update_water_ambience(loco, terrain, world_pos, delta)


func _is_shutting_down() -> bool:
	if _shutting_down:
		return true
	var audio_mgr := get_node_or_null("/root/AudioManager")
	return audio_mgr != null and audio_mgr.has_method("is_shutting_down") and bool(audio_mgr.call("is_shutting_down"))


func _ensure_surface_bank() -> void:
	if surface_bank == null:
		surface_bank = SurfaceAudioBank.new()
	if surface_bank.fallback_walk.is_empty() and surface_bank.fallback_run.is_empty():
		surface_bank.load_default_fallbacks()


func _update_footsteps(loco: CharacterLocomotion, delta: float) -> void:
	if loco.swim_amt > 0.55 or loco.speed_xz < 0.4:
		_step_timer = 0.0
		return
	var interval := RUN_STEP_INTERVAL if loco.is_running else WALK_STEP_INTERVAL
	var ref_speed := CharacterLocomotion.RUN_SPEED if loco.is_running else CharacterLocomotion.WALK_SPEED
	interval *= clampf(ref_speed / maxf(loco.speed_xz, 0.1), 0.75, 1.35)
	interval *= lerpf(1.0, 1.55, loco.swim_amt)
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = interval
	_play_footstep(loco.is_running, current_surface, loco.swim_amt)


func _play_footstep(running: bool, surface: int, swim_amt: float) -> void:
	if _feet == null or _is_shutting_down():
		return
	_ensure_surface_bank()
	var stream := surface_bank.get_stream(surface, running, _rng)
	if stream == null:
		return
	var vol_db := (-8.0 if running else -12.0) + _rng.randf_range(-1.0, 1.0)
	if swim_amt > 0.15:
		vol_db -= lerpf(0.0, 10.0, swim_amt)

	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx_3d"):
		am.call("play_sfx_3d", _feet, stream, vol_db, 0.92, 1.08)
	elif AudioServer.get_driver_name() != "Dummy":
		_feet.bus = &"SFX"
		_feet.stream = stream
		_feet.pitch_scale = _rng.randf_range(0.92, 1.08)
		_feet.volume_db = vol_db
		_feet.play()


func _setup_water_ambience() -> void:
	_water_amb = AudioStreamPlayer.new()
	_water_amb.name = "WaterAmbience"
	_water_amb.bus = &"Ambience"
	_water_amb.volume_db = -80.0
	add_child(_water_amb)
	var path := _water_loop_path
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_water_amb.stream = stream


func _update_water_ambience(loco: CharacterLocomotion, terrain: Object, world_pos: Vector3, delta: float) -> void:
	if _water_amb == null or _water_amb.stream == null or _is_shutting_down():
		return
	var target := 0.0
	if loco.swim_amt > 0.2 or loco.water_depth > CharacterLocomotion.DEPTH_ENTER:
		target = clampf(
			maxf(loco.swim_amt, smoothstep(CharacterLocomotion.DEPTH_ENTER, CharacterLocomotion.DEPTH_WALK, loco.water_depth)),
			0.0,
			1.0
		)
	elif terrain != null and terrain.has_method("nearest_water_distance"):
		var d: float = float(terrain.call("nearest_water_distance", world_pos.x, world_pos.z))
		if d < WATER_NEAR:
			target = 1.0 - smoothstep(WATER_FULL, WATER_NEAR, d)
			if terrain.has_method("biome_name_at") \
					and str(terrain.call("biome_name_at", world_pos.x, world_pos.z)) == "River":
				target = minf(1.0, target * 1.15)
	_water_vol = move_toward(_water_vol, target, delta * 1.8)
	if _water_vol < 0.01:
		_water_amb.volume_db = -80.0
		if _water_amb.playing:
			_water_amb.stop()
		return
	_water_amb.volume_db = lerpf(-52.0, WATER_VOL_DB, pow(_water_vol, 0.85))
	if not _water_amb.playing and AudioServer.get_driver_name() != "Dummy":
		_water_amb.play()


func _setup_action_sfx() -> void:
	_action_player = AudioStreamPlayer3D.new()
	_action_player.name = "ActionSfx"
	_action_player.bus = &"SFX"
	_action_player.max_distance = 28.0
	_action_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_action_player.position = Vector3(0.0, 0.85, 0.45)
	add_child(_action_player)

	_action_streams[&"gather"] = _synth_action_wav(&"gather")
	_action_streams[&"mine"] = _synth_action_wav(&"mine")
	_action_streams[&"chop"] = _synth_action_wav(&"chop")
	_action_streams[&"build"] = _synth_action_wav(&"build")


func _synth_action_wav(kind: StringName) -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.14
	var count := int(float(rate) * dur)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)

	for i in count:
		var t := float(i) / float(rate)
		var env := exp(-t * 28.0)
		var s := 0.0
		match kind:
			&"gather":
				env = sin(clampf(t / dur, 0.0, 1.0) * PI) * exp(-t * 14.0)
				s = (rng.randf_range(-1.0, 1.0) * 0.45 + sin(TAU * 420.0 * t) * 0.18) * env
			&"mine":
				var ring := sin(TAU * 1380.0 * t) * 0.35 + sin(TAU * 2140.0 * t) * 0.25
				var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 65.0) * 0.55
				s = (ring * exp(-t * 24.0) + crack)
			&"chop":
				var thud := sin(TAU * lerpf(210.0, 85.0, minf(t * 14.0, 1.0)) * t) * 0.65
				var snap := rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.40
				s = (thud * exp(-t * 22.0) + snap)
			&"build":
				var tap := sin(TAU * 540.0 * t) * 0.48 + sin(TAU * 920.0 * t) * 0.24
				var click := rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.35
				s = (tap * exp(-t * 30.0) + click)
		var sample := clampi(int(round(clampf(s, -0.95, 0.95) * 32767.0)), -32768, 32767)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
