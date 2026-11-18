@tool
extends EditorPlugin
## Registers core game-utils singletons and bus layout when enabled as an EditorPlugin.

const AUTOLOADS := {
	"SettingsStore": "res://addons/gu_core/settings/settings_store.gd",
	"InputRouter": "res://addons/gu_core/input/input_router.gd",
	"AudioManager": "res://addons/gu_core/audio/audio_manager.gd",
	"SaveService": "res://addons/gu_core/save/save_service.gd",
	"UIRouter": "res://addons/gu_core/ui/ui_router.gd",
	"GameFlow": "res://addons/gu_core/flow/game_flow.gd",
	"GameClock": "res://addons/gu_core/flow/game_clock.gd",
	"EventBus": "res://addons/gu_core/events/event_bus.gd",
	"PoolService": "res://addons/gu_core/pool/pool_service.gd",
	"DevConsole": "res://addons/gu_core/debug/dev_console.gd",
	"PlatformService": "res://addons/gu_core/platform/platform_service.gd",
}

const BUS_LAYOUT_PATH := "res://addons/gu_core/audio/default_bus_layout.tres"


func _enable_plugin() -> void:
	for singleton_name: String in AUTOLOADS:
		add_autoload_singleton(singleton_name, AUTOLOADS[singleton_name])
	if ProjectSettings.get_setting("audio/buses/default_bus_layout", "") == "":
		ProjectSettings.set_setting("audio/buses/default_bus_layout", BUS_LAYOUT_PATH)
		ProjectSettings.save()


func _disable_plugin() -> void:
	for singleton_name: String in AUTOLOADS:
		remove_autoload_singleton(singleton_name)
