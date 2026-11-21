class_name InventoryPanel
extends PanelContainer
## Occupied-slot list. Opening it pushes the UI input context.


signal drop_requested(item_id: StringName, amount: int)

const CONTEXT_OWNER := &"inventory_panel"
const TOGGLE_ACTION := &"toggle_inventory"

var _inventory: InventoryContainer
var _open := false
var _rows := VBoxContainer.new()
var _title := Label.new()
var _empty := Label.new()


func _init() -> void:
	custom_minimum_size = Vector2(280, 220)
	_title.text = "Inventory"
	_title.add_theme_font_size_override("font_size", 18)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_rows.add_theme_constant_override("separation", 4)
	_empty.add_theme_font_size_override("font_size", 13)
	box.add_child(_title)
	box.add_child(_rows)
	box.add_child(_empty)
	margin.add_child(box)
	add_child(margin)
	visible = false


func _enter_tree() -> void:
	_ensure_toggle_action()


func _exit_tree() -> void:
	if _open:
		set_open(false)
	if _inventory != null and _inventory.inventory_changed.is_connected(_rebuild):
		_inventory.inventory_changed.disconnect(_rebuild)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(String(TOGGLE_ACTION)) or event.is_echo():
		return
	var router := _router()
	if router != null and int(router.call("get_active_context")) == 2:
		return
	toggle()
	get_viewport().set_input_as_handled()


func bind_inventory(inv: InventoryContainer) -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_rebuild):
		_inventory.inventory_changed.disconnect(_rebuild)
	_inventory = inv
	if _inventory != null and not _inventory.inventory_changed.is_connected(_rebuild):
		_inventory.inventory_changed.connect(_rebuild)
	_rebuild()


func set_open(open: bool) -> void:
	if _open == open:
		visible = open
		return
	_open = open
	visible = open
	var router := _router()
	if router == null:
		return
	if open:
		router.call("push_context", 1, CONTEXT_OWNER)
	else:
		router.call("pop_context", CONTEXT_OWNER)


func toggle() -> void:
	set_open(not _open)


func is_open() -> bool:
	return _open


func get_row_texts() -> PackedStringArray:
	var lines := PackedStringArray()
	for child in _rows.get_children():
		var row := child as HBoxContainer
		if row == null or row.get_child_count() == 0:
			continue
		var label := row.get_child(0) as Label
		if label != null:
			lines.append(label.text)
	return lines


func _rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _inventory == null:
		_empty.text = ""
		return
	var occupied := 0
	for slot_variant in _inventory.get_slots():
		var slot: Dictionary = slot_variant
		var item_id := StringName(slot.get("id", &""))
		var count := int(slot.get("count", 0))
		if item_id == &"" or count <= 0:
			continue
		occupied += 1
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s x%d" % [_pretty(item_id), count]
		var drop := Button.new()
		drop.text = "Drop"
		drop.pressed.connect(_on_drop_pressed.bind(item_id))
		row.add_child(label)
		row.add_child(drop)
		_rows.add_child(row)
	var empty_slots := maxi(0, _inventory.max_slots - occupied)
	_empty.text = "Empty slots: %d" % empty_slots


func _on_drop_pressed(item_id: StringName) -> void:
	drop_requested.emit(item_id, 1)
	if _inventory != null:
		_inventory.remove_item(item_id, 1)
	var ui := _ui_router()
	if ui != null and ui.has_method("show_toast"):
		ui.call("show_toast", "Dropped %s" % _pretty(item_id), 1.2)


func _ensure_toggle_action() -> void:
	if not InputMap.has_action(String(TOGGLE_ACTION)):
		InputMap.add_action(String(TOGGLE_ACTION))
	var router := _router()
	if router != null and router.has_method("register_action"):
		router.call("register_action", TOGGLE_ACTION, [KEY_I], "Inventory")
	elif not _has_key_event(KEY_I):
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_I
		InputMap.action_add_event(String(TOGGLE_ACTION), ev)


func _has_key_event(key: Key) -> bool:
	for ev in InputMap.action_get_events(String(TOGGLE_ACTION)):
		var key_ev := ev as InputEventKey
		if key_ev != null and key_ev.physical_keycode == key:
			return true
	return false


func _pretty(item_id: StringName) -> String:
	var def := _inventory.get_item_def(item_id) if _inventory != null else null
	if def != null and def.display_name != "":
		return tr(def.display_name)
	var raw := String(item_id).replace("_", " ")
	if raw.is_empty():
		return raw
	return raw.substr(0, 1).to_upper() + raw.substr(1)


func _router() -> Node:
	return get_node_or_null("/root/InputRouter")


func _ui_router() -> Node:
	return get_node_or_null("/root/UIRouter")
