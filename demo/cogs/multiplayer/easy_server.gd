class_name EasyServer
extends Node

@export var port: int = 42424
@export var auto_start: bool = false

const PARAM_DELIM := "\uFFFF" # separates fields within one message
const MSG_DELIM := "\uFFFE" # separates multiple messages in one ws frame

var _tcp: TCPServer = null
var _running: bool = false
var _next_id: int = 1
var _peers: Dictionary = {}
var _greeted: Dictionary = {}

class PeerEntry:
	var id: int = 0
	var ws: WebSocketPeer = null
	var room_id: int = -1
	var x: int = 0
	var y: int = 0
	var facing: int = 2
	var speed: int = 4
	var sprite_name: String = ""
	var sprite_idx: int = 0
	var hidden: bool = false
	var transparency: int = 0
	var sys_name: String = ""
	var display_name: String = ""
	var chat_enabled: bool = false # p4o-a7o: off by default

func _ready() -> void:
	if auto_start:
		start()

func _process(_delta: float) -> void:
	if not _running:
		return
	while _tcp.is_connection_available():
		_accept_connection(_tcp.take_connection())
	
	var to_remove: Array = []
	for pid in _peers.keys():
		var entry: PeerEntry = _peers[pid]
		entry.ws.poll()
		match entry.ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if not _greeted.get(pid, false):
					_greeted[pid] = true
					_on_peer_open(pid, entry)
				while entry.ws.get_available_packet_count() > 0:
					_dispatch_frame(pid, entry, entry.ws.get_packet())
			WebSocketPeer.STATE_CLOSED:
				to_remove.append(pid)
			_:
				pass
	
	for pid in to_remove:
		_on_peer_closed(pid)

func start() -> bool:
	if _running:
		return true
	_tcp = TCPServer.new()
	var err := _tcp.listen(port)
	if err != OK:
		Log.error("[EasyServer] failed to listen on port %d: %s" % [port, error_string(err)])
		_tcp = null
		return false
	_running = true
	Log.info("[EasyServer] listening on ws://127.0.0.1:%d" % port)
	return true

func stop() -> void:
	if not _running:
		return
	_running = false
	for pid in _peers.keys():
		(_peers[pid] as PeerEntry).ws.close()
	_peers.clear()
	if _tcp:
		_tcp.stop()
		_tcp = null
	Log.info("[EasyServer] stopped")

func is_running() -> bool:
	return _running

func _accept_connection(stream: StreamPeerTCP) -> void:
	var ws := WebSocketPeer.new()
	ws.supported_protocols = PackedStringArray(["binary"])
	if ws.accept_stream(stream) != OK:
		return
	var pid := _next_id
	_next_id += 1
	var entry := PeerEntry.new()
	entry.id = pid
	entry.ws = ws
	_peers[pid] = entry
	Log.info("[EasyServer] new peer created %d" % pid)

func _on_peer_open(pid: int, _entry: PeerEntry) -> void:
	Log.debug("[EasyServer] peer %d open, sending s" % pid)
	# p4o-a7o: added PID to message for identifying self in chat messages
	_send_to(pid, _build("s", ["0", str(pid)]))

func _on_peer_closed(pid: int) -> void:
	if not _peers.has(pid):
		return
	var entry: PeerEntry = _peers[pid]
	Log.info("[EasyServer] peer %d closed (room %d)" % [pid, entry.room_id])
	_broadcast_to_room(entry.room_id, _build("d", [str(entry.id)]), pid)
	_peers.erase(pid)
	_greeted.erase(pid)

func _dispatch_frame(pid: int, entry: PeerEntry, raw: PackedByteArray) -> void:
	for msg in raw.get_string_from_utf8().split(MSG_DELIM, false):
		_dispatch_message(pid, entry, msg)

func _dispatch_message(pid: int, entry: PeerEntry, msg: String) -> void:
	var p := msg.find(PARAM_DELIM)
	var type: String
	var args: Array
	if p == -1:
		type = msg
		args = []
	else:
		type = msg.substr(0, p)
		args = Array(msg.substr(p + PARAM_DELIM.length()).split(PARAM_DELIM, false))
	Log.debug("[EasyServer] RX peer=%d '%s' args=%s" % [pid, type, str(args)])
	
	match type:
		"sr": _handle_sr(pid, entry, args)
		"m", "tp": _handle_move(pid, entry, args)
		"jmp": _handle_jump(pid, entry, args)
		"f": _handle_facing(pid, entry, args)
		"spd": _handle_speed(pid, entry, args)
		"spr": _handle_sprite(pid, entry, args)
		"tr": _handle_transparency(pid, entry, args)
		"h": _handle_hidden(pid, entry, args)
		"sys": _handle_sys(pid, entry, args)
		"name": _handle_name_pkt(pid, entry, args)
		"chat": _handle_chat(pid, entry, args)
		"chaton": _handle_chaton(pid, entry, args)
		"fl","rfl","rrfl","se","ba","ap","mp","rp","ss","sv","sev":
			_handle_relay(pid, entry, type, args)
		_:
			Log.warn("[EasyServer] unknown packet '%s' from peer %d" % [type, pid])

func _handle_sr(pid: int, entry: PeerEntry, args: Array) -> void:
	var new_room := int(args[0]) if args.size() > 0 else 0
	var old_room := entry.room_id
	if old_room >= 0:
		_broadcast_to_room(old_room, _build("d", [str(entry.id)]), pid)
	entry.room_id = new_room
	Log.info("[EasyServer] peer %d joined room %d" % [pid, new_room])
	_send_to(pid, _build("ri", [str(new_room)]))
	for other_pid in _peers.keys():
		if other_pid == pid:
			continue
		var other: PeerEntry = _peers[other_pid]
		if other.room_id != new_room:
			continue
		_send_peer_state_to(pid, other)
	
	# order is important
	_broadcast_to_room(new_room, _build("m", [str(entry.id), str(entry.x), str(entry.y)]), pid)
	_broadcast_to_room(new_room, _build("spr", [str(entry.id), entry.sprite_name, str(entry.sprite_idx)]), pid)
	_broadcast_to_room(new_room, _build("f", [str(entry.id), str(entry.facing)]), pid)
	_broadcast_to_room(new_room, _build("spd", [str(entry.id), str(entry.speed)]), pid)
	if entry.hidden:
		_broadcast_to_room(new_room, _build("h", [str(entry.id), "1"]), pid)
	if entry.transparency > 0:
		_broadcast_to_room(new_room, _build("tr", [str(entry.id), str(entry.transparency)]), pid)
	if entry.sys_name != "":
		_broadcast_to_room(new_room, _build("sys", [str(entry.id), entry.sys_name]), pid)
	if entry.display_name != "":
		_broadcast_to_room(new_room, _build("name", [str(entry.id), entry.display_name]), pid)

func _handle_move(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.size() < 2:
		return
	entry.x = int(args[0])
	entry.y = int(args[1])
	_broadcast_to_room(entry.room_id, _build("m", [str(entry.id)] + args), pid)

func _handle_jump(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.size() < 2:
		return
	entry.x = int(args[0])
	entry.y = int(args[1])
	_broadcast_to_room(entry.room_id, _build("jmp", [str(entry.id)] + args), pid)

func _handle_facing(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	entry.facing = int(args[0])
	_broadcast_to_room(entry.room_id, _build("f", [str(entry.id)] + args), pid)

func _handle_speed(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	entry.speed = int(args[0])
	_broadcast_to_room(entry.room_id, _build("spd", [str(entry.id)] + args), pid)

func _handle_sprite(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.size() < 2:
		return
	entry.sprite_name = args[0]
	entry.sprite_idx = int(args[1])
	_broadcast_to_room(entry.room_id, _build("spr", [str(entry.id)] + args), pid)

func _handle_transparency(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	entry.transparency = int(args[0])
	_broadcast_to_room(entry.room_id, _build("tr", [str(entry.id)] + args), pid)

func _handle_hidden(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	entry.hidden = int(args[0]) == 1
	_broadcast_to_room(entry.room_id, _build("h", [str(entry.id)] + args), pid)

func _handle_sys(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	entry.sys_name = args[0]
	_broadcast_to_room(entry.room_id, _build("sys", [str(entry.id)] + args), pid)

func _handle_name_pkt(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	entry.display_name = args[0]
	_broadcast_to_room(entry.room_id, _build("name", [str(entry.id)] + args), pid)

func _handle_chat(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.is_empty():
		return
	if not entry.chat_enabled:
		Log.warn("[EasyServer] Attempt to send chat message without chat enabled from PID %d" % pid)
		return
	# nameless players should probably not be able to talk...
	if entry.display_name == "" or entry.display_name.length() == 0:
		return
	var msg := args[0] as String
	if msg.length() > 100:
		return
	# basically _broadcast_to_room, but skips over
	# peers that have chat disabled, and also
	# broadcasts sender's message back to the sender
	for other_pid in _peers.keys():
		var cur_peer := _peers[other_pid] as PeerEntry
		if not cur_peer.chat_enabled:
			continue
		if cur_peer.room_id == entry.room_id:
			_send_to(other_pid, _build("chat", [str(pid), msg]))

func _handle_chaton(pid: int, entry: PeerEntry, args: Array) -> void:
	if args.size() < 1:
		return
	Log.debug("[EasyServer] chaton from PID %d: %s" % [pid, args[0]])
	entry.chat_enabled = args[0] == "1" # yeah

func _handle_relay(pid: int, entry: PeerEntry, pkt_name: String, args: Array) -> void:
	_broadcast_to_room(entry.room_id, _build(pkt_name, [str(entry.id)] + args), pid)

func _send_peer_state_to(target_pid: int, other: PeerEntry) -> void:
	_send_to(target_pid, _build("m", [str(other.id), str(other.x), str(other.y)]))
	_send_to(target_pid, _build("spr", [str(other.id), other.sprite_name, str(other.sprite_idx)]))
	_send_to(target_pid, _build("f", [str(other.id), str(other.facing)]))
	_send_to(target_pid, _build("spd", [str(other.id), str(other.speed)]))
	if other.hidden:
		_send_to(target_pid, _build("h", [str(other.id), "1"]))
	if other.transparency > 0:
		_send_to(target_pid, _build("tr", [str(other.id), str(other.transparency)]))
	if other.sys_name != "":
		_send_to(target_pid, _build("sys", [str(other.id), other.sys_name]))
	if other.display_name != "":
		_send_to(target_pid, _build("name", [str(other.id), other.display_name]))

func _build(type: String, args: Array = []) -> String:
	var s := type
	for a in args:
		s += PARAM_DELIM + str(a)
	return s

func _send_to(pid: int, msg: String) -> void:
	if not _peers.has(pid):
		return
	var entry: PeerEntry = _peers[pid]
	if entry.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	Log.debug("[EasyServer] TX -> peer=%d '%s'" % [pid, msg.substr(0, 60)])
	entry.ws.send(msg.to_utf8_buffer(), WebSocketPeer.WRITE_MODE_BINARY)

func _broadcast_to_room(room_id: int, msg: String, exclude_pid: int = -1) -> void:
	for pid in _peers.keys():
		if pid == exclude_pid:
			continue
		if (_peers[pid] as PeerEntry).room_id == room_id:
			_send_to(pid, msg)
