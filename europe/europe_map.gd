## 600 x 600 m European battlefield built in Blender (RTS_Battlefield/terrain_europe):
## rolling farmland, three dirt roads, old craters and tank tracks, the village of nine
## pre-fractured houses along the main road, 1200 trees, bushes, rocks and dead wood.
## Same interface as the old 2 km map, so units, trenches and game modes work unchanged:
##   get_height(x, z)  ground_original(x, z)  dig_segment(a, b, half_w, depth)
##   clear_trees(center, radius)  set_winter(on)  winter
## Explosions call take_blast(): trees near a blast fall over, tanks flatten the trees they drive into.
class_name EuropeMap
extends Node3D

const RES := 1025
const SIZE := 600.0
const HALF := 300.0
const GRID := SIZE / 1024.0
const CHUNK_CELLS := 64
const NCH := 16
const DIR := "res://europe/"

const TREE_TYPES := ["island_tree_01", "island_tree_02", "island_tree_03", "tree_small_02"]   # bare in winter, leaves in summer

@export var winter := true: set = set_winter

var heights := PackedFloat32Array()      # metres, row j = z, col i = x
## Jang maydoni generatori natijasi (BattleGen.generate). Bo'sh bo'lsa - asl qishki qishloq fayllardan.
var spec: Dictionary = {}
var houses: Array = []
var _chunks: Array = []                  # MeshInstance3D per terrain chunk
var _shapes: Array = []                  # HeightMapShape3D per chunk (only dug chunks are rebuilt)
var _mat: ShaderMaterial
var _dug_img: Image
var _dug_tex: ImageTexture
var _sun: DirectionalLight3D
var _env: Environment
var _snowfall: GPUParticles3D
var _veg_meshes := {}                    # type -> {bare: Mesh, full: Mesh}
var _veg_mmis: Array = []                # [type, MultiMeshInstance3D]
var _trees := {}                         # Vector2i cell (8 m) -> Array of tree entries
var _fallen: Array = []                  # [type, MeshInstance3D]
var _crush_t := 0.0


func _ready() -> void:
	add_to_group("destructibles")
	CoverSystem.reset()
	if spec.is_empty():
		_load_heights()
	else:
		heights = spec.heights
		winter = bool(spec.get("winter", false))
	_build_terrain()
	_build_lighting()
	RtsGround.height_func = get_height
	if spec.is_empty():
		RtsNav.setup(DIR + "terrain/nav_open.png", Vector2(-HALF, -HALF), 2.0)
	else:
		RtsNav.setup_image(spec.nav, Vector2(-HALF, -HALF), 2.0)
		if spec.get("water", false):
			BattleWater.create(self, float(spec.get("coast", -232.0)))
	_build_vegetation()
	_build_houses()
	set_winter(winter)


# ------------------------------------------------------------------ heights
func _load_heights() -> void:
	var f := FileAccess.open(DIR + "terrain/height_1025.f32", FileAccess.READ)
	if f == null:
		push_error("europe map: height_1025.f32 missing")
		heights.resize(RES * RES)
		return
	heights = f.get_buffer(RES * RES * 4).to_float32_array()


func terrain_height(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / GRID, 0.0, RES - 1.001)
	var gz := clampf((z + HALF) / GRID, 0.0, RES - 1.001)
	var i := int(gx); var j := int(gz)
	var fx := gx - i; var fz := gz - j
	var k := j * RES + i
	return lerpf(lerpf(heights[k], heights[k + 1], fx), lerpf(heights[k + RES], heights[k + RES + 1], fx), fz)


func get_height(x: float, z: float) -> float:
	return terrain_height(x, z)


func _hh(i: int, j: int) -> float:
	return heights[clampi(j, 0, RES - 1) * RES + clampi(i, 0, RES - 1)]


# ------------------------------------------------------------------ terrain mesh + collision
func _build_terrain() -> void:
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	_dug_img = Image.create(RES, RES, false, Image.FORMAT_L8)
	_dug_tex = ImageTexture.create_from_image(_dug_img)
	_mat = ShaderMaterial.new()
	_mat.shader = load(DIR + "terrain.gdshader")
	_mat.set_shader_parameter("albedo_array", load(DIR + "textures/terrain_albedo_array.png"))
	_mat.set_shader_parameter("normal_array", load(DIR + "textures/terrain_normal_array.png"))
	if spec.is_empty():
		_mat.set_shader_parameter("splat1", load(DIR + "terrain/splat1.png"))
		_mat.set_shader_parameter("splat2", load(DIR + "terrain/splat2.png"))
	else:
		_mat.set_shader_parameter("splat1", ImageTexture.create_from_image(spec.splat1))
		_mat.set_shader_parameter("splat2", ImageTexture.create_from_image(spec.splat2))
		for k in spec.get("shader", {}):
			_mat.set_shader_parameter(k, spec.shader[k])
	_mat.set_shader_parameter("dug_tex", _dug_tex)
	_mat.set_shader_parameter("map_size", SIZE)
	for cz in NCH:
		for cx in NCH:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.layers |= RtsGround.DECAL_LAYER          # decals (scorch, blood, footprints) paint the ground only
			root.add_child(mi)
			_chunks.append(mi)
			_rebuild_chunk(cx, cz)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	root.add_child(body)
	for cz in NCH:
		for cx in NCH:
			var cs := CollisionShape3D.new()
			var sh := HeightMapShape3D.new()
			sh.map_width = CHUNK_CELLS + 1
			sh.map_depth = CHUNK_CELLS + 1
			sh.map_data = _chunk_heights(cx, cz)
			cs.shape = sh
			cs.scale = Vector3.ONE * GRID                  # uniform scale: heights are stored divided by GRID
			cs.position = Vector3(-HALF + (cx * CHUNK_CELLS + CHUNK_CELLS * 0.5) * GRID, 0.0, -HALF + (cz * CHUNK_CELLS + CHUNK_CELLS * 0.5) * GRID)
			body.add_child(cs)
			_shapes.append(sh)


func _chunk_heights(cx: int, cz: int) -> PackedFloat32Array:
	var w := CHUNK_CELLS + 1
	var d := PackedFloat32Array()
	d.resize(w * w)
	var inv := 1.0 / GRID
	var n := 0
	for j in range(cz * CHUNK_CELLS, cz * CHUNK_CELLS + w):
		var row := j * RES
		for i in range(cx * CHUNK_CELLS, cx * CHUNK_CELLS + w):
			d[n] = heights[row + i] * inv
			n += 1
	return d


func _rebuild_chunk(cx: int, cz: int) -> void:
	var mi: MeshInstance3D = _chunks[cz * NCH + cx]
	var cells := CHUNK_CELLS
	var w := cells + 1
	var verts := PackedVector3Array(); verts.resize(w * w)
	var norms := PackedVector3Array(); norms.resize(w * w)
	var uvs := PackedVector2Array(); uvs.resize(w * w)
	var n := 0
	for j in range(cz * cells, cz * cells + w):
		for i in range(cx * cells, cx * cells + w):
			var x := -HALF + i * GRID
			var z := -HALF + j * GRID
			verts[n] = Vector3(x, _hh(i, j), z)
			norms[n] = Vector3(_hh(i - 1, j) - _hh(i + 1, j), 2.0 * GRID, _hh(i, j - 1) - _hh(i, j + 1)).normalized()
			uvs[n] = Vector2((x + HALF) / SIZE, (z + HALF) / SIZE)
			n += 1
	var idx := PackedInt32Array(); idx.resize(cells * cells * 6)
	n = 0
	for j in cells:
		for i in cells:
			var a := j * w + i
			idx[n] = a; idx[n + 1] = a + 1; idx[n + 2] = a + w
			idx[n + 3] = a + 1; idx[n + 4] = a + w + 1; idx[n + 5] = a + w
			n += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, _mat)
	mi.mesh = m


# ------------------------------------------------------------------ trench digging (same as the old map)
var _orig := {}            # vertex index -> original height (m)
var _dig := {}             # vertex index -> dug depth (m)
var _dirty := {}           # Vector2i chunk -> true
var _deform_t := 0.0


func ground_original(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / GRID, 0.0, RES - 1.001)
	var gz := clampf((z + HALF) / GRID, 0.0, RES - 1.001)
	var i := int(gx); var j := int(gz)
	var fx := gx - i; var fz := gz - j
	return lerpf(lerpf(_oh(i, j), _oh(i + 1, j), fx), lerpf(_oh(i, j + 1), _oh(i + 1, j + 1), fx), fz)


func _oh(i: int, j: int) -> float:
	var k := j * RES + i
	return _orig[k] if _orig.has(k) else heights[k]


func dig_segment(a: Vector3, b: Vector3, half_w: float, depth: float) -> void:
	var inner := half_w + 0.6
	var outer := half_w + 1.6
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * (outer + GRID)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * (outer + GRID)
	var i0 := clampi(int((lo.x + HALF) / GRID), 0, RES - 1)
	var i1 := clampi(int((hi.x + HALF) / GRID) + 1, 0, RES - 1)
	var j0 := clampi(int((lo.y + HALF) / GRID), 0, RES - 1)
	var j1 := clampi(int((hi.y + HALF) / GRID) + 1, 0, RES - 1)
	var a2 := Vector2(a.x, a.z); var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var l2 := maxf(ab.length_squared(), 0.0001)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(-HALF + i * GRID, -HALF + j * GRID)
			var t := clampf((p - a2).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a2 + ab * t)
			if d >= outer:
				continue
			var dg := depth + 0.2
			if d > inner:
				dg *= 1.0 - (d - inner) / (outer - inner)
			var k := j * RES + i
			if dg <= _dig.get(k, 0.0):
				continue
			if not _orig.has(k):
				_orig[k] = heights[k]
			_dig[k] = dg
			heights[k] = _orig[k] - dg
			_dug_img.set_pixel(i, j, Color(1, 1, 1))
			var cx := mini(i / CHUNK_CELLS, NCH - 1); var cz := mini(j / CHUNK_CELLS, NCH - 1)
			_dirty[Vector2i(cx, cz)] = true
			if i % CHUNK_CELLS == 0 and cx > 0: _dirty[Vector2i(cx - 1, cz)] = true
			if j % CHUNK_CELLS == 0 and cz > 0: _dirty[Vector2i(cx, cz - 1)] = true
			if i % CHUNK_CELLS == 0 and j % CHUNK_CELLS == 0 and cx > 0 and cz > 0: _dirty[Vector2i(cx - 1, cz - 1)] = true


## Shell craters: the ground really caves in (small bowl + rim), like the craters baked into the map.
func crater(at: Vector3, radius: float) -> void:
	var rr := clampf(radius, 0.8, 4.5)
	# a fresh shell hole is a new place to hide
	if rr >= 1.2 and CoverSystem.query(at, 2.5).filter(func(s): return s.kind == "crater").is_empty():
		CoverSystem.add(Vector3(at.x, get_height(at.x, at.z) - rr * 0.25, at.z), Vector3.ZERO, 0.6, "crater", self)
	var depth := rr * 0.28
	var i0 := clampi(int((at.x - rr * 1.5 + HALF) / GRID), 0, RES - 1)
	var i1 := clampi(int((at.x + rr * 1.5 + HALF) / GRID) + 1, 0, RES - 1)
	var j0 := clampi(int((at.z - rr * 1.5 + HALF) / GRID), 0, RES - 1)
	var j1 := clampi(int((at.z + rr * 1.5 + HALF) / GRID) + 1, 0, RES - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(-HALF + i * GRID, -HALF + j * GRID)
			var d := p.distance_to(Vector2(at.x, at.z)) / rr
			if d > 1.5:
				continue
			var k := j * RES + i
			var bowl := -depth * pow(maxf(0.0, 1.0 - d * d), 1.3)
			var rim := 0.25 * depth * exp(-pow((d - 1.05) / 0.28, 2.0))
			heights[k] += bowl + rim
			if d < 1.1:
				_dug_img.set_pixel(i, j, Color(maxf(_dug_img.get_pixel(i, j).r, 0.55 * (1.1 - d)), 0, 0))
			var cx := mini(i / CHUNK_CELLS, NCH - 1); var cz := mini(j / CHUNK_CELLS, NCH - 1)
			_dirty[Vector2i(cx, cz)] = true
			if i % CHUNK_CELLS == 0 and cx > 0: _dirty[Vector2i(cx - 1, cz)] = true
			if j % CHUNK_CELLS == 0 and cz > 0: _dirty[Vector2i(cx, cz - 1)] = true


func _flush_terrain() -> void:
	if _dirty.is_empty():
		return
	for c in _dirty.keys():
		_rebuild_chunk(c.x, c.y)
		(_shapes[c.y * NCH + c.x] as HeightMapShape3D).map_data = _chunk_heights(c.x, c.y)
	_dirty.clear()
	_dug_tex.update(_dug_img)


# ------------------------------------------------------------------ light, sky, snow
func _build_lighting() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 320.0
	_sun.directional_shadow_blend_splits = true
	_sun.shadow_blur = 1.2
	_sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-145.0), 0.0)
	add_child(_sun)
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.0
	_env.ssao_enabled = true
	_env.ssao_radius = 1.6
	_env.ssao_intensity = 2.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.35
	_env.glow_hdr_threshold = 1.4
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.4
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = _env
	add_child(we)


func set_winter(on: bool) -> void:
	winter = on
	if not is_inside_tree() or _env == null:
		return
	RenderingServer.global_shader_parameter_set("snow_amount", 1.0 if on else 0.0)
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	if on:
		_sun.light_color = Color(0.93, 0.95, 1.0); _sun.light_energy = 1.15
		sky.sky_top_color = Color(0.56, 0.62, 0.7); sky.sky_horizon_color = Color(0.86, 0.88, 0.9)
		sky.ground_horizon_color = Color(0.82, 0.84, 0.86); sky.ground_bottom_color = Color(0.6, 0.62, 0.64)
		_env.fog_light_color = Color(0.84, 0.87, 0.92); _env.fog_density = 0.0022
		_env.adjustment_saturation = 0.8
		_env.ambient_light_energy = 1.1
	else:
		_sun.light_color = Color(1.0, 0.94, 0.85); _sun.light_energy = 1.35
		sky.sky_top_color = Color(0.32, 0.47, 0.7); sky.sky_horizon_color = Color(0.74, 0.78, 0.82)
		sky.ground_horizon_color = Color(0.6, 0.6, 0.55); sky.ground_bottom_color = Color(0.3, 0.28, 0.24)
		_env.fog_light_color = Color(0.7, 0.74, 0.78); _env.fog_density = 0.0009
		_env.adjustment_saturation = 0.95
		_env.ambient_light_energy = 0.9
	for e in _veg_mmis:
		var t: String = e[0]
		if _veg_meshes.has(t) and _veg_meshes[t].has("bare"):
			(e[1] as MultiMeshInstance3D).multimesh.mesh = _veg_meshes[t]["bare" if on else "full"]
	for e in _fallen:
		if is_instance_valid(e[1]) and _veg_meshes.has(e[0]) and _veg_meshes[e[0]].has("bare"):
			(e[1] as MeshInstance3D).mesh = _veg_meshes[e[0]]["bare" if on else "full"]
	if on and _snowfall == null:
		_snowfall = _make_snowfall()
		add_child(_snowfall)
	if _snowfall:
		_snowfall.emitting = on
		_snowfall.visible = on


func _make_snowfall() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 2, 90)
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 8.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0.4, -1.0, 0.2)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.6; pm.scale_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	var p := GPUParticles3D.new()
	p.name = "Snowfall"
	p.amount = 6000
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.process_material = pm
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-100, -60, -100), Vector3(200, 80, 200))
	return p


# ------------------------------------------------------------------ vegetation
func _mesh_from_glb(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		push_warning("missing vegetation model " + path)
		return null
	var inst := (load(path) as PackedScene).instantiate()
	var out: Mesh = null
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		out = (c as MeshInstance3D).mesh
		break
	inst.free()
	if out == null:
		return null
	# leaf / twig cards: alpha scissor, two sided; soft sub-surface light through the leaves
	for si in out.get_surface_count():
		var m := out.surface_get_material(si) as BaseMaterial3D
		if m == null:
			continue
		m = m.duplicate()
		if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.resource_name.to_lower().contains("lea") or m.resource_name.to_lower().contains("branch"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		out.surface_set_material(si, m)
	return out


func _veg_mesh(type: String, variant := "") -> Mesh:
	if TREE_TYPES.has(type):
		if not _veg_meshes.has(type):
			_veg_meshes[type] = {"bare": _mesh_from_glb(DIR + "vegetation/%s_bare.glb" % type), "full": _mesh_from_glb(DIR + "vegetation/%s_full.glb" % type)}
		return _veg_meshes[type]["bare" if winter else "full"]
	if not _veg_meshes.has(type):
		_veg_meshes[type] = {"one": _mesh_from_glb(DIR + "vegetation/%s.glb" % type)}
	return _veg_meshes[type]["one"]


func _build_vegetation() -> void:
	var data: Dictionary = spec.get("vegetation", {})
	if spec.is_empty():
		var f := FileAccess.open(DIR + "vegetation.json", FileAccess.READ)
		if f == null:
			return
		data = JSON.parse_string(f.get_as_text())
	var root := Node3D.new()
	root.name = "Vegetation"
	add_child(root)
	const CELL := 100.0
	var ranges := {"trees": 360.0, "bushes": 220.0, "rocks": 260.0, "debris": 180.0}
	for cat in data:
		for type in data[cat]:
			var mesh := _veg_mesh(type)
			if mesh == null:
				continue
			var cells := {}
			for e in data[cat][type]:
				var c := Vector2i(int(floor((e[0] + HALF) / CELL)), int(floor((e[2] + HALF) / CELL)))
				if not cells.has(c): cells[c] = []
				cells[c].append(e)
			for c in cells:
				var arr: Array = cells[c]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				mm.instance_count = arr.size()
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.visibility_range_end = ranges.get(cat, 250.0)
				mmi.visibility_range_end_margin = 25.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if cat == "debris" or cat == "bushes":
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if cat == "debris" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				root.add_child(mmi)
				_veg_mmis.append([type, mmi])
				for k in arr.size():
					var e: Array = arr[k]
					var x: float = e[0]; var z: float = e[2]
					var s: float = e[4]
					var sink := 0.12 * s if cat == "rocks" else 0.05
					var xf := Transform3D(Basis(Vector3.UP, e[3]).scaled(Vector3.ONE * s), Vector3(x, get_height(x, z) - sink, z))
					mm.set_instance_transform(k, xf)
					if cat == "trees" or cat == "bushes":
						var tc := Vector2i(int(floor(x / 8.0)), int(floor(z / 8.0)))
						if not _trees.has(tc): _trees[tc] = []
						var entry := {"mmi": mmi, "i": k, "xf": xf, "type": type, "alive": true, "tree": cat == "trees", "slot": null}
						if cat == "trees":
							entry.slot = CoverSystem.add(xf.origin, Vector3.ZERO, 0.35, "tree", self)   # a trunk: half cover
						_trees[tc].append(entry)
					elif cat == "rocks" and s > 0.6 and not type.begins_with("stone_01") and not type.begins_with("rock_07"):
						CoverSystem.add(xf.origin, Vector3.ZERO, 0.7, "rock", self)
					elif cat == "debris" and not type.begins_with("dry_branches"):
						CoverSystem.add(xf.origin, Vector3.ZERO, 0.5, "log", self)


func _trees_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var c0 := Vector2i(int(floor((p.x - r) / 8.0)), int(floor((p.z - r) / 8.0)))
	var c1 := Vector2i(int(floor((p.x + r) / 8.0)), int(floor((p.z + r) / 8.0)))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for t in _trees.get(Vector2i(cx, cz), []):
				if t.alive and Vector2(t.xf.origin.x - p.x, t.xf.origin.z - p.z).length() < r:
					out.append(t)
	return out


func _hide_instance(t: Dictionary) -> void:
	t.alive = false
	if t.get("slot") != null:
		CoverSystem.remove(t.slot)
		t.slot = null
	var mm: MultiMesh = (t.mmi as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(t.i, Transform3D(Basis().scaled(Vector3.ZERO), t.xf.origin))


## Tree falls over away from `from` (blast or a tank driving into it).
func topple(t: Dictionary, from: Vector3, fast := false) -> void:
	if not t.alive:
		return
	_hide_instance(t)
	if not t.tree:
		return                                   # bushes are simply flattened
	var mi := MeshInstance3D.new()
	mi.mesh = (t.mmi as MultiMeshInstance3D).multimesh.mesh
	add_child(mi)
	mi.global_transform = t.xf
	_fallen.append([t.type, mi])
	var away: Vector3 = t.xf.origin - from
	away.y = 0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	away = away.normalized()
	var axis := Vector3.UP.cross(away).normalized()
	var b0: Basis = t.xf.basis
	var ang := deg_to_rad(randf_range(80.0, 88.0))
	var dur := 0.9 if fast else randf_range(1.4, 2.0)
	var tw := mi.create_tween()
	tw.tween_method(func(a: float): mi.global_transform = Transform3D(Basis(axis, a) * b0, t.xf.origin), 0.0, ang, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(a: float): mi.global_transform = Transform3D(Basis(axis, a) * b0, t.xf.origin), ang, ang - 0.06, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float): mi.global_transform = Transform3D(Basis(axis, a) * b0, t.xf.origin), ang - 0.06, ang, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# the fallen trunk is cover for infantry
	var lp: Vector3 = t.xf.origin + away * 3.0
	lp.y = get_height(lp.x, lp.z)
	CoverSystem.add(lp, Vector3.ZERO, 0.6, "log", self)
	if randf() < 0.6:
		get_tree().create_timer(dur).timeout.connect(func(): RtsExplosion.impact(self, t.xf.origin + away * 6.0))


func clear_trees(center: Vector3, radius: float) -> int:
	var n := 0
	for t in _trees_near(center, radius):
		_hide_instance(t)
		n += 1
	return n


## Called by every explosion (group "destructibles").
func take_blast(at: Vector3, radius: float) -> void:
	for t in _trees_near(at, radius * (0.75 if radius > 4.0 else 0.45)):
		if not t.tree or radius > 3.5 or randf() < 0.35:
			topple(t, at, true)
	if radius >= 3.0 and absf(at.y - get_height(at.x, at.z)) < 2.0:
		crater(at, radius * 0.35)


func _physics_process(delta: float) -> void:
	EuropeHouse.tick_debris(delta)
	CoverSystem.sync(get_tree(), delta)


func _process(delta: float) -> void:
	_deform_t -= delta
	if _deform_t <= 0.0 and not _dirty.is_empty():
		_deform_t = 0.4
		_flush_terrain()
	# tracked and wheeled vehicles push trees over
	_crush_t -= delta
	if _crush_t <= 0.0:
		_crush_t = 0.2
		for v in get_tree().get_nodes_in_group("vehicles"):
			var sp = v.get("_speed")
			if sp == null or float(sp) < 0.8:
				continue
			for t in _trees_near((v as Node3D).global_position, 3.2):
				topple(t, (v as Node3D).global_position)
	if _snowfall and _snowfall.emitting:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var target := cam.global_position + (-cam.global_basis.z) * 60.0
			_snowfall.global_position = Vector3(target.x, maxf(cam.global_position.y * 0.6, terrain_height(target.x, target.z) + 35.0), target.z)


# ------------------------------------------------------------------ village
func _build_houses() -> void:
	var list: Array = spec.get("village", [])
	if spec.is_empty():
		var f := FileAccess.open(DIR + "village.json", FileAccess.READ)
		if f == null:
			return
		list = JSON.parse_string(f.get_as_text())
	var root := Node3D.new()
	root.name = "Village"
	add_child(root)
	for h in list:
		var house := EuropeHouse.create(root, self, h)
		if house:
			houses.append(house)


## Centre of the village (towns, raid targets).
func village_center() -> Vector3:
	var c := Vector3.ZERO
	for h in houses:
		c += (h as EuropeHouse).center
	return c / maxi(1, houses.size())


## Minixarita: generator yasagan rasm yoki asl qishloq rasmi.
func minimap_texture() -> Texture2D:
	if spec.has("minimap"):
		return ImageTexture.create_from_image(spec.minimap)
	return load("res://europe/minimap.jpg")
