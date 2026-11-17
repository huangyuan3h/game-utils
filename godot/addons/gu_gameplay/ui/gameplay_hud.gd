class_name GameplayHud
extends CanvasLayer
## Always-on stat and quest readouts, plus a centered inventory panel.


var stats_root: VBoxContainer
var quests: QuestHud
var inventory: InventoryPanel


func _init() -> void:
	layer = 12
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	stats_root = VBoxContainer.new()
	stats_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stats_root.offset_left = 16.0
	stats_root.offset_top = 16.0
	stats_root.offset_right = 220.0
	stats_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_root.add_theme_constant_override("separation", 8)
	root.add_child(stats_root)

	quests = QuestHud.new()
	quests.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	quests.offset_left = -280.0
	quests.offset_top = 16.0
	quests.offset_right = -16.0
	quests.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(quests)

	inventory = InventoryPanel.new()
	inventory.set_anchors_preset(Control.PRESET_CENTER)
	inventory.offset_left = -150.0
	inventory.offset_top = -140.0
	inventory.offset_right = 150.0
	inventory.offset_bottom = 140.0
	root.add_child(inventory)


func bind_player_hud(stats: StatSet, stat_id: StringName, inv: InventoryContainer, tracker: QuestTracker, stat_title: String = "") -> void:
	for child in stats_root.get_children():
		var bar := child as StatBar
		if bar != null:
			bar.unbind()
		child.queue_free()
	var title := stat_title if stat_title != "" else String(stat_id).capitalize()
	var bar := StatBar.new()
	stats_root.add_child(bar)
	bar.bind_stat(stats, stat_id, title)
	inventory.bind_inventory(inv)
	quests.bind_tracker(tracker)


func add_stat_bar(stats: StatSet, stat_id: StringName, title: String) -> StatBar:
	var bar := StatBar.new()
	stats_root.add_child(bar)
	bar.bind_stat(stats, stat_id, title)
	return bar
