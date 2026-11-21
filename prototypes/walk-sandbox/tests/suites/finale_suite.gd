extends "res://tests/support/test_suite_base.gd"
## AI perception, sky clarity, and the end-to-end play/save/load smoke.


func run_all() -> void:
	_test_ai_perception()
	_test_summit_star_clarity()
	_test_play_smoke()


func _test_ai_perception() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var agent := AiAgentScript.new()
	agent.tick(0.1, origin, forward, Vector3(0, 0, -20), true)
	_assert(agent.mode == AiAgentScript.Mode.PATROL, "A distant target leaves the agent on patrol")
	var chase: Vector3 = agent.tick(0.1, origin, forward, Vector3(0, 0, -3), true)
	_assert(agent.mode == AiAgentScript.Mode.CHASE and chase.length() > 0.1, "A target inside the cone starts a chase")
	agent.tick(0.2, origin, forward, Vector3(0, 0, -3), false)
	_assert(agent.mode == AiAgentScript.Mode.LEASH, "Losing the target starts the leash timer")
	agent.tick(1.0, origin, forward, Vector3(0, 0, -3), false)
	_assert(agent.mode == AiAgentScript.Mode.PATROL, "The agent returns to patrol after the leash timeout")
	_assert(AiPerceptionScript.hears(origin, Vector3(1, 0, 0), 4.0), "Hearing range includes a nearby noise")
	agent.tick(0.1, origin, forward, Vector3(0, 0, -3), false, Vector3(1, 0, 0))
	_assert(agent.blackboard.has_value(&"heard_position"), "A heard noise is written to the blackboard")


func _test_summit_star_clarity() -> void:
	var shore := float(SkyTimeScript.altitude_clarity(1.1, 0.95, 11.0))
	var ridge := float(SkyTimeScript.altitude_clarity(5.0, 0.95, 11.0))
	var summit := float(SkyTimeScript.altitude_clarity(10.4, 0.95, 11.0))
	_assert(shore < 0.05, "Night sky stays dim near the shore")
	_assert(ridge > shore and ridge < summit, "Star clarity rises from the ridge toward the summit")
	_assert(summit > 0.95, "A summit night is clear enough to see the stars")
	var shader := load("res://shaders/sky_weather.gdshader") as Shader
	_assert(shader != null and shader.code.contains("altitude_clarity"), "Sky shader exposes summit star clarity")


func _test_play_smoke() -> void:
	var flow := get_root().get_node_or_null("GameFlow")
	var saves := get_root().get_node_or_null("SaveService")
	_assert(flow != null and saves != null, "Play smoke can use GameFlow and SaveService")
	if flow == null or saves == null:
		return
	var world := MockWorld.new()
	get_root().add_child(world)
	flow.call("register_world", world)
	_assert(flow.call("get_world") == world, "Play smoke registers the world")
	flow.call("start_new_game", {"seed": 7})
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PLAYING, "Play smoke reaches PLAYING")
	_assert(world.started_count >= 1, "Play smoke starts a new world")
	var save_err := int(flow.call("save_current_game", "play_smoke"))
	_assert(save_err == OK, "Play smoke writes a save")
	world.applied_doc = {}
	var loaded := bool(flow.call("load_game", "play_smoke"))
	_assert(loaded, "Play smoke loads the save")
	var applied := world.applied_doc
	var world_doc: Dictionary = applied.get("world", {}) as Dictionary
	_assert(int(world_doc.get("seed", -1)) == 777, "Play smoke restores the saved world seed")
	saves.call("delete_slot", "play_smoke")
	world.queue_free()
	if t.call("no_failures"):
		_quit_through_flow = true
