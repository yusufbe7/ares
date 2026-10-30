## OPERATION (semi-automatic, like the dev-log footage).
## The player does not micro-manage: he gives goals ("go there", "take that point", "call a squad")
## and the soldiers do the rest themselves - path finding, cover slots, firing, hiding, dragging the wounded.
##
##   * Points A (Crossroads), B (Village), C (East Farm). The side holding more of them makes the other
##     side BLEED men from its reserve every few seconds.
##   * Each side has a reserve of 150 men. R calls a 5-man squad from the SOUTH-WEST edge (cooldown);
##     Y calls a T-72 (supply + 3 crew), U calls artillery (red warning circle first, everybody runs).
##   * B opens the radial build menu: TRENCH (per metre), WIRE, CAMO NET, MINES - paid with supply.
##   * Trenches give 70-80 % protection and tanks can't cross them; mines blow up enemies walking on them.
##   * The operation ends when the time runs out (more men left wins) or a side has nobody left.
## The insurgent commander does the same from the NORTH-EAST: squads, artillery, tanks, drones.
class_name OperationMode
extends Node

const TIME_LIMIT := 30.0 * 60.0
const RESERVE := 150
const SQUAD_SIZE := 5
const SQUAD_CD := 25.0
const TANK_COST := 120
const TANK_MEN := 3
const TANK_CD := 120.0
const ARTY_COST := 40
const ARTY_CD := 60.0
const ARTY_R := 12.0
const BLEED_EVERY := 15.0
const DEFAULT_ENTRY := [Vector3(-200, 0, 150), Vector3(-150, 0, 205)]          # SOUTH-WEST (ours)
const DEFAULT_ENEMY_ENTRY := [Vector3(225, 0, -235), Vector3(150, 0, -258)]    # NORTH-EAST (theirs)
const DEFAULT_ZONES := [
	{"name": "A", "title": "Crossroads", "pos": Vector3(-60, 0, -72), "r": 30.0},
	{"name": "B", "title": "Village", "pos": Vector3(25, 0, -140), "r": 55.0},
	{"name": "C", "title": "East Farm", "pos": Vector3(205, 0, -135), "r": 35.0},
]
const NAMES := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima",
	"Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform", "Victor", "Whiskey", "Xray", "Yankee", "Zulu"]

## Generator yasagan maydonda (map.spec.layout) kirishlar va zonalar o'shandan olinadi.
var ENTRY: Array = DEFAULT_ENTRY.duplicate()
var ENEMY_ENTRY: Array = DEFAULT_ENEMY_ENTRY.duplicate()
var ZONES: Array = DEFAULT_ZONES.duplicate(true)
## Kampaniya jangi: o'yinchi himoyada (dushman hujum qilyapti) - zonalar boshidan bizniki.
var player_defends := false
var demo: Node3D
var hud: OperationHud
var supply := 80.0
var income := 0.0
var reserve := [RESERVE, RESERVE]
var zones: Array = []                  # {name, title, pos, r, owner, cap, ring, label}
var clock := TIME_LIMIT
var over := false
var bleeding := -1
var cooldowns := {"squad": 0.0, "tank": 0.0, "artillery": 0.0}
var minefields: Array = []             # {pos, r, charges, team, node}
var _bleed_t := BLEED_EVERY
var _tick := 0.0
var _ui_t := 0.0
var _mine_t := 0.0
var _squad_n := 0
var _enemy_squad_t := 25.0
var _enemy_arty_t := 100.0
var _enemy_tank_t := 300.0
var _enemy_drone_t := 220.0
var _paused := false


func setup(p_demo: Node3D) -> void:
	demo = p_demo
	var map: EuropeMap = demo.map
	_apply_layout(map.spec.get("layout", {}))
	for e in ENTRY + ENEMY_ENTRY:
		map.clear_trees(e, 22.0)
	# ---------------- points
	for z in ZONES:
		var zz: Dictionary = z.duplicate()
		zz.pos = _ground(z.pos)
		zz.owner = -1
		zz.cap = 0.0
		# kampaniya jangi: hudud egasi boshida bitta nuqtani ushlab turadi - hujumda dushman C (tayanch),
		# himoyada biz B (shaharcha)
		if not map.spec.is_empty() and z.name == ("B" if player_defends else "C"):
			zz.owner = 0 if player_defends else 1
			zz.cap = 1.0 if player_defends else -1.0
		var ring := Decal.new()
		ring.cull_mask = RtsGround.DECAL_LAYER
		ring.texture_albedo = RtsPlacer.circle_texture()
		ring.size = Vector3(zz.r * 2.0, 40.0, zz.r * 2.0)
		ring.albedo_mix = 0.85
		demo.add_child(ring)
		ring.global_position = zz.pos + Vector3.UP * 5.0
		zz.ring = ring
		var lb := Label3D.new()
		lb.text = z.name
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lb.pixel_size = 0.0006
		lb.font_size = 56
		lb.outline_size = 12
		demo.add_child(lb)
		lb.global_position = zz.pos + Vector3.UP * 12.0
		zz.label = lb
		zones.append(zz)
	# ---------------- our start: two squads, a T-72 and a Humvee at the south-west edge
	var med: Node3D = demo.place("props/medical_tent.glb", ENTRY[0].x - 18, ENTRY[0].z + 16, 30.0)
	if med:
		var m := Marker3D.new()
		m.add_to_group("medical")
		med.add_child(m)
	for k in 2:
		_squad(0, ENTRY[0] + Vector3(10 + k * 9, 0, -6), _ground(ZONES[0].pos) if k == 0 else null)
	var t := demo._unit(RtsTank, "t72.glb", ENTRY[0].x + 4, ENTRY[0].z + 10, 150) as RtsTank
	if t:
		t.team = 0
		t.add_to_group("player_units")
		reserve[0] -= TANK_MEN
	var hv: Node3D = demo._unit(RtsVehicle, "humvee.glb", ENTRY[0].x - 6, ENTRY[0].z + 4, 45)
	if hv:
		hv.add_to_group("player_units")
		reserve[0] -= 1
	# ---------------- the insurgents hold the village (B) and the farm (C)
	var covers: Array = demo.house_covers(ZONES[1].pos)
	for i in mini(10, covers.size()):
		var c: Node3D = covers[i * 2 % covers.size()]
		var e := _enemy(c.global_position, null)
		e.move_to(c.global_position)
	reserve[1] -= 10
	var cp: Vector3 = ZONES[2].pos
	for k in 2:
		RtsStructure.create(demo, "sandbags", _ground(cp + Vector3(-8 + k * 14, 0, 12)), 0.2 * k, 1, true)
	var tr := RtsTrench.create(demo, map, cp + Vector3(-14, 0, 4), cp + Vector3(10, 0, 8), 1)
	tr.progress = tr.work
	tr._update(true)
	tr._complete()
	for i in 6:
		var e := _enemy(cp + Vector3(randf_range(-12, 12), 0, randf_range(0, 10)), null)
		e.move_to(cp + Vector3(-12 + i * 4.0, 0, 5.5))
	reserve[1] -= 6
	for z in zones:
		if z.name != "A":
			z.owner = 1
			z.cap = -1.0
	# ---------------- UI
	hud = OperationHud.new()
	demo.add_child(hud)
	hud.setup(self, demo)
	demo.placer.validator = _validate
	demo.placer.placed.connect(_on_placed)
	demo.placer.target_picked.connect(_on_target)
	demo.cam.position = _ground(ENTRY[0] + Vector3(8, 0, -4))
	demo.cam.rotation.y = deg_to_rad(-35.0)
	demo.cam.distance = 95.0
	hud.notify("Operation started. Take points A, B and C - the side holding more of them bleeds the other.", Color(0.6, 0.85, 1.0))
	hud.notify("Right-click a point with soldiers selected: they take it themselves, cover to cover.")
	hud.notify("R: call a squad   Y: tank   U: artillery   B: build (trench, wire, camo net, mines)")
	_refresh_zone_visuals()
	set_process_unhandled_input(true)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, demo.ground_height(p.x, p.z), p.z)


# ------------------------------------------------------------------ spawning
func _enemy(p: Vector3, objective) -> RtsSoldier:
	var q := RtsNav.nearest_walkable(p + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
	var e: RtsSoldier = demo._soldier(q.x, q.z, 160, 1, randf() < 0.1)
	if randf() < 0.18: e.rpg_rounds = 2
	e.accuracy = 0.34
	if objective != null:
		e.objective = objective
	return e


## A 5-man squad enters at the map edge: rifleman x3, RPG gunner, medic (or MG for the enemy).
func _squad(team: int, at: Vector3, objective) -> Array:
	var men: Array = []
	if team == 0:
		var sid: int = demo.new_squad(NAMES[_squad_n % NAMES.size()])
		_squad_n += 1
		for i in SQUAD_SIZE:
			var p := at + Vector3((i % 3) * 2.2 - 2.2, 0, (i / 3) * 2.4)
			var s: RtsSoldier = demo._soldier(p.x, p.z, 45, 0, i == 4, sid)
			if i == 2: s.rpg_rounds = 3
			if objective != null:
				var o: Vector3 = objective
				s.objective = o + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
			s.move_to(s.global_position + Vector3(0, 0, -0.1))
			men.append(s)
	else:
		for i in SQUAD_SIZE:
			var e := _enemy(at + Vector3((i % 3) * 2.2, 0, (i / 3) * 2.4), null)
			if objective != null:
				var o: Vector3 = objective
				e.objective = o + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
			if i == 0:
				ConquestMode._make_mg(e)
			men.append(e)
	return men


func zone_at(p: Vector3) -> Variant:
	for z in zones:
		if Vector2(p.x - z.pos.x, p.z - z.pos.z).length() < z.r:
			return z
	return null


# ------------------------------------------------------------------ player actions
func action(key: String) -> void:
	if over:
		return
	match key:
		"squad": call_squad()
		"tank": call_tank()
		"artillery":
			if _can_arty() == "":
				demo.placer.begin_target("artillery", ARTY_R)
			else:
				hud.notify("Artillery: " + _can_arty())
		"build": open_build()


func call_squad() -> void:
	if cooldowns.squad > 0.0:
		hud.notify("Next squad in %ds" % int(ceil(cooldowns.squad)))
		return
	if reserve[0] < SQUAD_SIZE:
		hud.notify("No men left in the reserve!", Color(1, 0.5, 0.4))
		return
	reserve[0] -= SQUAD_SIZE
	cooldowns.squad = SQUAD_CD
	var at: Vector3 = ENTRY[randi() % ENTRY.size()]
	var goal := _player_goal()
	_squad(0, at, goal)
	hud.notify("Squad %s (5 men) is coming in from the SOUTH-WEST, heading for point %s." % [NAMES[(_squad_n - 1) % NAMES.size()], _zone_name(goal)], Color(0.6, 0.85, 1.0))


func call_tank() -> void:
	if cooldowns.tank > 0.0:
		hud.notify("Next tank in %ds" % int(ceil(cooldowns.tank)))
		return
	if supply < TANK_COST or reserve[0] < TANK_MEN:
		hud.notify("Tank: needs %d supply and %d crew" % [TANK_COST, TANK_MEN])
		return
	supply -= TANK_COST
	reserve[0] -= TANK_MEN
	cooldowns.tank = TANK_CD
	var at: Vector3 = ENTRY[1]
	var t := demo._unit(RtsTank, "t72.glb", at.x, at.z, 150) as RtsTank
	if t:
		t.team = 0
		t.add_to_group("player_units")
		t.move_to(_player_goal() + Vector3(-20, 0, 25))
	hud.notify("T-72 on its way from the SOUTH-WEST.", Color(0.6, 0.85, 1.0))


func _can_arty() -> String:
	if cooldowns.artillery > 0.0:
		return "ready in %ds" % int(ceil(cooldowns.artillery))
	if supply < ARTY_COST:
		return "needs %d supply" % ARTY_COST
	return ""


func open_build() -> void:
	var items: Array = []
	for k in ["trench", "wire", "camo", "mines"]:
		var d := BuildDefs.get_def(k)
		var cost := ("%d / m" % d.cost) if k == "trench" else ("%d SUPPLY" % d.cost)
		items.append([k, String(d.name).to_upper(), cost, supply >= float(d.cost)])
	hud.open_radial(items)


func build_pick(key: String) -> void:
	if key == "trench":
		demo.placer.begin_trench()
	else:
		demo.placer.begin(key, [])


## Nearest point we don't hold yet (else the most threatened one we do hold).
func _player_goal() -> Vector3:
	var best = null
	var bd := INF
	for z in zones:
		if z.owner != 0:
			var d: float = z.pos.distance_to(ENTRY[0])
			if d < bd: bd = d; best = z
	if best == null:
		best = zones[1]
	return best.pos


func _zone_name(p: Vector3) -> String:
	var z = zone_at(p)
	return z.name if z != null else "?"


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if demo.placer.active or hud.radial_open():
		return
	match Keys.logical(e.keycode):      # tugmalar Settings > Controls da almashtiriladi
		KEY_R: action("squad")
		KEY_Y: action("tank")
		KEY_U: action("artillery")
		KEY_B: action("build")
		_: return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ building
func _validate(key: String, p: Vector3, yaw: float) -> String:
	var d: Dictionary = BuildDefs.STRUCTURES[key]
	if supply < d.cost:
		return "not enough supply"
	if not RtsNav.walkable(p):
		return "a building in the way"
	var near := false
	for s in demo.get_tree().get_nodes_in_group("soldiers"):
		if s.team == 0 and s.is_commandable() and s.global_position.distance_to(p) < 60.0:
			near = true
			break
	if not near:
		return "too far from our soldiers"
	for e in demo.get_tree().get_nodes_in_group("enemies"):
		if (e as RtsSoldier).can_fight() and (e as Node3D).global_position.distance_to(p) < 18.0:
			return "too close to the enemy"
	var r: float = maxf(d.size.x, d.size.y) * 0.5
	for s in demo.get_tree().get_nodes_in_group("structures"):
		var o: RtsStructure = s
		if Vector2(p.x - o.global_position.x, p.z - o.global_position.z).length() < (r + maxf(o.def.size.x, o.def.size.y) * 0.5) * 0.7:
			return "blocked by %s" % o.def.name
	return ""


func _on_placed(key: String, p: Vector3, yaw: float) -> void:
	var d: Dictionary = BuildDefs.STRUCTURES[key]
	supply -= d.cost
	var site := RtsStructure.create(demo, key, p, yaw, 0)
	if key == "mines":
		site.completed.connect(_arm_mines)
	else:
		site.completed.connect(func(s): hud.notify("%s ready." % s.def.name, Color(0.6, 1.0, 0.65)))
	var men: Array = demo.commander.soldiers_selected()
	if men.is_empty():
		var idle: Array = demo.get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0 and s.can_fight() and s.work_site == null and s.global_position.distance_to(p) < 80.0)
		idle.sort_custom(func(a, b): return a.global_position.distance_to(p) < b.global_position.distance_to(p))
		men = idle.slice(0, 2)
	site.assign(men)
	demo.commander.lines(men, p, Color(0.45, 1.0, 0.6, 0.9))


## The minefield is laid: three hidden charges. Our men see little markers, the enemy sees nothing.
func _arm_mines(s: RtsStructure) -> void:
	var root := Node3D.new()
	demo.add_child(root)
	root.global_position = s.global_position
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.22, 0.18)
	m.roughness = 0.8
	for k in 5:
		var mi := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.16; cy.bottom_radius = 0.18; cy.height = 0.08
		cy.material = m
		mi.mesh = cy
		root.add_child(mi)
		var q := s.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		mi.global_position = Vector3(q.x, demo.ground_height(q.x, q.z) + 0.02, q.z)
	minefields.append({"pos": s.global_position, "r": 2.8, "charges": 3, "team": 0, "node": root})
	s.queue_free()
	hud.notify("Minefield laid.", Color(0.6, 1.0, 0.65))


func _mines_tick() -> void:
	var keep: Array = []
	for f in minefields:
		var foes: Array = demo.get_tree().get_nodes_in_group("enemies" if f.team == 0 else "soldiers")
		for u in foes:
			if f.charges <= 0:
				break
			var s := u as RtsSoldier
			if s and s.team != f.team and s.state != RtsSoldier.State.DEAD and Vector2(s.global_position.x - f.pos.x, s.global_position.z - f.pos.z).length() < f.r:
				RtsExplosion.spawn(demo, s.global_position, 0.75)
				f.charges -= 1
		for t in demo.get_tree().get_nodes_in_group("tanks"):
			if f.charges > 0 and t.team != f.team and not t.destroyed and Vector2(t.global_position.x - f.pos.x, t.global_position.z - f.pos.z).length() < f.r + 1.5:
				RtsExplosion.spawn(demo, t.global_position + Vector3.UP * 0.3, 1.5)
				f.charges -= 2
		if f.charges > 0:
			keep.append(f)
		elif is_instance_valid(f.node):
			f.node.queue_free()
	minefields = keep


# ------------------------------------------------------------------ artillery (both sides)
func _on_target(key: String, p: Vector3) -> void:
	if key != "artillery" or _can_arty() != "":
		return
	supply -= ARTY_COST
	cooldowns.artillery = ARTY_CD
	artillery(p, ARTY_R, 6, 0)
	hud.notify("Artillery: 6 shells, impact in 4 seconds.", Color(0.6, 0.85, 1.0))


## Red warning circle first, the danger zone makes every soldier run out of it, then the shells land.
func artillery(p: Vector3, r: float, shells: int, team: int) -> void:
	var warn := 4.0
	CoverSystem.add_danger(p, r + 4.0, warn + shells * 0.7 + 1.0)
	var ring := Decal.new()
	ring.cull_mask = RtsGround.DECAL_LAYER
	ring.texture_albedo = RtsPlacer.circle_texture()
	ring.size = Vector3(r * 2.0, 60.0, r * 2.0)
	ring.modulate = Color(1.0, 0.2, 0.15)
	ring.albedo_mix = 1.0
	demo.add_child(ring)
	ring.global_position = _ground(p) + Vector3.UP * 10.0
	var tw := ring.create_tween().set_loops(int((warn + shells * 0.7) / 0.6))
	tw.tween_property(ring, "albedo_mix", 0.35, 0.3)
	tw.tween_property(ring, "albedo_mix", 1.0, 0.3)
	demo.get_tree().create_timer(warn + shells * 0.7 + 0.5).timeout.connect(ring.queue_free)
	for i in shells:
		var off := Vector3(randf_range(-r, r), 0, randf_range(-r, r)) * 0.8
		demo.get_tree().create_timer(warn + i * 0.7).timeout.connect(func():
			if is_instance_valid(demo):
				RtsExplosion.spawn(demo, _ground(p + off), 1.5))


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if demo == null or over:
		return
	clock -= delta
	for k in cooldowns:
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	var held := zones.filter(func(z): return z.owner == 0).size()
	income = 0.5 + 0.3 * held
	supply += income * delta
	_mine_t -= delta
	if _mine_t <= 0.0:
		_mine_t = 0.2
		_mines_tick()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_zones_tick()
		_enemy_ai()
		_check_end()
	_bleed_t -= delta
	if _bleed_t <= 0.0:
		_bleed_t = BLEED_EVERY
		_bleed()
	_ui_t -= delta
	if _ui_t <= 0.0:
		_ui_t = 0.25
		_ui()


func _zones_tick() -> void:
	for z in zones:
		var n := [0, 0]
		for s in demo.get_tree().get_nodes_in_group("soldiers") + demo.get_tree().get_nodes_in_group("enemies"):
			if s is RtsSoldier and s.can_fight() and Vector2(s.global_position.x - z.pos.x, s.global_position.z - z.pos.z).length() < z.r:
				n[s.team] += 1
		for t in demo.get_tree().get_nodes_in_group("tanks"):
			if not t.destroyed and Vector2(t.global_position.x - z.pos.x, t.global_position.z - z.pos.z).length() < z.r:
				n[t.team] += 2
		var side := -1
		if n[0] > 0 and n[1] == 0: side = 0
		elif n[1] > 0 and n[0] == 0: side = 1
		if side == -1:
			continue
		var rate := 0.02 * minf(5.0, float(n[side]))
		var before: int = z.owner
		z.cap = clampf(z.cap + (rate if side == 0 else -rate), -1.0, 1.0)
		if z.cap >= 1.0: z.owner = 0
		elif z.cap <= -1.0: z.owner = 1
		elif (z.owner == 0 and z.cap < 0.0) or (z.owner == 1 and z.cap > 0.0): z.owner = -1
		if z.owner != before:
			_refresh_zone_visuals()
			if z.owner == 0:
				hud.notify("Point %s (%s) captured!" % [z.name, z.title], Color(0.6, 0.85, 1.0))
			elif z.owner == 1:
				hud.notify("Point %s (%s) lost to the insurgents." % [z.name, z.title], Color(1, 0.5, 0.4))
			else:
				hud.notify("Point %s (%s) is contested." % [z.name, z.title])


func _refresh_zone_visuals() -> void:
	for z in zones:
		var col := OperationHud.BLUE if z.owner == 0 else (OperationHud.RED if z.owner == 1 else OperationHud.GREY)
		(z.ring as Decal).modulate = col
		(z.label as Label3D).modulate = col
		(z.label as Label3D).text = z.name


func _bleed() -> void:
	var a := zones.filter(func(z): return z.owner == 0).size()
	var b := zones.filter(func(z): return z.owner == 1).size()
	bleeding = -1
	if a > b:
		reserve[1] = maxi(0, reserve[1] - (a - b))
		bleeding = 1
	elif b > a:
		reserve[0] = maxi(0, reserve[0] - (b - a))
		bleeding = 0


func _field(team: int) -> int:
	var n := 0
	for s in demo.get_tree().get_nodes_in_group("soldiers" if team == 0 else "enemies"):
		if s is RtsSoldier and s.team == team and (s.can_fight() or s.state in [RtsSoldier.State.WOUNDED, RtsSoldier.State.DRAGGED, RtsSoldier.State.TREATED, RtsSoldier.State.BUSY, RtsSoldier.State.RESCUE_RUN, RtsSoldier.State.DRAGGING, RtsSoldier.State.TREATING]):
			n += 1
	for t in demo.get_tree().get_nodes_in_group("tanks"):
		if t.team == team and not t.destroyed:
			n += TANK_MEN
	return n


# ------------------------------------------------------------------ insurgent commander
func _enemy_ai() -> void:
	var mins := (TIME_LIMIT - clock) / 60.0
	# squads from the north-east
	_enemy_squad_t -= 1.0
	if _enemy_squad_t <= 0.0:
		_enemy_squad_t = maxf(24.0, randf_range(38.0, 55.0) - mins)
		var field := 0
		for e in demo.enemies:
			if is_instance_valid(e) and e.can_fight(): field += 1
		if reserve[1] >= SQUAD_SIZE and field < 28:
			reserve[1] -= SQUAD_SIZE
			var goal := _enemy_goal()
			_squad(1, ENEMY_ENTRY[randi() % ENEMY_ENTRY.size()], goal)
	# artillery on a group of our soldiers
	_enemy_arty_t -= 1.0
	if _enemy_arty_t <= 0.0:
		_enemy_arty_t = randf_range(80.0, 120.0)
		var best := Vector3.ZERO
		var bn := 0
		var ours: Array = demo.get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0 and s.can_fight())
		for s in ours:
			var n := 0
			for o in ours:
				if o.global_position.distance_to(s.global_position) < 14.0: n += 1
			if n > bn: bn = n; best = s.global_position
		if bn >= 3:
			artillery(best, ARTY_R, 5, 1)
			hud.notify("ENEMY ARTILLERY INCOMING!", Color(1, 0.45, 0.35))
	# tanks
	_enemy_tank_t -= 1.0
	if _enemy_tank_t <= 0.0:
		_enemy_tank_t = 240.0
		var alive: int = demo.enemy_tanks.filter(func(t): return is_instance_valid(t) and not t.destroyed).size()
		if alive < 2 and reserve[1] >= TANK_MEN:
			reserve[1] -= TANK_MEN
			var at: Vector3 = ENEMY_ENTRY[0]
			var tk := demo._unit(RtsTank, "tank_enemy.glb", at.x, at.z, -30) as RtsTank
			if tk:
				tk.team = 1
				tk.wheel_radius = 0.36
				demo.enemy_tanks.append(tk)
				tk.move_to(_enemy_goal())
				hud.notify("Enemy armour spotted in the NORTH-EAST!", Color(1, 0.5, 0.4))
	# drones
	_enemy_drone_t -= 1.0
	if _enemy_drone_t <= 0.0:
		_enemy_drone_t = randf_range(90.0, 130.0)
		var at2: Vector3 = ENEMY_ENTRY[1]
		RtsDrone.launch(demo, at2 + Vector3(0, demo.ground_height(at2.x, at2.z) + 18.0, 0), 1)


## Our points nearest to them first, then neutral ones, else the weakest point they hold.
func _enemy_goal() -> Vector3:
	var pick = null
	var bd := INF
	for pref in [0, -1]:
		for z in zones:
			if z.owner == pref:
				var d: float = z.pos.distance_to(ENEMY_ENTRY[0])
				if d < bd: bd = d; pick = z
		if pick != null:
			return pick.pos
	var least := INF
	for z in zones:
		var n := 0
		for e in demo.enemies:
			if is_instance_valid(e) and e.can_fight() and e.global_position.distance_to(z.pos) < z.r: n += 1
		if n < least: least = n; pick = z
	return pick.pos


# ------------------------------------------------------------------ end of the operation
func _check_end() -> void:
	var f0 := _field(0)
	var f1 := _field(1)
	if reserve[1] <= 0 and f1 == 0:
		_finish(true, "The insurgents have no men left.")
	elif reserve[0] <= 0 and f0 == 0:
		_finish(false, "We have no men left.")
	elif clock <= 0.0:
		var a: int = reserve[0] + f0
		var b: int = reserve[1] + f1
		_finish(a >= b, "Time is up: %d of our men against %d insurgents." % [a, b])


func _finish(won: bool, why: String) -> void:
	over = true
	hud.big(("VICTORY\n" if won else "DEFEAT\n") + why)
	print("OPERATION ", "VICTORY " if won else "DEFEAT ", why)
	# kampaniya jangi: natija kampaniyaga qaytadi (polklar soni qolgan askarlardan)
	var gs := get_tree().root.get_node_or_null("GameSession")
	if gs and not demo.map.spec.is_empty() and not gs.battle_request.is_empty():
		var left := [reserve[0] + _field(0), reserve[1] + _field(1)]
		get_tree().create_timer(4.0, true).timeout.connect(func(): BattleBridge.finish(get_tree(), won, left))


func _ui() -> void:
	var d := {
		"slots": CoverSystem.count(), "used": CoverSystem.in_use(),
		"reserve": reserve, "field": [_field(0), _field(1)], "bleeding": bleeding,
		"zones": zones, "time": clock, "supply": supply, "income": income,
		"buttons": {
			"squad": [cooldowns.squad <= 0.0 and reserve[0] >= SQUAD_SIZE, "5 MEN" if cooldowns.squad <= 0.0 else "%ds" % int(ceil(cooldowns.squad))],
			"tank": [cooldowns.tank <= 0.0 and supply >= TANK_COST, "%d SUPPLY" % TANK_COST if cooldowns.tank <= 0.0 else "%ds" % int(ceil(cooldowns.tank))],
			"artillery": [_can_arty() == "", "%d SUPPLY" % ARTY_COST if cooldowns.artillery <= 0.0 else "%ds" % int(ceil(cooldowns.artillery))],
			"build": [true, "RADIAL MENU"],
		},
	}
	hud.update(d)
	var marks: Array = []
	for z in zones:
		marks.append([z.pos, OperationHud.BLUE if z.owner == 0 else (OperationHud.RED if z.owner == 1 else OperationHud.GREY), 12.0])
	var mine: Array = demo.get_tree().get_nodes_in_group("player_units").filter(func(n): return RtsCommander.is_mine(n))
	for n in mine:
		marks.append([n.global_position, Color(0.45, 0.8, 1.0), 3.0 if n is RtsSoldier else 5.0])
	for e in demo.enemies:
		if is_instance_valid(e) and e.can_fight():
			for n in mine:
				if n.global_position.distance_to(e.global_position) < 90.0:
					marks.append([e.global_position, Color(1.0, 0.3, 0.25), 3.0])
					break
	hud.set_marks(marks)


## Generator rejasi (Vector2) -> operatsiya nuqtalari (Vector3). Zona nomlari biomga qarab.
func _apply_layout(L: Dictionary) -> void:
	if L.is_empty():
		return
	var v3 := func(v: Vector2) -> Vector3: return Vector3(v.x, 0.0, v.y)
	ENTRY = L.entry.map(v3)
	ENEMY_ENTRY = L.enemy_entry.map(v3)
	var titles := {"A": "Crossroads", "B": "Town" if demo.map.spec.get("biome", "") == "city" else "Village", "C": "Strongpoint"}
	ZONES = []
	for z in L.zones:
		ZONES.append({"name": z.name, "title": titles.get(z.name, z.name), "pos": v3.call(z.pos), "r": float(z.r)})
