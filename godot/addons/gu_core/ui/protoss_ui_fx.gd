class_name ProtossUiFx
extends RefCounted
## Protoss UI interaction feedback helper: binds crystalline SFX via AudioManager
## and pause-safe Tweens for hover highlights and holographic panel entry animations.

const SFX_HOVER_PATH := "res://addons/gu_core/audio/sfx/protoss_hover.wav"
const SFX_CLICK_PATH := "res://addons/gu_core/audio/sfx/protoss_click.wav"
const SFX_BACK_PATH := "res://addons/gu_core/audio/sfx/protoss_back.wav"
const SFX_OPEN_PATH := "res://addons/gu_core/audio/sfx/protoss_open.wav"

const META_BOUND := &"_protoss_fx_bound"
const META_IS_BACK := &"_protoss_fx_is_back"


static func attach_tree(root: Node, back_buttons: Array = []) -> void:
	if root == null:
		return
	for btn in back_buttons:
		if btn is Node and is_instance_valid(btn):
			(btn as Node).set_meta(META_IS_BACK, true)
	_attach_recursive(root, root)


static func animate_panel_enter(panel: Control, owner_tree_node: Node = null, play_sfx: bool = true) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var host := owner_tree_node if owner_tree_node != null else panel
	if not host.is_inside_tree():
		return

	if play_sfx:
		play_open_sound(host)

	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var base_size := panel.size if panel.size.x > 1.0 and panel.size.y > 1.0 else panel.get_combined_minimum_size()
	panel.pivot_offset = base_size * 0.5
	panel.scale = Vector2(0.96, 0.92)

	var tw := host.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func play_hover_sound(host: Node) -> void:
	_play_ui_sfx(host, SFX_HOVER_PATH, 0.04)


static func play_click_sound(host: Node) -> void:
	_play_ui_sfx(host, SFX_CLICK_PATH, 0.03)


static func play_back_sound(host: Node) -> void:
	_play_ui_sfx(host, SFX_BACK_PATH, 0.02)


static func play_open_sound(host: Node) -> void:
	_play_ui_sfx(host, SFX_OPEN_PATH, 0.01)


static func _attach_recursive(node: Node, host: Node) -> void:
	if node is CheckButton:
		_bind_check_button(node as CheckButton, host)
	elif node is BaseButton:
		_bind_button(node as BaseButton, host)
	elif node is HSlider:
		_bind_slider(node as HSlider, host)

	for child in node.get_children():
		_attach_recursive(child, host)


static func _bind_button(btn: BaseButton, host: Node) -> void:
	if btn.has_meta(META_BOUND):
		return
	btn.set_meta(META_BOUND, true)

	btn.mouse_entered.connect(func() -> void:
		if not is_instance_valid(btn) or btn.disabled:
			return
		play_hover_sound(host)
		_tween_hover(btn, host, true)
	)
	btn.mouse_exited.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		_tween_hover(btn, host, false)
	)
	btn.focus_entered.connect(func() -> void:
		if not is_instance_valid(btn) or btn.disabled:
			return
		play_hover_sound(host)
	)
	btn.pressed.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		if btn.has_meta(META_IS_BACK):
			play_back_sound(host)
		else:
			play_click_sound(host)
	)


static func _bind_check_button(chk: CheckButton, host: Node) -> void:
	if chk.has_meta(META_BOUND):
		return
	chk.set_meta(META_BOUND, true)

	chk.mouse_entered.connect(func() -> void:
		if not is_instance_valid(chk) or chk.disabled:
			return
		play_hover_sound(host)
		_tween_hover(chk, host, true)
	)
	chk.mouse_exited.connect(func() -> void:
		if not is_instance_valid(chk):
			return
		_tween_hover(chk, host, false)
	)
	chk.toggled.connect(func(on: bool) -> void:
		if not is_instance_valid(chk):
			return
		if on:
			play_click_sound(host)
		else:
			play_back_sound(host)
	)


static func _bind_slider(slider: HSlider, host: Node) -> void:
	if slider.has_meta(META_BOUND):
		return
	slider.set_meta(META_BOUND, true)

	slider.mouse_entered.connect(func() -> void:
		if not is_instance_valid(slider) or not slider.editable:
			return
		play_hover_sound(host)
	)
	slider.drag_started.connect(func() -> void:
		if not is_instance_valid(slider):
			return
		play_click_sound(host)
	)


static func _tween_hover(ctrl: Control, host: Node, active: bool) -> void:
	if not host.is_inside_tree():
		return
	var target_mod := Color(1.08, 1.08, 1.12, 1.0) if active else Color.WHITE
	var tw := host.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(ctrl, "modulate", target_mod, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _play_ui_sfx(host: Node, path: String, pitch_jitter: float) -> void:
	if host == null or not host.is_inside_tree():
		return
	var audio_mgr := host.get_node_or_null("/root/AudioManager")
	if audio_mgr == null or not audio_mgr.has_method("play_ui"):
		return
	var stream := _get_stream(path)
	if stream != null:
		audio_mgr.call("play_ui", stream, pitch_jitter)


static func _get_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as AudioStream
