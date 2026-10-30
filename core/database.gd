extends Node
## Static game data loaded once from res://data/*.json.

var units: Dictionary = {}          # id -> Dictionary
var factions: Dictionary = {}       # id -> {name, color, desc}
var faction_order: Array = []
var fortifications: Dictionary = {}
var battle_maps: Dictionary = {}
var weather_table: Dictionary = {}
var seasons: Dictionary = {}          # id -> season palette
var season_order: Array = []
var victory_modes: Dictionary = {}
var difficulties: Dictionary = {}
var durations: Array = []

func _ready() -> void:
	_load_units()
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

func _load_units() -> void:
	var d := _read_json("res://data/units.json")
	for u in d.get("units", []):
		units[str(u["id"])] = u
	for f in d.get("fortifications", []):
		fortifications[str(f["id"])] = f
	for fa in d.get("factions", []):
		factions[str(fa["id"])] = fa
		faction_order.append(str(fa["id"]))

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

# --- helpers ----------------------------------------------------------------

func unit(id: String) -> Dictionary:
	return units.get(id, {})

func faction(id: String) -> Dictionary:
	return factions.get(id, factions.get("army", {}))

func faction_ids() -> Array:
	return faction_order

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

