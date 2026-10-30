## Saqlash: o'yinchi profili (user://profile.save) va kampaniya slotlari (user://saves/slot_N.json).
## Fayl buzilgan yoki eski versiya bo'lsa o'yin qulamaydi: standart profil bilan davom etadi va xabar beradi.
extends Node

const PROFILE_PATH := "user://profile.save"
const SAVE_DIR := "user://saves/"
const VERSION := 1

var last_error := ""


func save_profile(p: PlayerProfile) -> bool:
	var d := {"version": VERSION, "player_name": p.player_name, "xp": p.xp, "credits": p.credits, "supply": p.supply,
		"owned_vehicles": Array(p.owned_vehicles), "vehicle_upgrades": p.vehicle_upgrades,
		"selected_vehicles": Array(p.selected_vehicles), "owned_weapons": Array(p.owned_weapons),
		"owned_attachments": Array(p.owned_attachments), "weapon_mods": p.weapon_mods, "equipped_weapon": p.equipped_weapon,
		"owned_cosmetics": Array(p.owned_cosmetics), "owned_camos": Array(p.owned_camos),
		"loadouts": p.loadouts.map(func(l: SoldierLoadout): return l.to_dict()), "active_loadout": p.active_loadout,
		"mission_progress": p.mission_progress, "last_mission": p.last_mission, "daily": p.daily}
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		last_error = "save failed: %s" % error_string(FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(d, " "))
	return true


func load_profile() -> PlayerProfile:
	var p := PlayerProfile.new()
	if not FileAccess.file_exists(PROFILE_PATH):
		p.loadout()
		return p
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not (d is Dictionary) or int(d.get("version", 0)) > VERSION:
		last_error = "profile.save damaged, defaults used"
		push_warning(last_error)
		p.loadout()
		return p
	p.player_name = str(d.get("player_name", p.player_name))
	p.xp = int(d.get("xp", 0))
	p.credits = int(d.get("credits", p.credits))
	p.supply = int(d.get("supply", p.supply))
	for k in ["owned_vehicles", "selected_vehicles", "owned_weapons", "owned_attachments", "owned_cosmetics", "owned_camos"]:
		if d.get(k) is Array:
			p.set(k, PackedStringArray(d[k]))
	for k in ["vehicle_upgrades", "weapon_mods", "mission_progress", "daily"]:
		if d.get(k) is Dictionary:
			p.set(k, d[k])
	p.equipped_weapon = str(d.get("equipped_weapon", p.equipped_weapon))
	p.last_mission = str(d.get("last_mission", ""))
	p.active_loadout = int(d.get("active_loadout", 0))
	p.loadouts.clear()
	for l in d.get("loadouts", []):
		if l is Dictionary:
			p.loadouts.append(SoldierLoadout.from_dict(l))
	p.loadout()
	return p


# ------------------------------------------------------------------ kampaniya slotlari
func slot_path(i: int) -> String:
	return SAVE_DIR + "slot_%d.json" % i


func save_campaign(i: int, state: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	state["version"] = VERSION
	state["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f == null:
		last_error = "campaign save failed"
		return false
	f.store_string(JSON.stringify(state))
	return true


func load_campaign(i: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(i)):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(i)))
	return d if d is Dictionary else {}


## Slot haqida qisqa ma'lumot (nom, sana, davlat, yurish) yoki bo'sh.
func slot_info(i: int) -> Dictionary:
	var d := load_campaign(i)
	if d.is_empty():
		return {}
	return {"country": d.get("player_code", "?"), "turn": d.get("turn", 1), "saved_at": d.get("saved_at", ""), "slot": i}
