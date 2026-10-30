class_name ObjectiveTarget
extends Node3D
## The thing a "Destroy Target" match is fought over: a command post with its
## own health bar. It deliberately presents the same small surface as a
## building — dims, damage(), is_passable() — so shells, line of sight and
## attack orders already know what to do with it.

var team: int = 0
var max_hp: float = 4000.0
var hp: float = 4000.0
var dims: Vector3 = Vector3(14, 7, 14)
var destroyed: bool = false
var battle = null

var _mesh: MeshInstance3D
var _bar: MeshInstance3D
var _smoke: GPUParticles3D = null

func setup(ctx, p_team: int, pos: Vector3, color: Color) -> void:
	battle = ctx
	team = p_team
	position = pos
	_build(color)

func _build(color: Color) -> void:
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = dims
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.45)
	mat.roughness = 0.9
	_mesh.material_override = mat
	_mesh.position = Vector3(0, dims.y * 0.5, 0)
	add_child(_mesh)

	# A mast, so the post is findable from across the map.
	var mast := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.26
	cm.height = 14.0
	mast.mesh = cm
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = color
	mmat.emission_enabled = true
	mmat.emission = color
	mmat.emission_energy_multiplier = 0.8
	mast.material_override = mmat
	mast.position = Vector3(0, dims.y + 7.0, 0)
	add_child(mast)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dims
	cs.shape = shape
	cs.position = Vector3(0, dims.y * 0.5, 0)
	body.add_child(cs)
	body.collision_layer = 1 | 4
	add_child(body)

	_bar = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(dims.x, 0.9)
	_bar.mesh = qm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.3, 0.95, 0.45)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.material_override = bmat
	_bar.position = Vector3(0, dims.y + 2.2, 0)
	add_child(_bar)

	if battle != null:
		# The post itself is the best cover on the map for whoever defends it.
		for i in range(8):
			var ang := TAU * float(i) / 8.0
			var dir := Vector3(cos(ang), 0, sin(ang))
			battle.cover.add_slot(global_position + dir * (dims.x * 0.5 + 1.2), dir, 0.85, "command_post")

func is_passable() -> bool:
	return destroyed

func health_fraction() -> float:
	return clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)

## Same signature as DestructibleBuilding.damage so every weapon already hits it.
func damage(world_pos: Vector3, radius: float, power: float) -> void:
	if destroyed:
		return
	var d: float = global_position.distance_to(world_pos)
	if d > radius + dims.length() * 0.5:
		return
	take_damage(power * 18.0)

func take_damage(amount: float) -> void:
	if destroyed:
		return
	hp -= amount
	_refresh_bar()
	if hp <= max_hp * 0.5 and _smoke == null:
		_start_smoke()
	if hp <= 0.0:
		_destroy()

func _refresh_bar() -> void:
	if _bar == null:
		return
	var f := health_fraction()
	_bar.scale.x = maxf(f, 0.02)
	var mat: StandardMaterial3D = _bar.material_override
	mat.albedo_color = Color(0.9, 0.3, 0.25).lerp(Color(0.3, 0.95, 0.45), f)

func _start_smoke() -> void:
	_smoke = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, 1.0, 0)
	mat.scale_min = 3.0
	mat.scale_max = 7.0
	_smoke.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(5, 5)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.1, 0.1, 0.1, 0.5)
	qm.material = smat
	_smoke.draw_pass_1 = qm
	_smoke.amount = 50
	_smoke.lifetime = 6.0
	_smoke.position = Vector3(0, dims.y, 0)
	add_child(_smoke)

func _destroy() -> void:
	destroyed = true
	hp = 0.0
	_refresh_bar()
	if battle != null and is_instance_valid(battle):
		battle.spawn_explosion(global_position + Vector3(0, 3, 0), 14.0, 160.0, 1 - team, true)
		battle.cover.invalidate_near(global_position, dims.x)
		battle.on_objective_destroyed(self)
	if _mesh != null:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.albedo_color = Color(0.09, 0.08, 0.07)
	_mesh.scale.y = 0.35
