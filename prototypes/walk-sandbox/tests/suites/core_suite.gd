extends "res://tests/support/test_suite_base.gd"
## gu_core singletons: input contexts, settings, audio, save, flow, and the theme.


func run_all() -> void:
	_test_input_router()
	_test_settings_store()
	_test_settings_locale()
	_test_audio_manager()
	_test_save_service()
	_test_saveables_roundtrip()
	_test_game_flow_and_ui_router()
	_test_protoss_ui_skin()


func _test_input_router() -> void:
	var router := InputRouterScript.new()
	_assert(router.is_gameplay_active(), "InputRouter defaults to GAMEPLAY active")
	_assert(router.allow_debug(), "InputRouter allows debug by default")

	router.push_context(InputRouterScript.Context.UI, &"pause")
	_assert(not router.is_gameplay_active(), "UI context blocks gameplay input")
	_assert(router.is_ui_active(), "UI context reports is_ui_active()")
	_assert(router.allow_debug(), "UI context still allows debug")

	router.push_context(InputRouterScript.Context.MODAL, &"confirm")
	_assert(not router.allow_debug(), "MODAL context blocks debug hotkeys")
	_assert(router.get_stack_size() == 2, "Stack size tracks distinct owners")

	# Re-pushing same owner updates in place without leaking entries
	router.push_context(InputRouterScript.Context.MODAL, &"confirm")
	_assert(router.get_stack_size() == 2, "Re-pushing same owner does not duplicate stack entries")

	router.pop_context(&"confirm")
	_assert(router.is_ui_active() and router.allow_debug(), "Popping MODAL restores UI context")

	router.pop_context(&"pause")
	_assert(router.is_gameplay_active(), "Popping UI restores GAMEPLAY context")
	router.free()


func _test_settings_store() -> void:
	var tmp_path := "user://test_settings_phase2.cfg"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)

	var store := SettingsStoreScript.new()
	store.config_path = tmp_path
	store.load_settings()

	_assert(is_equal_approx(float(store.get_value("master_volume")), 1.0), "SettingsStore default master_volume is 1.0")
	var emitted := []
	store.setting_changed.connect(func(k: String, v: Variant) -> void: emitted.append([k, v]))

	store.set_value("sfx_volume", 1.8) # should clamp to 1.0 (was 0.90)
	_assert(is_equal_approx(float(store.get_value("sfx_volume")), 1.0), "SettingsStore clamps sfx_volume <= 1.0")
	store.set_value("bgm_volume", -0.5) # should clamp to 0.0
	_assert(is_equal_approx(float(store.get_value("bgm_volume")), 0.0), "SettingsStore clamps bgm_volume >= 0.0")
	store.set_value("show_debug_hud", false)
	_assert(emitted.size() == 3, "setting_changed fires for each unique change")

	var reloaded := SettingsStoreScript.new()
	reloaded.config_path = tmp_path
	var err := reloaded.load_settings()
	_assert(err == OK, "SettingsStore loads saved ConfigFile cleanly")
	_assert(is_equal_approx(float(reloaded.get_value("bgm_volume")), 0.0), "Persisted bgm_volume survives reload")
	_assert(bool(reloaded.get_value("show_debug_hud")) == false, "Persisted show_debug_hud survives reload")

	reloaded.reset_defaults()
	_assert(bool(reloaded.get_value("show_debug_hud")) == true, "reset_defaults restores show_debug_hud")

	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	store.free()
	reloaded.free()


func _test_settings_locale() -> void:
	var prev_locale := TranslationServer.get_locale()
	var shipped = TranslationCatalogScript.new()
	var shipped_err: Error = shipped.load_dir("res://data")
	_assert(shipped_err == OK, "res://data localization catalog loads")
	var shipped_locales: PackedStringArray = shipped.get_locales()
	_assert(shipped_locales.has("en") and shipped_locales.has("zh"), "Shipped ui_i18n.csv exposes en and zh")
	_assert(shipped.message("zh", "SETTINGS_LANGUAGE") == "语言", "Shipped zh translation for SETTINGS_LANGUAGE")
	_assert(shipped.message("zh", "TITLE_CONTINUE") == "继续", "Title screen has a Chinese string")
	_assert(shipped.get_locales().size() == 2, "Locale aliases stay out of the language list")
	_assert(shipped.locale_label("zh") == "中文", "Locale autonym is read from that locale")
	shipped.unload()

	var tmp_cfg := "user://test_settings_locale.cfg"
	var tmp_dir := "user://test_i18n_catalog"
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)
	_wipe_user_dir(tmp_dir)
	DirAccess.make_dir_absolute(tmp_dir)

	var csv_file := FileAccess.open(tmp_dir.path_join("ui_i18n.csv"), FileAccess.WRITE)
	_assert(csv_file != null, "Locale fixture CSV opens")
	if csv_file != null:
		csv_file.store_string("keys,en,zh\nTEST_HELLO,\"Hello, world\",你好\nLOCALE_en,English,英语\nLOCALE_zh,Chinese,中文\n")
		csv_file.close()
	var manifest_file := FileAccess.open(tmp_dir.path_join("i18n_manifest.json"), FileAccess.WRITE)
	_assert(manifest_file != null, "Locale fixture manifest opens")
	if manifest_file != null:
		manifest_file.store_string("{\n  \"version\": 1,\n  \"default_locale\": \"en\",\n  \"locales\": [\"en\", \"zh\"],\n  \"files\": [\"ui_i18n.csv\"]\n}\n")
		manifest_file.close()

	var store := SettingsStoreScript.new()
	store.config_path = tmp_cfg
	store.translation_dir = tmp_dir
	store.load_settings()
	var err: Error = store.load_translations()
	_assert(err == OK, "SettingsStore loads localization CSV into TranslationServer")
	_assert(FontFallbackScript.is_applied(), "CJK font fallback is attached to ThemeDB")
	_assert(store.get_locales().size() == 2, "SettingsStore locales come from the catalog")
	store.set_value("locale", "zh")
	_assert(str(store.get_value("locale")) == "zh", "SettingsStore accepts catalog locale zh")
	_assert(TranslationServer.get_locale() == "zh", "SettingsStore applies locale through TranslationServer")
	_assert(tr("TEST_HELLO") == "你好", "Quoted CSV cell reaches TranslationServer for zh")
	_assert(store.locale_label("zh") == "中文", "SettingsStore locale_label uses the locale autonym")
	store.set_value("locale", "nope")
	_assert(str(store.get_value("locale")) == "en", "Unknown locale falls back to default_locale")
	_assert(TranslationServer.get_locale() == "en", "Fallback locale is applied to TranslationServer")

	store.set_value("locale", "zh")
	var reloaded := SettingsStoreScript.new()
	reloaded.config_path = tmp_cfg
	reloaded.translation_dir = tmp_dir
	var load_err := reloaded.load_settings()
	_assert(load_err == OK and str(reloaded.get_value("locale")) == "zh", "Persisted locale survives SettingsStore reload")
	_assert(reloaded.load_translations() == OK, "Reloaded SettingsStore loads the same catalog")
	_assert(TranslationServer.get_locale() == "zh" and tr("TEST_HELLO") == "你好", "Reloaded locale is applied to TranslationServer")
	reloaded.reset_defaults()
	_assert(str(reloaded.get_value("locale")) == "en" and TranslationServer.get_locale() == "en", "reset_defaults restores locale en")
	_assert(tr("TEST_HELLO") == "Hello, world", "Quoted comma in the en column survives CSV parsing")

	store.clear_translations()
	reloaded.clear_translations()
	TranslationServer.set_locale(prev_locale)
	store.free()
	reloaded.free()
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)
	_wipe_user_dir(tmp_dir)


func _test_audio_manager() -> void:
	var am := AudioManagerScript.new()
	am.ensure_buses()
	for bus_name: StringName in AudioManagerScript.REQUIRED_BUSES:
		_assert(AudioServer.get_bus_index(bus_name) >= 0, "AudioServer has bus '%s'" % String(bus_name))

	am.set_bus_volume(AudioManagerScript.BUS_SFX, 1.5)
	_assert(is_equal_approx(am.get_bus_volume(AudioManagerScript.BUS_SFX), 1.0), "AudioManager clamps bus volume <= 1.0")

	am.set_bus_volume(AudioManagerScript.BUS_BGM, 0.0)
	var bgm_idx := AudioServer.get_bus_index(AudioManagerScript.BUS_BGM)
	_assert(AudioServer.is_bus_mute(bgm_idx), "AudioManager mutes bus when linear volume is 0.0")

	am.set_bus_volume(AudioManagerScript.BUS_BGM, 0.5)
	_assert(not AudioServer.is_bus_mute(bgm_idx), "AudioManager unmutes bus when linear volume > 0")
	_assert(not am.is_shutting_down(), "AudioManager is not shutting down initially")

	get_root().add_child(am)
	var sfx_stream := AudioStreamWAV.new()
	var p3d := am.play_sfx_at(Vector3(4.0, 1.5, -2.0), sfx_stream, -6.0)
	_assert(am.get_sfx3d_pool_size() == AudioManagerScript.SFX3D_POOL_SIZE, "AudioManager creates 3D SFX pool")
	_assert(p3d != null and p3d.stream == sfx_stream, "AudioManager.play_sfx_at assigns stream")
	_assert(p3d.global_position.is_equal_approx(Vector3(4.0, 1.5, -2.0)), "AudioManager.play_sfx_at sets 3D position")
	_assert(p3d.bus == AudioManagerScript.BUS_SFX, "AudioManager.play_sfx_at routes through SFX bus")

	var dummy_player := AudioStreamPlayer.new()
	dummy_player.stream = AudioStreamWAV.new()
	get_root().add_child(dummy_player)
	am.prepare_shutdown()
	_assert(am.is_shutting_down(), "AudioManager marks shutting down on prepare_shutdown()")
	_assert(dummy_player.stream == null, "AudioManager.prepare_shutdown() clears scene AudioStreamPlayer streams")
	get_root().remove_child(dummy_player)
	dummy_player.free()
	get_root().remove_child(am)
	am.free()


func _test_save_service() -> void:
	var tmp_dir := "user://test_saves_phase2"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir

	_assert(svc.sanitize_slot("../bad/slot!@#") == "badslot", "sanitize_slot strips path traversal & symbols")

	var sample_payload := {
		"world": {"seed": 9876, "landform": 2, "relief": 1.0},
		"sky": {"hour": 14.25, "weather": 3, "speed_index": 1},
		"player": {"position": [1.5, 2.0, -3.5], "facing_yaw": 0.5, "run_mode": true},
	}
	var save_err := svc.save_slot("test_slot", sample_payload)
	_assert(save_err == OK, "SaveService writes slot cleanly")
	_assert(svc.has_slot("test_slot"), "SaveService reports slot exists")

	var loaded := svc.load_slot("test_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService loads valid slot")
	var ldata: Dictionary = loaded["data"] as Dictionary
	_assert(int((ldata["world"] as Dictionary)["seed"]) == 9876, "SaveService preserves world seed")

	# Deterministic regeneration check from saved seed + landform
	var w: Dictionary = ldata["world"] as Dictionary
	var m1: MapData = MapGen.generate(int(w["seed"]), {"landform": int(w["landform"]), "relief": float(w["relief"])})
	var m2: MapData = MapGen.generate(int(w["seed"]), {"landform": int(w["landform"]), "relief": float(w["relief"])})
	_assert(is_equal_approx(m1.sample_height(5.0, -5.0), m2.sample_height(5.0, -5.0)), "Saved seed reproduces exact heightfield")

	# Corrupt JSON & unsupported schema validation
	var bad_path := svc.get_slot_path("corrupt")
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("{not valid json")
	f.close()
	var bad_res := svc.load_slot("corrupt")
	_assert(not bool(bad_res.get("ok", true)), "SaveService rejects corrupt JSON cleanly")

	var old_ver_path := svc.get_slot_path("bad_ver")
	var f2 := FileAccess.open(old_ver_path, FileAccess.WRITE)
	f2.store_string('{"schema_version": 999, "world": {"seed": 1}}')
	f2.close()
	var ver_res := svc.load_slot("bad_ver")
	_assert(not bool(ver_res.get("ok", true)), "SaveService rejects unsupported schema_version")

	svc.delete_slot("test_slot")
	svc.delete_slot("corrupt")
	svc.delete_slot("bad_ver")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()


func _test_saveables_roundtrip() -> void:
	var tmp_dir := "user://test_saves_saveables"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir

	var stats := StatSet.new()
	stats.define_stat(&"stamina", 100.0, 55.0)
	stats.add_modifier(&"stamina", &"well_fed", 10.0, 1.0)
	svc.register_saveable("player_stats", stats)

	var err := svc.save_slot("stats", {"world": {"seed": 1}})
	_assert(err == OK, "SaveService writes registered saveables")
	stats.set_value(&"stamina", 1.0)
	stats.remove_modifier(&"stamina", &"well_fed")

	var loaded := svc.load_slot("stats")
	_assert(bool(loaded.get("ok", false)), "Save slot with saveables loads")
	svc.apply_saveables(loaded.get("data", {}) as Dictionary)
	_assert(is_equal_approx(stats.get_value(&"stamina"), 55.0), "Save roundtrip restores current stamina")
	_assert(is_equal_approx(stats.get_max(&"stamina"), 110.0), "Save roundtrip restores stat modifiers")

	svc.delete_slot("stats")
	_wipe_user_dir(tmp_dir)
	svc.free()


func _test_game_flow_and_ui_router() -> void:
	# Verify autoloads registered in project.godot work inside SceneTree
	var flow := get_root().get_node_or_null("GameFlow")
	var ui := get_root().get_node_or_null("UIRouter")
	var input_router := get_root().get_node_or_null("InputRouter")
	_assert(flow != null and ui != null and input_router != null, "Autoloads GameFlow, UIRouter, InputRouter exist on SceneTree root")
	if flow == null or ui == null or input_router == null:
		return

	var mock_world := MockWorld.new()
	get_root().add_child(mock_world)
	flow.call("register_world", mock_world)

	var dummy_scene := PackedScene.new()
	var dummy_ctrl := Control.new()
	dummy_scene.pack(dummy_ctrl)
	dummy_ctrl.free()

	ui.call("register_screen", &"title", dummy_scene)
	ui.call("register_screen", &"pause", dummy_scene)
	ui.call("register_screen", &"settings", dummy_scene)

	flow.call("enter_title")
	_assert(int(flow.call("get_state")) == GameFlowScript.State.TITLE, "GameFlow transitions to TITLE")
	_assert(ui.call("top_screen_id") == &"title", "UIRouter shows title screen on enter_title()")
	_assert(not bool(input_router.call("is_gameplay_active")), "TITLE blocks gameplay input via UIRouter")

	flow.call("start_new_game", {"seed": 123})
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PLAYING, "GameFlow transitions to PLAYING on start_new_game()")
	_assert(mock_world.started_count == 1, "start_new_game invokes world.start_new_world()")
	_assert(bool(input_router.call("is_gameplay_active")), "PLAYING restores GAMEPLAY input context")

	flow.call("set_paused", true)
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PAUSED, "GameFlow transitions to PAUSED")
	_assert(paused, "SceneTree.paused becomes true when PAUSED")
	_assert(ui.call("top_screen_id") == &"pause", "UIRouter shows pause screen when PAUSED")

	flow.call("open_settings")
	_assert(ui.call("top_screen_id") == &"settings", "open_settings pushes settings over pause")
	flow.call("close_top_ui")
	_assert(ui.call("top_screen_id") == &"pause", "close_top_ui returns from settings to pause")
	flow.call("close_top_ui")
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PLAYING, "Closing pause screen resumes PLAYING")
	_assert(not paused, "SceneTree.paused becomes false after resume")

	flow.call("return_to_title")
	_assert(int(flow.call("get_state")) == GameFlowScript.State.TITLE, "return_to_title transitions back to TITLE")
	ui.call("clear_screens")

	# Toast queue + modal confirm + transition curtain checks
	ui.call("clear_toasts")
	ui.call("show_toast", "Toast 1", 1.0, &"info")
	ui.call("show_toast", "Toast 2", 1.0, &"success")
	ui.call("show_toast", "Toast 3", 1.0, &"warning")
	ui.call("show_toast", "Toast 4", 1.0, &"error")
	_assert(int(ui.call("get_active_toast_count")) == 3, "UIRouter caps active toasts at MAX_ACTIVE_TOASTS")
	_assert(int(ui.call("get_queued_toast_count")) == 1, "UIRouter queues excess toasts")
	ui.call("clear_toasts")

	var confirm_hits := [0]
	var dlg := ui.call("show_confirm", "Confirm", "Test body", func() -> void: confirm_hits[0] += 1) as Control
	_assert(dlg != null, "UIRouter.show_confirm returns dialog node")
	_assert(ui.call("top_screen_id") == UIRouterScript.CONFIRM_SCREEN_ID, "show_confirm pushes modal onto UIRouter")
	_assert(not bool(input_router.call("allow_debug")), "show_confirm activates InputRouter.Context.MODAL")
	dlg.call("confirm")
	_assert(confirm_hits[0] == 1, "ConfirmDialog.confirm invokes callback")
	_assert(bool(input_router.call("allow_debug")), "ConfirmDialog.confirm restores InputRouter context")

	ui.call("fade_out", 0.0)
	_assert(is_equal_approx(float(ui.call("get_transition_alpha")), 1.0), "UIRouter.fade_out reaches opaque")
	ui.call("fade_in", 0.0)
	_assert(is_equal_approx(float(ui.call("get_transition_alpha")), 0.0), "UIRouter.fade_in returns transparent")

	mock_world.queue_free()


func _test_protoss_ui_skin() -> void:
	var theme_path := "res://addons/gu_core/ui/protoss/protoss_theme.tres"
	var theme := load(theme_path) as Theme
	_assert(theme != null, "Protoss theme loads cleanly")
	if theme != null:
		_assert(theme.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "Protoss theme defines StyleBoxTexture for PanelContainer")
		_assert(theme.get_stylebox("normal", "Button") is StyleBoxTexture, "Protoss theme defines StyleBoxTexture for Button normal")
		_assert(theme.get_stylebox("hover", "Button") is StyleBoxTexture, "Protoss theme defines StyleBoxTexture for Button hover")
		_assert(theme.get_icon("grabber", "HSlider") is Texture2D, "Protoss theme defines HSlider grabber icon")
		_assert(theme.get_icon("checked", "CheckButton") is Texture2D, "Protoss theme defines CheckButton checked icon")

	var sfx_paths := [
		"res://addons/gu_core/audio/sfx/protoss_hover.wav",
		"res://addons/gu_core/audio/sfx/protoss_click.wav",
		"res://addons/gu_core/audio/sfx/protoss_back.wav",
		"res://addons/gu_core/audio/sfx/protoss_open.wav",
	]
	for p: String in sfx_paths:
		_assert(load(p) is AudioStream, "Protoss UI SFX loads cleanly: %s" % p)

	var plain := load("res://addons/gu_core/ui/default_theme.tres") as Theme
	_assert(plain != null, "Gray theme loads cleanly")
	if plain != null:
		_assert(plain.get_stylebox("panel", "PanelContainer") is StyleBoxFlat, "Gray theme uses a flat panel")
		_assert(plain.get_stylebox("normal", "Button") is StyleBoxFlat, "Gray theme uses a flat button")
	var ui := get_root().get_node_or_null("UIRouter")
	_assert(ui != null, "UIRouter autoload available for theme check")
	if ui != null:
		var stack_root := ui.get_node_or_null("UIRouterLayer/ScreenStack") as Control
		_assert(stack_root != null and stack_root.theme == plain, "UIRouter uses the gray theme")

	var screen_paths := [
		"res://scenes/ui/title_screen.tscn",
		"res://scenes/ui/pause_menu.tscn",
		"res://scenes/ui/settings_panel.tscn",
		"res://addons/gu_core/ui/save_slots_panel.tscn",
	]
	for sp: String in screen_paths:
		var packed := load(sp) as PackedScene
		_assert(packed != null, "UI scene loads cleanly: %s" % sp)
		if packed != null:
			var inst := packed.instantiate() as Control
			_assert(inst != null, "UI scene instantiates as Control: %s" % sp)
			if inst != null:
				get_root().add_child(inst)
				if inst.has_method("on_ui_enter"):
					inst.call("on_ui_enter", {})
				var panel := inst.get_node_or_null("%Panel") as PanelContainer
				_assert(panel != null, "UI scene exposes %%Panel container: %s" % sp)
				get_root().remove_child(inst)
				inst.free()
