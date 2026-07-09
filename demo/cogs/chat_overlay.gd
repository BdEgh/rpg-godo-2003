extends Control

# bde: i'll strip placeholder text for now o.o

@export var mp_connection: EasyMultiplayer = null
# TODO: menu option for this thing or a debug command
@export var chat_history_limit: int = 30:
	set(value):
		chat_history_limit = value
		_delete_old_messages()
@export var chat_fade_rate: float = 0.75
@export var chat_enabled = true

@onready var chat_text_field: LineEdit = %ChatField
@onready var chat_vbox: VBoxContainer = %MessageContainer
@onready var chat_overlay_layer: CanvasLayer = %ChatOverlayLayer

const _CHAT_MESSAGE_SCN := preload("res://scenes/chat_message.tscn")

var _chat_open = false
# p4o-a7o: yes im aware that Tweens exist but i did not want to pause
# the tweens when the chat was open, so i did it in this very goofy way
# bde: if it works, it works :3
class FadeTween:
	var countdown: float = 5
	var t: float = 1
var _fade_tweens: Array[FadeTween] = []

func _ready() -> void:
	MpEvents.on_chat_message.connect(add_chat_message)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_chat_toggle"):
		chat_enabled = not chat_enabled
		chat_overlay_layer.visible = not chat_overlay_layer.visible
	
	if not chat_enabled:
		return
	if event.is_action_pressed("game_chat_focus"):
		chat_text_field.set_visible(true)
		chat_text_field.grab_focus()
		_chat_open = true
		return

func _physics_process(delta: float) -> void:
	if not chat_enabled:
		return
	var msgs := chat_vbox.get_children()
	for i in msgs.size():
		# step tweens
		var tween = _fade_tweens[i]
		if tween.countdown > 0:
			tween.countdown -= delta
		else:
			tween.t = maxf(0, tween.t - (chat_fade_rate * delta))
		# modulate transparency now if the chat is not open
		var transp: float = tween.t
		if _chat_open:
			transp = 1
		var chat_msg_node := msgs[i]
		var contents := chat_msg_node
		contents.modulate.a = transp

func _delete_old_messages() -> void:
	while chat_vbox.get_child_count() > chat_history_limit:
		var to_delete := chat_vbox.get_child(0)
		chat_vbox.remove_child(to_delete)
		_fade_tweens.pop_front()
		to_delete.queue_free()

func add_chat_message(display_name: String, text: String) -> void:
	var msg_contents := "[%s]: %s" % [display_name, text]
	var chat_msg := _CHAT_MESSAGE_SCN.instantiate()
	chat_msg.text = msg_contents
	#chat_msg.get_node("Contents").text = msg_contents
	# it would probably be better if it was reverse order
	chat_vbox.add_child(chat_msg)
	_delete_old_messages()
	_fade_tweens.append(FadeTween.new())

func clear_chat():
	for item in chat_vbox.get_children():
		chat_vbox.remove_child(item)
		item.queue_free()
	_fade_tweens.clear()

func _on_chat_field_text_submitted(new_text: String) -> void:
	mp_connection._conn.send_packet("chat", [new_text])
	chat_text_field.clear()
	chat_text_field.set_visible(false)
	chat_text_field.release_focus()
	_chat_open = false

func _on_chat_field_editing_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		chat_text_field.set_visible(false)
		_chat_open = false
