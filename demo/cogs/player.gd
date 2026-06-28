extends RPGMakerPlayer

@export var texture_rect: TextureRect
@export var game_sub_viewport: SubViewport
@export var chat_text_field: LineEdit

## Note that _process and _ready functions
## were defined inside gdextension and will
## not work here

func _input(event: InputEvent) -> void:
	# p4o-a7o: TODO: release all keys held when pressing T
	# (because of the chat overlay)
	if chat_text_field.has_focus():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var easyrpg_key := _godot_key_to_easyrpg(key_event.keycode)
		if easyrpg_key >= 0:
			inject_key(easyrpg_key, key_event.pressed)

# gotta add proper control remap menu later
func _godot_key_to_easyrpg(keycode: Key) -> int:
	match keycode:
		KEY_UP:     return 13
		KEY_DOWN:   return 15
		KEY_LEFT:   return 12
		KEY_RIGHT:  return 14
		KEY_W:      return 13
		KEY_S:      return 15
		KEY_A:      return 12
		KEY_D:      return 14
		KEY_Z:      return 63
		KEY_X:      return 61
		KEY_ENTER:  return 4
		KEY_SPACE:  return 7
		KEY_ESCAPE: return 6
		KEY_SHIFT:  return 20
		KEY_F1:     return 85
		KEY_F2:     return 86
		KEY_F3:     return 87
		KEY_F4:     return 88
		KEY_F5:     return 89
		KEY_F6:     return 90
		KEY_F7:     return 91
		KEY_F8:     return 92
		KEY_F9:     return 93
		KEY_F10:     return 94
		KEY_F11:     return 95
		KEY_F12:     return 96
		KEY_1:      return 68
		KEY_2:      return 69
		KEY_3:      return 70
		KEY_4:      return 71
		KEY_5:      return 72
		KEY_6:      return 73
		KEY_7:      return 74
		KEY_8:      return 75
		KEY_9:      return 76
		KEY_0:      return 67
		KEY_MINUS:  return 102
		KEY_EQUAL:  return 103
		_:          return -1

func _on_resolution_changed(width: int, height: int) -> void:
	game_sub_viewport.size = Vector2i(width, height)
	texture_rect.texture = self.get_frame_texture()
