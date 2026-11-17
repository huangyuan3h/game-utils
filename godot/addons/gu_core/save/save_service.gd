extends Node
## Lightweight deterministic save-game persistence (seed + world opts + runtime state).

const SCHEMA_VERSION := 1
const DEFAULT_SAVE_DIR := "user://saves"

var save_dir: String = DEFAULT_SAVE_DIR


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func sanitize_slot(slot: String) -> String:
	var out := ""
	for i in slot.length():
		var ch := slot[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out if out != "" else "slot_1"


func get_slot_path(slot: String) -> String:
	return save_dir.path_join(sanitize_slot(slot) + ".json")


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(get_slot_path(slot))


func list_slots() -> Array[String]:
	var slots: Array[String] = []
	var da := DirAccess.open(save_dir)
	if da == null:
		return slots
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.ends_with(".json"):
			slots.append(fname.trim_suffix(".json"))
		fname = da.get_next()
	da.list_dir_end()
	slots.sort()
	return slots


func save_slot(slot: String, payload: Dictionary) -> Error:
	var dir_err := DirAccess.make_dir_recursive_absolute(save_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		return dir_err

	var doc := payload.duplicate(true)
	doc["schema_version"] = SCHEMA_VERSION
	doc["saved_at_unix"] = int(Time.get_unix_time_from_system())

	var f := FileAccess.open(get_slot_path(slot), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "\t") + "\n")
	f.close()
	return OK


func load_slot(slot: String) -> Dictionary:
	var path := get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Save slot not found: %s" % slot, "data": {}}

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot open save slot (%d)" % FileAccess.get_open_error(), "data": {}}
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		return {"ok": false, "error": "Corrupt save JSON at line %d" % json.get_error_line(), "data": {}}

	if not (json.data is Dictionary):
		return {"ok": false, "error": "Invalid save root type", "data": {}}

	var doc: Dictionary = json.data as Dictionary
	var version := int(doc.get("schema_version", -1))
	if version != SCHEMA_VERSION:
		return {"ok": false, "error": "Unsupported schema_version: %d" % version, "data": {}}
	if not (doc.get("world") is Dictionary):
		return {"ok": false, "error": "Missing world section in save", "data": {}}

	return {"ok": true, "error": "", "data": doc}


func delete_slot(slot: String) -> Error:
	var path := get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)
