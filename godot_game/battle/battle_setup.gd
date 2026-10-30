class_name BattleSetup
extends RefCounted
## Turns a human-sized description of a force — "30 infantry, 3 tanks, 2
## transports" — into the roster the battle actually spawns, and assembles the
## battle config that Custom Battle, Campaign and Sandbox all share.

## How a block of infantry is actually made up. A line of pure riflemen is not
## a force; it needs AT weight, a base of fire and eyes.
const INFANTRY_MIX := {
	"inf_rifle": 0.62,
	"inf_at": 0.18,
	"inf_mg": 0.12,
	"inf_recon": 0.08,
}

static func default_force() -> Dictionary:
	return {"infantry": 30, "tanks": 3, "transports": 2, "artillery": 1, "aircraft": 1}

## Expands a force into unit counts. The infantry mix always keeps at least one
## AT team and one recon team once there are enough bodies to spare.
static func roster_from_force(force: Dictionary) -> Dictionary:
	var roster: Dictionary = {}
	var infantry := int(force.get("infantry", 0))
	if infantry > 0:
		var assigned := 0
		var keys: Array = INFANTRY_MIX.keys()
		for i in range(keys.size()):
			var uid := str(keys[i])
			var n: int
			if i == keys.size() - 1:
				n = infantry - assigned          # last type soaks the remainder
			else:
				n = int(round(float(infantry) * float(INFANTRY_MIX[uid])))
			if n > 0:
				roster[uid] = n
				assigned += n
		if infantry >= 8:
			for uid in ["inf_at", "inf_recon"]:
				if int(roster.get(uid, 0)) == 0:
					roster[uid] = 1
					roster["inf_rifle"] = maxi(1, int(roster.get("inf_rifle", 1)) - 1)
	var tanks := int(force.get("tanks", 0))
	if tanks > 0:
		roster["veh_tank"] = tanks
	var transports := int(force.get("transports", 0))
	if transports > 0:
		roster["veh_apc"] = transports
	var artillery := int(force.get("artillery", 0))
	if artillery > 0:
		roster["veh_spg"] = artillery
	var aircraft := int(force.get("aircraft", 0))
	if aircraft > 0:
		# Air is split between a gunship and the drone that finds work for it.
		roster["air_heli"] = maxi(1, int(ceil(float(aircraft) * 0.6)))
		var drones: int = aircraft - int(roster["air_heli"])
		if drones > 0:
			roster["air_drone"] = drones
	return roster

static func unit_total(force: Dictionary) -> int:
	var n := 0
	for k in ["infantry", "tanks", "transports", "artillery", "aircraft"]:
		n += int(force.get(k, 0))
	return n

## Ticket pool for a side: every unit it fields, plus a reserve to replace
## losses with, so a battle does not end the moment the first wave dies.
static func tickets_for(force: Dictionary) -> int:
	var men := 0
	var roster := roster_from_force(force)
	for uid in roster.keys():
		men += int(roster[uid]) * maxi(1, int(DB.unit(str(uid)).get("men", 1)))
	return maxi(40, int(float(men) * 1.6))

## The one config builder every mode goes through.
static func build(options: Dictionary) -> Dictionary:
	var player_force: Dictionary = options.get("player_force", default_force())
	var enemy_force: Dictionary = options.get("enemy_force", default_force())
	var player_team := int(options.get("player_team", 0))
	var player_is_defender := bool(options.get("player_is_defender", false))
	var minutes := float(options.get("minutes", 15.0))

	var teams: Array = [{}, {}]
	teams[player_team] = {
		"team": player_team,
		"nation": str(options.get("player_nation", "PLAYER")),
		"name": str(options.get("player_name", "TEAM A")),
		"color": str(options.get("player_color", "3fa7d6")),
		"is_defender": player_is_defender,
		"roster": roster_from_force(player_force),
		"tickets": tickets_for(player_force),
		"supply": 1.0,
		"ai": false,
	}
	var enemy_team := 1 - player_team
	teams[enemy_team] = {
		"team": enemy_team,
		"nation": str(options.get("enemy_nation", "ENEMY")),
		"name": str(options.get("enemy_name", "TEAM B")),
		"color": str(options.get("enemy_color", "e05c5c")),
		"is_defender": not player_is_defender,
		"roster": roster_from_force(enemy_force),
		"tickets": tickets_for(enemy_force),
		"supply": 1.0,
		"ai": true,
	}
	return {
		"battle_id": 0,
		"province": -1,
		"province_name": str(options.get("title", "Custom Battle")),
		"map": str(options.get("map", "village")),
		"season": str(options.get("season", "summer")),
		"weather": str(options.get("weather", "clear")),
		"victory_mode": str(options.get("victory_mode", "capture")),
		"difficulty": str(options.get("difficulty", "normal")),
		"duration": minutes * 60.0,
		"seed": int(options.get("seed", randi())),
		"player_team": player_team,
		"sandbox": bool(options.get("sandbox", false)),
		"mission": str(options.get("mission", "")),
		"teams": teams,
	}

## A campaign mission row straight out of data/missions.json.
static func from_mission(mission: Dictionary) -> Dictionary:
	var cfg := build({
		"title": DB.local_name(mission.get("name", {}), str(mission.get("id", "mission"))),
		"map": str(mission.get("map", "village")),
		"season": str(mission.get("season", "summer")),
		"weather": str(mission.get("weather", "clear")),
		"victory_mode": str(mission.get("victory_mode", "capture")),
		"difficulty": str(mission.get("difficulty", "normal")),
		"minutes": float(mission.get("duration", 900)) / 60.0,
		"player_force": mission.get("player", default_force()),
		"enemy_force": mission.get("enemy", default_force()),
		"player_is_defender": bool(mission.get("player_is_defender", false)),
		"player_name": "SIZNING KUCHLARINGIZ",
		"enemy_name": "DUSHMAN",
		"mission": str(mission.get("id", "")),
	})
	return cfg

## Sandbox: no clock, no pressure, and enough supply to try anything.
static func sandbox(options: Dictionary) -> Dictionary:
	var opts := options.duplicate()
	opts["minutes"] = 0.0
	opts["sandbox"] = true
	opts["victory_mode"] = "elimination"
	var cfg := build(opts)
	cfg["teams"][int(cfg["player_team"])]["tickets"] = 9999
	return cfg
