class_name BugReport
extends RefCounted
## Writes a small on-disk pack: log, screenshot, save copy, and player position.

static func write_pack(dir_path: String, position: Vector3, save_text: String, world_seconds: float = 0.0) -> String:
	var absolute := ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(absolute)
	var log_file := FileAccess.open(absolute.path_join("log.txt"), FileAccess.WRITE)
	if log_file != null:
		log_file.store_string(GuLog.format_entries(GuLog.MAX_ENTRIES))
		log_file.close()
	var save_file := FileAccess.open(absolute.path_join("save.json"), FileAccess.WRITE)
	if save_file != null:
		save_file.store_string(save_text if save_text != "" else "{}\n")
		save_file.close()
	var pos_file := FileAccess.open(absolute.path_join("position.json"), FileAccess.WRITE)
	if pos_file != null:
		pos_file.store_string(JSON.stringify({
			"x": position.x,
			"y": position.y,
			"z": position.z,
			"world_seconds": world_seconds,
		}))
		pos_file.close()
	var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.4, 0.8))
	image.save_png(absolute.path_join("screenshot.png"))
	return absolute
