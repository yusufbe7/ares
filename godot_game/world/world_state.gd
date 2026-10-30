class_name WorldState
extends RefCounted
## The persistent global world: provinces, nations, alliances, wars and the
## day clock. The server owns one of these; clients hold a synced copy.
##
## Helper systems (Economy, SupplyNet, Diplomacy, WarCouncil, NationAI,
## SeasonCycle) take this object untyped on purpose, so none of them creates a
## cyclic class dependency back to WorldState.

var seed_value: int = 0
var day: int = 0
var season: String = "spring"
var weather: String = "clear"

var provinces: Dictionary = {}       # int id -> Province
var nations: Dictionary = {}         # String id -> Nation
var alliances: Dictionary = {}       # String id -> {id, name, members, leader}
var votes: Dictionary = {}           # String id -> vote dictionary
var wars: Array = []                 # [{attacker, defender, since, fronts:[]}]
var pending_battles: Array = []      # [{id, province, attacker, defender, ...}]
var log_lines: Array = []            # recent world events, newest last

var _next_army_id: int = 1
var _next_vote_id: int = 1
var _next_battle_id: int = 1

# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func generate(seed_input: int) -> void:
	seed_value = seed_input
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_input
	_generate_terrain(rng)
	_place_nations(rng)
	_seed_armies(rng)
	_seed_relations(rng)
	day = 0
	season = "spring"
	weather = "clear"
	push_log("Yangi dunyo yaratildi. Seed: %d" % seed_input)

func _generate_terrain(rng: RandomNumberGenerator) -> void:
	provinces.clear()
	var land_noise := FastNoiseLite.new()
	land_noise.seed = seed_input_safe(rng)
	land_noise.frequency = 0.06
	land_noise.fractal_octaves = 4

	var elev_noise := FastNoiseLite.new()
	elev_noise.seed = seed_input_safe(rng)
	elev_noise.frequency = 0.11
	elev_noise.fractal_octaves = 3

	var arid_noise := FastNoiseLite.new()
	arid_noise.seed = seed_input_safe(rng)
	arid_noise.frequency = 0.08

	for row in range(MapGrid.HEIGHT):
		for col in range(MapGrid.WIDTH):
			var p := Province.new()
			p.id = MapGrid.index(col, row)
			# Edge falloff keeps an ocean rim around the landmass.
			var nx := float(col) / float(MapGrid.WIDTH)
			var ny := float(row) / float(MapGrid.HEIGHT)
			var edge: float = minf(minf(nx, 1.0 - nx), minf(ny, 1.0 - ny))
			var land_value: float = land_noise.get_noise_2d(float(col), float(row)) * 0.5 + 0.5
			land_value += clampf(edge * 3.0 - 0.35, -0.6, 0.45)
			if land_value < 0.42:
				p.terrain = Province.Terrain.OCEAN
			else:
				var elev: float = elev_noise.get_noise_2d(float(col), float(row)) * 0.5 + 0.5
				var arid: float = arid_noise.get_noise_2d(float(col) + 100.0, float(row) - 50.0) * 0.5 + 0.5
				if elev > 0.76:
					p.terrain = Province.Terrain.MOUNTAIN
				elif elev > 0.62:
					p.terrain = Province.Terrain.HILLS
				elif arid > 0.68:
					p.terrain = Province.Terrain.DESERT
				elif arid < 0.36:
					p.terrain = Province.Terrain.FOREST
				else:
					p.terrain = Province.Terrain.PLAINS
			p.population = _population_for(p.terrain, rng)
			p.name = ""
			provinces[p.id] = p

func seed_input_safe(rng: RandomNumberGenerator) -> int:
	return int(rng.randi_range(1, 2000000000))

func _population_for(terrain: int, rng: RandomNumberGenerator) -> int:
	match terrain:
		Province.Terrain.OCEAN: return 0
		Province.Terrain.MOUNTAIN: return rng.randi_range(8000, 40000)
		Province.Terrain.DESERT: return rng.randi_range(5000, 35000)
		Province.Terrain.FOREST: return rng.randi_range(20000, 90000)
		Province.Terrain.HILLS: return rng.randi_range(25000, 110000)
		_: return rng.randi_range(40000, 220000)

func _place_nations(rng: RandomNumberGenerator) -> void:
	nations.clear()
	var wanted: Dictionary = {}      # nation id -> province budget
	var frontier: Dictionary = {}    # nation id -> Array[int]

	for raw in DB.nations_raw:
		var n := Nation.new()
		n.id = str(raw["id"])
		n.display_name = DB.local_name(raw.get("name", {}), n.id)
		n.color = Color.from_string(str(raw.get("color", "#ffffff")), Color.WHITE)
		n.capital_name = str(raw.get("capital", ""))
		n.tier = int(raw.get("tier", 1))
		n.doctrine = str(raw.get("doctrine", "combined_arms"))
		n.is_ai = true
		var td: Dictionary = DB.tier_data(n.tier)
		n.resources["money"] = float(td.get("start_money", 1000))
		n.resources["manpower"] = float(td.get("start_manpower", 50000))
		n.resources["food"] = 400.0
		n.resources["fuel"] = 300.0
		n.resources["steel"] = 250.0
		n.resources["ammo"] = 300.0
		var home: Array = raw.get("home", [0.5, 0.5])
		var cap := _nearest_land(float(home[0]), float(home[1]))
		if cap < 0:
			continue
		n.capital_province = cap
		var cap_p: Province = provinces[cap]
		cap_p.owner_id = n.id
		cap_p.is_capital = true
		cap_p.terrain = Province.Terrain.URBAN
		cap_p.name = n.capital_name
		cap_p.population = rng.randi_range(600000, 2400000)
		cap_p.development = {"factory": 1, "power_plant": 1, "military_base": 1}
		n.provinces.append(cap)
		nations[n.id] = n
		wanted[n.id] = int(DB.tier_data(n.tier).get("provinces", 4))
		frontier[n.id] = [cap]

	# Round-robin growth so that no nation eats the map before the others move.
	var growing := true
	while growing:
		growing = false
		for nid in nations.keys():
			var n: Nation = nations[nid]
			if n.provinces.size() >= int(wanted[nid]):
				continue
			var added := _grow_once(n, frontier[nid], rng)
			if added:
				growing = true

	_name_provinces(rng)

func _grow_once(n: Nation, frontier: Array, rng: RandomNumberGenerator) -> bool:
	while not frontier.is_empty():
		var idx: int = int(frontier[rng.randi_range(0, frontier.size() - 1)])
		var options: Array = []
		for nb in MapGrid.neighbors(idx):
			var p: Province = provinces[nb]
			if p.is_land() and p.owner_id == "":
				options.append(nb)
		if options.is_empty():
			frontier.erase(idx)
			continue
		var pick: int = int(options[rng.randi_range(0, options.size() - 1)])
		var picked: Province = provinces[pick]
		picked.owner_id = n.id
		if rng.randf() < 0.28:
			picked.terrain = Province.Terrain.VILLAGE
		n.provinces.append(pick)
		frontier.append(pick)
		return true
	return false

func _nearest_land(nx: float, ny: float) -> int:
	var target := Vector2(nx * float(MapGrid.WIDTH), ny * float(MapGrid.HEIGHT))
	var best := -1
	var best_d := INF
	for pid in provinces.keys():
		var p: Province = provinces[pid]
		if not p.is_land() or p.owner_id != "":
			continue
		var pos := Vector2(float(MapGrid.col_of(pid)), float(MapGrid.row_of(pid)))
		var d := pos.distance_squared_to(target)
		if d < best_d:
			best_d = d
			best = pid
	return best

func _name_provinces(rng: RandomNumberGenerator) -> void:
	var suffix := ["Shimoliy", "Janubiy", "Sharqiy", "G'arbiy", "Markaziy",
		"Yuqori", "Quyi", "Yangi", "Katta", "Kichik"]
	for pid in provinces.keys():
		var p: Province = provinces[pid]
		if p.name != "":
			continue
		if p.owner_id == "":
			p.name = "Egasiz hudud %d" % pid
			continue
		var n: Nation = nations[p.owner_id]
		p.name = "%s %s" % [suffix[rng.randi_range(0, suffix.size() - 1)], n.display_name]

func _seed_armies(rng: RandomNumberGenerator) -> void:
	for nid in nations.keys():
		var n: Nation = nations[nid]
		var points := int(DB.tier_data(n.tier).get("army_points", 10))
		var home_list: Array = n.provinces.duplicate()
		var group_count: int = clampi(points / 8, 1, 5)
		for g in range(group_count):
			var a := ArmyGroup.new()
			a.id = _next_army_id
			_next_army_id += 1
			a.owner_id = n.id
			a.name = "%d-armiya" % (g + 1)
			a.province = int(home_list[rng.randi_range(0, home_list.size() - 1)]) if not home_list.is_empty() else n.capital_province
			var budget := int(points / group_count)
			a.add("inf_rifle", maxi(2, budget))
			a.add("inf_at", maxi(1, budget / 3))
			a.add("inf_recon", 1)
			a.add("veh_tank", maxi(1, budget / 4))
			a.add("veh_apc", maxi(1, budget / 5))
			if n.tier >= 3:
				a.add("veh_spg", 2)
				a.add("air_heli", 1)
			a.add("air_drone", 1)
			n.armies.append(a)

func _seed_relations(rng: RandomNumberGenerator) -> void:
	var ids: Array = nations.keys()
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var na: Nation = nations[a]
			var base := rng.randi_range(-20, 25)
			if _shares_border(str(a), str(b)):
				base -= rng.randi_range(5, 30)     # neighbours rub each other
			if na.tier >= 4:
				base -= 5
			na.set_opinion(str(b), base)

func _shares_border(a: String, b: String) -> bool:
	var na: Nation = nations.get(a, null)
	if na == null:
		return false
	for pid in na.provinces:
		for nb in MapGrid.neighbors(pid):
			if str(provinces[nb].owner_id) == b:
				return true
	return false

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func nation(nid: String) -> Nation:
	return nations.get(nid, null)

func province(pid: int) -> Province:
	return provinces.get(pid, null)

func nation_ids() -> Array:
	return nations.keys()

func border_provinces(nid: String) -> Array:
	var out: Array = []
	var n: Nation = nation(nid)
	if n == null:
		return out
	for pid in n.provinces:
		for nb in MapGrid.neighbors(pid):
			var p: Province = provinces[nb]
			if p.is_land() and p.owner_id != nid:
				out.append(pid)
				break
	return out

func all_armies() -> Array:
	var out: Array = []
	for nid in nations.keys():
		for a in nations[nid].armies:
			out.append(a)
	return out

func armies_in_province(pid: int) -> Array:
	var out: Array = []
	for a in all_armies():
		if a.province == pid:
			out.append(a)
	return out

func push_log(text: String) -> void:
	log_lines.append({"day": day, "text": text})
	if log_lines.size() > 200:
		log_lines.remove_at(0)

func next_battle_id() -> int:
	var v := _next_battle_id
	_next_battle_id += 1
	return v

func next_vote_id() -> String:
	var v := "vote_%d" % _next_vote_id
	_next_vote_id += 1
	return v

func next_army_id() -> int:
	var v := _next_army_id
	_next_army_id += 1
	return v

# ---------------------------------------------------------------------------
# Daily tick — the heartbeat of the global game
# ---------------------------------------------------------------------------

func tick_day() -> void:
	day += 1
	SeasonCycle.advance(self)
	SupplyNet.recalculate(self)
	Economy.collect(self)
	_advance_construction()
	_advance_armies()
	Diplomacy.daily(self)
	WarCouncil.daily(self)
	NationAI.daily(self)
	_resolve_contacts()
	_decay_unrest()
	EventBus.world_tick.emit(day)

func _advance_construction() -> void:
	for pid in provinces.keys():
		var p: Province = provinces[pid]
		if p.construction.is_empty():
			continue
		var job: Dictionary = p.construction[0]
		job["days_left"] = int(job.get("days_left", 1)) - 1
		if int(job["days_left"]) <= 0:
			var bid := str(job.get("building", ""))
			p.development[bid] = p.level_of(bid) + 1
			p.construction.remove_at(0)
			push_log("%s: %s qurib bitkazildi." % [p.name, DB.local_name(DB.building(bid).get("name", bid), bid)])
			EventBus.province_changed.emit(pid)
		else:
			p.construction[0] = job

func _advance_armies() -> void:
	for a in all_armies():
		if a.move_path.is_empty():
			a.entrenched = minf(a.entrenched + 0.08, 1.0)
			continue
		a.entrenched = 0.0
		var speed := 0.34 * clampf(a.supply, 0.3, 1.0)
		var terrain_p: Province = province(int(a.move_path[0]))
		if terrain_p != null:
			match terrain_p.terrain:
				Province.Terrain.MOUNTAIN: speed *= 0.5
				Province.Terrain.FOREST: speed *= 0.75
				Province.Terrain.HILLS: speed *= 0.8
				_: pass
		speed *= SeasonCycle.movement_modifier(self)
		a.move_progress += speed
		if a.move_progress >= 1.0:
			a.move_progress = 0.0
			a.province = int(a.move_path.pop_front())

func _decay_unrest() -> void:
	for pid in provinces.keys():
		var p: Province = provinces[pid]
		if p.unrest > 0.0:
			p.unrest = maxf(0.0, p.unrest - 0.01)

## Where hostile armies now stand on the same province, queue a battle.
func _resolve_contacts() -> void:
	var by_province: Dictionary = {}
	for a in all_armies():
		if not by_province.has(a.province):
			by_province[a.province] = []
		by_province[a.province].append(a)
	for pid in by_province.keys():
		var list: Array = by_province[pid]
		if list.size() < 2:
			# A lone army sitting on enemy ground takes the province.
			var only: ArmyGroup = list[0]
			var p: Province = province(int(pid))
			if p != null and p.is_land() and p.owner_id != only.owner_id:
				var owner_nation: Nation = nation(only.owner_id)
				if owner_nation != null and (p.owner_id == "" or owner_nation.is_at_war_with(p.owner_id)):
					transfer_province(int(pid), only.owner_id)
			continue
		var sides: Dictionary = {}
		for a in list:
			sides[a.owner_id] = true
		var owners: Array = sides.keys()
		for i in range(owners.size()):
			for j in range(i + 1, owners.size()):
				var na: Nation = nation(str(owners[i]))
				if na != null and na.is_at_war_with(str(owners[j])):
					queue_battle(int(pid), str(owners[i]), str(owners[j]))

func queue_battle(pid: int, attacker: String, defender: String) -> Dictionary:
	for b in pending_battles:
		if int(b["province"]) == pid:
			return b
	var p: Province = province(pid)
	var battle := {
		"id": next_battle_id(),
		"province": pid,
		"province_name": p.name if p != null else "?",
		"map": p.battle_map_id() if p != null else "village",
		"attacker": attacker,
		"defender": defender,
		"season": season,
		"weather": weather,
		"day": day,
		"state": "pending",
	}
	pending_battles.append(battle)
	push_log("%s uchun jang boshlanmoqda: %s - %s" % [battle["province_name"], attacker, defender])
	return battle

func transfer_province(pid: int, new_owner: String) -> void:
	var p: Province = province(pid)
	if p == null or p.owner_id == new_owner:
		return
	var old := p.owner_id
	if old != "" and nations.has(old):
		var on: Nation = nations[old]
		on.provinces.erase(pid)
		on.shift_opinion(new_owner, -25)
	p.owner_id = new_owner
	p.unrest = 0.75
	p.fort_level = 0
	if new_owner != "" and nations.has(new_owner):
		var nn: Nation = nations[new_owner]
		if not nn.provinces.has(pid):
			nn.provinces.append(pid)
	push_log("%s hududi %s nazoratiga o'tdi." % [p.name, new_owner])
	EventBus.province_changed.emit(pid)

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var prov: Dictionary = {}
	for pid in provinces.keys():
		prov[str(pid)] = provinces[pid].to_dict()
	var nats: Dictionary = {}
	for nid in nations.keys():
		nats[str(nid)] = nations[nid].to_dict()
	return {
		"seed": seed_value, "day": day, "season": season, "weather": weather,
		"provinces": prov, "nations": nats, "alliances": alliances,
		"votes": votes, "wars": wars, "battles": pending_battles,
		"log": log_lines, "next_army": _next_army_id,
		"next_vote": _next_vote_id, "next_battle": _next_battle_id,
	}

func from_dict(d: Dictionary) -> void:
	seed_value = int(d.get("seed", 0))
	day = int(d.get("day", 0))
	season = str(d.get("season", "spring"))
	weather = str(d.get("weather", "clear"))
	provinces.clear()
	for key in d.get("provinces", {}).keys():
		var p := Province.new()
		p.from_dict(d["provinces"][key])
		provinces[p.id] = p
	nations.clear()
	for key in d.get("nations", {}).keys():
		var n := Nation.new()
		n.from_dict(d["nations"][key])
		nations[n.id] = n
	alliances = d.get("alliances", {})
	votes = d.get("votes", {})
	wars = d.get("wars", [])
	pending_battles = d.get("battles", [])
	log_lines = d.get("log", [])
	_next_army_id = int(d.get("next_army", 1))
	_next_vote_id = int(d.get("next_vote", 1))
	_next_battle_id = int(d.get("next_battle", 1))
