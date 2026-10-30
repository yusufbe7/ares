class_name BattleBridge
extends RefCounted
## The seam between the two halves of the game. It turns a province fight on the
## global map into a 3D battlefield setup, and feeds the battle's outcome back
## into the world: losses, territory, morale and unrest.

## Builds the dictionary the 3D battle scene needs.
static func build_config(world, battle: Dictionary) -> Dictionary:
	var pid := int(battle.get("province", -1))
	var p = world.province(pid)
	var attacker := str(battle.get("attacker", ""))
	var defender := str(battle.get("defender", ""))
	var cfg := {
		"battle_id": int(battle.get("id", 0)),
		"province": pid,
		"province_name": p.name if p != null else "?",
		"map": str(battle.get("map", "village")),
		"season": str(battle.get("season", world.season)),
		"weather": str(battle.get("weather", world.weather)),
		"seed": world.seed_value + pid * 31 + int(battle.get("id", 0)),
		"defense_bonus": p.defense_bonus() if p != null else 1.0,
		"duration": 1800.0,                 # 30 minutes of battle time
		"teams": [
			_team_block(world, attacker, 0, false, p),
			_team_block(world, defender, 1, true, p),
		],
	}
	return cfg

static func _team_block(world, nid: String, team: int, is_defender: bool, p) -> Dictionary:
	var n = world.nation(nid)
	var roster: Dictionary = {}
	var supply := 0.5
	var army_ids: Array = []
	if n != null and p != null:
		for a in n.armies_in(p.id):
			army_ids.append(a.id)
			supply = maxf(supply, a.supply)
			for uid in a.units.keys():
				roster[str(uid)] = int(roster.get(str(uid), 0)) + int(a.units[uid])
	if is_defender and p != null:
		for uid in p.garrison.keys():
			roster[str(uid)] = int(roster.get(str(uid), 0)) + int(p.garrison[uid])
	if roster.is_empty():
		roster = {"inf_rifle": 6, "inf_at": 2}
	var tickets := 0
	for uid in roster.keys():
		tickets += int(roster[uid]) * int(DB.unit(str(uid)).get("men", 1))
	return {
		"team": team,
		"nation": nid,
		"name": n.display_name if n != null else nid,
		"color": n.color.to_html(false) if n != null else "cccccc",
		"is_defender": is_defender,
		"armies": army_ids,
		"roster": roster,
		"tickets": maxi(60, tickets),
		"supply": supply,
		"ai": n == null or n.is_ai or n.online_players().is_empty(),
	}

## Fast resolution, used for fights no human is present for. It runs the same
## shape of combat as the 3D battle — strength, terrain, supply, anti-tank
## balance — just without the simulation.
static func auto_resolve(world, battle: Dictionary) -> Dictionary:
	var pid := int(battle.get("province", -1))
	var p = world.province(pid)
	var attacker := str(battle.get("attacker", ""))
	var defender := str(battle.get("defender", ""))
	var na = world.nation(attacker)
	var nd = world.nation(defender)
	if na == null or nd == null:
		return {}
	var att_power := 0.0
	var def_power := 0.0
	for a in na.armies_in(pid):
		att_power += a.strength()
	for d in nd.armies_in(pid):
		def_power += d.strength()
	def_power = maxf(def_power, 40.0) * (p.defense_bonus() if p != null else 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = world.seed_value + pid * 977 + world.day
	att_power *= rng.randf_range(0.85, 1.15)
	def_power *= rng.randf_range(0.85, 1.15)
	var total: float = att_power + def_power
	var att_share: float = att_power / maxf(total, 1.0)
	var attacker_wins: bool = att_share > 0.55
	var intensity: float = 1.0 - absf(att_share - 0.5) * 1.2    # even fights cost more
	var att_losses: float = clampf((1.0 - att_share) * 0.6 * intensity, 0.05, 0.75)
	var def_losses: float = clampf(att_share * 0.6 * intensity, 0.05, 0.75)
	return {
		"battle_id": int(battle.get("id", 0)),
		"province": pid,
		"winner": attacker if attacker_wins else defender,
		"attacker": attacker,
		"defender": defender,
		"attacker_losses": att_losses,
		"defender_losses": def_losses,
		"auto": true,
	}

## Writes a finished battle back into the world.
static func apply_result(world, result: Dictionary) -> void:
	if result.is_empty():
		return
	var pid := int(result.get("province", -1))
	var attacker := str(result.get("attacker", ""))
	var defender := str(result.get("defender", ""))
	var winner := str(result.get("winner", ""))
	var na = world.nation(attacker)
	var nd = world.nation(defender)
	var killed_a := 0
	var killed_d := 0
	if na != null:
		for a in na.armies_in(pid).duplicate():
			killed_a += a.apply_losses(float(result.get("attacker_losses", 0.2)))
			if a.is_empty():
				na.armies.erase(a)
	if nd != null:
		for d in nd.armies_in(pid).duplicate():
			killed_d += d.apply_losses(float(result.get("defender_losses", 0.2)))
			if d.is_empty():
				nd.armies.erase(d)
	var p = world.province(pid)
	if winner == attacker and p != null:
		world.transfer_province(pid, attacker)
		if na != null:
			na.war_weariness = maxf(0.0, na.war_weariness - 0.03)
		if nd != null:
			nd.war_weariness = minf(1.0, nd.war_weariness + 0.05)
	else:
		# A failed assault pushes the surviving attackers back one province.
		if na != null:
			for a in na.armies_in(pid):
				var retreat := _retreat_target(world, a, attacker)
				if retreat >= 0:
					a.province = retreat
					a.move_path.clear()
			na.war_weariness = minf(1.0, na.war_weariness + 0.05)
	for i in range(world.pending_battles.size() - 1, -1, -1):
		if int(world.pending_battles[i].get("id", -1)) == int(result.get("battle_id", -2)):
			world.pending_battles.remove_at(i)
	world.push_log("%s uchun jang tugadi. G'olib: %s (yo'qotishlar %d / %d)"
		% [p.name if p != null else pid, winner, killed_a, killed_d])
	EventBus.battle_ended.emit(result)

static func _retreat_target(world, army, nid: String) -> int:
	for nb in MapGrid.neighbors(army.province):
		var p = world.province(nb)
		if p != null and p.is_land() and p.owner_id == nid:
			return nb
	return -1

## Resolves every queued battle that no human will play out. Battles with a
## human on either side are left pending for a player to deploy into.
static func resolve_unattended(world) -> Array:
	var played: Array = []
	for battle in world.pending_battles.duplicate():
		var a = world.nation(str(battle.get("attacker", "")))
		var d = world.nation(str(battle.get("defender", "")))
		var human_present: bool = false
		if a != null and not a.online_players().is_empty():
			human_present = true
		if d != null and not d.online_players().is_empty():
			human_present = true
		if human_present:
			continue
		var result := auto_resolve(world, battle)
		apply_result(world, result)
		played.append(result)
	return played
