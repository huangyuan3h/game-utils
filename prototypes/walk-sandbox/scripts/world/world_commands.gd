class_name WorldCommands
extends RefCounted
## Registers walk-sandbox debug commands with DevConsole.


static func register(
	console: Node,
	tp_spawn_cb: Callable,
	get_beacons_cb: Callable,
	refresh_cb: Callable,
	sky_time: Node,
	player: Node
) -> void:
	if console == null or not console.has_method("register_command"):
		return

	console.call("register_command", "tp_spawn", "Teleport player to safe spawn point", func(_args: Array[String]) -> String:
		if tp_spawn_cb.is_valid():
			tp_spawn_cb.call()
		var pos_str := str((player as Node3D).global_position) if player is Node3D else "?"
		return "Teleported to %s" % pos_str
	)

	console.call("register_command", "light_all", "Light or extinguish all world beacons [on|off]", func(args: Array[String]) -> String:
		var turn_on := args.is_empty() or args[0].to_lower() != "off"
		var beacons: Array = get_beacons_cb.call() as Array if get_beacons_cb.is_valid() else []
		for b: Variant in beacons:
			if b is WorldBeacon and is_instance_valid(b as Object):
				(b as WorldBeacon).set_lit(turn_on, false)
		if refresh_cb.is_valid():
			refresh_cb.call()
		return "Set %d beacon(s) lit=%s" % [beacons.size(), str(turn_on)]
	)

	console.call("register_command", "time", "Set time of day in hours (0..24)", func(args: Array[String]) -> String:
		if args.is_empty() or sky_time == null:
			return "Usage: time <0..24>"
		var h := fposmod(float(args[0]), 24.0)
		sky_time.set("hour", h)
		return "Time set to %.2f" % h
	)

	console.call("register_command", "weather", "Set weather preset (clear|cloudy|overcast|rain|storm|snow)", func(args: Array[String]) -> String:
		if args.is_empty() or sky_time == null:
			return "Usage: weather <clear|cloudy|overcast|rain|storm|snow>"
		var names := ["clear", "cloudy", "overcast", "rain", "storm", "snow"]
		var idx := names.find(args[0].to_lower())
		if idx < 0:
			return "Unknown weather '%s'" % args[0]
		sky_time.call("apply_state", {"weather": idx})
		return "Weather set to %s" % names[idx]
	)

	console.call("register_command", "give_item", "Add items to player inventory <item_id> [amount]", func(args: Array[String]) -> String:
		if args.is_empty() or player == null or not player.has_method("get_inventory"):
			return "Usage: give_item <item_id> [amount]"
		var inv := player.call("get_inventory") as InventoryContainer
		if inv == null:
			return "Player inventory unavailable."
		var item_id := StringName(args[0])
		var amt := maxi(1, int(args[1])) if args.size() > 1 else 1
		var rem := inv.add_item(item_id, amt)
		if refresh_cb.is_valid():
			refresh_cb.call()
		return "Added %d %s (leftover=%d)" % [amt - rem, String(item_id), rem]
	)
