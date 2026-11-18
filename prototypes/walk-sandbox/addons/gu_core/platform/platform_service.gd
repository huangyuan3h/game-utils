extends Node
## Local stand-in for achievements, stats, cloud-save path, and rich presence.

const MOCK_PATH := "user://platform_mock.json"

var _achievements: Array[String] = []
var _stats: Dictionary = {}
var _presence: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


func unlock_achievement(achievement_id: String) -> void:
	var clean := achievement_id.strip_edges()
	if clean == "" or _achievements.has(clean):
		return
	_achievements.append(clean)
	GuLog.info("platform", "achievement %s" % clean)
	_save()


func set_stat(stat_id: String, value: float) -> void:
	_stats[stat_id] = value
	_save()


func cloud_save_dir() -> String:
	return "user://cloud_saves"


func set_presence(text: String) -> void:
	_presence = text
	GuLog.info("platform", "presence %s" % text)
	_save()


func has_achievement(achievement_id: String) -> bool:
	return _achievements.has(achievement_id)


func get_state() -> Dictionary:
	return {
		"achievements": _achievements.duplicate(),
		"stats": _stats.duplicate(true),
		"presence": _presence,
	}


func _load() -> void:
	if not FileAccess.file_exists(MOCK_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOCK_PATH))
	if not (parsed is Dictionary):
		return
	var doc := parsed as Dictionary
	_achievements.clear()
	var listed: Variant = doc.get("achievements", [])
	if listed is Array:
		for item in listed:
			var clean := str(item).strip_edges()
			if clean != "":
				_achievements.append(clean)
	var stats: Variant = doc.get("stats", {})
	if stats is Dictionary:
		_stats = (stats as Dictionary).duplicate(true)
	_presence = str(doc.get("presence", ""))


func _save() -> void:
	var file := FileAccess.open(MOCK_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(get_state(), "\t"))
	file.close()
