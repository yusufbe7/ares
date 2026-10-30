extends Node
## Static game data loaded once from res://data/*.json.

var nations_raw: Array = []
var tiers: Dictionary = {}
var units: Dictionary = {}          # id -> Dictionary
var fortifications: Dictionary = {}
var buildings: Dictionary = {}
var resource_names: Array = []
var battle_maps: Dictionary = {}
var weather_table: Dictionary = {}
var seasons: Array = []

func _ready() -> void:
	_load_countries()
	_load_units()
	_load_buildings()
	_load_maps()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Data file missing: %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Data file is not a JSON object: %s" % path)
		return {}
	return parsed

func _load_countries() -> void:
	var d := _read_json("res://data/countries.json")
	nations_raw = d.get("nations", [])
	tiers = d.get("tiers", {})

func _load_units() -> void:
	var d := _read_json("res://data/units.json")
	for u in d.get("units", []):
		units[str(u["id"])] = u
	for f in d.get("fortifications", []):
		fortifications[str(f["id"])] = f

func _load_buildings() -> void:
	var d := _read_json("res://data/buildings.json")
	for b in d.get("buildings", []):
		buildings[str(b["id"])] = b
	resource_names = d.get("resources", [])

func _load_maps() -> void:
	var d := _read_json("res://data/battle_maps.json")
	for m in d.get("maps", []):
		battle_maps[str(m["id"])] = m
	for w in d.get("weather", []):
		weather_table[str(w["id"])] = w
	seasons = d.get("seasons", [])

# --- helpers ----------------------------------------------------------------

func unit(id: String) -> Dictionary:
	return units.get(id, {})

func building(id: String) -> Dictionary:
	return buildings.get(id, {})

func battle_map(id: String) -> Dictionary:
	if battle_maps.has(id):
		return battle_maps[id]
	return battle_maps.get("village", {})

func weather(id: String) -> Dictionary:
	return weather_table.get(id, weather_table.get("clear", {}))

func tier_data(tier: int) -> Dictionary:
	return tiers.get(str(tier), tiers.get("1", {}))

## Returns a localized name out of a {"uz": .., "en": .., "ru": ..} block.
func local_name(block: Variant, fallback: String = "?") -> String:
	if typeof(block) == TYPE_STRING:
		return str(block)
	if typeof(block) != TYPE_DICTIONARY:
		return fallback
	var d: Dictionary = block
	if d.has(Settings.language):
		return str(d[Settings.language])
	if d.has("en"):
		return str(d["en"])
	return fallback

func unit_ids_for_role(role: String) -> Array:
	var out: Array = []
	for id in units.keys():
		if str(units[id].get("role", "")) == role:
			out.append(id)
	return out
