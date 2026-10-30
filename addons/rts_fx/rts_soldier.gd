## Infantry soldier (soldier.glb with 43 animations, CC rig) with a real combat model:
##   move_to(pos)        - runs there; takes cover behind a nearby "cover" object on arrival
##   attack(pos | node)  - shoots (bullets hit with a chance; cover, crouch and distance matter)
##   throw_grenade(pos)  - overhand throw, explodes after landing
##   fire_rpg(pos)       - kneels, fires an RPG rocket
##   take_blast()        - called by RtsExplosion
## Bullets wound or kill. A wounded soldier bleeds out unless a squad mate drags him to safety
## and gives first aid (he then gets up with low HP). Soldiers suppress, reload, scavenge ammo
## from bodies and can surrender when isolated.
class_name RtsSoldier
extends Node3D

signal died
signal wounded
signal revived

enum State { IDLE, MOVE, COVER, SHOOT, DEAD, WOUNDED, DRAGGED, TREATED, RESCUE_RUN, DRAGGING, TREATING, BUSY, SURRENDERED }

@export var team := 0                       ## 0 = player, 1 = enemy
@export var max_hp := 100.0
@export var run_speed := 3.5                ## matches Run_Rifle (no foot sliding)
@export var turn_speed := 540.0             ## deg/s
@export var model_forward := Vector3(0, 0, 1)
@export var cover_search_radius := 4.0
@export var fire_interval := 0.16
@export var burst := 4
@export var accuracy := 0.45                ## hit chance at 0 m vs. an exposed standing target
@export var damage := 26.0
@export var weapon_range := 85.0
@export_range(0.0, 1.0) var wound_chance := 0.65
@export var bleed_out_time := 45.0
@export var treat_time := 6.0
@export var is_medic := false               ## medics treat twice as fast
@export var auto_engage := true             ## shoot the nearest visible enemy when idle
@export var mag_size := 30
@export var spare_mags := 6
@export var rpg_rounds := 0                 ## anti-tank soldier: fires RPGs at enemy tanks by himself
@export var rifle_scene: PackedScene = preload("res://assets/weapons/ak47_rifle.tscn")   # AK-47 (MaX3Dd, Sketchfab)
@export var rpg_scene: PackedScene = preload("res://assets/weapons/rpg7.glb")
@export var shovel_scene: PackedScene = preload("res://assets/weapons/shovel.glb")
## extra work animations (Dig_Shovel) per rig, merged into the AnimationPlayer at runtime
const WORK_ANIMS := {"CC_Base_Hip_01": "res://assets/anims/dig_soldier.glb", "mixamorig_Hips": "res://assets/anims/dig_terrorist.glb"}

const LOOPS := ["Idle_Rifle", "Walk_Rifle", "Run_Rifle", "Crouch_Idle", "Crouch_Walk", "Prone_Idle", "Prone_Crawl",
	"Stand_Shoot", "Crouch_Shoot", "Prone_Shoot", "Cover_Idle", "Wounded_Down", "Drag_Walk_Back", "Dragged_Loop",
	"First_Aid_Loop", "Wounded_Receive_Aid", "Surrender_Idle", "Prisoner_Walk", "Walk_Aim", "Dig_Shovel"]
## paired animation offsets (victim space; model faces +Z) - computed in Blender
const DRAG_OFFSET := Vector3(-0.08, 0.0, -1.30)
const DRAG_SPEED := 0.53
const MEDIC_OFFSET := Vector3(-0.565, 0.0, -0.488)
const MEDIC_YAW := PI / 2.0

var state := State.IDLE
var hp := 100.0
var partner: RtsSoldier = null
var suppression := 0.0
var ammo := 30
var stance := 0                              # 0 stand, 1 crouch, 2 prone

var _anim: AnimationPlayer
var _target: Variant = null
var _path := PackedVector3Array()            # remaining waypoints (river crossings go over bridges)
var _shoot_at: Variant = null
var _shoot_node: Node3D = null
var _cover_node: Node3D = null              # (legacy) kept for old callers
var _slot = null                            # CoverSystem.Slot the soldier is using
var _pending_slot = null                    # slot he is running to
var _threat := Vector3.ZERO                 # last known enemy direction source
var _danger_t := 0.0
var _fire_t := 0.0
var _burst_left := 0
var _pause := 0.0
var _bleed := 0.0
var _drag_left := 0.0
var _treat_left := 0.0
var _think := 0.0
var _order_t := 0.0                          # player order keeps AI from overriding for a while
var _rifle: Node3D
var _rpg: Node3D
var _socket: Node3D
var _back: Node3D
var _busy_token := 0
var _stun := 0.0
var objective: Variant = null              ## attackers: keep pushing toward this point, cover to cover
var _idle_t := 0.0
var _drone_t := 0.0
var _shovel: Node3D
var work_site: Node3D = null                ## construction site this soldier is assigned to
var _digging := false
var _work_check := 0.0
var selected := false: set = set_selected
var _ring: MeshInstance3D
static var _work_cache := {}


func _ready() -> void:
	add_to_group("units")
	add_to_group("soldiers" if team == 0 else "enemies")
	hp = max_hp
	ammo = mag_size
	_think = randf() * 0.5
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		_anim = aps[0]
		_merge_work_anims()
		for a in LOOPS:
			if _anim.has_animation(_res(a)):
				_anim.get_animation(_res(a)).loop_mode = Animation.LOOP_LINEAR
		_play("Idle_Rifle", 0.0)
		_anim.seek(randf() * 1.5, true)
	_socket = find_child("Weapon_Socket", true, false)
	_back = find_child("Back_Socket", true, false)
	if _socket and rifle_scene:
		_rifle = rifle_scene.instantiate()
		_socket.add_child(_rifle)
	if _socket and rpg_scene:
		_rpg = rpg_scene.instantiate()
		_rpg.visible = false
		_socket.add_child(_rpg)
	if _socket and shovel_scene:
		_shovel = shovel_scene.instantiate()
		_shovel.visible = false
		_socket.add_child(_shovel)


func set_team(t: int) -> void:
	remove_from_group("soldiers"); remove_from_group("enemies")
	team = t
	add_to_group("soldiers" if team == 0 else "enemies")


func is_alive() -> bool:
	return state != State.DEAD


func can_fight() -> bool:
	return state in [State.IDLE, State.MOVE, State.COVER, State.SHOOT]


## Can take player orders (fighting or digging).
func is_commandable() -> bool:
	return can_fight() or _digging


## Adds Dig_Shovel (made for this rig in Blender) to the imported AnimationPlayer.
func _merge_work_anims() -> void:
	var sk := find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	for bone in WORK_ANIMS:
		if (sk[0] as Skeleton3D).find_bone(bone) < 0:
			continue
		var path: String = WORK_ANIMS[bone]
		if not _work_cache.has(path):
			_work_cache[path] = {}
			if ResourceLoader.exists(path):
				var n: Node = load(path).instantiate()
				var ap := n.find_children("*", "AnimationPlayer", true, false)
				if ap.size() > 0:
					for a in (ap[0] as AnimationPlayer).get_animation_list():
						_work_cache[path][a] = (ap[0] as AnimationPlayer).get_animation(a)
				n.free()
		var lib := _anim.get_animation_library("")
		for a in _work_cache[path]:
			if lib and not lib.has_animation(a):
				var anim: Animation = _work_cache[path][a]
				anim.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(a, anim)
		return


## Construction work: run to `slot`, face the site and dig until stop_work() (the site calls it).
func work_on(site: Node3D, slot: Vector3) -> void:
	if not can_fight() and state != State.BUSY:
		return
	if state == State.BUSY and work_site == site and _digging:
		return
	work_site = site
	_digging = false
	_set_tool(false)
	state = State.IDLE
	move_to(slot)
	_order_t = 0.0
	while state == State.MOVE and work_site == site:
		await get_tree().physics_frame
	if work_site != site or not is_instance_valid(site) or not (state in [State.IDLE, State.COVER]):
		return
	state = State.BUSY
	_busy_token += 1
	_set_slot(null)
	stance = 0
	_face_instant(site.face_point(global_position) if site.has_method("face_point") else site.global_position)
	_set_tool(true)
	_digging = true
	_play("Dig_Shovel", 0.3, randf_range(0.9, 1.1))
	if _anim: _anim.seek(randf() * 1.5, false)


## Sabotage: kneel at an enemy building, set a charge, step back. Boom.
func plant_charge(target: Node3D) -> void:
	if not can_fight() or target == null:
		return
	state = State.BUSY
	_face_instant(target.global_position)
	await _play_once("Loot_Body", "Crouch_Idle")
	if state != State.BUSY or not is_instance_valid(target):
		return
	state = State.IDLE
	var at := global_position.lerp(target.global_position, 0.5)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(target) and target.is_inside_tree():
			RtsExplosion.spawn(target.get_parent(), at, 0.9)
			if target.has_method("damage"): target.damage(110.0))
	move_to(global_position + (global_position - target.global_position).normalized() * 12.0)


func is_digging() -> bool:
	return _digging and state == State.BUSY


func stop_work(release := true) -> void:
	if release:
		work_site = null
	var was := _digging
	_digging = false
	_set_tool(false)
	if was and state == State.BUSY:
		state = State.IDLE
		_play(_idle_anim(), 0.3)


func _set_tool(on: bool) -> void:
	if _shovel: _shovel.visible = on
	if _rifle and is_instance_valid(_rifle):
		_holster(on)          # rifle goes on the back while digging


## Selection ring (player units)
func set_selected(v: bool) -> void:
	selected = v
	if v and _ring == null:
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42; tm.outer_radius = 0.5; tm.rings = 24; tm.ring_segments = 6
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 1.0, 0.55) if team == 0 else Color(1, 0.35, 0.3)
		m.no_depth_test = true
		tm.material = m
		_ring.mesh = tm
		_ring.scale = Vector3(1, 0.15, 1)
		_ring.position.y = 0.06
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	if _ring:
		_ring.visible = v and state != State.DEAD


## Godot's importer strips a "_Loop" suffix (Dragged_Loop -> Dragged); accept both names.
func _res(n: String) -> String:
	if _anim and not _anim.has_animation(n) and n.ends_with("_Loop"):
		return n.trim_suffix("_Loop")
	return n


func _play(n: String, blend := 0.2, speed := 1.0) -> void:
	n = _res(n)
	if _anim and _anim.has_animation(n) and _anim.current_animation != n:
		_anim.play(n, blend, speed)


## One-shot animation, then `next` (loop). Returns after the clip (await-able).
func _play_once(n: String, next: String, blend := 0.15) -> bool:
	_busy_token += 1
	var tok := _busy_token
	n = _res(n); next = _res(next)
	if _anim == null or not _anim.has_animation(n):
		return true
	_anim.play(n, blend)
	await get_tree().create_timer(_anim.get_animation(n).length).timeout
	if tok != _busy_token or not is_inside_tree():
		return false
	if state != State.DEAD and next != "":
		_anim.play(next, 0.12)
	return true


func forward() -> Vector3:
	var f := global_basis * model_forward
	f.y = 0
	return f.normalized()


# ------------------------------------------------------------------ orders
func move_to(p: Vector3) -> void:
	if not can_fight() and not _digging:
		return
	_order_t = 6.0
	if _digging:
		_digging = false
		_set_tool(false)
	_path = RtsNav.find_path(global_position, p)
	var first: Vector3 = _path[0]
	_path.remove_at(0)
	_target = Vector3(first.x, global_position.y, first.z)
	_shoot_at = null
	_shoot_node = null
	_set_slot(null)
	if _pending_slot != null:
		CoverSystem.release(_pending_slot, self)
		_pending_slot = null
	stance = 0
	state = State.MOVE
	_busy_token += 1
	_play("Run_Rifle")


func attack(p) -> void:
	if _digging:
		stop_work()
	if not can_fight():
		return
	_order_t = 8.0
	if p is Node3D:
		_shoot_node = p
		_shoot_at = (p as Node3D).global_position
	else:
		_shoot_node = null
		_shoot_at = p
	_burst_left = burst
	if state == State.COVER:
		_play("Cover_Peek_Shoot", 0.15)
	else:
		_target = null
		state = State.SHOOT
		_play(_shoot_anim())


func throw_grenade(p: Vector3) -> void:
	if not can_fight():
		return
	state = State.BUSY
	_face_instant(p)
	get_tree().create_timer(1.0).timeout.connect(func():
		if state == State.BUSY and is_inside_tree():
			var from := global_position + Vector3.UP * 1.9
			RtsGrenade.throw(get_parent(), from, p))
	await _play_once("Throw_Grenade", "Idle_Rifle")
	if state == State.BUSY: state = State.IDLE


func fire_rpg(p: Vector3) -> void:
	if not can_fight():
		return
	state = State.BUSY
	_face_instant(p)
	if _rifle: _rifle.visible = false
	if _rpg: _rpg.visible = true
	get_tree().create_timer(36.0 / 30.0).timeout.connect(func():
		if state == State.BUSY and is_inside_tree():
			var from := global_position + Vector3.UP * 1.25 + forward() * 0.9
			RtsExplosion.muzzle_flash(get_parent(), from, forward(), 0.5)
			RtsExplosion.muzzle_flash(get_parent(), from - forward() * 1.6, -forward(), 0.7)   # back-blast
			RtsProjectile.launch(get_parent(), from, p, 70.0, 1.0, true))
	await _play_once("Fire_RPG_Kneel", "Crouch_Idle")
	if _rifle: _rifle.visible = true
	if _rpg: _rpg.visible = false
	if state == State.BUSY:
		state = State.IDLE
		stance = 1


# ------------------------------------------------------------------ damage
## Bullet hit (called by the shooter after the bullet's travel time).
func take_hit(dmg: float, from: Vector3) -> void:
	if state == State.DEAD:
		return
	if state in [State.WOUNDED, State.DRAGGED, State.TREATED]:
		if randf() < 0.12:              # a soldier lying on the ground is rarely hit again
			_die(from, false)
		return
	if state == State.SURRENDERED:
		return
	hp -= dmg
	_threat = from
	suppression = minf(suppression + 0.5, 1.5)
	if hp > 0.0:
		if state in [State.IDLE, State.COVER, State.SHOOT]:
			_face_instant(from)
			_play_once("Hit_React", _idle_anim(), 0.05)
		return
	if randf() < wound_chance:
		_become_wounded(from)
	else:
		_die(from, false)


func take_blast(at: Vector3, radius: float) -> void:
	if state == State.DEAD:
		return
	var d := global_position.distance_to(at)
	if d > radius:
		return
	# cover protects from blasts on the other side of it
	var prot := CoverSystem.protection(_slot, at) if state == State.COVER else 0.0
	var protected := prot > 0.5
	if stance == 2: protected = protected or d > radius * 0.35
	# dug-in trench / crater: only a (nearly) direct hit gets through
	if state == State.COVER and _slot != null and _slot.omni() and _slot.prot >= 0.6:
		protected = protected or d > radius * 0.25
	if d < radius * 0.55 and not protected:
		if state in [State.WOUNDED, State.DRAGGED, State.TREATED] or d < radius * 0.3:
			_die(at, true)
		else:
			_become_wounded(at)
	else:
		suppression = 1.5
		if can_fight():
			_face_instant(at)
			_play_once("Hit_React", _idle_anim(), 0.05)
			if d < radius * 0.9:
				_stun = randf_range(2.0, 4.0)       # shell-shocked: can't shoot for a moment


## Nearby bullet / explosion: pins the soldier down.
func suppress(amount: float) -> void:
	if can_fight():
		suppression = minf(suppression + amount, 1.5)


func _become_wounded(from: Vector3) -> void:
	stop_work(false)
	_set_slot(null)
	_abort_partner()
	state = State.WOUNDED
	_target = null; _shoot_at = null; _shoot_node = null
	_bleed = bleed_out_time
	max_hp = maxf(40.0, max_hp * 0.85)          # every wound makes him weaker
	remove_from_group("units")
	add_to_group("wounded")
	_face_instant(from)
	wounded.emit()
	blood(get_parent(), global_position, 1.1)
	await _play_once("Wounded_Fall", "Wounded_Down", 0.08)


func _die(at: Vector3, blast: bool) -> void:
	var was_down := state in [State.WOUNDED, State.DRAGGED, State.TREATED]
	stop_work()
	_set_slot(null)
	if _ring: _ring.visible = false
	_abort_partner()
	state = State.DEAD
	_busy_token += 1
	_target = null; _shoot_at = null; _shoot_node = null
	remove_from_group("units"); remove_from_group("wounded")
	add_to_group("corpses")
	blood(get_parent(), global_position, 1.6)
	if blast and not was_down:
		_fling(at)
	if was_down:
		if _anim: _anim.pause()
	else:
		_face_instant(at)
		if _anim: _anim.play("Death_Backward" if blast else "Death_Forward", 0.08)
		get_tree().create_timer(0.6 if blast else 0.55).timeout.connect(_drop_weapon)
	died.emit()


static var _blood_tex: Texture2D = null

static func blood(parent: Node, pos: Vector3, size := 1.3) -> void:
	if _blood_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0.32, 0.0, 0.0, 0.95), Color(0.25, 0.0, 0.0, 0.8), Color(0.2, 0.0, 0.0, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1.0, 0.5)
		t.width = 64; t.height = 64
		_blood_tex = t
	var d := Decal.new()
	d.cull_mask = RtsGround.DECAL_LAYER
	d.texture_albedo = _blood_tex
	d.size = Vector3(size * randf_range(0.8, 1.3), 1.5, size * randf_range(0.8, 1.3))
	d.rotation.y = randf() * TAU
	d.albedo_mix = 0.9
	parent.add_child(d)
	d.global_position = pos


## Explosion throws the body (cheap ragdoll): arc away from the blast while Death_Backward plays.
func _fling(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0
	if away.length() < 0.1: away = -forward()
	away = away.normalized() * randf_range(2.5, 5.5)
	var start := global_position
	var end := start + away
	end.y = RtsGround.height(end.x, end.z)
	var h := randf_range(1.2, 2.4)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := start.lerp(end, t)
		p.y = lerpf(start.y, end.y, t) + 4.0 * h * t * (1.0 - t)
		global_position = p, 0.0, 1.0, 0.7)


func _drop_weapon() -> void:
	if _rifle == null or not is_instance_valid(_rifle) or not is_inside_tree():
		return
	var gt := _rifle.global_transform
	_rifle.reparent(get_parent())
	_rifle.global_transform = gt
	var gy := RtsGround.height(gt.origin.x, gt.origin.z) + 0.05
	var flat := Transform3D(Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, PI / 2), Vector3(gt.origin.x, gy, gt.origin.z))
	var tw := _rifle.create_tween()
	tw.tween_property(_rifle, "global_transform", flat, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_rifle = null


# ------------------------------------------------------------------ rescue
func _find_rescuer() -> void:
	if state != State.WOUNDED:
		return
	var best: RtsSoldier = null
	var bd := 40.0
	for s in get_tree().get_nodes_in_group("soldiers" if team == 0 else "enemies"):
		var r := s as RtsSoldier
		if r == null or r == self or not r.can_fight() or r.partner != null:
			continue
		var d := r.global_position.distance_to(global_position) * (0.6 if r.is_medic else 1.0)
		if d < bd:
			bd = d; best = r
	if best:
		best._start_rescue(self)


func _start_rescue(victim: RtsSoldier) -> void:
	partner = victim
	victim.partner = self
	state = State.RESCUE_RUN
	_shoot_at = null; _shoot_node = null; _target = null
	_busy_token += 1
	_play("Run_Rifle")


func _grab_transform() -> Transform3D:
	var vt := partner.global_transform
	return Transform3D(vt.basis, vt * DRAG_OFFSET)


func _abort_partner() -> void:
	if partner == null:
		return
	var p := partner
	partner = null
	if not is_instance_valid(p):
		return
	p.partner = null
	if p.state in [State.DRAGGED, State.TREATED]:
		p.state = State.WOUNDED
		p._busy_token += 1
		p._play("Wounded_Down")
	elif p.state in [State.RESCUE_RUN, State.DRAGGING, State.TREATING]:
		p._holster(false)
		p.state = State.IDLE
		p._busy_token += 1
		p._play("Crouch_Idle")


func _holster(on_back: bool) -> void:
	if _rifle == null or not is_instance_valid(_rifle):
		return
	var t := _back if on_back else _socket
	if t and _rifle.get_parent() != t:
		_rifle.reparent(t, false)
		_rifle.transform = Transform3D.IDENTITY


func _rescue_run(delta: float) -> void:
	if partner == null or not is_instance_valid(partner) or partner.state != State.WOUNDED:
		partner = null
		state = State.IDLE
		_play("Idle_Rifle")
		return
	var goal := _grab_transform()
	var to := goal.origin - global_position
	to.y = 0
	if to.length() > 0.2:
		_turn_towards(goal.origin, delta)
		var np := global_position + to.normalized() * minf(run_speed * delta, to.length())
		np.y = RtsGround.height(np.x, np.z)
		global_position = np
		return
	global_transform = Transform3D(goal.basis, Vector3(goal.origin.x, RtsGround.height(goal.origin.x, goal.origin.z), goal.origin.z))
	state = State.DRAGGING
	partner.state = State.DRAGGED
	_drag_left = randf_range(5.0, 8.0)
	_holster(false)
	partner._play_once("Dragged_Grab", "Dragged_Loop")
	_pause = 24.0 / 30.0                      # wait for the grab before moving


func _drag_step(delta: float) -> void:
	if partner == null or not is_instance_valid(partner) or partner.state != State.DRAGGED:
		_abort_partner(); state = State.IDLE; _play("Crouch_Idle"); return
	if _pause > 0.0:
		_pause -= delta
		if _anim.current_animation != "Drag_Grab" and _pause > 0.7:
			_play("Drag_Grab", 0.1)
		if _pause <= 0.0:
			_play("Drag_Walk_Back", 0.1)
		return
	var back := -(global_basis * model_forward)
	back.y = 0
	var step := back.normalized() * DRAG_SPEED * delta
	for n in [self, partner]:
		var np: Vector3 = n.global_position + step
		np.y = RtsGround.height(np.x, np.z)
		n.global_position = np
	_drag_left -= DRAG_SPEED * delta
	if _drag_left <= 0.0:
		_begin_treatment()


func _begin_treatment() -> void:
	state = State.BUSY
	var v := partner
	v._play_once("Dragged_Release", "Wounded_Down")
	var ok := await _play_once("Drag_Release", "")
	if not ok or partner != v or v.state == State.DEAD:
		return
	var vt := v.global_transform
	global_transform = vt * Transform3D(Basis(Vector3.UP, MEDIC_YAW), MEDIC_OFFSET)
	_holster(true)
	v.state = State.TREATED
	v._play("Wounded_Receive_Aid")
	ok = await _play_once("First_Aid_Start", "First_Aid_Loop")
	if not ok or partner != v:
		return
	state = State.TREATING
	_treat_left = treat_time * (0.5 if is_medic else 1.0)


func _finish_treatment() -> void:
	var v := partner
	partner = null
	state = State.BUSY
	if v and is_instance_valid(v) and v.state == State.TREATED:
		v.partner = null
		v._revive()
	await _play_once("First_Aid_End", "Crouch_Idle")
	_holster(false)
	if state == State.BUSY:
		state = State.IDLE
		stance = 1


func _revive() -> void:
	state = State.BUSY
	hp = maxf(35.0, max_hp * 0.4)
	remove_from_group("wounded")
	var ok := await _play_once("Revive_Get_Up", "Crouch_Idle")
	if ok and state == State.BUSY:
		add_to_group("units")
		state = State.IDLE
		stance = 1
		revived.emit()


# ------------------------------------------------------------------ prisoners / scavenging
func surrender() -> void:
	if not can_fight():
		return
	stop_work()
	state = State.SURRENDERED
	_target = null; _shoot_at = null; _shoot_node = null
	remove_from_group("units")
	add_to_group("prisoners")
	get_tree().create_timer(0.2).timeout.connect(_drop_weapon)
	await _play_once("Surrender", "Surrender_Idle")


func _loot_nearest_body() -> bool:
	var best: Node3D = null
	var bd := 18.0
	for c in get_tree().get_nodes_in_group("corpses"):
		var d := (c as Node3D).global_position.distance_to(global_position)
		if d < bd and not c.has_meta("looted"):
			bd = d; best = c
	if best == null:
		return false
	best.set_meta("looted", true)
	state = State.BUSY
	var spot: Vector3 = best.global_position + (global_position - best.global_position).normalized() * 0.65
	while global_position.distance_to(spot) > 0.3 and state == State.BUSY:
		_play("Run_Rifle")
		_turn_towards(spot, get_physics_process_delta_time())
		var np := global_position.move_toward(spot, run_speed * get_physics_process_delta_time())
		np.y = RtsGround.height(np.x, np.z)
		global_position = np
		await get_tree().physics_frame
	if state != State.BUSY:
		return false
	_face_instant(best.global_position)
	await _play_once("Loot_Body", "Crouch_Idle")
	spare_mags += 3
	if state == State.BUSY:
		state = State.IDLE
	return true


# ------------------------------------------------------------------ helpers
func _idle_anim() -> String:
	if state == State.COVER: return "Cover_Idle"
	return ["Idle_Rifle", "Crouch_Idle", "Prone_Idle"][stance]


func _shoot_anim() -> String:
	return ["Stand_Shoot", "Crouch_Shoot", "Prone_Shoot"][stance]


func _face_instant(p: Vector3) -> void:
	var to := p - global_position
	to.y = 0
	if to.length() > 0.05:
		rotate_y(forward().signed_angle_to(to.normalized(), Vector3.UP))


func _turn_towards(p: Vector3, delta: float) -> float:
	var to := p - global_position
	to.y = 0
	if to.length() < 0.05:
		return 0.0
	var ang := forward().signed_angle_to(to.normalized(), Vector3.UP)
	var step := deg_to_rad(turn_speed) * delta
	rotate_y(clampf(ang, -step, step))
	return abs(ang)


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies" if team == 0 else "soldiers")


func _nearest_enemy(max_d: float) -> RtsSoldier:
	var best: RtsSoldier = null
	var bd := max_d
	for e in _enemies():
		var s := e as RtsSoldier
		if s == null or not (s.can_fight() or s.state in [State.RESCUE_RUN, State.DRAGGING, State.TREATING] or s._digging):
			continue
		var d := s.global_position.distance_to(global_position)
		if not s.can_fight(): d *= 1.6          # prefer soldiers who shoot back
		if d < bd:
			bd = d; best = s
	return best


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	suppression = maxf(0.0, suppression - delta * 0.25)
	_stun = maxf(0.0, _stun - delta)
	if can_fight() and hp < max_hp:
		for t in get_tree().get_nodes_in_group("medical"):
			if (t as Node3D).global_position.distance_to(global_position) < 10.0:
				hp = minf(max_hp, hp + 6.0 * delta)
				break
	if state == State.WOUNDED:
		for t in get_tree().get_nodes_in_group("medical"):
			if (t as Node3D).global_position.distance_to(global_position) < 10.0:
				_bleed = bleed_out_time      # near the medical tent nobody bleeds out
	_order_t = maxf(0.0, _order_t - delta)
	# diggers drop the shovel and fight when the enemy shows up (the site calls them back later)
	if _digging:
		_work_check -= delta
		if _work_check <= 0.0:
			_work_check = 0.7
			if suppression > 0.45 or _nearest_enemy(minf(weapon_range, 70.0)) != null:
				stop_work(false)
	match state:
		State.WOUNDED:
			_bleed -= delta
			if _bleed <= 0.0:
				_die(global_position, false)
				return
			_think -= delta
			if _think <= 0.0:
				_think = 2.0
				_find_rescuer()
		State.DRAGGED:
			_bleed -= delta * 0.5
		State.RESCUE_RUN:
			_rescue_run(delta)
		State.DRAGGING:
			_drag_step(delta)
		State.TREATING:
			_treat_left -= delta
			if _treat_left <= 0.0:
				_finish_treatment()
		State.MOVE:
			var to: Vector3 = _target - global_position
			to.y = 0
			if not _path.is_empty() and to.length() < 1.2:
				_target = _path[0]
				_path.remove_at(0)
			elif to.length() < 0.4:
				_arrive()
			else:
				_turn_towards(_target, delta)
				var slow := 1.0
				for w in get_tree().get_nodes_in_group("wire"):
					if (w as Node3D).global_position.distance_to(global_position) < 3.0:
						slow = 0.3
						break
				var np := global_position + forward() * run_speed * slow * delta * clampf(to.length() / 1.5, 0.3, 1.0)
				np.y = RtsGround.height(np.x, np.z)
				global_position = np
		State.SHOOT, State.COVER, State.IDLE:
			_combat(delta)


func _anti_drone_and_tank(delta: float) -> bool:
	_drone_t -= delta
	if _drone_t > 0.0 or _stun > 0.0:
		return false
	_drone_t = 0.5
	# FPV drones nearby: everybody shoots at them (hard to hit)
	for d in get_tree().get_nodes_in_group("drones_%d" % (1 - team)):
		var dn := d as Node3D
		if dn.global_position.distance_to(global_position) < 40.0:
			_face_instant(dn.global_position)
			var from := global_position + Vector3.UP * 1.4
			RtsExplosion.muzzle_flash(get_parent(), from, (dn.global_position - from).normalized(), 0.1)
			RtsProjectile.launch(get_parent(), from, dn.global_position + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), 320.0, 0.0, false)
			if randf() < 0.14:
				dn.take_hit(10.0, global_position)
			if state != State.COVER: _play(_shoot_anim())
			return true
	# anti-tank soldier
	if rpg_rounds > 0 and state != State.BUSY:
		for t in get_tree().get_nodes_in_group("tanks"):
			if t.get("team") != team and (t as Node3D).global_position.distance_to(global_position) < 75.0:
				rpg_rounds -= 1
				# lead a moving tank: wind-up 1.2 s + rocket flight
				var tp := (t as Node3D).global_position
				var lead: Vector3 = t.hull_forward() * float(t.get("_speed")) * (1.2 + tp.distance_to(global_position) / 70.0)
				fire_rpg(tp + lead + Vector3.UP * 1.0)
				return true
		if rpg_rounds > 1 and _nearest_enemy(60.0) == null:
			for b in get_tree().get_nodes_in_group("structures_%d" % (1 - team)):
				if (b as Node3D).global_position.distance_to(global_position) < 55.0:
					rpg_rounds -= 1
					fire_rpg((b as Node3D).global_position + Vector3.UP * 1.5)
					return true
	return false


func _combat(delta: float) -> void:
	if _stun > 0.0:
		return
	# artillery warning circle: get out (a man deep in a trench stays down)
	_danger_t -= delta
	if _danger_t <= 0.0:
		_danger_t = 0.4
		var dz = CoverSystem.danger_at(global_position)
		if dz != null and not (_slot != null and _slot.kind == "trench"):
			_flee(dz)
			return
	if _anti_drone_and_tank(delta):
		return
	# pinned down by fire: crouch, then go prone
	var want := 0
	if suppression > 1.0: want = 2
	elif suppression > 0.35: want = 1
	if state != State.COVER and want > stance:
		stance = want
		_play(_shoot_anim() if state == State.SHOOT else _idle_anim(), 0.25)
	_think -= delta
	if _think <= 0.0:
		_think = 0.6 + randf() * 0.4
		if _shoot_node and (not is_instance_valid(_shoot_node) or (_shoot_node as RtsSoldier).state in [State.DEAD, State.WOUNDED, State.DRAGGED, State.TREATED, State.SURRENDERED]):
			_shoot_node = null
			_shoot_at = null
		if auto_engage and _shoot_at == null and _order_t <= 0.0:
			var e := _nearest_enemy(weapon_range)
			if e:
				_shoot_node = e
				_shoot_at = e.global_position
				_burst_left = burst
				if state == State.IDLE:
					state = State.SHOOT
					_play(_shoot_anim())
				elif state == State.COVER:
					_anim.play("Cover_Peek_Shoot", 0.15)
		if _shoot_at == null and state == State.SHOOT:
			state = State.IDLE
			_play(_idle_anim())
		if objective != null and _shoot_at == null and state in [State.IDLE, State.COVER]:
			_idle_t += 0.8
			if _idle_t > 2.0:
				_idle_t = 0.0
				_advance()
				return
		# under fire in the open: run to the nearest cover that faces the threat
		if state in [State.IDLE, State.SHOOT] and suppression > 0.45 and _order_t <= 0.0:
			var threat: Vector3 = _shoot_at if _shoot_at != null else global_position + forward() * 10.0
			var c = CoverSystem.best(self, threat, 18.0)
			if c and Vector2(c.pos.x - global_position.x, c.pos.z - global_position.z).length() > 1.2:
				var keep_target = _shoot_node
				_go_to_slot(c)
				_shoot_node = keep_target
				return
		# isolated, wounded enemy under fire may give up
		if team == 1 and hp < max_hp * 0.5 and suppression > 0.8 and randf() < 0.08:
			var friends := 0
			for f in get_tree().get_nodes_in_group("enemies"):
				if f != self and (f as Node3D).global_position.distance_to(global_position) < 25.0 and (f as RtsSoldier).can_fight():
					friends += 1
			if friends == 0:
				surrender()
				return
	if _shoot_at == null:
		return
	if _shoot_node and is_instance_valid(_shoot_node):
		_shoot_at = _shoot_node.global_position
	_threat = _shoot_at
	var off := _turn_towards(_shoot_at, delta) if state != State.COVER else 0.0
	_fire_t -= delta
	if state == State.COVER and suppression > 1.15:
		return                                  # pinned down: head stays below the cover
	if _fire_t <= 0.0 and off < 0.25 and _burst_left > 0:
		if ammo <= 0:
			_reload()
			return
		_fire_t = fire_interval * randf_range(0.8, 1.4)
		_burst_left -= 1
		ammo -= 1
		_shoot_once(_shoot_at)
	if _burst_left <= 0:
		_pause -= delta
		if _pause <= 0.0:
			_pause = randf_range(0.6, 1.4) * (1.0 + suppression)
			_burst_left = burst
			if state == State.COVER:
				_play("Cover_Idle")
				get_tree().create_timer(_pause * 0.6).timeout.connect(func():
					if state == State.COVER and _shoot_at != null:
						_anim.play("Cover_Peek_Shoot", 0.15))


## Attackers move toward `objective` in bounds of ~25 m, preferring cover on the way.
func _advance() -> void:
	var obj: Vector3 = objective
	var to := obj - global_position
	to.y = 0
	if to.length() < 6.0:
		# objective taken: hunt the nearest enemy still standing
		var e := _nearest_enemy(500.0)
		if e == null:
			return
		var ep := e.global_position
		objective = ep + (global_position - ep).normalized() * 12.0
		obj = objective
		to = obj - global_position
		to.y = 0
		if to.length() < 6.0:
			return
	var step := to.normalized() * minf(25.0, to.length())
	var spot := global_position + step + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	# bound forward from cover to cover
	var c = CoverSystem.best(self, obj, 26.0, spot)
	if c and Vector2(obj.x - c.pos.x, obj.z - c.pos.z).length() < to.length() - 4.0:
		_go_to_slot(c)
		return
	spot.y = RtsGround.height(spot.x, spot.z)
	move_to(spot)
	_order_t = 0.0


## Builder: walk to the site, kneel and work for `secs`, then go back.
func work_at(p: Vector3, secs: float) -> void:
	if not can_fight():
		return
	var home := global_position
	move_to(p + (global_position - p).normalized() * 1.2)
	while state == State.MOVE:
		await get_tree().physics_frame
	if not can_fight():
		return
	state = State.BUSY
	_face_instant(p)
	_play("Loot_Body", 0.2)
	await get_tree().create_timer(secs).timeout
	if state == State.BUSY:
		state = State.IDLE
		move_to(home)


func _reload() -> void:
	if spare_mags <= 0:
		_shoot_at = null; _shoot_node = null
		state = State.IDLE
		_loot_nearest_body()
		return
	var prev := state
	state = State.BUSY
	var ok := await _play_once("Reload_Crouch" if stance > 0 or prev == State.COVER else "Reload_Stand", "")
	if not ok or state != State.BUSY:
		return
	spare_mags -= 1
	ammo = mag_size
	state = prev if prev in [State.COVER, State.SHOOT] else State.IDLE
	_play("Cover_Idle" if state == State.COVER else (_shoot_anim() if state == State.SHOOT else _idle_anim()))


func _arrive() -> void:
	_target = null
	var c = _pending_slot
	_pending_slot = null
	if c == null or not c.alive or not CoverSystem.is_free(c, self) or Vector2(c.pos.x - global_position.x, c.pos.z - global_position.z).length() > 2.5:
		c = CoverSystem.best(self, _shoot_at if _shoot_at != null else (_threat if _threat != Vector3.ZERO else null), cover_search_radius)
	if c:
		_set_slot(c)
		state = State.COVER
		stance = 2 if c.kind == "crater" else 1
		if c.omni():
			_face_instant(_shoot_at if _shoot_at != null else (_threat if _threat != Vector3.ZERO else global_position + forward()))
		else:
			_face_instant(global_position + c.dir)
		_play_once("Cover_Enter", "Cover_Idle")
		if _shoot_node and is_instance_valid(_shoot_node):
			_shoot_at = _shoot_node.global_position
			_burst_left = burst
	else:
		state = State.IDLE
		_play(_idle_anim(), 0.25)


static func _covered(target: RtsSoldier, from: Vector3) -> float:
	if target.state != State.COVER or target._slot == null:
		return 0.0
	return CoverSystem.protection(target._slot, from)


## Take / leave a cover slot.
func _set_slot(sl) -> void:
	if _slot != null and _slot != sl:
		CoverSystem.release(_slot, self)
	_slot = sl
	_cover_node = null
	if sl != null:
		CoverSystem.claim(sl, self)


## Run to a cover slot and take it on arrival.
func _go_to_slot(sl) -> void:
	move_to(sl.pos)
	_order_t = 0.0
	_pending_slot = sl
	CoverSystem.claim(sl, self)


func _shoot_once(p: Vector3) -> void:
	var h: float = [1.45, 1.05, 0.35][stance]
	if state == State.COVER: h = 1.15
	var from: Vector3 = global_position + Vector3.UP * h + forward() * 0.7
	# pick the soldier being aimed at (explicit target, else whoever is close to the aim point)
	var tgt: RtsSoldier = _shoot_node as RtsSoldier
	if tgt == null:
		var bd := 3.0
		for e in _enemies():
			var s := e as RtsSoldier
			if s and s.can_fight():
				var d := s.global_position.distance_to(p)
				if d < bd: bd = d; tgt = s
	var dist: float = from.distance_to(p)
	var hit := false
	if tgt and dist <= weapon_range:
		var chance := accuracy * clampf(1.15 - dist / weapon_range, 0.15, 1.0)
		var low: int = tgt.stance
		if tgt.state in [State.RESCUE_RUN]: low = 1
		if tgt.state in [State.DRAGGING, State.TREATING]: low = 2
		chance *= [1.0, 0.75, 0.45][low]
		chance *= 1.0 - _covered(tgt, from) * 0.75
		chance *= 1.0 - suppression * 0.4
		if state == State.MOVE: chance *= 0.5
		hit = randf() < chance
	var aim := p + Vector3.UP * 1.0
	if tgt:
		aim = tgt.global_position + Vector3.UP * [1.25, 0.9, 0.3][tgt.stance]
	var miss := Vector3(randf_range(-1.6, 1.6), randf_range(-0.4, 0.8), randf_range(-1.6, 1.6))
	var end := aim if hit else aim + miss
	if not hit:
		end.y = maxf(end.y, RtsGround.height(end.x, end.z))
	RtsExplosion.muzzle_flash(get_parent(), from, (end - from).normalized(), 0.1)
	RtsProjectile.launch(get_parent(), from, end, 320.0, 0.0, false)
	var travel: float = from.distance_to(end) / 320.0
	if tgt:
		var dmg := damage * randf_range(0.7, 1.3)
		var src := global_position
		get_tree().create_timer(travel).timeout.connect(func():
			if is_instance_valid(tgt) and tgt.state != State.DEAD:
				if hit: tgt.take_hit(dmg, src)
				else: tgt.suppress(0.18))


## Run out of an artillery danger zone: best cover outside it, else straight away.
func _flee(dz: Dictionary) -> void:
	var c: Vector3 = dz.pos
	var r: float = dz.r
	var away := global_position - c
	away.y = 0
	if away.length() < 0.5:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var out := c + away.normalized() * (r + 8.0)
	var sl = CoverSystem.best(self, c, r + 18.0, out)
	if sl != null and not CoverSystem.in_danger(sl.pos):
		_go_to_slot(sl)
	else:
		move_to(out)
		_order_t = 0.0
	suppression = maxf(suppression, 0.8)
	if randf() < 0.4:
		RtsBubble.say(self, ["INCOMING!", "GET DOWN!", "ARTILLERY!", "MOVE!"][randi() % 4], 1.6)
