extends "res://tests/support/test_suite_base.gd"
## Character locomotion: dry, shallow, swim, and steep-climb transitions.


func run_all() -> void:
	_test_character_locomotion()
	_test_character_climbing()


func _test_character_locomotion() -> void:
	var loco := CharacterLocomotion.new()
	var terrain := MockTerrain.new()

	terrain.ground_y = 2.5
	terrain.water_y = -INF
	terrain.biome = MapTypes.Biome.GRASS
	var pos := Vector3(0.0, 2.5, 0.0)
	var vel := Vector3.ZERO
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Dry walk reports WALK state")
	_assert(is_equal_approx(pos.y, 2.5 + CharacterLocomotion.FEET_OFFSET), "Dry walk snaps feet to ground_y + FEET_OFFSET")
	_assert(loco.swim_amt < 0.01, "Dry walk has near-zero swim_amt")

	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), true, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "RUN", "Sprint on dry land reports RUN state")
	_assert(loco.speed_xz > CharacterLocomotion.WALK_SPEED, "Sprint exceeds WALK_SPEED")

	terrain.ground_y = -1.5
	terrain.water_y = 0.95
	terrain.biome = MapTypes.Biome.SEA
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(0.0, 1.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "SWIM", "Deep sea triggers SWIM state")
	_assert(loco.swim_amt > 0.9, "Deep sea sets swim_amt near 1.0")
	_assert(pos.y > terrain.ground_y + 0.5, "Swimmer floats above deep seabed")

	loco.reset()
	terrain.ground_y = 1.0
	terrain.water_y = 3.0
	terrain.biome = MapTypes.Biome.RIVER
	var river_res := loco.step(Vector3(0.0, 1.0, 0.0), Vector3.ZERO, Vector2(1.0, 0.0), false, terrain, 0.05)
	var river_pos := river_res["position"] as Vector3
	_assert(loco.swim_amt == 0.0, "River biome does not trigger swim blend")
	_assert(is_equal_approx(river_pos.y, 1.0 + CharacterLocomotion.FEET_OFFSET), "River keeps character grounded on riverbed")


func _test_character_climbing() -> void:
	var loco := CharacterLocomotion.new()
	var terrain := MockTerrain.new()

	# 1) Gentle slope (grade = 0.25) should stay in WALK, not CLIMB
	terrain.height_fn = func(x: float, _z: float) -> float:
		return 1.0 + maxf(0.0, x) * 0.25
	var pos := Vector3(0.0, 1.0, 0.0)
	var vel := Vector3.ZERO
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Gentle 0.25 slope stays in WALK state")
	_assert(loco.climb_amt < 0.05, "Gentle slope does not activate climb_amt")

	# 1b) A walkable hillside (grade 0.65, ~33 deg) stays on foot.
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		return 1.0 + maxf(0.0, x) * 0.65
	pos = Vector3(0.0, 1.0, 0.0)
	vel = Vector3.ZERO
	for _i in 24:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Hillside grade 0.65 is walked, not climbed")
	_assert(loco.climb_amt < 0.05, "Hillside does not activate climb_amt")

	# 2) Steep cliff (flat -> 1.0 grade cliff from x=1.5..6.5 -> flat plateau at x>=6.5)
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		if x < 1.5:
			return 1.0
		if x > 6.5:
			return 6.0
		return 1.0 + (x - 1.5) * 1.0
	pos = Vector3(0.5, 1.0, 0.0)
	vel = Vector3.ZERO
	var entered_climb := false
	for _i in 40:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
		if loco.state_label == "CLIMB":
			entered_climb = true
	_assert(entered_climb, "Steep 1.0-grade cliff triggers CLIMB state")
	_assert(loco.climb_amt > 0.8, "Climb blend reaches >0.8 on steep cliff")
	_assert(loco.facing_yaw > 1.2 and loco.facing_yaw < 1.9, "Climber faces uphill (+X) into the cliff")
	_assert(loco.speed_3d < CharacterLocomotion.WALK_SPEED * 0.92, "Steep scramble is slower than a flat walk")
	_assert(loco.speed_3d > 1.1, "Steep scramble still makes progress")

	# 3) Stopping mid-cliff keeps CLIMB state (clinging instead of flickering to WALK)
	for _i in 15:
		var res := loco.step(pos, vel, Vector2.ZERO, false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "CLIMB", "Stopping mid-cliff preserves CLIMB clinging state")
	_assert(loco.climb_move < 0.1, "Clinging idle drops climb_move toward 0")

	# 4) Continuing uphill onto flat plateau exits CLIMB back to WALK
	for _i in 100:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
		if pos.x > 7.5:
			break
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(pos.x > 6.8 and loco.state_label == "WALK", "Reaching flat plateau exits CLIMB back to WALK")

	# 5) Walking downhill from flat ground onto moderate slope does not spuriously climb
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		return 5.0 - maxf(0.0, x - 1.0) * 0.7
	pos = Vector3(0.0, 5.0, 0.0)
	vel = Vector3.ZERO
	for _i in 25:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Walking downhill does not trigger upward CLIMB")

	# 6) Deep sea prioritizes SWIM even over a steep seabed
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		return -2.5 + x * 1.1
	terrain.water_y = 0.95
	terrain.biome = MapTypes.Biome.SEA
	pos = Vector3(0.0, -2.5, 0.0)
	vel = Vector3.ZERO
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "SWIM", "Deep water prioritizes SWIM over steep seabed")

	# 7) Real MapData steep cliff cell triggers CLIMB when walked uphill
	var real_map: MapData = MapGen.generate(42, {"landform": MapTypes.Landform.TERRACED_HIGHLANDS, "relief": 1.0})
	var best_pos := Vector2.ZERO
	var best_grad := Vector2.ZERO
	for z in range(10, real_map.grid - 10):
		for x in range(10, real_map.grid - 10):
			var wx := (float(x) / float(real_map.grid - 1) - 0.5) * real_map.size
			var wz := (float(z) / float(real_map.grid - 1) - 0.5) * real_map.size
			if real_map.sample_height(wx, wz) < real_map.water_y + 1.0:
				continue
			var gx := (real_map.sample_height(wx + 0.35, wz) - real_map.sample_height(wx - 0.35, wz)) / 0.70
			var gz := (real_map.sample_height(wx, wz + 0.35) - real_map.sample_height(wx, wz - 0.35)) / 0.70
			var g := Vector2(gx, gz)
			if g.length() > best_grad.length():
				best_grad = g
				best_pos = Vector2(wx, wz)
	_assert(best_grad.length() > CharacterLocomotion.CLIMB_ENTER_GRADE, "Generated Terraced Highlands has steep climbable cliff")
	loco.reset()
	var up_dir := best_grad.normalized()
	var start_xz := best_pos - up_dir * 0.4
	var rpos := Vector3(start_xz.x, real_map.sample_height(start_xz.x, start_xz.y), start_xz.y)
	var rvel := Vector3.ZERO
	var real_climbed := false
	for _i in 20:
		var res := loco.step(rpos, rvel, up_dir, false, real_map, 0.05)
		rpos = res["position"] as Vector3
		rvel = res["velocity"] as Vector3
		if loco.state_label == "CLIMB":
			real_climbed = true
	_assert(real_climbed, "Real MapData steep cliff triggers CLIMB when moving uphill")
