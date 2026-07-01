extends Node

@export var engine: RPGMakerPlayer

@export var game_resolution: Vector2i = Vector2i(320, 240):
	set(value):
		game_resolution = value
		if engine != null and engine.is_running():
			engine.set_resolution(value.x, value.y)

@export var open_save_menu: bool = false:
	set(value):
		if value:
			open_save_menu = false
			do_open_save_menu()

@export var open_load_menu: bool = false:
	set(value):
		if value:
			open_load_menu = false
			do_open_load_menu()

@export var open_debug_menu: bool = false:
	set(value):
		if value:
			open_debug_menu = false
			do_open_debug_menu()

func do_open_save_menu() -> void:
	var e := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if e and e.is_running(): e.open_save_menu()
	else: Log.error("Engine is not running!")

func do_open_load_menu() -> void:
	var e := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if e and e.is_running(): e.open_load_menu()
	else: Log.error("Engine is not running!")

func do_open_debug_menu() -> void:
	var e := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if e and e.is_running(): e.open_debug_menu()
	else: Log.error("Engine is not running!")

func set_resolution_scale(scale: float) -> void:
	var e := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if scale < 0.75 or scale > 2.:
		Log.error("Keep scale in range of [0.75, 2.0]")
	if e and e.is_running():
		var x: int = floor(320. * scale)
		var y: int = floor(240. * scale)
		e.set_resolution(x, y)
		Log.info("Rendering %d x %d pixels" % [x, y])
	else: Log.error("Engine is not running!")

# p4o-a7o: maybe make this action accessible from a toolbar menu later
# i added this so its at least possible to disable/enable the chat
# while playing the game
func chat_command(enabled: bool) -> void:
	var e := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if e:
		if not e.is_running():
			Log.warn("Engine is not running!")
			return
		var mp_node := e.get_node_or_null("./MpNode") as EasyMultiplayer
		if not mp_node:
			Log.warn("You are not connected to multiplayer!")
			return
		mp_node.set_enable_chat(enabled)
		var chat_layer: CanvasLayer = %ChatOverlayLayer
		var chat_ctrl: Node = %ChatControl
		var chat_field: LineEdit = %ChatField
		if enabled:
			"""chat_layer.visible     = true
			chat_field.editable    = true
			chat_ctrl.chat_enabled = true"""
			chat_ctrl.enable_overlay()
		else:
			chat_ctrl.disable_overlay()
			"""chat_layer.visible  = false
			chat_field.editable = false
			chat_field.visible  = false
			# just to be ABSOLUTELY safe i guess
			chat_field.release_focus()
			chat_ctrl.chat_enabled = false
			chat_ctrl.clear_chat()"""
	else: Log.error("This command only runs on the client!")

func _add_limbo_commands() -> void:
	LimboConsole.register_command(do_open_save_menu, "save", "Open save screen")
	LimboConsole.register_command(do_open_load_menu, "load", "Open load screen")
	LimboConsole.register_command(do_open_debug_menu, "debug", "Open debug screen")
	LimboConsole.register_command(set_resolution_scale, "rescale", "Scales resolution to a given multiplier")
	LimboConsole.register_command(chat_command, "chat", "Enables/disables multiplayer chat. Only works on the client.")

func _ready() -> void:
	if OS.is_debug_build() or true:
		_add_limbo_commands()
