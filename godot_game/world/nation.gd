class_name Nation
extends RefCounted
## A playable country. Several human players may share one nation; each of them
## holds a role, and the national council (see WarCouncil) gates the decisions
## that bind everybody.

var id: String = ""
var display_name: String = ""
var color: Color = Color.WHITE
var capital_name: String = ""
var capital_province: int = -1
var tier: int = 1
var doctrine: String = "combined_arms"
var is_ai: bool = true

var resources: Dictionary = {
	"money": 0.0, "manpower": 0.0, "food": 0.0, "fuel": 0.0,
	"steel": 0.0, "ammo": 0.0, "power": 0.0, "production": 0.0, "intel": 0.0,
}
var provinces: Array[int] = []
var armies: Array = []                # ArmyGroup
var relations: Dictionary = {}        # nation_id -> -100..100
var at_war_with: Array = []           # nation_id
var truce_until: Dictionary = {}      # nation_id -> world day
var alliance_id: String = ""
var players: Array = []               # [{peer, name, role}]
var war_weariness: float = 0.0        # 0..1, rises during long wars
var intel_on: Dictionary = {}         # nation_id -> 0..1 how much we can see

func opinion_of(other: String) -> int:
	return int(relations.get(other, 0))

func set_opinion(other: String, value: int) -> void:
	relations[other] = clampi(value, -100, 100)

func shift_opinion(other: String, delta: int) -> void:
	set_opinion(other, opinion_of(other) + delta)

func is_at_war_with(other: String) -> bool:
	return at_war_with.has(other)

func has_truce_with(other: String, day: int) -> bool:
	return int(truce_until.get(other, -1)) > day

func human_players() -> Array:
	var out: Array = []
	for p in players:
		if not bool(p.get("ai", false)):
			out.append(p)
	return out

func online_players() -> Array:
	var out: Array = []
	for p in players:
		if bool(p.get("online", false)):
			out.append(p)
	return out

func player_role(peer: int) -> int:
	for p in players:
		if int(p.get("peer", -1)) == peer:
			return int(p.get("role", GameState.Role.OBSERVER))
	return GameState.Role.OBSERVER

func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if float(resources.get(str(k), 0.0)) < float(cost[k]):
			return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost.keys():
		resources[str(k)] = float(resources.get(str(k), 0.0)) - float(cost[k])
	return true

func gain(income: Dictionary) -> void:
	for k in income.keys():
		resources[str(k)] = float(resources.get(str(k), 0.0)) + float(income[k])

func army_by_id(aid: int) -> ArmyGroup:
	for a in armies:
		if a.id == aid:
			return a
	return null

func armies_in(province_id: int) -> Array:
	var out: Array = []
	for a in armies:
		if a.province == province_id:
			out.append(a)
	return out

func total_strength() -> float:
	var s := 0.0
	for a in armies:
		s += a.strength()
	return s

func to_dict() -> Dictionary:
	var army_list: Array = []
	for a in armies:
		army_list.append(a.to_dict())
	return {
		"id": id, "name": display_name, "color": color.to_html(false),
		"capital_name": capital_name, "capital": capital_province,
		"tier": tier, "doctrine": doctrine, "ai": is_ai,
		"res": resources, "provinces": provinces, "armies": army_list,
		"relations": relations, "wars": at_war_with, "truce": truce_until,
		"alliance": alliance_id, "players": players,
		"weariness": war_weariness, "intel": intel_on,
	}

func from_dict(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	display_name = str(d.get("name", id))
	color = Color.from_string("#" + str(d.get("color", "ffffff")), Color.WHITE)
	capital_name = str(d.get("capital_name", ""))
	capital_province = int(d.get("capital", -1))
	tier = int(d.get("tier", 1))
	doctrine = str(d.get("doctrine", "combined_arms"))
	is_ai = bool(d.get("ai", true))
	resources = d.get("res", resources)
	provinces.clear()
	for p in d.get("provinces", []):
		provinces.append(int(p))
	armies.clear()
	for a in d.get("armies", []):
		var g := ArmyGroup.new()
		g.from_dict(a)
		armies.append(g)
	relations = d.get("relations", {})
	at_war_with = d.get("wars", [])
	truce_until = d.get("truce", {})
	alliance_id = str(d.get("alliance", ""))
	players = d.get("players", [])
	war_weariness = float(d.get("weariness", 0.0))
	intel_on = d.get("intel", {})
