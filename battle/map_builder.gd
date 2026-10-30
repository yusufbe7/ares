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

	# Water and its crossings come first: the roads and everything else are
	# placed knowing where the river runs.
	_water_surface()
	_bridges(int(map_cfg.get("river", {}).get("bridges", 0)))
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
	_bushes(int(props.get("bushes", 0)))
	_hay_bales(int(props.get("hay", 0)))
	if int(props.get("rail", 0)) > 0:
		_railway()
	_power_line(int(props.get("poles", 0)))
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

## Dirt tracks that wind. A ruler-straight strip across a field reads as a
## placeholder; a track that bends around the ground reads as a road people
## actually wore into it. Only a city gets a straight grid, because a city is
## laid out rather than worn.
func _roads(count: int, map_id: String) -> void:
	var road_color := _weathered(_season_color("road", Color(0.3, 0.29, 0.27)), 0.7)
	var width := 7.0
	if map_id == "city":
		width = 12.0
	elif map_id == "military_base":
		width = 14.0
	var half := terrain.map_size * 0.5
	for i in range(count):
		var horizontal: bool = i % 2 == 0
		if map_id == "city" or map_id == "military_base":
			var lanes := maxi(2, count)
			var step := terrain.map_size / float(lanes + 1)
			var offset := -half + step * float(i + 1)
			_straight_road(horizontal, offset, width, road_color)
			continue
		_winding_road(horizontal, rng.randf_range(-0.34, 0.34) * terrain.map_size,
			width, road_color)

func _straight_road(horizontal: bool, offset: float, width: float, color: Color) -> void:
	var half := terrain.map_size * 0.5
	var a := Vector2(-half, offset) if horizontal else Vector2(offset, -half)
	var b := Vector2(half, offset) if horizontal else Vector2(offset, half)
	_road_ribbon(PackedVector2Array([a, b]), width, color)
	battle.roads.append({"horizontal": horizontal, "offset": offset, "width": width})

func _winding_road(horizontal: bool, offset: float, width: float, color: Color) -> void:
	var half := terrain.map_size * 0.5
	var points := PackedVector2Array()
	var steps := 9
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var along := lerpf(-half - 10.0, half + 10.0, t)
		# A slow sine plus noise: the track drifts instead of zig-zagging.
		var drift := sin(t * PI * rng.randf_range(1.2, 2.4) + rng.randf_range(0.0, TAU)) * 42.0
		drift += (rng.randf() - 0.5) * 14.0
		var across := clampf(offset + drift, -half + width, half - width)
		points.append(Vector2(along, across) if horizontal else Vector2(across, along))
	_road_ribbon(points, width, color)
	battle.roads.append({"horizontal": horizontal, "offset": offset, "width": width})

## Lays a ribbon of quads that follows the ground, so the track climbs and dips
## with the terrain instead of floating over it.
func _road_ribbon(points: PackedVector2Array, width: float, color: Color) -> void:
	if points.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w := width * 0.5
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var dir := (b - a)
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var side := Vector2(-dir.y, dir.x) * half_w
		# Split each span so the ribbon bends over hills rather than cutting in.
		var spans := maxi(1, int(a.distance_to(b) / 8.0))
		for k in range(spans):
			var t0 := float(k) / float(spans)
			var t1 := float(k + 1) / float(spans)
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var v0 := _road_point(p0 + side)
			var v1 := _road_point(p0 - side)
			var v2 := _road_point(p1 - side)
			var v3 := _road_point(p1 + side)
			for v: Vector3 in [v0, v1, v2, v0, v2, v3]:
				st.set_uv(Vector2(v.x, v.z) * 0.06)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle.add_child(mi)

func _road_point(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y) + 0.14, p.y)

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

## Low clay-and-stone farm buildings with a few outbuildings around them,
## rather than one uniform house repeated across the field.
func _houses(count: int) -> void:
	var walls := [Color(0.76, 0.66, 0.50), Color(0.70, 0.60, 0.45), Color(0.82, 0.74, 0.58)]
	var roofs := [Color(0.46, 0.30, 0.20), Color(0.34, 0.30, 0.24), Color(0.52, 0.36, 0.24)]
	var placed: Array = []
	for i in range(count):
		var p := _scatter(60.0, 22.0, placed)
		placed.append(p)
		var size := Vector3(rng.randf_range(6.5, 10.0), rng.randf_range(3.0, 4.2), rng.randf_range(6.0, 9.0))
		# Half of them get a shed or a wall stub beside the main building.
		if rng.randf() < 0.5:
			var off := Vector3(rng.randf_range(-11, 11), 0, rng.randf_range(-11, 11))
			var shed_pos := terrain.ground_point(p.x + off.x, p.z + off.z)
			if not terrain.is_in_water(shed_pos):
				_make_building(shed_pos,
					Vector3(rng.randf_range(4, 6), 2.6, rng.randf_range(3.5, 5.5)),
					_weathered(walls[rng.randi_range(0, walls.size() - 1)], 0.3),
					_weathered(roofs[rng.randi_range(0, roofs.size() - 1)], 0.8),
					rng.randf_range(0, TAU))
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

# ---------------------------------------------------------------------------
# Water, crossings and the small things that make ground read as lived-in
# ---------------------------------------------------------------------------

## The water itself: one flat ribbon of quads following the carved channel.
func _water_surface() -> void:
	var segments: Array = terrain.river_segments()
	if segments.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := terrain.water_level
	for seg in segments:
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var w: float = float(seg["width"]) * 0.92
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * w
		var p0 := Vector3(a.x + side.x, y, a.y + side.y)
		var p1 := Vector3(a.x - side.x, y, a.y - side.y)
		var p2 := Vector3(b.x - side.x, y, b.y - side.y)
		var p3 := Vector3(b.x + side.x, y, b.y + side.y)
		for v: Vector3 in [p0, p1, p2, p0, p2, p3]:
			st.set_uv(Vector2(v.x, v.z) * 0.02)
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	# Winter water reads as ice: pale, flat and opaque.
	if snow > 0.6:
		mat.albedo_color = Color(0.78, 0.85, 0.90, 1.0)
		mat.roughness = 0.55
	else:
		mat.albedo_color = Color(0.22, 0.38, 0.36, 0.78)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.12
		mat.metallic = 0.25
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle.add_child(mi)

## Stone crossings. Each one is a deck the troops actually walk on plus the
## arch and parapets that make it read as a bridge from above.
func _bridges(count: int) -> void:
	var segments: Array = terrain.river_segments()
	if count <= 0 or segments.is_empty():
		return
	var stone := _weathered(Color(0.58, 0.56, 0.50), 0.5)
	for i in range(count):
		var seg: Dictionary = segments[(i * maxi(1, segments.size() / maxi(count, 1))) % segments.size()]
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var centre: Vector2 = a.lerp(b, 0.5)
		# Keep the crossing on the map, not out past the edge.
		var limit := terrain.map_size * 0.38
		centre.x = clampf(centre.x, -limit, limit)
		centre.y = clampf(centre.y, -limit, limit)
		var along := (b - a).normalized()
		var across := Vector2(-along.y, along.x)
		var span: float = float(seg["width"]) * 2.6
		var deck_width := 11.0
		var yaw := atan2(across.y, across.x)
		var deck_y := terrain.add_bridge(centre, span, deck_width, yaw)
		battle.bridge_points.append({"pos": Vector3(centre.x, deck_y, centre.y),
			"half": span * 0.5, "dir": Vector3(across.x, 0, across.y)})

		var world_yaw := atan2(across.x, across.y)
		var centre3 := Vector3(centre.x, deck_y, centre.y)
		# Deck.
		_box(centre3 - Vector3(0, 0.45, 0), Vector3(deck_width, 0.9, span), stone,
			world_yaw, false)
		# Parapets, which double as cover for whoever holds the crossing.
		for edge: float in [-1.0, 1.0]:
			var side_dir := Vector3(along.x, 0, along.y).normalized()
			var wall_pos := centre3 + side_dir * edge * (deck_width * 0.5) + Vector3(0, 0.75, 0)
			_box(wall_pos, Vector3(0.6, 1.5, span), stone, world_yaw, false)
			cover.add_slot(wall_pos, side_dir * edge, 0.7, "parapet")
		# Piers under the deck, so the span does not float.
		for t: float in [-0.28, 0.28]:
			var pier := centre3 + Vector3(across.x, 0, across.y) * span * t
			_box(Vector3(pier.x, terrain.water_level + 1.0, pier.z),
				Vector3(deck_width * 0.8, (deck_y - terrain.water_level) * 1.2, 2.4),
				stone.darkened(0.15), world_yaw, false)

## Round bales: bright, chest-high and exactly the kind of thing infantry ends
## up fighting around on farmland.
func _hay_bales(count: int) -> void:
	if count <= 0:
		return
	var color := _weathered(Color(0.82, 0.70, 0.30), 0.55)
	for i in range(count):
		var p := terrain.random_point(rng, 30.0)
		var clusters := rng.randi_range(1, 3)
		for k in range(clusters):
			var off := Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5))
			var at := terrain.ground_point(p.x + off.x, p.z + off.z)
			if terrain.is_in_water(at):
				continue
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.25
			cm.bottom_radius = 1.25
			cm.height = 1.9
			mi.mesh = cm
			mi.material_override = _material(color, 1.0)
			battle.add_child(mi)
			mi.position = at + Vector3(0, 0.95, 0)
			mi.rotation = Vector3(PI * 0.5, rng.randf_range(0, TAU), 0)
			cover.add_rock(at, 1.5)

## Low scrub. It does not stop a bullet, but it breaks up the ground and gives
## prone infantry something to hide in.
func _bushes(count: int) -> void:
	if count <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bush := SphereMesh.new()
	bush.radius = 1.0
	bush.height = 1.3
	mm.mesh = bush
	mm.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var canopy := _season_color("canopy", Color(0.2, 0.36, 0.18))
	node.material_override = _material(_weathered(canopy.darkened(0.15), 0.6), 1.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle.add_child(node)
	for i in range(count):
		var p := terrain.random_point(rng, 10.0)
		var s := rng.randf_range(0.5, 1.5)
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s * 0.7, s)),
			p + Vector3(0, 0.4 * s, 0)))
		if s > 1.2:
			cover.add_slot(p, Vector3(cos(rng.randf_range(0, TAU)), 0, sin(rng.randf_range(0, TAU))),
				0.22, "bush")

## A single line of track across the map: sleepers, two rails, and a bank that
## reads from the air.
func _railway() -> void:
	var yaw := rng.randf_range(0, TAU)
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	var side := Vector3(dir.z, 0, -dir.x)
	var offset := rng.randf_range(-0.3, 0.3) * terrain.map_size
	var origin := side * offset
	var length := terrain.map_size
	var sleepers := int(length / 3.0)
	var wood := _weathered(Color(0.26, 0.21, 0.16), 0.5)
	var steel := _weathered(Color(0.42, 0.40, 0.38), 0.3)

	var sleeper_mm := MultiMesh.new()
	sleeper_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := BoxMesh.new()
	sm.size = Vector3(4.2, 0.22, 0.9)
	sleeper_mm.mesh = sm
	sleeper_mm.instance_count = sleepers
	var sleeper_node := MultiMeshInstance3D.new()
	sleeper_node.multimesh = sleeper_mm
	sleeper_node.material_override = _material(wood)
	sleeper_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	battle.add_child(sleeper_node)

	for i in range(sleepers):
		var t := (float(i) / float(sleepers) - 0.5) * length
		var at := origin + dir * t
		var ground := terrain.ground_point(at.x, at.z)
		sleeper_mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, yaw), ground + Vector3(0, 0.12, 0)))
	for rail_side: float in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.18, length)
		rail.mesh = bm
		rail.material_override = _material(steel, 0.5)
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		battle.add_child(rail)
		var mid := origin + side * rail_side * 1.5
		rail.position = terrain.ground_point(mid.x, mid.z) + Vector3(0, 0.3, 0)
		rail.rotation.y = yaw

## Power poles with a sagging wire between them. Pure scenery, but it is what
## makes an empty field look like somewhere people live.
func _power_line(count: int) -> void:
	if count <= 0:
		return
	var yaw := rng.randf_range(0, TAU)
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	var offset := Vector3(cos(yaw), 0, -sin(yaw)) * rng.randf_range(-0.3, 0.3) * terrain.map_size
	var wood := _weathered(Color(0.30, 0.24, 0.18), 0.4)
	var spacing := terrain.map_size / float(count)
	var tops: Array = []
	for i in range(count):
		var t := (float(i) - float(count) * 0.5) * spacing
		var at := offset + dir * t
		var ground := terrain.ground_point(at.x, at.z)
		if terrain.is_in_water(ground):
			tops.append(null)
			continue
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.22
		cm.height = 8.5
		pole.mesh = cm
		pole.material_override = _material(wood)
		battle.add_child(pole)
		pole.position = ground + Vector3(0, 4.25, 0)
		var cross := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 0.16, 0.16)
		cross.mesh = bm
		cross.material_override = _material(wood)
		battle.add_child(cross)
		cross.position = ground + Vector3(0, 7.6, 0)
		cross.rotation.y = yaw
		tops.append(ground + Vector3(0, 7.6, 0))
	_wires(tops)

func _wires(tops: Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(tops.size() - 1):
		if tops[i] == null or tops[i + 1] == null:
			continue
		var a: Vector3 = tops[i]
		var b: Vector3 = tops[i + 1]
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		# A few points with a sag, so the wire hangs instead of being a ruler.
		for k in range(7):
			var t := float(k) / 6.0
			var p := a.lerp(b, t)
			p.y -= sin(t * PI) * 0.9
			im.surface_add_vertex(p - a)
		im.surface_end()
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		battle.add_child(mi)
		mi.position = a
