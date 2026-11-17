extends Node
## Procedural weather ambience and delayed thunder audio synthesizer.
## Generates seamless looping rain/wind WAV streams and multi-stage thunderclaps at runtime.

const SAMPLE_RATE := 22050
const SPEED_OF_SOUND := 343.0
const MAX_THUNDER_PLAYERS := 4

var _rain_light_player: AudioStreamPlayer
var _rain_heavy_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _thunder_players: Array[AudioStreamPlayer] = []
var _thunder_near_streams: Array[AudioStreamWAV] = []
var _thunder_far_streams: Array[AudioStreamWAV] = []
var _thunder_queue: Array[Dictionary] = []

var _rain_light_vol: float = 0.0
var _rain_heavy_vol: float = 0.0
var _wind_vol: float = 0.0
var _rng := RandomNumberGenerator.new()
var _shutting_down: bool = false


func _ready() -> void:
	_rng.randomize()
	_setup_players()
	_build_streams()


func _exit_tree() -> void:
	_shutting_down = true
	_thunder_queue.clear()
	for p in [_rain_light_player, _rain_heavy_player, _wind_player]:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _thunder_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null


func _process(delta: float) -> void:
	if _is_shutting_down() or _thunder_queue.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for item in _thunder_queue:
		var delay: float = float(item["delay"]) - delta
		if delay <= 0.0:
			_play_thunder(float(item["distance"]), float(item["intensity"]))
		else:
			item["delay"] = delay
			remaining.append(item)
	_thunder_queue = remaining


func update_ambience(
	rain_intensity: float,
	snow_intensity: float,
	wind_strength: float,
	gust: float,
	delta: float
) -> void:
	if _is_shutting_down():
		return
	var r := clampf(rain_intensity, 0.0, 1.0)
	var s := clampf(snow_intensity, 0.0, 1.0)
	var w := clampf(wind_strength, 0.0, 1.0)

	# Light rain peaks during medium rain; heavy rain takes over during storm.
	var target_light := clampf(r * 1.45, 0.0, 1.0) * (1.0 - smoothstep(0.45, 0.95, r) * 0.45)
	var target_heavy := smoothstep(0.30, 1.0, r)
	# Snow softens air acoustics; wind carries soft winter hush or storm howl.
	var target_wind := clampf(w * (0.75 + gust * 0.35) + s * 0.12, 0.0, 1.0)

	var smooth := 1.0 - exp(-2.5 * delta)
	_rain_light_vol = lerpf(_rain_light_vol, target_light, smooth)
	_rain_heavy_vol = lerpf(_rain_heavy_vol, target_heavy, smooth)
	_wind_vol = lerpf(_wind_vol, target_wind, smooth)

	_apply_loop_volume(_rain_light_player, _rain_light_vol, -42.0, -15.0)
	_apply_loop_volume(_rain_heavy_player, _rain_heavy_vol, -44.0, -10.5)
	_apply_loop_volume(_wind_player, _wind_vol, -44.0, -16.0)
	if _wind_player != null:
		_wind_player.pitch_scale = lerpf(0.86, 1.16, clampf(w * 0.7 + gust * 0.3, 0.0, 1.0))


func trigger_thunder(distance_m: float, intensity: float = 1.0) -> void:
	if _is_shutting_down():
		return
	# Compress physical delay slightly so distant thunder still arrives before weather changes.
	var physical_delay := distance_m / SPEED_OF_SOUND
	var game_delay := clampf(physical_delay * 0.85, 0.12, 2.6)
	_thunder_queue.append({
		"delay": game_delay,
		"distance": distance_m,
		"intensity": clampf(intensity, 0.4, 1.4),
	})


func _setup_players() -> void:
	_rain_light_player = _make_player("RainLight", &"Ambience")
	_rain_heavy_player = _make_player("RainHeavy", &"Ambience")
	_wind_player = _make_player("WindLoop", &"Ambience")
	for i in MAX_THUNDER_PLAYERS:
		_thunder_players.append(_make_player("Thunder_%d" % i, &"SFX"))


func _make_player(node_name: String, bus_name: StringName = &"Ambience") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus_name
	p.volume_db = -80.0
	add_child(p)
	return p


func _build_streams() -> void:
	_rain_light_player.stream = _generate_rain_loop(3.0, false)
	_rain_heavy_player.stream = _generate_rain_loop(3.0, true)
	_wind_player.stream = _generate_wind_loop(4.0)

	_thunder_near_streams.clear()
	_thunder_far_streams.clear()
	for i in 2:
		_thunder_near_streams.append(_generate_thunder_wav(3.2, true, 1000 + i * 73))
		_thunder_far_streams.append(_generate_thunder_wav(4.2, false, 2000 + i * 97))


func _is_shutting_down() -> bool:
	if _shutting_down:
		return true
	var audio_mgr := get_node_or_null("/root/AudioManager")
	return audio_mgr != null and audio_mgr.has_method("is_shutting_down") and bool(audio_mgr.call("is_shutting_down"))


func _apply_loop_volume(player: AudioStreamPlayer, norm_vol: float, min_db: float, max_db: float) -> void:
	if player == null or player.stream == null or _is_shutting_down():
		return
	if norm_vol < 0.01:
		player.volume_db = -80.0
		if player.playing:
			player.stop()
		return
	player.volume_db = lerpf(min_db, max_db, pow(norm_vol, 0.65))
	if not player.playing and AudioServer.get_driver_name() != "Dummy":
		player.play()


func _play_thunder(distance_m: float, intensity: float) -> void:
	if _is_shutting_down() or AudioServer.get_driver_name() == "Dummy":
		return
	var is_near := distance_m < 140.0
	var pool := _thunder_near_streams if is_near else _thunder_far_streams
	if pool.is_empty():
		return
	var player := _acquire_thunder_player()
	player.stream = pool[_rng.randi_range(0, pool.size() - 1)]
	var dist_att := 1.0 - smoothstep(45.0, 320.0, distance_m)
	var db := lerpf(-16.0, -3.5, dist_att * clampf(intensity, 0.5, 1.2))
	player.volume_db = db
	player.pitch_scale = _rng.randf_range(0.88, 1.08) * lerpf(0.84, 1.04, dist_att)
	player.play()


func _acquire_thunder_player() -> AudioStreamPlayer:
	for p in _thunder_players:
		if not p.playing:
			return p
	return _thunder_players[0]


func _generate_rain_loop(duration_sec: float, heavy: bool) -> AudioStreamWAV:
	var n := int(duration_sec * SAMPLE_RATE)
	var fade := int(0.35 * SAMPLE_RATE)
	var total := n + fade
	var raw := PackedFloat32Array()
	raw.resize(total)

	# Paul Kellet pink-noise state + droplet shimmer.
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var lp := 0.0
	var hp_prev := 0.0
	var prev_in := 0.0
	var drop_env := 0.0

	for i in total:
		var white := _rng.randf_range(-1.0, 1.0)
		b0 = 0.99765 * b0 + white * 0.0990460
		b1 = 0.96300 * b1 + white * 0.2965164
		b2 = 0.57000 * b2 + white * 1.0526913
		var pink := (b0 + b1 + b2 + white * 0.1848) * 0.16

		if heavy:
			# Broader roaring body + crisp hiss.
			lp = lerpf(lp, pink, 0.36)
			var droplet := 0.0
			if _rng.randf() < 0.012:
				drop_env = _rng.randf_range(0.25, 0.6)
			drop_env *= 0.84
			droplet = drop_env * white * 0.45
			raw[i] = clampf((lp * 0.85 + white * 0.18 + droplet) * 0.72, -0.95, 0.95)
		else:
			# Light rain: gentle high-pass pattering without heavy rumble.
			hp_prev = 0.88 * (hp_prev + pink - prev_in)
			prev_in = pink
			lp = lerpf(lp, hp_prev, 0.52)
			if _rng.randf() < 0.008:
				drop_env = _rng.randf_range(0.18, 0.42)
			drop_env *= 0.80
			var pat := drop_env * white * 0.35
			raw[i] = clampf((lp * 0.75 + pat) * 0.68, -0.95, 0.95)

	var looped := _crossfade_loop(raw, n, fade)
	return _pack_wav(looped, true)


func _generate_wind_loop(duration_sec: float) -> AudioStreamWAV:
	var n := int(duration_sec * SAMPLE_RATE)
	var fade := int(0.45 * SAMPLE_RATE)
	var total := n + fade
	var raw := PackedFloat32Array()
	raw.resize(total)

	var lp1 := 0.0
	var lp2 := 0.0
	var bp := 0.0
	for i in total:
		var t := float(i) / float(SAMPLE_RATE)
		var white := _rng.randf_range(-1.0, 1.0)
		# Two-pole smooth filter creates hollow airy wind whistle.
		var cutoff := 0.055 + 0.035 * sin(TAU * t / duration_sec * 2.0)
		lp1 = lerpf(lp1, white, cutoff)
		lp2 = lerpf(lp2, lp1, cutoff * 1.4)
		bp = lerpf(bp, lp1 - lp2, 0.14)
		var swell := 0.65 + 0.35 * sin(TAU * t / duration_sec + 0.8)
		raw[i] = clampf((lp2 * 1.6 + bp * 1.8) * swell * 0.75, -0.95, 0.95)

	var looped := _crossfade_loop(raw, n, fade)
	return _pack_wav(looped, true)


func _generate_thunder_wav(duration_sec: float, near: bool, seed_val: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var n := int(duration_sec * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)

	# Build multi-peak rumble envelope (initial crack/strike + delayed echoes).
	var sub_pulses: Array[Dictionary] = []
	var pulse_count := 4 if near else 3
	var cursor := 0.03 if near else 0.12
	for p in pulse_count:
		sub_pulses.append({
			"time": cursor,
			"amp": (1.0 if p == 0 else rng.randf_range(0.35, 0.72)) * pow(0.75, p),
			"decay": rng.randf_range(2.2, 4.2) if near else rng.randf_range(1.1, 2.2),
		})
		cursor += rng.randf_range(0.22, 0.65)

	var lp_low := 0.0
	var lp_mid := 0.0
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var white := rng.randf_range(-1.0, 1.0)
		lp_low = lerpf(lp_low, white, 0.035 if near else 0.022)
		lp_mid = lerpf(lp_mid, white, 0.16 if near else 0.07)

		var env := 0.0
		for sp in sub_pulses:
			var dt := t - float(sp["time"])
			if dt >= 0.0:
				var attack := clampf(dt / (0.015 if near else 0.12), 0.0, 1.0)
				env += attack * exp(-dt * float(sp["decay"])) * float(sp["amp"])

		var crack := 0.0
		if near and t < 0.35:
			crack = white * exp(-t * 14.0) * 0.55

		var body := (lp_low * 2.6 + lp_mid * (1.1 if near else 0.65)) * clampf(env, 0.0, 1.35)
		var tail_fade := 1.0 - smoothstep(duration_sec - 0.5, duration_sec, t)
		samples[i] = clampf((body + crack) * tail_fade * 0.82, -0.98, 0.98)

	return _pack_wav(samples, false)


func _crossfade_loop(raw: PackedFloat32Array, loop_len: int, fade: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(loop_len)
	for i in loop_len:
		out[i] = raw[i]
	for i in fade:
		var alpha := float(i) / float(fade)
		out[i] = lerpf(raw[loop_len + i], raw[i], alpha)
	return out


func _pack_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := clampi(int(round(samples[i] * 32767.0)), -32767, 32767)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav
