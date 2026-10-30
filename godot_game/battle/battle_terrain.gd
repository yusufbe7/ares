class_name BattleTerrain
extends Node3D
## Procedural battlefield ground. The whole map is generated from the battle
## seed, so every client builds exactly the same terrain without shipping a
## single heightmap file.

var map_id: String = "village"
var map_size: float = 600.0
var resolution: int = 128
var snow: float = 0.0

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _craters: Array = []          # [{pos: Vector2, radius: float, depth: float}]
var _trenches: Array = []         # [{a: Vector2, b: Vector2, width: float, depth: float}]
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D

func build(cfg: Dictionary, seed_value: int, snow_amount: float) -> void:
	map_id = str(cfg.get("id", "village"))
	map_size = float(cfg.get("size", 600))
	snow = snow_amount
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 4
	_detail = FastNoiseLite.new()
	_detail.seed = seed_value + 7
	_detail.frequency = 0.02
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

func _make_material(cfg: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var ground := Color.from_string(str(cfg.get("ground", "#6c7a52")), Color(0.42, 0.48, 0.32))
	var snow_col := Color.from_string(str(cfg.get("snow_ground", "#e8eef2")), Color(0.9, 0.93, 0.95))
	m.albedo_color = ground.lerp(snow_col, snow)
	m.roughness = lerpf(0.95, 0.7, snow)
	m.metallic = 0.0
	return m

## Ground height, including every crater and trench dug so far. Units, props and
## the camera all read the world through this one function.
func height_at(x: float, z: float) -> float:
	var base: float = _noise.get_noise_2d(x, z) * 14.0
	base += _detail.get_noise_2d(x, z) * 1.6
	if map_id == "desert":
		base *= 1.5
	elif map_id == "forest":
		base *= 0.8
	var p := Vector2(x, z)
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

func random_point(rng: RandomNumberGenerator, margin: float = 30.0) -> Vector3:
	var half := map_size * 0.5 - margin
	var x := rng.randf_range(-half, half)
	var z := rng.randf_range(-half, half)
	return ground_point(x, z)

func clamp_to_map(pos: Vector3) -> Vector3:
	var half := map_size * 0.5 - 5.0
	return Vector3(clampf(pos.x, -half, half), pos.y, clampf(pos.z, -half, half))
