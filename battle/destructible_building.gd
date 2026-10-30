class_name DestructibleBuilding
extends Node3D
## A house that comes apart. It is built as a voxel shell of chunks (walls,
## roof, chimney). While it stands, every surviving chunk is drawn as one merged
## mesh, so an intact village costs almost nothing. Damage turns only the chunks
## near the hit into real debris, and anything that loses its path down to the
## foundation falls under its own weight.

const CHUNK := 0.8
const MAX_PHYSICS_DEBRIS := 14          # real rigid bodies per hit
const MAX_LIVE_DEBRIS := 60             # across the whole building

class Chunk extends RefCounted:
	var local: Vector3                  # centre, in building space
	var size: Vector3
	var color: Color
	var alive: bool = true
	var is_roof: bool = false
	var supported: bool = true

var chunks: Array = []
var dims: Vector3 = Vector3(10, 5, 8)
var intact_fraction: float = 1.0
var burning: bool = false
var cover: CoverSystem = null
var terrain: BattleTerrain = null

## Men inside the building: they shoot from the windows and the roof, and the
## walls do the work that cover slots do outside.
var garrison: Array = []
var garrison_team: int = -1
const GARRISON_PROTECTION := 0.86

var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _debris_live: int = 0
var _wall_color: Color = Color(0.82, 0.80, 0.74)
var _roof_color: Color = Color(0.45, 0.18, 0.16)
var _rng := RandomNumberGenerator.new()
var _smoke: GPUParticles3D = null
var _falling: Array = []                # chunks coming down without physics
var _debris_mm: MultiMesh = null        # one draw call for all of them
var _rubble: MeshInstance3D = null      # where settled fragments end up

func build(size: Vector3, seed_value: int, snow: float, wall_color: Color, roof_color: Color) -> void:
	dims = size
	_rng.seed = seed_value
	_wall_color = wall_color.lerp(Color(0.95, 0.96, 0.98), snow * 0.25)
	_roof_color = roof_color.lerp(Color(0.93, 0.95, 0.97), snow * 0.8)
	_make_chunks()
	_rebuild_visual()
	_rebuild_collision()

func _make_chunks() -> void:
	chunks.clear()
	var nx := maxi(2, int(dims.x / CHUNK))
	var ny := maxi(2, int(dims.y / CHUNK))
	var nz := maxi(2, int(dims.z / CHUNK))
	var hx := dims.x * 0.5
	var hz := dims.z * 0.5
	# Walls: the outer shell only. The inside of a house is empty space.
	for y in range(ny):
		for x in range(nx):
			for z in range(nz):
				var on_edge: bool = x == 0 or x == nx - 1 or z == 0 or z == nz - 1
				if not on_edge:
					continue
				var c := Chunk.new()
				c.local = Vector3(-hx + (float(x) + 0.5) * CHUNK, (float(y) + 0.5) * CHUNK,
					-hz + (float(z) + 0.5) * CHUNK)
				c.size = Vector3(CHUNK, CHUNK, CHUNK)
				# A window or a door is a hole in the shell from the start.
				if y >= 1 and y <= 2 and _rng.randf() < 0.16:
					continue
				c.color = _wall_color.darkened(_rng.randf_range(0.0, 0.12))
				chunks.append(c)
	# Roof: a simple gable, which is what reads as a house from above.
	var roof_rows := maxi(2, int(dims.z / CHUNK))
	for x in range(nx):
		for z in range(roof_rows):
			var t: float = absf(float(z) / float(roof_rows - 1) - 0.5) * 2.0
			var c2 := Chunk.new()
			c2.is_roof = true
			c2.local = Vector3(-hx + (float(x) + 0.5) * CHUNK,
				dims.y + (1.0 - t) * dims.y * 0.32,
				-hz + (float(z) + 0.5) * CHUNK)
			c2.size = Vector3(CHUNK, CHUNK * 0.6, CHUNK)
			c2.color = _roof_color.darkened(_rng.randf_range(0.0, 0.1))
			chunks.append(c2)
	# Chimney.
	for i in range(3):
		var c3 := Chunk.new()
		c3.is_roof = true
		c3.local = Vector3(hx - CHUNK * 1.5, dims.y + dims.y * 0.32 + float(i) * CHUNK, 0.0)
		c3.size = Vector3(CHUNK * 0.8, CHUNK, CHUNK * 0.8)
		c3.color = Color(0.5, 0.42, 0.38)
		chunks.append(c3)

func _rebuild_visual() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for c in chunks:
		if not c.alive:
			continue
		any = true
		_emit_box(st, c.local, c.size, c.color)
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		add_child(_mesh_instance)
	if not any:
		_mesh_instance.mesh = null
		return
	st.generate_normals()
	_mesh_instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	_mesh_instance.material_override = mat

func _emit_box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f in faces:
		_quad(st, corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], color)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(c)
	st.set_color(color)
	st.add_vertex(d)

## One box collider per standing wall rather than per chunk: a shell of four
## walls stops a shell at the right place and costs four shapes, not four
## hundred.
func _rebuild_collision() -> void:
	if _body != null:
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.collision_layer = 1 | 4        # world + "building" layer
	add_child(_body)
	var hx := dims.x * 0.5
	var hz := dims.z * 0.5
	var walls := [
		{"c": Vector3(0, dims.y * 0.5, -hz), "s": Vector3(dims.x, dims.y, CHUNK)},
		{"c": Vector3(0, dims.y * 0.5, hz), "s": Vector3(dims.x, dims.y, CHUNK)},
		{"c": Vector3(-hx, dims.y * 0.5, 0), "s": Vector3(CHUNK, dims.y, dims.z)},
		{"c": Vector3(hx, dims.y * 0.5, 0), "s": Vector3(CHUNK, dims.y, dims.z)},
	]
	for w in walls:
		if _wall_alive_fraction(w["c"]) < 0.3:
			continue
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w["s"]
		cs.shape = box
		cs.position = w["c"]
		_body.add_child(cs)

func _wall_alive_fraction(wall_center: Vector3) -> float:
	var total := 0
	var alive := 0
	for c in chunks:
		if c.is_roof:
			continue
		if c.local.distance_to(Vector3(wall_center.x, c.local.y, wall_center.z)) > dims.length() * 0.25:
			continue
		total += 1
		if c.alive:
			alive += 1
	if total == 0:
		return 0.0
	return float(alive) / float(total)

# ---------------------------------------------------------------------------
# Damage
# ---------------------------------------------------------------------------

## Blows a hole. world_pos is the impact point, power scales how far the
## fragments are thrown.
func damage(world_pos: Vector3, radius: float, power: float) -> void:
	var local_hit: Vector3 = to_local(world_pos)
	var hit_any := false
	var physics_budget := MAX_PHYSICS_DEBRIS
	var affected: Array = []
	for c in chunks:
		if not c.alive:
			continue
		if c.local.distance_to(local_hit) <= radius:
			affected.append(c)
	# Biggest fragments get the real physics; the rest just fall.
	affected.sort_custom(func(a, b): return a.size.length() > b.size.length())
	for c in affected:
		c.alive = false
		hit_any = true
		if physics_budget > 0 and _debris_live < MAX_LIVE_DEBRIS:
			physics_budget -= 1
			_spawn_physics_debris(c, local_hit, power)
		else:
			_add_falling(c)
	if not hit_any:
		return
	_collapse_unsupported()
	_rebuild_visual()
	_rebuild_collision()
	_update_state(world_pos, radius)

func _spawn_physics_debris(c: Chunk, from_local: Vector3, power: float) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 6.0
	rb.collision_layer = 8
	rb.collision_mask = 1          # debris hits the ground and walls, not each other
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = c.size
	shape.shape = box
	rb.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = c.size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c.color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	get_parent().add_child(rb)
	rb.global_position = to_global(c.local)
	var push: Vector3 = (c.local - from_local).normalized()
	if push.length() < 0.01:
		push = Vector3.UP
	rb.linear_velocity = push * power * _rng.randf_range(0.6, 1.3) + Vector3.UP * power * 0.4
	rb.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
	_debris_live += 1
	get_tree().create_timer(6.0).timeout.connect(_retire_debris.bind(rb))

## Debris is cleared on a timer. The live count has to come down whether or not
## the body is still around by then, so this is a named method rather than a
## lambda holding the node.
func _retire_debris(body: Node) -> void:
	_debris_live = maxi(0, _debris_live - 1)
	if is_instance_valid(body):
		body.queue_free()

## Support, the way a house actually loses it: a wall chunk stands as long as
## something in its own column is still under it, and the roof stays up only
## while enough wall is left to carry it. Anything that fails that test comes
## down in the same collapse as the hit that caused it.
func _collapse_unsupported() -> void:
	var columns: Dictionary = {}        # Vector2i(x,z) -> lowest alive wall level
	for c in chunks:
		if c.alive and not c.is_roof:
			var key := Vector2i(int(floor(c.local.x / CHUNK)), int(floor(c.local.z / CHUNK)))
			var level := int(floor(c.local.y / CHUNK))
			if not columns.has(key) or level < int(columns[key]):
				columns[key] = level
	var wall_fraction := _overall_wall_fraction()
	for c in chunks:
		if not c.alive:
			continue
		if c.is_roof:
			# The roof rides on the walls as a whole, not on one column.
			if wall_fraction < 0.35:
				c.alive = false
				_add_falling(c)
			continue
		var key2 := Vector2i(int(floor(c.local.x / CHUNK)), int(floor(c.local.z / CHUNK)))
		var my_level := int(floor(c.local.y / CHUNK))
		if my_level <= 0:
			continue                     # resting on the foundation
		if not columns.has(key2) or int(columns[key2]) >= my_level:
			# Nothing left underneath this piece of wall.
			c.alive = false
			_add_falling(c)

func _overall_wall_fraction() -> float:
	var total := 0
	var alive := 0
	for c in chunks:
		if c.is_roof:
			continue
		total += 1
		if c.alive:
			alive += 1
	if total == 0:
		return 0.0
	return float(alive) / float(total)

func _update_state(world_pos: Vector3, radius: float) -> void:
	var alive := 0
	for c in chunks:
		if c.alive:
			alive += 1
	intact_fraction = float(alive) / maxf(float(chunks.size()), 1.0)
	if cover != null:
		cover.invalidate_near(world_pos, radius + 1.5)
		if intact_fraction < 0.5:
			cover.add_wreck(global_position)
	if intact_fraction < 0.5 and not burning:
		_start_burning()
	if is_passable() and not garrison.is_empty():
		eject_garrison(25.0)

func _start_burning() -> void:
	burning = true
	_smoke = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 22.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, 1.2, 0)
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	mat.color = Color(0.1, 0.1, 0.1, 0.65)
	_smoke.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(3, 3)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.albedo_color = Color(0.08, 0.08, 0.08, 0.5)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = smat
	_smoke.draw_pass_1 = qm
	_smoke.amount = 40
	_smoke.lifetime = 5.0
	_smoke.position = Vector3(0, dims.y * 0.7, 0)
	add_child(_smoke)

## True once the shell is open enough for infantry to walk through the rubble.
func is_passable() -> bool:
	return intact_fraction < 0.45

# ---------------------------------------------------------------------------
# Garrison
# ---------------------------------------------------------------------------

func capacity() -> int:
	# Roughly one man per four metres of frontage, and a wreck holds nobody.
	if is_passable():
		return 0
	return clampi(int((dims.x + dims.z) / 4.0), 2, 10)

func can_garrison(team: int) -> bool:
	if capacity() <= 0:
		return false
	if garrison_team >= 0 and garrison_team != team:
		return false
	return garrison.size() < capacity()

## Window and rooftop positions, spread around the shell so a garrison covers
## every approach instead of stacking on one wall.
func firing_point(index: int) -> Vector3:
	var slots := maxi(capacity(), 1)
	var t: float = float(index % slots) / float(slots)
	var ang := t * TAU
	var hx := dims.x * 0.5 - 0.3
	var hz := dims.z * 0.5 - 0.3
	var local := Vector3(cos(ang) * hx, 1.2, sin(ang) * hz)
	# Every third man goes up top, which is what gives the position its reach.
	if index % 3 == 2:
		local.y = dims.y + 0.6
		local.x *= 0.6
		local.z *= 0.6
	return to_global(local)

func add_to_garrison(u) -> bool:
	if not can_garrison(u.team):
		return false
	garrison.append(u)
	garrison_team = u.team
	return true

func remove_from_garrison(u) -> void:
	garrison.erase(u)
	if garrison.is_empty():
		garrison_team = -1

## Everyone still inside a collapsing building is thrown out of it, hurt.
func eject_garrison(reason_damage: float) -> void:
	for u in garrison.duplicate():
		if is_instance_valid(u):
			u.leave_building(true)
			if reason_damage > 0.0:
				u.take_damage(reason_damage, null)
	garrison.clear()
	garrison_team = -1

## Fragments that did not earn a rigid body still fall, drawn through a single
## multimesh. Once one settles it is baked into the rubble mesh and stops
## costing anything at all.
const MAX_FALLING := 220

func _ensure_debris_mm() -> void:
	if _debris_mm != null:
		return
	_debris_mm = MultiMesh.new()
	_debris_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(CHUNK, CHUNK, CHUNK)
	_debris_mm.mesh = bm
	_debris_mm.instance_count = MAX_FALLING
	_debris_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _debris_mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _wall_color.darkened(0.15)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.top_level = true
	add_child(mmi)

func _add_falling(c: Chunk) -> void:
	if _falling.size() >= MAX_FALLING:
		return
	_ensure_debris_mm()
	_falling.append({
		"pos": to_global(c.local),
		"vel": Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5)),
		"spin": Vector3(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), _rng.randf_range(-3, 3)),
		"rot": Vector3.ZERO,
		"size": c.size,
	})

func _ground_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else global_position.y

func _process(delta: float) -> void:
	if _falling.is_empty():
		return
	var settled: Array = []
	var i := 0
	while i < _falling.size():
		var d: Dictionary = _falling[i]
		var vel: Vector3 = d["vel"]
		vel.y -= 9.8 * delta
		var pos: Vector3 = (d["pos"] as Vector3) + vel * delta
		var ground: float = _ground_at(pos.x, pos.z) + float((d["size"] as Vector3).y) * 0.5
		if pos.y <= ground:
			pos.y = ground
			settled.append(pos)
			_falling.remove_at(i)
			continue
		d["pos"] = pos
		d["vel"] = vel
		d["rot"] = (d["rot"] as Vector3) + (d["spin"] as Vector3) * delta
		i += 1
	_push_debris_transforms()
	if not settled.is_empty():
		_bake_rubble(settled)

func _push_debris_transforms() -> void:
	if _debris_mm == null:
		return
	_debris_mm.visible_instance_count = _falling.size()
	for i in range(_falling.size()):
		var d: Dictionary = _falling[i]
		var rot: Vector3 = d["rot"]
		var basis: Basis = Basis.from_euler(rot).scaled((d["size"] as Vector3) / CHUNK)
		_debris_mm.set_instance_transform(i, Transform3D(basis, d["pos"]))

## Settled fragments become one static mesh, so a flattened village does not
## carry hundreds of nodes for the rest of the match.
func _bake_rubble(positions: Array) -> void:
	if _rubble == null:
		_rubble = MeshInstance3D.new()
		_rubble.top_level = true
		_rubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		_rubble.material_override = mat
		add_child(_rubble)
		_rubble.global_position = Vector3.ZERO
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if _rubble.mesh != null:
		st.append_from(_rubble.mesh, 0, Transform3D.IDENTITY)
	for world_pos in positions:
		_emit_box(st, world_pos, Vector3(CHUNK, CHUNK * 0.5, CHUNK), _wall_color.darkened(0.35))
	st.generate_normals()
	_rubble.mesh = st.commit()
