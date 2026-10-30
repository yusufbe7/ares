extends Node
## Networking. The server owns the world; clients send commands and receive
## state. Single player runs the exact same code path with OFFLINE authority,
## so no system needs to care whether a game is online.

enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED }

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 16

var state: int = State.OFFLINE
var players: Dictionary = {}       # peer id -> {peer, name, nation, role, ready, online}
var world_sync_interval := 2.0
var _sync_accum := 0.0
var _day_accum := 0.0
var day_seconds := 6.0             # real seconds per world day while the clock runs
var clock_running := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_authority() -> bool:
	return state == State.OFFLINE or state == State.HOSTING

func my_peer_id() -> int:
	if state == State.OFFLINE:
		return 1
	return multiplayer.get_unique_id()

# ---------------------------------------------------------------------------
# Session setup
# ---------------------------------------------------------------------------

func start_offline() -> void:
	_reset_peer()
	state = State.OFFLINE
	players = {1: _make_player(1, Settings.player_name)}
	GameState.local_player_id = 1
	EventBus.net_state_changed.emit(state)
	EventBus.lobby_updated.emit(player_list())

func host(port: int = DEFAULT_PORT) -> String:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "Server ochilmadi (xato %d). Port band bo'lishi mumkin." % err
	multiplayer.multiplayer_peer = peer
	state = State.HOSTING
	players = {1: _make_player(1, Settings.player_name)}
	GameState.local_player_id = 1
	EventBus.net_state_changed.emit(state)
	EventBus.lobby_updated.emit(player_list())
	return ""

func join(address: String, port: int = DEFAULT_PORT) -> String:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "Ulanib bo'lmadi (xato %d)." % err
	multiplayer.multiplayer_peer = peer
	state = State.CONNECTING
	EventBus.net_state_changed.emit(state)
	return ""

func leave() -> void:
	_reset_peer()
	state = State.OFFLINE
	players.clear()
	clock_running = false
	EventBus.net_state_changed.emit(state)

func _reset_peer() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _make_player(peer: int, pname: String) -> Dictionary:
	return {"peer": peer, "name": pname, "nation": "", "role": GameState.Role.COMMANDER,
		"ready": false, "online": true}

func player_list() -> Array:
	var out: Array = []
	for k in players.keys():
		out.append(players[k])
	return out

# --- peer callbacks ---------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_authority():
		return
	players[id] = _make_player(id, "Player %d" % id)
	_push_lobby()

func _on_peer_disconnected(id: int) -> void:
	if not is_authority():
		return
	if players.has(id):
		var nid := str(players[id].get("nation", ""))
		players[id]["online"] = false
		_mark_nation_player(nid, id, false)
		players.erase(id)
	_push_lobby()

func _on_connected_ok() -> void:
	state = State.CONNECTED
	GameState.local_player_id = multiplayer.get_unique_id()
	EventBus.net_state_changed.emit(state)
	rpc_id(1, "srv_register", Settings.player_name)

func _on_connected_fail() -> void:
	state = State.OFFLINE
	EventBus.net_state_changed.emit(state)
	GameState.notify("Serverga ulanib bo'lmadi.", "bad")

func _on_server_disconnected() -> void:
	state = State.OFFLINE
	players.clear()
	EventBus.net_state_changed.emit(state)
	GameState.notify("Server bilan aloqa uzildi.", "bad")

# ---------------------------------------------------------------------------
# Lobby
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func srv_register(pname: String) -> void:
	if not is_authority():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = _make_player(id, pname)
	_push_lobby()
	if GameState.world != null:
		rpc_id(id, "cl_world", GameState.world.to_dict())

@rpc("any_peer", "call_remote", "reliable")
func srv_pick_nation(nation_id: String, role: int) -> void:
	if not is_authority():
		return
	_assign(multiplayer.get_remote_sender_id(), nation_id, role)

func pick_nation(nation_id: String, role: int = GameState.Role.COMMANDER) -> void:
	if is_authority():
		_assign(my_peer_id(), nation_id, role)
	else:
		rpc_id(1, "srv_pick_nation", nation_id, role)

func _assign(peer: int, nation_id: String, role: int) -> void:
	if not players.has(peer):
		players[peer] = _make_player(peer, "Player %d" % peer)
	var old := str(players[peer].get("nation", ""))
	if old != "" and old != nation_id:
		_mark_nation_player(old, peer, false)
	players[peer]["nation"] = nation_id
	players[peer]["role"] = role
	if GameState.world != null:
		var n = GameState.world.nation(nation_id)
		if n != null:
			var found := false
			for p in n.players:
				if int(p.get("peer", -1)) == peer:
					p["role"] = role
					p["online"] = true
					p["name"] = str(players[peer].get("name", "?"))
					found = true
			if not found:
				# The first human in a nation leads it; the rest fall in behind.
				var lead_role: int = role
				if n.human_players().is_empty():
					lead_role = GameState.Role.HEAD_OF_STATE
				n.players.append({"peer": peer, "name": str(players[peer].get("name", "?")),
					"role": lead_role, "online": true, "ai": false})
				players[peer]["role"] = lead_role
			n.is_ai = false
	if peer == my_peer_id():
		GameState.local_nation = nation_id
		GameState.local_role = int(players[peer]["role"])
	_push_lobby()

func _mark_nation_player(nation_id: String, peer: int, online: bool) -> void:
	if GameState.world == null or nation_id == "":
		return
	var n = GameState.world.nation(nation_id)
	if n == null:
		return
	for p in n.players:
		if int(p.get("peer", -1)) == peer:
			p["online"] = online
	if n.online_players().is_empty():
		n.is_ai = true      # hand the nation back to the AI while nobody is on

func set_ready(value: bool) -> void:
	if is_authority():
		if players.has(my_peer_id()):
			players[my_peer_id()]["ready"] = value
		_push_lobby()
	else:
		rpc_id(1, "srv_set_ready", value)

@rpc("any_peer", "call_remote", "reliable")
func srv_set_ready(value: bool) -> void:
	if not is_authority():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["ready"] = value
	_push_lobby()

func _push_lobby() -> void:
	EventBus.lobby_updated.emit(player_list())
	if state == State.HOSTING:
		rpc("cl_lobby", player_list())

@rpc("authority", "call_remote", "reliable")
func cl_lobby(list: Array) -> void:
	players.clear()
	for p in list:
		players[int(p["peer"])] = p
	var me := my_peer_id()
	if players.has(me):
		GameState.local_nation = str(players[me].get("nation", ""))
		GameState.local_role = int(players[me].get("role", GameState.Role.COMMANDER))
	EventBus.lobby_updated.emit(list)

# ---------------------------------------------------------------------------
# World sync
# ---------------------------------------------------------------------------

func broadcast_world() -> void:
	if state == State.HOSTING and GameState.world != null:
		rpc("cl_world", GameState.world.to_dict())

@rpc("authority", "call_remote", "reliable")
func cl_world(data: Dictionary) -> void:
	var st := WorldState.new()
	st.from_dict(data)
	GameState.set_world(st)

func _process(delta: float) -> void:
	if not is_authority() or GameState.world == null or not clock_running:
		return
	_day_accum += delta
	if _day_accum >= day_seconds:
		_day_accum = 0.0
		GameState.world.tick_day()
		BattleBridge.resolve_unattended(GameState.world)
	if state == State.HOSTING:
		_sync_accum += delta
		if _sync_accum >= world_sync_interval:
			_sync_accum = 0.0
			broadcast_world()

# ---------------------------------------------------------------------------
# World commands (client -> server -> world)
# ---------------------------------------------------------------------------

## The one door every player action goes through. Offline it runs straight
## away; online it is sent to the server, validated there and applied once.
func command(action: String, args: Dictionary) -> void:
	if is_authority():
		_apply_command(my_peer_id(), action, args)
	else:
		rpc_id(1, "srv_command", action, args)

@rpc("any_peer", "call_remote", "reliable")
func srv_command(action: String, args: Dictionary) -> void:
	if not is_authority():
		return
	_apply_command(multiplayer.get_remote_sender_id(), action, args)

func _apply_command(peer: int, action: String, args: Dictionary) -> void:
	var world = GameState.world
	if world == null:
		return
	var nid := str(players.get(peer, {}).get("nation", ""))
	if nid == "":
		return
	var err := ""
	match action:
		"build":
			var b: Dictionary = DB.building(str(args.get("building", "")))
			var res := WarCouncil.request_spend(world, nid, peer, "build", args, b.get("cost", {}))
			err = str(res.get("error", ""))
			if not res.get("vote", {}).is_empty():
				_reply(peer, "Kengash ovoz berishi ochildi.", "info")
		"recruit":
			var u: Dictionary = DB.unit(str(args.get("unit", "")))
			var cost: Dictionary = {}
			for k in u.get("cost", {}).keys():
				cost[str(k)] = float(u["cost"][k]) * float(args.get("count", 1))
			var res2 := WarCouncil.request_spend(world, nid, peer, "recruit", args, cost)
			err = str(res2.get("error", ""))
			if not res2.get("vote", {}).is_empty():
				_reply(peer, "Kengash ovoz berishi ochildi.", "info")
		"move_army":
			err = _move_army(world, nid, peer, int(args.get("army", -1)), int(args.get("target", -1)))
		"propose_war":
			var v := WarCouncil.open_vote(world, nid, "declare_war",
				{"target": str(args.get("target", "")), "reason": str(args.get("reason", ""))}, peer)
			err = str(v.get("error", ""))
		"propose_peace":
			var v2 := WarCouncil.open_vote(world, nid, "peace",
				{"target": str(args.get("target", "")), "terms": args.get("terms", {})}, peer)
			err = str(v2.get("error", ""))
		"propose_alliance":
			var kind := "join_alliance" if str(args.get("alliance", "")) != "" else "create_alliance"
			var v3 := WarCouncil.open_vote(world, nid, kind, args, peer)
			err = str(v3.get("error", ""))
		"leave_alliance":
			var v4 := WarCouncil.open_vote(world, nid, "leave_alliance", {}, peer)
			err = str(v4.get("error", ""))
		"cast_vote":
			err = WarCouncil.cast_vote(world, str(args.get("vote", "")), peer, bool(args.get("approve", false)))
		"start_clock":
			clock_running = bool(args.get("running", true))
		"request_battle":
			_start_battle(world, int(args.get("battle_id", -1)))
	if err != "":
		_reply(peer, err, "bad")
	if state == State.HOSTING:
		broadcast_world()

func _move_army(world, nid: String, peer: int, army_id: int, target: int) -> String:
	var n = world.nation(nid)
	if n == null:
		return "Davlat topilmadi."
	if n.player_role(peer) < GameState.Role.OFFICER:
		return "Sizda armiyani boshqarish huquqi yo'q."
	var a = n.army_by_id(army_id)
	if a == null:
		return "Armiya topilmadi."
	var path: Array = NationAI.path_between(world, a.province, target, nid, false)
	if path.is_empty():
		return "Bu hududga yo'l yo'q."
	a.move_path = path
	a.move_progress = 0.0
	return ""

func _start_battle(world, battle_id: int) -> void:
	for b in world.pending_battles:
		if int(b.get("id", -1)) == battle_id:
			var cfg := BattleBridge.build_config(world, b)
			b["state"] = "playing"
			if state == State.HOSTING:
				rpc("cl_battle_start", cfg)
			EventBus.battle_requested.emit(cfg)
			return

@rpc("authority", "call_remote", "reliable")
func cl_battle_start(cfg: Dictionary) -> void:
	EventBus.battle_requested.emit(cfg)

func _reply(peer: int, text: String, kind: String) -> void:
	if peer == my_peer_id():
		GameState.notify(text, kind)
	elif state == State.HOSTING:
		rpc_id(peer, "cl_notice", text, kind)

@rpc("authority", "call_remote", "reliable")
func cl_notice(text: String, kind: String) -> void:
	GameState.notify(text, kind)

# ---------------------------------------------------------------------------
# Battle traffic
# ---------------------------------------------------------------------------

## Clients send orders; the server simulates and sends back snapshots. Keeping
## the simulation on one machine is what stops two players from seeing two
## different battles.
func send_battle_order(order: Dictionary) -> void:
	if is_authority():
		_deliver_order(my_peer_id(), order)
	else:
		rpc_id(1, "srv_battle_order", order)

@rpc("any_peer", "call_remote", "reliable")
func srv_battle_order(order: Dictionary) -> void:
	if not is_authority():
		return
	_deliver_order(multiplayer.get_remote_sender_id(), order)

signal battle_order_received(peer: int, order: Dictionary)
signal battle_snapshot_received(snapshot: Dictionary)

func _deliver_order(peer: int, order: Dictionary) -> void:
	battle_order_received.emit(peer, order)

func send_battle_snapshot(snapshot: Dictionary) -> void:
	if state == State.HOSTING:
		rpc("cl_battle_snapshot", snapshot)

@rpc("authority", "call_remote", "unreliable_ordered")
func cl_battle_snapshot(snapshot: Dictionary) -> void:
	battle_snapshot_received.emit(snapshot)

func send_battle_result(result: Dictionary) -> void:
	if is_authority():
		BattleBridge.apply_result(GameState.world, result)
		if state == State.HOSTING:
			rpc("cl_battle_result", result)
			broadcast_world()
	else:
		rpc_id(1, "srv_battle_result", result)

@rpc("any_peer", "call_remote", "reliable")
func srv_battle_result(result: Dictionary) -> void:
	if not is_authority():
		return
	BattleBridge.apply_result(GameState.world, result)
	rpc("cl_battle_result", result)
	broadcast_world()

@rpc("authority", "call_remote", "reliable")
func cl_battle_result(result: Dictionary) -> void:
	GameState.last_battle_result = result
	EventBus.battle_ended.emit(result)

# --- chat -------------------------------------------------------------------

func say(text: String, channel: String = "global") -> void:
	var who := Settings.player_name
	if is_authority():
		EventBus.chat_received.emit(who, text, channel)
		if state == State.HOSTING:
			rpc("cl_chat", who, text, channel)
	else:
		rpc_id(1, "srv_chat", text, channel)

@rpc("any_peer", "call_remote", "reliable")
func srv_chat(text: String, channel: String) -> void:
	if not is_authority():
		return
	var id := multiplayer.get_remote_sender_id()
	var who := str(players.get(id, {}).get("name", "?"))
	EventBus.chat_received.emit(who, text, channel)
	rpc("cl_chat", who, text, channel)

@rpc("authority", "call_remote", "reliable")
func cl_chat(who: String, text: String, channel: String) -> void:
	EventBus.chat_received.emit(who, text, channel)
