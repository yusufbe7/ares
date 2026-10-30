## O'yinchi profili: ism, daraja, XP, credits, supply, sotib olinganlar, loadout slotlari, missiya progressi.
## SaveManager uni user://profile.save ga JSON qilib yozadi (versiya raqami bilan).
class_name PlayerProfile
extends Resource

const XP_PER_LEVEL := 500

@export var player_name := "Player"
@export var xp := 0
@export var credits := 250000
@export var supply := 320
@export var owned_vehicles: PackedStringArray = ["t72"]
@export var vehicle_upgrades := {}         ## id -> {"engine": 0..3, "armor": 0..3, "weapon": 0..3}
@export var selected_vehicles: PackedStringArray = ["t72"]
@export var owned_weapons: PackedStringArray = ["ak74", "rpg7"]
@export var owned_attachments: PackedStringArray = []
@export var weapon_mods := {}              ## weapon id -> {slot: attachment id}
@export var equipped_weapon := "ak74"
@export var owned_cosmetics: PackedStringArray = []
@export var owned_camos: PackedStringArray = ["olive"]
@export var loadouts: Array[SoldierLoadout] = []
@export var active_loadout := 0
@export var mission_progress := {}         ## mission id -> true
@export var last_mission := ""
@export var daily := {}                    ## topshiriq id -> {"progress": n, "claimed": bool}


func level() -> int:
	return 1 + xp / XP_PER_LEVEL


func level_progress() -> float:
	return float(xp % XP_PER_LEVEL) / XP_PER_LEVEL


func loadout() -> SoldierLoadout:
	while loadouts.size() < 3:
		var l := SoldierLoadout.new()
		l.slot_name = "Loadout %d" % (loadouts.size() + 1)
		loadouts.append(l)
	return loadouts[clampi(active_loadout, 0, 2)]


## Harbiy unvon (data/ranks.json, XP chegaralari bo'yicha) - tarjima kaliti.
func rank_key() -> String:
	var ranks: Array = CampaignData._json("res://data/ranks.json", [])
	var out := "rank.private"
	for r in ranks:
		if xp >= int(r.get("xp", 0)):
			out = str(r.get("name", out))
	return out
