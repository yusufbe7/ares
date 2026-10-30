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
		GameState.go("setup", {})
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

	GameState.notify("%s — %s, %s"
		% [str(cfg.get("province_name", "Arena")), str(cfg.get("map", "")), str(cfg.get("weather", ""))], "info")

## Which side the local player is on. The setup screen says so outright; a
## config that does not name one puts the player on the first side.
func _local_team_for(cfg: Dictionary) -> int:
	if cfg.has("player_team"):
		return clampi(int(cfg["player_team"]), 0, 1)
	var teams: Array = cfg.get("teams", [])
	for i in range(teams.size()):
		if not bool(teams[i].get("ai", true)):
			return i
	return 0

func _on_battle_ended(result: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	GameState.go("result", result)

func on_back() -> bool:
	GameState.go("setup", {})
	return true
