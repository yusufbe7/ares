class_name Economy
extends RefCounted
## Daily income, upkeep, recruitment pool and war weariness.

static func collect(world) -> void:
	for nid in world.nations.keys():
		var n = world.nations[nid]
		var income := income_of(world, str(nid))
		var upkeep := upkeep_of(world, str(nid))
		for k in income.keys():
			n.resources[str(k)] = float(n.resources.get(str(k), 0.0)) + float(income[k])
		for k in upkeep.keys():
			var have: float = float(n.resources.get(str(k), 0.0))
			n.resources[str(k)] = maxf(0.0, have - float(upkeep[k]))
		# Manpower regrows from population, slowed by war weariness.
		var pop := 0
		for pid in n.provinces:
			var p = world.province(int(pid))
			if p != null:
				pop += p.population
		var growth: float = float(pop) * 0.00012 * (1.0 - n.war_weariness * 0.7)
		n.resources["manpower"] = float(n.resources.get("manpower", 0.0)) + growth
		# War weariness climbs while at war and heals in peace.
		if n.at_war_with.is_empty():
			n.war_weariness = maxf(0.0, n.war_weariness - 0.004)
		else:
			n.war_weariness = minf(1.0, n.war_weariness + 0.0025 * float(n.at_war_with.size()))
		EventBus.treasury_changed.emit(str(nid), n.resources)

static func income_of(world, nid: String) -> Dictionary:
	var out: Dictionary = {}
	var n = world.nation(nid)
	if n == null:
		return out
	for pid in n.provinces:
		var p = world.province(int(pid))
		if p == null:
			continue
		var y: Dictionary = p.daily_yield()
		for k in y.keys():
			out[str(k)] = float(out.get(str(k), 0.0)) + float(y[k])
	# Alliance members trade with each other at a small bonus.
	if n.alliance_id != "":
		var members: Array = world.alliances.get(n.alliance_id, {}).get("members", [])
		var bonus: float = 1.0 + 0.02 * float(maxi(0, members.size() - 1))
		out["money"] = float(out.get("money", 0.0)) * bonus
	out.erase("recruit")
	return out

static func upkeep_of(world, nid: String) -> Dictionary:
	var out: Dictionary = {}
	var n = world.nation(nid)
	if n == null:
		return out
	for a in n.armies:
		var u: Dictionary = a.daily_upkeep()
		for k in u.keys():
			out[str(k)] = float(out.get(str(k), 0.0)) + float(u[k])
	# Buildings burn power; a shortfall is paid in money instead.
	return out

## Recruitment capacity per day across the whole nation.
static func recruit_capacity(world, nid: String) -> float:
	var n = world.nation(nid)
	if n == null:
		return 0.0
	var cap := 2.0
	for pid in n.provinces:
		var p = world.province(int(pid))
		if p != null:
			cap += float(p.level_of("military_base")) * 6.0
			cap += float(p.level_of("factory")) * 2.0
	return cap

static func net_balance(world, nid: String) -> Dictionary:
	var inc := income_of(world, nid)
	var up := upkeep_of(world, nid)
	var out: Dictionary = {}
	for k in inc.keys():
		out[str(k)] = float(inc[k]) - float(up.get(str(k), 0.0))
	for k in up.keys():
		if not out.has(str(k)):
			out[str(k)] = -float(up[k])
	return out

## Starts a building job in a province. Returns an error string, "" on success.
static func start_construction(world, nid: String, pid: int, building_id: String) -> String:
	var n = world.nation(nid)
	var p = world.province(pid)
	if n == null or p == null:
		return "Noto'g'ri hudud."
	if p.owner_id != nid:
		return "Bu hudud sizga tegishli emas."
	var b: Dictionary = DB.building(building_id)
	if b.is_empty():
		return "Bunday bino yo'q."
	var allowed: Array = b.get("terrain", ["any"])
	if not allowed.has("any") and not allowed.has(Province.terrain_name(p.terrain)):
		return "Bu yer turi bu binoga mos emas."
	if p.level_of(building_id) >= int(b.get("max_level", 1)):
		return "Daraja eng yuqori."
	if p.construction.size() >= 2:
		return "Bu hududda navbat to'lgan."
	var cost: Dictionary = b.get("cost", {})
	if not n.can_afford(cost):
		return "Mablag' yetarli emas."
	n.pay(cost)
	p.construction.append({"building": building_id, "days_left": int(b.get("build_days", 5))})
	EventBus.province_changed.emit(pid)
	return ""

## Adds units to an army, paying for them. Returns "" on success.
static func recruit(world, nid: String, army_id: int, unit_id: String, count: int) -> String:
	var n = world.nation(nid)
	if n == null:
		return "Davlat topilmadi."
	var a = n.army_by_id(army_id)
	if a == null:
		return "Armiya topilmadi."
	var u: Dictionary = DB.unit(unit_id)
	if u.is_empty():
		return "Bunday bo'linma yo'q."
	var cost: Dictionary = {}
	for k in u.get("cost", {}).keys():
		cost[str(k)] = float(u["cost"][k]) * float(count)
	if not n.can_afford(cost):
		return "Mablag' yoki jonli kuch yetarli emas."
	n.pay(cost)
	a.add(unit_id, count)
	return ""
