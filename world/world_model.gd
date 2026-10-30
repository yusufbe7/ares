class_name WorldModel
extends RefCounted
## The global picture: which bloc holds which country, how much of the world's
## land that adds up to, and where the fighting is.
##
## Geography comes from data/world_map.json, simplified from Natural Earth
## 1:110m, which is public domain. Coordinates there are lon/lat scaled by ten.

class Country extends RefCounted:
	var id: String = ""
	var name: String = ""
	var continent: String = ""
	var population: int = 0
	var rings: Array = []          # Array[PackedVector2Array] in lon/lat
	var area: float = 0.0          # square degrees, weighted by latitude
	var centre: Vector2 = Vector2.ZERO
	var owner: String = "unaligned"
	var contested: bool = false
	var unrest: float = 0.0

var countries: Dictionary = {}     # id -> Country
var order: Array = []              # ids, for stable drawing
var factions: Dictionary = {}      # id -> raw dictionary
var faction_order: Array = []
var capitals: Dictionary = {}      # id -> Vector2 lon/lat
var total_area: float = 0.0

func load_from_data() -> void:
	_load_geography()
	_load_factions()
	_assign_owners()

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _load_geography() -> void:
	var d := _read("res://data/world_map.json")
	var scale := float(d.get("scale", 10))
	for raw in d.get("countries", []):
		var c := Country.new()
		c.id = str(raw.get("id", ""))
		c.name = str(raw.get("name", c.id))
		c.continent = str(raw.get("cont", ""))
		c.population = int(raw.get("pop", 0))
		var sum := Vector2.ZERO
		var points := 0
		for flat in raw.get("rings", []):
			var ring := PackedVector2Array()
			var i := 0
			while i + 1 < flat.size():
				var p := Vector2(float(flat[i]) / scale, float(flat[i + 1]) / scale)
				ring.append(p)
				sum += p
				points += 1
				i += 2
			if ring.size() >= 3:
				c.rings.append(ring)
				# Land near the poles covers fewer square kilometres per degree,
				# so the share of the world is weighted by latitude.
				c.area += _ring_area(ring) * cos(deg_to_rad(clampf(ring[0].y, -85.0, 85.0)))
		if c.rings.is_empty():
			continue
		c.centre = sum / maxf(float(points), 1.0)
		countries[c.id] = c
		order.append(c.id)
		total_area += c.area

static func _ring_area(ring: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5

func _load_factions() -> void:
	var d := _read("res://data/factions.json")
	for raw in d.get("factions", []):
		var id := str(raw.get("id", ""))
		factions[id] = raw
		faction_order.append(id)
	for key in d.get("capitals", {}).keys():
		var pair: Array = d["capitals"][key]
		if pair.size() == 2:
			capitals[str(key)] = Vector2(float(pair[0]), float(pair[1]))
	for id in d.get("contested", []):
		if countries.has(str(id)):
			countries[str(id)].contested = true
			countries[str(id)].unrest = 0.6

func _assign_owners() -> void:
	for fid in faction_order:
		for member in factions[fid].get("members", []):
			if countries.has(str(member)):
				countries[str(member)].owner = fid

# ---------------------------------------------------------------------------

func faction_color(fid: String) -> Color:
	return Color.from_string(str(factions.get(fid, {}).get("color", "#6b7079")), Color.GRAY)

func faction_accent(fid: String) -> Color:
	return Color.from_string(str(factions.get(fid, {}).get("accent", "#aab0ba")), Color.WHITE)

func faction_name(fid: String) -> String:
	return DB.local_name(factions.get(fid, {}).get("name", {}), fid)

func country(id: String) -> Country:
	return countries.get(id, null)

## Share of the world's land each bloc holds, as a fraction of 1.
func control_share() -> Dictionary:
	var out: Dictionary = {}
	for fid in faction_order:
		out[fid] = 0.0
	for id in order:
		var c: Country = countries[id]
		out[c.owner] = float(out.get(c.owner, 0.0)) + c.area
	for fid in out.keys():
		out[fid] = float(out[fid]) / maxf(total_area, 1.0)
	return out

func members_of(fid: String) -> Array:
	var out: Array = []
	for id in order:
		if countries[id].owner == fid:
			out.append(id)
	return out

func transfer(country_id: String, to_faction: String) -> void:
	var c: Country = countries.get(country_id, null)
	if c == null or c.owner == to_faction:
		return
	c.owner = to_faction
	c.unrest = 0.8

## Countries of a rival bloc that touch this one, which is where a war can
## actually start. Adjacency is approximated by centre distance, which is
## enough at this scale and costs no extra data.
func neighbours_of(country_id: String, limit: float = 32.0) -> Array:
	var c: Country = countries.get(country_id, null)
	if c == null:
		return []
	var out: Array = []
	for id in order:
		if id == country_id:
			continue
		var other: Country = countries[id]
		if c.centre.distance_to(other.centre) < limit:
			out.append(id)
	return out

## The battlefield a country produces, from where it is on the globe.
func battle_map_for(country_id: String) -> String:
	var c: Country = countries.get(country_id, null)
	if c == null:
		return "village"
	var lat: float = absf(c.centre.y)
	if c.continent == "Africa" and lat < 30.0:
		return "desert"
	if c.continent == "Asia" and c.centre.y < 32.0 and c.centre.x > 30.0 and c.centre.x < 70.0:
		return "desert"
	if lat > 55.0:
		return "forest"
	if c.population > 60000000:
		return "city"
	if c.continent == "South America" or c.continent == "Oceania":
		return "forest"
	return "village"

func season_for(country_id: String) -> String:
	var c: Country = countries.get(country_id, null)
	if c == null:
		return "summer"
	var lat: float = c.centre.y
	if lat > 50.0:
		return "winter"
	if lat > 35.0:
		return "autumn"
	if lat < -20.0:
		return "spring"
	return "summer"
