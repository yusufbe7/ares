## Strategik xarita sinovi: godot --headless --path . -s res://tests/test_campaign.gd
extends SceneTree

var m  ## tipsiz: sahna skriptlari autoload (EventBus) yuklangandan keyin kompilyatsiya qilinadi
var f := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	if not cond: fails += 1
	print(("OK    " if cond else "XATO  ") + what)


func _initialize() -> void:
	Loc.set_lang("en", false)
	root.get_node("GameSession").campaign_setup = {}          # davlat tanlash ekranisiz: xaritada tanlash
	DirAccess.remove_absolute("user://campaign_setup.json")
	var t0 := Time.get_ticks_msec()
	m = (load("res://campaign/campaign_map.tscn") as PackedScene).instantiate()
	root.add_child(m)
	print("yuklash ms: ", Time.get_ticks_msec() - t0)


func pid_at(lon: float, lat: float) -> int:
	var d: CampaignData = m.data
	var px := Vector2i(int((lon - d.meta.lon_min) / (d.meta.lon_max - d.meta.lon_min) * d.width), int((d.meta.lat_max - lat) / (d.meta.lat_max - d.meta.lat_min) * d.height))
	return d.id_at(px)


func _process(_d: float) -> bool:
	f += 1
	if f != 3:
		return false
	var d: CampaignData = m.data
	var r: CampaignRules = m.rules
	# 1. relyef (butun dunyo)
	ok(d.width == 4320 and d.height == 1704, "height.png o'lchami %dx%d" % [d.width, d.height])
	var hp := func(lon: float, lat: float) -> float:
		return d.height_at(Vector2i(int((lon + 180.0) / 360.0 * d.width), int((84.0 - lat) / 142.0 * d.height)))
	ok(hp.call(86.9, 27.98) > 5000.0, "Himoloy baland: %d m" % hp.call(86.9, 27.98))
	ok(hp.call(18.0, 35.0) < -1000.0, "O'rta yer dengizi chuqur: %d m" % hp.call(18.0, 35.0))
	# 2. hududlar
	ok(d.provinces.size() > 1000 and d.countries.size() > 150, "hududlar: %d, davlatlar: %d" % [d.provinces.size(), d.countries.size()])
	var tash := 0
	for p in d.provinces.values():
		if p.name == "Tashkent": tash = p.id
	ok(tash > 0 and d.countries[d.provinces[tash].owner].code == "UZB", "Toshkent hududi topildi: id %d" % tash)
	var tp: ProvinceData = d.provinces[tash]
	ok(tp.neighbors.size() > 0, "Toshkent qo'shnilari: %s" % [Array(tp.neighbors).map(func(i): return d.provinces[i].name)])
	# 5. tanlash
	m.cam.focus(m.province_world(tash))
	m.cam.distance = 40.0
	m.cam._target_dist = 40.0
	m.cam._update()
	var picked: int = m.province_at_screen(m.cam.camera.unproject_position(m.province_world(tash)))
	ok(picked == tash, "sichqoncha bilan tanlash: %d" % picked)
	# tanlash ekrani
	m._process(0.016)
	ok(m.armies_ui.clusters.is_empty(), "tanlash ekranida qo'shin belgilari yashirin")
	m._hover(tash)
	ok(m.hover_owner == m._country_by_code("UZB"), "hover: %s" % Loc.country(d.countries.get(m.hover_owner)))
	# davlat nomlari o'z hududi ichida
	var inside := 0
	var codes := ["FRA", "GRC", "ITA", "GBR", "RUS", "UZB", "TUR", "ESP", "USA", "CHN", "BRA", "JPN", "IDN", "CAN", "AUS"]
	for code in codes:
		var l: Label3D = m.labels.country_label(m._country_by_code(code))
		if m.owner_of(d.id_at(m.world_to_px(l.position))) == m._country_by_code(code): inside += 1
		else: print("      tashqarida: ", code)
	ok(inside == codes.size(), "davlat nomlari o'z hududi ichida: %d / %d" % [inside, codes.size()])
	# til
	var uzb: int = m._country_by_code("UZB")
	var txt := []
	for lang in ["uz", "ru", "en"]:
		Loc.set_lang(lang, false); m.apply_language(); m.labels.update([])
		txt.append(m.labels.country_label(uzb).text)
	ok(txt == ["O'ZBEKISTON", "УЗБЕКИСТАН", "UZBEKISTAN"], "til almashadi (tr): %s" % [txt])
	ok(tr("end_turn") == "End Turn", "tr() ishlaydi: " + tr("end_turn"))
	# 3 / 9. conquer: faqat info teksturasi o'zgaradi
	var kaz: int = m._country_by_code("KAZ")
	m.conquer(tash, kaz)
	m._process(0.016)
	var px: Color = m.terrain.info_img.get_pixel(tash, 1)
	ok(d.provinces[tash].owner == kaz and px.r8 + px.g8 * 256 == kaz, "conquer(): Toshkent Qozog'istonga o'tdi, info teksturasi yangilandi")
	m.conquer(tash, uzb)
	# 6. davlat tanlash, missiyalar
	m.choose_country(uzb)
	ok(r.phase == "play" and r.missions.targets.size() == r.missions.list.size() and r.missions.list.size() == 5, "davlat tanlandi, 5 missiya, maqsadlar aniqlandi")
	var army: ArmyData = m.army_in(d.countries[uzb].capital)
	ok(army != null, "poytaxtda qo'shin: %d polk" % (army.size if army else 0))
	# diplomatiya: urushsiz hujum yo'q
	var enemy := 0
	for n in tp.neighbors:
		if d.provinces[n].owner != uzb: enemy = n
	army.size = 60
	ok(not m.order_move(army, enemy), "urush e'lon qilinmagan davlatga hujum qilib bo'lmaydi")
	var eo: int = d.provinces[enemy].owner
	ok(r.declare_war(uzb, eo) and r.diplomacy.at_war(uzb, eo), "urush e'lon qilindi: %s" % Loc.country(d.countries[eo]))
	var gold0 := int(d.countries[uzb].resources.gold)
	ok(m.order_move(army, enemy) and d.provinces[enemy].owner == uzb, "hujum: %s egallandi" % d.provinces[enemy].name)
	ok(r.missions.done.has("m01_border_fire") and int(d.countries[uzb].resources.gold) > gold0, "1-missiya bajarildi (urush + jang), mukofot berildi")
	# tension
	var tsum := 0.0
	for row in CampaignTension.compute(d):
		tsum += row.share
	ok(absf(tsum - 1.0) < 0.01, "Global Tension ulushlari yig'indisi 100%%: %.3f" % tsum)
	# dengiz yo'llari: Sitsiliya, Kipr, Britaniya
	for isl in [["Sicily", 14.2, 37.5], ["Cyprus", 33.2, 35.1], ["Britain", -1.5, 52.8]]:
		var ip := pid_at(isl[1], isl[2])
		ok(ip > 0 and not d.provinces[ip].sea.is_empty(), "%s dengiz orqali bog'langan: %s" % [isl[0], d.provinces[ip].sea.keys().map(func(k): return d.provinces[k].name) if ip > 0 else "-"])
	var sic := pid_at(14.2, 37.5)
	# poytaxt emas (poytaxt olinsa davlat taslim bo'ladi va urush tugaydi)
	var caps: Array = d.countries.values().map(func(c): return c.capital)
	var src: int = d.provinces[sic].sea.keys().filter(func(k): return not (int(k) in caps))[0]
	d.bases = d.bases.filter(func(b): return b.province != src and b.province != sic)   # bosib olingan baza ta'minot beradi
	var marine := r.new_army(uzb, src, 80)
	var so: int = d.provinces[sic].owner
	r.declare_war(uzb, so)
	if d.allied(uzb, d.provinces[src].owner) == false and d.provinces[src].owner != uzb:
		r.conquer(src, uzb)
	ok(m.order_move(marine, sic) and d.provinces[sic].owner == uzb and marine.busy == 1, "dengiz orqali Sitsiliyaga desant (qo'shin keyingi yurish ham band)")
	r.supply.update()
	ok(not marine.supplied and not r.supply.routes[marine.id].ok and r.supply.factor(marine) < 1.0, "ta'minot uzildi: yo'l qizil, kuch jarimasi %.0f%%" % (100 - r.supply.factor(marine) * 100))
	ok(army.supplied, "poytaxtga ulangan qo'shin ta'minlangan")
	ok(r.conflicts().size() >= 2, "ziddiyat nuqtalari (jang log'idan): %d" % r.conflicts().size())
	# qo'shin belgilari: uzoqda birlashadi
	m.cam.distance = 150.0; m.cam._update()
	m.labels.update([]); m.armies_ui.rebuild()
	var merged: int = m.armies_ui.clusters.filter(func(c): return c.armies.size() > 1).size()
	m.cam.distance = 10.0; m.cam._update()
	m.labels.update([]); m.armies_ui.rebuild()
	var near_merged: int = m.armies_ui.clusters.filter(func(c): return c.armies.size() > 1).size()
	ok(merged > 0 and near_merged < merged, "belgilar uzoqda birlashadi (%d), yaqinda ajraladi (%d)" % [merged, near_merged])
	# saqlash / yuklash
	var snap := CampaignSave.to_dict(r)
	m.conquer(tash, kaz)
	ok(CampaignSave.from_dict(r, JSON.parse_string(JSON.stringify(snap))) and d.provinces[tash].owner == uzb, "kampaniya saqlanadi va tiklanadi")
	# UI
	var scr = m.ui
	ok(scr.bottom.get_child_count() == 4, "pastda 4 panel")
	var bus: Node = root.get_node("EventBus")
	bus.map_option_changed.emit("borders", false)
	bus.map_view_changed.emit(1)
	ok(m.terrain.mat.get_shader_parameter("show_borders") == false and m.terrain.mat.get_shader_parameter("view_mode") == 1, "MAP OPTIONS / MAP VIEW shaderni o'zgartiradi")
	# yurishlar
	var t1 := Time.get_ticks_msec()
	for k in 5: m.end_turn()
	print("5 ta yurish ms: ", Time.get_ticks_msec() - t1, "   urushlar: ", r.diplomacy._wars.size())
	ok(r.turn == 6 and r.history.size() == 5, "yurishlar va iqtisod tarixi")
	print("XATOLAR: ", fails)
	return true
