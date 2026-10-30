class_name BattleDirector
extends Node
## Runs the match itself: capture points, the reserve both sides bleed from,
## battlefield supply, reinforcement waves and the win condition.

const BLEED_INTERVAL := 15.0
const REINFORCE_DELAY := 25.0

var battle = null
var tickets: Array = [150, 150]
var supply: Array = [60.0, 60.0]
var points: Array = []                     # ObjectivePoint
var elapsed: float = 0.0
var duration: float = 1800.0
var finished: bool = false
var result: Dictionary = {}
var initial_tickets: Array = [150, 150]

var _bleed_timer: float = BLEED_INTERVAL
var _reinforce_cd: Array = [0.0, 0.0]
var _supply_timer: float = 1.0

func setup(ctx, cfg: Dictionary) -> void:
	battle = ctx
	duration = float(cfg.get("duration", 1800.0))
	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		tickets[i] = int(teams[i].get("tickets", 150))
	initial_tickets = tickets.duplicate()

func add_point(id: String, display: String, pos: Vector3, owner_team: int = -1) -> ObjectivePoint:
	var p := ObjectivePoint.new()
	p.id = id
	p.display_name = display
	p.position = pos
	p.owner_team = owner_team
	p.progress = -1.0 if owner_team == 0 else (1.0 if owner_team == 1 else 0.0)
	points.append(p)
	return p

func held_by(team: int) -> int:
	var n := 0
	for p in points:
		if p.owner_team == team:
			n += 1
	return n

func tick(delta: float, units: Array) -> void:
	if finished:
		return
	elapsed += delta
	for p in points:
		if p.update(delta, units):
			EventBus.objective_captured.emit(p.id, p.owner_team)
			battle.on_point_captured(p)
	_bleed_timer -= delta
	if _bleed_timer <= 0.0:
		_bleed_timer = BLEED_INTERVAL
		_apply_bleed()
	_supply_timer -= delta
	if _supply_timer <= 0.0:
		_supply_timer = 1.0
		_tick_supply()
	for i in range(2):
		_reinforce_cd[i] = maxf(0.0, _reinforce_cd[i] - delta)
	_check_end(units)

## The side holding fewer points loses men from its reserve: the difference in
## points, every fifteen seconds.
func _apply_bleed() -> void:
	var a := held_by(0)
	var b := held_by(1)
	if a == b:
		return
	var loser: int = 1 if a > b else 0
	var amount: int = absi(a - b)
	tickets[loser] = maxi(0, tickets[loser] - amount)
	EventBus.tickets_changed.emit(loser, tickets[loser])

func _tick_supply() -> void:
	for team in range(2):
		var income: float = 1.0 + float(held_by(team)) * 0.6
		supply[team] = minf(supply[team] + income, 300.0)
		EventBus.supply_changed.emit(team, supply[team])

func can_pay(team: int, amount: float) -> bool:
	return supply[team] >= amount

func pay(team: int, amount: float) -> bool:
	if not can_pay(team, amount):
		return false
	supply[team] -= amount
	EventBus.supply_changed.emit(team, supply[team])
	return true

func reinforcement_ready(team: int) -> bool:
	return _reinforce_cd[team] <= 0.0

func start_reinforce_cooldown(team: int) -> void:
	_reinforce_cd[team] = REINFORCE_DELAY

func reinforce_cooldown(team: int) -> float:
	return _reinforce_cd[team]

func spend_tickets(team: int, men: int) -> bool:
	if tickets[team] < men:
		return false
	tickets[team] -= men
	EventBus.tickets_changed.emit(team, tickets[team])
	return true

func on_unit_died(u: BattleUnit) -> void:
	# Losses come straight off the reserve, so a bad assault is felt at once.
	tickets[u.team] = maxi(0, tickets[u.team] - u.men_count())
	EventBus.tickets_changed.emit(u.team, tickets[u.team])

func _check_end(units: Array) -> void:
	var alive := [0, 0]
	for u in units:
		if u.is_alive():
			alive[u.team] += u.men_count()
	for team in range(2):
		if tickets[team] <= 0 and alive[team] <= 0:
			_finish(1 - team, "annihilation")
			return
	if elapsed >= duration:
		var winner: int = 0 if tickets[0] >= tickets[1] else 1
		if held_by(0) != held_by(1):
			winner = 0 if held_by(0) > held_by(1) else 1
		_finish(winner, "time")

func _finish(winner: int, reason: String) -> void:
	finished = true
	var losses := [0.0, 0.0]
	for i in range(2):
		var start: float = maxf(float(initial_tickets[i]), 1.0)
		losses[i] = clampf(1.0 - float(tickets[i]) / start, 0.0, 1.0)
	result = {
		"winner_team": winner,
		"reason": reason,
		"tickets": tickets.duplicate(),
		"points": [held_by(0), held_by(1)],
		"losses": losses,
		"elapsed": elapsed,
	}
	battle.on_battle_finished(result)

func time_left() -> float:
	return maxf(0.0, duration - elapsed)
