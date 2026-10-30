## Hujum operatsiyalari sinovi: godot --headless --path . -s res://tests/test_war_ops.gd
extends SceneTree

var fails := 0


func ok(cond: bool, what: String) -> void:
	if not cond: fails += 1
	print(("OK    " if cond else "XATO  ") + what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Loc.set_lang("en", false)
	var d := CampaignData.new()
	d.load_all()
	var r := CampaignRules.new(d)
	var ops := CampaignWarOps.new(r)
	# biomlar taqsimoti
	var cnt := {}
	for pid in d.provinces:
		var b := ops.biome_for(pid)
		cnt[b] = int(cnt.get(b, 0)) + 1
	print("biomlar: ", cnt)
	ok(cnt.size() == 7, "7 xil biom uchraydi")
	var name_b := func(n: String) -> String:
		for p in d.provinces.values():
			if p.name == n: return ops.biome_for(p.id)
		return "?"
	print("Paris=%s  Tashkent=%s  Riyadh=%s  Murmansk=%s  Tibet=%s" % [name_b.call("Paris"), name_b.call("Tashkent"),
		name_b.call("Ar Riyad"), name_b.call("Murmansk"), name_b.call("Xizang")])
	# sozlamalar
	r.player_id = int(d.by_code.FRA)
	r.apply_setup({"country": "FRA", "difficulty": 3, "no_blocs": true}, true)
	r.choose_country(r.player_id)
	ok(d.countries[r.player_id].bloc == "", "no_blocs: bloklar o'chdi")
	ok(float(d.rule("bot_attack_ratio", 0)) == 1.1, "qiyinlik 3: bot_attack_ratio")
	# quruqlik hujumi: Fransiya -> Ispaniya
	var esp := int(d.by_code.ESP)
	var fra := r.player_id
	var a: ArmyData = null
	var target := 0
	for x in d.armies:
		if x.owner != fra: continue
		for n in d.provinces[x.province].neighbors:
			if d.provinces[n].owner == esp:
				a = x; target = n
	if a == null:
		var pid := 0
		for p in d.provinces.values():
			if p.owner != fra: continue
			for n in p.neighbors:
				if d.provinces[n].owner == esp: pid = p.id; target = n
		a = r.new_army(fra, pid, 8)
	a.size = maxi(a.size, 8)
	var ck := ops.check(a, target)
	ok(not ck.ok and ck.reason == "op.not_at_war", "urushsiz hujum yo'q: " + ck.reason)
	r.declare_war(fra, esp)
	d.countries[fra].resources.supply = 100
	ck = ops.check(a, target)
	ok(ck.methods.land.ok, "quruqlik ochiq")
	ok(not ck.methods.air.ok, "havo: " + ck.methods.air.reason)
	var before := a.size
	var op := ops.launch(a, target, "land", 5)
	ok(not op.is_empty() and op.count == 5 and a.size == before - 5, "qo'shin bo'lindi: %d qoldi, %d hujumda" % [a.size, op.get("count", 0)])
	ok(int(d.countries[fra].resources.supply) == 95, "ta'minot to'landi")
	ok(op.biome in ["temperate", "mountain", "forest", "coast", "city", "desert", "winter"], "maydon: " + op.biome)
	op.army.size = 40
	var won := ops.resolve_auto(op)
	ok(won and d.provinces[target].owner == fra, "avto-jang: hudud olindi")
	# 3D natija
	var t2 := 0
	for n in d.provinces[target].neighbors:
		if d.provinces[n].owner == esp: t2 = n
	if t2 > 0:
		op.army.moved = false
		var op2 := ops.launch(op.army, t2, "land", 3)
		ops.apply_result(op2, {"won": false, "att_left": 1, "def_left": 2})
		ok(d.provinces[t2].owner == esp and op2.army.size == 1, "3D mag'lubiyat qo'llandi")
	print("DONE fails=%d" % fails)
	quit(fails)
