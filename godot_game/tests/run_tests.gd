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
	check(DB.battle_maps.size() == 3, "three battle maps are defined")
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

func _test_seasons() -> void:
	print("- seasons and weather")
	check(SeasonCycle.season_for_day(0) == "spring", "the world starts in spring")
	check(SeasonCycle.season_for_day(SeasonCycle.DAYS_PER_SEASON * 3) == "winter", "winter arrives on schedule")
	check(SeasonCycle.snow_amount("winter", "snow") > 0.9, "winter snow covers the battlefield")
	check(SeasonCycle.snow_amount("summer", "clear") == 0.0, "summer has no snow")
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
