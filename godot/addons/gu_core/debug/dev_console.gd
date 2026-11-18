extends Node
## In-game developer command console toggled with backtick (`), pushing MODAL input context.

signal command_executed(line: String, output: String)
signal toggled(open: bool)

const TOGGLE_ACTION := &"toggle_dev_console"
const BugReportScript := preload("res://addons/gu_core/debug/bug_report.gd")
const CONTEXT_OWNER := &"dev_console"

var input_router: Node = null

var _commands: Dictionary = {} ## String -> {"desc": String, "handler": Callable}
var _order: Array[String] = []
var _is_open: bool = false
var _history: Array[String] = []

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _output_label: RichTextLabel = null
var _input_edit: LineEdit = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_toggle_action()
	_register_builtins()


func is_open() -> bool:
	return _is_open


func set_open(open: bool) -> void:
	if _is_open == open:
		return
	_is_open = open
	var ir := _get_input_router()
	if _is_open:
		_ensure_ui()
		_panel.visible = true
		if ir != null and ir.has_method("push_context"):
			ir.call("push_context", 2, CONTEXT_OWNER) # InputRouter.Context.MODAL == 2
		if _input_edit != null and is_inside_tree():
			_input_edit.call_deferred("grab_focus")
	else:
		if _panel != null:
			_panel.visible = false
		if ir != null and ir.has_method("pop_context"):
			ir.call("pop_context", CONTEXT_OWNER)
	toggled.emit(_is_open)


func toggle() -> void:
	set_open(not _is_open)


func register_command(cmd_name: String, description: String, handler: Callable) -> void:
	var key := cmd_name.strip_edges().to_lower()
	if key == "" or not handler.is_valid():
		return
	if not _commands.has(key):
		_order.append(key)
	_commands[key] = {"desc": description, "handler": handler}


func unregister_command(cmd_name: String) -> void:
	var key := cmd_name.strip_edges().to_lower()
	if _commands.erase(key):
		_order.erase(key)


func has_command(cmd_name: String) -> bool:
	return _commands.has(cmd_name.strip_edges().to_lower())


func execute(line: String) -> String:
	var trimmed := line.strip_edges()
	if trimmed == "":
		return ""
	_history.append(trimmed)
	var tokens := _tokenize(trimmed)
	if tokens.is_empty():
		return ""

	var cmd := tokens[0].to_lower()
	var args: Array[String] = []
	for i in range(1, tokens.size()):
		args.append(tokens[i])

	var output := ""
	if not _commands.has(cmd):
		output = "Unknown command '%s'. Type 'help' for commands." % cmd
		GuLog.warn("DevConsole", output)
	else:
		var handler: Callable = (_commands[cmd] as Dictionary)["handler"] as Callable
		var res: Variant = handler.call(args)
		output = str(res) if res != null else "OK"
		GuLog.info("DevConsole", "> %s -> %s" % [trimmed, output])

	_append_output("> %s\n%s" % [trimmed, output])
	command_executed.emit(trimmed, output)
	return output


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F9:
		write_bug_report()
		get_viewport().set_input_as_handled()
		return
	if not InputMap.has_action(TOGGLE_ACTION):
		return
	if event.is_action_pressed(TOGGLE_ACTION):
		var ir := _get_input_router()
		if _is_open or ir == null or bool(ir.call("allow_debug")):
			toggle()
			get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func write_bug_report(dir_path: String = "user://bug_reports/latest", position: Vector3 = Vector3.ZERO) -> String:
	var save_text := ""
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("get_slot_path"):
		var slot_path := str(save_svc.call("get_slot_path", "autosave"))
		if FileAccess.file_exists(slot_path):
			save_text = FileAccess.get_file_as_string(slot_path)
	var world_seconds := 0.0
	var clock := get_node_or_null("/root/GameClock")
	if clock != null and clock.has_method("export_state"):
		var clock_state: Dictionary = clock.call("export_state") as Dictionary
		world_seconds = float(clock_state.get("world_seconds", 0.0))
	return BugReportScript.write_pack(dir_path, position, save_text, world_seconds)


func _register_builtins() -> void:
	register_command("help", "List available console commands", func(_args: Array[String]) -> String:
		var lines: Array[String] = []
		for k: String in _order:
			var desc := str((_commands[k] as Dictionary)["desc"])
			lines.append("%s - %s" % [k, desc])
		return "\n".join(lines)
	)
	register_command("clear", "Clear console output", func(_args: Array[String]) -> String:
		if _output_label != null:
			_output_label.text = ""
		return ""
	)
	register_command("echo", "Echo arguments", func(args: Array[String]) -> String:
		return " ".join(args)
	)
	register_command("logs", "Show recent GuLog entries [limit]", func(args: Array[String]) -> String:
		var limit := int(args[0]) if not args.is_empty() else 15
		var txt := GuLog.format_entries(maxi(1, limit))
		return txt if txt != "" else "(no log entries)"
	)
	register_command("toast", "Show a UIRouter toast <message>", func(args: Array[String]) -> String:
		var msg := " ".join(args) if not args.is_empty() else "DevConsole toast"
		var ui := get_node_or_null("/root/UIRouter")
		if ui != null and ui.has_method("show_toast"):
			ui.call("show_toast", msg, 2.0, &"info")
			return "Toast shown."
		return "UIRouter unavailable."
	)
	register_command("save", "Save current game [slot]", func(args: Array[String]) -> String:
		var slot := args[0] if not args.is_empty() else ""
		var flow := get_node_or_null("/root/GameFlow")
		if flow != null and flow.has_method("save_current_game"):
			var err := int(flow.call("save_current_game", slot))
			return "Saved (err=%d)" % err
		return "GameFlow unavailable."
	)
	register_command("load", "Load saved game [slot]", func(args: Array[String]) -> String:
		var slot := args[0] if not args.is_empty() else ""
		var flow := get_node_or_null("/root/GameFlow")
		if flow != null and flow.has_method("load_game"):
			return "Loaded" if bool(flow.call("load_game", slot)) else "Load failed."
		return "GameFlow unavailable."
	)


func _ensure_ui() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.name = "DevConsoleLayer"
	_layer.layer = 120
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.name = "ConsolePanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = 280.0
	_panel.visible = false
	_layer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_output_label = RichTextLabel.new()
	_output_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output_label.scroll_following = true
	vbox.add_child(_output_label)

	_input_edit = LineEdit.new()
	_input_edit.placeholder_text = "Type command (e.g. help)..."
	_input_edit.text_submitted.connect(_on_submitted)
	vbox.add_child(_input_edit)


func _on_submitted(text: String) -> void:
	if _input_edit != null:
		_input_edit.text = ""
	execute(text)


func _append_output(txt: String) -> void:
	if _output_label == null or txt == "":
		return
	_output_label.append_text(txt + "\n")


func _tokenize(line: String) -> Array[String]:
	var tokens: Array[String] = []
	var cur := ""
	var in_quote := false
	for i in line.length():
		var ch := line[i]
		if ch == "\"":
			in_quote = not in_quote
		elif ch == " " and not in_quote:
			if cur != "":
				tokens.append(cur)
				cur = ""
		else:
			cur += ch
	if cur != "":
		tokens.append(cur)
	return tokens


func _get_input_router() -> Node:
	if input_router != null and is_instance_valid(input_router):
		return input_router
	return get_node_or_null("/root/InputRouter")


func _ensure_toggle_action() -> void:
	var ir := _get_input_router()
	if ir != null and ir.has_method("register_action"):
		ir.call("register_action", TOGGLE_ACTION, [KEY_QUOTELEFT], "Toggle Dev Console")
	elif not InputMap.has_action(String(TOGGLE_ACTION)):
		InputMap.add_action(String(TOGGLE_ACTION))
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_QUOTELEFT
		InputMap.action_add_event(String(TOGGLE_ACTION), ev)
