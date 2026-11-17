extends Node
## Deterministic save-game persistence with Saveable registry, schema migrations,
## and atomic .tmp/.bak write + recovery.

const SCHEMA_VERSION := 1
const DEFAULT_SAVE_DIR := "user://saves"

var save_dir: String = DEFAULT_SAVE_DIR
var current_schema_version: int = SCHEMA_VERSION

var _saveables: Dictionary = {} ## String -> Object
var _migrations: Dictionary = {} ## int (from_version) -> Callable


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


func get_backup_path(slot: String) -> String:
	return get_slot_path(slot) + ".bak"


func get_temp_path(slot: String) -> String:
	return get_slot_path(slot) + ".tmp"


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(get_slot_path(slot)) or FileAccess.file_exists(get_backup_path(slot))


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


func get_slot_metadata(slot: String) -> Dictionary:
	var clean := sanitize_slot(slot)
	var primary := get_slot_path(clean)
	var bak := get_backup_path(clean)
	var has_bak := FileAccess.file_exists(bak)
	var path := primary if FileAccess.file_exists(primary) else (bak if has_bak else "")
	if path == "":
		return {
			"slot": clean,
			"exists": false,
			"saved_at_unix": 0,
			"saved_at_text": "",
			"schema_version": -1,
			"has_backup": false,
		}

	var f := FileAccess.open(path, FileAccess.READ)
	var saved_unix := 0
	var ver := -1
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var d := parsed as Dictionary
			saved_unix = int(d.get("saved_at_unix", 0))
			ver = int(d.get("schema_version", -1))

	var saved_txt := ""
	if saved_unix > 0:
		saved_txt = Time.get_datetime_string_from_unix_time(saved_unix, true).replace("T", " ")

	return {
		"slot": clean,
		"exists": true,
		"saved_at_unix": saved_unix,
		"saved_at_text": saved_txt,
		"schema_version": ver,
		"has_backup": has_bak,
	}


func list_slot_metadata() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot_name: String in list_slots():
		out.append(get_slot_metadata(slot_name))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a.get("saved_at_unix", 0))
		var tb := int(b.get("saved_at_unix", 0))
		if ta != tb:
			return ta > tb
		return str(a.get("slot", "")) < str(b.get("slot", ""))
	)
	return out


func register_saveable(section_key: String, provider: Object) -> void:
	if section_key == "" or provider == null or not is_instance_valid(provider):
		return
	_saveables[section_key] = provider


func unregister_saveable(section_key: String) -> void:
	_saveables.erase(section_key)


func collect_saveables(base_payload: Dictionary = {}) -> Dictionary:
	var out := base_payload.duplicate(true)
	var dead_keys: Array[String] = []
	for key: String in _saveables:
		var provider: Variant = _saveables[key]
		if not (provider is Object) or not is_instance_valid(provider as Object):
			dead_keys.append(key)
			continue
		var obj := provider as Object
		if obj.has_method("export_state"):
			out[key] = obj.call("export_state")
		elif obj.has_method("export_save_state"):
			out[key] = obj.call("export_save_state")
	for dk in dead_keys:
		_saveables.erase(dk)
	return out


func apply_saveables(doc: Dictionary) -> void:
	var dead_keys: Array[String] = []
	for key: String in _saveables:
		var provider: Variant = _saveables[key]
		if not (provider is Object) or not is_instance_valid(provider as Object):
			dead_keys.append(key)
			continue
		if not doc.has(key):
			continue
		var obj := provider as Object
		var section: Variant = doc[key]
		if obj.has_method("apply_state") and section is Dictionary:
			obj.call("apply_state", section as Dictionary)
		elif obj.has_method("apply_save_state") and section is Dictionary:
			obj.call("apply_save_state", section as Dictionary)
	for dk in dead_keys:
		_saveables.erase(dk)


func register_migration(from_version: int, migrate_fn: Callable) -> void:
	if from_version < 1 or not migrate_fn.is_valid():
		return
	_migrations[from_version] = migrate_fn


func clear_migrations() -> void:
	_migrations.clear()


func save_slot(slot: String, payload: Dictionary) -> Error:
	var dir_err := DirAccess.make_dir_recursive_absolute(save_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		return dir_err

	var doc := collect_saveables(payload)
	doc["schema_version"] = current_schema_version
	doc["saved_at_unix"] = int(Time.get_unix_time_from_system())

	var text := JSON.stringify(doc, "\t") + "\n"
	var primary_path := get_slot_path(slot)
	var tmp_path := get_temp_path(slot)
	var bak_path := get_backup_path(slot)

	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()

	if FileAccess.file_exists(primary_path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var bak_err := DirAccess.copy_absolute(primary_path, bak_path)
		if bak_err != OK:
			push_warning("SaveService failed to create backup '%s' (err=%d)" % [bak_path, bak_err])
		DirAccess.remove_absolute(primary_path)

	var rename_err := DirAccess.rename_absolute(tmp_path, primary_path)
	if rename_err != OK:
		# Fallback write directly if cross-volume rename fails
		var f_fallback := FileAccess.open(primary_path, FileAccess.WRITE)
		if f_fallback == null:
			return rename_err
		f_fallback.store_string(text)
		f_fallback.close()
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
	return OK


func load_slot(slot: String) -> Dictionary:
	var primary_path := get_slot_path(slot)
	var bak_path := get_backup_path(slot)

	var primary_res := _load_and_migrate_file(primary_path)
	if bool(primary_res.get("ok", false)):
		primary_res["recovered_from_backup"] = false
		return primary_res

	if FileAccess.file_exists(bak_path):
		var bak_res := _load_and_migrate_file(bak_path)
		if bool(bak_res.get("ok", false)):
			bak_res["recovered_from_backup"] = true
			return bak_res

	primary_res["recovered_from_backup"] = false
	return primary_res


func delete_slot(slot: String) -> Error:
	var primary_path := get_slot_path(slot)
	var bak_path := get_backup_path(slot)
	var tmp_path := get_temp_path(slot)
	var removed := false
	for p: String in [primary_path, bak_path, tmp_path]:
		if FileAccess.file_exists(p):
			var err := DirAccess.remove_absolute(p)
			if err != OK:
				return err
			removed = true
	return OK if removed else ERR_FILE_NOT_FOUND


func _load_and_migrate_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Save slot not found: %s" % path, "data": {}}

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

	var doc: Dictionary = (json.data as Dictionary).duplicate(true)
	var version := int(doc.get("schema_version", -1))
	if version < 1 or version > current_schema_version:
		return {"ok": false, "error": "Unsupported schema_version: %d" % version, "data": {}}

	while version < current_schema_version:
		if not _migrations.has(version):
			return {"ok": false, "error": "Missing migration from schema_version %d" % version, "data": {}}
		var fn: Callable = _migrations[version] as Callable
		var migrated: Variant = fn.call(doc)
		if not (migrated is Dictionary):
			return {"ok": false, "error": "Migration %d returned non-Dictionary" % version, "data": {}}
		doc = migrated as Dictionary
		version += 1
		doc["schema_version"] = version

	if not (doc.get("world") is Dictionary):
		return {"ok": false, "error": "Missing world section in save", "data": {}}

	return {"ok": true, "error": "", "data": doc}
