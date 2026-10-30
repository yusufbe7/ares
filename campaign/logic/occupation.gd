## Bosib olingandan keyingi mexanika (UI'siz):
##   * tartibsizlik (unrest): yangi bosib olingan hududda 60, har yurish kamayadi, daromadni kamaytiradi,
##     yuqori bo'lsa qo'zg'olon - hudud oldingi egasiga qaytadi;
##   * baza qo'lga olinsa xabar (aerodrom, port, ombor egasi hudud egasi bilan birga o'zgaradi);
##   * poytaxt olinsa - kapitulyatsiya: tinchlik, tovon (oltin), poytaxt boshqa hududga ko'chadi; davlat
##     yo'q bo'lib ketmaydi; o'yinchi poytaxti olinsa - mag'lubiyat;
##   * diplomatiya: blokdoshlar himoyaga kiradi, poytaxt olinsa boshqa bloklar sanksiya qo'yadi, umumiy
##     dushmani bor blokka kirmagan davlat o'yinchiga ittifoq taklif qiladi;
##   * g'alaba shartlari (rules.json -> victory): dunyo ulushi yoki kapitulyatsiyalar soni.
class_name CampaignOccupation
extends RefCounted

var r: CampaignRules
var unrest := {}                 ## hudud id -> 0..100
var prev_owner := {}             ## hudud id -> oldingi egasi (qo'zg'olon uchun)
var sanctions := {}              ## davlat id -> qolgan yurishlar
var capitulations := {}          ## davlat id -> taslim qildirgan davlatlar soni
var home_capital := {}           ## davlat id -> asl poytaxti (qaytarib olinsa poytaxt qaytadi)


func _init(rules: CampaignRules) -> void:
	r = rules


func _cfg(key: String, def: Variant) -> Variant:
	return (r.data.rule("occupation", {}) as Dictionary).get(key, def)


## Daromad ko'paytmasi (tartibsizlik va sanksiya).
func income_mult(cid: int, pid: int) -> float:
	var m := 1.0 - float(unrest.get(pid, 0)) / 100.0 * float(_cfg("unrest_income_loss", 0.7))
	if sanctions.has(cid):
		m *= 1.0 - float(_cfg("sanction_income_loss", 0.15))
	return m


## rules.conquer dan keyin chaqiriladi.
func on_conquer(pid: int, old: int, new_owner: int) -> void:
	var d := r.data
	unrest[pid] = int(_cfg("unrest_on_conquest", 60))
	prev_owner[pid] = old
	var player_side := old == r.player_id or new_owner == r.player_id
	for b in d.bases:
		if b.province == pid and player_side:
			r.message.emit(Loc.t("occ.base", [Loc.country(d.countries.get(new_owner)), Loc.t("base." + str(b.type)), d.provinces[pid].name]))
	var nc: CountryData = d.countries.get(new_owner)
	if nc and int(home_capital.get(new_owner, 0)) == pid:
		nc.capital = pid                                    # asl poytaxt qaytarib olindi
		home_capital.erase(new_owner)
	var oc: CountryData = d.countries.get(old)
	if oc and oc.capital == pid and oc.province_count > 0:
		if not home_capital.has(old):
			home_capital[old] = pid
		_capitulate(old, new_owner)
	check_victory()


func _capitulate(loser: int, winner: int) -> void:
	var d := r.data
	var lc: CountryData = d.countries[loser]
	var wc: CountryData = d.countries.get(winner)
	r.diplomacy.make_peace(loser, winner)
	var pay := int(int(lc.resources.get("gold", 0)) * float(_cfg("reparations", 0.3)))
	lc.resources.gold = int(lc.resources.get("gold", 0)) - pay
	if wc:
		wc.resources.gold = int(wc.resources.get("gold", 0)) + pay
	capitulations[winner] = int(capitulations.get(winner, 0)) + 1
	# yangi poytaxt: eng ko'p aholili qolgan hudud
	var best: ProvinceData = null
	for p in d.provinces.values():
		if p.owner == loser and (best == null or p.population > best.population):
			best = p
	if best:
		lc.capital = best.id
	r.message.emit(Loc.t("occ.capitulated", [Loc.country(lc), Loc.country(wc), pay]))
	if best:
		r.message.emit(Loc.t("occ.capital_moved", [Loc.country(lc), best.name]))
	if loser == r.player_id:
		r.phase = "over"
		r.message.emit(Loc.t("occ.defeat"))
		return
	# boshqa bloklar sanksiya qo'yadi (o'yinchi poytaxt olsa)
	if winner == r.player_id:
		var n := int(_cfg("sanction_turns", 5))
		sanctions[winner] = n
		var who := []
		for b in d.blocs:
			if d.bloc_of(winner) != b.id:
				who.append(str(b.name))
		r.message.emit(Loc.t("occ.sanctions", [", ".join(who), Loc.country(wc), n]))


## Urush e'lon qilinganda: himoyachining blokdoshlari hujumchiga urush e'lon qiladi.
func on_war(a: int, b: int) -> void:
	var d := r.data
	for c in d.countries.values():
		if c.id == a or c.id == b or c.province_count == 0 or not d.allied(c.id, b):
			continue
		if r.diplomacy.declare_war(c.id, a, r.turn) and (a == r.player_id or b == r.player_id or c.id == r.player_id):
			r.message.emit(Loc.t("occ.bloc_joins", [Loc.country(c), Loc.country(d.countries[b])]))


## Yurish oxiri: tartibsizlik kamayadi, qo'zg'olon, sanksiya muddati, ittifoq takliflari.
func end_turn() -> void:
	var d := r.data
	var decay := int(_cfg("unrest_decay", 8))
	for pid in unrest.keys():
		var p: ProvinceData = d.provinces.get(pid)
		var u: int = unrest[pid]
		if p and u >= int(_cfg("revolt_unrest", 45)) and r.army_in(pid) == null and randf() < float(_cfg("revolt_chance", 0.08)):
			var back: int = prev_owner.get(pid, 0)
			if d.countries.has(back) and d.countries[back].province_count > 0:
				if back == r.player_id or p.owner == r.player_id:
					r.message.emit(Loc.t("occ.revolt", [p.name, Loc.country(d.countries[back])]))
				r.conquer(pid, back)
				r.new_army(back, pid, 2)
				unrest.erase(pid)
				continue
		unrest[pid] = u - decay
		if unrest[pid] <= 0:
			unrest.erase(pid)
	for c in sanctions.keys():
		sanctions[c] -= 1
		if sanctions[c] <= 0:
			sanctions.erase(c)
	_offers()


func _offers() -> void:
	var d := r.data
	var enemies := r.diplomacy.enemies_of(r.player_id)
	if enemies.is_empty():
		return
	for c in d.countries.values():
		if c.id == r.player_id or c.bloc != "" or c.province_count == 0 or d.allied(c.id, r.player_id):
			continue
		if r.diplomacy.at_war(c.id, r.player_id) or randf() > float(_cfg("alliance_offer_chance", 0.04)):
			continue
		for e in enemies:
			if r.diplomacy.at_war(c.id, e):
				d.extra_allies[CampaignDiplomacy._key(c.id, r.player_id)] = true
				r.message.emit(Loc.t("occ.alliance", [Loc.country(c), Loc.country(d.countries.get(e))]))
				break


## O'yinchi g'alabasi: dunyo hududlari ulushi yoki kapitulyatsiyalar (rules.json -> victory, rejim bo'yicha).
func progress() -> Dictionary:
	var v: Dictionary = (r.data.rule("victory", {}) as Dictionary).get(str(r.setup.get("mode", "standard")), {"world_share": 0.2, "capitulations": 3})
	var pc: CountryData = r.data.countries.get(r.player_id)
	var share := float(pc.province_count) / maxf(1.0, r.data.provinces.size()) if pc else 0.0
	return {"share": share, "need_share": float(v.get("world_share", 0.2)), "caps": int(capitulations.get(r.player_id, 0)),
		"need_caps": int(v.get("capitulations", 0))}


func check_victory() -> void:
	if r.phase != "play":
		return
	var p := progress()
	if p.share >= p.need_share or (p.need_caps > 0 and p.caps >= p.need_caps):
		r.phase = "over"
		r.message.emit(Loc.t("occ.victory", [Loc.country(r.data.countries[r.player_id])]))


func to_dict() -> Dictionary:
	return {"unrest": unrest, "prev": prev_owner, "sanctions": sanctions, "caps": capitulations, "home": home_capital}


func from_dict(s: Dictionary) -> void:
	var all := {"unrest": unrest, "prev": prev_owner, "sanctions": sanctions, "caps": capitulations, "home": home_capital}
	for k in all:
		var src: Dictionary = s.get(k, {})
		var dst: Dictionary = all[k]
		dst.clear()
		for key in src:
			dst[int(key)] = int(src[key])
