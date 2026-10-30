class_name NationAI
extends RefCounted
## Runs every nation that has no human head of state. It plays the same game by
## the same rules: it builds, recruits, moves armies, picks fights it thinks it
## can win and sues for peace when it cannot.

static func daily(world) -> void:
	for nid in world.nations.keys():
		var n = world.nations[nid]
		if not n.is_ai:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = world.seed_value + world.day * 131 + hash(nid)
		_economy(world, n, rng)
		_military(world, n, rng)
		_diplomacy(world, n, rng)

static func _economy(world, n, rng: RandomNumberGenerator) -> void:
	if float(n.resources.get("money", 0.0)) < 600.0:
		return
	if rng.randf() > 0.35:
		return
	var candidates: Array = n.provinces.duplicate()
	if candidates.is_empty():
		return
	var pid := int(candidates[rng.randi_range(0, candidates.size() - 1)])
	var p = world.province(pid)
	if p == null or p.construction.size() >= 1:
		return
	var wish: Array = _build_priority(world, n, p)
	for bid in wish:
		if Economy.start_construction(world, n.id, pid, str(bid)) == "":
			return

static func _build_priority(world, n, p) -> Array:
	var at_war: bool = not n.at_war_with.is_empty()
	var low_fuel: bool = float(n.resources.get("fuel", 0.0)) < 150.0
	var low_ammo: bool = float(n.resources.get("ammo", 0.0)) < 150.0
	var out: Array = []
	if at_war and p.supply < 0.5:
		out.append("railway")
	if low_ammo:
		out.append("factory")
	if low_fuel:
		out.append("refinery")
	if p.is_capital:
		out.append("power_plant")
	out.append_array(["military_base", "factory", "farm", "mine", "radar", "airport", "fortline"])
	return out

static func _military(world, n, rng: RandomNumberGenerator) -> void:
	# Keep the stacks topped up.
	if not n.armies.is_empty() and float(n.resources.get("money", 0.0)) > 400.0 and rng.randf() < 0.5:
		var a = n.armies[rng.randi_range(0, n.armies.size() - 1)]
		var pick := "inf_rifle"
		if a.anti_tank_power() < 3.0:
			pick = "inf_at"
		elif a.count("veh_tank") < 3 and n.tier >= 2:
			pick = "veh_tank"
		Economy.recruit(world, n.id, a.id, pick, 1)

	for a in n.armies:
		if not a.move_path.is_empty():
			continue
		if n.at_war_with.is_empty():
			_garrison_move(world, n, a, rng)
		else:
			_offensive_move(world, n, a, rng)

static func _garrison_move(world, n, a, rng: RandomNumberGenerator) -> void:
	# In peacetime, drift toward the weakest-supplied border province.
	var borders: Array = world.border_provinces(n.id)
	if borders.is_empty() or rng.randf() > 0.15:
		return
	var target := int(borders[rng.randi_range(0, borders.size() - 1)])
	if target != a.province:
		a.move_path = path_between(world, a.province, target, n.id, true)

static func _offensive_move(world, n, a, rng: RandomNumberGenerator) -> void:
	# Find the nearest enemy province next to our own ground and take it.
	var best := -1
	var best_score := -INF
	for pid in n.provinces:
		for nb in MapGrid.neighbors(int(pid)):
			var p = world.province(nb)
			if p == null or not p.is_land():
				continue
			if p.owner_id == "" or not n.is_at_war_with(p.owner_id):
				continue
			var defenders := 0.0
			for d in world.armies_in_province(nb):
				defenders += d.strength()
			var score: float = a.strength() - defenders * p.defense_bonus()
			score -= float(MapGrid.distance(a.province, nb)) * 20.0
			if score > best_score:
				best_score = score
				best = nb
	if best >= 0 and best_score > 0.0:
		a.move_path = path_between(world, a.province, best, n.id, false)
	elif a.supply < 0.35:
		# Falling apart out there — go home.
		if not n.provinces.is_empty():
			a.move_path = path_between(world, a.province, int(n.provinces[0]), n.id, true)

static func _diplomacy(world, n, rng: RandomNumberGenerator) -> void:
	# Sue for peace when the war has gone badly for long enough.
	if not n.at_war_with.is_empty() and n.war_weariness > 0.45 and rng.randf() < 0.2:
		var target := str(n.at_war_with[0])
		var terms := {"winner": target, "provinces": [], "reparations": 200.0, "trade": true}
		if Diplomacy.peace_acceptance(world, n.id, target, terms) > 0.5:
			Diplomacy.make_peace(world, n.id, target, terms)
			return
	# Join an alliance when isolated.
	if n.alliance_id == "" and rng.randf() < 0.06:
		for aid in world.alliances.keys():
			var pact: Dictionary = world.alliances[aid]
			var leader = world.nation(str(pact.get("leader", "")))
			if leader != null and n.opinion_of(leader.id) > 35:
				Diplomacy.join_alliance(world, n.id, str(aid))
				return
		if rng.randf() < 0.3:
			Diplomacy.create_alliance(world, n.id, "")
			return
	# Pick a fight with a weak, disliked neighbour.
	if rng.randf() > 0.04:
		return
	if n.war_weariness > 0.3 or n.at_war_with.size() >= 2:
		return
	var targets: Array = []
	for pid in n.provinces:
		for nb in MapGrid.neighbors(int(pid)):
			var p = world.province(nb)
			if p != null and p.is_land() and p.owner_id != "" and p.owner_id != n.id:
				if not targets.has(p.owner_id):
					targets.append(p.owner_id)
	for t in targets:
		var other = world.nation(str(t))
		if other == null:
			continue
		if not other.is_ai and other.online_players().is_empty():
			continue   # do not jump an undefended human nation while nobody is on
		if n.opinion_of(str(t)) > -25:
			continue
		if n.total_strength() < other.total_strength() * 1.35:
			continue
		if Diplomacy.declare_war(world, n.id, str(t), "Hududiy da'vo") == "":
			return

# ---------------------------------------------------------------------------
# Pathfinding over the province grid (A* on hex cells)
# ---------------------------------------------------------------------------

static func path_between(world, from_id: int, to_id: int, mover: String, friendly_only: bool) -> Array:
	if from_id == to_id:
		return []
	var open: Array = [from_id]
	var came: Dictionary = {}
	var g: Dictionary = {from_id: 0.0}
	var f: Dictionary = {from_id: float(MapGrid.distance(from_id, to_id))}
	var guard := 0
	while not open.is_empty() and guard < 20000:
		guard += 1
		var best_i := 0
		for i in range(open.size()):
			if float(f.get(open[i], INF)) < float(f.get(open[best_i], INF)):
				best_i = i
		var cur: int = int(open[best_i])
		if cur == to_id:
			return _rebuild(came, cur)
		open.remove_at(best_i)
		for nb in MapGrid.neighbors(cur):
			var p = world.province(nb)
			if p == null or not p.is_land():
				continue
			if friendly_only and p.owner_id != mover and nb != to_id:
				continue
			var n = world.nation(mover)
			var passable: bool = p.owner_id == mover or p.owner_id == "" or nb == to_id
			if not passable and n != null and n.is_at_war_with(p.owner_id):
				passable = true
			if not passable:
				continue
			var step := 1.0
			match p.terrain:
				Province.Terrain.MOUNTAIN: step = 3.0
				Province.Terrain.FOREST: step = 2.0
				Province.Terrain.DESERT: step = 1.5
				_: step = 1.0
			var tentative: float = float(g.get(cur, INF)) + step
			if tentative < float(g.get(nb, INF)):
				came[nb] = cur
				g[nb] = tentative
				f[nb] = tentative + float(MapGrid.distance(nb, to_id))
				if not open.has(nb):
					open.append(nb)
	return []

static func _rebuild(came: Dictionary, cur: int) -> Array:
	var path: Array = [cur]
	while came.has(cur):
		cur = int(came[cur])
		path.push_front(cur)
	if path.size() > 0:
		path.remove_at(0)      # drop the starting cell
	return path
