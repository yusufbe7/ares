class_name BattleControls
extends Node
## Selection and orders. The player gives intent, never footsteps: pick units,
## point at a place, a point, an enemy or a house, and the units sort out the
## rest themselves.

enum Pending { NONE, TRENCH, FORTIFICATION, ARTILLERY, AIR_STRIKE, NUKE }

var battle: Battle
var rig: CameraRig
var selected: Array = []
var pending: int = Pending.NONE
var pending_kind: String = ""
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _trench_start: Vector3 = Vector3.ZERO
var _has_trench_start: bool = false

signal selection_box_changed(rect: Rect2, active: bool)
signal build_menu_requested(open: bool)

func setup(b: Battle, r: CameraRig) -> void:
	battle = b
	rig = r

func _unhandled_input(event: InputEvent) -> void:
	if battle == null or battle.director == null or battle.director.finished:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		selection_box_changed.emit(_current_rect(event.position), true)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
			_dragging = true
		else:
			_dragging = false
			selection_box_changed.emit(Rect2(), false)
			var rect := _current_rect(event.position)
			if rect.size.length() < 6.0:
				_click_select(event.position, event.shift_pressed)
			else:
				_box_select(rect, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_order(event.position)

func _current_rect(current: Vector2) -> Rect2:
	var top_left := Vector2(minf(_drag_start.x, current.x), minf(_drag_start.y, current.y))
	var size := (current - _drag_start).abs()
	return Rect2(top_left, size)

func _click_select(screen_pos: Vector2, additive: bool) -> void:
	var u := _unit_at(screen_pos, battle.player_team)
	if u == null:
		if not additive:
			_set_selection([])
		return
	if additive:
		var list := selected.duplicate()
		if list.has(u):
			list.erase(u)
		else:
			list.append(u)
		_set_selection(list)
	else:
		_set_selection([u])

func _box_select(rect: Rect2, additive: bool) -> void:
	var found: Array = []
	for u: BattleUnit in battle.units_of_team(battle.player_team):
		var screen: Vector2 = rig.camera.unproject_position(u.global_position)
		if rect.has_point(screen):
			found.append(u)
	if additive:
		for u in selected:
			if not found.has(u):
				found.append(u)
	_set_selection(found)

## Selecting a saved control group, from a key or from the HUD button.
func select_squad(index: int) -> void:
	if index < 0 or index >= battle.squads.size():
		return
	_set_selection(battle.squads[index].alive_units())
	if not selected.is_empty():
		rig.focus_on(battle.squads[index].center())

func _set_selection(list: Array) -> void:
	for u in selected:
		if is_instance_valid(u):
			u.set_selected(false)
	selected = list.filter(func(u): return is_instance_valid(u) and u.is_alive())
	for u in selected:
		u.set_selected(true)
	EventBus.selection_changed.emit(selected)

func _unit_at(screen_pos: Vector2, team_filter: int = -1) -> BattleUnit:
	var best: BattleUnit = null
	var best_d := 34.0
	for u: BattleUnit in battle.units:
		if not is_instance_valid(u) or not u.is_alive() or not u.visible:
			continue
		if team_filter >= 0 and u.team != team_filter:
			continue
		if rig.camera.is_position_behind(u.global_position):
			continue
		var d: float = rig.camera.unproject_position(u.global_position).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = u
	return best

func _building_at(world_pos: Vector3):
	for h in battle.buildings:
		if is_instance_valid(h) and h.global_position.distance_to(world_pos) < maxf(h.dims.x, h.dims.z):
			return h
	return null

func _issue_order(screen_pos: Vector2) -> void:
	var ground := rig.ground_from_screen(screen_pos)
	if pending == Pending.ARTILLERY:
		_fire_support(ground)
		return
	if pending == Pending.AIR_STRIKE:
		pending = Pending.NONE
		if battle.director.use_air_strike(battle.player_team):
			battle.call_air_strike(ground, battle.player_team)
		else:
			GameState.notify("Aviatsiya hali tayyor emas.", "warn")
		return
	if pending == Pending.NUKE:
		pending = Pending.NONE
		if battle.director.use_nuke(battle.player_team):
			battle.call_nuke(ground, battle.player_team)
		else:
			GameState.notify("Yadro zarbasi ishlatib bo'lingan.", "warn")
		return
	if pending == Pending.TRENCH:
		_trench_order(ground)
		return
	if pending == Pending.FORTIFICATION:
		battle.place_fortification(pending_kind, ground, Vector3.FORWARD, battle.player_team)
		pending = Pending.NONE
		return
	if selected.is_empty():
		return
	var enemy := _unit_at(screen_pos, 1 - battle.player_team)
	if enemy != null:
		for u in selected:
			u.order_attack(enemy)
		return
	var house = _building_at(ground)
	if house != null:
		for u in selected:
			u.order_attack_building(house)
		return
	for p: ObjectivePoint in battle.director.points:
		if ground.distance_to(p.position) < p.radius:
			_group_of_selection().order_capture(p)
			return
	_group_of_selection().order_move(ground, battle.terrain)

## Orders go through a temporary Squad so that a hand-picked selection spreads
## out the same way a saved control group does.
func _group_of_selection() -> Squad:
	var s := Squad.new()
	s.index = -1
	for u in selected:
		s.units.append(u)
	return s

func _trench_order(ground: Vector3) -> void:
	if not _has_trench_start:
		_trench_start = ground
		_has_trench_start = true
		GameState.notify("Xandaqning oxirini belgilang.", "info")
		return
	if battle.dig_trench(_trench_start, ground, battle.player_team):
		GameState.notify("Xandaq qazildi.", "good")
	else:
		GameState.notify("Ta'minot yetarli emas.", "bad")
	_has_trench_start = false
	pending = Pending.NONE

func _fire_support(ground: Vector3) -> void:
	if battle.director.pay(battle.player_team, 40.0):
		battle.call_artillery_strike(Vector3.ZERO, ground, battle.player_team, null)
	else:
		GameState.notify("Artilleriya uchun ta'minot yetmaydi.", "bad")
	pending = Pending.NONE

func _handle_key(event: InputEventKey) -> void:
	var team := battle.player_team
	# Control groups 1..5: Ctrl assigns, a bare number selects.
	if event.keycode >= KEY_1 and event.keycode <= KEY_5:
		var idx: int = event.keycode - KEY_1
		if event.ctrl_pressed:
			battle.squads[idx].units.clear()
			for u in selected:
				battle.squads[idx].add(u)
			GameState.notify("%d-guruh tuzildi (%d)." % [idx + 1, selected.size()], "info")
		else:
			select_squad(idx)
		return
	if Input.is_action_just_pressed("bf_reinforce"):
		if battle.director.reinforcement_ready(team) and battle.director.pay(team, 10.0):
			battle.director.start_reinforce_cooldown(team)
			battle.spawn_reinforcement_squad(team)
			GameState.notify("Otryad yo'lga chiqdi.", "good")
		else:
			GameState.notify("Otryad hali tayyor emas.", "warn")
	elif Input.is_action_just_pressed("bf_call_tank"):
		if battle.director.pay(team, 120.0):
			battle.spawn_support_vehicle(team, "veh_tank")
			GameState.notify("Tank chaqirildi.", "good")
		else:
			GameState.notify("Ta'minot yetarli emas (120 kerak).", "bad")
	elif Input.is_action_just_pressed("bf_call_artillery"):
		pending = Pending.ARTILLERY
		GameState.notify("Artilleriya uchun nuqtani belgilang (40 ta'minot).", "info")
	elif Input.is_action_just_pressed("bf_air_strike"):
		if battle.director.air_strike_ready(team):
			pending = Pending.AIR_STRIKE
			GameState.notify("Aviazarba uchun nishonni belgilang.", "info")
		else:
			GameState.notify("Aviatsiya %d soniyadan keyin tayyor."
				% int(battle.director.air_strike_cd[team]), "warn")
	elif Input.is_action_just_pressed("bf_nuke"):
		if battle.director.nuke_ready(team):
			pending = Pending.NUKE
			GameState.notify("YADRO ZARBASI — nishonni belgilang.", "bad")
		else:
			GameState.notify("Yadro zarbasi ishlatib bo'lingan.", "warn")
	elif Input.is_action_just_pressed("bf_build_menu"):
		build_menu_requested.emit(true)
	elif Input.is_action_just_pressed("bf_dig_trench"):
		pending = Pending.TRENCH
		_has_trench_start = false
		GameState.notify("Xandaqning boshini belgilang.", "info")
	elif Input.is_action_just_pressed("bf_grenade"):
		_throw_grenade()
	elif Input.is_action_just_pressed("bf_rocket"):
		_fire_rpg()
	elif Input.is_action_just_pressed("bf_halt"):
		for u in selected:
			u.order_hold()
	elif Input.is_action_just_pressed("bf_focus"):
		if not selected.is_empty():
			var sum := Vector3.ZERO
			for u in selected:
				sum += u.global_position
			rig.focus_on(sum / float(selected.size()))
	elif Input.is_action_just_pressed("bf_prone"):
		for u in selected:
			u.order_stance(BattleUnit.Stance.PRONE)
	elif Input.is_action_just_pressed("bf_crouch"):
		for u in selected:
			u.order_stance(BattleUnit.Stance.CROUCH)
	elif Input.is_action_just_pressed("bf_stand"):
		for u in selected:
			u.order_stance(BattleUnit.Stance.STAND)
	elif Input.is_action_just_pressed("bf_recon"):
		if battle.director.pay(team, 25.0):
			battle.spawn_support_vehicle(team, "air_drone")
			GameState.notify("Razvedka droni uchdi.", "good")
		else:
			GameState.notify("Dron uchun ta'minot yetmaydi.", "bad")

func _throw_grenade() -> void:
	for u in selected:
		if u.attack_target != null and u.global_position.distance_to(u.attack_target.global_position) < 30.0:
			battle.spawn_explosion(u.attack_target.global_position, 5.0, 70.0, u.team, false)
			return
	GameState.notify("Granata uchun yaqin nishon yo'q.", "warn")

func _fire_rpg() -> void:
	for u in selected:
		if u.attack_target != null:
			battle.spawn_rocket(u.muzzle_position(), u.attack_target, u.team, 260.0)
			return
	GameState.notify("RPG uchun nishon tanlanmagan.", "warn")

func build_fortification(kind: String) -> void:
	pending = Pending.FORTIFICATION
	pending_kind = kind
	GameState.notify("Joyni belgilang.", "info")
