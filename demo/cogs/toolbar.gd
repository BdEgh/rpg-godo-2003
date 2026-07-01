extends Control

@onready var container := %PanelContainer
@onready var dimmer := %ToolbarDimmer

var tex_reconnect_off := preload("res://resources/reconnect-off.png")
var tex_reconnect_on := preload("res://resources/reconnect.png")
var tex_chat_off := preload("res://resources/chat-off.png")
var tex_chat_on := preload("res://resources/chat-on.png")

func _ready() -> void:
	container.set_position(Vector2(0, -container.size.y))
	%ReconnectButton.icon = tex_reconnect_off
	%ChatToggle.icon = tex_chat_off
	%ChatToggle.button_pressed = false
	
	dimmer.set_position(Vector2(0, -container.size.y))
	
	MpEvents.on_connected.connect(_multiplayer_connected)
	MpEvents.on_disconnected.connect(_multiplayer_disconnected)

var active_tween: Tween
func stop_tween():
	if not active_tween:
		return
	active_tween.kill()

func reveal_toolbar():
	_toolbar_on()
	var tween := container.create_tween()
	tween.parallel().tween_property(container, "position", Vector2(0, 0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	# borders_texture has a margin so im just
	# gonna do it like this for now i suppose so
	# the dimmer is in the same position as the
	# container while also taking up the exact amount
	# of area of the container that i want
	tween.parallel().tween_property(dimmer, "position", Vector2(0, 0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	stop_tween()
	active_tween = tween
func hide_toolbar():
	var tween := container.create_tween()
	tween.parallel().tween_property(container, "position", Vector2(0, -container.size.y), 0.4) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(dimmer, "position", Vector2(0, -container.size.y), 0.4) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN)
	tween.tween_callback(_toolbar_off)
	stop_tween()
	active_tween = tween

# p4o-a7o: This makes it so you can't navigate the toolbar
# with the keyboard while it's hidden, which would lead to confusion at best.
# For whatever reason this doesn't work for the setup screen as you can
# still keyboard-navigate the setup screen while in-game.
func _toolbar_off():
	container.visible = false

func _toolbar_on():
	container.visible = true

func _fullscreen(on: bool):
	if on:
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		get_window().mode = Window.MODE_WINDOWED

func _on_mouse_entered() -> void:
	reveal_toolbar()

func _on_mouse_exited() -> void:
	hide_toolbar()

func _multiplayer_connected():
	%ReconnectButton.icon = tex_reconnect_on
	%ReconnectButton.modulate = Color(0.5, 1.0, 0.5)
	
func _multiplayer_disconnected():
	%ReconnectButton.icon = tex_reconnect_off
	%ReconnectButton.modulate = Color(1.0, 0.33, 0.33)

func _on_chat_toggle_toggled(toggled_on: bool) -> void:
	%ChatToggle.icon = tex_chat_on if toggled_on else tex_chat_off
	var engine := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if not engine or not engine.is_running():
		Log.warn("Toolbar: Chat button pressed but no game is running!")
		return
	
	var mp_node := engine.get_node_or_null("./MpNode") as EasyMultiplayer
	if not mp_node:
		return
	
	mp_node.set_enable_chat(toggled_on)
	if toggled_on:
		%ChatControl.enable_overlay()
	else:
		%ChatControl.disable_overlay()

func _on_reconnect_button_pressed() -> void:
	var engine := get_node_or_null("%RPGMakerPlayer") as RPGMakerPlayer
	if not engine or not engine.is_running():
		Log.warn("Toolbar: Reconnect requested but no game is running!")
		return
	
	var mp_node := engine.get_node_or_null("./MpNode") as EasyMultiplayer
	if not mp_node:
		return
	Log.debug("Toolbar: Reconnect requested")
	%ReconnectButton.icon = tex_reconnect_off
	%ReconnectButton.modulate = Color(1.0, 0.7, 0.33)
	mp_node.quit()
	await get_tree().create_timer(0.5).timeout
	mp_node.connect_to_room(mp_node._room_id)

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	_fullscreen(toggled_on)
