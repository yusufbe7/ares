## SURVIVAL (like the Defilade demo): defend the village behind the trench line.
## Build phase: select soldiers and dig in - sandbags, barriers, hedgehogs, barbed wire, camo nets, MG nests.
## Then waves of insurgents attack (from wave 2 FPV drones, from wave 3 tanks). Survive 5 waves.
class_name SurvivalMode
extends Node

const WAVES := 5
const BUILD_TIME := 90.0
const BREAK_TIME := 40.0
const DEFEND := Vector3(35, 0, -100)           # south edge of the village
const SPAWNS := [Vector2(240, 110), Vector2(140, 260), Vector2(275, -30), Vector2(-60, 270)]
const REINF := Vector2(25, -205)                # reinforcements arrive behind the village
const TABS := {"DEFENCES": ["trench", "sandbags", "hesco", "bunker", "barriers", "wire", "hedgehog", "camo", "mg"], "SUPPORT": ["artillery", "drone"]}
const ZONE := 140.0

var demo: Node3D
var hud: RtsHud
var phase := "build"          # build | wave | break | won | lost
var wave := 0
var timer := BUILD_TIME
var supply := 700.0
var enemies_left := 0
var cooldowns := {}
var _spawn_queue: Array = []
var _spawn_t := 0.0
var _drone_t := 0.0
var _drones_left := 0
var _tank_t := 0.0
var _man_t := 0.0
var _ui_t := 0.0


func setup(p_demo: Node3D) -> void:
	demo = p_demo
	var map: Node3D = demo.map
	map.clear_trees(DEFEND + Vector3(20, 0, 35), 40.0)      # open field of fire south of the village
	var med := Marker3D.new()
	med.add_to_group("medical")
	demo.add_child(med)
	med.global_position = Vector3(30, demo.ground_height(30, -170), -170)
	# defenders: in cover along the south-facing walls of the houses
	var cover: Array = demo.house_covers(DEFEND + Vector3(40, 0, 80))
	var n := 14
	var sid := -1
	for i in n:
		if i % 4 == 0:
			sid = demo.new_squad(["Alpha", "Bravo", "Charlie", "Delta"][i / 4])
		var c: Node3D = cover[i % cover.size()]
		var p: Vector3 = c.global_position + Vector3(randf_range(-1.0, 1.0), 0, -1.0)
		var s: RtsSoldier = demo._soldier(p.x, p.z, 160, 0, i == 3 or i == 10, sid)
		if i in [2, 6, 11]: s.rpg_rounds = 4
		s.move_to(c.global_position)
	var nest := Marker3D.new()
	demo.add_child(nest)
	nest.global_position = Vector3(DEFEND.x, demo.ground_height(DEFEND.x, DEFEND.z), DEFEND.z)
	nest.add_to_group("cover")
	var g: RtsSoldier = demo._soldier(DEFEND.x, DEFEND.z - 1.5, 160, 0, false, demo.new_squad("MG"))
	ConquestMode._make_mg(g)
	g.move_to(DEFEND + Vector3(0, 0, -0.6))
	var t := demo._unit(RtsTank, "t72.glb", 10, -125, 150) as RtsTank
	if t:
		t.team = 0
		t.max_hp = 160.0
		t.hp = 160.0
		t.add_to_group("player_units")
	hud = RtsHud.new()
	hud.title = "SURVIVAL"
	hud.subtitle = "HOLD THE VILLAGE"
	demo.add_child(hud)
	hud.setup(demo, self, TABS)
	var go := Button.new()
	go.text = "READY - START THE WAVE"
	go.focus_mode = Control.FOCUS_NONE
	go.custom_minimum_size = Vector2(0, 40)
	go.add_theme_stylebox_override("normal", RtsHud._sb(Color(0.45, 0.22, 0.08), RtsHud.ORANGE, 1))
	go.pressed.connect(func(): if phase in ["build", "break"]: timer = 0.0)
	hud._side.get_child(0).add_child(go)
	hud.set_meta("go", go)
	demo.placer.validator = _validate
	demo.placer.placed.connect(_on_placed)
	demo.placer.target_picked.connect(_on_target)
	demo.cam.position = Vector3(DEFEND.x + 10, demo.ground_height(DEFEND.x, DEFEND.z), DEFEND.z + 15)
	demo.cam.distance = 100.0
	hud.notify("Dig in! Select soldiers, choose a defence, click to place. They build it on site.", Color(0.6, 1.0, 0.65))


# ------------------------------------------------------------------ HUD interface
func hud_item_state(key: String) -> Dictionary:
	var d := BuildDefs.get_def(key)
	if BuildDefs.SUPPORT.has(key):
		var cd: float = cooldowns.get(key, 0.0)
		if cd > 0.0:
			return {"ok": false, "reason": "%ds" % int(ceil(cd)), "progress": 1.0 - cd / float(d.cooldown)}
	if supply < d.cost:
		return {"ok": false, "reason": "NEED %d" % d.cost}
	return {"ok": true}


func hud_click(key: String) -> void:
	if not hud_item_state(key).ok:
		return
	if key == "trench":
		demo.placer.begin_trench()
	elif BuildDefs.STRUCTURES.has(key):
		demo.placer.begin(key, [[DEFEND, ZONE]])
	else:
		demo.placer.begin_target(key, 14.0 if key == "artillery" else 4.0)


func _validate(key: String, p: Vector3, yaw: float) -> String:
	var d: Dictionary = BuildDefs.STRUCTURES[key]
	if supply < d.cost:
		return "not enough supply"
	if Vector2(p.x - DEFEND.x, p.z - DEFEND.z).length() > ZONE:
		return "outside the defence zone"
	if not RtsNav.walkable(p):
		return "water"
	var r: float = maxf(d.size.x, d.size.y) * 0.5
	for s in demo.get_tree().get_nodes_in_group("structures"):
		var dist := Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length()
		if dist < (r + maxf(s.def.size.x, s.def.size.y) * 0.5) * 0.75:
			return "blocked"
	return ""


func _on_placed(key: String, p: Vector3, yaw: float) -> void:
	var d: Dictionary = BuildDefs.STRUCTURES[key]
	supply -= d.cost
	var site := RtsStructure.create(demo, key, p, yaw, 0)
	site.completed.connect(func(s):
		hud.notify("%s ready." % s.def.name, Color(0.6, 1.0, 0.65))
		if s.def.get("gunner", false):
			var gg: RtsSoldier = demo._soldier(s.global_position.x - 1.5, s.global_position.z, 90, 0, false, demo.new_squad("MG"))
			ConquestMode._make_mg(gg)
			gg.move_to(s.global_position + Vector3(-1.2, 0, 0)))
	var men: Array = demo.commander.soldiers_selected()
	if men.is_empty():
		var idle: Array = demo.get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0 and s.can_fight() and s.work_site == null and s.fire_interval > 0.1)
		idle.sort_custom(func(a, b): return a.global_position.distance_to(p) < b.global_position.distance_to(p))
		men = idle.slice(0, 3)
	site.assign(men)


func _on_target(key: String, p: Vector3) -> void:
	var d: Dictionary = BuildDefs.SUPPORT[key]
	supply -= d.cost
	cooldowns[key] = float(d.cooldown)
	if key == "drone":
		var dr := RtsDrone.launch(demo, Vector3(REINF.x, demo.ground_height(REINF.x, REINF.y) + 16, REINF.y), 0)
		dr.goal = p
	else:
		for i in 6:
			var off := Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
			demo.get_tree().create_timer(2.5 + i * 0.7).timeout.connect(func():
				var q := p + off
				RtsExplosion.spawn(demo, Vector3(q.x, demo.ground_height(q.x, q.z), q.z), 1.6))


# ------------------------------------------------------------------ waves
func _start_wave() -> void:
	wave += 1
	phase = "wave"
	demo.placer.cancel()
	hud.big("WAVE %d" % wave)
	demo.get_tree().create_timer(3.0).timeout.connect(func(): if phase == "wave": hud.big(""))
	var count := 5 + wave * 3
	for i in count:
		_spawn_queue.append(SPAWNS[i % (2 if wave < 3 else SPAWNS.size())])
	_spawn_t = 0.0
	_drones_left = maxi(0, wave - 1) * 2
	_drone_t = 12.0
	var tanks := 0 if wave < 3 else (1 if wave < 5 else 2)
	for k in tanks:
		var sp: Vector2 = SPAWNS[k]
		var t := demo._unit(RtsTank, "tank_enemy.glb", sp.x, sp.y + k * 15, -40) as RtsTank
		if t:
			t.team = 1
			t.wheel_radius = 0.36
			t.move_to(DEFEND + Vector3(randf_range(40, 90), 0, randf_range(60, 100)))
			demo.enemy_tanks.append(t)


func _spawn_one(sp: Vector2) -> void:
	var p := Vector2(sp.x + randf_range(-25, 25), sp.y + randf_range(-25, 25))
	var e: RtsSoldier = demo._soldier(p.x, p.y, -40, 1, randf() < 0.08)
	e.objective = DEFEND + Vector3(randf_range(-60, 60), 0, randf_range(-50, 10))
	if randf() < 0.12: e.rpg_rounds = 2
	e.accuracy = 0.36
	var to := (DEFEND - Vector3(p.x, 0, p.y)).normalized()
	e.move_to(Vector3(p.x, 0, p.y) + to * 40.0)


## Soldiers standing idle in the open go back into a free trench slot.
func _man_trench() -> void:
	var slots: Array = []
	for c in demo.get_tree().get_nodes_in_group("cover"):
		if c.has_meta("omni"):
			slots.append(c)
	for s in demo.squad:
		if not is_instance_valid(s) or s.state != RtsSoldier.State.IDLE or s.fire_interval < 0.1 or s.work_site != null or s._order_t > 0.0:
			continue
		var best: Node3D = null
		var bd := 250.0
		for c in slots:
			var cp: Vector3 = (c as Node3D).global_position
			var taken := false
			for o in demo.squad:
				if o != s and is_instance_valid(o) and (o as Node3D).global_position.distance_to(cp) < 1.6:
					taken = true; break
			if taken: continue
			var d: float = cp.distance_to(s.global_position)
			if d < bd: bd = d; best = c
		if best:
			slots.erase(best)
			s.move_to(best.global_position + Vector3(-0.3, 0, 0))
			s._order_t = 0.0


## Enemy tanks keep closing in on the nearest defender until it is in gun range.
func _tanks_hunt() -> void:
	for t in demo.enemy_tanks:
		if not is_instance_valid(t) or t.destroyed or t._move_target != null:
			continue
		var best: Node3D = null
		var bd := INF
		for u in demo.get_tree().get_nodes_in_group("soldiers") + demo.get_tree().get_nodes_in_group("tanks"):
			if u.get("team") != 0 or (u.has_method("can_fight") and not u.can_fight()) or u.get("destroyed") == true:
				continue
			var d: float = (u as Node3D).global_position.distance_to(t.global_position)
			if d < bd: bd = d; best = u
		if best and bd > 90.0:
			var bp: Vector3 = best.global_position
			t.move_to(bp + (t.global_position - bp).normalized() * 70.0)


func _count_enemies() -> int:
	var n := _spawn_queue.size()
	for e in demo.enemies:
		if is_instance_valid(e) and (e as RtsSoldier).can_fight():
			n += 1
	for t in demo.enemy_tanks:
		if is_instance_valid(t) and not t.destroyed:
			n += 1
	return n


func _process(delta: float) -> void:
	if demo == null:
		return
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	match phase:
		"build", "break":
			timer -= delta
			_man_t -= delta
			if _man_t <= 0.0:
				_man_t = 3.0
				_man_trench()
			if timer <= 0.0:
				_start_wave()
		"wave":
			_spawn_t -= delta
			if _spawn_t <= 0.0 and not _spawn_queue.is_empty():
				_spawn_t = 0.6
				_spawn_one(_spawn_queue.pop_front())
			_drone_t -= delta
			if _drones_left > 0 and _drone_t <= 0.0:
				_drone_t = randf_range(10.0, 18.0)
				_drones_left -= 1
				var sp: Vector2 = SPAWNS[randi() % 2]
				RtsDrone.launch(demo, Vector3(sp.x, demo.ground_height(sp.x, sp.y) + 15.0, sp.y), 1)
			_tank_t -= delta
			if _tank_t <= 0.0:
				_tank_t = 4.0
				_tanks_hunt()
			enemies_left = _count_enemies()
			if enemies_left == 0:
				if wave >= WAVES:
					phase = "won"
					hud.big("VICTORY\nThe village holds")
				else:
					phase = "break"
					timer = BREAK_TIME
					supply += 350
					hud.notify("Wave beaten! +350 supply, +4 reinforcements", Color(0.6, 1.0, 0.65))
					var sid: int = demo.new_squad("Reinforcements")
					for k in 4:
						var s: RtsSoldier = demo._soldier(REINF.x + k * 2.0, REINF.y, 180, 0, false, sid)
						s.move_to(DEFEND + Vector3(randf_range(-40, 40), 0, randf_range(-25, -5)))
	if phase in ["wave", "break", "build"] and demo._alive(demo.squad).is_empty():
		phase = "lost"
		hud.big("DEFEAT\nAll soldiers are down")
	_ui_t -= delta
	if _ui_t <= 0.0:
		_ui_t = 0.25
		_update_ui()


func _update_ui() -> void:
	hud.set_supply(supply, 0.0)
	hud.refresh()
	var t := "%d:%02d" % [int(timer) / 60, int(timer) % 60]
	match phase:
		"build": hud.set_banner("BUILD PHASE  %s   |   wave %d of %d next" % [t, wave + 1, WAVES])
		"break": hud.set_banner("BREAK  %s   |   wave %d of %d next" % [t, wave + 1, WAVES])
		"wave": hud.set_banner("WAVE %d / %d   |   ENEMIES LEFT %d" % [wave, WAVES, enemies_left])
		"won": hud.set_banner("VICTORY")
		"lost": hud.set_banner("DEFEAT")
	var go: Button = hud.get_meta("go")
	go.visible = phase in ["build", "break"]
	var men: int = demo._alive(demo.squad).size()
	var sel: Array = demo.commander.selection
	hud.set_men(men, "SELECTED %d" % sel.size() if not sel.is_empty() else "")
	var marks: Array = []
	for s in demo.get_tree().get_nodes_in_group("structures"):
		marks.append([s.global_position, Color(0.35, 0.85, 1.0), 6.0])
	for s in demo._alive(demo.squad):
		marks.append([s.global_position, Color(0.45, 1.0, 0.5), 3.0])
	for e in demo._alive(demo.enemies):
		marks.append([e.global_position, Color(1.0, 0.25, 0.2), 3.0])
	hud.set_marks(marks)
