class_name Battle
extends Node3D
## The 3D battlefield. Builds the map from the battle config, spawns both
## armies, runs combat, and reports the result back to the global map.

## Hard ceiling on live units per side, so a huge custom roster cannot drag
## the frame rate down to nothing.
const MAX_UNITS_PER_TEAM := 160

var cfg: Dictionary = {}
var terrain: BattleTerrain
var cover: CoverSystem
var director: BattleDirector
var ai_commanders: Array = []

var units: Array = []
var buildings: Array = []
var trees: Array = []            # [{pos, index, felled, mm, canopy}]
var roads: Array = []            # [{horizontal, offset, width}]
var hard_points: Array = []      # bunkers and other prepared positions
var nav_obstacles: Array = []    # [{pos, radius}] props that block movement
var wounded_units: Array = []    # men down and waiting for somebody to come
var bridge_points: Array = []    # [{pos, half, dir}] the crossings over the river
var _tracks_mm: MultiMesh = null
var _track_next: int = 0
var _trail_mm: MultiMesh = null
var _trail_next: int = 0
var _trail_age: Array = []
var objectives: Array = []       # per team: the thing a "destroy" match targets
var stats: BattleStats = null
var squads: Array = []           # Squad, index 0..4 for keys 1..5
var player_team: int = 0

var season: String = "summer"
var weather: String = "clear"
var victory_mode: String = "capture"
var difficulty: String = "normal"
var sandbox: bool = false
var snow: float = 0.0

var _rng := RandomNumberGenerator.new()
var _astar: AStarGrid2D
var _grid_step: float = 4.0
var _revealed: Dictionary = {}    # Vector2i -> time left, per enemy visibility
var _reveal_timer: float = 0.0
var _fog_timer: float = 0.0
var _rescue_timer: float = 0.0
var _team_colors: Array = [Color(0.35, 0.62, 0.9), Color(0.85, 0.35, 0.3)]
## Difficulty shows up as how well the AI side shoots, not as free damage.
var _team_accuracy: Array = [1.0, 1.0]
var _sun: DirectionalLight3D
var _fog_env: WorldEnvironment
var _weather_particles: GPUParticles3D = null

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func start(config: Dictionary, local_team: int = 0) -> void:
	cfg = config
	player_team = local_team
	cfg["player_team"] = local_team
	season = str(cfg.get("season", "summer"))
	weather = str(cfg.get("weather", "clear"))
	victory_mode = str(cfg.get("victory_mode", "capture"))
	difficulty = str(cfg.get("difficulty", "normal"))
	sandbox = bool(cfg.get("sandbox", false))
	snow = SeasonCycle.snow_amount(season, weather)
	_rng.seed = int(cfg.get("seed", 12345))

	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		_team_colors[i] = Color.from_string("#" + str(teams[i].get("color", "cccccc")), _team_colors[i])

	cover = CoverSystem.new()
	add_child(cover)

	terrain = BattleTerrain.new()
	add_child(terrain)
	Radio.reset()
	var map_cfg: Dictionary = DB.battle_map(str(cfg.get("map", "village")))
	terrain.build(map_cfg, _rng.seed, season, weather)

	_build_environment()
	var builder := MapBuilder.new()
	builder.build(self, map_cfg, season, weather, _rng.seed)
	_build_navigation()

	stats = BattleStats.new()
	stats.setup(cfg)

	director = BattleDirector.new()
	add_child(director)
	director.setup(self, cfg)
	_place_objectives()
	if victory_mode == "destroy":
		_place_destroy_targets()

	for i in range(5):
		var s := Squad.new()
		s.index = i
		s.team = player_team
		squads.append(s)

	_spawn_armies()
	_setup_ai()

	EventBus.battle_started.emit(cfg)

## Sky, sun and fog all come out of the season palette, with the weather
## layered on top. Nothing here is per-map, which is why one map reskins.
func _build_environment() -> void:
	var w: Dictionary = DB.weather(weather)
	var light_mod := float(w.get("light", 1.0))

	_sun = DirectionalLight3D.new()
	# A low sun: the long shadows it throws are most of what gives the ground
	# its shape from this far out.
	_sun.rotation_degrees = Vector3(-26, 38, 0)
	_sun.light_color = DB.season_color(season, "sun", Color(1.0, 0.96, 0.9))
	_sun.light_energy = float(DB.season(season).get("sun_energy", 1.1)) * light_mod
	_sun.shadow_enabled = Settings.graphics_quality > 0 and light_mod > 0.5
	_sun.directional_shadow_max_distance = 420.0
	_sun.shadow_bias = 0.04
	add_child(_sun)

	_fog_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = DB.season_color(season, "sky_top", Color(0.35, 0.52, 0.78))
	sky_mat.sky_horizon_color = DB.season_color(season, "sky_horizon", Color(0.72, 0.78, 0.84))
	sky_mat.ground_bottom_color = DB.season_color(season, "ground_alt", Color(0.2, 0.2, 0.18))
	sky_mat.ground_horizon_color = DB.season_color(season, "ground", Color(0.3, 0.3, 0.26))
	if light_mod < 0.6:
		sky_mat.sky_top_color = sky_mat.sky_top_color.darkened(0.45)
		sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.darkened(0.3)
	sky.sky_material = sky_mat
	env.sky = sky

	var fog_density := float(DB.season(season).get("fog", 0.0)) + float(w.get("fog_add", 0.0))
	env.fog_enabled = fog_density > 0.0005
	env.fog_density = fog_density
	env.fog_light_color = DB.season_color(season, "sky_horizon", Color(0.8, 0.83, 0.86))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = clampf(light_mod, 0.4, 1.2)
	_fog_env.environment = env
	add_child(_fog_env)

	_build_weather_particles(str(w.get("particles", "none")))

## Rain, snow and blowing dust follow the camera so a single emitter covers the
## whole map without a particle in sight being wasted.
func _build_weather_particles(kind: String) -> void:
	if kind == "none" or Settings.graphics_quality == 0:
		return
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(120, 1, 120)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 4.0
	mat.gravity = Vector3(0, -9.8, 0)
	var quad := QuadMesh.new()
	var qmat := StandardMaterial3D.new()
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	match kind:
		"rain":
			mat.initial_velocity_min = 16.0
			mat.initial_velocity_max = 22.0
			quad.size = Vector2(0.03, 0.9)
			qmat.albedo_color = Color(0.68, 0.76, 0.86, 0.5)
			p.amount = 1400
			p.lifetime = 1.6
		"snow":
			mat.initial_velocity_min = 1.6
			mat.initial_velocity_max = 3.2
			mat.gravity = Vector3(1.5, -2.2, 0.8)
			quad.size = Vector2(0.16, 0.16)
			qmat.albedo_color = Color(1, 1, 1, 0.85)
			p.amount = 1200
			p.lifetime = 7.0
		"storm":
			mat.initial_velocity_min = 10.0
			mat.initial_velocity_max = 26.0
			mat.gravity = Vector3(-14.0, -9.0, 4.0)
			quad.size = Vector2(0.05, 0.7)
			qmat.albedo_color = Color(0.7, 0.72, 0.68, 0.45)
			p.amount = 1800
			p.lifetime = 1.4
	quad.material = qmat
	p.draw_pass_1 = quad
	p.position = Vector3(0, 60, 0)
	p.local_coords = false
	add_child(p)
	_weather_particles = p

## A coarse grid over the map. Units path on it, which keeps routing cheap
## enough to run a few hundred of them at once.
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
	# Deep water is impassable, so an attack has to go through a crossing.
	var cells_side := int(terrain.map_size / _grid_step)
	for cx in range(cells_side):
		for cz in range(cells_side):
			var cell := Vector2i(cx, cz)
			var world := _cell_to_world(cell)
			if terrain.is_in_water(world):
				_astar.set_point_solid(cell, true)
	for h in buildings:
		mark_solid(h.global_position, maxf(h.dims.x, h.dims.z) * 0.5)
	# Rocks, bunkers, ridges and crates block movement too, even though they
	# are not buildings.
	for o in nav_obstacles:
		mark_solid(o["pos"], float(o["radius"]))

## Blocks a patch of the navigation grid. Safe to call after the grid is built,
## which is how a command post placed late still turns into an obstacle.
func mark_solid(world_pos: Vector3, radius: float) -> void:
	if _astar == null:
		return
	var c := _world_to_cell(world_pos)
	var r := int(ceil(radius / _grid_step))
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

## What the battle is fought over depends on the mode: three points to take,
## one zone to hold, or a command post on each side to blow up.
func _place_objectives() -> void:
	var half := terrain.map_size * 0.3
	match victory_mode:
		"hold":
			var defender := director.hold_defender
			var zone := ObjectivePoint.new()
			zone.id = "HOLD"
			zone.display_name = "Mudofaa hududi"
			zone.position = terrain.ground_point(0.0, 0.0)
			zone.radius = 42.0
			zone.owner_team = defender
			zone.progress = -1.0 if defender == 0 else 1.0
			director.hold_zone = zone
			_add_point_marker(zone)
		"destroy":
			# One point in the middle, so there is still ground worth taking on
			# the way to the enemy post.
			director.add_point("B", "Markaz", terrain.ground_point(0.0, 0.0), -1)
			_add_point_marker(director.points[0])
		_:
			director.add_point("A", "Chorraha", terrain.ground_point(-half, 0.0), 0)
			director.add_point("B", "Markaz", terrain.ground_point(0.0, 0.0), -1)
			director.add_point("C", "Sharqiy ferma", terrain.ground_point(half, 0.0), 1)
			for p: ObjectivePoint in director.points:
				_add_point_marker(p)

func _add_point_marker(p: ObjectivePoint) -> void:
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
	add_child(marker)
	marker.position = p.position + Vector3(0, 0.3, 0)
	p.marker = marker

## Each side gets a command post behind its own spawn. It is registered as a
## building so shells, sight lines and attack orders all already handle it.
func _place_destroy_targets() -> void:
	objectives = [null, null]
	for team in range(2):
		var base := spawn_point_for(team)
		var inward: float = -1.0 if team == 0 else 1.0
		var pos := terrain.clamp_to_map(base + Vector3(0, 0, inward * -22.0))
		pos = terrain.ground_point(pos.x, pos.z)
		var t := ObjectiveTarget.new()
		add_child(t)
		t.setup(self, team, pos, team_color(team))
		objectives[team] = t
		buildings.append(t)
		mark_solid(pos, t.dims.x * 0.5)

## Returns the building if it is still a live target, else null. Used by units
## that must re-assert an attack order after a move order cleared it.
func objective_or_building(b):
	if b == null or not is_instance_valid(b) or b.is_passable():
		return null
	return b

func objective_for(team: int):
	if objectives.size() <= team:
		return null
	return objectives[team]

func on_objective_destroyed(target: ObjectiveTarget) -> void:
	buildings.erase(target)
	var mine: bool = target.team == player_team
	GameState.notify("Shtab yo'q qilindi: %s" % ("sizniki" if mine else "dushmanniki"),
		"bad" if mine else "good")
	director.on_objective_destroyed(target)

## A deployment point on each team's own edge, kept out of the river.
func spawn_point_for(team: int) -> Vector3:
	var half := terrain.map_size * 0.42
	var z: float = half if team == 0 else -half
	for i in range(16):
		var x: float = _rng.randf_range(-half * 0.6, half * 0.6)
		var p := terrain.ground_point(x, z)
		if not terrain.is_in_water(p):
			return p
	return terrain.ground_point(0.0, z)

func _spawn_armies() -> void:
	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		var roster: Dictionary = teams[i].get("roster", {})
		var base := spawn_point_for(i)
		var n := 0
		for uid in roster.keys():
			if n >= MAX_UNITS_PER_TEAM:
				break
			for k in range(int(roster[uid])):
				if n >= MAX_UNITS_PER_TEAM:
					break
				var offset := Vector3(_rng.randf_range(-40, 40), 0, _rng.randf_range(-20, 20))
				spawn_unit(i, str(uid), terrain.clamp_to_map(base + offset))
				n += 1
	_stage_aircraft()
	_mount_transports()
	_auto_group_player_units()

## Gunships begin the battle on the ground behind their own line.
func _stage_aircraft() -> void:
	for team in range(2):
		for u in units_of_team(team):
			if u.is_air() and u.has_method("stage_on_pad"):
				u.stage_on_pad()

## A marked circle on the ground where a helicopter sits.
func mark_landing_pad(at: Vector3) -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 9.0
	cm.bottom_radius = 9.0
	cm.height = 0.12
	pad.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.35, 0.30)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad.material_override = mat
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	pad.global_position = terrain.ground_point(at.x, at.z) + Vector3(0, 0.1, 0)

## Fills every transport with whatever infantry is standing near it.
func _mount_transports() -> void:
	for team in range(2):
		var riders: Array = []
		for u in units_of_team(team):
			if u.unit_class() == "infantry":
				riders.append(u)
		for v in units_of_team(team):
			if v.unit_class() != "vehicle" or str(v.data.get("role", "")) != "transport":
				continue
			var seats := int(v.data.get("capacity", 0))
			while seats > 0 and not riders.is_empty():
				var rider = riders.pop_back()
				if v.load_passenger(rider):
					seats -= 1

func _auto_group_player_units() -> void:
	# Pre-sorted groups, so the player starts with something to command rather
	# than a single blob: 1 infantry, 2 armour, 3 guns, 4 recon, 5 reserve.
	for u: BattleUnit in units_of_team(player_team):
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
	if stats != null:
		stats.on_spawn(team, uid)
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
	for p: ObjectivePoint in director.points:
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
		var diff: Dictionary = DB.difficulty(difficulty)
		_team_accuracy[i] = float(diff.get("accuracy", 1.0))
		var ai := BattleAI.new()
		add_child(ai)
		ai.setup(self, i, int(cfg.get("seed", 1)), diff)
		ai_commanders.append(ai)

# ---------------------------------------------------------------------------
# Queries used by units
# ---------------------------------------------------------------------------

## Vehicles leave ruts behind them. On snow or mud it is the clearest record
## of where an attack came from, so it is worth a draw call. One multimesh
## holds them all and the oldest mark is overwritten once it is full.
const MAX_TRACKS := 420

func _ensure_track_layer() -> void:
	if _tracks_mm != null:
		return
	_tracks_mm = MultiMesh.new()
	_tracks_mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := PlaneMesh.new()
	quad.size = Vector2(3.6, 4.4)
	_tracks_mm.mesh = quad
	_tracks_mm.instance_count = MAX_TRACKS
	_tracks_mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = _tracks_mm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Dark ruts on snow, a softer scuff on bare ground.
	if snow > 0.4:
		mat.albedo_color = Color(0.52, 0.55, 0.60, 0.72)
	else:
		mat.albedo_color = Color(0.26, 0.22, 0.17, 0.42)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## Shell and rocket trails: a bead of smoke every few metres, each fading on
## its own clock. A barrage then draws its own arcs across the sky, which is
## what makes indirect fire readable from this far out.
const MAX_TRAIL_PUFFS := 700
const TRAIL_LIFE := 5.0

func _ensure_trail_layer() -> void:
	if _trail_mm != null:
		return
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	_trail_mm.mesh = quad
	_trail_mm.instance_count = MAX_TRAIL_PUFFS
	_trail_mm.visible_instance_count = 0
	_trail_age.resize(MAX_TRAIL_PUFFS)
	_trail_age.fill(0.0)
	var node := MultiMeshInstance3D.new()
	node.multimesh = _trail_mm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.95, 0.95, 0.93, 0.85)
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

func leave_trail_puff(pos: Vector3, scale: float = 1.0) -> void:
	if Settings.graphics_quality == 0:
		return
	_ensure_trail_layer()
	var basis := Basis().scaled(Vector3.ONE * scale)
	_trail_mm.set_instance_transform(_trail_next, Transform3D(basis, pos))
	_trail_mm.set_instance_color(_trail_next, Color(1, 1, 1, 0.85))
	_trail_age[_trail_next] = TRAIL_LIFE
	_trail_next = (_trail_next + 1) % MAX_TRAIL_PUFFS
	_trail_mm.visible_instance_count = MAX_TRAIL_PUFFS

func _fade_trails(delta: float) -> void:
	if _trail_mm == null:
		return
	for i in range(MAX_TRAIL_PUFFS):
		var life: float = _trail_age[i]
		if life <= 0.0:
			continue
		life -= delta
		_trail_age[i] = life
		var t: float = clampf(life / TRAIL_LIFE, 0.0, 1.0)
		# The bead swells and thins as it drifts, the way smoke does.
		var xf := _trail_mm.get_instance_transform(i)
		xf.basis = Basis().scaled(Vector3.ONE * (1.0 + (1.0 - t) * 1.8))
		xf.origin.y += delta * 0.8
		_trail_mm.set_instance_transform(i, xf)
		_trail_mm.set_instance_color(i, Color(1, 1, 1, 0.85 * t))

func leave_track(pos: Vector3, yaw: float) -> void:
	if Settings.graphics_quality == 0:
		return
	_ensure_track_layer()
	if terrain.is_in_water(pos):
		return
	var ground := terrain.ground_point(pos.x, pos.z) + Vector3(0, 0.06, 0)
	_tracks_mm.set_instance_transform(_track_next, Transform3D(Basis(Vector3.UP, yaw), ground))
	_track_next = (_track_next + 1) % MAX_TRACKS
	_tracks_mm.visible_instance_count = maxi(_tracks_mm.visible_instance_count, _track_next)
	if _track_next == 0:
		_tracks_mm.visible_instance_count = MAX_TRACKS

## A vehicle body stops rounds for whoever is behind it. Checked live rather
## than published as slots, because the cover moves when the vehicle does.
func vehicle_cover_at(pos: Vector3, from_dir: Vector3) -> float:
	var incoming := from_dir.normalized()
	var best := 0.0
	for u in units:
		if not is_instance_valid(u) or u.unit_class() != "vehicle" or not u.is_alive():
			continue
		var offset: Vector3 = u.global_position - pos
		offset.y = 0.0
		var d := offset.length()
		if d > 6.0 or d < 0.2:
			continue
		# Only counts if the hull is actually between the man and the shooter.
		var align: float = offset.normalized().dot(-incoming)
		if align <= 0.35:
			continue
		best = maxf(best, 0.72 * align * clampf(1.0 - d / 6.0, 0.25, 1.0))
	return best

func team_name(team: int) -> String:
	var teams: Array = cfg.get("teams", [])
	if teams.size() > team:
		return str(teams[team].get("name", "TEAM %d" % (team + 1)))
	return "TEAM %d" % (team + 1)

func team_color(team: int) -> Color:
	return _team_colors[clampi(team, 0, 1)]

func units_of_team(team: int) -> Array:
	var out: Array = []
	for u: BattleUnit in units:
		if is_instance_valid(u) and u.team == team and u.is_alive():
			out.append(u)
	return out

func enemies_of(team: int) -> Array:
	var out: Array = []
	for u: BattleUnit in units:
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

func team_accuracy(team: int) -> float:
	return float(_team_accuracy[clampi(team, 0, 1)])

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
	for u: BattleUnit in enemies_of(team):
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
	if _rng.randf() < 0.3:
		spawn_muzzle_smoke(from, (to - from).normalized(), 0.35)
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
	get_tree().create_timer(0.06).timeout.connect(line.queue_free)

## The white cloud a gun throws when it fires. It is the single clearest sign
## of where the shooting is coming from when the camera is this far out, so it
## matters more than the round itself.
func spawn_muzzle_smoke(at: Vector3, direction: Vector3, scale: float = 1.0) -> void:
	if Settings.graphics_quality == 0:
		return
	var puff := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.2, 2.2) * scale
	puff.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.92, 0.92, 0.90, 0.75)
	puff.material_override = mat
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puff)
	puff.global_position = at + direction.normalized() * 0.8

	# It blooms forward and thins out, which is what reads from above.
	var grow := create_tween()
	grow.set_parallel(true)
	grow.tween_property(puff, "scale", Vector3.ONE * (3.4 * scale), 0.9)
	grow.tween_property(puff, "global_position",
		puff.global_position + direction.normalized() * 3.5 * scale + Vector3(0, 1.2, 0), 0.9)
	grow.tween_property(mat, "albedo_color", Color(0.92, 0.92, 0.90, 0.0), 0.9)
	grow.chain().tween_callback(puff.queue_free)

func spawn_shell(from: Vector3, to: Vector3, team: int, damage: float, at_value: float) -> void:
	spawn_muzzle_smoke(from, (to - from).normalized(), 1.6)
	var shell := Projectile.new()
	add_child(shell)
	shell.trail_scale = 1.0
	shell.launch(self, from, to, team, damage, at_value, 120.0, 3.0)

func spawn_rocket(from: Vector3, target: BattleUnit, team: int, damage: float) -> void:
	spawn_muzzle_smoke(from, (target.global_position - from).normalized(), 1.3)
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
	for u: BattleUnit in units:
		if is_instance_valid(u) and u.is_alive() and u.global_position.distance_to(target) < 20.0:
			var away: Vector3 = (u.global_position - target).normalized() * 30.0
			u.order_move(terrain.clamp_to_map(u.global_position + away))
			u.take_suppression(0.5)
	get_tree().create_timer(4.0).timeout.connect(marker.queue_free)
	get_tree().create_timer(4.0).timeout.connect(_artillery_impact.bind(target, team))

## An aircraft runs in across the map and walks a stick of bombs through the
## target. It is the one piece of firepower the player can put anywhere, which
## is why it is on a long cooldown rather than a price.
func call_air_strike(target: Vector3, team: int) -> void:
	var dir := Vector3(0, 0, 1.0 if team == 0 else -1.0)
	var entry := terrain.clamp_to_map(target - dir * terrain.map_size * 0.5)
	var plane := MeshInstance3D.new()
	var body := BoxMesh.new()
	body.size = Vector3(1.6, 1.0, 9.0)
	plane.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.26)
	plane.material_override = mat
	add_child(plane)
	var wing := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(11.0, 0.4, 2.2)
	wing.mesh = wm
	wing.material_override = mat
	plane.add_child(wing)
	plane.global_position = entry + Vector3(0, 70.0, 0)
	plane.look_at(plane.global_position + dir, Vector3.UP)

	var run := create_tween()
	run.tween_property(plane, "global_position",
		terrain.clamp_to_map(target + dir * terrain.map_size * 0.5) + Vector3(0, 70.0, 0), 4.0)
	run.tween_callback(plane.queue_free)

	Radio.say("SHTAB", Radio.Call.AIR_CALLED, 0.0)
	GameState.notify("Aviatsiya yo'lda.", "good")
	# Mark the run-in so everyone on the ground can clear the line.
	for u: BattleUnit in units:
		if is_instance_valid(u) and u.is_alive() and u.global_position.distance_to(target) < 26.0:
			u.take_suppression(0.4)
	for i in range(6):
		var delay := 1.8 + float(i) * 0.18
		var at := target + dir * (float(i) - 2.5) * 11.0
		var t := get_tree().create_timer(delay)
		t.timeout.connect(_drop_bomb.bind(at, team))

func _drop_bomb(at: Vector3, team: int) -> void:
	if not is_instance_valid(self) or terrain == null:
		return
	var ground := terrain.ground_point(at.x, at.z)
	spawn_explosion(ground, 13.0, 190.0, team, true)

## One shot, map-changing. It flattens everything in a wide circle, friend or
## foe, which is the point: it is a last resort, not a tool.
func call_nuke(target: Vector3, team: int) -> void:
	var ground := terrain.ground_point(target.x, target.z)
	GameState.notify("YADRO ZARBASI", "bad")
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.75)
	flash.light_energy = 60.0
	flash.omni_range = 400.0
	flash.position = ground + Vector3(0, 30, 0)
	add_child(flash)
	var fade := create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 2.5)
	fade.tween_callback(flash.queue_free)

	spawn_explosion(ground, 60.0, 4000.0, team, true)
	for i in range(10):
		var ang := TAU * float(i) / 10.0
		var at := ground + Vector3(cos(ang), 0, sin(ang)) * 42.0
		spawn_explosion(terrain.ground_point(at.x, at.z), 26.0, 900.0, team, true)
	# Everything left standing anywhere near it comes down.
	for h in buildings.duplicate():
		if is_instance_valid(h) and h.global_position.distance_to(ground) < 140.0:
			h.damage(h.global_position, 40.0, 30.0)
	_mushroom_cloud(ground)

func _mushroom_cloud(at: Vector3) -> void:
	var smoke := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 18.0
	mat.initial_velocity_min = 14.0
	mat.initial_velocity_max = 26.0
	mat.gravity = Vector3(0, 2.0, 0)
	mat.scale_min = 14.0
	mat.scale_max = 34.0
	smoke.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(12, 12)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.25, 0.22, 0.2, 0.6)
	qm.material = smat
	smoke.draw_pass_1 = qm
	smoke.amount = 220
	smoke.lifetime = 14.0
	smoke.one_shot = true
	smoke.position = at + Vector3(0, 8, 0)
	add_child(smoke)
	smoke.emitting = true

## The shells land a few seconds after the circle appears, scattered around
## the aim point rather than all on it.
func _artillery_impact(target: Vector3, team: int) -> void:
	if terrain == null:
		return
	for i in range(6):
		var offset := Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
		spawn_explosion(terrain.ground_point(target.x + offset.x, target.z + offset.z),
			8.0, 110.0, team, true)

func spawn_explosion(pos: Vector3, radius: float, damage: float, team: int, make_crater: bool) -> void:
	# Light, smoke and a hole in the ground.
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.light_energy = 8.0
	flash.omni_range = radius * 3.0
	flash.position = pos + Vector3(0, 2, 0)
	add_child(flash)
	_spawn_fireball(pos, radius)
	get_tree().create_timer(0.25).timeout.connect(flash.queue_free)
	if make_crater:
		terrain.add_crater(pos, radius * 0.9, radius * 0.25)
		cover.add_crater(pos, radius * 0.9)
	for u: BattleUnit in units:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var d: float = u.global_position.distance_to(pos)
		if d > radius * 2.0:
			continue
		var falloff: float = clampf(1.0 - d / (radius * 2.0), 0.0, 1.0)
		var dir: Vector3 = (u.global_position - pos).normalized()
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
## The orange ball of flame an impact actually makes, which is what the eye
## catches before the smoke.
func _spawn_fireball(pos: Vector3, radius: float) -> void:
	if Settings.graphics_quality == 0:
		return
	var ball := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 1.6, radius * 1.6)
	ball.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.72, 0.22, 0.95)
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = pos + Vector3(0, radius * 0.4, 0)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(ball, "scale", Vector3.ONE * 1.9, 0.45)
	t.tween_property(ball, "global_position", ball.global_position + Vector3(0, radius * 0.5, 0), 0.45)
	t.tween_property(mat, "albedo_color", Color(0.35, 0.18, 0.08, 0.0), 0.45)
	t.chain().tween_callback(ball.queue_free)

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
		var dir: Vector3 = (p - pos).normalized()
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
		for u: BattleUnit in units:
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
	for ai in ai_commanders:
		ai.tick(delta)
	director.tick(delta, units)
	_check_mines()
	_fade_trails(delta)
	_rescue_timer -= delta
	if _rescue_timer <= 0.0:
		_rescue_timer = 1.5
		_assign_rescuers()
	if stats != null:
		stats.elapsed = director.elapsed
	_follow_camera_with_weather()
	_tick_reveal(delta)
	_update_point_markers()
	_fog_timer -= delta
	if _fog_timer <= 0.0:
		_fog_timer = 0.25
		_update_fog_of_war()

## One emitter box kept over the camera covers the visible map; emitting over
## the whole battlefield would spend thousands of particles nobody can see.
func _follow_camera_with_weather() -> void:
	if _weather_particles == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_weather_particles.global_position = Vector3(cam.global_position.x, cam.global_position.y + 40.0,
		cam.global_position.z)

func _tick_reveal(delta: float) -> void:
	for key in _revealed.keys().duplicate():
		var left: float = float(_revealed[key]) - delta
		if left <= 0.0:
			_revealed.erase(key)
		else:
			_revealed[key] = left

func _update_point_markers() -> void:
	if director.hold_zone != null:
		_refresh_marker(director.hold_zone)
	for p: ObjectivePoint in director.points:
		_refresh_marker(p)

func _refresh_marker(p: ObjectivePoint) -> void:
	if p.marker == null or not is_instance_valid(p.marker):
		return
	var mat: StandardMaterial3D = p.marker.material_override
	var c: Color = p.color_for_owner(_team_colors)
	c.a = 0.4 if p.contested else 0.22
	mat.albedo_color = c

## Recon matters because enemies you have not seen are simply not drawn.
func _update_fog_of_war() -> void:
	var friendly := units_of_team(player_team)
	for u: BattleUnit in units:
		if not is_instance_valid(u) or u.team == player_team:
			continue
		var seen: bool = is_revealed(u.global_position)
		if not seen:
			for f: BattleUnit in friendly:
				var sight: float = float(f.data.get("vision", 50)) * vision_modifier()
				if f.global_position.distance_to(u.global_position) < sight:
					if has_line_of_sight(f, u):
						seen = true
						break
		u.visible = seen

func on_point_captured(p: ObjectivePoint) -> void:
	if stats != null:
		stats.on_point_captured(p.owner_team)
	if p.owner_team == player_team:
		Radio.say("SHTAB", Radio.Call.OBJECTIVE_TAKEN, 0.0)
	var who: String = "Siz" if p.owner_team == player_team else "Dushman"
	GameState.notify("%s %s nuqtasini egalladi." % [who, p.id], "good" if p.owner_team == player_team else "warn")

func on_unit_wounded(u: BattleUnit) -> void:
	if not wounded_units.has(u):
		wounded_units.append(u)
	if u.team == player_team:
		GameState.notify("Yarador: qutqaruvchi kerak.", "warn")

func on_unit_recovered(u: BattleUnit) -> void:
	wounded_units.erase(u)
	if stats != null:
		stats.on_rescued(u.team)
	if u.team == player_team:
		GameState.notify("Yarador qutqarildi va safga qaytdi.", "good")

func on_unit_died(u: BattleUnit, was_wounded: bool = false) -> void:
	wounded_units.erase(u)
	# Credit the man who did it, so he can earn his way up.
	if u.last_attacker_team >= 0 and u.last_attacker_team != u.team:
		for killer in units_of_team(u.last_attacker_team):
			if killer.unit_id == u.last_attacker_unit and killer.is_fighting():
				killer.credit_kill()
				break
	director.on_unit_died(u)
	if stats != null:
		stats.on_kill(u.team, u.unit_id, u.unit_class(), u.men_count(),
			u.last_attacker_team, u.last_attacker_unit)
		if was_wounded:
			stats.on_bled_out(u.team)
	for s in squads:
		s.remove(u)

## Sends the nearest man who is not already busy. Carrying somebody off is a
## real cost: that is one rifle out of the line for as long as it takes.
func _assign_rescuers() -> void:
	for w in wounded_units.duplicate():
		if not is_instance_valid(w) or not w.wounded:
			wounded_units.erase(w)
			continue
		if w.rescuer != null and is_instance_valid(w.rescuer) and w.rescuer.is_fighting():
			continue
		w.rescuer = null
		var best: BattleUnit = null
		var best_d := 70.0
		for u in units_of_team(w.team):
			if u == w or not u.is_fighting() or u.unit_class() != "infantry":
				continue
			if u.rescuing != null:
				continue
			var d: float = u.global_position.distance_to(w.global_position)
			if d < best_d:
				best_d = d
				best = u
		if best != null:
			best.rescuing = w
			w.rescuer = best
			best.activity = BattleUnit.Activity.RESCUING

## Somewhere a wounded man can be dragged to: back toward his own edge.
func safe_point_for(team: int) -> Vector3:
	return spawn_point_for(team)

func on_battle_finished(res: Dictionary) -> void:
	var teams: Array = cfg.get("teams", [])
	var winner_team := int(res.get("winner_team", 0))
	var losses: Array = res.get("losses", [0.3, 0.3])
	if stats != null:
		stats.elapsed = float(res.get("elapsed", director.elapsed))
	var out := {
		"battle_id": int(cfg.get("battle_id", 0)),
		"province": int(cfg.get("province", -1)),
		"province_name": str(cfg.get("province_name", "")),
		"map": str(cfg.get("map", "")),
		"season": season,
		"weather": weather,
		"victory_mode": victory_mode,
		"reason": str(res.get("reason", "")),
		"mission": str(cfg.get("mission", "")),
		"winner_team": winner_team,
		"winner": str(teams[winner_team].get("nation", "")) if teams.size() > winner_team else "",
		"attacker": str(teams[0].get("nation", "")) if teams.size() > 0 else "",
		"defender": str(teams[1].get("nation", "")) if teams.size() > 1 else "",
		"attacker_losses": float(losses[0]),
		"defender_losses": float(losses[1]),
		"tickets": res.get("tickets", [0, 0]),
		"points_held": res.get("points", [0, 0]),
		"player_team": player_team,
		"player_won": winner_team == player_team,
		"stats": stats.to_dict() if stats != null else {},
		"auto": false,
	}
	GameState.last_battle_result = out
	EventBus.battle_ended.emit(out)
