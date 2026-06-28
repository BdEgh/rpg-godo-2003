class_name EasyMultiplayer
extends Node

@export var server_url: String = "wss://127.0.0.1/"
@export var engine: NodePath
@export var chat_ctrl: Control

@export var player_name: String = ""

@export var enable_sounds: bool = true
@export var enable_chat: bool = false
@export var mute_audio: bool = false
@export var moving_queue_limit: int = 4

var _conn: EasyConnection = null
var _engine: Node = null

var _room_id: int = -1
var _my_pid: int = -1
var _session_active: bool = false
var _session_connected: bool = false
var _switching_room: bool = true
var _switched_room: bool = false
var _reconnecting: bool = false

var _players: Dictionary = {}
var _dc_players: Array = []
var _pending_spawn: Array = []

class OtherPlayer:
	var id: int = -1
	var display_name: String = ""
	var sprite_name: String = ""
	var sprite_index: int = 0
	var facing: int = 2 # DOWN (RPGMaker default)
	var speed: int = 4 # normal speed
	var transparency: int = 0
	var hidden: bool = false
	var system_name: String = ""
	var x: int = 0
	var y: int = 0

# every sound from this list has a reduced distance attenuation
const _INST_SET: Dictionary = {
	"kalimba_c3": true, "kalimba_c#3": true, "kalimba_d3": true,
	"kalimba_d#3": true, "kalimba_e3": true, "kalimba_f3": true,
	"kalimba_f#3": true, "kalimba_g3": true, "kalimba_g#3": true,
	"kalimba_a3": true, "kalimba_a#3": true, "kalimba_b3": true,
	"kalimba_c4": true, "kalimba_c#4": true, "kalimba_d4": true,
	"kalimba_d#4": true, "kalimba_e4": true, "kalimba_f4": true,
	"kalimba_f#4": true, "kalimba_g4": true, "kalimba_g#4": true,
	"kalimba_a4": true, "kalimba_a#4": true, "kalimba_b4": true,
	"kalimba_c5": true, "kalimba_c#5": true, "kalimba_d5": true,
	"kalimba_d#5": true, "kalimba_e5": true,
}

var _sync_switches: Array = []
var _sync_vars: Array = []
var _sync_events: Array = []
var _sync_action_events: Array = []
var _sync_picture_names: Array = []
var _global_sync_pic_names: Array = []
var _global_sync_pic_pfx: Array = []
var _sync_battle_anim_ids: Array = []
var _sync_picture_cache: Dictionary = {}

var _frame_index: int = 0
var _last_flash_frame_index: int = -1
var _last_frame_flash: Array = []
var _repeating_flashes: Dictionary = {}

# local player state (from RPGMakerPlayer signals)
var _local_x: int = 0
var _local_y: int = 0
var _local_speed: int = 4
var _local_sprite_name: String = ""
var _local_sprite_index: int = 0
var _local_facing: int = 2
var _local_hidden: bool = false
var _local_system_name: String = ""

func _ready() -> void:
	_conn = EasyConnection.new()
	_conn.connected.connect(_on_ws_connected)
	_conn.disconnected.connect(_on_ws_disconnected)
	_conn.packet_received.connect(_on_packet)
	
	if engine:
		_engine = get_node(engine)
		if _engine:
			_wire_player_signals()
			Log.info("[EasyMultiplayer] wired to RPGMakerPlayer '%s'" % _engine.name)
		else:
			Log.error("[EasyMultiplayer] engine NodePath did not resolve: " + str(engine))

func _process(_delta: float) -> void:
	if _conn:
		_conn.poll()
	if _session_active:
		_update_frame()
	if _session_connected:
		_conn.flush_queue()
	_retry_pending_spawns()

func connect_to_room(map_id: int, room_switch: bool = false) -> void:
	Log.info("[EasyMultiplayer] connect_to_room id=%d room_switch=%s" % [map_id, str(room_switch)])
	_room_id = map_id
	_session_active = true
	_switching_room = true
	if room_switch:
		_switched_room = false
	_initialize()
	_dc_players.clear()
	
	if _engine and _engine.is_running():
		_engine.mp_set_session_active(true)
		_engine.mp_set_room_id(map_id)
	
	if _conn.is_connected_to_server():
		Log.debug("[EasyMultiplayer] already connected — sending basic data + sr")
		_session_connected = true
		if _engine and _engine.is_running():
			_engine.mp_sync_local_player()
		_send_basic_data()
		_conn.send_packet("sr", [str(_room_id)])
	else:
		var url := _room_url(map_id)
		Log.info("[EasyMultiplayer] opening WebSocket: %s" % url)
		_conn.open(url)

func quit() -> void:
	Log.info("[EasyMultiplayer] quit")
	_session_active = false
	_reconnecting = false
	if _engine and _engine.is_running():
		_engine.mp_set_session_active(false)
	_conn.close()
	_initialize()

func set_enable_chat(on: bool) -> void:
	enable_chat = on
	if not _session_connected:
		return
	_conn.send_packet("chaton", ["1" if enable_chat else "0"])

func _wire_player_signals() -> void:
	_engine.player_moved.connect(_on_local_moved)
	_engine.player_facing_changed.connect(_on_local_facing)
	_engine.player_speed_changed.connect(_on_local_speed)
	_engine.player_sprite_changed.connect(_on_local_sprite)
	_engine.player_jumped.connect(_on_local_jumped)
	_engine.player_flashed.connect(_on_local_flashed)
	_engine.player_transparency_changed.connect(_on_local_transparency)
	_engine.player_hidden_changed.connect(_on_local_hidden)
	_engine.player_teleported.connect(_on_local_teleported)
	_engine.player_se_played.connect(_on_local_se)
	_engine.player_system_changed.connect(_on_local_system)
	_engine.map_changed.connect(_on_map_changed)
	_engine.switch_set.connect(_on_switch_set)
	_engine.variable_set.connect(_on_variable_set)
	_engine.event_triggered.connect(_on_event_triggered)

func _on_local_moved(x: int, y: int) -> void:
	_local_x = x
	_local_y = y
	if not _session_connected:
		return
	_conn.send_packet("m", [str(x), str(y)])

func _on_local_facing(dir: int) -> void:
	_local_facing = dir
	if not _session_connected:
		return
	_conn.send_packet("f", [str(dir)])

func _on_local_speed(spd: int) -> void:
	_local_speed = spd
	if not _session_connected:
		return
	_conn.send_packet("spd", [str(spd)])

func _on_local_sprite(spr_name: String, index: int) -> void:
	_local_sprite_name = spr_name
	_local_sprite_index = index
	if not _session_connected:
		return
	_conn.send_packet("spr", [_sanitize(spr_name), str(index)])

func _on_local_jumped(x: int, y: int) -> void:
	if not _session_connected:
		return
	_conn.send_packet("jmp", [str(x), str(y)])

func _on_local_flashed(r: int, g: int, b: int, power: int, frames: int) -> void:
	if not _session_connected:
		return
	var flash := [r, g, b, power, frames]
	var is_continuation := (
		_last_flash_frame_index > -1
		and _frame_index - _last_flash_frame_index <= 1
		and (_last_frame_flash.is_empty() or _last_frame_flash == flash)
	)
	if is_continuation:
		if _last_frame_flash.is_empty():
			_last_frame_flash = flash
			_conn.send_packet("rfl", [str(r), str(g), str(b), str(power), str(frames)])
	else:
		_conn.send_packet("fl", [str(r), str(g), str(b), str(power), str(frames)])
		_last_frame_flash = []
	_last_flash_frame_index = _frame_index

func _on_local_transparency(t: int) -> void:
	if not _session_connected:
		return
	_conn.send_packet("tr", [str(t)])

func _on_local_hidden(hidden: bool) -> void:
	_local_hidden = hidden
	if not _session_connected:
		return
	_conn.send_packet("h", [str(1 if hidden else 0)])

func _on_local_teleported(map_id: int, x: int, y: int) -> void:
	if not _session_connected:
		return
	Log.debug("[EasyMultiplayer] local teleported map=%d (%d,%d)" % [map_id, x, y])
	_conn.send_packet("tp", [str(x), str(y)])

func _on_local_se(snd_name: String, volume: int, tempo: int, balance: int) -> void:
	if not _session_connected:
		return
	_conn.send_packet("se", [_sanitize(snd_name), str(volume), str(tempo), str(balance)])

func _on_local_system(sys_name: String) -> void:
	_local_system_name = sys_name
	if not _session_connected:
		return
	_conn.send_packet("sys", [_sanitize(sys_name)])

func _on_map_changed(map_id: int) -> void:
	connect_to_room(map_id, true)

func _on_switch_set(switch_id: int, value: int) -> void:
	if switch_id in _sync_switches:
		_conn.send_packet("ss", [str(switch_id), str(value)])

func _on_variable_set(var_id: int, value: int) -> void:
	if var_id in _sync_vars:
		_conn.send_packet("sv", [str(var_id), str(value)])

func _on_event_triggered(event_id: int, action: bool) -> void:
	if action:
		if event_id in _sync_action_events:
			_conn.send_packet("sev", [str(event_id), "1"])
	else:
		if event_id in _sync_events:
			_conn.send_packet("sev", [str(event_id), "0"])

func _on_ws_connected() -> void:
	Log.info("[EasyMultiplayer] WebSocket connected")
	if _engine and _engine.is_running():
		_engine.mp_set_session_active(true)

func _on_ws_disconnected(code: int) -> void:
	Log.info("[EasyMultiplayer] WebSocket disconnected code=%d" % code)
	_session_connected = false
	if code == 1028:
		Log.warn("[EasyMultiplayer] server EXIT (1028) — stopping session")
		_session_active = false
		_reconnecting = false
		quit()
	elif _session_active:
		if _reconnecting:
			Log.debug("[EasyMultiplayer] reconnect already pending — skipping duplicate")
			return
		_reconnecting = true
		Log.info("[EasyMultiplayer] reconnecting to room %d in 5s…" % _room_id)
		await get_tree().create_timer(5.0).timeout
		_reconnecting = false
		if _session_active:
			connect_to_room(_room_id)
	else:
		quit()

func _on_packet(type: String, args: Array) -> void:
	match type:
		"s": _handle_sync_player_data(args)
		"ri": _handle_room_info(args)
		"d": _handle_disconnect(args)
		"m": _handle_move(args)
		"jmp": _handle_jump(args)
		"f": _handle_facing(args)
		"spd": _handle_speed(args)
		"spr": _handle_sprite(args)
		"fl": _handle_flash(args)
		"rfl": _handle_repeating_flash(args)
		"rrfl": _handle_remove_repeating_flash(args)
		"tr": _handle_transparency(args)
		"h": _handle_hidden(args)
		"sys": _handle_system(args)
		"se": _handle_se(args)
		"ss": _handle_sync_switch(args)
		"sv": _handle_sync_variable(args)
		"sev": _handle_sync_event(args)
		"sp": _handle_sync_picture(args)
		"pns": _handle_name_list_sync(args)
		"bas": _handle_battle_anim_id_list(args)
		"name": _handle_name(args)
		"chat": _handle_chat(args)
		_:
			Log.warn("[EasyMultiplayer] unknown packet '%s' args=%s" % [type, str(args)])

func _handle_sync_player_data(_args: Array) -> void:
	_session_connected = true
	Log.info("[EasyMultiplayer] session ready")
	_my_pid = int(_args[1])
	if _engine and _engine.is_running():
		_engine.mp_sync_local_player()
	_send_basic_data()
	_conn.send_packet("sr", [str(_room_id)])
	_conn.send_packet("chaton", ["1" if enable_chat else "0"])

func _handle_room_info(args: Array) -> void:
	if args.is_empty():
		return
	var room_id := int(args[0])
	if room_id != _room_id:
		Log.warn("[EasyMultiplayer] wrong room %d (expected %d) — reconnecting" % [room_id, _room_id])
		connect_to_room(_room_id)
		return
	_switching_room = false
	Log.info("[EasyMultiplayer] room %d confirmed" % room_id)
	if _engine and _engine.is_running():
		_engine.mp_notify_room_ready()

func _handle_disconnect(args: Array) -> void:
	if args.is_empty():
		return
	var id := int(args[0])
	Log.info("[EasyMultiplayer] player DISCONNECT id=%d" % id)
	if not _players.has(id):
		return
	_dc_players.append(_players[id])
	_players.erase(id)
	_repeating_flashes.erase(id)
	if _engine:
		_engine.mp_remove_player(id)

func _handle_move(args: Array) -> void:
	if args.size() < 3:
		return
	var id := int(args[0])
	var x := int(args[1])
	var y := int(args[2])
	if not _players.has(id):
		Log.debug("[EasyMultiplayer] late spawn for id=%d on first move" % id)
		_spawn_player(id)
	_players[id].x = x
	_players[id].y = y
	if _is_pending(id):
		return
	if _engine and _engine.is_running():
		_engine.mp_move_player(id, x, y)

func _handle_jump(args: Array) -> void:
	if args.size() < 3:
		return
	var id := int(args[0])
	if not _players.has(id):
		return
	if _engine:
		_engine.mp_move_player(id, int(args[1]), int(args[2]))

func _handle_facing(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var facing := clampi(int(args[1]), 0, 3)
	if not _players.has(id):
		return
	_players[id].facing = facing
	if _is_pending(id):
		return
	if _engine:
		_engine.mp_set_player_facing(id, facing)

func _handle_speed(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var speed := clampi(int(args[1]), 1, 6)
	if not _players.has(id):
		return
	_players[id].speed = speed
	if _is_pending(id):
		return
	if _engine:
		_engine.mp_set_player_speed(id, speed)

func _handle_sprite(args: Array) -> void:
	if args.size() < 3:
		return
	var id := int(args[0])
	var spr_name := args[1] as String
	var index := clampi(int(args[2]), 0, 7)
	if not _players.has(id):
		return
	_players[id].sprite_name = spr_name
	_players[id].sprite_index = index
	if _is_pending(id):
		return
	if _engine:
		_engine.mp_set_player_sprite(id, spr_name, index)

func _handle_flash(args: Array) -> void:
	if args.size() < 6:
		return
	var id := int(args[0])
	if not _players.has(id) or _is_pending(id):
		return
	if _engine:
		_engine.mp_flash_player(id,
			int(args[1]), int(args[2]), int(args[3]), int(args[4]), int(args[5]))

func _handle_repeating_flash(args: Array) -> void:
	if args.size() < 6:
		return
	var id := int(args[0])
	var flash := [int(args[1]), int(args[2]), int(args[3]), int(args[4]), int(args[5])]
	if not _players.has(id):
		return
	_repeating_flashes[id] = flash
	if _is_pending(id):
		return
	if _engine:
		_engine.mp_flash_player(id, flash[0], flash[1], flash[2], flash[3], flash[4])

func _handle_remove_repeating_flash(args: Array) -> void:
	if args.is_empty():
		return
	_repeating_flashes.erase(int(args[0]))

func _handle_transparency(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var t := clampi(int(args[1]), 0, 7)
	if not _players.has(id):
		return
	_players[id].transparency = t
	if _is_pending(id):
		return
	if _engine:
		_engine.mp_set_player_transparency(id, t)

func _handle_hidden(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var hidden := int(args[1]) == 1
	if not _players.has(id):
		return
	_players[id].hidden = hidden
	if _is_pending(id):
		return
	if _engine:
		_engine.mp_set_player_hidden(id, hidden)

func _handle_system(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var sys_name := args[1] as String
	if _players.has(id):
		_players[id].system_name = sys_name
	if _engine and _engine.is_running() and _engine.is_map_ready():
		_engine.mp_set_player_system_graphic(id, sys_name)

func _handle_se(args: Array) -> void:
	if args.size() < 5:
		return
	if not enable_sounds or mute_audio:
		return
	if _engine == null or not _engine.is_running():
		return
	
	var id := int(args[0])
	var snd_name := args[1] as String
	var snd_volume := int(args[2])
	var snd_tempo := int(args[3])
	var snd_balance := int(args[4])
	
	if not _players.has(id):
		return
	var p: OtherPlayer = _players[id]
	
	var px := _local_x
	var py := _local_y
	var ox := p.x
	var oy := p.y
	var rx := px - ox
	var ry := py - oy
	var dist := sqrt(float(rx * rx + ry * ry))
	if _INST_SET.has(snd_name):
		dist = maxf(0.0, dist - 7.0)
	
	var dist_volume := 75.0 - dist * 10.0
	var real_volume := maxi(int(dist_volume * float(snd_volume) / 100.0), 0)
	if real_volume <= 0:
		return
	
	_engine.mp_play_se(snd_name, real_volume, snd_tempo, snd_balance)

func _handle_sync_switch(args: Array) -> void:
	if args.size() < 2:
		return
	var sw_id := int(args[0])
	var sync_type := int(args[1])
	if sync_type >= 1 and sw_id not in _sync_switches:
		_sync_switches.append(sw_id)

func _handle_sync_variable(args: Array) -> void:
	if args.size() < 2:
		return
	var var_id := int(args[0])
	var sync_type := int(args[1])
	if sync_type >= 1 and var_id not in _sync_vars:
		_sync_vars.append(var_id)

func _handle_sync_event(args: Array) -> void:
	if args.size() < 2:
		return
	var ev_id := int(args[0])
	var trig_type := int(args[1])
	if trig_type != 1 and ev_id not in _sync_events:
		_sync_events.append(ev_id)
	if trig_type >= 1 and ev_id not in _sync_action_events:
		_sync_action_events.append(ev_id)

func _handle_sync_picture(args: Array) -> void:
	if args.is_empty():
		return
	var pic_name := args[0] as String
	if pic_name not in _sync_picture_names:
		_sync_picture_names.append(pic_name)

func _handle_name_list_sync(args: Array) -> void:
	if args.is_empty():
		return
	match int(args[0]):
		0: _global_sync_pic_names = args.slice(1)
		1: _global_sync_pic_pfx = args.slice(1)

func _handle_battle_anim_id_list(args: Array) -> void:
	_sync_battle_anim_ids = args.map(func(s): return int(s))

func _handle_name(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var n := args[1] as String
	if _players.has(id):
		_players[id].display_name = n
		Log.debug("[EasyMultiplayer] player %d name='%s'" % [id, n])
	if _engine and _engine.is_running() and _engine.is_map_ready():
		_engine.mp_set_player_name(id, n)

func _handle_chat(args: Array) -> void:
	if args.size() < 2:
		return
	var id := int(args[0])
	var msg := args[1] as String
	if msg.length() > 100:
		Log.warn("[EasyMultiplayer] Attempt to send message over 100 characters from PID %d" % id)
		return
	var display_name := player_name
	if not _players.has(id):
		if id != _my_pid:
			Log.warn("[EasyMultiplayer] got chat message from unknown PID: %d" % id)
			return
	else:
		display_name = _players[id].display_name
	MpEvents.on_chat_message.emit(display_name, msg)

func _send_basic_data() -> void:
	if not _session_connected:
		return
	Log.debug("[EasyMultiplayer] sending basic data pos=(%d,%d) spr='%s'[%d]" \
		% [_local_x, _local_y, _local_sprite_name, _local_sprite_index])
	_conn.send_packet("m", [str(_local_x), str(_local_y)])
	_conn.send_packet("spd", [str(_local_speed)])
	_conn.send_packet("spr", [_sanitize(_local_sprite_name), str(_local_sprite_index)])
	_conn.send_packet("f", [str(_local_facing)])
	_conn.send_packet("h", [str(1 if _local_hidden else 0)])
	if _local_system_name != "":
		_conn.send_packet("sys", [_sanitize(_local_system_name)])
	if player_name != "":
		_conn.send_packet("name", [_sanitize(player_name)])

func _update_frame() -> void:
	if (_last_flash_frame_index > -1
			and not _last_frame_flash.is_empty()
			and _frame_index > _last_flash_frame_index):
		_conn.send_packet("rrfl", [])
		_last_flash_frame_index = -1
		_last_frame_flash = []
	
	_frame_index += 1
	
	for id in _repeating_flashes:
		if _players.has(id) and _engine:
			var f: Array = _repeating_flashes[id]
			_engine.mp_flash_player(id, f[0], f[1], f[2], f[3], f[4])
	
	if not _switching_room and not _switched_room:
		_switched_room = true

func _is_pending(id: int) -> bool:
	return id in _pending_spawn

func _room_url(room_id: int) -> String:
	var url := server_url.rstrip("/") + "/room?id=" + str(room_id)
	return url

func _initialize() -> void:
	_session_connected = false
	if _conn:
		_conn.clear_queue()
	if _engine and _engine.is_running():
		for id in _players.keys():
			_engine.mp_remove_player(id)
	_players.clear()
	_dc_players.clear()
	_pending_spawn.clear()
	_sync_switches.clear()
	_sync_vars.clear()
	_sync_events.clear()
	_sync_action_events.clear()
	_sync_picture_names.clear()
	_sync_picture_cache.clear()
	_repeating_flashes.clear()
	_frame_index = 0
	_last_flash_frame_index = -1
	_last_frame_flash = []

func _spawn_player(id: int) -> void:
	Log.debug("[EasyMultiplayer] queuing spawn for id=%d" % id)
	var p := OtherPlayer.new()
	p.id = id
	_players[id] = p
	if id not in _pending_spawn:
		_pending_spawn.append(id)

func _do_mp_add_player(id: int) -> bool:
	if not _players.has(id):
		return true
	if _engine == null or not _engine.is_running():
		return false
	if not _engine.is_map_ready():
		return false
	var p: OtherPlayer = _players[id]
	Log.info("[EasyMultiplayer] spawning id=%d pos=(%d,%d) spr='%s'[%d]" \
		% [id, p.x, p.y, p.sprite_name, p.sprite_index])
	_engine.mp_add_player(id, p.x, p.y, p.sprite_name, p.sprite_index, p.facing, p.speed)
	if p.transparency > 0:
		_engine.mp_set_player_transparency(id, p.transparency)
	if p.hidden:
		_engine.mp_set_player_hidden(id, true)
	if p.display_name != "":
		_engine.mp_set_player_name(id, p.display_name)
	if p.system_name != "":
		_engine.mp_set_player_system_graphic(id, p.system_name)
	return true

func _retry_pending_spawns() -> void:
	if _pending_spawn.is_empty() or _engine == null or not _engine.is_running():
		return
	var ids := _pending_spawn.duplicate()
	_pending_spawn.clear()
	for id in ids:
		if _players.has(id):
			if not _do_mp_add_player(id):
				if id not in _pending_spawn:
					_pending_spawn.append(id)

func _sanitize(s: String) -> String:
	return s.replace(EasyConnection.PARAM_DELIM, "").replace(EasyConnection.MSG_DELIM, "")
