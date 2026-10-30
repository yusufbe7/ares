class_name BattleDirector
extends Node
## Runs the match: capture points, the reserve both sides bleed from,
## battlefield supply, reinforcement waves, and the four ways a battle can end.
##
##   elimination — wipe the enemy force out
##   capture     — hold the control points
##   hold        — defend marked ground until the clock runs out
##   destroy     — blow up the enemy command post

const BLEED_INTERVAL := 15.0
const REINFORCE_DELAY := 25.0
const HOLD_WIN_SECONDS := 120.0        # attacker's continuous hold to win early
const ALL_POINTS_WIN_SECONDS := 45.0   # hold every point this long to end it

var battle = null
var mode: String = "capture"
var tickets: Array = [150, 150]
var supply: Array = [60.0, 60.0]
var points: Array = []                     # ObjectivePoint
var elapsed: float = 0.0
var duration: float = 1800.0
var endless: bool = false
var finished: bool = false
var sandbox: bool = false
var player_team: int = 0
var result: Dictionary = {}
var initial_tickets: Array = [150, 150]

## "hold" mode: one zone, one defender, one clock.
var hold_zone: ObjectivePoint = null
var hold_defender: int = 1
var hold_attacker_timer: float = 0.0

var _bleed_timer: float = BLEED_INTERVAL
var _reinforce_cd: Array = [0.0, 0.0]
var _supply_timer: float = 1.0
var _sweep_timer: Array = [0.0, 0.0]       # how long a team has held everything

## Support strikes are gated by time, not supply: an air strike comes round
## every so often, and a nuke is a single shot per side per battle.
const AIR_STRIKE_COOLDOWN := 75.0
var air_strike_cd: Array = [25.0, 40.0]
var nuke_spent: Array = [false, false]

func setup(ctx, cfg: Dictionary) -> void:
	battle = ctx
	mode = str(cfg.get("victory_mode", "capture"))
	sandbox = bool(cfg.get("sandbox", false))
	player_team = int(cfg.get("player_team", 0))
	duration = float(cfg.get("duration", 1800.0))
	endless = duration <= 0.0
	var teams: Array = cfg.get("teams", [])
	for i in range(mini(2, teams.size())):
		tickets[i] = int(teams[i].get("tickets", 150))
		if bool(teams[i].get("is_defender", false)):
			hold_defender = i
	initial_tickets = tickets.duplicate()
	var diff: Dictionary = DB.difficulty(str(cfg.get("difficulty", "normal")))
	# A harder opponent simply gets more to spend, not a damage multiplier.
	var enemy: int = 1 - int(cfg.get("player_team", 0))
	supply[enemy] *= float(diff.get("supply", 1.0))

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
	for p: ObjectivePoint in points:
		if p.owner_team == team:
			n += 1
	return n

func tick(delta: float, units: Array) -> void:
	if finished:
		return
	elapsed += delta
	for p: ObjectivePoint in points:
		if p.update(delta, units):
			EventBus.objective_captured.emit(p.id, p.owner_team)
			battle.on_point_captured(p)
	if hold_zone != null:
		hold_zone.update(delta, units)
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
		air_strike_cd[i] = maxf(0.0, air_strike_cd[i] - delta)
	_check_end(delta, units)

## The side holding fewer points loses men from its reserve: the difference in
## points, every fifteen seconds. Only the point-based modes bleed.
func _apply_bleed() -> void:
	if mode != "capture" and mode != "elimination":
		return
	var a := held_by(0)
	var b := held_by(1)
	if a == b:
		return
	var loser: int = 1 if a > b else 0
	var amount: int = absi(a - b)
	tickets[loser] = maxi(0, tickets[loser] - amount)
	EventBus.tickets_changed.emit(loser, tickets[loser])

func _tick_supply() -> void:
	if sandbox:
		# Sandbox is for trying things, not for budgeting.
		supply[player_team] = 9999.0
		EventBus.supply_changed.emit(player_team, supply[player_team])
	for team in range(2):
		if sandbox and team == player_team:
			continue
		var income: float = 1.0 + float(held_by(team)) * 0.6
		if mode == "hold" and team != hold_defender:
			income += 0.8          # the attacker has to pay for an assault
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

func air_strike_ready(team: int) -> bool:
	return air_strike_cd[team] <= 0.0

func use_air_strike(team: int) -> bool:
	if not air_strike_ready(team):
		return false
	air_strike_cd[team] = AIR_STRIKE_COOLDOWN
	EventBus.support_changed.emit(team, "air_strike", false)
	return true

func nuke_ready(team: int) -> bool:
	return not nuke_spent[team]

func use_nuke(team: int) -> bool:
	if nuke_spent[team]:
		return false
	nuke_spent[team] = true
	EventBus.support_changed.emit(team, "nuke", false)
	return true

## How many men this side still has standing. The one number the video's HUD
## shows, and the one players actually track.
func men_alive(team: int, units: Array) -> int:
	var n := 0
	for u in units:
		if u.is_alive() and u.team == team:
			n += u.men_count()
	return n

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

## A command post went down: in destroy mode that ends the battle outright.
func on_objective_destroyed(target: ObjectiveTarget) -> void:
	if finished:
		return
	if mode == "destroy":
		_finish(1 - target.team, "target_destroyed")

# ---------------------------------------------------------------------------
# Victory conditions
# ---------------------------------------------------------------------------

func _check_end(delta: float, units: Array) -> void:
	if sandbox:
		return        # a sandbox never declares a winner
	var alive := [0, 0]
	for u in units:
		if u.is_fighting():
			alive[u.team] += u.men_count()

	# A side with nothing left on the field and nothing left to send loses in
	# every mode — there is no way back from that.
	for team in range(2):
		if tickets[team] <= 0 and alive[team] <= 0:
			_finish(1 - team, "annihilation")
			return

	match mode:
		"elimination":
			_check_elimination(alive)
		"capture":
			_check_capture(delta)
		"hold":
			_check_hold(delta)
		"destroy":
			pass        # decided by on_objective_destroyed, or by the clock
	if finished:
		return
	if not endless and elapsed >= duration:
		_finish(_timeout_winner(alive), "time")

func _check_elimination(alive: Array) -> void:
	for team in range(2):
		if alive[team] <= 0 and tickets[team] < 5:
			_finish(1 - team, "elimination")
			return

## Holding every point for a while ends the battle early; otherwise the point
## count decides it at the final whistle.
func _check_capture(delta: float) -> void:
	for team in range(2):
		if not points.is_empty() and held_by(team) == points.size():
			_sweep_timer[team] += delta
			if _sweep_timer[team] >= ALL_POINTS_WIN_SECONDS:
				_finish(team, "all_points")
				return
		else:
			_sweep_timer[team] = 0.0

func _check_hold(delta: float) -> void:
	if hold_zone == null:
		return
	var attacker: int = 1 - hold_defender
	if hold_zone.owner_team == attacker:
		hold_attacker_timer += delta
		if hold_attacker_timer >= HOLD_WIN_SECONDS:
			_finish(attacker, "zone_taken")
	else:
		hold_attacker_timer = maxf(0.0, hold_attacker_timer - delta * 0.5)

## Who wins when the clock runs out, by mode.
func _timeout_winner(alive: Array) -> int:
	match mode:
		"hold":
			return hold_defender          # surviving the clock is the win
		"destroy":
			# Whichever post took the most damage loses.
			var best := 0
			var worst_health := 2.0
			for team in range(2):
				var t = battle.objective_for(team)
				var health: float = t.health_fraction() if t != null else 1.0
				if health < worst_health:
					worst_health = health
					best = 1 - team
			return best
		"capture":
			if held_by(0) != held_by(1):
				return 0 if held_by(0) > held_by(1) else 1
			return 0 if tickets[0] >= tickets[1] else 1
		_:
			if alive[0] != alive[1]:
				return 0 if alive[0] > alive[1] else 1
			return 0 if tickets[0] >= tickets[1] else 1

func _finish(winner: int, reason: String) -> void:
	if finished:
		return
	finished = true
	var losses := [0.0, 0.0]
	for i in range(2):
		var start: float = maxf(float(initial_tickets[i]), 1.0)
		losses[i] = clampf(1.0 - float(tickets[i]) / start, 0.0, 1.0)
	result = {
		"winner_team": winner,
		"mode": mode,
		"reason": reason,
		"tickets": tickets.duplicate(),
		"points": [held_by(0), held_by(1)],
		"losses": losses,
		"elapsed": elapsed,
	}
	battle.on_battle_finished(result)

func time_left() -> float:
	if endless:
		return INF
	return maxf(0.0, duration - elapsed)

## One line for the HUD describing what this side has to do to win.
func objective_text(team: int) -> String:
	match mode:
		"elimination":
			return "Dushman kuchlarini butunlay yo'q qiling."
		"capture":
			return "A / B / C nuqtalarini egallang va ushlab turing."
		"hold":
			if team == hold_defender:
				return "Hududni vaqt tugaguncha himoya qiling."
			return "Hududni egallab, %d soniya ushlab turing." % int(HOLD_WIN_SECONDS)
		"destroy":
			return "Dushman shtabini yo'q qiling, o'zingiznikini saqlang."
	return ""

## Progress toward the win, 0..1, for the HUD bar. Returns -1 when the mode
## has nothing meaningful to show.
func objective_progress(team: int) -> float:
	match mode:
		"capture":
			if points.is_empty():
				return -1.0
			return float(held_by(team)) / float(points.size())
		"hold":
			if team == hold_defender:
				return 1.0 - clampf(hold_attacker_timer / HOLD_WIN_SECONDS, 0.0, 1.0)
			return clampf(hold_attacker_timer / HOLD_WIN_SECONDS, 0.0, 1.0)
		"destroy":
			var enemy_post = battle.objective_for(1 - team)
			if enemy_post == null:
				return -1.0
			return 1.0 - enemy_post.health_fraction()
		"elimination":
			var start: float = maxf(float(initial_tickets[1 - team]), 1.0)
			return 1.0 - clampf(float(tickets[1 - team]) / start, 0.0, 1.0)
	return -1.0
