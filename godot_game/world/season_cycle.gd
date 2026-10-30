class_name SeasonCycle
extends RefCounted
## Seasons and weather. They change what the world map costs to cross and what
## the 3D battlefield looks and plays like.

const DAYS_PER_SEASON := 30

static func season_for_day(day: int) -> String:
	var order := ["spring", "summer", "autumn", "winter"]
	return order[int(day / DAYS_PER_SEASON) % 4]

static func advance(world) -> void:
	var new_season: String = season_for_day(world.day)
	var changed: bool = new_season != world.season
	world.season = new_season
	var rng := RandomNumberGenerator.new()
	rng.seed = world.seed_value + world.day * 7919
	world.weather = roll_weather(new_season, rng)
	if changed:
		world.push_log("Fasl almashdi: %s" % new_season)
	EventBus.weather_changed.emit(world.season, world.weather)

static func roll_weather(season: String, rng: RandomNumberGenerator) -> String:
	var table: Dictionary
	match season:
		"winter":
			table = {"clear": 30, "snow": 40, "fog": 20, "storm": 10}
		"autumn":
			table = {"clear": 35, "rain": 35, "fog": 20, "storm": 10}
		"spring":
			table = {"clear": 45, "rain": 30, "fog": 20, "storm": 5}
		_:
			table = {"clear": 70, "rain": 15, "fog": 10, "storm": 5}
	var total := 0
	for k in table.keys():
		total += int(table[k])
	var roll := rng.randi_range(1, total)
	for k in table.keys():
		roll -= int(table[k])
		if roll <= 0:
			return str(k)
	return "clear"

## Multiplies global-map army movement speed.
static func movement_modifier(world) -> float:
	var w: Dictionary = DB.weather(world.weather)
	var seasonal := 1.0
	if world.season == "winter":
		seasonal = 0.8
	elif world.season == "autumn":
		seasonal = 0.9
	return seasonal * float(w.get("speed", 1.0))

## Multiplies sight range everywhere, on the map and in battle.
static func vision_modifier(world) -> float:
	return float(DB.weather(world.weather).get("vision", 1.0))

static func accuracy_modifier(world) -> float:
	return float(DB.weather(world.weather).get("accuracy", 1.0))

## Snow cover 0..1 drives the winter look of the battlefield.
static func snow_amount(season: String, weather: String) -> float:
	if season == "winter":
		return 0.85 if weather != "snow" else 1.0
	if season == "autumn" and weather == "snow":
		return 0.35
	return 0.0
