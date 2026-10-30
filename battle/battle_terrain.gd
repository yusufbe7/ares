class_name BattleTerrain
extends Node3D
## Procedural battlefield ground. The whole map is generated from the battle
## seed, so every client builds exactly the same terrain without shipping a
## single heightmap file.

var map_id: String = "village"
var map_size: float = 600.0
var resolution: int = 128
var snow: float = 0.0
var wet: float = 0.0
var season_id: String = "summer"
var relief: float = 1.0

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _craters: Array = []          # [{pos: Vector2, radius: float, depth: float}]
var _trenches: Array = []         # [{a: Vector2, b: Vector2, width: float, depth: float}]
var _river: Array = []            # [{a: Vector2, b: Vector2, width: float, depth: float}]
var _bridges: Array = []          # [{center: Vector2, half: Vector2, yaw: float, height: float}]
var water_level: float = -3.2
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D

func build(cfg: Dictionary, seed_value: int, p_season: String, p_weather: String) -> void:
	map_id = str(cfg.get("id", "village"))
	map_size = float(cfg.get("size", 600))
	relief = float(cfg.get("relief", 1.0))
	season_id = p_season
	snow = SeasonCycle.snow_amount(p_season, p_weather)
	wet = SeasonCycle.wetness(p_season, p_weather)
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 4
	_detail = FastNoiseLite.new()
	_detail.seed = seed_value + 7
	_detail.frequency = 0.02
	if map_id == "mountain":
		_noise.fractal_octaves = 5
		_noise.frequency = 0.0028
	_generate_river(cfg, seed_value)
	_build_mesh(cfg)

func _build_mesh(cfg: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := map_size / float(resolution)
	var half := map_size * 0.5
	for z in range(resolution):
		for x in range(resolution):
			var x0 := -half + float(x) * step
			var z0 := -half + float(z) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x1, height_at(x1, z0), z0)
			var p11 := Vector3(x1, height_at(x1, z1), z1)
			var p01 := Vector3(x0, height_at(x0, z1), z1)
			_add_tri(st, p00, p11, p10)
			_add_tri(st, p00, p01, p11)
	st.generate_normals()
	var mesh := st.commit()

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.material_override = _make_material(cfg)
	add_child(_mesh_instance)

	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hm := ConcavePolygonShape3D.new()
	hm.set_faces(mesh.get_faces())
	shape.shape = hm
	_body.add_child(shape)
	_body.collision_layer = 1
	add_child(_body)

func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var uv_scale := 0.08
	st.set_uv(Vector2(a.x, a.z) * uv_scale)
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z) * uv_scale)
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z) * uv_scale)
	st.add_vertex(c)

## The ground colour comes from the season, not the map: the same village is
## green in spring, bleached in summer, brown in autumn and white in winter.
func _make_material(_cfg: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var ground := DB.season_color(season_id, "ground", Color(0.42, 0.48, 0.32))
	var alt := DB.season_color(season_id, "ground_alt", ground.darkened(0.15))
	var base := ground.lerp(alt, 0.35)
	match map_id:
		"desert":
			base = base.lerp(Color(0.78, 0.68, 0.45), 0.55)
		"city":
			base = base.lerp(Color(0.34, 0.33, 0.32), 0.5)
		"military_base":
			base = base.lerp(Color(0.40, 0.40, 0.38), 0.35)
		"mountain":
			base = base.lerp(DB.season_color(season_id, "rock", Color(0.42, 0.42, 0.4)), 0.35)
		_:
			pass
	m.albedo_color = base
	# Wet ground is darker and shinier; snow is bright and flat.
	m.albedo_color = m.albedo_color.darkened(wet * 0.22)
	m.roughness = clampf(1.0 - wet * 0.45, 0.35, 1.0)
	m.metallic = 0.0
	m.metallic_specular = lerpf(0.3, 0.6, wet)
	return m

## Ground height, including every crater and trench dug so far. Units, props and
## the camera all read the world through this one function.
func height_at(x: float, z: float) -> float:
	var base: float = _noise.get_noise_2d(x, z) * 14.0 * relief
	base += _detail.get_noise_2d(x, z) * 1.6 * clampf(relief, 0.3, 1.5)
	if map_id == "mountain":
		# Ridges: squaring the noise turns rolling hills into real spines.
		var ridge: float = 1.0 - absf(_noise.get_noise_2d(x * 0.6, z * 0.6))
		base += ridge * ridge * 26.0
	var p := Vector2(x, z)
	# A bridge deck overrides everything under it, so troops cross over the
	# water instead of walking along the riverbed.
	for b in _bridges:
		if _inside_rotated(p, b["center"], b["half"], float(b["yaw"])):
			return float(b["height"])
	# The river channel: a wide, smooth cut with sloped banks.
	for seg in _river:
		var d: float = _distance_to_segment(p, seg["a"], seg["b"])
		var w: float = float(seg["width"])
		if d < w:
			var t: float = 1.0 - d / w
			base -= float(seg["depth"]) * smoothstep(0.0, 1.0, t)
	for c in _craters:
		var d: float = p.distance_to(c["pos"])
		var r: float = float(c["radius"])
		if d < r:
			var t: float = 1.0 - d / r
			base -= float(c["depth"]) * t * t
	for t_data in _trenches:
		var d2 := _distance_to_segment(p, t_data["a"], t_data["b"])
		var w: float = float(t_data["width"])
		if d2 < w:
			var k: float = 1.0 - d2 / w
			base -= float(t_data["depth"]) * clampf(k * 2.0, 0.0, 1.0)
	return base

static func _inside_rotated(p: Vector2, center: Vector2, half: Vector2, yaw: float) -> bool:
	var local := (p - center).rotated(-yaw)
	return absf(local.x) <= half.x and absf(local.y) <= half.y

static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)

func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

## A shell landing leaves a hole that is cover from then on. Only the patch
## around the hit is rebuilt, never the whole map.
func add_crater(pos: Vector3, radius: float, depth: float) -> void:
	_craters.append({"pos": Vector2(pos.x, pos.z), "radius": radius, "depth": depth})
	if _craters.size() > 160:
		_craters.remove_at(0)
	_rebuild_patch(Vector2(pos.x, pos.z), radius + 6.0)

func dig_trench(a: Vector3, b: Vector3, width: float = 2.2, depth: float = 1.8) -> void:
	_trenches.append({"a": Vector2(a.x, a.z), "b": Vector2(b.x, b.z), "width": width, "depth": depth})
	var mid := (Vector2(a.x, a.z) + Vector2(b.x, b.z)) * 0.5
	_rebuild_patch(mid, Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) * 0.5 + width + 4.0)

func trenches() -> Array:
	return _trenches

## Rivers are part of the map description, so the channel is cut before the
## mesh is generated and the water is really in the ground, not painted on it.
func _generate_river(cfg: Dictionary, seed_value: int) -> void:
	var river: Dictionary = cfg.get("river", {})
	if river.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5521
	var half := map_size * 0.5
	var bends := maxi(1, int(river.get("bends", 2)))
	var points := PackedVector2Array()
	# A river runs corner to corner with a few bends, never straight.
	var start := Vector2(-half - 20.0, rng.randf_range(-half * 0.5, half * 0.2))
	var finish := Vector2(half + 20.0, rng.randf_range(-half * 0.2, half * 0.6))
	points.append(start)
	for i in range(bends):
		var t: float = float(i + 1) / float(bends + 1)
		var mid := start.lerp(finish, t)
		mid += Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-90.0, 90.0))
		points.append(mid)
	points.append(finish)
	carve_river(points, float(river.get("width", 22)), float(river.get("depth", 6)))

## Cuts a river along a path. Called before the mesh is built, so the channel
## is part of the terrain rather than something painted on top of it.
func carve_river(points: PackedVector2Array, width: float, depth: float) -> void:
	_river.clear()
	for i in range(points.size() - 1):
		_river.append({"a": points[i], "b": points[i + 1], "width": width, "depth": depth})
	water_level = -depth * 0.55

func river_segments() -> Array:
	return _river

## Lays a bridge deck over the water at this point on the path.
func add_bridge(center: Vector2, length: float, width: float, yaw: float) -> float:
	var deck := height_at(center.x + cos(yaw) * length, center.y + sin(yaw) * length)
	deck = maxf(deck, water_level + 3.2)
	_bridges.append({"center": center, "half": Vector2(length * 0.5, width * 0.5),
		"yaw": yaw, "height": deck})
	return deck

func bridges() -> Array:
	return _bridges

func is_on_bridge(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	for b in _bridges:
		if _inside_rotated(p, b["center"], b["half"], float(b["yaw"])):
			return true
	return false

## True where the ground is under water: impassable, and nothing is built there.
func is_in_water(pos: Vector3) -> bool:
	if is_on_bridge(pos):
		return false
	return height_at(pos.x, pos.z) < water_level

func craters() -> Array:
	return _craters

func is_in_trench(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	for t_data in _trenches:
		if _distance_to_segment(p, t_data["a"], t_data["b"]) < float(t_data["width"]):
			return true
	return false

## Rebuilds the terrain mesh. The patch argument is kept so that the cost of a
## single shell stays bounded on bigger maps; for the current resolution the
## whole surface is cheap enough to re-emit in one go.
func _rebuild_patch(_center: Vector2, _radius: float) -> void:
	if _mesh_instance == null:
		return
	var cfg: Dictionary = DB.battle_map(map_id)
	var old_body := _body
	var old_mesh := _mesh_instance
	_build_mesh(cfg)
	if old_body != null:
		old_body.queue_free()
	if old_mesh != null:
		old_mesh.queue_free()

## A point on dry land. Props and spawns use this so nothing ends up in the
## river.
func random_point(rng: RandomNumberGenerator, margin: float = 30.0) -> Vector3:
	var half := map_size * 0.5 - margin
	for i in range(24):
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var p := ground_point(x, z)
		if not is_in_water(p):
			return p
	return ground_point(rng.randf_range(-half, half), rng.randf_range(-half, half))

func clamp_to_map(pos: Vector3) -> Vector3:
	var half := map_size * 0.5 - 5.0
	return Vector3(clampf(pos.x, -half, half), pos.y, clampf(pos.z, -half, half))
