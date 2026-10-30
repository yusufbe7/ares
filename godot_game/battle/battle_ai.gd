class_name BattleAI
extends Node
## The enemy commander. It plays with the same orders a human has: it forms
## groups, sends them at points, shells whatever has bunched up, and calls in
## armour and drones when it can pay for them.

var battle = null
var team: int = 1
var think_timer: float = 2.0
var aggression: float = 0.5
var _rng := RandomNumberGenerator.new()
var _groups: Array = []

func setup(ctx, p_team: int, seed_value: int, p_aggression: float = 0.5) -> void:
	battle = ctx
	team = p_team
	aggression = p_aggression
	_rng.seed = seed_value + p_team * 977

func tick(delta: float) -> void:
	if battle == null or battle.director.finished:
		return
	think_timer -= delta
	if think_timer > 0.0:
		return
	think_timer = _rng.randf_range(3.0, 6.0)
	_organise()
	_assign_objectives()
	_use_support()

## Keeps three standing groups: a line, an armoured fist and the guns.
func _organise() -> void:
	_groups = [[], [], []]
	for u in battle.units_of_team(team):
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
		for u in armour:
			if not u.has_move_target:
				var offset := Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
				u.order_move(battle.terrain.clamp_to_map(spearhead.position + offset))

func _priority_points() -> Array:
	var list: Array = []
	for p in battle.director.points:
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
	if cluster["count"] >= 4 and dir.can_pay(team, 40.0):
		dir.pay(team, 40.0)
		battle.call_artillery_strike(_center_of_mass(), cluster["pos"], team, null)
	# Reinforce when the reserve allows it.
	if dir.reinforcement_ready(team) and dir.can_pay(team, 10.0):
		dir.pay(team, 10.0)
		dir.start_reinforce_cooldown(team)
		battle.spawn_reinforcement_squad(team)
	# Armour, when the enemy has armour or the line has stalled.
	if dir.can_pay(team, 120.0) and _rng.randf() < 0.35 + aggression * 0.3:
		dir.pay(team, 120.0)
		battle.spawn_support_vehicle(team, "veh_tank")
	# Eyes.
	if dir.can_pay(team, 25.0) and _rng.randf() < 0.2:
		dir.pay(team, 25.0)
		battle.spawn_support_vehicle(team, "air_drone")
	# A cheap FPV drone against anything armoured that got close.
	if dir.can_pay(team, 15.0) and _rng.randf() < 0.3:
		for u in battle.enemies_of(team):
			if u.is_alive() and u.unit_class() == "vehicle":
				dir.pay(team, 15.0)
				battle.spawn_support_vehicle(team, "air_fpv")
				break

func _find_enemy_cluster() -> Dictionary:
	var enemies := battle.enemies_of(team)
	var best := {"pos": Vector3.ZERO, "count": 0}
	for u in enemies:
		if not u.is_alive():
			continue
		var n := 0
		for v in enemies:
			if v.is_alive() and v.global_position.distance_to(u.global_position) < 22.0:
				n += 1
		if n > int(best["count"]):
			best = {"pos": u.global_position, "count": n}
	return best
