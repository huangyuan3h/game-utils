class_name StatBar
extends VBoxContainer
## One labeled bar bound to a [StatSet] stat or a [HealthComponent].


var _stats: StatSet
var _stat_id: StringName = &""
var _title := Label.new()
var _value := Label.new()
var _bar := ProgressBar.new()


func _init() -> void:
	add_theme_constant_override("separation", 2)
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	_value.add_theme_font_size_override("font_size", 12)
	_value.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(180, 10)
	add_child(_title)
	add_child(_bar)
	add_child(_value)


func bind_stat(stats: StatSet, stat_id: StringName, title: String) -> void:
	unbind()
	_stats = stats
	_stat_id = stat_id
	_title.text = title
	if _stats != null and not _stats.stat_changed.is_connected(_on_stat_changed):
		_stats.stat_changed.connect(_on_stat_changed)
	_refresh()


func bind_health(health: HealthComponent, title: String) -> void:
	if health == null:
		unbind()
		return
	bind_stat(health.get_stats(), health.stat_id, title)


func unbind() -> void:
	if _stats != null and _stats.stat_changed.is_connected(_on_stat_changed):
		_stats.stat_changed.disconnect(_on_stat_changed)
	_stats = null
	_stat_id = &""


func _exit_tree() -> void:
	unbind()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		unbind()


func get_displayed_ratio() -> float:
	return float(_bar.value)


func get_value_text() -> String:
	return _value.text


func _on_stat_changed(stat_id: StringName, _current: float, _maximum: float) -> void:
	if stat_id == _stat_id:
		_refresh()


func _refresh() -> void:
	if _stats == null or _stat_id == &"":
		_bar.value = 0.0
		_value.text = ""
		return
	var current := _stats.get_value(_stat_id)
	var maximum := _stats.get_max(_stat_id)
	_bar.value = _stats.get_ratio(_stat_id)
	_value.text = "%s / %s" % [_format_number(current), _format_number(maximum)]


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
