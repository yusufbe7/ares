## Player control: drag a box to select, click a soldier to select his whole squad,
## right-click to move (formation), attack, or send soldiers to help on a construction site.
##   Ctrl+1..9 save a group, 1..9 recall it (twice = camera jumps there)
##   G grenade, R RPG, Z/X/C prone/crouch/stand, H halt, F focus camera
class_name RtsCommander
extends Node

signal selection_changed

var demo: Node3D
var selection: Array = []
var groups := {}
var enabled := true
var _press := Vector2.ZERO
var _pressing := false
var _box: BoxDraw
var _last_click_t := 0.0
var _last_group := -1
var _last_group_t := 0.0
var _assaults: Array = []          # [{unit, target}] soldiers sent to blow up a building
var _assault_t := 0.0


class BoxDraw extends Control:
	var r := Rect2()
	func _draw() -> void:
		if r.size.length() < 4.0:
			return
		draw_rect(r, Color(0.45, 1.0, 0.6, 0.12), true)
		draw_rect(r, Color(0.55, 1.0, 0.65, 0.9), false, 1.5)


## Shield badge floating over every squad (like the RTS dev log): squad letter + men alive.
## Click it to select the squad; it turns green while the squad is selected.
class SquadMarks extends Control:
	var cmd
	var rects := {}            # squad id -> Rect2 on screen
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		rects.clear()
		if DisplayServer.get_name() == "headless":
			return
		if cmd == null or cmd.demo == null or cmd.demo.cam == null:
			return
		var cam: Camera3D = cmd.demo.cam.camera
		var groups := {}
		for u in cmd._units():
			if u is RtsSoldier and u.has_meta("squad"):
				var id: int = u.get_meta("squad")
				if not groups.has(id):
					groups[id] = []
				groups[id].append(u)
		var font := ThemeDB.fallback_font
		for id in groups:
			var men: Array = groups[id]
			var c := Vector3.ZERO
			var top := -INF
			for u in men:
				c += u.global_position
				top = maxf(top, u.global_position.y)
			c /= men.size()
			c.y = top + 3.2
			if cam.is_position_behind(c):
				continue
			var sp := cam.unproject_position(c)
			if not sp.is_finite() or not get_rect().grow(40.0).has_point(sp):
				continue
			var sel: bool = men.any(func(u): return cmd.selection.has(u))
			var w := 22.0; var h := 26.0
			var pts := PackedVector2Array([sp + Vector2(-w * 0.5, -h * 0.5), sp + Vector2(w * 0.5, -h * 0.5), sp + Vector2(w * 0.5, h * 0.05),
				sp + Vector2(0, h * 0.5), sp + Vector2(-w * 0.5, h * 0.05)])
			draw_colored_polygon(pts, Color(0.16, 0.2, 0.12, 0.88) if not sel else Color(0.12, 0.32, 0.16, 0.95))
			var edge := Color(0.55, 1.0, 0.6) if sel else Color(0.85, 0.8, 0.62)
			var ring := pts.duplicate(); ring.append(pts[0])
			draw_polyline(ring, edge, 1.6, true)
			var nm: String = cmd.demo._squads[id] if id < cmd.demo._squads.size() else "S"
			var letter := nm.substr(0, 1).to_upper()
			draw_string(font, sp + Vector2(-w * 0.5, 1), letter, HORIZONTAL_ALIGNMENT_CENTER, w, 14, edge)
			draw_string(font, sp + Vector2(-w * 0.5 - 6, h * 0.5 + 12), str(men.size()), HORIZONTAL_ALIGNMENT_CENTER, w + 12, 11, Color(1, 1, 1, 0.85))
			rects[id] = Rect2(sp - Vector2(w, h) * 0.5, Vector2(w, h))


var _marks: SquadMarks


func _mark_at(mp: Vector2) -> int:
	if _marks == null:
		return -1
	for id in _marks.rects:
		if (_marks.rects[id] as Rect2).grow(3.0).has_point(mp):
			return id
	return -1


func setup(p_demo: Node3D) -> void:
	demo = p_demo
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	_box = BoxDraw.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_box)
	_marks = SquadMarks.new()
	_marks.cmd = self
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_marks)


# ------------------------------------------------------------------ helpers
static func is_mine(n) -> bool:
	if not is_instance_valid(n) or not (n is Node3D):
		return false
	if n is RtsSoldier:
		return n.team == 0 and n.is_commandable()
	if n is RtsTank:
		return n.team == 0 and not n.destroyed
	return (n as Node).is_in_group("player_units")


func _units() -> Array:
	var out: Array = []
	for n in demo.get_tree().get_nodes_in_group("player_units"):
		if is_mine(n):
			out.append(n)
	return out


func _screen(n: Node3D) -> Variant:
	var cam: Camera3D = demo.cam.camera
	var p := n.global_position + Vector3.UP * 1.0
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


func _pick(mp: Vector2, pool: Array, max_px := 26.0) -> Node3D:
	var best: Node3D = null
	var bd := max_px
	for n in pool:
		var sp = _screen(n)
		if sp == null:
			continue
		var r := max_px if n is RtsSoldier else max_px * 1.8
		var d: float = (sp as Vector2).distance_to(mp)
		if d < bd and d < r:
			bd = d; best = n
	return best


func set_selection(arr: Array) -> void:
	for n in selection:
		if is_instance_valid(n) and n is RtsSoldier:
			n.selected = false
		elif is_instance_valid(n) and n.has_method("set_selected"):
			n.set_selected(false)
	selection = arr.filter(func(n): return is_mine(n))
	for n in selection:
		if n is RtsSoldier:
			n.selected = true
		elif n.has_method("set_selected"):
			n.set_selected(true)
		else:
			_vehicle_ring(n, true)
	for n in _units():
		if not selection.has(n) and not (n is RtsSoldier):
			_vehicle_ring(n, false)
	selection_changed.emit()


func _vehicle_ring(n: Node3D, on: bool) -> void:
	var r := n.get_node_or_null("SelRing") as MeshInstance3D
	if r == null and on:
		r = MeshInstance3D.new()
		r.name = "SelRing"
		var tm := TorusMesh.new()
		tm.inner_radius = 3.4; tm.outer_radius = 3.7; tm.rings = 32; tm.ring_segments = 6
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 1.0, 0.55)
		m.no_depth_test = true
		tm.material = m
		r.mesh = tm
		r.scale = Vector3(1, 0.1, 1)
		r.position.y = 0.2
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(r)
	if r:
		r.visible = on


func soldiers_selected() -> Array:
	return selection.filter(func(n): return is_instance_valid(n) and n is RtsSoldier and n.is_commandable())


func squads_in(arr: Array) -> int:
	var ids := {}
	for n in arr:
		if n is RtsSoldier:
			ids[n.get_meta("squad", -1)] = true
	return ids.size()


# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if not enabled or demo == null or demo.cam == null:
		return
	if demo.placer and demo.placer.active:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_pressing = true
			elif _pressing:
				_pressing = false
				_box.r = Rect2(); _box.queue_redraw()
				if _press.distance_to(mb.position) > 8.0:
					_box_select(Rect2(_press, mb.position - _press).abs(), mb.shift_pressed)
				else:
					_click_select(mb.position, mb.shift_pressed, mb.double_click)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_command(mb.position, mb.shift_pressed)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and _pressing:
		_box.r = Rect2(_press, (e as InputEventMouseMotion).position - _press).abs()
		_box.queue_redraw()
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e as InputEventKey)


func _box_select(r: Rect2, add: bool) -> void:
	var picked: Array = selection.duplicate() if add else []
	for n in _units():
		var sp = _screen(n)
		if sp != null and r.has_point(sp) and not picked.has(n):
			picked.append(n)
	set_selection(picked)


func _click_select(mp: Vector2, add: bool, dbl: bool) -> void:
	var sid := _mark_at(mp)
	if sid >= 0:
		var sq: Array = selection.duplicate() if add else []
		for u in _units():
			if u is RtsSoldier and u.get_meta("squad", -2) == sid and not sq.has(u):
				sq.append(u)
		set_selection(sq)
		return
	var n := _pick(mp, _units())
	if n == null:
		if not add:
			set_selection([])
		return
	var picked: Array = selection.duplicate() if add else []
	if n is RtsSoldier and dbl:
		# double click: every soldier on screen
		for u in _units():
			if u is RtsSoldier and _screen(u) != null and Rect2(Vector2.ZERO, demo.get_viewport().get_visible_rect().size).has_point(_screen(u)):
				if not picked.has(u): picked.append(u)
	elif n is RtsSoldier and n.has_meta("squad"):
		for u in _units():
			if u is RtsSoldier and u.get_meta("squad", -2) == n.get_meta("squad") and not picked.has(u):
				picked.append(u)
	elif not picked.has(n):
		picked.append(n)
	set_selection(picked)


func _key(k: InputEventKey) -> void:
	var p = demo._mouse_point()
	var men := soldiers_selected()
	if k.keycode >= KEY_1 and k.keycode <= KEY_9 and not demo.debug_keys:
		var g := k.keycode - KEY_0
		if k.ctrl_pressed:
			groups[g] = selection.duplicate()
			demo.notify("Group %d set (%d units)" % [g, selection.size()])
		elif groups.has(g):
			set_selection(groups[g])
			if _last_group == g and Time.get_ticks_msec() / 1000.0 - _last_group_t < 0.5:
				focus()
			_last_group = g
			_last_group_t = Time.get_ticks_msec() / 1000.0
		get_viewport().set_input_as_handled()
		return
	match Keys.logical(k.keycode):      # tugmalar Settings > Controls da almashtiriladi
		KEY_G:
			var s := _closest(men, p)
			if s and p != null: s.throw_grenade(p)
		KEY_T:
			var rp := men.filter(func(m): return m.rpg_rounds > 0)
			var s := _closest(rp if not rp.is_empty() else men, p)
			if s and p != null:
				if s.rpg_rounds > 0: s.rpg_rounds -= 1
				s.fire_rpg(p)
		KEY_Z, KEY_X, KEY_C:
			var stn: int = {KEY_Z: 2, KEY_X: 1, KEY_C: 0}[k.keycode]
			for s in men:
				s.stance = stn
				s._play(s._idle_anim() if s.state != RtsSoldier.State.SHOOT else s._shoot_anim(), 0.25)
		KEY_H:
			for n in selection:
				if n is RtsSoldier:
					n.stop_work(); n.move_to(n.global_position)
				elif n.has_method("stop"):
					n.stop()
		KEY_F:
			focus()
		_:
			return
	get_viewport().set_input_as_handled()


func focus() -> void:
	if selection.is_empty():
		return
	var c := Vector3.ZERO
	for n in selection:
		c += (n as Node3D).global_position
	c /= selection.size()
	demo.cam.position = Vector3(c.x, demo.ground_height(c.x, c.z), c.z)


func _closest(arr: Array, p) -> RtsSoldier:
	if p == null: return null
	var best: RtsSoldier = null
	var bd := INF
	for s in arr:
		var d: float = (s as Node3D).global_position.distance_to(p)
		if d < bd: bd = d; best = s
	return best


# ------------------------------------------------------------------ orders
func _command(mp: Vector2, queue: bool) -> void:
	selection = selection.filter(func(n): return is_mine(n))
	if selection.is_empty():
		return
	var p = demo._mouse_point()
	# enemy soldier under the cursor?
	var foes: Array = demo.get_tree().get_nodes_in_group("enemies").filter(func(e): return e is RtsSoldier and e.can_fight())
	foes += demo.get_tree().get_nodes_in_group("tanks").filter(func(t): return t.team != 0 and not t.destroyed)
	var foe := _pick(mp, foes, 22.0)
	var site := _structure_at(p)
	var tr := _trench_at(p)
	if foe:
		_attack(foe)
		marker(foe.global_position, Color(1, 0.3, 0.25))
	elif tr and not tr.built:
		var men0 := soldiers_selected()
		tr.assign(men0)
		lines(men0, tr.global_position, Color(0.45, 1.0, 0.6, 0.9))
		demo.notify("%d soldiers sent to dig" % men0.size())
	elif tr and tr.built:
		_man_trench(tr)
		marker(tr.global_position, Color(0.45, 1.0, 0.55))
	elif site and site.team == 0 and not site.built:
		var men := soldiers_selected()
		site.assign(men)
		lines(men, site.global_position, Color(0.45, 1.0, 0.6, 0.9))
		demo.notify("%d soldiers sent to build the %s" % [men.size(), site.display_name()])
		marker(site.global_position, Color(1, 0.65, 0.2))
	elif site and site.team != 0:
		_attack_structure(site)
		marker(site.global_position, Color(1, 0.3, 0.25))
	elif p != null and demo.mode_node != null and demo.mode_node.has_method("zone_at") and demo.mode_node.zone_at(p) != null and not soldiers_selected().is_empty():
		_take_zone(demo.mode_node.zone_at(p))
	elif p != null and demo.has_method("house_under_mouse") and demo.house_under_mouse() != null:
		_house_order(demo.house_under_mouse(), p)
	elif p != null:
		move_selection(p)
		lines(selection, p, Color(0.45, 1.0, 0.6, 0.6))
		marker(p, Color(0.45, 1.0, 0.55))


func _trench_at(p) -> RtsTrench:
	if p == null:
		return null
	var best: RtsTrench = null
	var bd := RtsTrench.HALF_W + 1.2
	for t in demo.get_tree().get_nodes_in_group("trenches_0"):
		var d: float = t.distance_to(p)
		if d < bd: bd = d; best = t
	return best


## Selected soldiers jump into the trench, one per fighting position (nearest trenches first).
func _man_trench(tr: RtsTrench) -> void:
	var spots: Array = tr.fighting_positions()
	# connected trenches nearby add their positions too
	for t in demo.get_tree().get_nodes_in_group("trenches_0"):
		if t != tr and t.built and t.distance_to(tr.global_position) < 40.0:
			spots += t.fighting_positions()
	var men := soldiers_selected()
	spots.sort_custom(func(x, y): return x.distance_to(tr.global_position) < y.distance_to(tr.global_position))
	for i in men.size():
		var s: RtsSoldier = men[i]
		s.stop_work()
		s.move_to(spots[i % maxi(1, spots.size())] if not spots.is_empty() else tr.global_position)


func _structure_at(p) -> RtsStructure:
	if p == null:
		return null
	for s in demo.get_tree().get_nodes_in_group("structures"):
		var st := s as RtsStructure
		var lp := st.to_local(p)
		var sz: Vector2 = st.def.size
		if absf(lp.x) < sz.x * 0.5 + 1.0 and absf(lp.z) < sz.y * 0.5 + 1.0:
			return st
	return null


func move_selection(p: Vector3) -> void:
	var men := soldiers_selected()
	var others := selection.filter(func(n): return not (n is RtsSoldier))
	if not men.is_empty():
		var c := Vector3.ZERO
		for s in men: c += s.global_position
		c /= men.size()
		var fwd := (p - c); fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.5 else Vector3.FORWARD
		var right := fwd.cross(Vector3.UP).normalized()
		var cols := mini(4, men.size())
		# keep squads together: sort by squad then by distance
		men.sort_custom(func(a, b): return a.get_meta("squad", 0) < b.get_meta("squad", 0))
		for i in men.size():
			var row := i / cols
			var col := i % cols
			var off := right * ((col - (cols - 1) * 0.5) * 2.6) - fwd * (row * 2.8)
			var s: RtsSoldier = men[i]
			s.stop_work()
			s.objective = null                  # an explicit order: hold where you are sent
			s.move_to(p + off)
	for i in others.size():
		var n: Node3D = others[i]
		var off := Vector3((i - (others.size() - 1) * 0.5) * 9.0, 0, 0)
		if n.has_method("move_to"):
			n.move_to(p + off)


func _attack(foe: Node3D) -> void:
	for n in selection:
		if n is RtsSoldier:
			n.attack(foe)
		elif n is RtsTank:
			n.order_fire(foe.global_position)
		elif n is RtsHelicopter:
			n.fire_rockets(foe.global_position, 6)


func _attack_structure(st: RtsStructure) -> void:
	var men := soldiers_selected()
	for n in selection:
		if n is RtsTank:
			n.order_fire(st.global_position + Vector3.UP)
		elif n is RtsHelicopter:
			n.fire_rockets(st.global_position, 8)
	# infantry: RPG men fire, two sappers run in and set charges, the rest cover them
	var sappers := 0
	for s in men:
		if s.rpg_rounds > 0 and s.global_position.distance_to(st.global_position) < 70.0:
			s.rpg_rounds -= 1
			s.fire_rpg(st.global_position + Vector3.UP * 1.5)
		elif sappers < 2:
			sappers += 1
			var dir: Vector3 = (s.global_position - st.global_position)
			dir.y = 0
			var sz: Vector2 = st.def.size
			s.move_to(st.global_position + dir.normalized() * (maxf(sz.x, sz.y) * 0.5 + 1.5))
			_assaults.append({"unit": s, "target": st})
		else:
			var dir2: Vector3 = (s.global_position - st.global_position)
			dir2.y = 0
			s.move_to(st.global_position + dir2.normalized() * 25.0)


func _process(delta: float) -> void:
	_assault_t -= delta
	if _assault_t > 0.0:
		return
	_assault_t = 0.4
	var keep: Array = []
	for a in _assaults:
		var s: RtsSoldier = a.unit
		var st: RtsStructure = a.target
		if not is_instance_valid(s) or not is_instance_valid(st) or st.dead or s.state == RtsSoldier.State.DEAD:
			continue
		var sz: Vector2 = st.def.size
		if s.state != RtsSoldier.State.MOVE and s.global_position.distance_to(st.global_position) < maxf(sz.x, sz.y) * 0.5 + 4.0:
			s.plant_charge(st)
		elif s.can_fight():
			keep.append(a)
	_assaults = keep
	# forget dead units
	if selection.any(func(n): return not is_mine(n)):
		set_selection(selection)


## Order lines from each unit to the target (like the green build beams in Defilade).
func lines(units: Array, to: Vector3, col: Color) -> void:
	if units.is_empty():
		return
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	var tgt := Vector3(to.x, demo.ground_height(to.x, to.z) + 0.6, to.z)
	for u in units:
		if not is_instance_valid(u):
			continue
		for k in 3:          # three slightly offset lines read as one thick beam
			var o := Vector3(0.06 * (k - 1), 0, 0)
			im.surface_add_vertex((u as Node3D).global_position + Vector3.UP * 1.0 + o)
			im.surface_add_vertex(tgt + o)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	demo.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 1.1)
	tw.tween_callback(mi.queue_free)


## Little ring that flashes where an order went.
func marker(p: Vector3, col: Color) -> void:
	var r := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9; tm.outer_radius = 1.05; tm.rings = 32; tm.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	tm.material = m
	r.mesh = tm
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	demo.add_child(r)
	r.global_position = Vector3(p.x, demo.ground_height(p.x, p.z) + 0.15, p.z)
	r.scale = Vector3(2.0, 0.2, 2.0)
	var tw := r.create_tween()
	tw.set_parallel()
	tw.tween_property(r, "scale", Vector3(0.4, 0.2, 0.4), 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(r.queue_free)


## Right-click on a village house: tanks and the gunship shell / rocket that wall,
## infantry spread out into cover along its walls (rubble counts as cover too).
func _house_order(house: Node3D, p: Vector3) -> void:
	var heavy := false
	for n in selection:
		if n is RtsTank:
			n.order_fire(p)
			heavy = true
		elif n is RtsHelicopter:
			n.fire_rockets(p, 6)
			heavy = true
	var men := soldiers_selected()
	if not men.is_empty():
		var spots: Array = house.cover_points()
		var c := Vector3.ZERO
		for s in men: c += s.global_position
		c /= men.size()
		spots.sort_custom(func(a, b): return a.global_position.distance_to(c) < b.global_position.distance_to(c))
		for i in men.size():
			var s: RtsSoldier = men[i]
			s.stop_work()
			s.move_to(spots[i % spots.size()].global_position if not spots.is_empty() else p)
		lines(men, house.global_position if house.get("center") == null else house.center, Color(0.45, 1.0, 0.6, 0.6))
	marker(p, Color(1, 0.3, 0.25) if heavy else Color(0.45, 1.0, 0.55))


## Right-click inside a capture zone: "take that point". The squads bound forward cover to cover
## by themselves and spread over the zone; vehicles drive to its edge.
func _take_zone(z: Dictionary) -> void:
	var men := soldiers_selected()
	for i in men.size():
		var s: RtsSoldier = men[i]
		s.stop_work()
		var a := TAU * float(i) / maxf(1.0, men.size())
		s.objective = z.pos + Vector3(cos(a), 0, sin(a)) * z.r * randf_range(0.2, 0.55)
		s._idle_t = 2.0
		s._order_t = 0.0
		s._advance()
	for n in selection:
		if not (n is RtsSoldier) and n.has_method("move_to"):
			var d: Vector3 = (n.global_position - z.pos)
			d.y = 0
			n.move_to(z.pos + d.normalized() * z.r * 0.8)
	lines(men, z.pos, Color(0.45, 0.75, 1.0, 0.7))
	marker(z.pos, Color(0.45, 0.75, 1.0))
	demo.notify("%d men sent to take point %s" % [men.size(), z.name])
