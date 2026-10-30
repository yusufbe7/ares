class_name MapBuilder
extends RefCounted
## Builds the props of a battlefield. There is one geometry per map — village,
## forest, desert, city, mountain, military base — and the season only swaps
## materials, vegetation and litter on top of it. That is what makes four
## seasons cost one map instead of four.

var battle                       # Battle
var terrain: BattleTerrain
var cover: CoverSystem
var rng: RandomNumberGenerator
var season_id: String = "summer"
var weather_id: String = "clear"
var snow: float = 0.0
var wet: float = 0.0
var leaves: float = 0.0

func build(ctx, map_cfg: Dictionary, p_season: String, p_weather: String, seed_value: int) -> void:
	battle = ctx
	terrain = ctx.terrain
	cover = ctx.cover
	season_id = p_season
	weather_id = p_weather
	snow = SeasonCycle.snow_amount(p_season, p_weather)
	wet = SeasonCycle.wetness(p_season, p_weather)
	leaves = float(DB.season(p_season).get("leaves", 0.0))
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	var props: Dictionary = map_cfg.get("props", {})
	var map_id := str(map_cfg.get("id", "village"))

	_roads(int(props.get("roads", 3)), map_id)
	match map_id:
		"city":
			_city_blocks(int(props.get("blocks", 30)))
			_wrecks(int(props.get("wrecks", 10)))
		"military_base":
			_hangars(int(props.get("hangars", 8)))
			_bunkers(int(props.get("bunkers", 6)))
			_depots(int(props.get("depots", 14)))
			_houses(int(props.get("houses", 4)))
		"mountain":
			_ridges(int(props.get("ridges", 8)))
			_houses(int(props.get("houses", 8)))
		"desert":
			_houses(int(props.get("houses", 10)))
		_:
			_houses(int(props.get("houses", 20)))
	_trees(int(props.get("trees", 200)), map_id)
	_rocks(int(props.get("rocks", 60)))
	if int(props.get("logs", 0)) > 0:
		_fallen_logs(int(props["logs"]))
	if int(props.get("fences", 0)) > 0:
		_fences(int(props["fences"]))
	if leaves > 0.05:
		_leaf_litter()

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

func _season_color(key: String, fallback: Color) -> Color:
	return DB.season_color(season_id, key, fallback)

## Anything standing outside gets a little snow on it in winter and a little
## dirt on it when the ground is wet.
func _weathered(base: Color, snow_take: float = 0.5) -> Color:
	var c := base.lerp(Color(0.93, 0.95, 0.97), snow * snow_take)
	return c.darkened(wet * 0.15)

func _material(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

func _box(center: Vector3, size: Vector3, color: Color, yaw: float = 0.0,
		solid: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _material(color)
	battle.add_child(mi)
	mi.position = center
	mi.rotation.y = yaw
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.collision_layer = 1
		mi.add_child(body)
		battle.nav_obstacles.append({"pos": center, "radius": maxf(size.x, size.z) * 0.5})
	return mi

func _scatter(margin: float, min_gap: float, placed: Array, tries: int = 40) -> Vector3:
	for i in range(tries):
		var p := terrain.random_point(rng, margin)
		var ok := true
		for other in placed:
			if p.distance_to(other) < min_gap:
				ok = false
				break
		if ok:
			return p
	return terrain.random_point(rng, margin)

# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------

func _roads(count: int, map_id: String) -> void:
	var road_color := _weathered(_season_color("road", Color(0.3, 0.29, 0.27)), 0.7)
	var width := 7.0
	if map_id == "city":
		width = 12.0
	elif map_id == "military_base":
		width = 14.0
	for i in range(count):
		var horizontal: bool = i % 2 == 0
		var offset: float = rng.randf_range(-0.38, 0.38) * terrain.map_size
		if map_id == "city":
			# A grid, not random lanes: this is what makes a city read as blocks.
			var lanes := maxi(2, count / 2)
			var step := terrain.map_size / float(lanes + 1)
			offset = -terrain.map_size * 0.5 + step * float(i / 2 + 1)
		var strip := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(terrain.map_size, width) if horizontal else Vector2(width, terrain.map_size)
		strip.mesh = pm
		strip.material_override = _material(road_color, 1.0)
		var x: float = 0.0 if horizontal else offset
		var z: float = offset if horizontal else 0.0
		battle.add_child(strip)
		strip.position = Vector3(x, terrain.height_at(x, z) + 0.14, z)
		battle.roads.append({"horizontal": horizontal, "offset": offset, "width": width})

# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------

func _make_building(pos: Vector3, size: Vector3, wall: Color, roof: Color,
		yaw: float) -> DestructibleBuilding:
	var h := DestructibleBuilding.new()
	h.cover = cover
	h.terrain = terrain
	battle.add_child(h)
	h.position = pos
	h.rotation.y = yaw
	h.build(size, rng.randi(), snow, wall, roof)
	cover.add_building(pos, size, yaw)
	battle.buildings.append(h)
	return h

func _houses(count: int) -> void:
	var walls := [Color(0.86, 0.84, 0.78), Color(0.78, 0.74, 0.66), Color(0.9, 0.88, 0.8)]
	var roofs := [Color(0.45, 0.17, 0.15), Color(0.2, 0.32, 0.24), Color(0.25, 0.28, 0.34)]
	var placed: Array = []
	for i in range(count):
		var p := _scatter(60.0, 24.0, placed)
		placed.append(p)
		var size := Vector3(rng.randf_range(8, 13), rng.randf_range(3.6, 5.2), rng.randf_range(7, 11))
		_make_building(p, size,
			_weathered(walls[rng.randi_range(0, walls.size() - 1)], 0.3),
			_weathered(roofs[rng.randi_range(0, roofs.size() - 1)], 0.85),
			rng.randf_range(0, TAU))

## City: tall blocks laid out along the road grid, with gaps that become the
## alleys infantry fights through.
func _city_blocks(count: int) -> void:
	var concrete := [Color(0.62, 0.60, 0.57), Color(0.55, 0.54, 0.52), Color(0.68, 0.64, 0.58)]
	var placed: Array = []
	for i in range(count):
		var p := _scatter(50.0, 30.0, placed)
		placed.append(p)
		var storeys := rng.randi_range(2, 6)
		var size := Vector3(rng.randf_range(12, 20), float(storeys) * 3.2, rng.randf_range(12, 18))
		var wall := _weathered(concrete[rng.randi_range(0, concrete.size() - 1)], 0.2)
		var h := _make_building(p, size, wall, wall.darkened(0.25),
			snappedf(rng.randf_range(0, TAU), PI * 0.5))
		# Tall blocks take a lot more punishment before they come apart.
		h.set_meta("storeys", storeys)

func _wrecks(count: int) -> void:
	for i in range(count):
		var p := terrain.random_point(rng, 40.0)
		var mi := _box(p + Vector3(0, 0.7, 0), Vector3(3.2, 1.4, 6.6),
			_weathered(Color(0.16, 0.15, 0.14), 0.6), rng.randf_range(0, TAU))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cover.add_wreck(p)

## Military base: wide hangars, hard bunkers and stacks of crates on an apron.
func _hangars(count: int) -> void:
	var placed: Array = []
	for i in range(count):
		var p := _scatter(70.0, 42.0, placed)
		placed.append(p)
		var size := Vector3(rng.randf_range(22, 30), rng.randf_range(7, 9), rng.randf_range(14, 18))
		_make_building(p, size,
			_weathered(Color(0.46, 0.48, 0.44), 0.3),
			_weathered(Color(0.38, 0.40, 0.38), 0.7),
			snappedf(rng.randf_range(0, TAU), PI * 0.5))

func _bunkers(count: int) -> void:
	for i in range(count):
		var p := terrain.random_point(rng, 55.0)
		var yaw := rng.randf_range(0, TAU)
		_box(p + Vector3(0, 1.3, 0), Vector3(9, 2.6, 7),
			_weathered(Color(0.40, 0.41, 0.39), 0.25), yaw)
		# A bunker is the best cover on the map: thick and it faces every way.
		for k in range(6):
			var ang := TAU * float(k) / 6.0 + yaw
			var dir := Vector3(cos(ang), 0, sin(ang))
			cover.add_slot(p + dir * 5.2, dir, 0.92, "bunker")
		battle.hard_points.append({"pos": p, "radius": 6.0})

func _depots(count: int) -> void:
	for i in range(count):
		var p := terrain.random_point(rng, 45.0)
		var stacks := rng.randi_range(2, 5)
		for k in range(stacks):
			var off := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
			var size := Vector3(2.2, 2.0, 2.2)
			_box(terrain.ground_point(p.x + off.x, p.z + off.z) + Vector3(0, 1.0, 0), size,
				_weathered(Color(0.42, 0.38, 0.26), 0.5), rng.randf_range(0, TAU))
		cover.add_rock(p, 3.0)

## Mountain: long rock spines that block sight and force movement into passes.
func _ridges(count: int) -> void:
	var rock_color := _weathered(_season_color("rock", Color(0.42, 0.42, 0.40)), 0.8)
	for i in range(count):
		var p := terrain.random_point(rng, 40.0)
		var yaw := rng.randf_range(0, TAU)
		var length := rng.randf_range(26, 60)
		var segments := int(length / 8.0)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		for k in range(segments):
			var at := p + dir * (float(k) - float(segments) * 0.5) * 8.0
			var ground := terrain.ground_point(at.x, at.z)
			var height := rng.randf_range(4.0, 9.0)
			_box(ground + Vector3(0, height * 0.5, 0),
				Vector3(rng.randf_range(6, 10), height, rng.randf_range(6, 9)), rock_color,
				yaw + rng.randf_range(-0.3, 0.3))
			cover.add_rock(ground, 5.0)

func _fences(count: int) -> void:
	var wood := _weathered(Color(0.38, 0.30, 0.20), 0.6)
	for i in range(count):
		var p := terrain.random_point(rng, 40.0)
		var yaw := rng.randf_range(0, TAU)
		var mi := _box(p + Vector3(0, 0.7, 0), Vector3(6.0, 1.2, 0.2), wood, yaw, false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var facing := Vector3(cos(yaw), 0, -sin(yaw))
		cover.add_slot(p + facing * 0.6, facing, 0.35, "fence")

# ---------------------------------------------------------------------------
# Vegetation
# ---------------------------------------------------------------------------

func _trees(count: int, map_id: String) -> void:
	if count <= 0:
		return
	var bark := _weathered(_season_color("bark", Color(0.26, 0.2, 0.14)), 0.4)
	var canopy := _season_color("canopy", Color(0.18, 0.36, 0.16))
	var is_bare: bool = season_id == "winter" or (season_id == "autumn" and rng.randf() < 0.4)

	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.34
	trunk.height = 6.0
	trunk_mm.mesh = trunk
	trunk_mm.instance_count = count
	var trunk_node := MultiMeshInstance3D.new()
	trunk_node.multimesh = trunk_mm
	trunk_node.material_override = _material(bark)
	battle.add_child(trunk_node)

	var canopy_mm := MultiMesh.new()
	canopy_mm.transform_format = MultiMesh.TRANSFORM_3D
	var leaf := SphereMesh.new()
	leaf.radius = 2.6
	leaf.height = 5.0
	canopy_mm.mesh = leaf
	canopy_mm.instance_count = count
	var canopy_node := MultiMeshInstance3D.new()
	canopy_node.multimesh = canopy_mm
	# In winter the canopy is a thin, pale crown of snow on bare branches.
	canopy_node.material_override = _material(_weathered(canopy, 0.9 if is_bare else 0.4))
	battle.add_child(canopy_node)

	var margin := 15.0
	var desert: bool = map_id == "desert"
	for i in range(count):
		var p := terrain.random_point(rng, margin)
		var scale := rng.randf_range(0.8, 1.3)
		if desert:
			scale *= 0.7         # palms and scrub, not forest
		var t := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * scale),
			p + Vector3(0, 3.0 * scale, 0))
		trunk_mm.set_instance_transform(i, t)
		var crown_scale := scale * (0.45 if is_bare else 1.0)
		canopy_mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, 0.0).scaled(Vector3.ONE * crown_scale), p + Vector3(0, 6.2 * scale, 0)))
		cover.add_tree(p)
		battle.trees.append({"pos": p, "index": i, "felled": false,
			"mm": trunk_mm, "canopy": canopy_mm})

func _rocks(count: int) -> void:
	if count <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var rock := SphereMesh.new()
	rock.radius = 1.2
	rock.height = 1.8
	mm.mesh = rock
	mm.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _material(_weathered(_season_color("rock", Color(0.42, 0.41, 0.4)), 0.6))
	battle.add_child(node)
	for i in range(count):
		var p := terrain.random_point(rng, 20.0)
		var s := rng.randf_range(0.7, 2.0)
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), p))
		cover.add_rock(p, 1.2 * s)
		if s > 1.4:
			battle.nav_obstacles.append({"pos": p, "radius": 1.2 * s})

func _fallen_logs(count: int) -> void:
	var bark := _weathered(_season_color("bark", Color(0.26, 0.2, 0.14)), 0.5)
	for i in range(count):
		var p := terrain.random_point(rng, 25.0)
		var yaw := rng.randf_range(0, TAU)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.4
		cm.bottom_radius = 0.45
		cm.height = rng.randf_range(5.0, 9.0)
		mi.mesh = cm
		mi.material_override = _material(bark)
		battle.add_child(mi)
		mi.position = p + Vector3(0, 0.45, 0)
		mi.rotation = Vector3(PI * 0.5, yaw, 0)
		cover.add_log(p, Vector3(sin(yaw), 0, cos(yaw)))

## Autumn ground cover: flat patches of fallen leaves. Cheap, and it is most of
## what sells the season at this camera distance.
func _leaf_litter() -> void:
	var patches := int(90.0 * leaves)
	var color := _season_color("canopy", Color(0.7, 0.45, 0.2)).darkened(0.25)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := PlaneMesh.new()
	quad.size = Vector2(9, 9)
	mm.mesh = quad
	mm.instance_count = patches
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := _material(color, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.75
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle.add_child(node)
	for i in range(patches):
		var p := terrain.random_point(rng, 10.0)
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, rng.randf_range(0, TAU)), p + Vector3(0, 0.08, 0)))
