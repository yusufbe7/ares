extends SceneTree
## Runs a real 3D battle headless for a fixed number of ticks and prints what
## happened. Use it to sanity-check combat balance without opening the editor:
##   godot --headless --path . -s res://tests/sim_battle.gd

const TICKS := 1800          # 60 seconds at 30 Hz

func _initialize() -> void:
	print("=== headless battle simulation ===")
	var cfg := {
		"battle_id": 1, "province": -1, "province_name": "Sim",
		"map": "village", "season": "winter", "weather": "snow",
		"seed": 1234, "duration": 180.0,
		"teams": [
			{"team": 0, "nation": "BLUE", "name": "Blue", "color": "3fa7d6",
			"is_defender": false, "roster": {"inf_rifle": 6, "inf_at": 2, "veh_tank": 2}, "tickets": 90, "ai": true},
			{"team": 1, "nation": "RED", "name": "Red", "color": "e05c5c",
			"is_defender": true, "roster": {"inf_rifle": 6, "inf_mg": 2, "veh_tank": 2}, "tickets": 90, "ai": true},
		],
	}
	var battle := Battle.new()
	get_root().add_child(battle)
	battle.start(cfg, 0)
	print("units spawned: %d" % battle.units.size())
	print("cover slots: %d" % battle.cover.slot_count())
	print("buildings: %d" % battle.buildings.size())
	var step := 1.0 / 30.0
	for i in range(TICKS):
		battle._physics_process(step)
		for u in battle.units:
			if is_instance_valid(u) and u.is_alive():
				u._physics_process(step)
		if battle.director.finished:
			break
		if i % 300 == 0:
			print("t=%4ds  tickets %3d/%3d  points %d/%d  alive %d"
				% [int(float(i) * step), battle.director.tickets[0], battle.director.tickets[1],
				battle.director.held_by(0), battle.director.held_by(1),
				battle.units_of_team(0).size() + battle.units_of_team(1).size()])
	print("final tickets: %d / %d" % [battle.director.tickets[0], battle.director.tickets[1]])
	print("points held: %d / %d" % [battle.director.held_by(0), battle.director.held_by(1)])
	print("cover slots after fighting: %d" % battle.cover.slot_count())
	quit(0)
