class_name BattleAI
extends Node
## The enemy commander. It plays with the same orders a human has: it forms
## groups, sends them at points, shells whatever has bunched up, and calls in
## armour and drones when it can pay for them.

var battle = null
var team: int = 1
var think_timer: float = 2.0
var aggression: float = 0.55
var reaction: float = 4.0          # seconds between decisions
var support_mult: float = 1.0      # how freely it spends supply
var _rng := RandomNumberGenerator.new()
var _groups: Array = []

func setup(ctx, p_team: int, seed_value: int, difficulty: Dictionary) -> void:
	battle = ctx
	team = p_team
	aggression = float(difficulty.get("aggression", 0.55))
	reaction = float(difficulty.get("reaction", 4.0))
	support_mult = float(difficulty.get("support", 1.0))
	_rng.seed = seed_value + p_team * 977
	think_timer = reaction * 0.5

func tick(delta: float) -> void:
	if battle == null or battle.director.finished:
		return
	think_timer -= delta
	if think_timer > 0.0:
		return
	think_timer = reaction * _rng.randf_range(0.8, 1.3)
	_organise()
	_assign_objectives()
	_use_support()

## Keeps three standing groups: a line, an armoured fist and the guns.
func _organise() -> void:
	_groups = [[], [], []]
	for u: BattleUnit in battle.units_of_team(team):
		if not u.is_alive():
			continue
		match u.unit_class():
			"vehicle":
				if str(u.data.get("role", "")) == "artillery":
					_groups[2].append(u)
				else:
					_groups[1].append(u)
			_:
				_groups[0].append(u)

func _assign_objectives() -> void:
	match battle.victory_mode:
		"destroy":
			_push_command_post()
			return
		"hold":
			_contest_hold_zone()
			return
		_:
			pass
	var targets := _priority_points()
	if targets.is_empty():
		return
	# Infantry takes and holds; armour pushes the most contested point.
	var inf: Array = _groups[0]
	if not inf.is_empty():
		var split: int = maxi(1, inf.size() / maxi(1, targets.size()))
		var ti := 0
		for i in range(inf.size()):
			var u: BattleUnit = inf[i]
			var point = targets[mini(ti, targets.size() - 1)]
			if u.activity == BattleUnit.Activity.IDLE or not u.has_move_target:
				u.order_capture(point)
			if (i + 1) % split == 0:
				ti += 1
	var armour: Array = _groups[1]
	if not armour.is_empty():
		var spearhead = targets[0]
		for u: BattleUnit in armour:
			if not u.has_move_target:
				var offset := Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
				u.order_move(battle.terrain.clamp_to_map(spearhead.position + offset))

## Destroy mode: armour goes for the enemy post, infantry screens our own.
func _push_command_post() -> void:
	var enemy_post = battle.objective_for(1 - team)
	var own_post = battle.objective_for(team)
	if enemy_post == null:
		return
	for u: BattleUnit in _groups[1]:
		if not u.has_move_target:
			u.order_attack_building(enemy_post)
	var defenders: int = maxi(1, int(float(_groups[0].size()) * (1.0 - aggression)))
	for i in range(_groups[0].size()):
		var u: BattleUnit = _groups[0][i]
		if u.has_move_target:
			continue
		if i < defenders and own_post != null:
			var ring := Vector3(_rng.randf_range(-20, 20), 0, _rng.randf_range(-20, 20))
			u.order_move(battle.terrain.clamp_to_map(own_post.global_position + ring))
		else:
			u.order_attack_building(enemy_post)

## Hold mode: the defender digs in on the zone, the attacker walks into it.
func _contest_hold_zone() -> void:
	var zone = battle.director.hold_zone
	if zone == null:
		return
	var defending: bool = team == battle.director.hold_defender
	var radius: float = zone.radius * (0.7 if defending else 1.0)
	for group in _groups:
		for u: BattleUnit in group:
			if u.has_move_target:
				continue
			var ang := _rng.randf_range(0.0, TAU)
			var dist: float = radius * (_rng.randf_range(0.3, 1.0) if defending else 0.5)
			var spot := zone.position + Vector3(cos(ang), 0, sin(ang)) * dist
			if defending:
				# Put part of the line into whatever is standing on the zone.
				var house = _nearest_free_building(u.global_position, zone.position)
				if house != null and u.unit_class() == "infantry" and _rng.randf() < 0.6:
					u.order_garrison(house)
				else:
					u.order_move(battle.terrain.clamp_to_map(spot))
			else:
				u.order_capture(zone)

## A building near the ground we are holding that still has room in it.
func _nearest_free_building(from: Vector3, near: Vector3):
	var best = null
	var best_d := 60.0
	for h in battle.buildings:
		if not is_instance_valid(h) or not h.has_method("can_garrison"):
			continue
		if not h.can_garrison(team):
			continue
		if h.global_position.distance_to(near) > 70.0:
			continue
		var d: float = from.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = h
	return best

func _priority_points() -> Array:
	var list: Array = []
	for p: ObjectivePoint in battle.director.points:
		list.append(p)
	# Enemy-held and neutral points first, closest to our own mass.
	var home := _center_of_mass()
	list.sort_custom(func(a, b):
		var sa: float = (0.0 if a.owner_team == team else 60.0) - home.distance_to(a.position) * 0.1
		var sb: float = (0.0 if b.owner_team == team else 60.0) - home.distance_to(b.position) * 0.1
		return sa > sb)
	return list

func _center_of_mass() -> Vector3:
	var list := battle.units_of_team(team)
	if list.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var n := 0
	for u in list:
		if u.is_alive():
			sum += u.global_position
			n += 1
	return sum / maxf(float(n), 1.0)

func _use_support() -> void:
	var dir := battle.director
	# Shell whatever the enemy has stacked up.
	var cluster := _find_enemy_cluster()
	var cluster_threshold: int = 6 - int(aggression * 4.0)
	if int(cluster["count"]) >= cluster_threshold and dir.can_pay(team, 40.0):
		dir.pay(team, 40.0)
		battle.call_artillery_strike(_center_of_mass(), cluster["pos"], team, null)
	# Reinforce when the reserve allows it.
	if dir.reinforcement_ready(team) and dir.can_pay(team, 10.0):
		dir.pay(team, 10.0)
		dir.start_reinforce_cooldown(team)
		battle.spawn_reinforcement_squad(team)
	# Armour, when the enemy has armour or the line has stalled.
	if dir.can_pay(team, 120.0) and _rng.randf() < (0.2 + aggression * 0.4) * support_mult:
		dir.pay(team, 120.0)
		battle.spawn_support_vehicle(team, "veh_tank")
	# Eyes.
	if dir.can_pay(team, 25.0) and _rng.randf() < 0.2 * support_mult:
		dir.pay(team, 25.0)
		battle.spawn_support_vehicle(team, "air_drone")
	# A cheap FPV drone against anything armoured that got close.
	if dir.can_pay(team, 15.0) and _rng.randf() < 0.3 * support_mult:
		for u: BattleUnit in battle.enemies_of(team):
			if u.is_alive() and u.unit_class() == "vehicle":
				dir.pay(team, 15.0)
				battle.spawn_support_vehicle(team, "air_fpv")
				break

func _find_enemy_cluster() -> Dictionary:
	var enemies := battle.enemies_of(team)
	var best := {"pos": Vector3.ZERO, "count": 0}
	for u: BattleUnit in enemies:
		if not u.is_alive():
			continue
		var n := 0
		for v: BattleUnit in enemies:
			if v.is_alive() and v.global_position.distance_to(u.global_position) < 22.0:
				n += 1
		if n > int(best["count"]):
			best = {"pos": u.global_position, "count": n}
	return best
