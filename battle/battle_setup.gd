class_name BattleSetup
extends RefCounted
## Turns a human-sized description of a force — "30 infantry, 3 tanks, 2
## transports" — into the roster the battle actually spawns, and assembles the
## battle config that Custom Battle, Campaign and Sandbox all share.

## How a block of infantry is actually made up. A line of pure riflemen is not
## a force; it needs AT weight, a base of fire and eyes.
const INFANTRY_MIX := {
	"rifle": 0.62,
	"at": 0.18,
	"mg": 0.12,
	"recon": 0.08,
}

## The same order of battle produces a different army depending on who is
## fielding it: a regular force gets APCs and gunships, insurgents get
## technicals and RPGs.
const FACTION_UNITS := {
	"army": {
		"rifle": "inf_rifle", "at": "inf_at", "mg": "inf_mg", "recon": "inf_recon",
		"tank": "veh_tank", "transport": "veh_apc", "artillery": "veh_spg",
		"air": "air_heli", "drone": "air_drone",
	},
	"insurgent": {
		"rifle": "inf_insurgent", "at": "inf_rpg", "mg": "inf_mg", "recon": "inf_recon",
		"tank": "veh_tank", "transport": "veh_technical", "artillery": "veh_spg",
		"air": "air_drone", "drone": "air_drone",
	},
}

static func unit_for(faction: String, slot: String) -> String:
	var table: Dictionary = FACTION_UNITS.get(faction, FACTION_UNITS["army"])
	return str(table.get(slot, ""))

static func default_force() -> Dictionary:
	return {"infantry": 30, "tanks": 3, "transports": 2, "artillery": 1, "aircraft": 1}

## Expands a force into unit counts. The infantry mix always keeps at least one
## AT team and one recon team once there are enough bodies to spare.
static func roster_from_force(force: Dictionary, faction: String = "army") -> Dictionary:
	var roster: Dictionary = {}
	var infantry := int(force.get("infantry", 0))
	if infantry > 0:
		var assigned := 0
		var slots: Array = INFANTRY_MIX.keys()
		for i in range(slots.size()):
			var slot := str(slots[i])
			var uid := unit_for(faction, slot)
			var n: int
			if i == slots.size() - 1:
				n = infantry - assigned          # last type soaks the remainder
			else:
				n = int(round(float(infantry) * float(INFANTRY_MIX[slot])))
			if n > 0 and uid != "":
				roster[uid] = int(roster.get(uid, 0)) + n
				assigned += n
		if infantry >= 8:
			# Never field a line with no anti-tank weight and no eyes.
			var rifle_id := unit_for(faction, "rifle")
			for slot in ["at", "recon"]:
				var uid2 := unit_for(faction, slot)
				if uid2 != "" and int(roster.get(uid2, 0)) == 0:
					roster[uid2] = 1
					roster[rifle_id] = maxi(1, int(roster.get(rifle_id, 1)) - 1)
	_add(roster, unit_for(faction, "tank"), int(force.get("tanks", 0)))
	_add(roster, unit_for(faction, "transport"), int(force.get("transports", 0)))
	_add(roster, unit_for(faction, "artillery"), int(force.get("artillery", 0)))
	var aircraft := int(force.get("aircraft", 0))
	if aircraft > 0:
		# Air is split between a gunship and the drone that finds work for it.
		var gunships: int = maxi(1, int(ceil(float(aircraft) * 0.6)))
		_add(roster, unit_for(faction, "air"), gunships)
		_add(roster, unit_for(faction, "drone"), aircraft - gunships)
	return roster

static func _add(roster: Dictionary, unit_id: String, count: int) -> void:
	if unit_id == "" or count <= 0:
		return
	roster[unit_id] = int(roster.get(unit_id, 0)) + count

static func unit_total(force: Dictionary) -> int:
	var n := 0
	for k in ["infantry", "tanks", "transports", "artillery", "aircraft"]:
		n += int(force.get(k, 0))
	return n

## Ticket pool for a side: every unit it fields, plus a reserve to replace
## losses with, so a battle does not end the moment the first wave dies.
static func tickets_for(force: Dictionary, faction: String = "army") -> int:
	var men := 0
	var roster := roster_from_force(force, faction)
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
	var player_faction := str(options.get("player_faction", "army"))
	var enemy_faction := str(options.get("enemy_faction", "insurgent"))

	var teams: Array = [{}, {}]
	teams[player_team] = {
		"team": player_team,
		"nation": str(options.get("player_nation", "PLAYER")),
		"name": str(options.get("player_name", "TEAM A")),
		"color": str(options.get("player_color", DB.faction(player_faction).get("color", "4a5d3a"))),
		"faction": player_faction,
		"is_defender": player_is_defender,
		"roster": roster_from_force(player_force, player_faction),
		"tickets": tickets_for(player_force, player_faction),
		"supply": 1.0,
		"ai": false,
	}
	var enemy_team := 1 - player_team
	teams[enemy_team] = {
		"team": enemy_team,
		"nation": str(options.get("enemy_nation", "ENEMY")),
		"name": str(options.get("enemy_name", "TEAM B")),
		"color": str(options.get("enemy_color", DB.faction(enemy_faction).get("color", "6b5436"))),
		"faction": enemy_faction,
		"is_defender": not player_is_defender,
		"roster": roster_from_force(enemy_force, enemy_faction),
		"tickets": tickets_for(enemy_force, enemy_faction),
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

## Sandbox: no clock, no pressure, and enough supply to try anything.
static func sandbox(options: Dictionary) -> Dictionary:
	var opts := options.duplicate()
	opts["minutes"] = 0.0
	opts["sandbox"] = true
	opts["victory_mode"] = "elimination"
	var cfg := build(opts)
	cfg["teams"][int(cfg["player_team"])]["tickets"] = 9999
	return cfg
