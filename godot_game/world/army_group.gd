class_name ArmyGroup
extends RefCounted
## A stack of units standing in one province. Armies move province to province
## on the global map; when two hostile armies meet, a 3D battle is created.

var id: int = 0
var name: String = "Army"
var owner_id: String = ""
var province: int = -1
var units: Dictionary = {}        # unit_id -> count
var morale: float = 1.0           # 0..1
var supply: float = 1.0           # 0..1, set by Supply each day
var move_path: Array = []         # queued province ids
var move_progress: float = 0.0    # 0..1 towards the next province
var entrenched: float = 0.0       # 0..1, grows while standing still

func men() -> int:
	var total := 0
	for uid in units.keys():
		var u: Dictionary = DB.unit(str(uid))
		total += int(u.get("men", 1)) * int(units[uid])
	return total

func count(unit_id: String) -> int:
	return int(units.get(unit_id, 0))

func add(unit_id: String, n: int) -> void:
	units[unit_id] = count(unit_id) + n

func remove(unit_id: String, n: int) -> void:
	var left := count(unit_id) - n
	if left <= 0:
		units.erase(unit_id)
	else:
		units[unit_id] = left

func is_empty() -> bool:
	return units.is_empty()

## Raw combat power, before terrain and fortification modifiers.
func strength() -> float:
	var s := 0.0
	for uid in units.keys():
		var u: Dictionary = DB.unit(str(uid))
		var n := float(units[uid])
		var dps := float(u.get("damage", 1)) * maxf(float(u.get("rpm", 60)), 1.0) / 60.0
		s += n * (dps * 0.5 + float(u.get("hp", 50)) * 0.05 + float(u.get("armor", 0)) * 6.0)
	return s * clampf(morale, 0.3, 1.2) * clampf(supply, 0.2, 1.0)

func anti_tank_power() -> float:
	var s := 0.0
	for uid in units.keys():
		var u: Dictionary = DB.unit(str(uid))
		s += float(units[uid]) * float(u.get("at", 0.0))
	return s

func vision() -> float:
	var best := 0.0
	for uid in units.keys():
		best = maxf(best, float(DB.unit(str(uid)).get("vision", 0)))
	return best

func daily_upkeep() -> Dictionary:
	var out := {}
	for uid in units.keys():
		var u: Dictionary = DB.unit(str(uid))
		var n := float(units[uid])
		for key in u.get("upkeep", {}).keys():
			var k := str(key)
			out[k] = float(out.get(k, 0.0)) + float(u["upkeep"][key]) * n
	return out

## Applies battle losses as a fraction, rounding so that a wiped stack is gone.
func apply_losses(fraction: float) -> int:
	var killed := 0
	var f := clampf(fraction, 0.0, 1.0)
	for uid in units.keys().duplicate():
		var n := int(units[uid])
		var lost := int(round(float(n) * f))
		if f >= 0.999:
			lost = n
		if lost > 0:
			killed += lost * int(DB.unit(str(uid)).get("men", 1))
			remove(str(uid), lost)
	morale = clampf(morale - f * 0.8, 0.05, 1.0)
	return killed

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "owner": owner_id, "province": province,
		"units": units, "morale": morale, "supply": supply,
		"path": move_path, "progress": move_progress, "entrenched": entrenched}

func from_dict(d: Dictionary) -> void:
	id = int(d.get("id", 0))
	name = str(d.get("name", "Army"))
	owner_id = str(d.get("owner", ""))
	province = int(d.get("province", -1))
	units = d.get("units", {})
	morale = float(d.get("morale", 1.0))
	supply = float(d.get("supply", 1.0))
	move_path = d.get("path", [])
	move_progress = float(d.get("progress", 0.0))
	entrenched = float(d.get("entrenched", 0.0))
