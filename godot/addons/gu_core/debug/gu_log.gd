class_name GuLog
extends RefCounted
## Lightweight ring-buffered structured logger with optional file sink.

enum Level { DEBUG, INFO, WARN, ERROR }

const MAX_ENTRIES := 200
const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]

static var _entries: Array[Dictionary] = []
static var _log_file_path: String = ""


static func set_log_file(path: String) -> void:
	_log_file_path = path
	if path == "":
		return
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)


static func debug(tag: String, message: String) -> void:
	_append(Level.DEBUG, tag, message)


static func info(tag: String, message: String) -> void:
	_append(Level.INFO, tag, message)


static func warn(tag: String, message: String) -> void:
	_append(Level.WARN, tag, message)


static func error(tag: String, message: String) -> void:
	_append(Level.ERROR, tag, message)


static func get_entries(min_level: int = Level.DEBUG) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _entries:
		if int(e["level"]) >= min_level:
			out.append(e.duplicate())
	return out


static func format_entries(limit: int = 20, min_level: int = Level.DEBUG) -> String:
	var filtered := get_entries(min_level)
	var start := maxi(0, filtered.size() - limit)
	var lines: Array[String] = []
	for i in range(start, filtered.size()):
		var e := filtered[i]
		lines.append("[%s][%s] %s" % [e["level_name"], e["tag"], e["message"]])
	return "\n".join(lines)


static func clear() -> void:
	_entries.clear()


static func _append(level: int, tag: String, message: String) -> void:
	var lvl_idx := clampi(level, 0, LEVEL_NAMES.size() - 1)
	var entry := {
		"level": lvl_idx,
		"level_name": LEVEL_NAMES[lvl_idx],
		"tag": tag,
		"message": message,
		"ts": Time.get_time_string_from_system(),
	}
	_entries.append(entry)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()

	if _log_file_path != "":
		var line := "%s [%s][%s] %s\n" % [entry["ts"], entry["level_name"], tag, message]
		var mode := FileAccess.READ_WRITE if FileAccess.file_exists(_log_file_path) else FileAccess.WRITE
		var f := FileAccess.open(_log_file_path, mode)
		if f != null:
			f.seek_end()
			f.store_string(line)
			f.close()
