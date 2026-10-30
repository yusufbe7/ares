## Realistic one-shot explosion for top-down RTS.
## Usage:  RtsExplosion.spawn(get_tree().current_scene, hit_position, 1.0)
##   size 0.5 = grenade, 1.0 = RPG / tank shell, 2.0 = artillery, 3.5+ = airstrike bomb
class_name RtsExplosion
extends Node3D

enum Kind { GROUND, AIR }

@export var size := 1.0
@export var kind := Kind.GROUND
@export var leave_scorch := true
@export var camera_shake := true
## How long the scorch mark stays on the ground (seconds)
@export var scorch_lifetime := 45.0

const TEX_SMOKE := preload("res://addons/rts_fx/textures/smoke_flipbook_8x8.png")
const TEX_FIRE := preload("res://addons/rts_fx/textures/fire_flipbook_8x8.png")
const TEX_SPARK := preload("res://addons/rts_fx/textures/spark.png")
const TEX_SCORCH := preload("res://addons/rts_fx/textures/scorch_decal.png")

static var _mats := {}

static func spawn(parent: Node, pos: Vector3, p_size := 1.0, p_kind := Kind.GROUND) -> RtsExplosion:
	var e := RtsExplosion.new()
	e.size = p_size
	e.kind = p_kind
	# position BEFORE entering the tree: _ready() applies the blast damage at global_position
	e.position = (parent as Node3D).global_transform.affine_inverse() * pos if parent is Node3D and parent.is_inside_tree() else pos
	parent.add_child(e)
	e.global_position = pos
	return e

## Bullet impact: small dust puff, no damage, no scorch, no shake.
static func impact(parent: Node, pos: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var dp := _proc(Vector3.UP, 35.0, 1.0, 3.0, 0.1)
	dp.gravity = Vector3(0, -3.0, 0)
	dp.scale_min = 0.4
	dp.scale_max = 0.8
	dp.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.5)], 2.0)
	dp.anim_speed_min = 1.0
	dp.anim_speed_max = 1.0
	dp.color_ramp = _grad([0.0, 1.0], [Color(0.45, 0.38, 0.3, 0.8), Color(0.5, 0.45, 0.4, 0.0)])
	root.add_child(_particles(4, 0.9, dp, _quad("smoke_lit"), 1.0))
	root.get_tree().create_timer(1.2).timeout.connect(root.queue_free)

## Small muzzle blast (tank gun, RPG back-blast). dir = barrel direction (world).
static func muzzle_flash(parent: Node, pos: Vector3, dir: Vector3, p_size := 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var s := p_size
	# light
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.4)
	l.light_energy = 6.0 * s
	l.omni_range = 6.0 * s
	root.add_child(l)
	root.create_tween().tween_property(l, "light_energy", 0.0, 0.12)
	# fire burst forward
	var fp := _proc(dir.normalized(), 18.0, 6.0 * s, 14.0 * s, 0.25 * s)
	fp.scale_min = 0.8 * s
	fp.scale_max = 1.6 * s
	fp.damping_min = 20.0
	fp.damping_max = 30.0
	fp.anim_speed_min = 1.0
	fp.anim_speed_max = 1.0
	fp.color = Color(2.6, 2.1, 1.6)
	fp.color_ramp = _grad([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	root.add_child(_particles(8, 0.22, fp, _quad("fire"), 1.0))
	# grey muzzle smoke that drifts
	var sp := _proc(dir.normalized(), 40.0, 1.0 * s, 4.0 * s, 0.3 * s)
	sp.scale_min = 1.2 * s
	sp.scale_max = 2.2 * s
	sp.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.6)], 2.0)
	sp.damping_min = 2.0
	sp.damping_max = 3.0
	sp.gravity = Vector3(0.4, 0.5, 0.2)
	sp.anim_speed_min = 1.0
	sp.anim_speed_max = 1.0
	sp.color = Color(0.75, 0.74, 0.72)
	sp.color_ramp = _grad([0.0, 0.1, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	root.add_child(_particles(6, 2.5, sp, _quad("smoke"), 0.9))
	root.get_tree().create_timer(3.0).timeout.connect(root.queue_free)


func _ready() -> void:
	var s := size
	var ground := kind == Kind.GROUND
	var longest := 0.0

	# 1) FLASH: light + bright sprite
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.35)
	light.light_energy = 12.0 * s
	light.omni_range = 9.0 * s + 4.0
	light.position.y = 1.0 * s
	add_child(light)
	var lt := create_tween()
	lt.tween_property(light, "light_energy", 3.0 * s, 0.08)
	lt.tween_property(light, "light_energy", 0.0, 0.5)

	var flash := _proc(Vector3.UP, 0.0, 0.0, 0.0, 0.0)
	flash.scale_min = 7.0 * s
	flash.scale_max = 7.0 * s
	flash.gravity = Vector3.ZERO
	flash.color = Color(5.0, 3.6, 2.2)
	flash.color_ramp = _grad([0.0, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var fl := _particles(1, 0.12, flash, _quad("spark"), 1.0)
	fl.position.y = 0.8 * s
	add_child(fl)

	# 2) FIREBALL
	var fb := _proc(Vector3.UP, 75.0, 1.5 * s, 4.5 * s, 0.6 * s)
	fb.scale_min = 2.4 * s
	fb.scale_max = 3.8 * s
	fb.scale_curve = _curve([Vector2(0, 0.45), Vector2(0.25, 1.0), Vector2(1, 1.2)], 1.5)
	fb.gravity = Vector3(0, 2.0, 0)
	fb.damping_min = 3.0
	fb.damping_max = 5.0
	fb.anim_speed_min = 1.0
	fb.anim_speed_max = 1.0
	fb.color = Color(2.4, 2.1, 1.8)
	fb.color_ramp = _grad([0.0, 0.7, 1.0], [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var fire := _particles(int(10 + 6 * s), 0.85 + 0.15 * s, fb, _quad("fire"), 0.95)
	fire.position.y = 0.6 * s
	add_child(fire)

	# 3) SPARKS / EMBERS
	var sk := _proc(Vector3.UP, 80.0, 7.0 * sqrt(s), 20.0 * sqrt(s), 0.4 * s)
	sk.scale_min = 0.12 * s
	sk.scale_max = 0.3 * s
	sk.gravity = Vector3(0, -9.8, 0)
	sk.color = Color(4.0, 2.2, 0.8)
	sk.color_ramp = _grad([0.0, 0.7, 1.0], [Color(1, 1, 1, 1), Color(1, 0.6, 0.3, 1), Color(1, 0.4, 0.2, 0)])
	var sparks := _particles(int(20 + 15 * s), 1.1, sk, _quad("spark"), 1.0)
	sparks.position.y = 0.5 * s
	add_child(sparks)

	# 4) BLACK SMOKE COLUMN (lit by the sun)
	var smoke_life := 6.0 + 2.5 * s
	var sm := _proc(Vector3.UP, 30.0, 1.5 * s, 4.0 * s, 0.9 * s)
	sm.scale_min = 2.6 * s
	sm.scale_max = 4.2 * s
	sm.scale_curve = _curve([Vector2(0, 0.35), Vector2(0.15, 0.8), Vector2(1, 1.9)], 2.0)
	sm.gravity = Vector3(0.9, 0.6, 0.35)   # buoyancy + light wind
	sm.damping_min = 0.6
	sm.damping_max = 1.0
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.angular_velocity_min = -12.0
	sm.angular_velocity_max = 12.0
	sm.anim_speed_min = 1.0
	sm.anim_speed_max = 1.0
	sm.color = Color(1, 1, 1)
	sm.color_ramp = _grad([0.0, 0.06, 0.35, 1.0],
		[Color(0.10, 0.09, 0.08, 0.0), Color(0.13, 0.12, 0.11, 0.95), Color(0.30, 0.29, 0.28, 0.8), Color(0.55, 0.54, 0.52, 0.0)])
	var smoke := _particles(int(12 + 6 * s), smoke_life, sm, _quad("smoke_lit"), 0.8)
	sm.lifetime_randomness = 0.35
	smoke.position.y = 0.8 * s
	add_child(smoke)
	longest = max(longest, smoke_life)

	if ground:
		# 5) DUST RING rolling along the ground
		var dr := _proc(Vector3.UP, 10.0, 0.3, 0.8, 0.5 * s)
		dr.radial_velocity_min = 3.5 * s
		dr.radial_velocity_max = 8.0 * s
		dr.damping_min = 4.0
		dr.damping_max = 6.0
		dr.gravity = Vector3(0.3, 0.15, 0.1)
		dr.scale_min = 2.8 * s
		dr.scale_max = 4.2 * s
		dr.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.7)], 2.0)
		dr.angle_min = -180.0
		dr.angle_max = 180.0
		dr.anim_speed_min = 1.0
		dr.anim_speed_max = 1.0
		dr.color_ramp = _grad([0.0, 0.08, 1.0],
			[Color(0.50, 0.42, 0.32, 0.0), Color(0.50, 0.42, 0.32, 0.85), Color(0.62, 0.56, 0.48, 0.0)])
		var dust := _particles(int(26 + 12 * s), 3.5 + s, dr, _quad("smoke_lit"), 0.95)
		dust.position.y = 0.3 * s
		add_child(dust)
		longest = max(longest, 3.5 + s)

		# 6) DIRT SPRAY (earth thrown up)
		var ds := _proc(Vector3.UP, 22.0, 6.0 * sqrt(s), 13.0 * sqrt(s), 0.4 * s)
		ds.gravity = Vector3(0, -14.0, 0)
		ds.scale_min = 0.35 * s
		ds.scale_max = 0.8 * s
		ds.angle_min = -180.0
		ds.angle_max = 180.0
		ds.anim_speed_min = 0.6
		ds.anim_speed_max = 0.9
		ds.color_ramp = _grad([0.0, 0.8, 1.0],
			[Color(0.22, 0.17, 0.12, 1.0), Color(0.28, 0.22, 0.16, 0.7), Color(0.3, 0.25, 0.2, 0.0)])
		var dirt := _particles(int(14 + 8 * s), 1.6 * sqrt(s), ds, _quad("smoke_lit"), 0.95)
		add_child(dirt)

		# 7) DEBRIS CHUNKS (3D)
		var db := _proc(Vector3.UP, 38.0, 4.0 * sqrt(s), 9.0 * sqrt(s), 0.4 * s)
		db.gravity = Vector3(0, -18.0, 0)
		db.scale_min = 0.35 * sqrt(s)
		db.scale_max = 0.9 * sqrt(s)
		db.scale_curve = _curve([Vector2(0, 1), Vector2(0.85, 1), Vector2(1, 0)], 1.0)
		db.angular_velocity_min = -400.0
		db.angular_velocity_max = 400.0
		db.particle_flag_rotate_y = true
		db.color = Color(0.25, 0.21, 0.17)
		var chunks := _particles(int(8 + 5 * s), 1.1 * sqrt(s), db, _debris_mesh(), 1.0)
		chunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(chunks)

		# 8) SCORCH MARK on the ground (outlives the explosion)
		if leave_scorch and get_parent():
			var d := Decal.new()
			d.texture_albedo = TEX_SCORCH
			d.size = Vector3(3.2 * s, 3.0, 3.2 * s)
			d.albedo_mix = 0.9
			d.cull_mask = RtsGround.DECAL_LAYER
			d.rotation.y = randf() * TAU
			get_parent().add_child(d)
			d.global_position = global_position
			var dt := d.create_tween()
			dt.tween_interval(scorch_lifetime)
			dt.tween_property(d, "albedo_mix", 0.0, 5.0)
			dt.tween_callback(d.queue_free)

	# damage: soldiers / units react to the blast
	get_tree().call_group("units", "take_blast", global_position, 4.0 * s + 1.0)
	get_tree().call_group("wounded", "take_blast", global_position, 4.0 * s + 1.0)
	get_tree().call_group("structures", "take_blast", global_position, 4.0 * s + 1.0)
	get_tree().call_group("destructibles", "take_blast", global_position, 4.0 * s + 1.0)
	for u in get_tree().get_nodes_in_group("units"):
		if u.has_method("suppress") and (u as Node3D).global_position.distance_to(global_position) < 14.0 * s:
			u.suppress(0.9)

	if camera_shake and is_inside_tree():
		get_tree().call_group("rts_camera", "add_shake", 0.35 * s, global_position)

	get_tree().create_timer(longest + 1.0).timeout.connect(queue_free)


# ---------------------------------------------------------------- helpers

static func _particles(amount: int, life: float, proc: ParticleProcessMaterial, mesh: Mesh, explosiveness: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = max(1, amount)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = explosiveness
	p.process_material = proc
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	p.emitting = true
	_normalize(p)
	return p

## Bake the average particle scale into the quad size. Billboard particles keep the
## quad size reliably in every renderer, so the effect looks the same everywhere.
static func _normalize(p: GPUParticles3D) -> void:
	var q := p.draw_pass_1 as QuadMesh
	var m := p.process_material as ParticleProcessMaterial
	if q == null or m == null:
		return
	var mean := (m.scale_min + m.scale_max) * 0.5
	if mean <= 0.0001:
		return
	q.size = Vector2(mean, mean)
	m.scale_min /= mean
	m.scale_max /= mean

static func _proc(dir: Vector3, spread: float, vmin: float, vmax: float, radius: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = vmin
	m.initial_velocity_max = vmax
	if radius > 0.0:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = radius
	m.angle_min = -180.0
	m.angle_max = 180.0
	return m

static func _curve(points: Array, max_v: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_v
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t

static func _grad(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

static func _quad(kind_name: String) -> QuadMesh:
	var q := QuadMesh.new()
	q.material = _material(kind_name)
	return q

static func _material(kind_name: String) -> StandardMaterial3D:
	if _mats.has(kind_name):
		return _mats[kind_name]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# soft particles need the depth texture (Forward+ / Mobile); the Compatibility renderer can't do it
	var soft: bool = RenderingServer.get_rendering_device() != null
	match kind_name:
		"fire":
			m.albedo_texture = TEX_FIRE
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.particles_anim_h_frames = 8
			m.particles_anim_v_frames = 8
			m.particles_anim_loop = false
			m.proximity_fade_enabled = soft
			m.proximity_fade_distance = 0.8
		"smoke", "smoke_lit":
			m.albedo_texture = TEX_SMOKE
			m.particles_anim_h_frames = 8
			m.particles_anim_v_frames = 8
			m.particles_anim_loop = false
			m.proximity_fade_enabled = soft
			m.proximity_fade_distance = 1.2
			m.roughness = 1.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			if kind_name == "smoke":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			else:
				# lit by sun, soft: backlight makes it look volumetric
				m.backlight_enabled = true
				m.backlight = Color(0.35, 0.33, 0.3)
		"spark":
			m.albedo_texture = TEX_SPARK
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats[kind_name] = m
	return m

static func _debris_mesh() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.18, 0.1, 0.14)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.13, 0.1)
	m.roughness = 0.95
	b.material = m
	return b
