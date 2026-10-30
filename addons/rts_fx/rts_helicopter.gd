## Helicopter controller (made for "Mi-24 Hind", works with any heli whose rotors are separate nodes).
## Put the helicopter .glb as a CHILD of a Node3D with this script.
##   move_to(world_pos)            - fly there at cruise altitude (nose tilts, banks in turns)
##   fire_rockets(world_pos, n)    - rocket salvo with smoke trails
## For Gazelle or other models: set rotor_node / tail_rotor_node names and model_forward.
class_name RtsHelicopter
extends Node3D

@export var rotor_node := "Top_Rotor"
@export var tail_rotor_node := "Tail_Rotor"
@export var rotor_axis := Vector3.UP          # rotor local spin axis
@export var tail_rotor_axis := Vector3.RIGHT
@export var model_forward := Vector3(0, 0, 1) # used only when auto_forward is off
## Find the nose automatically: the tail is the end of the fuselage farthest from the main rotor.
@export var auto_forward := true
@export var rotor_rps := 5.0
@export var tail_rps := 14.0

## Start on the ground with rotors stopped; spools up on the first move_to().
@export var landed := false
## If rotor_node isn't found, find flat wide meshes on top and spin them (works for Gazelle).
@export var auto_detect_rotor := true
@export var cruise_altitude := 22.0
@export var max_speed := 28.0
@export var acceleration := 7.0
@export var turn_speed := 70.0                # deg/s
@export var max_tilt := 14.0                  # deg

@export var rocket_speed := 75.0
@export var rocket_explosion := 0.8
@export var rocket_pods := [Vector3(2.6, -0.6, 1.0), Vector3(-2.6, -0.6, 1.0)]

var _model: Node3D
var _model_base := Transform3D.IDENTITY
var _rotor: Node3D
var _tail: Node3D
var _rotor_base := Basis.IDENTITY
var _tail_base := Basis.IDENTITY
var _rotor_angle := 0.0
var _tail_angle := 0.0
var _target: Variant = null
var _face: Variant = null
var _vel := Vector3.ZERO
var _t := 0.0
var _pitch := 0.0
var _roll := 0.0
var _downwash: GPUParticles3D
var _spool := 1.0

func _ready() -> void:
	_model = get_child(0) as Node3D
	_model_base = _model.transform
	_rotor = _model.find_child(rotor_node, true, false) as Node3D
	_tail = _model.find_child(tail_rotor_node, true, false) as Node3D
	if _rotor == null and auto_detect_rotor:
		_rotor = _auto_rotor()
	if _rotor: _rotor_base = _rotor.basis
	if auto_forward:
		model_forward = _detect_forward()
	if _tail: _tail_base = _tail.basis
	# the Mi-24 file has a gear/rotor animation that would fight the code, stop it
	for ap in _model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	_spool = 0.0 if landed else 1.0
	_downwash = _make_downwash()
	get_parent().add_child.call_deferred(_downwash)

func move_to(p: Vector3) -> void:
	_target = Vector3(p.x, RtsGround.height(p.x, p.z) + cruise_altitude, p.z)
	_face = null
	landed = false

func face(p: Vector3) -> void:
	_face = p

func forward() -> Vector3:
	var f := global_basis * model_forward
	f.y = 0
	return f.normalized()

func fire_rockets(p: Vector3, count := 8) -> void:
	_face = p
	for i in count:
		get_tree().create_timer(0.35 + i * 0.12).timeout.connect(_launch_one.bind(p, i))

func _launch_one(p: Vector3, i: int) -> void:
	if not is_inside_tree():
		return
	var pod: Vector3 = rocket_pods[i % rocket_pods.size()]
	var from := global_position + global_basis * _local_from_forward(pod)
	var spread := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	RtsExplosion.muzzle_flash(get_parent(), from, (p - from).normalized(), 0.4)
	RtsProjectile.launch(get_parent(), from, p + spread, rocket_speed, rocket_explosion, true)

func _local_from_forward(v: Vector3) -> Vector3:
	# pod offsets are given as (right, up, forward); convert to this node's local space
	var f := model_forward.normalized()
	var r := f.cross(Vector3.UP).normalized()
	return r * v.x + Vector3.UP * v.y + f * v.z

func _physics_process(delta: float) -> void:
	_t += delta
	_spool = move_toward(_spool, 0.0 if landed else 1.0, delta * 0.35)
	var acc := Vector3.ZERO
	if _target != null and _spool < 0.75:
		acc = -_vel  # still spinning up on the pad
	elif _target != null:
		var to: Vector3 = _target - global_position
		var dist := to.length()
		var desired := to.normalized() * max_speed * clampf(dist / 30.0, 0.0, 1.0)
		acc = (desired - _vel).limit_length(acceleration)
		if dist < 1.5 and _vel.length() < 1.0:
			_target = null
	else:
		acc = (-_vel).limit_length(acceleration)
	_vel += acc * delta
	global_position += _vel * delta
	# yaw: face target when attacking, otherwise face travel direction
	var look_dir := Vector3.ZERO
	if _face != null:
		look_dir = (_face as Vector3) - global_position
	elif Vector2(_vel.x, _vel.z).length() > 2.0:
		look_dir = _vel
	look_dir.y = 0
	if look_dir.length() > 0.1:
		var ang := forward().signed_angle_to(look_dir.normalized(), Vector3.UP)
		var step := deg_to_rad(turn_speed) * delta
		rotate_y(clampf(ang, -step, step))
	# tilt: nose down when accelerating forward, bank into lateral acceleration
	var f := forward()
	var r := f.cross(Vector3.UP)
	var fwd_acc := (acc + _vel * 0.25).dot(f)
	var side_acc := (acc + _vel * 0.25).dot(r)
	_pitch = lerp(_pitch, clampf(fwd_acc / max(acceleration, 0.1), -1, 1) * deg_to_rad(max_tilt), 1.0 - exp(-delta * 2.5))
	_roll = lerp(_roll, clampf(side_acc / max(acceleration, 0.1), -1, 1) * deg_to_rad(max_tilt), 1.0 - exp(-delta * 2.5))
	var mf := model_forward.normalized()
	var mr := mf.cross(Vector3.UP).normalized()
	var bob := Vector3(0, sin(_t * 1.3) * 0.25 * _spool, 0)
	_model.transform = Transform3D(Basis(mr, -_pitch) * Basis(mf, _roll), bob) * _model_base
	# rotors
	_rotor_angle = fmod(_rotor_angle + TAU * rotor_rps * _spool * _spool * delta, TAU)
	_tail_angle = fmod(_tail_angle + TAU * tail_rps * _spool * _spool * delta, TAU)
	if _rotor: _rotor.basis = _rotor_base * Basis(rotor_axis.normalized(), _rotor_angle)
	if _tail: _tail.basis = _tail_base * Basis(tail_rotor_axis.normalized(), _tail_angle)
	# rotor downwash dust when flying low
	if is_instance_valid(_downwash) and _downwash.is_inside_tree():
		var gh := RtsGround.height(global_position.x, global_position.z)
		var alt := global_position.y - gh
		_downwash.global_position = Vector3(global_position.x, gh + 0.3, global_position.z)
		_downwash.emitting = alt < 14.0 and _spool > 0.5
		_downwash.amount_ratio = clampf(1.0 - alt / 14.0, 0.1, 1.0) * _spool

func _make_downwash() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 3.0
	pm.emission_ring_inner_radius = 1.0
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.radial_velocity_min = 7.0
	pm.radial_velocity_max = 12.0
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.scale_min = 1.8
	pm.scale_max = 3.0
	pm.scale_curve = RtsExplosion._curve([Vector2(0, 0.4), Vector2(1, 1.6)], 2.0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.color_ramp = RtsExplosion._grad([0.0, 0.15, 1.0],
		[Color(0.58, 0.5, 0.4, 0.0), Color(0.58, 0.5, 0.4, 0.4), Color(0.6, 0.55, 0.5, 0.0)])
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 2.0
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = RtsExplosion._quad("smoke_lit")
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 30, 120))
	p.emitting = false
	RtsExplosion._normalize(p)
	return p

## Group every wide & flat mesh near the top of the model under one pivot node and return it.
func _auto_rotor() -> Node3D:
	var meshes: Array[MeshInstance3D] = []
	var top := -INF
	var all := _model.find_children("*", "MeshInstance3D", true, false)
	var boxes := {}
	for m in all:
		var mi := m as MeshInstance3D
		if mi.mesh == null: continue
		var a: AABB = global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
		boxes[mi] = a
		top = max(top, a.end.y)
	for mi in boxes:
		var a: AABB = boxes[mi]
		var horiz := max(a.size.x, a.size.z)
		if horiz > 3.0 and a.size.y < horiz * 0.12 and a.end.y > top - 1.2:
			meshes.append(mi)
	if meshes.is_empty():
		return null
	var box: AABB = boxes[meshes[0]]
	for mi in meshes: box = box.merge(boxes[mi])
	var pivot := Node3D.new()
	pivot.name = "AutoRotor"
	_model.add_child(pivot)
	pivot.global_position = global_transform * Vector3(box.get_center().x, box.position.y, box.get_center().z)
	for mi in meshes:
		var gx := mi.global_transform
		mi.get_parent().remove_child(mi)
		pivot.add_child(mi)
		mi.global_transform = gx
	rotor_axis = (pivot.global_basis.orthonormalized().inverse() * global_basis.orthonormalized() * Vector3.UP).normalized()
	return pivot


## Nose direction in this node's space. Uses the tail rotor if present; otherwise the
## fuselage end that sticks out farthest from the main rotor hub is the tail boom.
func _detect_forward() -> Vector3:
	var inv := global_transform.affine_inverse()
	var hub := Vector3.ZERO
	if _rotor:
		hub = inv * _rotor.global_position
	if _tail:
		var t := inv * _tail.global_position - hub
		t.y = 0
		if t.length() > 1.0:
			return -t.normalized()
	var lo := INF; var hi := -INF; var lox := INF; var hix := -INF
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or (_rotor and _rotor.is_ancestor_of(mi)) or (_tail and _tail.is_ancestor_of(mi)):
			continue
		var a: AABB = inv * mi.global_transform * mi.mesh.get_aabb()
		lo = minf(lo, a.position.z); hi = maxf(hi, a.end.z)
		lox = minf(lox, a.position.x); hix = maxf(hix, a.end.x)
	if lo == INF:
		return model_forward
	if (hi - lo) >= (hix - lox):
		return Vector3(0, 0, 1) if (hub.z - lo) > (hi - hub.z) else Vector3(0, 0, -1)
	return Vector3(1, 0, 0) if (hub.x - lox) > (hix - hub.x) else Vector3(-1, 0, 0)
