class_name SceneLoader
extends Node
## Threaded PackedScene loader with progress signals and async await helper.

signal progress_changed(scene_path: String, progress: float)
signal scene_loaded(scene_path: String, packed: PackedScene)
signal load_failed(scene_path: String, status: int)

var _active_path: String = ""
var _progress: float = 0.0
var _loading: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_loading() -> bool:
	return _loading


func get_progress() -> float:
	return _progress


func get_active_path() -> String:
	return _active_path


func request_load(scene_path: String) -> Error:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		load_failed.emit(scene_path, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
		return ERR_FILE_NOT_FOUND
	if _loading:
		return ERR_BUSY

	var err := ResourceLoader.load_threaded_request(scene_path)
	if err != OK:
		load_failed.emit(scene_path, ResourceLoader.THREAD_LOAD_FAILED)
		return err

	_active_path = scene_path
	_progress = 0.0
	_loading = true
	return OK


func load_packed_async(scene_path: String) -> PackedScene:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return null
	if not is_inside_tree():
		return ResourceLoader.load(scene_path) as PackedScene

	var err := request_load(scene_path)
	if err != OK:
		return null

	while _loading:
		await get_tree().process_frame
		if not _loading:
			break
		_poll_once()

	var res := ResourceLoader.load_threaded_get(scene_path)
	return res as PackedScene


func _process(_delta: float) -> void:
	if _loading:
		_poll_once()


func _poll_once() -> void:
	if not _loading or _active_path == "":
		return
	var prog := []
	var status := ResourceLoader.load_threaded_get_status(_active_path, prog)
	if not prog.is_empty():
		_progress = clampf(float(prog[0]), 0.0, 1.0)
		progress_changed.emit(_active_path, _progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			var finished_path := _active_path
			var packed := ResourceLoader.load_threaded_get(finished_path) as PackedScene
			_progress = 1.0
			_loading = false
			_active_path = ""
			if packed != null:
				scene_loaded.emit(finished_path, packed)
			else:
				load_failed.emit(finished_path, ResourceLoader.THREAD_LOAD_FAILED)
		_:
			var failed_path := _active_path
			_loading = false
			_active_path = ""
			load_failed.emit(failed_path, status)
