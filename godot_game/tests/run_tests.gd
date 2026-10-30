extends SceneTree
## Headless test suite.
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if anything fails, so it works in CI.

var passed: int = 0
var failed: int = 0
var failures: Array = []

func _initialize() -> void:
	print("=== World Frontier tests ===")
	_test_data()
	_test_map_grid()
	_test_world_generation()
	_test_economy()
	_test_supply()
	_test_pathfinding()
	_test_diplomacy()
	_test_war_council()
	_test_spend_authority()
	_test_battle_bridge()
	_test_cover_system()
	_test_maps_and_seasons()
	_test_battle_setup()
	_test_campaign()
	_test_battle_stats()
	_test_victory_modes()
	_test_seasons()
	_test_serialization()
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

func _new_world(seed_value: int = 4242) -> WorldState:
	var w := WorldState.new()
	w.generate(seed_value)
	return w

# ---------------------------------------------------------------------------

func _test_data() -> void:
	print("- data")
	check(DB.nations_raw.size() >= 20, "countries.json loads at least 20 nations")
	check(DB.units.has("inf_rifle"), "units.json has inf_rifle")
	check(DB.units.has("veh_tank"), "units.json has veh_tank")
	check(DB.buildings.has("factory"), "buildings.json has factory")
	check(DB.battle_maps.size() == 6, "six battle maps are defined")
	check(DB.unit("veh_tank").get("armor_sides", {}).has("rear"), "tank has a rear armour facing")

func _test_map_grid() -> void:
	print("- map grid")
	var center := MapGrid.index(10, 10)
	check(MapGrid.neighbors(center).size() == 6, "an inner cell has six neighbours")
	check(MapGrid.neighbors(MapGrid.index(0, 0)).size() < 6, "a corner cell has fewer neighbours")
	check(MapGrid.distance(center, center) == 0, "distance to self is zero")
	check(MapGrid.distance(center, MapGrid.index(11, 10)) == 1, "distance to a neighbour is one")
	for nb in MapGrid.neighbors(center):
		check(MapGrid.neighbors(nb).has(center), "adjacency is symmetric")
		break

func _test_world_generation() -> void:
	print("- world generation")
	var w := _new_world()
	check(w.provinces.size() == MapGrid.WIDTH * MapGrid.HEIGHT, "every grid cell became a province")
	check(w.nations.size() >= 20, "all nations were placed")
	var land := 0
	for pid in w.provinces.keys():
		if w.provinces[pid].is_land():
			land += 1
	check(land > 200, "the generator produced a real landmass (%d cells)" % land)
	for nid in w.nations.keys():
		var n: Nation = w.nations[nid]
		check(n.provinces.size() >= 1, "%s owns at least its capital" % nid)
		check(n.capital_province >= 0, "%s has a capital province" % nid)
		check(n.armies.size() >= 1, "%s starts with an army" % nid)
		break
	# Determinism: the same seed must rebuild the same world on every client.
	var w2 := _new_world()
	var same := true
	for pid in w.provinces.keys():
		if w.provinces[pid].owner_id != w2.provinces[pid].owner_id:
			same = false
			break
	check(same, "the same seed generates the same map")

func _test_economy() -> void:
	print("- economy")
	var w := _new_world()
	var nid := str(w.nation_ids()[0])
	var n: Nation = w.nation(nid)
	var income := Economy.income_of(w, nid)
	check(float(income.get("money", 0.0)) > 0.0, "a nation earns money each day")
	var money_before := float(n.resources["money"])
	w.tick_day()
	check(float(n.resources["money"]) != money_before, "the daily tick moves the treasury")

	var pid := int(n.provinces[0])
	n.resources["money"] = 100000.0
	n.resources["steel"] = 100000.0
	var err := Economy.start_construction(w, nid, pid, "farm")
	var p: Province = w.province(pid)
	var terrain_ok: bool = err == "" or err.contains("yer turi")
	check(terrain_ok, "construction either starts or is refused for the terrain")
	if err == "":
		check(p.construction.size() == 1, "the build job is queued")
		for i in range(20):
			w.tick_day()
		check(p.level_of("farm") >= 1, "the building finishes after its build time")

func _test_supply() -> void:
	print("- supply")
	var w := _new_world()
	var nid := str(w.nation_ids()[0])
	var n: Nation = w.nation(nid)
	SupplyNet.recalculate(w)
	var cap: Province = w.province(n.capital_province)
	check(cap.supply > 0.5, "the capital is well supplied")
	for a in n.armies:
		check(a.supply > 0.0, "armies receive a supply value")
		break
	check(SupplyNet.status_text(0.9) != SupplyNet.status_text(0.2), "supply status text differentiates")

func _test_pathfinding() -> void:
	print("- pathfinding")
	var w := _new_world()
	var nid := str(w.nation_ids()[0])
	var n: Nation = w.nation(nid)
	if n.provinces.size() >= 2:
		var from_id := int(n.provinces[0])
		var to_id := int(n.provinces[n.provinces.size() - 1])
		var path := NationAI.path_between(w, from_id, to_id, nid, true)
		check(not path.is_empty(), "a path exists across friendly territory")
		if not path.is_empty():
			check(int(path[path.size() - 1]) == to_id, "the path ends at the destination")

func _test_diplomacy() -> void:
	print("- diplomacy")
	var w := _new_world()
	var pair := _find_neighbour_pair(w)
	check(not pair.is_empty(), "the map contains two bordering nations")
	if pair.is_empty():
		return
	var a := str(pair[0])
	var b := str(pair[1])
	check(Diplomacy.can_declare_war(w, a, b) == "", "neighbours may declare war on each other")
	check(Diplomacy.declare_war(w, a, b, "test") == "", "war is declared")
	check(w.nation(a).is_at_war_with(b), "the attacker is at war")
	check(w.nation(b).is_at_war_with(a), "the defender is at war")
	check(Diplomacy.can_declare_war(w, a, b) != "", "a second declaration is refused")
	check(Diplomacy.make_peace(w, a, b, {"winner": a, "provinces": [], "reparations": 0.0}) == "", "peace is signed")
	check(not w.nation(a).is_at_war_with(b), "the war is over")
	check(Diplomacy.can_declare_war(w, a, b).contains("Sulh"), "the truce blocks an immediate new war")

	# Alliances drag their members in.
	var w2 := _new_world(99)
	var pair2 := _find_neighbour_pair(w2)
	if not pair2.is_empty():
		var x := str(pair2[0])
		var y := str(pair2[1])
		var aid := Diplomacy.create_alliance(w2, x, "Test Pact")
		var third := ""
		for nid in w2.nation_ids():
			if str(nid) != x and str(nid) != y:
				third = str(nid)
				break
		if third != "":
			Diplomacy.join_alliance(w2, third, aid)
			Diplomacy.declare_war(w2, y, x, "test")
			check(w2.nation(third).is_at_war_with(y), "an alliance member joins its partner's war")

func _find_neighbour_pair(w: WorldState) -> Array:
	for a in w.nation_ids():
		for b in w.nation_ids():
			if str(a) != str(b) and w._shares_border(str(a), str(b)):
				return [str(a), str(b)]
	return []

func _test_war_council() -> void:
	print("- war council")
	var w := _new_world()
	var pair := _find_neighbour_pair(w)
	if pair.is_empty():
		return
	var a := str(pair[0])
	var b := str(pair[1])
	var n: Nation = w.nation(a)
	n.is_ai = false
	n.players = [
		{"peer": 1, "name": "Head", "role": GameState.Role.HEAD_OF_STATE, "online": true, "ai": false},
		{"peer": 2, "name": "Cmd", "role": GameState.Role.COMMANDER, "online": true, "ai": false},
		{"peer": 3, "name": "Off", "role": GameState.Role.OFFICER, "online": false, "ai": false},
	]
	# The head of state proposing carries weight 2 of 4 — not a majority yet.
	var vote := WarCouncil.open_vote(w, a, "declare_war", {"target": b, "reason": "test"}, 1)
	check(not vote.has("error"), "a vote opens")
	check(str(vote["status"]) == "open", "the vote is still open on the proposer's own ballot")
	check(WarCouncil.cast_vote(w, str(vote["id"]), 2, true) == "", "a commander can vote")
	check(str(w.votes[vote["id"]]["status"]) == "passed", "a majority closes the vote at once")
	check(w.nation(a).is_at_war_with(b), "the passed vote actually declared the war")

	# An offline council: nobody votes, the deadline decides.
	var w2 := _new_world(7)
	var pair2 := _find_neighbour_pair(w2)
	if pair2.is_empty():
		return
	var c := str(pair2[0])
	var d := str(pair2[1])
	var n2: Nation = w2.nation(c)
	n2.is_ai = false
	n2.players = [
		{"peer": 1, "name": "Solo", "role": GameState.Role.COMMANDER, "online": true, "ai": false},
		{"peer": 2, "name": "Asleep", "role": GameState.Role.COMMANDER, "online": false, "ai": false},
		{"peer": 3, "name": "Asleep2", "role": GameState.Role.COMMANDER, "online": false, "ai": false},
	]
	var v2 := WarCouncil.open_vote(w2, c, "declare_war", {"target": d, "reason": "test"}, 1)
	check(str(v2["status"]) == "open", "one yes of three does not pass immediately")
	for i in range(4):
		w2.tick_day()
	check(str(w2.votes[v2["id"]]["status"]) == "passed",
		"after the deadline a commander's motion carries despite absent players")

	# An officer alone cannot move the nation.
	var w3 := _new_world(11)
	var pair3 := _find_neighbour_pair(w3)
	if pair3.is_empty():
		return
	var e := str(pair3[0])
	var n3: Nation = w3.nation(e)
	n3.is_ai = false
	n3.players = [
		{"peer": 5, "name": "Officer", "role": GameState.Role.OFFICER, "online": true, "ai": false},
		{"peer": 6, "name": "Away", "role": GameState.Role.HEAD_OF_STATE, "online": false, "ai": false},
	]
	var v3 := WarCouncil.open_vote(w3, e, "declare_war", {"target": str(pair3[1])}, 5)
	for i in range(4):
		w3.tick_day()
	check(str(w3.votes[v3["id"]]["status"]) == "failed", "a lone officer's war motion lapses")

func _test_spend_authority() -> void:
	print("- spending authority")
	var w := _new_world()
	var nid := str(w.nation_ids()[0])
	var n: Nation = w.nation(nid)
	n.is_ai = false
	n.resources["money"] = 1000.0
	n.players = [{"peer": 1, "name": "Solo", "role": GameState.Role.COMMANDER, "online": true, "ai": false}]
	check(WarCouncil.within_authority(w, nid, 1, {"money": 900.0}),
		"a nation with one human player needs no vote")
	n.players.append({"peer": 2, "name": "Second", "role": GameState.Role.COMMANDER, "online": true, "ai": false})
	check(WarCouncil.within_authority(w, nid, 1, {"money": 100.0}),
		"a small spend stays within a commander's own authority")
	check(not WarCouncil.within_authority(w, nid, 1, {"money": 900.0}),
		"a spend above the commander's share needs the council")
	var res := WarCouncil.request_spend(w, nid, 1, "build",
		{"province": int(n.provinces[0]), "building": "farm"}, {"money": 900.0})
	check(not res.get("vote", {}).is_empty(), "the oversized spend opened a vote instead of paying")

func _test_battle_bridge() -> void:
	print("- battle bridge")
	var w := _new_world()
	var pair := _find_neighbour_pair(w)
	if pair.is_empty():
		return
	var a := str(pair[0])
	var b := str(pair[1])
	Diplomacy.declare_war(w, a, b, "test")
	var target := -1
	for pid in w.nation(b).provinces:
		for nb in MapGrid.neighbors(int(pid)):
			if str(w.province(nb).owner_id) == a:
				target = int(pid)
				break
		if target >= 0:
			break
	check(target >= 0, "a front province exists between the two")
	if target < 0:
		return
	var army: ArmyGroup = w.nation(a).armies[0]
	army.province = target
	var battle := w.queue_battle(target, a, b)
	var cfg := BattleBridge.build_config(w, battle)
	check(cfg.get("teams", []).size() == 2, "the battle config has two sides")
	check(not cfg["teams"][0].get("roster", {}).is_empty(), "the attacker brings units")
	check(DB.battle_maps.has(str(cfg.get("map", ""))), "the battle map id is real")
	check(DB.victory_modes.has(str(cfg.get("victory_mode", ""))), "the province picked a real victory mode")
	var result := BattleBridge.auto_resolve(w, battle)
	check(result.has("winner"), "auto resolution picks a winner")
	var owner_before := w.province(target).owner_id
	result["winner"] = a
	result["attacker_losses"] = 0.2
	result["defender_losses"] = 0.5
	BattleBridge.apply_result(w, result)
	check(w.province(target).owner_id == a, "the winner takes the province (was %s)" % owner_before)
	check(w.province(target).unrest > 0.5, "a freshly taken province is restless")
	check(w.pending_battles.is_empty(), "the resolved battle left the queue")

func _test_cover_system() -> void:
	print("- cover system")
	var cover := CoverSystem.new()
	cover.add_building(Vector3.ZERO, Vector3(10, 4, 8), 0.0)
	check(cover.slot_count() > 8, "a house publishes cover on every face and corner")
	# Threat from the north: the chosen slot should face that way.
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

func _test_maps_and_seasons() -> void:
	print("- maps, seasons and modes")
	for id in ["village", "forest", "desert", "city", "mountain", "military_base"]:
		var m: Dictionary = DB.battle_map(id)
		check(str(m.get("id", "")) == id, "map %s exists" % id)
		check(not m.get("props", {}).is_empty(), "map %s declares its props" % id)
		check(float(m.get("size", 0)) > 100.0, "map %s has a real size" % id)
	check(DB.battle_map("mountain").get("relief", 1.0) > DB.battle_map("city").get("relief", 1.0),
		"mountains are more broken ground than a city")
	check(float(DB.battle_map("forest").get("vision_mod", 1.0)) < 1.0, "the forest shortens sight")
	check(float(DB.battle_map("desert").get("vision_mod", 1.0)) > 1.0, "the desert lengthens it")

	check(DB.season_ids().size() == 4, "four seasons are defined")
	for sid in ["spring", "summer", "autumn", "winter"]:
		var season: Dictionary = DB.season(sid)
		check(season.has("ground") and season.has("canopy") and season.has("sky_top"),
			"season %s carries a full palette" % sid)
		check(not season.get("weather_bias", {}).is_empty(), "season %s has weather odds" % sid)
	check(float(DB.season("winter").get("snow", 0.0)) > 0.5, "winter is a snow season")
	check(float(DB.season("summer").get("snow", 1.0)) == 0.0, "summer is not")
	check(float(DB.season("autumn").get("leaves", 0.0)) > 0.5, "autumn drops leaves")
	# The same map in two seasons must come out looking different.
	var spring_ground := DB.season_color("spring", "ground", Color.BLACK)
	var winter_ground := DB.season_color("winter", "ground", Color.BLACK)
	check(spring_ground != winter_ground, "the ground is repainted per season")

	check(DB.victory_modes.size() == 4, "four victory conditions are defined")
	for vid in ["elimination", "capture", "hold", "destroy"]:
		check(DB.victory_modes.has(vid), "victory mode %s exists" % vid)
	check(DB.difficulties.size() == 3, "three bot skill levels are defined")
	check(float(DB.difficulty("hard").get("aggression", 0.0))
		> float(DB.difficulty("easy").get("aggression", 1.0)), "hard bots push harder")
	check(float(DB.difficulty("hard").get("reaction", 9.0))
		< float(DB.difficulty("easy").get("reaction", 0.0)), "hard bots decide faster")

func _test_battle_setup() -> void:
	print("- battle setup")
	var force := {"infantry": 30, "tanks": 3, "transports": 2, "artillery": 1, "aircraft": 1}
	check(BattleSetup.unit_total(force) == 37, "the unit count is the sum of the sliders")
	var roster := BattleSetup.roster_from_force(force)
	var infantry_total := 0
	for uid in roster.keys():
		if str(DB.unit(str(uid)).get("class", "")) == "infantry":
			infantry_total += int(roster[uid])
	check(infantry_total == 30, "every requested soldier is placed (%d)" % infantry_total)
	check(int(roster.get("inf_at", 0)) > 0, "the infantry mix always includes anti-tank")
	check(int(roster.get("inf_recon", 0)) > 0, "the infantry mix always includes recon")
	check(int(roster.get("veh_tank", 0)) == 3, "tanks come through as asked")
	check(int(roster.get("veh_apc", 0)) == 2, "transports come through as asked")
	check(roster.has("air_heli"), "air support is split into a gunship")
	check(BattleSetup.tickets_for(force) > 30, "the reserve is larger than the first wave")

	var small := BattleSetup.roster_from_force({"infantry": 3})
	var small_total := 0
	for uid in small.keys():
		small_total += int(small[uid])
	check(small_total == 3, "a tiny force is not padded out")

	var cfg := BattleSetup.build({"map": "city", "season": "winter", "weather": "snow",
		"victory_mode": "destroy", "difficulty": "hard", "minutes": 10.0,
		"player_force": force, "enemy_force": force})
	check(str(cfg["map"]) == "city", "the chosen map reaches the config")
	check(str(cfg["victory_mode"]) == "destroy", "the chosen victory mode reaches the config")
	check(float(cfg["duration"]) == 600.0, "minutes are converted to seconds")
	check(cfg["teams"].size() == 2, "both sides are built")
	check(not bool(cfg["teams"][0]["ai"]), "the player side is not AI")
	check(bool(cfg["teams"][1]["ai"]), "the enemy side is AI")

	var sb := BattleSetup.sandbox({"map": "desert", "player_force": force, "enemy_force": force})
	check(bool(sb["sandbox"]), "sandbox is flagged")
	check(float(sb["duration"]) == 0.0, "sandbox has no clock")

func _test_campaign() -> void:
	print("- campaign")
	check(DB.missions.size() >= 6, "the campaign has missions")
	var orders: Array = []
	for m in DB.missions:
		orders.append(int(m.get("order", 0)))
	var sorted_orders: Array = orders.duplicate()
	sorted_orders.sort()
	check(orders == sorted_orders, "missions are in order")
	var used_maps: Dictionary = {}
	for m in DB.missions:
		check(DB.battle_maps.has(str(m.get("map", ""))), "mission %s uses a real map" % str(m.get("id", "")))
		check(DB.victory_modes.has(str(m.get("victory_mode", ""))),
			"mission %s uses a real victory mode" % str(m.get("id", "")))
		used_maps[str(m.get("map", ""))] = true
	check(used_maps.size() >= 5, "the campaign visits most of the maps")

	var first := str(DB.missions[0].get("id", ""))
	var second := str(DB.missions[1].get("id", ""))
	GameState.completed_missions = []
	check(GameState.mission_unlocked(first), "the first mission is always open")
	check(not GameState.mission_unlocked(second), "the second is locked until the first is won")
	GameState.completed_missions = [first]
	check(GameState.mission_unlocked(second), "winning one mission opens the next")
	GameState.completed_missions = []

	var cfg := BattleSetup.from_mission(DB.missions[0])
	check(str(cfg["mission"]) == first, "the config remembers which mission it is")
	check(not cfg["teams"][0]["roster"].is_empty(), "the mission fields a force")

func _test_battle_stats() -> void:
	print("- battle statistics")
	var stats := BattleStats.new()
	stats.setup({"teams": [{"name": "Blue"}, {"name": "Red"}]})
	stats.on_spawn(0, "veh_tank")
	stats.on_spawn(0, "inf_rifle")
	stats.on_spawn(1, "inf_rifle")
	stats.on_damage(0, "veh_tank", 300.0)
	stats.on_kill(1, "inf_rifle", "infantry", 1, 0, "veh_tank")
	stats.on_kill(1, "inf_rifle", "infantry", 1, 0, "veh_tank")
	stats.on_kill(0, "inf_rifle", "infantry", 1, 1, "inf_rifle")
	check(stats.kills[0] == 2, "kills are credited to the right side")
	check(stats.losses[1] == 2, "losses are counted on the side that took them")
	check(stats.losses[0] == 1, "both sides are tracked")
	check(stats.damage_dealt[0] == 300.0, "damage is accumulated")
	var best := stats.best_unit(0)
	check(best != null and best.unit_id == "veh_tank", "the stand-out unit type is identified")
	stats.on_kill(0, "veh_tank", "vehicle", 3, 1, "inf_at")
	check(stats.vehicles_lost[0] == 1, "vehicle losses are counted separately")
	check(stats.men_lost[0] == 4, "men lost adds up the crew too")
	var d := stats.to_dict()
	check(d.has("records") and not d["records"].is_empty(), "the report serializes per-unit rows")
	check(str(d["best_unit"][0]) == "veh_tank", "the report names the best unit")

func _test_victory_modes() -> void:
	print("- victory conditions")
	# Destroy: losing the command post ends it, whatever else is happening.
	var fake := FakeBattle.new()
	var post := FakePost.new()
	post.team = 1
	fake.posts = [null, post]
	var d := BattleDirector.new()
	d.battle = fake
	d.setup(fake, {"victory_mode": "destroy", "duration": 600.0,
		"teams": [{"tickets": 50}, {"tickets": 50}], "player_team": 0})
	check(d.mode == "destroy", "the director took the mode")
	d.on_objective_destroyed(post)
	check(d.finished, "destroying the post ends the battle")
	check(int(fake.finished_with.get("winner_team", -1)) == 0, "the other side wins")
	d.free()

	# Hold: the defender wins by surviving the clock.
	var fake2 := FakeBattle.new()
	var d2 := BattleDirector.new()
	d2.battle = fake2
	d2.setup(fake2, {"victory_mode": "hold", "duration": 2.0,
		"teams": [{"tickets": 50, "is_defender": false}, {"tickets": 50, "is_defender": true}],
		"player_team": 0})
	check(d2.hold_defender == 1, "the defender is read from the setup")
	for i in range(30):
		d2.tick(0.2, [])
	check(d2.finished, "the clock ends a hold match")
	check(int(fake2.finished_with.get("winner_team", -1)) == 1, "surviving the clock wins it")
	d2.free()

	# Elimination: a side with nothing left loses.
	var fake3 := FakeBattle.new()
	var d3 := BattleDirector.new()
	d3.battle = fake3
	d3.setup(fake3, {"victory_mode": "elimination", "duration": 600.0,
		"teams": [{"tickets": 40}, {"tickets": 0}], "player_team": 0})
	d3.tick(0.1, [])
	check(d3.finished, "an empty side ends an elimination match")
	check(int(fake3.finished_with.get("winner_team", -1)) == 0, "the surviving side wins")
	d3.free()

	# Sandbox never ends.
	var fake4 := FakeBattle.new()
	var d4 := BattleDirector.new()
	d4.battle = fake4
	d4.setup(fake4, {"victory_mode": "elimination", "duration": 1.0, "sandbox": true,
		"teams": [{"tickets": 0}, {"tickets": 0}], "player_team": 0})
	for i in range(20):
		d4.tick(0.2, [])
	check(not d4.finished, "a sandbox never declares a winner")
	check(d4.supply[0] > 1000.0, "a sandbox keeps the player supplied")
	d4.free()

func _test_seasons() -> void:
	print("- seasons and weather")
	check(SeasonCycle.season_for_day(0) == "spring", "the world starts in spring")
	check(SeasonCycle.season_for_day(SeasonCycle.DAYS_PER_SEASON * 3) == "winter", "winter arrives on schedule")
	check(SeasonCycle.snow_amount("winter", "snow") > 0.9, "winter snow covers the battlefield")
	check(SeasonCycle.snow_amount("summer", "clear") == 0.0, "summer has no snow")
	check(SeasonCycle.wetness("autumn", "rain") > SeasonCycle.wetness("summer", "clear"),
		"autumn rain leaves the ground wetter than a dry summer")
	var w := _new_world()
	w.season = "winter"
	w.weather = "snow"
	check(SeasonCycle.movement_modifier(w) < 1.0, "winter slows armies down")
	check(SeasonCycle.vision_modifier(w) < 1.0, "snow shortens sight")

func _test_serialization() -> void:
	print("- serialization")
	var w := _new_world()
	for i in range(5):
		w.tick_day()
	var data := w.to_dict()
	var json := JSON.stringify(data)
	check(json.length() > 1000, "the world serializes to JSON")
	var parsed: Variant = JSON.parse_string(json)
	check(typeof(parsed) == TYPE_DICTIONARY, "the JSON parses back")
	var w2 := WorldState.new()
	w2.from_dict(parsed)
	check(w2.provinces.size() == w.provinces.size(), "every province survives the round trip")
	check(w2.nations.size() == w.nations.size(), "every nation survives the round trip")
	check(w2.day == w.day, "the day counter survives")
	var nid := str(w.nation_ids()[0])
	check(w2.nation(nid).provinces.size() == w.nation(nid).provinces.size(),
		"province ownership survives the round trip")
	check(w2.nation(nid).armies.size() == w.nation(nid).armies.size(), "armies survive the round trip")
