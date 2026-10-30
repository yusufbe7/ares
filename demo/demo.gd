## EUROPE FRONT RTS - the winter village battlefield from RTS_Battlefield (Blender) with the units of
## battlefield_rts: Ground Forces soldiers, insurgents, T-72s, the Mi-24, Humvees, FPV drones, F-117.
## Every village house is pre-fractured in Blender and really breaks apart (shells, rockets, bombs).
## Starts straight into the OPERATION (no menu). Other modes are kept for tests (_auto_mode):
##   VILLAGE ASSAULT - the battle from the video: tanks, a gunship and three squads take the village
##   CONQUEST        - build a base, train troops, take the village and the farms, destroy the stronghold
##   SURVIVAL        - hold the village against 5 waves (dig trenches first)
extends Node3D

const A := "res://assets/"
const MAP := "res://europe/europe_map.gd"

var map: EuropeMap
var cam: RtsCamera
var commander: RtsCommander
var placer: RtsPlacer
var mode := ""                 # "" (menu) | assault | conquest | survival
var mode_node: Node = null
var survival: Node = null      # kept for tests
var squad: Array = []          # every player soldier ever spawned
var enemies: Array = []        # every enemy soldier ever spawned
var enemy_tanks: Array = []
var units: Array = []          # assault vehicles
var debug_keys := false        ## 1-4 / Space = free explosions + air strike (assault only)
var info: Label
var status: Label
var _menu: Control
var _winter_box: CheckBox
var _squads: Array = []
var _won := false
var _wave_t := 75.0
var _waves := 0
static var _auto_mode := ""    ## tests: start a mode without the menu
static var _auto_winter := true


func ground_height(x: float, z: float) -> float:
	return map.get_height(x, z)


func _ready() -> void:
	map = EuropeMap.new()
	map.name = "EuropeMap"
	# kampaniya jangi: hududga mos maydon (cho'l, shahar, tog', o'rmon, qirg'oq...)
	var br: Dictionary = GameSession.battle_request
	if not br.is_empty():
		map.spec = BattleGen.generate(str(br.get("biome", "temperate")), int(br.get("seed", 1)))
	add_child(map)
	RtsGround.height_func = ground_height
	cam = RtsCamera.new()
	add_child(cam)
	cam.max_distance = 200.0
	cam.pitch_deg = 52.0
	cam.position = Vector3(20, ground_height(20, -110), -110)
	cam.rotation.y = deg_to_rad(-25.0)
	cam.distance = 120.0
	commander = RtsCommander.new()
	add_child(commander)
	commander.setup(self)
	placer = RtsPlacer.new()
	add_child(placer)
	placer.setup(self)
	placer.trench_validator = trench_validate
	placer.trench_placed.connect(on_trench_placed)
	# no main menu: straight into the operation (tests can still pick another mode)
	start(_auto_mode if _auto_mode != "" else _deploy_mode(), _auto_winter if _auto_mode != "" else bool(_deploy_opt("winter", _auto_winter)))
	var ph := PauseHandler.new()
	ph.demo = self
	add_child(ph)


# ------------------------------------------------------------------ menu
func _build_menu() -> void:
	commander.enabled = false
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	_menu = ColorRect.new()
	(_menu as ColorRect).color = Color(0.05, 0.05, 0.06, 0.5)
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(_menu)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -270; box.offset_right = 270; box.offset_top = -250
	box.add_theme_constant_override("separation", 12)
	_menu.add_child(box)
	var t := Label.new()
	t.text = "EUROPE FRONT"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", Color(0.96, 0.95, 0.92))
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	box.add_child(t)
	var st := Label.new()
	st.text = "GROUND FORCES  -  WINTER OPERATIONS"
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 16)
	st.add_theme_color_override("font_color", Color(0.95, 0.58, 0.18))
	box.add_child(st)
	for m in [["VILLAGE ASSAULT  -  Take the village", "assault", "Tanks, a Mi-24 and three squads storm the village. Houses break apart."],
			["CONQUEST  -  Take the valley", "conquest", "Build a base, train troops, take the village and the farms, destroy the stronghold."],
			["SURVIVAL  -  Hold the village (5 waves)", "survival", "Dig in before the waves hit: insurgents, drones, tanks."]]:
		var b := Button.new()
		b.text = m[0]
		b.tooltip_text = m[2]
		b.custom_minimum_size = Vector2(540, 54)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_stylebox_override("normal", RtsHud._sb(Color(0.16, 0.16, 0.17, 0.95), Color(0.4, 0.4, 0.42), 1))
		b.add_theme_stylebox_override("hover", RtsHud._sb(Color(0.24, 0.2, 0.15, 0.95), Color(0.95, 0.58, 0.18), 2))
		b.pressed.connect(func(): start(m[1], _winter_box.button_pressed))
		box.add_child(b)
	_winter_box = CheckBox.new()
	_winter_box.text = "Winter (snow)  -  press N in game to switch"
	_winter_box.button_pressed = true
	_winter_box.add_theme_font_size_override("font_size", 16)
	box.add_child(_winter_box)
	var q := Button.new()
	q.text = "Quit"
	q.pressed.connect(func(): get_tree().quit())
	box.add_child(q)


func start(p_mode: String, p_winter: bool) -> void:
	mode = p_mode
	if _menu:
		_menu.get_parent().queue_free()
		_menu = null
	commander.enabled = true
	map.set_winter(p_winter if map.spec.is_empty() else bool(map.spec.get("winter", false)))
	match mode:
		"operation":
			mode_node = OperationMode.new()
			var br: Dictionary = GameSession.battle_request
			mode_node.player_defends = bool(br.get("player_defends", false))
			add_child(mode_node)
			mode_node.setup(self)
			if not br.is_empty():
				# kampaniya jangi: zaxiralar polklar sonidan (BattleBridge.men_for)
				var men: Array = BattleBridge.men_for(br)
				mode_node.reserve = [maxi(0, men[0] - mode_node._field(0)), maxi(0, men[1] - mode_node._field(1))]
				BattleIntro.make(self, br)
			else:
				# OPERATIONS ekranidagi qiyinlik: dushman zaxirasi (oson 0.75x, o'rta 1x, qiyin 1.35x)
				mode_node.reserve[1] = int(OperationMode.RESERVE * float(_deploy_opt("enemy_reserve_mult", 1.0)))
		"conquest":
			mode_node = ConquestMode.new()
			add_child(mode_node)
			mode_node.setup(self)
		"survival":
			mode_node = SurvivalMode.new()
			survival = mode_node
			add_child(mode_node)
			mode_node.setup(self)
		_:
			mode = "assault"
			debug_keys = true
			_build_assault()
			_build_info()


# ------------------------------------------------------------------ trenches (all modes)
var _last_trench: RtsTrench = null


func trench_cost(a: Vector3, b: Vector3) -> int:
	return maxi(3, int(ceil(Vector2(b.x - a.x, b.z - a.z).length() * BuildDefs.TRENCH.cost)))


func trench_validate(a: Vector3, b: Vector3) -> String:
	var L := Vector2(b.x - a.x, b.z - a.z).length()
	if L < 2.5:
		return "too short"
	if mode_node and mode_node.get("supply") != null and mode_node.supply < trench_cost(a, b):
		return "not enough supply (%d)" % trench_cost(a, b)
	var dir := (b - a); dir.y = 0; dir = dir.normalized()
	var nrm := dir.cross(Vector3.UP)
	var n := int(L) + 1
	for k in n + 1:
		var c := a + (b - a) * (float(k) / n)
		for side in [-1.4, 0.0, 1.4]:
			var q: Vector3 = c + nrm * side
			if not RtsNav.walkable(q):
				return "a building in the way"
	for s in get_tree().get_nodes_in_group("structures"):
		var st: RtsStructure = s
		var r: float = maxf(st.def.size.x, st.def.size.y) * 0.5 + 1.5
		for k in n + 1:
			var c := a + (b - a) * (float(k) / n)
			if Vector2(c.x - st.global_position.x, c.z - st.global_position.z).length() < r:
				return "blocked by %s" % st.def.name
	var h0: float = map.ground_original(a.x, a.z)
	var h1: float = map.ground_original(b.x, b.z)
	if absf(h1 - h0) > L * 0.35:
		return "too steep"
	return ""


func on_trench_placed(a: Vector3, b: Vector3, joined: bool) -> void:
	var cost := trench_cost(a, b)
	if mode_node and mode_node.get("supply") != null:
		mode_node.supply -= cost
	map.clear_trees((a + b) * 0.5, a.distance_to(b) * 0.5 + 2.0)
	var t := RtsTrench.create(self, map, a, b, 0)
	if joined and is_instance_valid(_last_trench) and _last_trench.b.distance_to(Vector3(a.x, 0, a.z)) < 0.5:
		_last_trench.open_end = true
		_last_trench.links.append(t)
		t.links.append(_last_trench)
		_last_trench._update(true)
		t.open_start = true
		t._update(true)
	_last_trench = t
	t.completed.connect(func(_t): notify("Trench dug. Right-click it with soldiers selected to man it."))
	var men: Array = commander.soldiers_selected()
	if men.is_empty():
		var idle: Array = get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0 and s.can_fight() and s.work_site == null and s.fire_interval > 0.1)
		idle.sort_custom(func(x, y): return x.global_position.distance_to(a) < y.global_position.distance_to(a))
		men = idle.slice(0, mini(6, maxi(2, int(t.length() / 3.0))))
	else:
		men = men.filter(func(s): return s.work_site == null or not s.is_digging())
		if men.is_empty():
			men = commander.soldiers_selected().slice(0, 2)
	t.assign(men)
	commander.lines(men, t.global_position, Color(0.45, 1.0, 0.6, 0.9))


func notify(t: String) -> void:
	if mode_node and mode_node.get("hud") != null:
		mode_node.hud.notify(t)
	elif status:
		status.text = t
	else:
		print(t)


# ------------------------------------------------------------------ spawning
func new_squad(squad_name: String) -> int:
	_squads.append(squad_name)
	return _squads.size() - 1


## team 0 = player soldiers (soldier.glb), team 1 = insurgents (terrorist.glb, same animations)
func _soldier(x: float, z: float, yaw: float, team: int, medic := false, squad_id := -1) -> RtsSoldier:
	var s := RtsSoldier.new()
	s.team = team
	s.is_medic = medic
	var model := "terrorist.glb" if team == 1 and ResourceLoader.exists(A + "terrorist.glb") else "soldier.glb"
	var mdl: Node = load(A + model).instantiate()
	s.add_child(mdl)
	if team == 0:
		LoadoutApplier.apply_session(s, mdl)       # bosh menyuda tanlangan kiyim / kamuflyaj / qurol
	add_child(s)
	var p := RtsNav.nearest_walkable(Vector3(x, 0, z))
	s.position = Vector3(p.x, ground_height(p.x, p.z), p.z)
	s.rotation.y = deg_to_rad(yaw)
	if team == 0:
		s.add_to_group("player_units")
		s.set_meta("squad", squad_id if squad_id >= 0 else new_squad("Squad"))
		squad.append(s)
	else:
		enemies.append(s)
	return s


func _unit(script: Script, file: String, x: float, z: float, yaw := 0.0) -> Node3D:
	var path := A + file
	if not ResourceLoader.exists(path):
		push_warning("Missing model: " + path)
		return null
	var u: Node3D = script.new()
	u.add_child(load(path).instantiate())
	add_child(u)
	u.position = Vector3(x, ground_height(x, z), z)
	u.rotation.y = deg_to_rad(yaw)
	return u


## Instance a model so its footprint centre sits at (x, z) on the ground.
func place(file: String, x: float, z: float, yaw_deg := 0.0, scale := 1.0, sink := 0.0) -> Node3D:
	var path := A + file
	if not ResourceLoader.exists(path):
		push_warning("Missing model: " + path)
		return null
	var a := BuildDefs.aabb_of(path)
	var holder := Node3D.new()
	add_child(holder)
	var inst: Node3D = load(path).instantiate()
	holder.add_child(inst)
	inst.position = -Vector3(a.get_center().x, a.position.y, a.get_center().z)
	holder.rotation.y = deg_to_rad(yaw_deg)
	holder.scale = Vector3.ONE * scale
	holder.position = Vector3(x, ground_height(x, z) - sink, z)
	if not (file.contains("sandbag") or file.contains("stone_wall")):
		RtsNav.add_node_obstacle(holder, 0.3, 0.85)
	return holder


func _cover(file: String, x: float, z: float, yaw := 0.0, scale := 1.0) -> void:
	var n := place(file, x, z, yaw, scale)
	if n:
		var c := Node3D.new()
		n.add_child(c)
		c.add_to_group("cover")


func _alive(arr: Array) -> Array:
	return arr.filter(func(s): return is_instance_valid(s) and (s as RtsSoldier).can_fight())


## Free cover spots around the village houses, nearest to `from` first.
func house_covers(from: Vector3, max_d := 9999.0) -> Array:
	var out: Array = []
	for h in map.houses:
		for c in (h as EuropeHouse).cover_points():
			if (c as Node3D).global_position.distance_to(from) < max_d:
				out.append(c)
	out.sort_custom(func(a, b): return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return out


# ------------------------------------------------------------------ VILLAGE ASSAULT
const ASSEMBLY := Vector3(5, 0, -35)          # our side: south of the village, by the road
const NORTH := Vector3(70, 0, -240)           # insurgent reinforcements come from the north-east


func _build_assault() -> void:
	map.clear_trees(ASSEMBLY, 30.0)
	map.clear_trees(Vector3(-5, 0, 0), 14.0)
	# sandbag line + medical tent at the assembly area
	_cover("sandbag_wall.glb", ASSEMBLY.x - 10, ASSEMBLY.z - 14, 0.0)
	_cover("sandbag_wall.glb", ASSEMBLY.x + 2, ASSEMBLY.z - 15, 0.0)
	_cover("sandbag_wall.glb", ASSEMBLY.x + 14, ASSEMBLY.z - 14, 0.0)
	var tent := place("props/medical_tent.glb", -5, 0, 0.0)
	if tent:
		var med := Marker3D.new()
		med.add_to_group("medical")
		tent.add_child(med)
	# armour
	var t1 := _unit(RtsTank, "t72.glb", ASSEMBLY.x - 16, ASSEMBLY.z + 8, 180)
	var t2 := _unit(RtsTank, "t72.glb", ASSEMBLY.x + 20, ASSEMBLY.z + 6, 180)
	var hv := _unit(RtsVehicle, "humvee.glb", ASSEMBLY.x + 6, ASSEMBLY.z + 16, 90)
	var mi24 := _unit(RtsHelicopter, "mi24.glb", ASSEMBLY.x - 30, ASSEMBLY.z + 45) as RtsHelicopter
	if mi24:
		mi24.position.y += 24.0
	for u in [t1, t2, hv, mi24]:
		if u:
			if u is RtsTank: (u as RtsTank).team = 0
			u.add_to_group("player_units")
			units.append(u)
	# three squads
	var names := ["Alpha", "Bravo", "Charlie"]
	for g in 3:
		var sid := new_squad(names[g])
		for i in 4:
			var x: float = ASSEMBLY.x - 12 + g * 12 + (i % 2) * 2.2
			var z: float = ASSEMBLY.z - 10 + (i / 2) * 2.2
			var s := _soldier(x, z, 180, 0, i == 3 and g == 1, sid)
			if i == 2: s.rpg_rounds = 4
			s.move_to(s.global_position + Vector3(0, 0, -0.1))
	# insurgents dug in around the houses
	var covers := house_covers(map.village_center())
	covers.shuffle()
	var n := mini(20, covers.size())
	for i in n:
		var c: Node3D = covers[i]
		var e := _soldier(c.global_position.x, c.global_position.z, 0, 1, i % 9 == 4)
		e.accuracy = 0.34
		if i % 5 == 0: e.rpg_rounds = 2
		e.move_to(c.global_position + Vector3(0.1, 0, 0.1))
	var et := _unit(RtsTank, "tank_enemy.glb", 55, -215, 160) as RtsTank
	if et:
		et.team = 1
		et.wheel_radius = 0.36
		enemy_tanks.append(et)
		et.move_to(Vector3(45, 0, -165))
	cam.position = Vector3(ASSEMBLY.x + 5, ground_height(ASSEMBLY.x, ASSEMBLY.z - 40), ASSEMBLY.z - 40)
	cam.rotation.y = 0.0
	cam.distance = 105.0
	var dt := Timer.new()
	dt.wait_time = 45.0
	dt.autostart = true
	add_child(dt)
	dt.timeout.connect(func():
		if not _alive(enemies).is_empty():
			var dr := RtsDrone.launch(self, NORTH + Vector3(0, ground_height(NORTH.x, NORTH.z) + 16, 0), 1)
			dr.goal = ASSEMBLY)


func _assault_waves(delta: float) -> void:
	_wave_t -= delta
	if _wave_t > 0.0 or _waves >= 3:
		return
	_waves += 1
	_wave_t = 90.0
	var target := map.village_center() + Vector3(0, 0, 25)
	for i in 4 + _waves * 2:
		var e := _soldier(NORTH.x + randf_range(-15, 15), NORTH.z + randf_range(-10, 10), 180, 1, i == 0)
		e.accuracy = 0.34
		if randf() < 0.2: e.rpg_rounds = 2
		e.objective = target + Vector3(randf_range(-20, 20), 0, randf_range(-12, 12))
	if _waves == 2:
		var tk := _unit(RtsTank, "tank_enemy.glb", NORTH.x + 20, NORTH.z, 180) as RtsTank
		if tk:
			tk.team = 1
			tk.wheel_radius = 0.36
			enemy_tanks.append(tk)
			tk.move_to(target)
	status.text = "Insurgent reinforcements coming from the north-east!"


func _build_info() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RtsHud._sb(Color(0.05, 0.05, 0.06, 0.55), Color(0.3, 0.3, 0.32), 1))
	panel.position = Vector2(10, 10)
	cl.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	info = Label.new()
	status = Label.new()
	for l in [info, status]:
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_font_size_override("font_size", 13)
		v.add_child(l)
	status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	info.text = "VILLAGE ASSAULT  -  take the village\n" \
		+ "Drag LMB: select   Click: squad   RMB: move / attack (RMB on a house: tanks & Mi-24 shell it, infantry take cover by it)\n" \
		+ "G grenade   R RPG   Z / X / C prone / crouch / stand   H halt   F focus   V dig a trench   Ctrl+number: group\n" \
		+ "1 / 2 / 3 / 4: grenade / shell / artillery / bomb at cursor   Space: F-117 air strike\n" \
		+ "WASD camera   Wheel zoom   Q/E rotate   N winter / summer   Esc menu"


func _process(delta: float) -> void:
	if mode != "assault" or status == null:
		return
	_assault_waves(delta)
	var w := 0; var a := 0; var d := 0
	for s in squad:
		if not is_instance_valid(s): continue
		var st: int = (s as RtsSoldier).state
		if st == RtsSoldier.State.DEAD: d += 1
		elif st in [RtsSoldier.State.WOUNDED, RtsSoldier.State.DRAGGED, RtsSoldier.State.TREATED]: w += 1
		else: a += 1
	var ea := _alive(enemies).size()
	var pr := get_tree().get_nodes_in_group("prisoners").size()
	var ruins := 0
	for h in map.houses:
		if (h as EuropeHouse).ruined: ruins += 1
	if Engine.get_process_frames() % 30 == 0 and not status.text.begins_with("Insurgent"):
		status.text = "Ours: %d fighting, %d wounded, %d killed   |   Insurgents: %d left, %d captured   |   Houses destroyed: %d / %d" % [a, w, d, ea, pr, ruins, map.houses.size()]
	elif Engine.get_process_frames() % 400 == 0:
		status.text = ""
	if ea == 0 and _waves >= 3 and not _won:
		_won = true
		var l := Label.new()
		l.text = "VICTORY!  The village is ours"
		l.set_anchors_preset(Control.PRESET_CENTER)
		l.position = Vector2(-300, -60)
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 8)
		info.get_parent().get_parent().get_parent().add_child(l)


# ------------------------------------------------------------------ input
func _mouse_point() -> Variant:
	# ray against terrain and houses; fallback to a flat plane
	var mp := get_viewport().get_mouse_position()
	var o := cam.camera.project_ray_origin(mp)
	var dir := cam.camera.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * 3000.0, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		return hit.position
	var p = cam.mouse_ground_point(0.0)
	if p != null: p.y = ground_height(p.x, p.z)
	return p


## The house under the mouse cursor (or null).
func house_under_mouse() -> EuropeHouse:
	var mp := get_viewport().get_mouse_position()
	var o := cam.camera.project_ray_origin(mp)
	var dir := cam.camera.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * 3000.0, 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider and hit.collider.get_parent() is EuropeHouse:
		return hit.collider.get_parent()
	return null


func _unhandled_input(e: InputEvent) -> void:
	if mode == "" or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match Keys.logical(e.keycode):      # tugmalar Settings > Controls da almashtiriladi
		KEY_N:
			map.set_winter(not map.winter)
		KEY_V:
			if not placer.active:
				placer.begin_trench()
		KEY_ESCAPE:
			pass                                  # pause: see PauseHandler
	if not debug_keys:
		return
	var p = _mouse_point()
	if p == null:
		return
	match e.keycode:
		KEY_1: RtsExplosion.spawn(self, p, 0.5)
		KEY_2: RtsExplosion.spawn(self, p, 1.0)
		KEY_3: RtsExplosion.spawn(self, p, 2.0)
		KEY_4: RtsExplosion.spawn(self, p, 3.5)
		KEY_SPACE: RtsJetStrike.call_in(self, A + "f117.glb", p, Vector3(1, 0, 0.35))


## Esc pauses the battle, F9 restarts the operation (works while paused), M (paused) returns to the main menu.
class PauseHandler extends Node:
	var demo: Node3D
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _unhandled_input(e: InputEvent) -> void:
		if not (e is InputEventKey) or not e.pressed or e.echo:
			return
		if e.keycode == KEY_ESCAPE:
			if demo.placer.active and not get_tree().paused:
				return
			get_tree().paused = not get_tree().paused
			if demo.mode_node and demo.mode_node.get("hud") is OperationHud:
				demo.mode_node.hud.set_paused(get_tree().paused)
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_M and get_tree().paused:
			# pauza paytida M: bosh menyuga qaytish
			get_tree().paused = false
			var sm := get_tree().root.get_node_or_null("ScreenManager")
			if sm:
				sm.open("main")
		elif e.keycode == KEY_F9:
			get_tree().paused = false
			get_tree().reload_current_scene()


## Bosh menyudagi DEPLOY tanlagan rejim (GameSession.deploy.battle_mode); bo'lmasa "operation".
func _deploy_mode() -> String:
	var gs := get_tree().root.get_node_or_null("GameSession")
	if gs and gs.deploy is Dictionary and str(gs.deploy.get("battle_mode", "")) != "":
		return str(gs.deploy.battle_mode)
	return "operation"


func _deploy_opt(key: String, def: Variant) -> Variant:
	var gs := get_tree().root.get_node_or_null("GameSession") if is_inside_tree() else null
	return gs.deploy.get(key, def) if gs and gs.deploy is Dictionary else def
