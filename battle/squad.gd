class_name Squad
extends RefCounted
## A control group. The design rule for this game is that the player never
## drives the whole army with one click: you form groups — infantry, armour,
## guns, recon, reserve — and give each one its own job.

var index: int = 0
var label: String = ""
var team: int = 0
var units: Array = []

func add(u: BattleUnit) -> void:
	if u == null or units.has(u):
		return
	if u.squad_index >= 0 and u.squad_index != index:
		pass      # a unit belongs to exactly one group; the new one wins
	units.append(u)
	u.squad_index = index

func remove(u: BattleUnit) -> void:
	units.erase(u)
	if u != null and u.squad_index == index:
		u.squad_index = -1

func alive_units() -> Array:
	var out: Array = []
	for u in units:
		if is_instance_valid(u) and u.is_alive():
			out.append(u)
	units = out
	return out

func size() -> int:
	return alive_units().size()

func center() -> Vector3:
	var list := alive_units()
	if list.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for u in list:
		sum += u.global_position
	return sum / float(list.size())

## Spreads the group out around the destination instead of stacking everyone on
## one point, with vehicles behind the infantry line.
func order_move(target: Vector3, terrain: BattleTerrain) -> void:
	var list := alive_units()
	if list.is_empty():
		return
	var forward := (target - center())
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0, forward.x)
	var per_row := maxi(1, int(ceil(sqrt(float(list.size())))))
	for i in range(list.size()):
		var u: BattleUnit = list[i]
		var row := i / per_row
		var col := i % per_row
		var spacing := 4.5 if u.unit_class() == "infantry" else 9.0
		var offset: Vector3 = right * (float(col) - float(per_row - 1) * 0.5) * spacing
		offset -= forward * float(row) * spacing
		if u.unit_class() == "vehicle":
			offset -= forward * 10.0
		var dest: Vector3 = target + offset
		if terrain != null:
			dest = terrain.clamp_to_map(dest)
			dest.y = terrain.height_at(dest.x, dest.z)
		u.order_move(dest)

func order_attack(target: BattleUnit) -> void:
	for u in alive_units():
		u.order_attack(target)

func order_attack_building(building) -> void:
	for u in alive_units():
		u.order_attack_building(building)

func order_capture(point) -> void:
	for u in alive_units():
		u.order_capture(point)

func order_hold() -> void:
	for u in alive_units():
		u.order_hold()

func order_stance(stance: int) -> void:
	for u in alive_units():
		u.order_stance(stance)

## A readable name for the HUD, taken from what is actually in the group.
func auto_label() -> String:
	if label != "":
		return label
	var counts: Dictionary = {}
	for u in alive_units():
		var role := str(u.data.get("role", "line"))
		counts[role] = int(counts.get(role, 0)) + 1
	var best := ""
	var best_n := 0
	for r in counts.keys():
		if int(counts[r]) > best_n:
			best_n = int(counts[r])
			best = str(r)
	match best:
		"line": return "Piyodalar"
		"armor": return "Tanklar"
		"artillery": return "Artilleriya"
		"recon": return "Razvedka"
		"anti_tank": return "Tankka qarshi"
		"anti_air": return "Zenit"
		"gunship": return "Aviatsiya"
		"transport": return "Transport"
		"suppression": return "Pulemyot"
	return "Guruh %d" % (index + 1)
