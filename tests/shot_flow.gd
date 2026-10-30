## Skrinshotlar (xvfb + vulkan): davlat tanlash, hujum rejasi, jang introsi -> user://shots/flow_*.png
extends SceneTree

var sm
var gs


func _initialize() -> void:
	_run.call_deferred()


func shot(name: String, frames := 6) -> void:
	for k in frames:
		await process_frame
	DirAccess.make_dir_recursive_absolute("user://shots")
	root.get_texture().get_image().save_png("user://shots/flow_%s.png" % name)
	print("shot ", name)


func wait_scene(name_has: String) -> Node:
	for k in 6000:
		await process_frame
		if current_scene and str(current_scene.scene_file_path).contains(name_has) and current_scene.is_node_ready():
			return current_scene
	return null


func _run() -> void:
	sm = root.get_node("ScreenManager")
	gs = root.get_node("GameSession")
	Loc.set_lang("en", false)
	gs.setup_shown = false
	change_scene_to_file("res://ui/main.tscn")
	await wait_scene("main.tscn")
	await shot("country", 30)
	gs.campaign_setup = {"country": "FRA", "mode": "standard", "difficulty": 2, "no_blocs": true}
	sm.open_campaign(-1)
	var map = await wait_scene("campaign_map")
	for k in 10: await process_frame
	var r = map.rules
	var d = map.data
	var esp := int(d.by_code.ESP)
	r.declare_war(r.player_id, esp)
	var target := 0
	var src := 0
	for p in d.provinces.values():
		if p.owner != r.player_id: continue
		for n in p.neighbors:
			if d.provinces[n].owner == esp: src = p.id; target = n
	var a = r.army_in(src)
	if a == null: a = r.new_army(r.player_id, src, 12)
	a.size = 12
	d.countries[r.player_id].resources.supply = 120
	map.cam.focus(map.province_world(target))
	map.select_province(src)
	map.plan_or_move(a, target)
	await shot("attack_plan", 20)
	var w = map.ui.root.get_children().filter(func(c): return c is AttackPlan).back()
	w._fast.button_pressed = false
	w._launch()
	await shot("map_move", 60)
	var demo = await wait_scene("demo.tscn")
	await shot("intro", 40)
	var intro = demo.get_children().filter(func(c): return c is BattleIntro)[0]
	intro._t = 6.0
	await shot("intro2", 20)
	intro._start()
	await shot("battle", 40)
	quit()
