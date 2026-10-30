extends Node
## Hosts one 3D battle: the simulation, the camera, the input layer and the HUD.

var battle: Battle
var rig: CameraRig
var controls: BattleControls
var hud: BattleHUD
var _ended: bool = false

func open(payload: Dictionary) -> void:
	var cfg := payload
	if cfg.is_empty() or not cfg.has("teams"):
		GameState.notify("Jang sozlamalari topilmadi.", "bad")
		GameState.go("main_menu", {})
		return

	var local_team := _local_team_for(cfg)

	battle = Battle.new()
	add_child(battle)
	battle.start(cfg, local_team)

	rig = CameraRig.new()
	rig.terrain = battle.terrain
	add_child(rig)
	rig.focus_on(battle.spawn_point_for(local_team))

	controls = BattleControls.new()
	controls.setup(battle, rig)
	add_child(controls)

	hud = BattleHUD.new()
	add_child(hud)
	hud.setup(battle, controls)

	EventBus.battle_ended.connect(_on_battle_ended)
	Net.battle_snapshot_received.connect(_on_snapshot)
	Net.battle_order_received.connect(_on_remote_order)

	GameState.notify("%s — %s, %s"
		% [str(cfg.get("province_name", "Arena")), str(cfg.get("map", "")), str(cfg.get("weather", ""))], "info")

## Which side the local player is on. A custom battle or mission says so
## outright; in a global war it is whichever side is their own nation.
func _local_team_for(cfg: Dictionary) -> int:
	if cfg.has("player_team"):
		return clampi(int(cfg["player_team"]), 0, 1)
	var teams: Array = cfg.get("teams", [])
	for i in range(teams.size()):
		if str(teams[i].get("nation", "")) == GameState.local_nation:
			return i
	return 0

func _on_battle_ended(result: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	GameState.go("result", result)

## A client's order arrives on the server and is replayed into the simulation.
func _on_remote_order(_peer: int, order: Dictionary) -> void:
	if not Net.is_authority() or battle == null:
		return
	var ids: Array = order.get("units", [])
	var list: Array = []
	for u in battle.units:
		if is_instance_valid(u) and ids.has(u.get_instance_id()):
			list.append(u)
	if list.is_empty():
		return
	var pos_arr: Array = order.get("pos", [0, 0, 0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	match str(order.get("kind", "move")):
		"move":
			var s := Squad.new()
			s.units = list
			s.order_move(pos, battle.terrain)
		"hold":
			for u in list:
				u.order_hold()
		"stance":
			for u in list:
				u.order_stance(int(order.get("stance", 0)))

func _on_snapshot(snapshot: Dictionary) -> void:
	if Net.is_authority() or battle == null:
		return
	battle.apply_snapshot(snapshot)

func on_back() -> bool:
	if GameState.mode == GameState.Mode.GLOBAL_WAR:
		GameState.go("world", {})
	else:
		GameState.go("main_menu", {})
	return true
