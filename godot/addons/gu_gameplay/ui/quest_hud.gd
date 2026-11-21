class_name QuestHud
extends VBoxContainer
## Active quest tracker. Completed rows stay until acknowledged or the fade timer.


var _tracker: QuestTracker
var _rows: Dictionary = {}
var _fade_seconds := 2.5


func _init() -> void:
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(240, 0)


func bind_tracker(tracker: QuestTracker) -> void:
	_disconnect_tracker()
	_tracker = tracker
	if _tracker == null:
		return
	_tracker.quest_started.connect(_on_quest_started)
	_tracker.objective_progressed.connect(_on_objective_progressed)
	_tracker.quest_completed.connect(_on_quest_completed)
	_rebuild()


func acknowledge_completion(quest_id: StringName = &"") -> void:
	var ids: Array[StringName] = []
	if quest_id == &"":
		for key in _rows.keys():
			var row: Dictionary = _rows[key]
			if bool(row.get("complete", false)):
				ids.append(key)
	else:
		ids.append(quest_id)
	for id in ids:
		_remove_row(id)


func get_row_texts() -> PackedStringArray:
	var lines := PackedStringArray()
	for child in get_children():
		if child is Label:
			lines.append((child as Label).text)
		elif child is VBoxContainer:
			for nested in child.get_children():
				if nested is Label:
					lines.append((nested as Label).text)
	return lines


func _exit_tree() -> void:
	_disconnect_tracker()


func _disconnect_tracker() -> void:
	if _tracker == null:
		return
	if _tracker.quest_started.is_connected(_on_quest_started):
		_tracker.quest_started.disconnect(_on_quest_started)
	if _tracker.objective_progressed.is_connected(_on_objective_progressed):
		_tracker.objective_progressed.disconnect(_on_objective_progressed)
	if _tracker.quest_completed.is_connected(_on_quest_completed):
		_tracker.quest_completed.disconnect(_on_quest_completed)
	_tracker = null


func _rebuild() -> void:
	_clear_children()
	_rows.clear()
	if _tracker == null:
		return
	for raw_status in _tracker.list_active_quests():
		var status: Dictionary = raw_status
		_render_active(StringName(status.get("id", &"")))
	var saved := _tracker.export_state()
	var completed: Array = saved.get("completed", []) as Array
	for raw_id in completed:
		var quest_id := StringName(str(raw_id))
		if quest_id != &"" and not _rows.has(quest_id):
			_render_complete(quest_id)


func _render_active(quest_id: StringName) -> void:
	var status := _tracker.get_quest_status(quest_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var title := Label.new()
	title.text = tr(String(status.get("title", quest_id)))
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	var objectives: Array = status.get("objectives", []) as Array
	for obj_variant in objectives:
		var obj: Dictionary = obj_variant
		var line := Label.new()
		line.add_theme_font_size_override("font_size", 13)
		line.text = "%s %d/%d" % [tr(String(obj.get("description", ""))), int(obj.get("current", 0)), int(obj.get("target", 0))]
		box.add_child(line)
	add_child(box)
	_rows[quest_id] = {"node": box, "complete": false}


func _render_complete(quest_id: StringName) -> void:
	var status := _tracker.get_quest_status(quest_id)
	var line := Label.new()
	line.text = "%s  COMPLETE" % tr(String(status.get("title", quest_id)))
	line.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	add_child(line)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = _fade_seconds
	timer.timeout.connect(acknowledge_completion.bind(quest_id))
	line.add_child(timer)
	timer.start()
	_rows[quest_id] = {"node": line, "complete": true, "timer": timer}


func _remove_row(quest_id: StringName) -> void:
	if not _rows.has(quest_id):
		return
	var row: Dictionary = _rows[quest_id]
	var node := row.get("node") as Node
	_detach(node)
	_rows.erase(quest_id)


func _clear_children() -> void:
	for child in get_children():
		_detach(child)


func _detach(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()


func _on_quest_started(quest_id: StringName) -> void:
	_remove_row(quest_id)
	_render_active(quest_id)


func _on_objective_progressed(quest_id: StringName, _objective_id: StringName, _current: int, _target: int) -> void:
	_remove_row(quest_id)
	if _tracker != null and _tracker.is_active(quest_id):
		_render_active(quest_id)


func _on_quest_completed(quest_id: StringName) -> void:
	_remove_row(quest_id)
	_render_complete(quest_id)
