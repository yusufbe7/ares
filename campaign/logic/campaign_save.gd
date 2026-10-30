## Kampaniya holatini saqlash / yuklash (JSON lug'at). SaveManager slot fayliga yozadi.
## Saqlanadi: hudud egalari, qo'shinlar, davlat resurslari, urushlar, yurish, o'yinchi, XP, jang log'i,
## iqtisod tarixi, missiyalar holati.
class_name CampaignSave
extends RefCounted


static func to_dict(r: CampaignRules) -> Dictionary:
	var d := r.data
	var owners := {}
	for p in d.provinces.values():
		owners[str(p.id)] = p.owner
	var armies := []
	for a in d.armies:
		armies.append([a.id, a.owner, a.province, a.size, a.busy])
	var res := {}
	for c in d.countries.values():
		res[str(c.id)] = c.resources
	var pc: CountryData = d.countries.get(r.player_id)
	return {"player": r.player_id, "player_code": pc.code if pc else "", "turn": r.turn, "xp": r.xp,
		"owners": owners, "armies": armies, "resources": res, "wars": r.diplomacy.to_dict(),
		"battle_log": r.battle_log, "history": r.history, "setup": r.setup, "occupation": r.occupation.to_dict(),
		"extra_allies": d.extra_allies,
		"missions": {"targets": r.missions.targets, "done": r.missions.done, "start": r.missions.start_provinces,
			"won": r.missions.battles_won}}


## Holatni tiklaydi. Buzilgan bo'lsa false (o'yin yangi kampaniya bilan davom etadi).
static func from_dict(r: CampaignRules, s: Dictionary) -> bool:
	var d := r.data
	if not d.countries.has(int(s.get("player", 0))):
		return false
	for k in s.get("owners", {}):
		var p: ProvinceData = d.provinces.get(int(k))
		if p:
			p.owner = int(s.owners[k])
	d.armies.clear()
	for e in s.get("armies", []):
		if e is Array and e.size() >= 4 and d.provinces.has(int(e[2])):
			var a := ArmyData.new()
			a.id = int(e[0]); a.owner = int(e[1]); a.province = int(e[2]); a.size = int(e[3])
			a.busy = int(e[4]) if e.size() > 4 else 0
			d.armies.append(a)
	for k in s.get("resources", {}):
		var c: CountryData = d.countries.get(int(k))
		if c and s.resources[k] is Dictionary:
			c.resources = s.resources[k]
	d.recount()
	r.player_id = int(s.player)
	for c in d.countries.values():
		c.controller = "player" if c.id == r.player_id else "bot"
	r.phase = "play"
	r.turn = int(s.get("turn", 1))
	r.xp = int(s.get("xp", 0))
	r.diplomacy.from_dict(s.get("wars", {}))
	r.battle_log = s.get("battle_log", [])
	r.history = s.get("history", [])
	r.apply_setup(s.get("setup", {}), false)
	r.occupation.from_dict(s.get("occupation", {}))
	d.extra_allies = (s.get("extra_allies", {}) as Dictionary).duplicate()
	var m: Dictionary = s.get("missions", {})
	r.missions.targets = {}
	for k in m.get("targets", {}):
		r.missions.targets[k] = int(m.targets[k])
	r.missions.done = m.get("done", {})
	r.missions.start_provinces = int(m.get("start", 0))
	r.missions.battles_won = int(m.get("won", 0))
	r.supply.update()
	r.state_changed.emit()
	return true
