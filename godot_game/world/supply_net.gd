class_name SupplyNet
extends RefCounted
## Supply lines. A province is supplied by a chain of friendly provinces back to
## a capital, a military base or an airbase. Cut the chain and the army at the
## end of it loses fuel, ammo and morale — which is exactly how a front
## collapses.

const BASE_RANGE := 5

static func recalculate(world) -> void:
	for nid in world.nations.keys():
		_recalculate_for(world, str(nid))
	_apply_to_armies(world)

static func _recalculate_for(world, nid: String) -> void:
	var n = world.nation(nid)
	if n == null:
		return
	# Breadth-first from every supply source, carrying a remaining range value.
	var remaining: Dictionary = {}     # province id -> best remaining range
	var queue: Array = []
	for pid in n.provinces:
		var p = world.province(int(pid))
		if p == null:
			continue
		var is_source: bool = p.is_capital or p.level_of("military_base") > 0 or p.level_of("airport") > 0
		if is_source:
			var r: int = BASE_RANGE + p.supply_range_bonus() + p.level_of("military_base")
			remaining[int(pid)] = r
			queue.append(int(pid))
	while not queue.is_empty():
		var cur: int = int(queue.pop_front())
		var left: int = int(remaining[cur])
		if left <= 0:
			continue
		for nb in MapGrid.neighbors(cur):
			var np = world.province(nb)
			if np == null or not np.is_land():
				continue
			if np.owner_id != nid:
				continue
			var cost := 1
			match np.terrain:
				Province.Terrain.MOUNTAIN: cost = 3
				Province.Terrain.FOREST: cost = 2
				Province.Terrain.DESERT: cost = 2
				_: cost = 1
			cost = maxi(1, cost - np.level_of("railway"))
			var next_left: int = left - cost
			if next_left > int(remaining.get(nb, -999)):
				remaining[nb] = next_left
				queue.append(nb)
	# Write the result back, with enemy pressure on the border taken off the top.
	for pid in n.provinces:
		var p = world.province(int(pid))
		if p == null:
			continue
		var left: int = int(remaining.get(int(pid), -1))
		var value: float = 0.15
		if left >= 0:
			value = clampf(0.45 + float(left) / float(BASE_RANGE * 2), 0.15, 1.0)
		var hostile := 0
		for nb in MapGrid.neighbors(int(pid)):
			var np = world.province(nb)
			if np != null and np.is_land() and np.owner_id != "" and np.owner_id != nid:
				if n.is_at_war_with(np.owner_id):
					hostile += 1
		value -= float(hostile) * 0.07
		p.supply = clampf(value, 0.1, 1.0)

static func _apply_to_armies(world) -> void:
	for a in world.all_armies():
		var p = world.province(a.province)
		if p == null:
			a.supply = 0.3
			continue
		var base: float = p.supply if p.owner_id == a.owner_id else _foreign_supply(world, a, p)
		var n = world.nation(a.owner_id)
		if n != null:
			var need: Dictionary = a.daily_upkeep()
			var fuel_need: float = float(need.get("fuel", 0.0))
			var ammo_need: float = float(need.get("ammo", 0.0))
			if fuel_need > 0.0 and float(n.resources.get("fuel", 0.0)) < fuel_need:
				base *= 0.6
			if ammo_need > 0.0 and float(n.resources.get("ammo", 0.0)) < ammo_need:
				base *= 0.6
		a.supply = clampf(base, 0.1, 1.0)
		# Morale follows supply slowly, in both directions.
		if a.supply < 0.4:
			a.morale = maxf(0.1, a.morale - 0.04)
		elif a.supply > 0.7:
			a.morale = minf(1.0, a.morale + 0.02)

## An army standing abroad is supplied through the nearest friendly province.
static func _foreign_supply(world, army, p) -> float:
	var best := 0.0
	for nb in MapGrid.neighbors(p.id):
		var np = world.province(nb)
		if np != null and np.owner_id == army.owner_id:
			best = maxf(best, np.supply * 0.8)
	if best <= 0.0:
		best = 0.25
	return best

## Human-readable status for the UI.
static func status_text(value: float) -> String:
	if value > 0.8:
		return "To'liq ta'minot"
	if value > 0.55:
		return "Yetarli"
	if value > 0.3:
		return "Kam"
	return "Uzilgan"
