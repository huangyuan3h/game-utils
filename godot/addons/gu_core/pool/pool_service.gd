extends Node
## Reusable PackedScene object pool supporting prewarm, acquire/release hooks, and stats.

var _available: Dictionary = {} ## key: String -> Array[Node]
var _active: Dictionary = {} ## key: String -> Array[Node]
var _node_to_key: Dictionary = {} ## int (instance_id) -> String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func prewarm(scene: PackedScene, count: int) -> void:
	if scene == null or count <= 0:
		return
	var key := _key_for(scene)
	var avail: Array = _available.get(key, []) as Array
	for _i in count:
		var inst := scene.instantiate()
		if inst == null:
			break
		_park_node(inst)
		avail.append(inst)
		_node_to_key[inst.get_instance_id()] = key
	_available[key] = avail


func acquire(scene: PackedScene, parent: Node = null) -> Node:
	if scene == null:
		return null
	var key := _key_for(scene)
	var avail: Array = _available.get(key, []) as Array
	var inst: Node = null

	while not avail.is_empty():
		var cand: Variant = avail.pop_back()
		if cand is Node and is_instance_valid(cand as Node):
			inst = cand as Node
			break
	_available[key] = avail

	if inst == null:
		inst = scene.instantiate()
		if inst == null:
			return null
		_node_to_key[inst.get_instance_id()] = key

	if inst.get_parent() == self:
		remove_child(inst)
	if parent != null and is_instance_valid(parent):
		if inst.get_parent() != parent:
			if inst.get_parent() != null:
				inst.get_parent().remove_child(inst)
			parent.add_child(inst)

	inst.process_mode = Node.PROCESS_MODE_INHERIT
	if inst is Node3D:
		(inst as Node3D).visible = true
	elif inst is CanvasItem:
		(inst as CanvasItem).visible = true

	var act: Array = _active.get(key, []) as Array
	act.append(inst)
	_active[key] = act

	if inst.has_method("on_pool_acquire"):
		inst.call("on_pool_acquire")
	return inst


func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var iid := node.get_instance_id()
	if not _node_to_key.has(iid):
		node.queue_free()
		return

	var key := str(_node_to_key[iid])
	var act: Array = _active.get(key, []) as Array
	for i in range(act.size() - 1, -1, -1):
		if act[i] == node or not is_instance_valid(act[i] as Object):
			act.remove_at(i)
	_active[key] = act

	if node.has_method("on_pool_release"):
		node.call("on_pool_release")

	_park_node(node)
	var avail: Array = _available.get(key, []) as Array
	if not avail.has(node):
		avail.append(node)
	_available[key] = avail


func clear_pool(scene: PackedScene = null) -> void:
	if scene != null:
		var key := _key_for(scene)
		_free_list(_available.get(key, []) as Array)
		_free_list(_active.get(key, []) as Array)
		_available.erase(key)
		_active.erase(key)
		return

	for k: String in _available:
		_free_list(_available[k] as Array)
	for k: String in _active:
		_free_list(_active[k] as Array)
	_available.clear()
	_active.clear()
	_node_to_key.clear()


func get_pool_stats(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {"available": 0, "active": 0}
	var key := _key_for(scene)
	var avail_count := 0
	for n: Variant in (_available.get(key, []) as Array):
		if n is Node and is_instance_valid(n as Node):
			avail_count += 1
	var act_count := 0
	for n: Variant in (_active.get(key, []) as Array):
		if n is Node and is_instance_valid(n as Node):
			act_count += 1
	return {"available": avail_count, "active": act_count}


func _park_node(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Node3D:
		(node as Node3D).visible = false
	elif node is CanvasItem:
		(node as CanvasItem).visible = false
	var p := node.get_parent()
	if p != self:
		if p != null:
			p.remove_child(node)
		add_child(node)


func _free_list(arr: Array) -> void:
	for item: Variant in arr:
		if item is Node and is_instance_valid(item as Node):
			var n := item as Node
			_node_to_key.erase(n.get_instance_id())
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()


func _key_for(scene: PackedScene) -> String:
	if scene.resource_path != "":
		return scene.resource_path
	return "scene:" + str(scene.get_instance_id())
