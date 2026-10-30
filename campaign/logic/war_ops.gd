## Hujum operatsiyalari (UI'siz): hududga quruqlik / dengiz / havo orqali hujum rejasi.
##   check()   - qaysi usul mumkin, nega mumkin emas, nechta polk yuborish mumkin, ta'minot narxi;
##   launch()  - qo'shin bo'linadi (qolgani joyida qoladi), ta'minot to'lanadi, operatsiya lug'ati qaytadi;
##   resolve_auto() - avto-jang; apply_result() - 3D jang natijasini qo'llaydi;
##   biome_for() - hududga mos jang maydoni turi (cho'l, shahar, tog', o'rmon, qirg'oq, qish, mo''tadil).
## Sonlar data/rules.json -> operations va data/battle_biomes.json -> _select da.
class_name CampaignWarOps
extends RefCounted

const METHODS := ["land", "sea", "air"]
const KM_PER_PX := 9.266                 ## 4320 px = 360 daraja

var r: CampaignRules


func _init(rules: CampaignRules) -> void:
	r = rules


func _cfg(key: String, def: Variant) -> Variant:
	return (r.data.rule("operations", {}) as Dictionary).get(key, def)


func cost(method: String) -> int:
	return int((_cfg("supply_cost", {}) as Dictionary).get(method, 1))


## Ikki hudud orasidagi masofa (km, taxminiy).
func distance_km(a: int, b: int) -> float:
	var pa: ProvinceData = r.data.provinces[a]
	var pb: ProvinceData = r.data.provinces[b]
	var lat := deg_to_rad(84.0 - (pa.center_px.y + pb.center_px.y) * 0.5 / r.data.height * 142.0)
	var d := Vector2(pb.center_px - pa.center_px)
	d.x = fposmod(d.x + r.data.width * 0.5, r.data.width) - r.data.width * 0.5     # sana chizig'idan o'tish
	return Vector2(d.x * cos(lat), d.y).length() * KM_PER_PX


func _base_in(owner: int, pid: int, type: String) -> bool:
	for b in r.data.bases:
		if b.province == pid and b.type == type and r.data.provinces[pid].owner == owner:
			return true
	return false


## Hujum imkoniyatlari: {ok, reason (umumiy), methods: {land|sea|air: {ok, reason, max, cost}}}.
func check(a: ArmyData, target: int) -> Dictionary:
	var out := {"ok": false, "reason": "", "methods": {}}
	var tp: ProvinceData = r.data.provinces.get(target)
	var from: ProvinceData = r.data.provinces.get(a.province) if a else null
	if tp == null or from == null:
		out.reason = "op.no_army"
		return out
	if tp.owner == a.owner:
		out.reason = "op.own"
	elif r.data.allied(a.owner, tp.owner):
		out.reason = "op.ally"
	elif not r.diplomacy.can_attack(a.owner, tp.owner):
		out.reason = "op.not_at_war"
	elif a.moved or a.busy > 0:
		out.reason = "already_moved"
	var c: CountryData = r.data.countries[a.owner]
	var sup := int(c.resources.get("supply", 0))
	for m in METHODS:
		var e := {"ok": false, "reason": "", "cost": cost(m), "max": a.size}
		match m:
			"land":
				if not (target in from.neighbors):
					e.reason = "op.no_border"
			"sea":
				if not from.is_sea_link(target):
					e.reason = "op.no_sea_route"
				elif not _naval_near(a.owner, from):
					e.reason = "op.no_port"
			"air":
				e.max = mini(a.size, int(_cfg("air_max_regiments", 4)))
				if not _base_in(a.owner, a.province, "air"):
					e.reason = "op.no_airbase"
				elif distance_km(a.province, target) > float(_cfg("air_range_km", 1500)):
					e.reason = "op.out_of_range"
		e.max = mini(e.max, sup / maxi(1, e.cost))
		if e.reason == "" and e.max < 1:
			e.reason = "op.no_supply"
		e.ok = e.reason == "" and out.reason == ""
		out.methods[m] = e
		out.ok = out.ok or e.ok
	return out


## Dengiz hujumi: qo'shin turgan yoki unga qo'shni o'z hududida harbiy-dengiz bazasi bo'lishi kerak.
func _naval_near(owner: int, from: ProvinceData) -> bool:
	if _base_in(owner, from.id, "naval"):
		return true
	for n in from.neighbors:
		if _base_in(owner, n, "naval"):
			return true
	return false


## Hujumni boshlaydi: count polk ajratiladi (qolgani joyida qoladi), ta'minot to'lanadi.
func launch(a: ArmyData, target: int, method: String, count: int) -> Dictionary:
	var ck := check(a, target)
	var m: Dictionary = ck.methods.get(method, {})
	if not m.get("ok", false):
		return {}
	count = clampi(count, 1, int(m.max))
	var c: CountryData = r.data.countries[a.owner]
	c.resources.supply = int(c.resources.get("supply", 0)) - count * int(m.cost)
	var strike := a
	if count < a.size:
		a.size -= count
		strike = r.new_army(a.owner, a.province, count)
	a.moved = true
	strike.moved = true
	var tp: ProvinceData = r.data.provinces[target]
	var dfn := r.army_in(target)
	return {"army": strike, "from": strike.province, "to": target, "method": method, "count": count,
		"attacker": a.owner, "defender": tp.owner, "def_regiments": dfn.size if dfn else 0,
		"biome": biome_for(target), "seed": target * 7919 + r.turn * 31}


## Avto-jang. G'alaba bo'lsa hudud bosib olinadi; dengizdan tushgan qo'shin keyingi yurish band.
func resolve_auto(op: Dictionary) -> bool:
	var a: ArmyData = op.army
	var tp: ProvinceData = r.data.provinces[op.to]
	var other := r.army_in(op.to)
	var mult := float((_cfg("mult", {}) as Dictionary).get(op.method, 1.0))
	var won := r._battle(a, tp, other, mult)
	_finish(op, won)
	return won


## 3D jang natijasi: {won, att_left (polk), def_left (polk)}.
func apply_result(op: Dictionary, res: Dictionary) -> void:
	var a: ArmyData = op.army
	var won := bool(res.get("won", false))
	a.size = maxi(1, int(res.get("att_left", a.size)))
	var other := r.army_in(op.to)
	if other and other.owner != a.owner:
		if won or int(res.get("def_left", 1)) <= 0:
			r.data.armies.erase(other)
		else:
			other.size = maxi(1, int(res.def_left))
	var e := {"turn": r.turn, "province": op.to, "attacker": a.owner, "defender": op.defender, "won": won}
	r.battle_log.append(e)
	if won and a.owner == r.player_id:
		r.missions.battles_won += 1
		r.add_xp("battle_won")
	r.battle_fought.emit(e)
	_finish(op, won)


func _finish(op: Dictionary, won: bool) -> void:
	var a: ArmyData = op.army
	if won:
		a.province = op.to
		if op.method == "sea":
			a.busy = int(r.data.rule("sea_move_extra_turns", 1))
		if a.owner == r.player_id:
			r.add_xp("province_taken")
		r.conquer(op.to, a.owner)
	r.supply.update()
	r.armies_changed.emit()
	r.state_changed.emit()


## Hudud -> jang maydoni turi.
func biome_for(pid: int) -> String:
	var p: ProvinceData = r.data.provinces.get(pid)
	if p == null:
		return "temperate"
	var sel: Dictionary = BattleGen.biomes().get("_select", {})
	var lat := 84.0 - float(p.center_px.y) / r.data.height * 142.0
	var dens := float(p.population) / maxf(1.0, float(p.area_km2))
	var cap := false
	for c in r.data.countries.values():
		if c.capital == pid:
			cap = true
	if absf(lat) >= float(sel.get("winter_lat", 56)):
		return "winter"
	if p.elevation_m >= int(sel.get("mountain_m", 1100)):
		return "mountain"
	if dens >= float(sel.get("city_density", 350)) or (cap and p.population >= int(sel.get("city_capital_pop", 2000000))):
		return "city"
	var dn: Array = sel.get("desert_lat", [14, 36])
	var ds: Array = sel.get("desert_lat_south", [-34, -16])
	if dens < float(sel.get("desert_density", 40)) and ((lat >= dn[0] and lat <= dn[1]) or (lat >= ds[0] and lat <= ds[1])):
		return "desert"
	if p.coastal:
		return "coast"
	if p.resource == "wood":
		return "forest"
	return "temperate"
