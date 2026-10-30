## One village house from RTS_Battlefield (house_gen.py): every wall pier, lintel, gable, floor slab,
## roof plane and chimney was split in Blender into convex Voronoi chunks. While the house stands,
## all intact chunks are drawn as ONE merged mesh (cheap) and each has a box collider (shells hit walls).
## take_blast(): chunks close to the blast fly off as Jolt rigid bodies, cracked masonry around it
## gives way, and everything that lost its connection to the foundation collapses under gravity
## (the support graph was computed in Blender). Smashed glass, soot, plaster dust and a burning ruin.
class_name EuropeHouse
extends Node3D

signal collapsed(house: EuropeHouse)

const LAYER_TERRAIN := 1
const LAYER_BUILDING := 4
const LAYER_DEBRIS := 8
const MAX_ACTIVE := 60                      # rigid bodies simulated at once (all houses)
const PHYS_PER_BLAST := 14                  # only the biggest flying pieces get real physics
const SPAWN_PER_FRAME := 8                  # pieces released per frame (no hitch)
const DIR := "res://europe/"

## material name (Blender) -> [texture, tint, uv scale, roughness, snow on top]
const WALL_TINTS := [Color(0.95, 0.93, 0.88), Color(0.92, 0.86, 0.72), Color(0.88, 0.88, 0.86), Color(0.93, 0.84, 0.70), Color(0.80, 0.78, 0.74)]
const ROOFS := [["clay_roof_tiles", Color(1.0, 1.0, 1.0)], ["clay_roof_tiles_02", Color(0.85, 0.75, 0.7)], ["grey_roof_tiles", Color(0.45, 0.62, 0.48)],
	["grey_roof_tiles", Color(0.55, 0.55, 0.6)], ["grey_roof_tiles", Color(0.62, 0.42, 0.36)]]

static var _mats := {}
static var _active: Array = []              # [RigidBody3D, age] across all houses
static var _dust_mat: StandardMaterial3D

var map: Node3D
var info: Dictionary
var center := Vector3.ZERO
var radius := 10.0
var yaw := 0.0
var size := Vector2(10, 8)
var chunks: Array = []                      # dicts, see _load()
var _place_xf := Transform3D.IDENTITY     ## ko'chirilgan uy uchun (info.place)
var statics: Array = []                     # foundation / fence / shed surfaces (never break)
var alive_count := 0
var ruined := false
var _vis: MeshInstance3D
var _body: StaticBody3D
var _debris: Node3D
var _nav_cells := PackedInt32Array()
var _dirty := false
var _rebuild_t := 0.0
var _covers: Array = []
var _slots: Array = []                      # CoverSystem slots along the walls
var _queue: Array = []                      # [chunk index, velocity, physical]
var _falling: Array = []                    # scripted (no physics) falling pieces
var _rubble: Array = []                     # landed pieces, drawn as one merged mesh
var _rubble_mi: MeshInstance3D
var _rubble_dirty := false
var _rubble_t := 0.0


static func create(parent: Node, p_map: Node3D, p_info: Dictionary) -> EuropeHouse:
	var path: String = DIR + "houses/%s.glb" % p_info.name
	if not ResourceLoader.exists(path):
		push_warning("missing house " + path)
		return null
	var h := EuropeHouse.new()
	h.name = p_info.name
	h.map = p_map
	h.info = p_info
	parent.add_child(h)
	return h


func _ready() -> void:
	add_to_group("destructibles")
	add_to_group("houses")
	yaw = float(info.rot)
	center = Vector3(info.x, 0, -float(info.y))
	# boshqa joyga ko'chirilgan uy (jang maydoni generatori): Blender'da dunyo koordinatasida eksport qilingan
	# bo'laklar asl joydan (x, z, rot, yer balandligi info.z) yangi joyga o'tkaziladi
	if info.has("place"):
		var pl: Dictionary = info.place
		var to := Vector3(float(pl.x), 0.0, float(pl.z))
		to.y = map.get_height(to.x, to.z)
		var rot := Basis(Vector3.UP, float(pl.rot) - yaw)
		_place_xf = Transform3D(rot, to) * Transform3D(Basis.IDENTITY, -Vector3(center.x, float(info.get("z", 0.0)), center.z))
		yaw = float(pl.rot)
		center = to
	center.y = map.get_height(center.x, center.z)
	size = Vector2(info.W, info.D)
	_body = StaticBody3D.new()
	_body.name = "Walls"
	_body.collision_layer = LAYER_BUILDING
	_body.collision_mask = 0
	add_child(_body)
	_debris = Node3D.new()
	_debris.name = "Debris"
	add_child(_debris)
	_vis = MeshInstance3D.new()
	_vis.name = "Intact"
	add_child(_vis)
	_rubble_mi = MeshInstance3D.new()
	_rubble_mi.name = "Rubble"
	_rubble_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rubble_mi)
	_load()
	_rebuild()
	# units walk around the house
	_nav_cells = RtsNav.add_obstacle(Transform3D(Basis(Vector3.UP, yaw), center), size, 0.4)
	_make_cover()


# ------------------------------------------------------------------ loading
func _load() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "houses/%s.json" % info.name))
	var scene: Node = (load(DIR + "houses/%s.glb" % info.name) as PackedScene).instantiate()
	var by_name := {}
	for m in scene.find_children("*", "MeshInstance3D", true, false):
		by_name[String(m.name)] = m
	var idx := 0
	for e in meta.chunks:
		var mi: MeshInstance3D = by_name.get(e.n)
		if mi == null:
			continue
		var xf := _place_xf * _xf_in_scene(mi, scene)
		var ch := {"name": e.n, "kind": e.k, "c": _place_xf * Vector3(e.c[0], e.c[1], e.c[2]), "g": int(e.g) == 1, "vol": float(e.v),
			"nb": PackedInt32Array(e.nb), "mesh": mi.mesh, "xf": xf, "alive": true, "hp": 1.0, "char": 0.0,
			"surfs": _surfaces(mi.mesh, xf)}
		var aabb: AABB = mi.mesh.get_aabb()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size.max(Vector3.ONE * 0.05)
		cs.shape = box
		cs.transform = xf * Transform3D(Basis.IDENTITY, aabb.get_center())
		_body.add_child(cs)
		ch["shape"] = cs
		chunks.append(ch)
		by_name.erase(e.n)
		idx += 1
	for n in by_name:
		var mi: MeshInstance3D = by_name[n]
		var xf := _place_xf * _xf_in_scene(mi, scene)
		statics.append({"surfs": _surfaces(mi.mesh, xf), "alive": true, "char": 0.0})
		if String(n).ends_with("_foundation"):
			var aabb: AABB = mi.mesh.get_aabb()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = aabb.size
			cs.shape = box
			cs.transform = xf * Transform3D(Basis.IDENTITY, aabb.get_center())
			_body.add_child(cs)
	scene.free()
	alive_count = chunks.size()
	var far := 0.0
	for ch in chunks:
		far = maxf(far, Vector2(ch.c.x - center.x, ch.c.z - center.z).length())
	radius = far + 2.0


static func _xf_in_scene(n: Node3D, root: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf


## Surface arrays already moved into house (= world) space, grouped by material key.
func _surfaces(mesh: Mesh, xf: Transform3D) -> Array:
	var out: Array = []
	var rot := Transform3D(xf.basis.orthonormalized(), Vector3.ZERO)
	for s in mesh.get_surface_count():
		var a: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = xf * (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var n: PackedVector3Array = rot * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		if t.size() == v.size() * 4:
			t = t.duplicate()
			for k in v.size():
				var tv := rot.basis * Vector3(t[k * 4], t[k * 4 + 1], t[k * 4 + 2])
				t[k * 4] = tv.x; t[k * 4 + 1] = tv.y; t[k * 4 + 2] = tv.z
		else:
			t = PackedFloat32Array()
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if uv.size() != v.size():
			uv.resize(v.size())
		var i: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var mat := mesh.surface_get_material(s)
		out.append({"key": mat.resource_name if mat else "default", "v": v, "n": n, "t": t, "uv": uv, "i": i})
	return out


# ------------------------------------------------------------------ materials
static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var tex := ""
	var tint := Color.WHITE
	var sc := 0.5
	var rough := 0.85
	var cap := 0.35
	var grime := true
	if key.begins_with("MAT_Plaster_"):
		tex = "painted_plaster_wall"; tint = WALL_TINTS[clampi(int(key.get_slice("_", 2)), 0, 4)]; sc = 0.5
	elif key.begins_with("MAT_Roof_"):
		var r: Array = ROOFS[clampi(int(key.get_slice("_", 2)), 0, 4)]
		tex = r[0]; tint = r[1]; sc = 0.45; cap = 1.0; rough = 0.8
	elif key == "MAT_FractureBrick":
		tex = "broken_brick_wall"; tint = Color(0.9, 0.85, 0.8); sc = 0.6; grime = false
	elif key == "MAT_Concrete":
		tex = "concrete_wall_008"; tint = Color(0.8, 0.8, 0.8); sc = 0.4; grime = false; cap = 1.0
	elif key == "MAT_Brick":
		tex = "large_red_bricks"; tint = Color(0.9, 0.85, 0.8); sc = 0.7; cap = 1.0
	elif key == "MAT_WoodDark":
		tex = "dark_wooden_planks"; tint = Color(0.8, 0.75, 0.7); sc = 0.5; grime = false
	elif key == "MAT_FenceWood":
		tex = "dark_wooden_planks"; tint = Color(0.75, 0.68, 0.6); sc = 0.6; grime = false; cap = 0.8
	elif key == "MAT_ShedRoof":
		tex = "grey_roof_tiles"; tint = Color(0.42, 0.4, 0.38); sc = 0.6; cap = 1.0
	var m: Material
	if tex == "":
		var sm := StandardMaterial3D.new()
		if key == "MAT_WindowGlass":
			sm.albedo_color = Color(0.03, 0.035, 0.04)
			sm.roughness = 0.05
			sm.metallic_specular = 0.9
		else:
			sm.albedo_color = Color(0.82, 0.82, 0.79)
			sm.roughness = 0.6
		m = sm
	else:
		var shm := ShaderMaterial.new()
		shm.shader = load(DIR + "house.gdshader")
		shm.set_shader_parameter("albedo_tex", load(DIR + "textures/%s_diff.jpg" % tex))
		shm.set_shader_parameter("normal_tex", load(DIR + "textures/%s_nor_gl.jpg" % tex))
		shm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
		shm.set_shader_parameter("uv_scale", sc)
		shm.set_shader_parameter("roughness", rough)
		shm.set_shader_parameter("snow_cap", cap)
		shm.set_shader_parameter("grime", grime)
		m = shm
	_mats[key] = m
	return m


# ------------------------------------------------------------------ merged mesh of the intact chunks
func _rebuild() -> void:
	_dirty = false
	_vis.mesh = _merge([chunks, statics])


func _merge(lists: Array) -> ArrayMesh:
	var groups := {}
	for list in lists:
		for ch in list:
			if not ch.alive:
				continue
			var col := Color(ch.char, 0, 0)
			for s in ch.surfs:
				if not groups.has(s.key):
					groups[s.key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(),
						"c": PackedColorArray(), "i": PackedInt32Array(), "has_t": true}
				var g: Dictionary = groups[s.key]
				var base: int = g.v.size()
				g.v.append_array(s.v)
				g.n.append_array(s.n)
				g.uv.append_array(s.uv)
				if s.t.is_empty():
					g.has_t = false
				else:
					g.t.append_array(s.t)
				var cc := PackedColorArray()
				cc.resize(s.v.size())
				cc.fill(col)
				g.c.append_array(cc)
				var ii: PackedInt32Array = s.i
				var gi: PackedInt32Array = g.i
				var o := gi.size()
				gi.resize(o + ii.size())
				for k in ii.size():
					gi[o + k] = ii[k] + base
				g.i = gi
	var mesh := ArrayMesh.new()
	for key in groups:
		var g: Dictionary = groups[key]
		if g.i.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g.v
		arr[Mesh.ARRAY_NORMAL] = g.n
		if g.has_t and g.t.size() == g.v.size() * 4:
			arr[Mesh.ARRAY_TANGENT] = g.t
		arr[Mesh.ARRAY_TEX_UV] = g.uv
		arr[Mesh.ARRAY_COLOR] = g.c
		arr[Mesh.ARRAY_INDEX] = g.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(key))
	return mesh


# ------------------------------------------------------------------ damage
## Explosion: radius = blast radius from RtsExplosion (4 * size + 1).
func take_blast(at: Vector3, r: float) -> void:
	if Vector2(at.x - center.x, at.z - center.z).length() > radius + r:
		return
	var r_kill := r * 0.5
	var r_crack := r * 1.15
	var power := clampf(r / 5.8, 0.4, 2.0)
	var flown := 0
	var hit_pos := Vector3.ZERO
	var hits: Array = []
	for i in chunks.size():
		var ch: Dictionary = chunks[i]
		if not ch.alive:
			continue
		var d: float = maxf(0.0, (ch.c as Vector3).distance_to(at) - 0.35)
		if d > r_crack * 1.4:
			continue
		var soot := clampf(1.25 - d / (r * 1.4), 0.0, 1.0)
		if soot > ch.char:
			ch.char = soot
			_dirty = true
		if ch.kind == "window" and d < r * 0.9:
			_detach(i, Vector3.ZERO, false)     # glass shatters
			continue
		if d < r_kill:
			var dir: Vector3 = ((ch.c as Vector3) - at).normalized()
			dir.y = dir.y * 0.6 + 0.35
			hits.append([i, dir.normalized() * lerpf(15.0, 4.0, d / r_kill) * power])
		elif d < r_crack:
			ch.hp -= (1.0 - d / r_crack) * power * 1.3
			if ch.hp <= 0.0:
				hits.append([i, ((ch.c as Vector3) - at).normalized() * 2.0])
	# the biggest pieces fly as real rigid bodies, the rest is scripted (cheap)
	hits.sort_custom(func(x, y): return chunks[x[0]].vol > chunks[y[0]].vol)
	for k in hits.size():
		_detach(hits[k][0], hits[k][1], k < PHYS_PER_BLAST)
		hit_pos += chunks[hits[k][0]].c
	flown = hits.size()
	var fell := _support_check()
	if flown + fell > 0:
		_dirty = true
		var c: Vector3 = hit_pos / maxi(1, flown) if flown > 0 else at
		_dust(c, clampf(0.8 + (flown + fell) * 0.03, 0.8, 3.5))
		if fell > 25:
			get_tree().create_timer(0.8).timeout.connect(func(): _dust(center + Vector3.UP * 2.0, clampf(fell * 0.04, 1.2, 4.0)))
	_check_ruin()


## Breadth-first search from the chunks that sit on the foundation; whatever is no longer connected falls.
func _support_check() -> int:
	var seen := PackedByteArray()
	seen.resize(chunks.size())
	var q: Array[int] = []
	for i in chunks.size():
		if chunks[i].alive and chunks[i].g:
			seen[i] = 1
			q.append(i)
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		for j in chunks[i].nb:
			if seen[j] == 0 and chunks[j].alive:
				seen[j] = 1
				q.append(j)
	var n := 0
	for i in chunks.size():
		if chunks[i].alive and seen[i] == 0:
			_detach(i, Vector3(randf_range(-0.8, 0.8), randf_range(-0.5, 0.3), randf_range(-0.8, 0.8)), n < 6 and chunks[i].vol > 0.3)
			n += 1
	return n


func _detach(i: int, vel: Vector3, physical: bool) -> void:
	var ch: Dictionary = chunks[i]
	if not ch.alive:
		return
	ch.alive = false
	alive_count -= 1
	_dirty = true
	if is_instance_valid(ch.shape):
		ch.shape.queue_free()
	if ch.kind == "window":
		return
	_queue.append([i, vel, physical])


func _piece_mesh(ch: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ch.mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in (ch.mesh as Mesh).get_surface_count():
		var m := (ch.mesh as Mesh).surface_get_material(s)
		mi.set_surface_override_material(s, material(m.resource_name if m else "default"))
	mi.set_instance_shader_parameter("char_amount", ch.char)
	return mi


func _spawn(i: int, vel: Vector3, physical: bool) -> void:
	var ch: Dictionary = chunks[i]
	var xf := global_transform * (ch.xf as Transform3D)
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.6 + vel.length() * 0.3)
	if physical and _active.size() < MAX_ACTIVE:
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER_DEBRIS
		rb.collision_mask = LAYER_TERRAIN | LAYER_BUILDING      # pieces never collide with each other (cheap)
		rb.mass = clampf(float(ch.vol) * 1600.0, 15.0, 4000.0)
		rb.can_sleep = true
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.05
		rb.physics_material_override = pm
		rb.linear_damp = 0.2
		rb.angular_damp = 0.6
		rb.add_child(_piece_mesh(ch))
		var aabb: AABB = (ch.mesh as Mesh).get_aabb()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size.max(Vector3.ONE * 0.08)
		cs.shape = box
		cs.position = aabb.get_center()
		rb.add_child(cs)
		_debris.add_child(rb)
		rb.global_transform = xf
		rb.linear_velocity = vel
		rb.angular_velocity = spin
		_active.append([rb, 0.0, self, i])
		return
	var mi := _piece_mesh(ch)
	_debris.add_child(mi)
	mi.global_transform = xf
	_falling.append({"mi": mi, "vel": vel, "spin": spin, "i": i})


func _physics_process(delta: float) -> void:
	# release queued pieces a few per frame
	var n := 0
	while not _queue.is_empty() and n < SPAWN_PER_FRAME:
		var q: Array = _queue.pop_front()
		_spawn(q[0], q[1], q[2])
		n += 1
	# scripted falling pieces: gravity + tumble until they hit the ground, then they become rubble
	if not _falling.is_empty():
		var keep: Array = []
		for f in _falling:
			var mi: MeshInstance3D = f.mi
			f.vel += Vector3(0, -9.8, 0) * delta
			var xf := mi.global_transform
			xf.origin += f.vel * delta
			if f.spin.length() > 0.01:
				xf.basis = Basis(f.spin.normalized(), f.spin.length() * delta) * xf.basis
			var gy: float = map.get_height(xf.origin.x, xf.origin.z) + 0.2
			if xf.origin.y <= gy:
				xf.origin.y = gy
				mi.global_transform = xf
				_land(f.i, xf)
				mi.queue_free()
				continue
			mi.global_transform = xf
			keep.append(f)
		_falling = keep
	if _dirty:
		_rebuild_t -= delta
		if _rebuild_t <= 0.0:
			_rebuild_t = 0.12
			_rebuild()
	if _rubble_dirty:
		_rubble_t -= delta
		if _rubble_t <= 0.0:
			_rubble_t = 0.6
			_rubble_dirty = false
			_rubble_mi.mesh = _merge([_rubble])


## A piece came to rest: it joins the merged rubble mesh (no node, no physics any more).
func _land(i: int, world_xf: Transform3D) -> void:
	var ch: Dictionary = chunks[i]
	_rubble.append({"surfs": _surfaces(ch.mesh, global_transform.affine_inverse() * world_xf), "alive": true, "char": ch.char})
	_rubble_dirty = true


## Rigid pieces settle (asleep or after a few seconds) and are turned into rubble (called by the map).
static func tick_debris(delta: float) -> void:
	if _active.is_empty():
		return
	var keep: Array = []
	for e in _active:
		var body = e[0]
		if not is_instance_valid(body):
			continue
		e[1] += delta
		var rb := body as RigidBody3D
		if rb.global_position.y < -40.0:
			rb.queue_free()
			continue
		if e[1] > 5.0 or (e[1] > 1.2 and rb.sleeping):
			var h = e[2]
			if is_instance_valid(h):
				h._land(e[3], rb.global_transform)
			rb.queue_free()
			continue
		keep.append(e)
	_active = keep


func _check_ruin() -> void:
	if ruined:
		return
	var walls := 0
	var walls_alive := 0
	for ch in chunks:
		if ch.kind == "wall":
			walls += 1
			if ch.alive:
				walls_alive += 1
	if walls > 0 and float(walls_alive) / walls < 0.45:
		ruined = true
		for sl in _slots:
			sl.prot = 0.7                           # rubble: still cover, but not a solid wall
			sl.kind = "ruin"
		RtsNav.remove_obstacle(_nav_cells)        # the rubble can be crossed
		_nav_cells = PackedInt32Array()
		_burn()
		collapsed.emit(self)


## Burning ruin: low flames and a thick black smoke column for a minute (like the reference footage).
func _burn() -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = center + Vector3(randf_range(-1.5, 1.5), 0.8, randf_range(-1.5, 1.5))
	var fp := RtsExplosion._proc(Vector3.UP, 25.0, 0.6, 1.6, 1.6)
	fp.scale_min = 1.2
	fp.scale_max = 2.4
	fp.gravity = Vector3(0, 1.5, 0)
	fp.anim_speed_min = 1.0
	fp.anim_speed_max = 1.0
	fp.color = Color(2.2, 1.8, 1.4)
	fp.color_ramp = RtsExplosion._grad([0.0, 0.2, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var fire := RtsExplosion._particles(24, 1.2, fp, RtsExplosion._quad("fire"), 0.0)
	fire.one_shot = false
	root.add_child(fire)
	var sp := RtsExplosion._proc(Vector3.UP, 12.0, 1.5, 3.0, 1.5)
	sp.scale_min = 3.0
	sp.scale_max = 5.5
	sp.scale_curve = RtsExplosion._curve([Vector2(0, 0.4), Vector2(1, 2.2)], 2.5)
	sp.gravity = Vector3(1.2, 0.7, 0.4)
	sp.damping_min = 0.4
	sp.damping_max = 0.8
	sp.anim_speed_min = 1.0
	sp.anim_speed_max = 1.0
	sp.color_ramp = RtsExplosion._grad([0.0, 0.08, 0.5, 1.0],
		[Color(0.06, 0.055, 0.05, 0.0), Color(0.08, 0.075, 0.07, 0.9), Color(0.22, 0.21, 0.2, 0.6), Color(0.45, 0.44, 0.43, 0.0)])
	var smoke := RtsExplosion._particles(60, 14.0, sp, RtsExplosion._quad("smoke_lit"), 0.0)
	smoke.one_shot = false
	smoke.visibility_aabb = AABB(Vector3(-80, -10, -80), Vector3(160, 120, 160))
	root.add_child(smoke)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 2.5
	l.omni_range = 9.0
	root.add_child(l)
	get_tree().create_timer(75.0).timeout.connect(func():
		if is_instance_valid(fire):
			fire.emitting = false
			l.queue_free()
			smoke.emitting = false
			get_tree().create_timer(16.0).timeout.connect(root.queue_free))


# ------------------------------------------------------------------ dust
func _dust(at: Vector3, s: float) -> void:
	var pm := RtsExplosion._proc(Vector3.UP, 70.0, 0.5 * s, 2.5 * s, 1.2 * s)
	pm.radial_velocity_min = 1.0 * s
	pm.radial_velocity_max = 3.5 * s
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.gravity = Vector3(0.4, 0.25, 0.15)
	pm.scale_min = 2.5 * s
	pm.scale_max = 4.5 * s
	pm.scale_curve = RtsExplosion._curve([Vector2(0, 0.4), Vector2(1, 1.9)], 2.0)
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.color_ramp = RtsExplosion._grad([0.0, 0.06, 0.5, 1.0],
		[Color(0.72, 0.68, 0.62, 0.0), Color(0.74, 0.7, 0.64, 0.8), Color(0.78, 0.75, 0.7, 0.45), Color(0.8, 0.78, 0.75, 0.0)])
	var p := RtsExplosion._particles(int(16 + 10 * s), 7.0 + s * 2.0, pm, RtsExplosion._quad("smoke_lit"), 0.85)
	add_child(p)
	p.global_position = at
	get_tree().create_timer(10.0 + s * 2.0).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ cover for infantry along the walls
func _make_cover() -> void:
	var b := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.5 + 0.9
	var hz := size.y * 0.5 + 0.9
	for side in 4:
		var along := hx if side < 2 else hz
		var n := maxi(2, int(along * 2.0 / 2.5))
		for k in n:
			var t := (k + 0.5) / n * 2.0 - 1.0
			var lp: Vector3
			var nrm: Vector3
			match side:
				0: lp = Vector3(t * (hx - 0.8), 0, hz); nrm = Vector3(0, 0, 1)
				1: lp = Vector3(t * (hx - 0.8), 0, -hz); nrm = Vector3(0, 0, -1)
				2: lp = Vector3(hx, 0, t * (hz - 0.8)); nrm = Vector3(1, 0, 0)
				_: lp = Vector3(-hx, 0, t * (hz - 0.8)); nrm = Vector3(-1, 0, 0)
			var p := center + b * lp
			p.y = map.get_height(p.x, p.z)
			var c := Marker3D.new()
			add_child(c)
			c.global_position = p
			_covers.append(c)
			# the wall is behind the man (towards the house): it shields him from everything on the far side
			_slots.append(CoverSystem.add(p, -(b * nrm), 1.0, "wall", self))
	# corners: lean out and fire along two walls
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var p := center + b * Vector3(cx * hx, 0, cz * hz)
			p.y = map.get_height(p.x, p.z)
			_slots.append(CoverSystem.add(p, -(b * Vector3(cx, 0, cz)), 0.75, "corner", self))


func cover_points() -> Array:
	return _covers.filter(func(c): return is_instance_valid(c))


## Fraction of the house still standing (0..1).
func integrity() -> float:
	return float(alive_count) / maxf(1.0, chunks.size())
