class_name BattleStats
extends RefCounted
## After-action record. Every kill is attributed to the unit type that made it,
## so the end screen can answer the question players actually ask: which
## vehicle earned its place in this battle?

class TypeRecord extends RefCounted:
	var unit_id: String = ""
	var team: int = 0
	var spawned: int = 0
	var lost: int = 0
	var kills: int = 0
	var damage: float = 0.0

	## One number to rank a unit type by: kills carry it, damage breaks ties,
	## losses count against it.
	func score() -> float:
		return float(kills) * 10.0 + damage * 0.02 - float(lost) * 3.0

var team_names: Array = ["", ""]
var kills: Array = [0, 0]
var losses: Array = [0, 0]
var men_lost: Array = [0, 0]
var vehicles_lost: Array = [0, 0]
var aircraft_lost: Array = [0, 0]
var damage_dealt: Array = [0.0, 0.0]
var points_captured: Array = [0, 0]
var bled_out: Array = [0, 0]
var rescued: Array = [0, 0]
var records: Dictionary = {}        # "team:unit_id" -> TypeRecord
var elapsed: float = 0.0

func setup(cfg: Dictionary) -> void:
	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		team_names[i] = str(teams[i].get("name", "Team %d" % (i + 1)))

func _key(team: int, unit_id: String) -> String:
	return "%d:%s" % [team, unit_id]

func record(team: int, unit_id: String) -> TypeRecord:
	var k := _key(team, unit_id)
	if not records.has(k):
		var r := TypeRecord.new()
		r.unit_id = unit_id
		r.team = team
		records[k] = r
	return records[k]

func on_spawn(team: int, unit_id: String) -> void:
	record(team, unit_id).spawned += 1

func on_damage(attacker_team: int, attacker_unit: String, amount: float) -> void:
	if attacker_team < 0 or attacker_team > 1:
		return
	damage_dealt[attacker_team] += amount
	if attacker_unit != "":
		record(attacker_team, attacker_unit).damage += amount

func on_kill(victim_team: int, victim_unit: String, victim_class: String, men: int,
		killer_team: int, killer_unit: String) -> void:
	if victim_team >= 0 and victim_team <= 1:
		losses[victim_team] += 1
		men_lost[victim_team] += men
		match victim_class:
			"vehicle": vehicles_lost[victim_team] += 1
			"aircraft": aircraft_lost[victim_team] += 1
			_: pass
		record(victim_team, victim_unit).lost += 1
	if killer_team >= 0 and killer_team <= 1 and killer_team != victim_team:
		kills[killer_team] += 1
		if killer_unit != "":
			record(killer_team, killer_unit).kills += 1

## Men nobody reached in time. Worth separating from men killed outright,
## because it is the number that says whether the rescues were working.
func on_bled_out(team: int) -> void:
	if team >= 0 and team <= 1:
		bled_out[team] += 1

func on_rescued(team: int) -> void:
	if team >= 0 and team <= 1:
		rescued[team] += 1

func on_point_captured(team: int) -> void:
	if team >= 0 and team <= 1:
		points_captured[team] += 1

## The stand-out unit type of the battle for one side, by score.
func best_unit(team: int) -> TypeRecord:
	var best: TypeRecord = null
	for k in records.keys():
		var r: TypeRecord = records[k]
		if r.team != team or r.kills == 0:
			continue
		if best == null or r.score() > best.score():
			best = r
	return best

func top_units(team: int, limit: int = 4) -> Array:
	var list: Array = []
	for k in records.keys():
		var r: TypeRecord = records[k]
		if r.team == team and (r.kills > 0 or r.lost > 0):
			list.append(r)
	list.sort_custom(func(a, b): return a.score() > b.score())
	return list.slice(0, limit)

## Flat dictionary for the result screen and for the network.
func to_dict() -> Dictionary:
	var rows: Array = []
	for k in records.keys():
		var r: TypeRecord = records[k]
		rows.append({"team": r.team, "unit": r.unit_id, "spawned": r.spawned,
			"lost": r.lost, "kills": r.kills, "damage": r.damage})
	var best: Array = []
	for team in range(2):
		var b := best_unit(team)
		best.append(b.unit_id if b != null else "")
	return {
		"team_names": team_names, "kills": kills, "losses": losses,
		"men_lost": men_lost, "vehicles_lost": vehicles_lost,
		"aircraft_lost": aircraft_lost, "damage": damage_dealt,
		"points": points_captured, "bled_out": bled_out, "rescued": rescued,
		"elapsed": elapsed,
		"best_unit": best, "records": rows,
	}
