## Tank controller for a rigged tank model (made for "Low Poly T-72 Tank - Game Ready").
## Put the tank .glb as a CHILD of a Node3D that has this script.
##   move_to(world_pos)  - drive there (turns hull, spins road wheels, kicks up dust)
##   aim_at(world_pos)   - rotate turret
##   fire_at(world_pos)  - aim, then fire when aligned (muzzle blast, recoil, shell, explosion)
class_name RtsTank
extends Node3D

signal fired(target: Vector3)

@export var turret_bone := "Turret_07"
@export var barrel_bone := "Barrel_08"
@export var muzzle_bone := "BulletSpawn_09"
@export var wheel_bone_prefix := "Wheel."
@export var wheel_radius := 0.42

@export var max_speed := 8.0           # m/s
@export var acceleration := 3.0
@export var hull_turn_speed := 40.0    # deg/s
@export var turret_turn_speed := 35.0  # deg/s
@export var reload_time := 4.0
@export var shell_speed := 160.0
@export var explosion_size := 1.2
@export var recoil_distance := 0.45
@export var team := 0                  ## 0 = player, 1 = enemy
@export var max_hp := 100.0
@export var auto_engage := true        ## fire at the nearest enemy tank / infantry by itself
@export var engage_range := 140.0

var hp := 100.0
var destroyed := false
var _think := 0.0
var _order_t := 0.0

var _skel: Skeleton3D
var _model: Node3D
var _model_base := Transform3D.IDENTITY
var _turret := -1
var _barrel := -1
var _muzzle := -1
var _wheels: Array[int] = []
var _turret_axis := Vector3.UP          # in turret bone local space
var _wheel_axes: Array[Vector3] = []
var _barrel_back := Vector3.ZERO        # in turret local space
var _hull_fwd_local := Vector3.FORWARD  # hull forward in this node's local space

var _move_target: Variant = null
var _aim_target: Variant = null
var _pending_fire: Variant = null
var _speed := 0.0
var _turret_yaw := 0.0
var _wheel_angle := 0.0
var _reload := 0.0
var _recoil := 0.0
var _rock := 0.0
var _dust: GPUParticles3D

func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("units")
	add_to_group("tanks")
	hp = max_hp
	_think = randf() * 2.0
	_skel = _find_skeleton(self)
	if _skel == null:
		push_error("RtsTank: no Skeleton3D found under " + str(get_path()))
		return
	_model = get_child(0) as Node3D
	_model_base = _model.transform
	_turret = _skel.find_bone(turret_bone)
	_barrel = _skel.find_bone(barrel_bone)
	_muzzle = _skel.find_bone(muzzle_bone)
	for i in _skel.get_bone_count():
		var n := _skel.get_bone_name(i)
		if n.begins_with(wheel_bone_prefix) and not n.contains("_end"):
			_wheels.append(i)
	# directions measured from the rest pose (works whatever way the model was exported)
	var sk_basis := _skel.global_basis.orthonormalized()
	var up_sk := (sk_basis.inverse() * Vector3.UP).normalized()
	var barrel_dir_sk := (_skel.get_bone_global_rest(_muzzle).origin - _skel.get_bone_global_rest(_barrel).origin).normalized()
	var fwd_world := sk_basis * barrel_dir_sk
	fwd_world.y = 0
	_hull_fwd_local = (global_basis.orthonormalized().inverse() * fwd_world).normalized()
	var right_sk := barrel_dir_sk.cross(up_sk).normalized()
	var tb := _skel.get_bone_global_rest(_turret).basis.orthonormalized()
	_turret_axis = (tb.inverse() * up_sk).normalized()
	_barrel_back = (tb.inverse() * -barrel_dir_sk).normalized()
	for w in _wheels:
		var wb := _skel.get_bone_global_rest(w).basis.orthonormalized()
		_wheel_axes.append((wb.inverse() * right_sk).normalized())
	_dust = _make_dust_static()
	add_child(_dust)
	_dust.position = -_hull_fwd_local * 3.2 + Vector3.UP * 0.3

## Explosions: a direct hit from an RPG / tank shell / artillery damages the tank.
func take_blast(at: Vector3, radius: float) -> void:
	if destroyed:
		return
	var c := global_position + Vector3.UP * 1.2
	var d := at.distance_to(c)
	if radius < 2.5 or d > radius * 0.6:
		return
	# armour: thick glacis and turret front, thin sides, thinner rear and roof
	var to := at - global_position
	to.y = 0
	var f := hull_forward().dot(to.normalized()) if to.length() > 0.3 else 0.0
	var armour := 0.45 if f > 0.55 else (1.6 if f < -0.55 else 1.05)
	if to.length() <= 0.3 or at.y > c.y + 1.2:
		armour = 1.3                            # mine under the belly / top attack
	var dmg := 55.0 * (radius / 5.0) * clampf(1.0 - d / (radius * 0.6), 0.25, 1.0) * armour
	if radius < 3.5:
		dmg *= 0.35                             # grenade: tracks, optics
	hp -= dmg
	_rock += 0.04
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	destroyed = true
	_move_target = null; _aim_target = null; _pending_fire = null
	_speed = 0.0
	remove_from_group("units"); remove_from_group("tanks")
	add_to_group("wrecks")
	RtsExplosion.spawn(get_parent(), global_position + Vector3.UP * 1.5, 2.2)
	if _dust: _dust.emitting = false
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.03, 0.03, 0.03, 0.75)
	burnt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burnt.roughness = 1.0
	for m in find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = burnt
	_turret_yaw += randf_range(-0.6, 0.6)
	var c := Marker3D.new()
	add_child(c)
	c.add_to_group("cover")
	# burning wreck: fire + black smoke for a while
	for i in 6:
		get_tree().create_timer(2.0 + i * 3.5).timeout.connect(func():
			if is_inside_tree():
				RtsExplosion.spawn(get_parent(), global_position + Vector3(randf_range(-1, 1), 1.8, randf_range(-1, 1)), 0.35))


func _auto_engage(delta: float) -> void:
	_order_t = maxf(0.0, _order_t - delta)
	_think -= delta
	if _think > 0.0 or not auto_engage or _order_t > 0.0 or _reload > 0.5:
		return
	_think = 1.5
	var best: Node3D = null
	var bd := engage_range
	for t in get_tree().get_nodes_in_group("tanks"):
		if t != self and t.get("team") != team:
			var d := (t as Node3D).global_position.distance_to(global_position)
			if d < bd: bd = d; best = t
	if best == null:
		bd = engage_range * 0.8
		for s in get_tree().get_nodes_in_group("enemies" if team == 0 else "soldiers"):
			if s.has_method("can_fight") and s.can_fight():
				var d := (s as Node3D).global_position.distance_to(global_position)
				if d < bd: bd = d; best = s
	if best == null:
		# nothing alive to shoot: shell enemy buildings in range
		bd = engage_range * 0.85
		for b in get_tree().get_nodes_in_group("structures_%d" % (1 - team)):
			var d := (b as Node3D).global_position.distance_to(global_position)
			if d < bd: bd = d; best = b
		if best:
			fire_at(best.global_position + Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5)))
			return
	if best:
		fire_at(best.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))


var _path := PackedVector3Array()

func move_to(p: Vector3) -> void:
	_path = RtsNav.find_path(global_position, p, true)
	var first: Vector3 = _path[0]
	_path.remove_at(0)
	_move_target = Vector3(first.x, global_position.y, first.z)

func stop() -> void:
	_move_target = null
	_path.clear()

func aim_at(p: Vector3) -> void:
	_aim_target = p

func order_fire(p: Vector3) -> void:
	_order_t = 6.0
	fire_at(p)


func fire_at(p: Vector3) -> void:
	_aim_target = p
	_pending_fire = p

func hull_forward() -> Vector3:
	return (global_basis * _hull_fwd_local).normalized()

func muzzle_position() -> Vector3:
	return _skel.global_transform * _skel.get_bone_global_pose(_muzzle).origin

func _physics_process(delta: float) -> void:
	if _skel == null or destroyed:
		return
	_auto_engage(delta)
	_reload = max(0.0, _reload - delta)
	_drive(delta)
	_turret_update(delta)
	if _pending_fire != null and _reload <= 0.0 and _aligned(_pending_fire, 2.5):
		_fire(_pending_fire)
		_pending_fire = null
	_recoil = move_toward(_recoil, 0.0, delta * 1.6)
	_rock = lerp(_rock, 0.0, 1.0 - exp(-delta * 4.0))
	_apply_pose()

func _drive(delta: float) -> void:
	var want := 0.0
	if _move_target != null:
		var to: Vector3 = _move_target - global_position
		to.y = 0
		var dist := to.length()
		if not _path.is_empty() and dist < 4.0:
			_move_target = _path[0]
			_path.remove_at(0)
		elif dist < 1.0:
			_move_target = null
		else:
			var fwd := hull_forward()
			var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
			var step := deg_to_rad(hull_turn_speed) * delta
			rotate_y(clampf(ang, -step, step))
			if abs(ang) < deg_to_rad(35):
				want = max_speed * clampf(dist / 8.0, 0.25, 1.0)
	_speed = move_toward(_speed, want, acceleration * delta)
	var np := global_position + hull_forward() * _speed * delta
	np.y = RtsGround.height(np.x, np.z)
	global_position = np
	_wheel_angle += _speed * delta / wheel_radius
	_dust.emitting = _speed > 1.5
	# body pitches a little when accelerating / braking
	_rock += (want - _speed) * 0.0008

func _turret_update(delta: float) -> void:
	if _aim_target == null:
		_turret_yaw = move_toward(_turret_yaw, 0.0, deg_to_rad(turret_turn_speed) * delta)
		return
	var to: Vector3 = _aim_target - global_position
	to.y = 0
	if to.length() < 0.5:
		return
	var desired := hull_forward().signed_angle_to(to.normalized(), Vector3.UP)
	var diff := wrapf(desired - _turret_yaw, -PI, PI)
	var step := deg_to_rad(turret_turn_speed) * delta
	_turret_yaw += clampf(diff, -step, step)

func _aligned(p: Vector3, tol_deg: float) -> bool:
	var to := p - global_position
	to.y = 0
	var desired := hull_forward().signed_angle_to(to.normalized(), Vector3.UP)
	return abs(wrapf(desired - _turret_yaw, -PI, PI)) < deg_to_rad(tol_deg)

func _fire(p: Vector3) -> void:
	_reload = reload_time
	_recoil = 1.0
	_rock -= 0.05
	var from := muzzle_position()
	var dir := (p - from).normalized()
	RtsExplosion.muzzle_flash(get_parent(), from, dir, 1.0)
	RtsProjectile.launch(get_parent(), from, p, shell_speed, explosion_size, false)
	get_tree().call_group("rts_camera", "add_shake", 0.12, from)
	fired.emit(p)

func _apply_pose() -> void:
	var tr := _skel.get_bone_rest(_turret)
	_skel.set_bone_pose_rotation(_turret, tr.basis.get_rotation_quaternion() * Quaternion(_turret_axis, _turret_yaw))
	var br := _skel.get_bone_rest(_barrel)
	var rec := ease(_recoil, 2.5) * recoil_distance
	_skel.set_bone_pose_position(_barrel, br.origin + _barrel_back * rec)
	for i in _wheels.size():
		var w := _wheels[i]
		var r := _skel.get_bone_rest(w)
		_skel.set_bone_pose_rotation(w, r.basis.get_rotation_quaternion() * Quaternion(_wheel_axes[i], _wheel_angle))
	# hull rock (pitch around the hull's right axis)
	var right := _hull_fwd_local.cross(Vector3.UP).normalized()
	_model.transform = Transform3D(Basis(right, clampf(_rock, -0.08, 0.08)), Vector3.ZERO) * _model_base

static func _make_dust_static() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.4, 0.1, 0.4)
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0.3, 0.25, 0.1)
	pm.scale_min = 1.5
	pm.scale_max = 2.6
	pm.scale_curve = RtsExplosion._curve([Vector2(0, 0.4), Vector2(1, 1.8)], 2.0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.color_ramp = RtsExplosion._grad([0.0, 0.1, 1.0],
		[Color(0.55, 0.47, 0.37, 0.0), Color(0.55, 0.47, 0.37, 0.45), Color(0.6, 0.55, 0.48, 0.0)])
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 3.0
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = RtsExplosion._quad("smoke_lit")
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 30, 120))
	p.emitting = false
	RtsExplosion._normalize(p)
	return p

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null
