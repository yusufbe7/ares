extends SceneTree
## Headless test suite.
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if anything fails, so it works in CI.

var passed: int = 0
var failed: int = 0
var failures: Array = []

func _initialize() -> void:
	print("=== Frontline tests ===")
	_test_data()
	_test_maps_and_seasons()
	_test_factions()
	_test_battle_setup()
	_test_cover_system()
	_test_victory_modes()
	_test_support_strikes()
	_test_battle_stats()
	_test_seasons()
	print("---")
	print("PASS: %d   FAIL: %d" % [passed, failed])
	for f in failures:
		print("  FAILED: %s" % f)
	quit(1 if failed > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		print("  [x] %s" % label)

## A stand-in for Battle, so the director can be tested without a scene tree.
class FakeBattle extends RefCounted:
	var finished_with: Dictionary = {}
	var posts: Array = [null, null]
	var victory_mode: String = "capture"

	func on_battle_finished(res: Dictionary) -> void:
		finished_with = res

	func on_point_captured(_p) -> void:
		pass

	func objective_for(team: int):
		return posts[team]

class FakePost extends RefCounted:
	var team: int = 0
	var health: float = 1.0

	func health_fraction() -> float:
		return health

class FakeUnit extends RefCounted:
	var team: int = 0
	var men: int = 1
	var alive: bool = true

	func is_alive() -> bool:
		return alive

	func men_count() -> int:
		return men

# ---------------------------------------------------------------------------

func _test_data() -> void:
	print("- data")
	check(DB.units.has("inf_rifle"), "units.json has the rifleman")
	check(DB.units.has("inf_insurgent"), "units.json has the insurgent")
	check(DB.units.has("veh_technical"), "units.json has the technical")
	check(DB.units.has("veh_tank"), "units.json has the tank")
	check(DB.unit("veh_tank").get("armor_sides", {}).has("rear"), "the tank has a rear armour facing")
	check(int(DB.unit("inf_rifle").get("men", 0)) == 1, "one infantry unit is one man")
	check(int(DB.unit("veh_tank").get("men", 0)) > 1, "a tank costs its crew")
	check(float(DB.unit("veh_technical").get("speed", 0)) > float(DB.unit("veh_tank").get("speed", 99)),
		"a technical is faster than a tank")
	check(float(DB.unit("veh_technical").get("armor", 9)) < float(DB.unit("veh_tank").get("armor", 0)),
		"and far thinner skinned")

func _test_maps_and_seasons() -> void:
	print("- maps, seasons and modes")
	for id in ["village", "forest", "desert", "city", "mountain", "military_base"]:
		var m: Dictionary = DB.battle_map(id)
		check(str(m.get("id", "")) == id, "map %s exists" % id)
		check(not m.get("props", {}).is_empty(), "map %s declares its props" % id)
		check(float(m.get("size", 0)) > 100.0, "map %s has a real size" % id)
	check(DB.battle_maps.size() == 6, "six battle maps are defined")
	check(float(DB.battle_map("mountain").get("relief", 1.0))
		> float(DB.battle_map("city").get("relief", 1.0)),
		"mountains are more broken ground than a city")
	check(float(DB.battle_map("forest").get("vision_mod", 1.0)) < 1.0, "the forest shortens sight")
	check(float(DB.battle_map("desert").get("vision_mod", 1.0)) > 1.0, "the desert lengthens it")
	check(not DB.battle_map("village").get("river", {}).is_empty(), "the village has a river")
	check(int(DB.battle_map("village").get("river", {}).get("bridges", 0)) > 0,
		"and at least one crossing over it")
	check(int(DB.map_props("village").get("hay", 0)) > 0, "the village has hay bales")
	check(int(DB.map_props("village").get("bushes", 0)) > 0, "and scrub on the ground")

	check(DB.season_ids().size() == 4, "four seasons are defined")
	for sid in ["spring", "summer", "autumn", "winter"]:
		var season: Dictionary = DB.season(sid)
		check(season.has("ground") and season.has("canopy") and season.has("sky_top"),
			"season %s carries a full palette" % sid)
		check(not season.get("weather_bias", {}).is_empty(), "season %s has weather odds" % sid)
	check(float(DB.season("winter").get("snow", 0.0)) > 0.5, "winter is a snow season")
	check(float(DB.season("summer").get("snow", 1.0)) == 0.0, "summer is not")
	check(float(DB.season("autumn").get("leaves", 0.0)) > 0.5, "autumn drops leaves")
	check(DB.season_color("spring", "ground", Color.BLACK) != DB.season_color("winter", "ground", Color.BLACK),
		"the ground is repainted per season")

	check(DB.victory_modes.size() == 4, "four victory conditions are defined")
	for vid in ["elimination", "capture", "hold", "destroy"]:
		check(DB.victory_modes.has(vid), "victory mode %s exists" % vid)
	check(DB.difficulties.size() == 3, "three bot skill levels are defined")
	check(float(DB.difficulty("hard").get("aggression", 0.0))
		> float(DB.difficulty("easy").get("aggression", 1.0)), "hard bots push harder")
	check(float(DB.difficulty("hard").get("reaction", 9.0))
		< float(DB.difficulty("easy").get("reaction", 0.0)), "hard bots decide faster")

func _test_factions() -> void:
	print("- factions")
	check(DB.faction_ids().size() == 2, "two sides are defined")
	check(DB.factions.has("army") and DB.factions.has("insurgent"), "army and insurgents")
	var force := {"infantry": 20, "tanks": 2, "transports": 2, "artillery": 0, "aircraft": 0}
	var army := BattleSetup.roster_from_force(force, "army")
	var irregular := BattleSetup.roster_from_force(force, "insurgent")
	check(army.has("inf_rifle"), "the army fields riflemen")
	check(irregular.has("inf_insurgent"), "the insurgents field their own fighters")
	check(not irregular.has("inf_rifle"), "and not the army's")
	check(army.has("veh_apc"), "the army's transport is an APC")
	check(irregular.has("veh_technical"), "the insurgents' transport is a technical")
	check(irregular.has("inf_rpg"), "the insurgents carry RPGs for anti-tank work")
	var army_total := 0
	var irregular_total := 0
	for uid in army.keys():
		army_total += int(army[uid])
	for uid in irregular.keys():
		irregular_total += int(irregular[uid])
	check(army_total == irregular_total, "the same order of battle fields the same number of units")

func _test_battle_setup() -> void:
	print("- battle setup")
	var force := {"infantry": 30, "tanks": 3, "transports": 2, "artillery": 1, "aircraft": 1}
	check(BattleSetup.unit_total(force) == 37, "the unit count is the sum of the sliders")
	var roster := BattleSetup.roster_from_force(force, "army")
	var infantry_total := 0
	for uid in roster.keys():
		if str(DB.unit(str(uid)).get("class", "")) == "infantry":
			infantry_total += int(roster[uid])
	check(infantry_total == 30, "every requested soldier is placed (%d)" % infantry_total)
	check(int(roster.get("inf_at", 0)) > 0, "the infantry mix always includes anti-tank")
	check(int(roster.get("inf_recon", 0)) > 0, "the infantry mix always includes recon")
	check(int(roster.get("veh_tank", 0)) == 3, "tanks come through as asked")
	check(int(roster.get("veh_apc", 0)) == 2, "transports come through as asked")
	check(BattleSetup.tickets_for(force, "army") > 30, "the reserve is larger than the first wave")

	var small := BattleSetup.roster_from_force({"infantry": 3}, "army")
	var small_total := 0
	for uid in small.keys():
		small_total += int(small[uid])
	check(small_total == 3, "a tiny force is not padded out")

	var cfg := BattleSetup.build({"map": "city", "season": "winter", "weather": "snow",
		"victory_mode": "destroy", "difficulty": "hard", "minutes": 10.0,
		"player_force": force, "enemy_force": force,
		"player_faction": "army", "enemy_faction": "insurgent"})
	check(str(cfg["map"]) == "city", "the chosen map reaches the config")
	check(str(cfg["victory_mode"]) == "destroy", "the chosen victory mode reaches the config")
	check(float(cfg["duration"]) == 600.0, "minutes are converted to seconds")
	check(cfg["teams"].size() == 2, "both sides are built")
	check(not bool(cfg["teams"][0]["ai"]), "the player side is not AI")
	check(bool(cfg["teams"][1]["ai"]), "the enemy side is AI")
	check(str(cfg["teams"][1]["faction"]) == "insurgent", "the enemy side carries its faction")

	var sb := BattleSetup.sandbox({"map": "desert", "player_force": force, "enemy_force": force})
	check(bool(sb["sandbox"]), "sandbox is flagged")
	check(float(sb["duration"]) == 0.0, "sandbox has no clock")

func _test_cover_system() -> void:
	print("- cover system")
	var cover := CoverSystem.new()
	cover.add_building(Vector3.ZERO, Vector3(10, 4, 8), 0.0)
	check(cover.slot_count() > 8, "a house publishes cover on every face and corner")
	var threat := Vector3(0, 0, -1)
	var slot = cover.best_slot(Vector3(0, 0, -12), threat, 30.0, 1)
	check(slot != null, "a soldier finds cover near a house")
	if slot != null:
		check(slot.facing.dot(threat) > 0.0, "the chosen slot faces the threat")
		cover.take(slot, 1)
		var other = cover.best_slot(slot.position, threat, 2.0, 2)
		check(other == null or other != slot, "a taken slot is not handed to a second soldier")
		cover.release(slot, 1)
		check(slot.occupant == 0, "releasing frees the slot")
	cover.invalidate_near(Vector3.ZERO, 40.0)
	check(cover.slot_count() == 0, "blown-up cover stops being offered")
	var trench_cover := CoverSystem.new()
	trench_cover.add_trench(Vector3(-10, 0, 0), Vector3(10, 0, 0))
	check(trench_cover.slot_count() > 3, "a trench publishes cover along its length")
	cover.free()
	trench_cover.free()

func _test_victory_modes() -> void:
	print("- victory conditions")
	var fake := FakeBattle.new()
	var post := FakePost.new()
	post.team = 1
	fake.posts = [null, post]
	var d := BattleDirector.new()
	d.setup(fake, {"victory_mode": "destroy", "duration": 600.0,
		"teams": [{"tickets": 50}, {"tickets": 50}], "player_team": 0})
	check(d.mode == "destroy", "the director took the mode")
	d.on_objective_destroyed(post)
	check(d.finished, "destroying the post ends the battle")
	check(int(fake.finished_with.get("winner_team", -1)) == 0, "the other side wins")
	d.free()

	var fake2 := FakeBattle.new()
	var d2 := BattleDirector.new()
	d2.setup(fake2, {"victory_mode": "hold", "duration": 2.0,
		"teams": [{"tickets": 50, "is_defender": false}, {"tickets": 50, "is_defender": true}],
		"player_team": 0})
	check(d2.hold_defender == 1, "the defender is read from the setup")
	for i in range(30):
		d2.tick(0.2, [])
	check(d2.finished, "the clock ends a hold match")
	check(int(fake2.finished_with.get("winner_team", -1)) == 1, "surviving the clock wins it")
	d2.free()

	var fake3 := FakeBattle.new()
	var d3 := BattleDirector.new()
	d3.setup(fake3, {"victory_mode": "elimination", "duration": 600.0,
		"teams": [{"tickets": 40}, {"tickets": 0}], "player_team": 0})
	d3.tick(0.1, [])
	check(d3.finished, "an empty side ends an elimination match")
	check(int(fake3.finished_with.get("winner_team", -1)) == 0, "the surviving side wins")
	d3.free()

	var fake4 := FakeBattle.new()
	var d4 := BattleDirector.new()
	d4.setup(fake4, {"victory_mode": "elimination", "duration": 1.0, "sandbox": true,
		"teams": [{"tickets": 0}, {"tickets": 0}], "player_team": 0})
	for i in range(20):
		d4.tick(0.2, [])
	check(not d4.finished, "a sandbox never declares a winner")
	check(d4.supply[0] > 1000.0, "a sandbox keeps the player supplied")
	d4.free()

func _test_support_strikes() -> void:
	print("- air strike and nuke")
	var fake := FakeBattle.new()
	var d := BattleDirector.new()
	d.setup(fake, {"victory_mode": "capture", "duration": 600.0,
		"teams": [{"tickets": 50}, {"tickets": 50}], "player_team": 0})
	check(not d.air_strike_ready(0), "the first air strike is not available at the whistle")
	for i in range(300):
		d.tick(0.2, [])
	check(d.air_strike_ready(0), "it comes round after its cooldown")
	check(d.use_air_strike(0), "calling it succeeds")
	check(not d.air_strike_ready(0), "and puts it back on cooldown")
	check(d.nuke_ready(1), "each side starts with one nuke")
	check(d.use_nuke(1), "which can be fired once")
	check(not d.use_nuke(1), "and never twice")

	var units: Array = []
	for i in range(4):
		var u := FakeUnit.new()
		u.team = 0
		units.append(u)
	var crew := FakeUnit.new()
	crew.team = 0
	crew.men = 3
	units.append(crew)
	var enemy := FakeUnit.new()
	enemy.team = 1
	units.append(enemy)
	check(d.men_alive(0, units) == 7, "the men counter adds up bodies and crews")
	check(d.men_alive(1, units) == 1, "and counts each side separately")
	crew.alive = false
	check(d.men_alive(0, units) == 4, "the dead stop counting")
	d.free()

func _test_battle_stats() -> void:
	print("- battle statistics")
	var stats := BattleStats.new()
	stats.setup({"teams": [{"name": "Army"}, {"name": "Insurgents"}]})
	stats.on_spawn(0, "veh_tank")
	stats.on_spawn(0, "inf_rifle")
	stats.on_spawn(1, "inf_insurgent")
	stats.on_damage(0, "veh_tank", 300.0)
	stats.on_kill(1, "inf_insurgent", "infantry", 1, 0, "veh_tank")
	stats.on_kill(1, "inf_insurgent", "infantry", 1, 0, "veh_tank")
	stats.on_kill(0, "inf_rifle", "infantry", 1, 1, "inf_rpg")
	check(stats.kills[0] == 2, "kills are credited to the right side")
	check(stats.losses[1] == 2, "losses are counted on the side that took them")
	check(stats.losses[0] == 1, "both sides are tracked")
	check(stats.damage_dealt[0] == 300.0, "damage is accumulated")
	var best := stats.best_unit(0)
	check(best != null and best.unit_id == "veh_tank", "the stand-out unit type is identified")
	stats.on_kill(0, "veh_tank", "vehicle", 3, 1, "inf_rpg")
	check(stats.vehicles_lost[0] == 1, "vehicle losses are counted separately")
	check(stats.men_lost[0] == 4, "men lost adds up the crew too")
	var d := stats.to_dict()
	check(d.has("records") and not d["records"].is_empty(), "the report serializes per-unit rows")
	check(str(d["best_unit"][0]) == "veh_tank", "the report names the best unit")

func _test_seasons() -> void:
	print("- seasons and weather")
	check(SeasonCycle.season_for_day(0) == "spring", "the cycle starts in spring")
	check(SeasonCycle.season_for_day(SeasonCycle.DAYS_PER_SEASON * 3) == "winter",
		"winter arrives on schedule")
	check(SeasonCycle.snow_amount("winter", "snow") > 0.9, "winter snow covers the battlefield")
	check(SeasonCycle.snow_amount("summer", "clear") == 0.0, "summer has no snow")
	check(SeasonCycle.wetness("autumn", "rain") > SeasonCycle.wetness("summer", "clear"),
		"autumn rain leaves the ground wetter than a dry summer")
	check(float(DB.weather("fog").get("vision", 1.0)) < float(DB.weather("clear").get("vision", 0.0)),
		"fog shortens sight")
	check(float(DB.weather("snow").get("speed", 1.0)) < 1.0, "falling snow slows movement")
