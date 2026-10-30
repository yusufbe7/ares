class_name BattleUnit
extends Node3D
## Base for everything that fights. The player never micromanages these: an
## order sets an intent ("take that point", "attack that building") and the unit
## works out the route, the cover, when to shoot and when to keep its head down.

enum Stance { STAND, CROUCH, PRONE }
enum Activity { IDLE, MOVING, ENGAGING, SUPPRESSED, CAPTURING, DEAD, RETREATING }

var battle = null                 # the Battle node, set on spawn
var team: int = 0
var unit_id: String = "inf_rifle"
var data: Dictionary = {}
var squad_index: int = -1         # which control group owns it, -1 = none

var max_hp: float = 100.0
var hp: float = 100.0
var suppression: float = 0.0      # 0..1 — the single biggest driver of behaviour
var stance: int = Stance.STAND
var activity: int = Activity.IDLE
var morale: float = 1.0

var move_target: Vector3 = Vector3.ZERO
var has_move_target: bool = false
var path: Array = []
var path_index: int = 0
var attack_target: BattleUnit = null
var forced_target: BattleUnit = null
var target_building = null
var capture_point = null
var hold_position: bool = false

var _fire_cooldown: float = 0.0
var _retarget_timer: float = 0.0
var _repath_timer: float = 0.0
var _cover_slot = null
var _speed: float = 4.0
var _vision: float = 50.0
var _range: float = 45.0
var _facing: Vector3 = Vector3.FORWARD
var _rng := RandomNumberGenerator.new()
var _selected: bool = false
var _marker: MeshInstance3D = null
## Kill credit: whoever landed the last hit gets it in the after-action report.
var last_attacker_team: int = -1
var last_attacker_unit: String = ""

func setup(ctx, p_team: int, p_unit_id: String, spawn_pos: Vector3) -> void:
	battle = ctx
	team = p_team
	unit_id = p_unit_id
	data = DB.unit(p_unit_id)
	max_hp = float(data.get("hp", 100))
	hp = max_hp
	_speed = float(data.get("speed", 4.0))
	_vision = float(data.get("vision", 50.0))
	_range = float(data.get("range", 45.0))
	_rng.seed = int(Time.get_ticks_usec()) + get_instance_id()
	position = spawn_pos
	_build_visual()
	_build_marker()

func _build_visual() -> void:
	pass          # subclasses build their own body

func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	_marker.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.4, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker.material_override = mat
	_marker.position = Vector3(0, 0.1, 0)
	_marker.visible = false
	add_child(_marker)

func set_selected(value: bool) -> void:
	_selected = value
	if _marker != null:
		_marker.visible = value

func is_alive() -> bool:
	return activity != Activity.DEAD and hp > 0.0

func unit_class() -> String:
	return str(data.get("class", "infantry"))

func is_air() -> bool:
	return unit_class() == "aircraft"

# ---------------------------------------------------------------------------
# Orders
# ---------------------------------------------------------------------------

func order_move(pos: Vector3, keep_formation_offset: Vector3 = Vector3.ZERO) -> void:
	move_target = pos + keep_formation_offset
	has_move_target = true
	hold_position = false
	capture_point = null
	target_building = null
	forced_target = null
	activity = Activity.MOVING
	_recompute_path()

func order_attack(target: BattleUnit) -> void:
	forced_target = target
	attack_target = target
	hold_position = false
	capture_point = null
	activity = Activity.ENGAGING

func order_attack_building(building) -> void:
	target_building = building
	forced_target = null
	hold_position = false
	activity = Activity.ENGAGING
	if unit_class() == "infantry":
		# Infantry does not level houses; it takes cover against them.
		order_move(building.global_position + (global_position - building.global_position).normalized() * 6.0)
		target_building = building

func order_capture(point) -> void:
	capture_point = point
	hold_position = false
	order_move(point.position)
	capture_point = point
	activity = Activity.MOVING

func order_hold() -> void:
	hold_position = true
	has_move_target = false
	path.clear()
	activity = Activity.IDLE

func order_stance(new_stance: int) -> void:
	stance = new_stance

func _recompute_path() -> void:
	if battle == null:
		return
	if is_air():
		path = [move_target]
		path_index = 0
		return
	path = battle.find_path(global_position, move_target)
	path_index = 0
	if path.is_empty():
		path = [move_target]

# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_alive() or battle == null:
		return
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_retarget_timer -= delta
	_repath_timer -= delta
	suppression = maxf(0.0, suppression - delta * 0.22)
	if _retarget_timer <= 0.0:
		_retarget_timer = _rng.randf_range(0.4, 0.9)
		_acquire_target()
	_think(delta)
	_shoot(delta)

func _think(delta: float) -> void:
	_move_step(delta)

func _acquire_target() -> void:
	if forced_target != null and forced_target.is_alive():
		attack_target = forced_target
		return
	forced_target = null
	var best: BattleUnit = null
	var best_score := -INF
	var sight: float = _vision * battle.vision_modifier()
	for u in battle.enemies_of(team):
		if not u.is_alive():
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d > sight:
			continue
		if not battle.has_line_of_sight(self, u):
			continue
		var score: float = sight - d
		# Shoot what you can actually hurt: AT at armour, rifles at infantry.
		var at: float = float(data.get("at", 0.0))
		if u.unit_class() == "vehicle":
			score += 60.0 * at - 40.0 * (1.0 - at)
		if u.is_air():
			score += 80.0 if str(data.get("role", "")) == "anti_air" else -200.0
		if score > best_score:
			best_score = score
			best = u
	attack_target = best

func _move_step(delta: float) -> void:
	if path.is_empty() or path_index >= path.size():
		has_move_target = false
		return
	var speed: float = effective_speed()
	var waypoint: Vector3 = path[path_index]
	var flat_target := Vector3(waypoint.x, global_position.y, waypoint.z)
	var to_target := flat_target - global_position
	if to_target.length() < 2.0:
		path_index += 1
		if path_index >= path.size():
			has_move_target = false
			_on_arrived()
		return
	var dir := to_target.normalized()
	_facing = _facing.lerp(dir, clampf(delta * 4.0, 0.0, 1.0)).normalized()
	global_position += dir * speed * delta
	_stick_to_ground()
	look_at_direction(_facing)

func _on_arrived() -> void:
	if capture_point != null:
		activity = Activity.CAPTURING
	else:
		activity = Activity.IDLE

func effective_speed() -> float:
	var s: float = _speed
	match stance:
		Stance.CROUCH: s *= 0.55
		Stance.PRONE: s *= 0.22
	s *= 1.0 - suppression * 0.5
	s *= battle.speed_modifier()
	return maxf(s, 0.2)

func _stick_to_ground() -> void:
	if is_air():
		var alt: float = float(data.get("altitude", 25.0))
		var ground: float = battle.terrain.height_at(global_position.x, global_position.z)
		global_position.y = lerpf(global_position.y, ground + alt, 0.08)
		return
	global_position.y = battle.terrain.height_at(global_position.x, global_position.z) + ground_offset()

func ground_offset() -> float:
	return 0.0

func look_at_direction(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	if flat.length() < 0.01:
		return
	rotation.y = atan2(flat.x, flat.z)

# ---------------------------------------------------------------------------
# Shooting
# ---------------------------------------------------------------------------

func _shoot(_delta: float) -> void:
	if attack_target == null or not attack_target.is_alive():
		_shoot_building()
		return
	if _fire_cooldown > 0.0:
		return
	var d: float = global_position.distance_to(attack_target.global_position)
	if d > _range:
		return
	if suppression > 0.75:
		return        # pinned: the soldier stays behind the wall
	if not battle.has_line_of_sight(self, attack_target):
		return
	var rpm: float = maxf(float(data.get("rpm", 60)), 1.0)
	_fire_cooldown = 60.0 / rpm
	look_at_direction(attack_target.global_position - global_position)
	fire_at(attack_target, d)

func fire_at(target: BattleUnit, distance: float) -> void:
	var acc: float = float(data.get("accuracy", 0.5))
	acc *= battle.accuracy_modifier()
	acc *= battle.team_accuracy(team)
	acc *= 1.0 - suppression * 0.6
	acc *= clampf(1.0 - distance / maxf(_range, 1.0) * 0.5, 0.25, 1.0)
	match stance:
		Stance.CROUCH: acc *= 1.12
		Stance.PRONE: acc *= 1.25
	var from_dir: Vector3 = (target.global_position - global_position).normalized()
	target.take_suppression(0.18)
	battle.spawn_tracer(muzzle_position(), target.global_position, team)
	if _rng.randf() > acc:
		return
	var protection: float = battle.cover.protection_at(target.global_position, from_dir)
	if battle.terrain.is_in_trench(target.global_position):
		protection = maxf(protection, 0.75)
	var dmg: float = float(data.get("damage", 10)) * (1.0 - protection)
	dmg *= target.armor_multiplier(from_dir, float(data.get("at", 0.0)))
	target.take_damage(dmg, self)

## An order to attack a house or a command post is carried out by whatever the
## unit actually has: armour and guns put rounds into the wall, infantry only
## works on it at close range.
func _shoot_building() -> void:
	if target_building == null or not is_instance_valid(target_building):
		target_building = null
		return
	if target_building.is_passable():
		target_building = null          # nothing left worth shooting
		return
	if _fire_cooldown > 0.0 or suppression > 0.75:
		return
	var aim: Vector3 = target_building.global_position + Vector3(0, 1.5, 0)
	var d: float = global_position.distance_to(aim)
	var reach: float = _range if unit_class() != "infantry" else 22.0
	if d > reach:
		return
	var rpm: float = maxf(float(data.get("rpm", 60)), 1.0)
	_fire_cooldown = 60.0 / rpm
	look_at_direction(aim - global_position)
	var role := str(data.get("role", ""))
	if role == "artillery":
		battle.call_artillery_strike(global_position, target_building.global_position, team, self)
		_fire_cooldown = maxf(_fire_cooldown, 12.0)
		return
	if unit_class() == "vehicle" or role == "gunship":
		battle.spawn_shell(muzzle_position(), aim, team,
			float(data.get("damage", 100)), float(data.get("at", 1.0)))
		return
	if float(data.get("at", 0.0)) > 0.5:
		battle.spawn_shell(muzzle_position(), aim, team, float(data.get("damage", 10)) * 4.0, 0.8)
		return
	# Small arms chip at a wall rather than bring it down.
	battle.spawn_tracer(muzzle_position(), aim, team)
	target_building.damage(aim, 1.5, 0.35)

func muzzle_position() -> Vector3:
	return global_position + Vector3(0, 1.4, 0) + _facing * 0.8

func take_suppression(amount: float) -> void:
	suppression = clampf(suppression + amount, 0.0, 1.0)
	if suppression > 0.45 and stance == Stance.STAND:
		stance = Stance.CROUCH
	if suppression > 0.8:
		stance = Stance.PRONE

## How much of an incoming hit the armour stops. Infantry has none; vehicles
## override this with real facings.
func armor_multiplier(_from_dir: Vector3, _attacker_at: float) -> float:
	return 1.0

func take_damage(amount: float, source) -> void:
	if not is_alive() or amount <= 0.0:
		return
	var applied: float = minf(amount, hp)
	hp -= amount
	morale = maxf(0.0, morale - amount / maxf(max_hp, 1.0) * 0.4)
	take_suppression(amount / maxf(max_hp, 1.0) * 0.8)
	if source != null and source is BattleUnit:
		last_attacker_team = source.team
		last_attacker_unit = source.unit_id
		if attack_target == null:
			attack_target = source
		if battle != null and battle.stats != null:
			battle.stats.on_damage(source.team, source.unit_id, applied)
	if hp <= 0.0:
		die()

func die() -> void:
	activity = Activity.DEAD
	hp = 0.0
	if _cover_slot != null and battle != null:
		battle.cover.release(_cover_slot, get_instance_id())
		_cover_slot = null
	EventBus.unit_died.emit(self)
	if battle != null:
		battle.on_unit_died(self)
	_on_death_visual()

func _on_death_visual() -> void:
	queue_free()

func men_count() -> int:
	return int(data.get("men", 1))

## Compact state for the network snapshot.
func snapshot() -> Dictionary:
	return {
		"i": get_instance_id(), "t": team, "u": unit_id,
		"p": [global_position.x, global_position.y, global_position.z],
		"r": rotation.y, "h": hp, "s": suppression, "a": activity, "st": stance,
	}

func apply_snapshot(d: Dictionary) -> void:
	var p: Array = d.get("p", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation.y = float(d.get("r", rotation.y))
	hp = float(d.get("h", hp))
	suppression = float(d.get("s", suppression))
	activity = int(d.get("a", activity))
	stance = int(d.get("st", stance))
