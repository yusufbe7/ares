extends Node
## Runs real battles headless and prints what happened. Use it to sanity-check
## balance across maps, seasons and victory conditions without opening the
## editor:
##   godot --headless --path . res://tests/sim_battle.tscn

const SECONDS := 90.0
const HZ := 30.0

func _ready() -> void:
	print("=== headless battle simulation ===")
	var cases := [
		{"map": "village", "season": "winter", "weather": "snow", "mode": "capture"},
		{"map": "forest", "season": "autumn", "weather": "fog", "mode": "elimination"},
		{"map": "desert", "season": "summer", "weather": "clear", "mode": "capture"},
		{"map": "city", "season": "spring", "weather": "rain", "mode": "hold"},
		{"map": "mountain", "season": "autumn", "weather": "storm", "mode": "capture"},
		{"map": "military_base", "season": "winter", "weather": "clear", "mode": "destroy"},
	]
	for case in cases:
		_run(case)
	get_tree().quit(0)

func _run(case: Dictionary) -> void:
	var force := {"infantry": 20, "tanks": 3, "transports": 2, "artillery": 1, "aircraft": 1}
	var cfg := BattleSetup.build({
		"map": str(case["map"]), "season": str(case["season"]), "weather": str(case["weather"]),
		"victory_mode": str(case["mode"]), "difficulty": "normal", "minutes": SECONDS / 60.0,
		"seed": 4242, "player_force": force, "enemy_force": force,
	})
	# Both sides on AI, so the simulation plays itself.
	cfg["teams"][0]["ai"] = true

	var battle := Battle.new()
	add_child(battle)
	battle.start(cfg, 0)
	print("\n--- %s / %s / %s / %s" % [case["map"], case["season"], case["weather"], case["mode"]])
	print("  units %d   cover slots %d   buildings %d   trees %d"
		% [battle.units.size(), battle.cover.slot_count(), battle.buildings.size(), battle.trees.size()])

	var step := 1.0 / HZ
	var ticks := int(SECONDS * HZ)
	for i in range(ticks):
		battle._physics_process(step)
		for u in battle.units:
			if is_instance_valid(u) and u.is_alive():
				u._physics_process(step)
		if battle.director.finished:
			break
	var d := battle.director
	var stats := battle.stats
	print("  tickets %d / %d   points %d / %d   alive %d / %d"
		% [d.tickets[0], d.tickets[1], d.held_by(0), d.held_by(1),
		battle.units_of_team(0).size(), battle.units_of_team(1).size()])
	print("  kills %d / %d   losses %d / %d   damage %d / %d"
		% [stats.kills[0], stats.kills[1], stats.losses[0], stats.losses[1],
		int(stats.damage_dealt[0]), int(stats.damage_dealt[1])])
	var best := stats.best_unit(0)
	if best != null:
		print("  best unit (team A): %s with %d kills" % [best.unit_id, best.kills])
	if d.finished:
		print("  FINISHED: winner team %d (%s)"
			% [int(d.result.get("winner_team", -1)), str(d.result.get("reason", ""))])
	else:
		print("  still fighting at the cut-off")
	battle.queue_free()
