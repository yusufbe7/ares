## To'liq oqim: davlat tanlash -> kampaniya -> hujum rejasi -> xaritada harakat -> 3D jang (intro) -> natija kampaniyada.
## godot --headless --path . -s res://tests/test_flow.gd
extends SceneTree

var fails := 0
var sm
var gs


func ok(cond: bool, what: String) -> void:
	if not cond: fails += 1
	print(("OK    " if cond else "XATO  ") + what)


func _initialize() -> void:
	_run.call_deferred()


func wait_scene(name_has: String, max_frames := 4000) -> Node:
	for k in max_frames:
		await process_frame
		if current_scene and str(current_scene.scene_file_path).contains(name_has) and current_scene.is_node_ready():
			return current_scene
	return null


func _run() -> void:
	sm = root.get_node("ScreenManager")
	gs = root.get_node("GameSession")
	Loc.set_lang("en", false)
	gs.setup_shown = true
	gs.campaign_setup = {"country": "FRA", "mode": "standard", "difficulty": 2, "ironman": false, "no_blocs": true}
	sm.open_campaign(-1)
	var map = await wait_scene("campaign_map")
	for k in 5: await process_frame
	ok(map != null and map.rules.player_id == int(map.data.by_code.FRA), "kampaniya tanlangan davlat bilan boshlandi (FRA)")
	var r: CampaignRules = map.rules
	var d: CampaignData = map.data
	var esp := int(d.by_code.ESP)
	r.declare_war(r.player_id, esp)
	var target := 0
	var src := 0
	for p in d.provinces.values():
		if p.owner != r.player_id: continue
		for n in p.neighbors:
			if d.provinces[n].owner == esp: src = p.id; target = n
	var a: ArmyData = r.army_in(src)
	if a == null: a = r.new_army(r.player_id, src, 12)
	a.size = 12
	d.countries[r.player_id].resources.supply = 200
	map.select_province(src)
	map.plan_or_move(a, target)
	var w: AttackPlan = map.ui.root.get_children().filter(func(c): return c is AttackPlan).back()
	ok(w != null and w._method == "land" and not w._go.disabled, "hujum rejasi ochildi, quruqlik tanlandi")
	w._slider.value = 8
	w._fast.button_pressed = true
	w._auto.button_pressed = false
	w._launch()
	ok(map.runner.busy(), "qo'shin xaritada harakatlanmoqda")
	ok(a.size == 4, "qolgan qo'shin joyida: %d" % a.size)
	var demo = await wait_scene("demo.tscn")
	for k in 5: await process_frame
	ok(demo != null and not demo.map.spec.is_empty(), "jang maydoni generatsiya qilindi: " + str(gs.battle_request.get("biome", "?")))
	var intro = demo.get_children().filter(func(c): return c is BattleIntro)
	ok(not intro.is_empty() and paused, "intro: pauza, kamera aylanmoqda")
	ok(demo.mode_node.reserve[0] + demo.mode_node._field(0) == BattleBridge.men_for(gs.battle_request)[0], "askarlar polklardan: %d" % BattleBridge.men_for(gs.battle_request)[0])
	intro[0]._start()
	ok(not paused, "JANGNI BOSHLASH -> pauza yechildi")
	for k in 30: await process_frame
	demo.mode_node.reserve[1] = 0
	for e in demo.enemies: if is_instance_valid(e): e.queue_free()
	demo.mode_node._finish(true, "test")
	map = await wait_scene("campaign_map", 8000)
	for k in 8: await process_frame
	ok(map != null and map.data.provinces[target].owner == map.rules.player_id, "natija qo'llandi: hudud bizniki")
	ok(gs.battle_request.is_empty(), "jang so'rovi tozalandi")
	print("DONE fails=%d" % fails)
	quit(fails)
