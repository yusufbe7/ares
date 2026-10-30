class_name Battle
extends Node3D
## The 3D battlefield. Builds the map from the battle config, spawns both
## armies, runs combat, and reports the result back to the global map.

var cfg: Dictionary = {}
var terrain: BattleTerrain
var cover: CoverSystem
var director: BattleDirector
var ai_commanders: Array = []

var units: Array = []
var buildings: Array = []
var trees: Array = []            # [{node, pos, felled}]
var squads: Array = []           # Squad, index 0..4 for keys 1..5
var player_team: int = 0

var season: String = "summer"
var weather: String = "clear"
var snow: float = 0.0

var _rng := RandomNumberGenerator.new()
var _astar: AStarGrid2D
var _grid_step: float = 4.0
var _revealed: Dictionary = {}    # Vector2i -> time left, per enemy visibility
var _reveal_timer: float = 0.0
var _fog_timer: float = 0.0
var _snapshot_timer: float = 0.0
var _team_colors: Array = [Color(0.35, 0.62, 0.9), Color(0.85, 0.35, 0.3)]
var _sun: DirectionalLight3D
var _fog_env: WorldEnvironment
var _is_sim_authority: bool = true

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func start(config: Dictionary, local_team: int = 0) -> void:
	cfg = config
	player_team = local_team
	_is_sim_authority = Net.is_authority()
	season = str(cfg.get("season", "summer"))
	weather = str(cfg.get("weather", "clear"))
	snow = SeasonCycle.snow_amount(season, weather)
	_rng.seed = int(cfg.get("seed", 12345))

	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		_team_colors[i] = Color.from_string("#" + str(teams[i].get("color", "cccccc")), _team_colors[i])

	cover = CoverSystem.new()
	add_child(cover)

	terrain = BattleTerrain.new()
	add_child(terrain)
	var map_cfg: Dictionary = DB.battle_map(str(cfg.get("map", "village")))
	terrain.build(map_cfg, _rng.seed, snow)

	_build_environment()
	_build_props(map_cfg)
	_build_navigation()

	director = BattleDirector.new()
	add_child(director)
	director.setup(self, cfg)
	_place_objectives()

	for i in range(5):
		var s := Squad.new()
		s.index = i
		s.team = player_team
		squads.append(s)

	_spawn_armies()
	_setup_ai()

	EventBus.battle_started.emit(cfg)

func _build_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, 35, 0)
	_sun.light_energy = 1.1 if weather == "clear" else 0.55
	_sun.light_color = Color(1.0, 0.96, 0.9)
	if season == "winter":
		_sun.light_color = Color(0.88, 0.93, 1.0)
	_sun.shadow_enabled = Settings.graphics_quality > 0
	add_child(_sun)

	_fog_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	if season == "winter":
		sky_mat.sky_top_color = Color(0.55, 0.62, 0.72)
		sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.86)
	elif weather == "storm":
		sky_mat.sky_top_color = Color(0.2, 0.22, 0.26)
		sky_mat.sky_horizon_color = Color(0.4, 0.42, 0.45)
	else:
		sky_mat.sky_top_color = Color(0.35, 0.52, 0.78)
		sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.84)
	sky.sky_material = sky_mat
	env.sky = sky
	env.fog_enabled = weather == "fog" or weather == "snow" or weather == "storm"
	env.fog_density = 0.012 if weather == "fog" else 0.004
	env.fog_light_color = Color(0.8, 0.83, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_fog_env.environment = env
	add_child(_fog_env)

func _build_props(map_cfg: Dictionary) -> void:
	_build_roads(int(map_cfg.get("roads", 3)))
	_build_houses(int(map_cfg.get("houses", 20)))
	_build_trees(int(map_cfg.get("trees", 300)))
	_build_rocks(int(map_cfg.get("rocks", 60)))

func _build_roads(count: int) -> void:
	# Roads are flat strips: they read as a village and they tell the player
	# where vehicles will move fastest.
	for i in range(count):
		var horizontal: bool = i % 2 == 0
		var offset: float = _rng.randf_range(-0.35, 0.35) * terrain.map_size
		var strip := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(terrain.map_size, 7.0) if horizontal else Vector2(7.0, terrain.map_size)
		strip.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.29, 0.27).lerp(Color(0.85, 0.87, 0.9), snow * 0.7)
		mat.roughness = 1.0
		strip.material_override = mat
		var x: float = 0.0 if horizontal else offset
		var z: float = offset if horizontal else 0.0
		strip.position = Vector3(x, terrain.height_at(x, z) + 0.12, z)
		add_child(strip)

func _build_houses(count: int) -> void:
	var wall_colors := [Color(0.86, 0.84, 0.78), Color(0.78, 0.74, 0.66), Color(0.9, 0.88, 0.8)]
	var roof_colors := [Color(0.45, 0.17, 0.15), Color(0.2, 0.32, 0.24), Color(0.25, 0.28, 0.34)]
	var placed: Array = []
	var attempts := 0
	while placed.size() < count and attempts < count * 30:
		attempts += 1
		var p := terrain.random_point(_rng, 60.0)
		var too_close := false
		for other in placed:
			if p.distance_to(other) < 24.0:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var h := DestructibleBuilding.new()
		h.cover = cover
		h.terrain = terrain
		add_child(h)
		h.position = p
		h.rotation.y = _rng.randf_range(0, TAU)
		var size := Vector3(_rng.randf_range(8, 13), _rng.randf_range(3.6, 5.2), _rng.randf_range(7, 11))
		h.build(size, _rng.randi(), snow,
			wall_colors[_rng.randi_range(0, wall_colors.size() - 1)],
			roof_colors[_rng.randi_range(0, roof_colors.size() - 1)])
		cover.add_building(p, size, h.rotation.y)
		buildings.append(h)

func _build_trees(count: int) -> void:
	# One multimesh for the whole forest: thousands of trunks at one draw call.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.34
	trunk.height = 6.0
	mm.mesh = trunk
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.2, 0.14)
	mmi.material_override = mat
	add_child(mmi)

	var canopy_mm := MultiMesh.new()
	canopy_mm.transform_format = MultiMesh.TRANSFORM_3D
	var leaf := SphereMesh.new()
	leaf.radius = 2.6
	leaf.height = 5.0
	canopy_mm.mesh = leaf
	canopy_mm.instance_count = count
	var canopy := MultiMeshInstance3D.new()
	canopy.multimesh = canopy_mm
	var cmat := StandardMaterial3D.new()
	if season == "winter":
		cmat.albedo_color = Color(0.72, 0.76, 0.78)
	elif season == "autumn":
		cmat.albedo_color = Color(0.6, 0.42, 0.18)
	else:
		cmat.albedo_color = Color(0.18, 0.36, 0.16)
	canopy.material_override = cmat
	add_child(canopy)

	for i in range(count):
		var p := terrain.random_point(_rng, 15.0)
		var t := Transform3D(Basis(Vector3.UP, _rng.randf_range(0, TAU)).scaled(
			Vector3.ONE * _rng.randf_range(0.8, 1.3)), p + Vector3(0, 3.0, 0))
		mm.set_instance_transform(i, t)
		canopy_mm.set_instance_transform(i, Transform3D(t.basis, p + Vector3(0, 6.2, 0)))
		cover.add_tree(p)
		trees.append({"pos": p, "index": i, "felled": false, "mm": mm, "canopy": canopy_mm})

func _build_rocks(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var rock := SphereMesh.new()
	rock.radius = 1.2
	rock.height = 1.8
	mm.mesh = rock
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.41, 0.4).lerp(Color(0.9, 0.92, 0.95), snow * 0.5)
	mmi.material_override = mat
	add_child(mmi)
	for i in range(count):
		var p := terrain.random_point(_rng, 20.0)
		var s := _rng.randf_range(0.7, 2.0)
		mm.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0, TAU)).scaled(Vector3.ONE * s), p))
		cover.add_rock(p, 1.2 * s)

## A coarse grid over the map. Units path on it, which keeps routing cheap
## enough to run a few hundred of them at once.
func _build_navigation() -> void:
	_astar = AStarGrid2D.new()
	var cells := int(terrain.map_size / _grid_step)
	_astar.region = Rect2i(0, 0, cells, cells)
	_astar.cell_size = Vector2(_grid_step, _grid_step)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()
	for h in buildings:
		var half := Vector2(h.dims.x, h.dims.z) * 0.5
		var c := _world_to_cell(h.global_position)
		var r := int(ceil(maxf(half.x, half.y) / _grid_step))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var cell := Vector2i(c.x + dx, c.y + dz)
				if _astar.is_in_boundsv(cell):
					_astar.set_point_solid(cell, true)

func _world_to_cell(pos: Vector3) -> Vector2i:
	var half := terrain.map_size * 0.5
	return Vector2i(int((pos.x + half) / _grid_step), int((pos.z + half) / _grid_step))

func _cell_to_world(cell: Vector2i) -> Vector3:
	var half := terrain.map_size * 0.5
	var x := float(cell.x) * _grid_step - half + _grid_step * 0.5
	var z := float(cell.y) * _grid_step - half + _grid_step * 0.5
	return Vector3(x, terrain.height_at(x, z), z)

func find_path(from: Vector3, to: Vector3) -> Array:
	if _astar == null:
		return [to]
	var a := _world_to_cell(from)
	var b := _world_to_cell(to)
	if not _astar.is_in_boundsv(a) or not _astar.is_in_boundsv(b):
		return [to]
	if _astar.is_point_solid(b):
		b = _nearest_free(b)
	var cells := _astar.get_id_path(a, b)
	var out: Array = []
	for c in cells:
		out.append(_cell_to_world(c))
	if out.is_empty():
		out.append(to)
	else:
		out[out.size() - 1] = to
	return out

func _nearest_free(cell: Vector2i) -> Vector2i:
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var c := Vector2i(cell.x + dx, cell.y + dz)
				if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
					return c
	return cell

# ---------------------------------------------------------------------------
# Objectives and spawning
# ---------------------------------------------------------------------------

func _place_objectives() -> void:
	var half := terrain.map_size * 0.3
	director.add_point("A", "Chorrraha", terrain.ground_point(-half, 0.0), 0)
	director.add_point("B", "Qishloq", terrain.ground_point(0.0, 0.0), -1)
	director.add_point("C", "Sharqiy ferma", terrain.ground_point(half, 0.0), 1)
	for p in director.points:
		var marker := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = p.radius
		cm.bottom_radius = p.radius
		cm.height = 0.2
		marker.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p.color_for_owner(_team_colors)
		mat.albedo_color.a = 0.22
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mat
		marker.position = p.position + Vector3(0, 0.3, 0)
		add_child(marker)
		p.marker = marker

func spawn_point_for(team: int) -> Vector3:
	var half := terrain.map_size * 0.42
	var z: float = half if team == 0 else -half
	var x: float = _rng.randf_range(-half * 0.5, half * 0.5)
	return terrain.ground_point(x, z)

func _spawn_armies() -> void:
	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		var roster: Dictionary = teams[i].get("roster", {})
		var base := spawn_point_for(i)
		var n := 0
		for uid in roster.keys():
			for k in range(int(roster[uid])):
				var offset := Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-20, 20))
				spawn_unit(i, str(uid), terrain.clamp_to_map(base + offset))
				n += 1
				if n > 120:
					break      # keep the live unit count sane on big stacks
	_auto_group_player_units()

func _auto_group_player_units() -> void:
	# Pre-sorted groups, so the player starts with something to command rather
	# than a single blob: 1 infantry, 2 armour, 3 guns, 4 recon, 5 reserve.
	for u in units_of_team(player_team):
		match str(u.data.get("role", "line")):
			"line", "suppression": squads[0].add(u)
			"armor", "transport": squads[1].add(u)
			"artillery": squads[2].add(u)
			"recon", "gunship": squads[3].add(u)
			_: squads[4].add(u)

func spawn_unit(team: int, uid: String, pos: Vector3) -> BattleUnit:
	var info: Dictionary = DB.unit(uid)
	if info.is_empty():
		return null
	var u: BattleUnit
	match str(info.get("class", "infantry")):
		"vehicle": u = VehicleUnit.new()
		"aircraft": u = AircraftUnit.new()
		_: u = Infantry.new()
	add_child(u)
	u.setup(self, team, uid, pos)
	u.position.y = terrain.height_at(pos.x, pos.z) + u.ground_offset()
	units.append(u)
	EventBus.unit_spawned.emit(u)
	return u

## The reinforcement wave: five men from the friendly map edge, who then walk
## to the nearest point that is not ours yet.
func spawn_reinforcement_squad(team: int) -> Array:
	var made: Array = []
	var base := spawn_point_for(team)
	if not director.spend_tickets(team, 5):
		return made
	for i in range(5):
		var u := spawn_unit(team, "inf_rifle", terrain.clamp_to_map(base + Vector3(i * 3.0 - 6.0, 0, 0)))
		if u != null:
			made.append(u)
	var target = _nearest_unowned_point(base, team)
	if target != null:
		for u in made:
			u.order_capture(target)
	return made

func spawn_support_vehicle(team: int, uid: String) -> BattleUnit:
	var base := spawn_point_for(team)
	var u := spawn_unit(team, uid, base)
	if u != null:
		var target = _nearest_unowned_point(base, team)
		if target != null:
			u.order_move(target.position)
	return u

func _nearest_unowned_point(from: Vector3, team: int):
	var best = null
	var best_d := INF
	for p in director.points:
		if p.owner_team == team:
			continue
		var d: float = from.distance_to(p.position)
		if d < best_d:
			best_d = d
			best = p
	return best

func _setup_ai() -> void:
	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		if i == player_team:
			continue
		if not bool(teams[i].get("ai", true)):
			continue
		var ai := BattleAI.new()
		add_child(ai)
		ai.setup(self, i, int(cfg.get("seed", 1)), 0.5 + 0.1 * float(i))
		ai_commanders.append(ai)

# ---------------------------------------------------------------------------
# Queries used by units
# ---------------------------------------------------------------------------

func team_color(team: int) -> Color:
	return _team_colors[clampi(team, 0, 1)]

func units_of_team(team: int) -> Array:
	var out: Array = []
	for u in units:
		if is_instance_valid(u) and u.team == team and u.is_alive():
			out.append(u)
	return out

func enemies_of(team: int) -> Array:
	var out: Array = []
	for u in units:
		if is_instance_valid(u) and u.team != team and u.is_alive():
			out.append(u)
	return out

func vision_modifier() -> float:
	return float(DB.weather(weather).get("vision", 1.0)) \
		* float(DB.battle_map(str(cfg.get("map", "village"))).get("vision_mod", 1.0))

func speed_modifier() -> float:
	return float(DB.weather(weather).get("speed", 1.0))

func accuracy_modifier() -> float:
	return float(DB.weather(weather).get("accuracy", 1.0))

## Sight is blocked by the ground itself and by any building still standing in
## the way — which is what makes a village fight different from a desert one.
func has_line_of_sight(from_unit: BattleUnit, to_unit: BattleUnit) -> bool:
	var a: Vector3 = from_unit.global_position + Vector3(0, 1.3, 0)
	var b: Vector3 = to_unit.global_position + Vector3(0, 1.0, 0)
	if from_unit.is_air() or to_unit.is_air():
		return true
	var dist := a.distance_to(b)
	var steps := clampi(int(dist / 6.0), 2, 24)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if terrain.height_at(p.x, p.z) > p.y + 0.4:
			return false
		for h in buildings:
			if not is_instance_valid(h) or h.is_passable():
				continue
			var local: Vector3 = h.to_local(p)
			if absf(local.x) < h.dims.x * 0.5 and absf(local.z) < h.dims.z * 0.5 and local.y < h.dims.y:
				return false
	return true

## Which way the shooting is coming from, for a unit that has not spotted
## anyone yet but is being shot at.
func threat_direction(team: int, pos: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for u in enemies_of(team):
		var d: float = pos.distance_to(u.global_position)
		if d < 120.0:
			sum += (u.global_position - pos).normalized()
			n += 1
	if n == 0:
		return Vector3(0, 0, -1.0 if team == 0 else 1.0)
	return (sum / float(n)).normalized()

func reveal_area(center: Vector3, radius: float, team: int, seconds: float) -> void:
	if team != player_team:
		return
	var cell := Vector2i(int(center.x / 20.0), int(center.z / 20.0))
	var reach := int(ceil(radius / 20.0))
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			_revealed[Vector2i(cell.x + dx, cell.y + dz)] = seconds

func is_revealed(pos: Vector3) -> bool:
	return _revealed.has(Vector2i(int(pos.x / 20.0), int(pos.z / 20.0)))

# ---------------------------------------------------------------------------
# Weapons and effects
# ---------------------------------------------------------------------------

func spawn_tracer(from: Vector3, to: Vector3, team: int) -> void:
	if Settings.graphics_quality == 0:
		return
	var line := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(to - from)
	im.surface_end()
	line.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4) if team == 0 else Color(1.0, 0.5, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.material_override = mat
	line.position = from
	add_child(line)
	var t := get_tree().create_timer(0.06)
	t.timeout.connect(func():
		if is_instance_valid(line):
			line.queue_free())

func spawn_shell(from: Vector3, to: Vector3, team: int, damage: float, at_value: float) -> void:
	var shell := Projectile.new()
	add_child(shell)
	shell.launch(self, from, to, team, damage, at_value, 120.0, 3.0)

func spawn_rocket(from: Vector3, target: BattleUnit, team: int, damage: float) -> void:
	var rocket := Projectile.new()
	add_child(rocket)
	rocket.launch_guided(self, from, target, team, damage, 0.95, 45.0)

## Indirect fire: a red circle lands first and every soldier in it runs. The
## shells follow a few seconds later.
func call_artillery_strike(from: Vector3, target: Vector3, team: int, source) -> void:
	var marker := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 16.0
	cm.bottom_radius = 16.0
	cm.height = 0.15
	marker.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.15, 0.1, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = mat
	marker.position = terrain.ground_point(target.x, target.z) + Vector3(0, 0.25, 0)
	add_child(marker)
	# Everyone nearby runs, both sides — artillery does not read uniforms.
	for u in units:
		if is_instance_valid(u) and u.is_alive() and u.global_position.distance_to(target) < 20.0:
			var away := (u.global_position - target).normalized() * 30.0
			u.order_move(terrain.clamp_to_map(u.global_position + away))
			u.take_suppression(0.5)
	var delay := get_tree().create_timer(4.0)
	delay.timeout.connect(func():
		if is_instance_valid(marker):
			marker.queue_free()
		if not is_instance_valid(self):
			return
		for i in range(6):
			var offset := Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
			spawn_explosion(terrain.ground_point(target.x + offset.x, target.z + offset.z),
				8.0, 110.0, team, true))

func spawn_explosion(pos: Vector3, radius: float, damage: float, team: int, make_crater: bool) -> void:
	# Light, smoke and a hole in the ground.
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.light_energy = 8.0
	flash.omni_range = radius * 3.0
	flash.position = pos + Vector3(0, 2, 0)
	add_child(flash)
	var t := get_tree().create_timer(0.25)
	t.timeout.connect(func():
		if is_instance_valid(flash):
			flash.queue_free())
	if make_crater:
		terrain.add_crater(pos, radius * 0.9, radius * 0.25)
		cover.add_crater(pos, radius * 0.9)
	for u in units:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var d: float = u.global_position.distance_to(pos)
		if d > radius * 2.0:
			continue
		var falloff: float = clampf(1.0 - d / (radius * 2.0), 0.0, 1.0)
		var dir := (u.global_position - pos).normalized()
		var protection: float = cover.protection_at(u.global_position, dir) * 0.6
		if terrain.is_in_trench(u.global_position):
			protection = maxf(protection, 0.8)
		u.take_suppression(falloff * 0.9)
		u.take_damage(damage * falloff * falloff * (1.0 - protection) * u.armor_multiplier(dir, 0.5), null)
	for h in buildings:
		if is_instance_valid(h) and h.global_position.distance_to(pos) < radius * 2.5:
			h.damage(pos, radius * 1.2, 12.0)
	_fell_trees_near(pos, radius * 1.6)

## Tanks knock trees down, and a felled trunk is cover for whoever gets there.
func crush_at(pos: Vector3, radius: float, _by) -> void:
	_fell_trees_near(pos, radius)

func _fell_trees_near(pos: Vector3, radius: float) -> void:
	for t in trees:
		if bool(t["felled"]):
			continue
		var p: Vector3 = t["pos"]
		if p.distance_to(pos) > radius:
			continue
		t["felled"] = true
		var dir := (p - pos).normalized()
		if dir.length() < 0.1:
			dir = Vector3.FORWARD
		var mm: MultiMesh = t["mm"]
		var idx: int = int(t["index"])
		var fallen := Transform3D(
			Basis(Vector3(dir.z, 0, -dir.x).normalized(), PI * 0.5),
			p + Vector3(0, 0.4, 0) + dir * 2.0)
		mm.set_instance_transform(idx, fallen)
		var canopy: MultiMesh = t["canopy"]
		canopy.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ONE * 0.01), p))
		cover.add_log(p + dir * 2.0, dir)

func dig_trench(a: Vector3, b: Vector3, team: int) -> bool:
	var length := a.distance_to(b)
	var cost := length * float(DB.fortifications.get("trench", {}).get("cost_per_m", 1))
	if not director.pay(team, cost):
		return false
	terrain.dig_trench(a, b)
	cover.add_trench(a, b)
	return true

func place_fortification(kind: String, pos: Vector3, facing: Vector3, team: int) -> bool:
	var f: Dictionary = DB.fortifications.get(kind, {})
	if f.is_empty():
		return false
	if not director.pay(team, float(f.get("cost", 5))):
		return false
	match kind:
		"sandbag":
			cover.add_sandbags(pos, facing)
			_spawn_prop_box(pos, Vector3(3.0, 0.8, 1.0), Color(0.6, 0.56, 0.4), facing)
		"wire":
			_spawn_prop_box(pos, Vector3(4.0, 0.9, 0.3), Color(0.35, 0.35, 0.35), facing)
		"camo_net":
			_spawn_prop_box(pos, Vector3(6.0, 0.2, 6.0), Color(0.3, 0.38, 0.26), facing)
		"mines":
			_place_mine(pos, team, float(f.get("damage", 200)))
	return true

func _spawn_prop_box(pos: Vector3, size: Vector3, color: Color, facing: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = terrain.ground_point(pos.x, pos.z) + Vector3(0, size.y * 0.5, 0)
	mi.rotation.y = atan2(facing.x, facing.z)
	add_child(mi)

var _mines: Array = []

func _place_mine(pos: Vector3, team: int, damage: float) -> void:
	_mines.append({"pos": terrain.ground_point(pos.x, pos.z), "team": team, "damage": damage})

func _check_mines() -> void:
	for i in range(_mines.size() - 1, -1, -1):
		var m: Dictionary = _mines[i]
		for u in units:
			if not is_instance_valid(u) or not u.is_alive() or u.team == int(m["team"]) or u.is_air():
				continue
			if u.global_position.distance_to(m["pos"]) < 2.5:
				spawn_explosion(m["pos"], 5.0, float(m["damage"]), int(m["team"]), true)
				_mines.remove_at(i)
				break

# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if director == null:
		return
	units = units.filter(func(u): return is_instance_valid(u))
	if _is_sim_authority:
		for ai in ai_commanders:
			ai.tick(delta)
		director.tick(delta, units)
		_check_mines()
	_tick_reveal(delta)
	_update_point_markers()
	_fog_timer -= delta
	if _fog_timer <= 0.0:
		_fog_timer = 0.25
		_update_fog_of_war()
	if Net.state == Net.State.HOSTING:
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = 0.1
			_send_snapshot()

func _tick_reveal(delta: float) -> void:
	for key in _revealed.keys().duplicate():
		var left: float = float(_revealed[key]) - delta
		if left <= 0.0:
			_revealed.erase(key)
		else:
			_revealed[key] = left

func _update_point_markers() -> void:
	for p in director.points:
		if p.marker != null and is_instance_valid(p.marker):
			var mat: StandardMaterial3D = p.marker.material_override
			var c := p.color_for_owner(_team_colors)
			c.a = 0.4 if p.contested else 0.22
			mat.albedo_color = c

## Recon matters because enemies you have not seen are simply not drawn.
func _update_fog_of_war() -> void:
	var friendly := units_of_team(player_team)
	for u in units:
		if not is_instance_valid(u) or u.team == player_team:
			continue
		var seen := is_revealed(u.global_position)
		if not seen:
			for f in friendly:
				var sight: float = float(f.data.get("vision", 50)) * vision_modifier()
				if f.global_position.distance_to(u.global_position) < sight:
					if has_line_of_sight(f, u):
						seen = true
						break
		u.visible = seen

func on_point_captured(p: ObjectivePoint) -> void:
	var who := "Siz" if p.owner_team == player_team else "Dushman"
	GameState.notify("%s %s nuqtasini egalladi." % [who, p.id], "good" if p.owner_team == player_team else "warn")

func on_unit_died(u: BattleUnit) -> void:
	director.on_unit_died(u)
	for s in squads:
		s.remove(u)

func on_battle_finished(res: Dictionary) -> void:
	var teams: Array = cfg.get("teams", [])
	var winner_team := int(res.get("winner_team", 0))
	var losses: Array = res.get("losses", [0.3, 0.3])
	var out := {
		"battle_id": int(cfg.get("battle_id", 0)),
		"province": int(cfg.get("province", -1)),
		"winner_team": winner_team,
		"winner": str(teams[winner_team].get("nation", "")) if teams.size() > winner_team else "",
		"attacker": str(teams[0].get("nation", "")) if teams.size() > 0 else "",
		"defender": str(teams[1].get("nation", "")) if teams.size() > 1 else "",
		"attacker_losses": float(losses[0]),
		"defender_losses": float(losses[1]),
		"player_won": winner_team == player_team,
		"auto": false,
	}
	GameState.last_battle_result = out
	Net.send_battle_result(out)
	EventBus.battle_ended.emit(out)

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

func _send_snapshot() -> void:
	var arr: Array = []
	for u in units:
		if is_instance_valid(u) and u.is_alive():
			arr.append(u.snapshot())
	Net.send_battle_snapshot({"t": director.elapsed, "u": arr,
		"tickets": director.tickets, "points": _point_states()})

func _point_states() -> Array:
	var out: Array = []
	for p in director.points:
		out.append({"id": p.id, "o": p.owner_team, "p": p.progress})
	return out

func apply_snapshot(snapshot: Dictionary) -> void:
	# Clients do not simulate; they draw what the server says is there.
	var by_id: Dictionary = {}
	for u in units:
		if is_instance_valid(u):
			by_id[u.get_instance_id()] = u
	for row in snapshot.get("u", []):
		var id := int(row.get("i", 0))
		if by_id.has(id):
			by_id[id].apply_snapshot(row)
	var tick_list: Array = snapshot.get("tickets", [])
	for i in range(mini(2, tick_list.size())):
		director.tickets[i] = int(tick_list[i])
		EventBus.tickets_changed.emit(i, director.tickets[i])
	for row in snapshot.get("points", []):
		for p in director.points:
			if p.id == str(row.get("id", "")):
				p.owner_team = int(row.get("o", -1))
				p.progress = float(row.get("p", 0.0))
