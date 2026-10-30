class_name Province
extends RefCounted
## One cell of the global map: the unit of ownership, economy and invasion.

enum Terrain { OCEAN, PLAINS, HILLS, MOUNTAIN, DESERT, FOREST, VILLAGE, URBAN }

var id: int = -1
var name: String = ""
var terrain: int = Terrain.PLAINS
var owner_id: String = ""            # "" = unowned / ocean
var is_capital: bool = false
var population: int = 0
var fort_level: int = 0
var supply: float = 1.0              # 0..1, drives army strength in battle
var unrest: float = 0.0              # 0..1, raised by recent conquest
var development: Dictionary = {}     # building_id -> level
var construction: Array = []         # [{building, days_left}]
var garrison: Dictionary = {}        # unit_id -> count

static func terrain_name(t: int) -> String:
	match t:
		Terrain.OCEAN: return "ocean"
		Terrain.PLAINS: return "plains"
		Terrain.HILLS: return "hills"
		Terrain.MOUNTAIN: return "mountain"
		Terrain.DESERT: return "desert"
		Terrain.FOREST: return "forest"
		Terrain.VILLAGE: return "village"
		Terrain.URBAN: return "urban"
	return "plains"

## Which 3D battle map this province fights on.
func battle_map_id() -> String:
	match terrain:
		Terrain.FOREST, Terrain.MOUNTAIN, Terrain.HILLS:
			return "forest"
		Terrain.DESERT:
			return "desert"
		_:
			return "village"

func is_land() -> bool:
	return terrain != Terrain.OCEAN

func level_of(building_id: String) -> int:
	return int(development.get(building_id, 0))

## Resource output of this province per day, including terrain base yield and
## every finished building. Low supply and high unrest cut the output.
func daily_yield() -> Dictionary:
	var out := {"money": 0.0, "food": 0.0, "fuel": 0.0, "steel": 0.0,
		"ammo": 0.0, "power": 0.0, "production": 0.0, "intel": 0.0, "recruit": 0.0}
	if not is_land():
		return out
	out["money"] = 2.0 + float(population) / 40000.0
	match terrain:
		Terrain.PLAINS: out["food"] += 3.0
		Terrain.HILLS: out["steel"] += 1.5
		Terrain.MOUNTAIN: out["steel"] += 2.5
		Terrain.DESERT: out["fuel"] += 2.0
		Terrain.FOREST: out["food"] += 1.0
		Terrain.VILLAGE: out["food"] += 2.0
		Terrain.URBAN:
			out["money"] += 6.0
			out["production"] += 3.0
	for bid in development.keys():
		var b: Dictionary = DB.building(str(bid))
		var lvl := int(development[bid])
		for key in b.get("yield", {}).keys():
			var k := str(key)
			if not out.has(k):
				out[k] = 0.0
			out[k] = float(out[k]) + float(b["yield"][key]) * float(lvl)
	var efficiency: float = clampf(supply, 0.25, 1.0) * (1.0 - unrest * 0.6)
	for k in out.keys():
		out[k] = float(out[k]) * efficiency
	return out

## Defensive multiplier applied to the defender when this province is attacked.
func defense_bonus() -> float:
	var terrain_bonus := 1.0
	match terrain:
		Terrain.MOUNTAIN: terrain_bonus = 1.45
		Terrain.HILLS: terrain_bonus = 1.25
		Terrain.FOREST: terrain_bonus = 1.2
		Terrain.URBAN: terrain_bonus = 1.35
		Terrain.VILLAGE: terrain_bonus = 1.15
		Terrain.DESERT: terrain_bonus = 0.9
		_: terrain_bonus = 1.0
	return terrain_bonus + float(fort_level) * 0.12 + float(level_of("fortline")) * 0.1

func supply_range_bonus() -> int:
	return level_of("railway") + level_of("airport")

func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "terrain": terrain, "owner": owner_id,
		"capital": is_capital, "pop": population, "fort": fort_level,
		"supply": supply, "unrest": unrest, "dev": development,
		"construction": construction, "garrison": garrison,
	}

func from_dict(d: Dictionary) -> void:
	id = int(d.get("id", -1))
	name = str(d.get("name", ""))
	terrain = int(d.get("terrain", Terrain.PLAINS))
	owner_id = str(d.get("owner", ""))
	is_capital = bool(d.get("capital", false))
	population = int(d.get("pop", 0))
	fort_level = int(d.get("fort", 0))
	supply = float(d.get("supply", 1.0))
	unrest = float(d.get("unrest", 0.0))
	development = d.get("dev", {})
	construction = d.get("construction", [])
	garrison = d.get("garrison", {})
