## Tank shell (fast tracer) or rocket (smoke trail). Explodes on arrival.
## RtsProjectile.launch(parent, from, to, speed, explosion_size, is_rocket)
class_name RtsProjectile
extends Node3D

var target := Vector3.ZERO
var speed := 120.0
var explosion_size := 1.0
var is_rocket := false
var arc_height := 0.0

var _start := Vector3.ZERO
var _t := 0.0
var _dur := 1.0
var _done := false
var _wobble_seed := 0.0
var _visual: Node3D
var _trail: GPUParticles3D

static func launch(parent: Node, from: Vector3, to: Vector3, p_speed := 120.0, p_size := 1.0, rocket := false) -> RtsProjectile:
	var p := RtsProjectile.new()
	p.target = to
	p.speed = p_speed
	p.explosion_size = p_size
	p.is_rocket = rocket
	parent.add_child(p)
	p.global_position = from
	p._start = from
	p._dur = max(0.05, from.distance_to(to) / p_speed)
	p.arc_height = 0.0 if not rocket else from.distance_to(to) * 0.03
	return p

func _ready() -> void:
	_wobble_seed = randf() * 100.0
	_visual = Node3D.new()
	add_child(_visual)
	# glowing tracer / rocket motor
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.08 if not is_rocket else 0.12
	cap.height = 1.6 if not is_rocket else 0.6
	if explosion_size <= 0.0:
		cap.radius = 0.03
		cap.height = 1.2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(3.5, 2.0, 0.8)
	cap.material = m
	mi.mesh = cap
	mi.rotation_degrees.x = 90.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(mi)
	if is_rocket:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.6, 0.3)
		l.light_energy = 2.0
		l.omni_range = 4.0
		_visual.add_child(l)
		_trail = _make_trail()
		add_child(_trail)

func _make_trail() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.5, 0.4, 0.2)
	pm.damping_min = 1.0
	pm.damping_max = 1.0
	pm.scale_min = 0.7
	pm.scale_max = 1.0
	pm.scale_curve = RtsExplosion._curve([Vector2(0, 0.6), Vector2(1, 2.6)], 3.0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.color_ramp = RtsExplosion._grad([0.0, 0.05, 1.0],
		[Color(0.9, 0.88, 0.85, 0.0), Color(0.92, 0.9, 0.88, 0.85), Color(0.95, 0.95, 0.95, 0.0)])
	var p := GPUParticles3D.new()
	p.amount = 320
	p.lifetime = 2.2
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = RtsExplosion._quad("smoke_lit")
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 100, 400))
	p.emitting = true
	RtsExplosion._normalize(p)
	return p

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t = min(1.0, _t + delta / _dur)
	var pos := _start.lerp(target, _t)
	pos.y += arc_height * 4.0 * _t * (1.0 - _t)
	if is_rocket:
		var w := (1.0 - _t) * 0.35
		pos += Vector3(sin(_wobble_seed + _t * 25.0), 0, cos(_wobble_seed * 1.3 + _t * 21.0)) * w
	if explosion_size > 0.0 and _t > 0.0:
		var q := PhysicsRayQueryParameters3D.create(global_position, pos, 4)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit and (hit.position as Vector3).distance_to(_start) > 2.0:
			target = hit.position - (pos - global_position).normalized() * 0.3
			global_position = target
			_explode()
			return
	if pos.distance_squared_to(global_position) > 0.0001:
		look_at(pos, Vector3.UP if abs((pos - global_position).normalized().y) < 0.99 else Vector3.FORWARD)
	global_position = pos
	if _t >= 1.0:
		_explode()

func _explode() -> void:
	_done = true
	_visual.visible = false
	if explosion_size <= 0.0:
		RtsExplosion.impact(get_parent(), target)
	else:
		RtsExplosion.spawn(get_parent(), target, explosion_size)
	if _trail:
		_trail.emitting = false
		get_tree().create_timer(_trail.lifetime + 0.2).timeout.connect(queue_free)
	else:
		queue_free()
