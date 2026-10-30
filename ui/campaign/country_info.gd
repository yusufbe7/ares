## Davlat tanlash ekrani uchun ma'lumot: countries.json, provinces.json, armies.json, bases.json, blocs.json dan
## (og'ir CampaignData rasmlarini yuklamasdan). Kuch (0..100): polklar soni va iqtisod (YaIM) aralashmasi.
class_name CountryInfo
extends RefCounted

static var _list: Array = []         ## [{country: CountryData, provinces, regiments, bases, strength, neighbours, capital_name}]
static var _by_id := {}


static func all() -> Array:
	if _list.is_empty():
		_build()
	return _list


static func get_info(cid: int) -> Dictionary:
	all()
	return _by_id.get(cid, {})


static func by_code(code: String) -> Dictionary:
	for e in all():
		if e.country.code == code:
			return e
	return {}


static func _build() -> void:
	var prov_owner := {}
	var prov_name := {}
	var counts := {}
	for p in CampaignData._json("res://data/provinces.json", []):
		prov_owner[int(p.id)] = int(p.owner)
		prov_name[int(p.id)] = str(p.name)
		counts[int(p.owner)] = int(counts.get(int(p.owner), 0)) + 1
	var regs := {}
	for a in CampaignData._json("res://data/armies.json", []):
		regs[int(a.owner)] = int(regs.get(int(a.owner), 0)) + int(a.size)
	var bases := {}
	for b in CampaignData._json("res://data/bases.json", []):
		var o: int = prov_owner.get(int(b.province), 0)
		bases[o] = int(bases.get(o, 0)) + 1
	var bloc_of := {}
	var blocs: Dictionary = CampaignData._json("res://data/blocs.json", {})
	for b in blocs.get("blocs", []):
		for m in b.members:
			bloc_of[str(m)] = str(b.name)
	var nb: Dictionary = CampaignData._json("res://data/neighbors.json", {})
	var max_r := 1.0
	var max_g := 1.0
	for c in CampaignData._json("res://data/countries.json", []):
		var cd := CountryData.new()
		cd.id = int(c.id); cd.code = str(c.code); cd.iso2 = str(c.get("iso2", "")); cd.name = str(c.name)
		cd.color = Color(str(c.color)); cd.capital = int(c.capital)
		cd.population = int(c.population); cd.gdp_musd = int(c.gdp_musd); cd.resources = c.get("resources", {})
		cd.bloc = bloc_of.get(cd.code, "")
		var e := {"country": cd, "provinces": int(counts.get(cd.id, 0)), "regiments": int(regs.get(cd.id, 0)),
			"bases": int(bases.get(cd.id, 0)), "capital_name": prov_name.get(cd.capital, "?"), "neighbours": []}
		max_r = maxf(max_r, e.regiments)
		max_g = maxf(max_g, log(1.0 + cd.gdp_musd))
		_list.append(e)
		_by_id[cd.id] = e
	# qo'shnilar: davlat hududlarining quruqlik qo'shnilari egalari
	for pid in prov_owner:
		var own: int = prov_owner[pid]
		if not _by_id.has(own):
			continue
		var land: Array = (nb.get(str(pid), {}) as Dictionary).get("land", [])
		for q in land:
			var o2: int = prov_owner.get(int(q), 0)
			if o2 != own and o2 != 0 and not (o2 in _by_id[own].neighbours):
				_by_id[own].neighbours.append(o2)
	# kuch: polklar va iqtisod aralashmasi bo'yicha o'rin (persentil) - 1..100 bo'ylab teng taqsimlanadi
	for e in _list:
		e.score = sqrt(float(e.regiments) / max_r) * 0.6 + log(1.0 + e.country.gdp_musd) / max_g * 0.4
	var ranked := _list.duplicate()
	ranked.sort_custom(func(a, b): return a.score < b.score)
	for k in ranked.size():
		ranked[k].strength = clampi(int(round(float(k + 1) / ranked.size() * 100.0)), 1, 100)
	_list.sort_custom(func(a, b): return Loc.country(a.country) < Loc.country(b.country))


## Avtomatik tavsif (Opis): aholi, hudud, poytaxt, iqtisod, kuch darajasi, qo'shnilar.
static func describe(e: Dictionary) -> String:
	var c: CountryData = e.country
	var t := Loc.t("cs.desc", [Loc.country(c), _big(c.population), e.provinces, e.capital_name,
		UiKit.num(int(round(c.gdp_musd / 1000.0)))])
	var tier := 1 if e.strength >= 85 else (2 if e.strength >= 50 else 3)
	t += "\n\n" + Loc.t("cs.size.%d" % tier)
	var names := []
	for n in e.neighbours.slice(0, 6):
		names.append(Loc.country(_by_id[n].country))
	if not names.is_empty():
		t += "\n\n" + Loc.t("cs.neighbours", [", ".join(names)])
	return t


static func bloc_members(bloc_name: String) -> Array:
	return all().filter(func(e): return e.country.bloc == bloc_name and bloc_name != "")


static func _big(n: int) -> String:
	if n >= 1000000:
		return "%.1f M" % (n / 1000000.0)
	if n >= 1000:
		return "%d K" % (n / 1000)
	return str(n)
