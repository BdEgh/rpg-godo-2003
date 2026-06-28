extends Control

# p4o-a7o: NOTE: the placeholder text for ChatField is "Press [T] to type...", but
# i would have preferred if it was formatted/localized, but i don't really
# know how to do that since ive never worked with Godot, and it's probably
# not a huge deal for anyone anyway so that will suffice for now, but
# i thought i would add a note here anyways since i do not intend it to be hard-coded

@export var mp_connection: EasyMultiplayer = null
# TODO: menu option for this thing or a debug command
@export var chat_history_limit: int = 10:
	set(value):
		chat_history_limit = value
		_delete_old_messages()
@export var chat_fade_rate: float = 0.75
@export var chat_enabled = false

@onready var chat_text_field: LineEdit = %ChatField
@onready var chat_vbox: VBoxContainer = %MessageContainer

const _CHAT_MESSAGE_SCN := preload("res://scenes/chat_message.tscn")

var _chat_open = false
# p4o-a7o: yes im aware that Tweens exist but i did not want to pause
# the tweens when the chat was open, so i did it in this very goofy way
class FadeTween:
	var countdown: float = 5
	var t: float = 1
var _fade_tweens: Array[FadeTween] = []

func _ready() -> void:
	chat_text_field.text_submitted.connect(_on_text_submitted)
	MpEvents.on_chat_message.connect(add_chat_message)
	pass

func _input(event: InputEvent) -> void:
	if not chat_enabled:
		return
	if event.is_action_released("game_chat_release") and _chat_open:
		chat_text_field.set_visible(false)
		chat_text_field.release_focus()
		_chat_open = false
		return
	# im doing this on released to avoid having a "t" appear in the chat box every single time
	if event.is_action_released("game_chat_focus"):
		chat_text_field.set_visible(true)
		chat_text_field.grab_focus()
		_chat_open = true
		return

func _process(delta: float) -> void:
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

func _on_text_submitted(text_field) -> void:
	mp_connection._conn.send_packet("chat", [chat_text_field.text])
	chat_text_field.clear()
	chat_text_field.set_visible(false)
	chat_text_field.release_focus()
	_chat_open = false

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
