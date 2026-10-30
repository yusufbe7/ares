class_name SeasonCycle
extends RefCounted
## Seasons and weather: how much snow is on the ground, how wet it is, and
## which weather a season tends to produce. Purely a lookup over the data in
## battle_maps.json, with no state of its own.

const DAYS_PER_SEASON := 30

static func season_for_day(day: int) -> String:
	var order: Array = DB.season_ids()
	if order.is_empty():
		order = ["spring", "summer", "autumn", "winter"]
	return str(order[int(day / DAYS_PER_SEASON) % order.size()])

static func roll_weather(season_id: String, rng: RandomNumberGenerator) -> String:
	# Each season carries its own weather odds in data, so winter brings snow
	# and autumn brings rain without any of that living in code.
	var table: Dictionary = DB.season(season_id).get("weather_bias", {})
	if table.is_empty():
		table = {"clear": 60, "rain": 20, "fog": 20}
	var total := 0
	for k in table.keys():
		total += int(table[k])
	if total <= 0:
		return "clear"
	var roll := rng.randi_range(1, total)
	for k in table.keys():
		roll -= int(table[k])
		if roll <= 0:
			return str(k)
	return "clear"

## Snow cover 0..1 drives the winter look of the battlefield. The season sets
## the base; falling snow tops it up.
static func snow_amount(season_id: String, weather_id: String) -> float:
	var base := float(DB.season(season_id).get("snow", 0.0))
	if weather_id == "snow":
		base = maxf(base, 0.4) + 0.15
	return clampf(base, 0.0, 1.0)

## How wet and muddy the ground reads, which is what sells autumn and spring.
static func wetness(season_id: String, weather_id: String) -> float:
	var base := float(DB.season(season_id).get("wet", 0.0))
	if weather_id == "rain" or weather_id == "storm":
		base = minf(1.0, base + 0.35)
	return clampf(base, 0.0, 1.0)
