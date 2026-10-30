## Kampaniya missiyalari: res://data/missions/*.tres ni yuklaydi, maqsad hududlarni (qoida bo'yicha)
## o'yinchi davlatiga qarab tanlaydi va vazifalar holatini HAQIQIY o'yin holatidan tekshiradi.
class_name CampaignMissions
extends RefCounted

signal completed(m: MissionData)

const DIR := "res://data/missions/"

var rules: CampaignRules
var list: Array[MissionData] = []
var targets := {}               ## mission id -> province id
var done := {}                  ## mission id -> true
var start_provinces := 0
var battles_won := 0


func _init(r: CampaignRules) -> void:
	rules = r
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		var path := DIR + f.trim_suffix(".remap")
		if path.ends_with(".tres") and ResourceLoader.exists(path):
			var m := load(path) as MissionData
			if m:
				list.append(m)
	list.sort_custom(func(a, b): return a.order < b.order)


## Davlat tanlanganda: maqsadlar o'yinchi davlatiga qarab aniqlanadi.
func start(cid: int) -> void:
	targets.clear()
	done.clear()
	battles_won = 0
	start_provinces = rules.data.countries[cid].province_count
	for m in list:
		targets[m.id] = _resolve(m.target_rule, cid)


func _resolve(rule: String, cid: int) -> int:
	var d := rules.data
	var c: CountryData = d.countries[cid]
	var border := {}
	for p in d.provinces.values():
		if p.owner != cid:
			continue
		for n in p.all_neighbors():
			var q: ProvinceData = d.provinces.get(n)
			if q and q.owner != cid and not d.allied(cid, q.owner):
				border[n] = true
	if border.is_empty():
		return 0
	var cap := rules.province_px(c.capital)
	match rule:
		"richest_enemy_neighbor":
			return border.keys().reduce(func(a, b): return a if d.provinces[a].gdp_musd >= d.provinces[b].gdp_musd else b)
		"weakest_neighbor_border":
			return border.keys().reduce(func(a, b): return a if rules.defence(a) <= rules.defence(b) else b)
		"nearest_enemy_capital":
			var best := 0
			var bd := INF
			for o in d.countries.values():
				if o.id == cid or o.province_count == 0 or d.allied(cid, o.id):
					continue
				var dd := cap.distance_squared_to(rules.province_px(o.capital))
				if dd < bd:
					bd = dd
					best = o.capital
			return best
	return 0


func available(m: MissionData) -> bool:
	return m.requires == "" or done.has(m.requires)


## Vazifa holati: [{text, done, progress}]
func status(m: MissionData) -> Array:
	var out := []
	var d := rules.data
	var pid := rules.player_id
	var t: int = targets.get(m.id, 0)
	var tname: String = d.provinces[t].name if d.provinces.has(t) else "?"
	for o in m.objectives:
		var n := int(o.get("count", 1))
		var ok := false
		var prog := ""
		match str(o.get("type", "")):
			"declare_war":
				ok = rules.diplomacy.enemies_of(pid).size() >= n
			"win_battles":
				ok = battles_won >= n
				prog = "%d/%d" % [mini(battles_won, n), n]
			"capture_target":
				ok = t > 0 and d.provinces[t].owner == pid
			"supply_target":
				var a := rules.army_in(t)
				ok = a != null and a.owner == pid and a.supplied
			"own_provinces_plus":
				var have: int = d.countries[pid].province_count - start_provinces
				ok = have >= n
				prog = "%d/%d" % [clampi(have, 0, n), n]
			"own_provinces_mult":
				var need := int(ceil(start_provinces * float(o.get("mult", 2.0))))
				ok = d.countries[pid].province_count >= need
				prog = "%d/%d" % [d.countries[pid].province_count, need]
		# hudud maqsadlari nom oladi, son maqsadlari son oladi
		var typ := str(o.get("type", ""))
		var args: Array = [tname] if typ in ["capture_target", "supply_target"] else [n]
		out.append({"text": Loc.t(str(o.get("text", "")), args), "done": ok, "progress": prog})
	return out


## Har o'zgarishdan keyin: bajarilgan missiya mukofotini beradi va keyingisini ochadi.
func check() -> void:
	if rules.player_id == 0:
		return
	for m in list:
		if done.has(m.id) or not available(m):
			continue
		var all_ok := true
		for s in status(m):
			all_ok = all_ok and s.done
		if all_ok and not m.objectives.is_empty():
			done[m.id] = true
			rules.grant(m.rewards)
			completed.emit(m)


func current() -> MissionData:
	for m in list:
		if not done.has(m.id) and available(m):
			return m
	return list.back() if not list.is_empty() else null
