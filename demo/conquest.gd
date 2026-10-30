## CONQUEST: your ground forces vs the insurgents.
## You start at the Command Post west of the river with 8 soldiers and 735 supply.
## Build a base (soldiers dig every building on site), train troops, take the 3 towns (+15% income each)
## and destroy the Insurgent Stronghold in the east. Lose the Command Post and the operation fails.
class_name ConquestMode
extends Node

const HQ_POS := Vector3(-150, 0, 200)
const ENEMY_HQ := Vector3(230, 0, -250)
const START_SUPPLY := 735.0
const TOWN_BONUS := 0.15
const TOWNS := [
	{"name": "Crossroads", "pos": Vector3(-60, 0, -72), "r": 40.0, "garrison": 4},
	{"name": "Village", "pos": Vector3(25, 0, -140), "r": 75.0, "garrison": 9},
	{"name": "East Farm", "pos": Vector3(205, 0, -135), "r": 45.0, "garrison": 4},
]
const TABS := {
	"BASE": ["fob", "barracks", "factory", "research", "medical", "depot"],
	"DEF": ["trench", "sandbags", "hesco", "bunker", "barriers", "wire", "hedgehog", "camo", "mg"],
	"INF": ["rifle", "medic", "rpg", "mgteam"],
	"ARMOR": ["humvee", "t72", "mi24"],
	"SUPPORT": ["drone", "artillery", "airstrike"],
}

var demo: Node3D
var hud: RtsHud
var supply := START_SUPPLY
var income := 0.0
var clock := 0.0
var over := false
var hq: RtsStructure
var stronghold: RtsStructure
var towns: Array = []               # [{name, pos, r, owner, cap, flag}]
var queues := {}                    # producer structure -> [{key, t, total}]
var cooldowns := {}
var _tick := 0.0
var _ui_t := 0.0
var _attack_t := 330.0
var _refill_t := 200.0
var _wave := 0
var _raiders: Array = []
var _stats := {"built": 0, "trained": 0, "lost": 0, "killed": 0}


func setup(p_demo: Node3D) -> void:
	demo = p_demo
	var map: Node3D = demo.map
	for c in [[HQ_POS, 120.0], [ENEMY_HQ, 70.0]]:
		map.clear_trees(c[0], c[1])
	# ---------------- player
	hq = RtsStructure.create(demo, "hq", _ground(HQ_POS), PI * 0.5, 0, true)
	hq.destroyed.connect(func(_s): _defeat("The Command Post was destroyed."))
	var names := ["Alpha", "Bravo"]
	for sq in 2:
		var sid: int = demo.new_squad(names[sq])
		for i in 4:
			var p := HQ_POS + Vector3(16 + (i % 2) * 2.4, 0, -6 + sq * 10 + (i / 2) * 2.4)
			var s: RtsSoldier = demo._soldier(p.x, p.z, 90, 0, sq == 1 and i == 3, sid)
			if sq == 0 and i == 3: s.rpg_rounds = 3
	# ---------------- enemy
	stronghold = RtsStructure.create(demo, "stronghold", _ground(ENEMY_HQ), -PI * 0.5, 1, true)
	stronghold.destroyed.connect(func(_s): _victory())
	for k in 6:
		var a := k * TAU / 6.0
		_enemy(ENEMY_HQ + Vector3(cos(a), 0, sin(a)) * 16.0, null)
	# trench line in front of Eastfield
	var trench: Array = []
	for c in demo.get_tree().get_nodes_in_group("cover"):
		if c.has_meta("omni"):
			trench.append(c)
	trench.shuffle()
	for i in mini(7, trench.size()):
		var cp: Vector3 = trench[i].global_position
		var e := _enemy(cp, null)
		e.move_to(cp + Vector3(0.3, 0, 0))
	for t in TOWNS:
		var town: Dictionary = t.duplicate()
		town["owner"] = 1
		town["cap"] = 0.0
		var flag := BuildDefs.flag_pole(1, Vector3.ZERO)
		demo.add_child(flag)
		flag.global_position = _ground(t.pos)
		town["flag"] = flag
		towns.append(town)
		_garrison(town, t.garrison)
	# ---------------- UI
	hud = RtsHud.new()
	hud.title = "COMMAND"
	hud.subtitle = "GROUND FORCES"
	demo.add_child(hud)
	hud.setup(demo, self, TABS)
	demo.placer.validator = _validate
	demo.placer.placed.connect(_on_placed)
	demo.placer.target_picked.connect(_on_target)
	demo.commander.selection_changed.connect(_update_men)
	demo.cam.position = _ground(HQ_POS + Vector3(25, 0, -10))
	demo.cam.distance = 90.0
	hud.notify("Operation started. Build a Barracks, then take the crossroads, the village and the east farm.", Color(0.6, 1.0, 0.65))
	hud.notify("Select soldiers (drag), pick a building, click to place. They dig it on site.")
	_update_men()


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, demo.ground_height(p.x, p.z), p.z)


func _enemy(p: Vector3, objective) -> RtsSoldier:
	var q := RtsNav.nearest_walkable(p + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	var e: RtsSoldier = demo._soldier(q.x, q.z, -90, 1, randf() < 0.1)
	if randf() < 0.15: e.rpg_rounds = 2
	e.accuracy = 0.34
	e.died.connect(func(): _stats.killed += 1)
	if objective != null:
		e.objective = objective
	return e


func _garrison(town: Dictionary, n: int) -> void:
	# defenders sit near the houses (cover markers of the map if any)
	var covers: Array = []
	for c in demo.get_tree().get_nodes_in_group("cover"):
		if (c as Node3D).global_position.distance_to(town.pos) < town.r * 0.8:
			covers.append(c)
	covers.shuffle()
	for i in n:
		var p: Vector3 = covers[i].global_position if i < covers.size() else town.pos + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
		var e := _enemy(p, null)
		e.move_to(p + Vector3(0.2, 0, 0.2))


# ------------------------------------------------------------------ HUD interface
func _built(key: String) -> Array:
	return demo.get_tree().get_nodes_in_group("structures_0").filter(func(s): return s.key == key and s.built and not s.dead)


func _has(req: String) -> String:
	for r in req.split("+"):
		if r != "" and _built(r).is_empty():
			return r
	return ""


func hud_item_state(key: String) -> Dictionary:
	var d := BuildDefs.get_def(key)
	var cost: int = d.get("cost", 0)
	var miss := _has(d.get("needs", ""))
	if miss != "":
		return {"ok": false, "reason": "NEEDS " + String(BuildDefs.STRUCTURES[miss].name).to_upper()}
	if BuildDefs.SUPPORT.has(key):
		var cd: float = cooldowns.get(key, 0.0)
		if cd > 0.0:
			return {"ok": false, "reason": "%ds" % int(ceil(cd)), "progress": 1.0 - cd / float(d.cooldown)}
	var pr := 0.0
	if BuildDefs.UNITS.has(key):
		for b in queues:
			for q in queues[b]:
				if q.key == key:
					pr = maxf(pr, 1.0 - q.t / q.total)
	if supply < cost:
		return {"ok": false, "reason": "NEED %d" % cost, "progress": pr}
	return {"ok": true, "reason": "TRAINING" if pr > 0.0 else "", "progress": pr}


func hud_click(key: String) -> void:
	var st := hud_item_state(key)
	if not st.ok and st.get("reason", "") != "TRAINING":
		hud.notify("%s: %s" % [BuildDefs.get_def(key).name, String(st.reason).to_lower()])
		return
	if key == "trench":
		demo.placer.begin_trench()
	elif BuildDefs.STRUCTURES.has(key):
		demo.placer.begin(key, _zones())
	elif BuildDefs.UNITS.has(key):
		_train(key)
	elif BuildDefs.SUPPORT.has(key):
		demo.placer.begin_target(key, {"drone": 4.0, "artillery": 14.0, "airstrike": 22.0}[key])


func _zones() -> Array:
	var z: Array = []
	for s in demo.get_tree().get_nodes_in_group("structures_0"):
		if s.built and s.def.has("zone"):
			z.append([s.global_position, float(s.def.zone)])
	return z


# ------------------------------------------------------------------ building
func _validate(key: String, p: Vector3, yaw: float) -> String:
	var d: Dictionary = BuildDefs.STRUCTURES[key]
	if supply < d.cost:
		return "not enough supply"
	var sz: Vector2 = d.size
	var b := Basis(Vector3.UP, yaw)
	var hs: Array = []
	for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3.ZERO]:
		var q: Vector3 = p + b * Vector3(c.x * sz.x * 0.5, 0, c.z * sz.y * 0.5)
		if not RtsNav.walkable(q):
			return "water"
		hs.append(demo.ground_height(q.x, q.z))
	if hs.max() - hs.min() > maxf(2.5, maxf(sz.x, sz.y) * 0.22):
		return "ground too steep"
	var in_zone := false
	for z in _zones():
		if Vector2(p.x - z[0].x, p.z - z[0].z).length() < z[1]:
			in_zone = true
	if not in_zone:
		var near_men := false
		for s in demo.get_tree().get_nodes_in_group("soldiers"):
			if s.team == 0 and s.is_commandable() and s.global_position.distance_to(p) < 45.0:
				near_men = true
				break
		if key == "fob" or d.cat == "DEF":
			if not near_men:
				return "outside the build zone (move soldiers there first)"
		else:
			return "outside the build zone"
	var r := maxf(sz.x, sz.y) * 0.5
	for s in demo.get_tree().get_nodes_in_group("structures"):
		var o: RtsStructure = s
		var orad: float = maxf(o.def.size.x, o.def.size.y) * 0.5
		var dist := Vector2(p.x - o.global_position.x, p.z - o.global_position.z).length()
		if dist < (r + orad) * 0.75:
			return "blocked by %s" % o.def.name
		if o.team != 0 and dist < 70.0:
			return "too close to the enemy"
	return ""


func _on_placed(key: String, p: Vector3, yaw: float) -> void:
	var d: Dictionary = BuildDefs.STRUCTURES[key]
	supply -= d.cost
	var site := RtsStructure.create(demo, key, p, yaw, 0)
	site.completed.connect(_on_completed)
	site.destroyed.connect(func(s): hud.notify("%s destroyed!" % s.def.name, Color(1, 0.45, 0.35)))
	var men: Array = demo.commander.soldiers_selected()
	if men.is_empty():
		var idle: Array = demo.get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0 and s.can_fight() and s.work_site == null and s.global_position.distance_to(p) < 300.0)
		idle.sort_custom(func(a, b): return a.global_position.distance_to(p) < b.global_position.distance_to(p))
		men = idle.slice(0, 4)
	var n := site.assign(men)
	demo.commander.lines(men, p, Color(0.45, 1.0, 0.6, 0.9))
	if n == 0:
		hud.notify("%s placed. Select soldiers and right-click it to build." % d.name, Color(1, 0.75, 0.4))
	else:
		hud.notify("%s: %d soldiers are digging." % [d.name, n])


func _on_completed(s: RtsStructure) -> void:
	_stats.built += 1
	hud.notify("%s completed." % s.def.name, Color(0.6, 1.0, 0.65))
	if s.def.get("gunner", false):
		var p: Vector3 = s.global_position
		var sid: int = demo.new_squad("MG")
		var g: RtsSoldier = demo._soldier(p.x - 1.5, p.z, 90, 0, false, sid)
		_make_mg(g)
		g.move_to(p + s.global_basis * Vector3(0, 0, -1.2))
	if s.key == "research":
		hud.notify("Research online: MG nests, tanks, drones and fire support unlocked.", Color(0.6, 0.85, 1.0))


static func _make_mg(g: RtsSoldier) -> void:
	g.fire_interval = 0.07
	g.burst = 14
	g.accuracy = 0.32
	g.weapon_range = 110.0
	g.spare_mags = 20
	g.mag_size = 100
	g.ammo = 100


# ------------------------------------------------------------------ training
func _producer(key: String) -> RtsStructure:
	var need := "factory" if BuildDefs.UNITS[key].cat == "ARMOR" else "barracks"
	var best: RtsStructure = null
	var bl := 999
	for b in _built(need):
		var l: int = queues.get(b, []).size()
		if l < bl: bl = l; best = b
	return best


func _train(key: String) -> void:
	var b := _producer(key)
	if b == null:
		return
	var d: Dictionary = BuildDefs.UNITS[key]
	if queues.get(b, []).size() >= 5:
		hud.notify("%s queue is full." % b.def.name)
		return
	supply -= d.cost
	if not queues.has(b): queues[b] = []
	queues[b].append({"key": key, "t": float(d.time), "total": float(d.time)})
	hud.notify("Training %s..." % d.name)


func _finish_unit(b: RtsStructure, key: String) -> void:
	var d: Dictionary = BuildDefs.UNITS[key]
	var out: Vector3 = b.global_transform * Vector3(0, 0, b.def.size.y * 0.5 + 4.0)
	var rally: Vector3 = b.global_transform * Vector3(0, 0, b.def.size.y * 0.5 + 12.0)
	out = RtsNav.nearest_walkable(out)
	_stats.trained += 1
	if key == "humvee":
		var v: Node3D = demo._unit(RtsVehicle, "humvee.glb", out.x, out.z, rad_to_deg(b.rotation.y))
		if v: v.add_to_group("player_units"); v.move_to(rally)
	elif key == "mi24":
		var hl := demo._unit(RtsHelicopter, "mi24.glb", out.x, out.z, rad_to_deg(b.rotation.y)) as RtsHelicopter
		if hl:
			hl.landed = true
			hl.add_to_group("player_units")
			hl.move_to(rally)
	elif key == "t72":
		var t: RtsTank = demo._unit(RtsTank, "t72.glb", out.x, out.z, rad_to_deg(b.rotation.y)) as RtsTank
		if t:
			t.team = 0
			t.add_to_group("player_units")
			t.move_to(rally)
	else:
		var sid: int = demo.new_squad(d.name)
		for i in int(d.get("men", 1)):
			var p := out + Vector3((i % 2) * 1.6, 0, (i / 2) * 1.6)
			var s: RtsSoldier = demo._soldier(p.x, p.z, rad_to_deg(b.rotation.y), 0, d.get("medic", false), sid)
			if d.has("rpg"): s.rpg_rounds = d.rpg
			if d.get("mg", false) and i == 0: _make_mg(s)
			s.move_to(rally + Vector3((i % 2) * 2.4, 0, (i / 2) * 2.4))
	hud.notify("%s ready." % d.name, Color(0.6, 1.0, 0.65))


# ------------------------------------------------------------------ fire support
func _on_target(key: String, p: Vector3) -> void:
	var d: Dictionary = BuildDefs.SUPPORT[key]
	if supply < d.cost:
		return
	supply -= d.cost
	cooldowns[key] = float(d.cooldown)
	match key:
		"drone":
			var from: Vector3 = _nearest_own_structure(p) + Vector3.UP * 14.0
			var dr := RtsDrone.launch(demo, from, 0)
			dr.goal = p
			hud.notify("FPV drone launched.")
		"artillery":
			hud.notify("Artillery: shells on the way!")
			for i in 6:
				var off := Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
				demo.get_tree().create_timer(2.5 + i * 0.7).timeout.connect(func():
					var q := p + off
					RtsExplosion.spawn(demo, Vector3(q.x, demo.ground_height(q.x, q.z), q.z), 1.6))
		"airstrike":
			hud.notify("F-117 inbound.")
			RtsJetStrike.call_in(demo, "res://assets/f117.glb", p, (p - HQ_POS).normalized())


func _nearest_own_structure(p: Vector3) -> Vector3:
	var best := hq.global_position
	var bd := INF
	for s in demo.get_tree().get_nodes_in_group("structures_0"):
		var d: float = s.global_position.distance_to(p)
		if s.built and d < bd: bd = d; best = s.global_position
	return best


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if demo == null or over:
		return
	clock += delta
	# economy
	income = 0.0
	for s in demo.get_tree().get_nodes_in_group("structures_0"):
		if s.built:
			income += float(s.def.get("income", 0.0))
	var held: int = towns.filter(func(t): return t.owner == 0).size()
	income *= 1.0 + TOWN_BONUS * held
	supply += income * delta
	# production
	for b in queues.keys():
		if not is_instance_valid(b) or b.dead:
			queues.erase(b)
			continue
		var q: Array = queues[b]
		if q.is_empty():
			continue
		q[0].t -= delta
		if q[0].t <= 0.0:
			var k: String = q[0].key
			q.pop_front()
			_finish_unit(b, k)
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, cooldowns[k] - delta)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_towns_tick()
		_enemy_ai()
		_check_defeat()
	_ui_t -= delta
	if _ui_t <= 0.0:
		_ui_t = 0.25
		_ui()


func _ui() -> void:
	hud.set_supply(supply, income)
	hud.refresh()
	var held: int = towns.filter(func(t): return t.owner == 0).size()
	var unheld := towns.size() - held
	var mins := int(clock) / 60
	hud.set_banner("%d TOWNS UNHELD  +%d%%    |    %02d:%02d    |    NEXT RAID %ds" % [unheld, roundi(unheld * TOWN_BONUS * 100), mins, int(clock) % 60, int(maxf(0.0, _attack_t))])
	_update_men()
	# radar
	var marks: Array = []
	var mine: Array = demo.get_tree().get_nodes_in_group("player_units").filter(func(n): return RtsCommander.is_mine(n))
	for t in towns:
		marks.append([t.pos, Color(0.2, 0.6, 1.0, 0.7) if t.owner == 0 else Color(0.9, 0.2, 0.15, 0.6), 11.0])
	for s in demo.get_tree().get_nodes_in_group("structures"):
		marks.append([s.global_position, Color(0.35, 0.85, 1.0) if s.team == 0 else Color(1.0, 0.3, 0.2), 7.0])
	for n in mine:
		marks.append([n.global_position, Color(0.45, 1.0, 0.5), 3.0 if n is RtsSoldier else 5.0])
	for e in demo.enemies:
		if is_instance_valid(e) and e.state != RtsSoldier.State.DEAD:
			for n in mine:
				if n.global_position.distance_to(e.global_position) < 140.0:
					marks.append([e.global_position, Color(1.0, 0.25, 0.2), 3.0])
					break
	hud.set_marks(marks)


func _update_men() -> void:
	var men: int = demo.get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0 and s.is_commandable()).size()
	var sel: Array = demo.commander.selection
	var txt := ""
	if not sel.is_empty():
		txt = "SELECTED %d  (%d squads)" % [sel.size(), demo.commander.squads_in(sel)]
	hud.set_men(men, txt)


func _towns_tick() -> void:
	for t in towns:
		var mine := 0
		var theirs := 0
		for s in demo.get_tree().get_nodes_in_group("soldiers") + demo.get_tree().get_nodes_in_group("enemies"):
			if s is RtsSoldier and s.can_fight() and s.global_position.distance_to(t.pos) < t.r:
				if s.team == 0: mine += 1
				else: theirs += 1
		for tk in demo.get_tree().get_nodes_in_group("tanks"):
			if not tk.destroyed and tk.global_position.distance_to(t.pos) < t.r:
				if tk.team == 0: mine += 2
				else: theirs += 2
		var side := -1
		if mine > 0 and theirs == 0: side = 0
		elif theirs > 0 and mine == 0: side = 1
		if side == -1 or side == t.owner:
			t.cap = maxf(0.0, t.cap - 0.05)
			continue
		t.cap += 0.06 * minf(4.0, float(mine if side == 0 else theirs)) / 2.0
		if t.cap >= 1.0:
			t.cap = 0.0
			t.owner = side
			var cloth: MeshInstance3D = t.flag.get_node("Cloth")
			cloth.material_override = BuildDefs.flag_material(side)
			if side == 0:
				hud.notify("%s captured! Income +%d%%" % [t.name, int(TOWN_BONUS * 100)], Color(0.6, 1.0, 0.65))
			else:
				hud.notify("%s was lost to the insurgents." % t.name, Color(1, 0.45, 0.35))


# ------------------------------------------------------------------ insurgent AI
func _enemy_ai() -> void:
	if stronghold == null or stronghold.dead:
		return
	_attack_t -= 1.0
	_refill_t -= 1.0
	var mins := clock / 60.0
	if _attack_t <= 0.0:
		_wave += 1
		_attack_t = maxf(110.0, 175.0 - mins * 4.0)
		var target := _raid_target()
		var n := mini(14, 4 + int(mins / 2.0))
		hud.notify("Insurgent raid #%d spotted moving west (%d fighters)!" % [_wave, n], Color(1, 0.6, 0.35))
		for i in n:
			var e := _enemy(ENEMY_HQ + Vector3(-20 + randf_range(-8, 8), 0, randf_range(-14, 14)), target + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)))
			if randf() < 0.25: e.rpg_rounds = 3
			_raiders.append(e)
		if mins > 7.0:
			for k in (1 if mins < 14.0 else 2):
				var dr := RtsDrone.launch(demo, ENEMY_HQ + Vector3(0, 18, 0), 1)
				dr.goal = target
		if mins > 11.0 and _wave % 2 == 0:
			var tk := demo._unit(RtsTank, "tank_enemy.glb", ENEMY_HQ.x - 30, ENEMY_HQ.z + 10, -90) as RtsTank
			if tk:
				tk.team = 1
				tk.wheel_radius = 0.36
				tk.move_to(target + (ENEMY_HQ - target).normalized() * 60.0)
				demo.enemy_tanks.append(tk)
	if _refill_t <= 0.0:
		_refill_t = 180.0
		for t in towns:
			if t.owner != 1:
				continue
			var alive := 0
			for e in demo.enemies:
				if is_instance_valid(e) and e.can_fight() and e.global_position.distance_to(t.pos) < t.r:
					alive += 1
			if alive < 3:
				for i in 2:
					_enemy(ENEMY_HQ + Vector3(-15, 0, randf_range(-10, 10)), t.pos + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15)))
	# raiders that reach a building blow it up
	_raiders = _raiders.filter(func(e): return is_instance_valid(e) and e.state != RtsSoldier.State.DEAD)
	for e in _raiders:
		if not e.can_fight() or e._nearest_enemy(25.0) != null:
			continue
		for s in demo.get_tree().get_nodes_in_group("structures_0"):
			var sz: Vector2 = s.def.size
			if e.global_position.distance_to(s.global_position) < maxf(sz.x, sz.y) * 0.5 + 5.0:
				e.plant_charge(s)
				break


func _raid_target() -> Vector3:
	# a town we hold, else the nearest of our buildings to their base, else the Command Post
	var best := hq.global_position
	var bd := INF
	for t in towns:
		if t.owner == 0:
			var d: float = t.pos.distance_to(ENEMY_HQ)
			if d < bd: bd = d; best = t.pos
	if bd == INF:
		for s in demo.get_tree().get_nodes_in_group("structures_0"):
			var d: float = s.global_position.distance_to(ENEMY_HQ)
			if d < bd: bd = d; best = s.global_position
	return best


# ------------------------------------------------------------------ end
func _check_defeat() -> void:
	if over:
		return
	var men: int = demo.get_tree().get_nodes_in_group("player_units").filter(func(n): return RtsCommander.is_mine(n)).size()
	if men == 0 and (_built("barracks").is_empty() or supply < 120.0):
		_defeat("No forces left.")


func _victory() -> void:
	if over: return
	over = true
	print("VICTORY")
	hud.big("VICTORY\nThe Insurgent Stronghold has fallen")
	hud.notify("Time %02d:%02d  |  built %d  |  trained %d  |  enemies killed %d" % [int(clock) / 60, int(clock) % 60, _stats.built, _stats.trained, _stats.killed], Color(1, 0.9, 0.6))


func _defeat(why: String) -> void:
	if over: return
	over = true
	print("DEFEAT: ", why)
	hud.big("DEFEAT\n" + why)
