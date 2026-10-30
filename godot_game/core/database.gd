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
var seasons: Dictionary = {}          # id -> season palette
var season_order: Array = []
var victory_modes: Dictionary = {}
var difficulties: Dictionary = {}
var durations: Array = []

var missions: Array = []
var campaign_name: Dictionary = {}

func _ready() -> void:
	_load_countries()
	_load_units()
	_load_buildings()
	_load_maps()
	_load_missions()

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
	for s in d.get("seasons", []):
		seasons[str(s["id"])] = s
		season_order.append(str(s["id"]))
	for v in d.get("victory_modes", []):
		victory_modes[str(v["id"])] = v
	for diff in d.get("difficulties", []):
		difficulties[str(diff["id"])] = diff
	durations = d.get("durations", [])

func _load_missions() -> void:
	var d := _read_json("res://data/missions.json")
	var c: Dictionary = d.get("campaign", {})
	campaign_name = c.get("name", {})
	missions = c.get("missions", [])
	missions.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))

func mission(id: String) -> Dictionary:
	for m in missions:
		if str(m.get("id", "")) == id:
			return m
	return {}

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

## The look of a season: ground, grass, canopy, sky, sun and fog. The whole
## point of keeping it in data is that a map is built once and reskinned four
## times instead of being authored four times.
func season(id: String) -> Dictionary:
	return seasons.get(id, seasons.get("summer", {}))

func season_color(season_id: String, key: String, fallback: Color) -> Color:
	var s: Dictionary = season(season_id)
	if not s.has(key):
		return fallback
	return Color.from_string(str(s[key]), fallback)

func season_ids() -> Array:
	return season_order

func victory_mode(id: String) -> Dictionary:
	return victory_modes.get(id, victory_modes.get("capture", {}))

func difficulty(id: String) -> Dictionary:
	return difficulties.get(id, difficulties.get("normal", {}))

## Geometry counts for a map, e.g. how many houses or hangars it places.
func map_props(map_id: String) -> Dictionary:
	return battle_map(map_id).get("props", {})

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
