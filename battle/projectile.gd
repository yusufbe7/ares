class_name Projectile
extends Node3D
## Shells and rockets. They travel, so a tank round can miss a moving target and
## an RPG can be fired at a wall to blow a hole in it.

var battle = null
var velocity: Vector3 = Vector3.ZERO
var damage: float = 100.0
var at_value: float = 1.0
var team: int = 0
var blast_radius: float = 3.0
var guided_target: BattleUnit = null
var life: float = 8.0
var _gravity: float = 0.0
var trail_scale: float = 1.0
var _last_puff_at: Vector3 = Vector3.ZERO
var _has_puffed: bool = false

func _build_body(color: Color, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)

func launch(ctx, from: Vector3, to: Vector3, p_team: int, p_damage: float,
		p_at: float, speed: float, radius: float) -> void:
	battle = ctx
	team = p_team
	damage = p_damage
	at_value = p_at
	blast_radius = radius
	global_position = from
	velocity = (to - from).normalized() * speed
	_gravity = 2.0
	_build_body(Color(1.0, 0.9, 0.5), Vector3(0.14, 0.14, 0.8))

func launch_guided(ctx, from: Vector3, target: BattleUnit, p_team: int,
		p_damage: float, p_at: float, speed: float) -> void:
	battle = ctx
	team = p_team
	damage = p_damage
	at_value = p_at
	blast_radius = 3.5
	guided_target = target
	global_position = from
	velocity = (target.global_position - from).normalized() * speed
	_build_body(Color(1.0, 0.6, 0.25), Vector3(0.12, 0.12, 0.9))

func _physics_process(delta: float) -> void:
	if battle == null or not is_instance_valid(battle):
		queue_free()
		return
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if guided_target != null and is_instance_valid(guided_target) and guided_target.is_alive():
		# A rocket corrects, but slowly enough that a moving tank can break lock.
		var want := (guided_target.global_position + Vector3(0, 1.0, 0) - global_position).normalized()
		velocity = velocity.lerp(want * velocity.length(), clampf(delta * 2.2, 0.0, 1.0))
	_drop_trail()
	velocity.y -= _gravity * delta
	var step := velocity * delta
	var next := global_position + step
	look_at_direction(velocity)
	# Ground.
	if next.y <= battle.terrain.height_at(next.x, next.z):
		_detonate(Vector3(next.x, battle.terrain.height_at(next.x, next.z), next.z))
		return
	# Buildings: the first wall it meets is where it goes off.
	for h in battle.buildings:
		if not is_instance_valid(h) or h.is_passable():
			continue
		var local: Vector3 = h.to_local(next)
		if absf(local.x) < h.dims.x * 0.5 + 0.4 and absf(local.z) < h.dims.z * 0.5 + 0.4 and local.y < h.dims.y:
			_detonate(next)
			return
	# Units.
	for u in battle.units:
		if not is_instance_valid(u) or not u.is_alive() or u.team == team:
			continue
		if u.global_position.distance_to(next) < 2.2:
			_detonate(next)
			return
	global_position = next

## A bead every few metres, which is what draws the arc.
func _drop_trail() -> void:
	if not _has_puffed:
		_last_puff_at = global_position
		_has_puffed = true
		return
	if global_position.distance_to(_last_puff_at) < 4.0:
		return
	_last_puff_at = global_position
	battle.leave_trail_puff(global_position, trail_scale)

func look_at_direction(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	rotation.y = atan2(dir.x, dir.z)
	rotation.x = -asin(clampf(dir.normalized().y, -1.0, 1.0))

func _detonate(at: Vector3) -> void:
	if battle != null and is_instance_valid(battle):
		battle.spawn_explosion(at, blast_radius, damage, team, blast_radius > 4.0)
		for h in battle.buildings:
			if is_instance_valid(h) and h.global_position.distance_to(at) < h.dims.length():
				h.damage(at, blast_radius * 1.5, 14.0)
	queue_free()
