extends "res://tests/support/test_suite_base.gd"
## Runtime navmesh baking and the navmesh-driven enemy sample.


func run_all() -> void:
	_test_navmesh_bake()
	_test_enemy_chases_and_attacks()
	_test_enemy_dies_and_disables_its_hurtbox()
	_test_player_strike_damages_enemy()


func _test_navmesh_bake() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	get_root().add_child(ground)
	var region := NavigationRegion3D.new()
	get_root().add_child(region)

	var baked := NavMeshBaker.bake(region, ground, 0.5)
	_assert(baked, "NavMeshBaker bakes a runtime navigation mesh")
	_assert(region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0, "Baked region exposes navigation polygons")

	ground.queue_free()
	region.queue_free()


func _test_enemy_chases_and_attacks() -> void:
	var terrain := MockTerrain.new()
	terrain.ground_y = 0.0
	terrain.biome = MapTypes.Biome.GRASS

	var target := Node3D.new()
	target.name = "PlayerProbe"
	get_root().add_child(target)
	target.global_position = Vector3(0.0, 0.0, -2.4)
	var target_health := HealthComponent.new()
	target_health.max_hp = 30.0
	target.add_child(target_health)
	var target_hurtbox := Hurtbox.new()
	target_hurtbox.name = "Hurtbox"
	target_hurtbox.faction = &"player"
	target_hurtbox.health = target_health
	target.add_child(target_hurtbox)

	var enemy := GuEnemy.new()
	enemy.max_hp = 20.0
	enemy.attack_cooldown = 0.5
	enemy.setup(terrain, target, Vector3.ZERO)
	get_root().add_child(enemy)
	_assert(enemy.get_health() != null and enemy.get_hurtbox() != null, "Enemy builds health and hurtbox without scene nodes")
	_assert(enemy.get_hurtbox().faction == &"enemy", "Enemy hurtbox uses the enemy faction")

	var start_distance := enemy.global_position.distance_to(target.global_position)
	enemy._physics_process(0.25)
	enemy._physics_process(0.25)
	var moved_distance := enemy.global_position.distance_to(target.global_position)
	_assert(moved_distance < start_distance, "Enemy steers toward a visible target without a baked navmesh")
	_assert(target_health.get_hp() < 30.0, "Enemy melee attack damages the target hurtbox")
	_assert(not enemy.is_dead(), "Enemy stays alive while its health remains")

	get_root().remove_child(enemy)
	enemy.free()
	get_root().remove_child(target)
	target.free()


func _test_enemy_dies_and_disables_its_hurtbox() -> void:
	var terrain := MockTerrain.new()
	terrain.ground_y = 0.0
	var target := Node3D.new()
	get_root().add_child(target)
	var enemy := GuEnemy.new()
	enemy.max_hp = 10.0
	enemy.respawn_seconds = 0.05
	enemy.setup(terrain, target, Vector3.ZERO)
	get_root().add_child(enemy)

	var defeats: Array[GuEnemy] = []
	enemy.defeated.connect(func(defeated: GuEnemy) -> void: defeats.append(defeated))
	var hurtbox := enemy.get_hurtbox()
	hurtbox.receive(99.0, null, Vector3.ZERO, false)
	_assert(enemy.is_dead(), "Lethal damage marks the enemy dead")
	_assert(defeats.size() == 1, "Enemy emits defeated once")
	_assert(not enemy.visible, "Dead enemy hides until respawn")
	_assert(hurtbox.receive(10.0, null, Vector3.ZERO, false) == 0.0, "Dead enemy ignores further hits")

	get_root().remove_child(enemy)
	enemy.free()
	get_root().remove_child(target)
	target.free()


func _test_player_strike_damages_enemy() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var world := packed.instantiate()
	var player := world.get_node_or_null("Player") as GuPlayer
	_assert(player != null, "Walk-sandbox player exposes GuPlayer for the strike test")
	if player == null:
		world.free()
		return
	world.remove_child(player)
	get_root().add_child(player)
	player.global_position = Vector3.ZERO
	player.set_facing_yaw(0.0)
	var clock := get_root().get_node_or_null("GameClock")
	if clock != null:
		clock.call("set_gameplay_running", true)
	_assert(player.get_health() != null and player.get_hurtbox() != null, "Player scene wires combat nodes")

	var enemy := GuEnemy.new()
	enemy.max_hp = 45.0
	enemy.respawn_seconds = 99.0
	enemy.setup(null, player, Vector3(0.0, 0.0, -2.0))
	get_root().add_child(enemy)

	_assert(player.perform_action(&"strike"), "Player can start the strike action")
	for _i in 20:
		player._physics_process(0.1)
	_assert(enemy.get_health().get_hp() < 45.0, "Player strike beats damage an enemy in front")

	if clock != null:
		clock.call("set_gameplay_running", false)
	get_root().remove_child(enemy)
	enemy.free()
	get_root().remove_child(player)
	player.free()
	world.free()
