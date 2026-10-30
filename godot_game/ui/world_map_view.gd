class_name WorldMapView
extends Control
## The global map: every province is a hex, coloured by its owner. Pan with the
## mouse or WASD, zoom with the wheel, click a province to select it.

signal province_clicked(pid: int, button: int)
signal province_hovered(pid: int)

var world: WorldState = null
var hex_radius: float = 15.0
var pan: Vector2 = Vector2(40, 40)
var selected_province: int = -1
var hovered_province: int = -1
var highlight: Array = []            # province ids drawn with a bright outline
var show_supply: bool = false
var show_terrain: bool = false
var local_nation: String = ""

var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO

const TERRAIN_COLORS := {
	Province.Terrain.OCEAN: Color(0.10, 0.16, 0.26),
	Province.Terrain.PLAINS: Color(0.42, 0.50, 0.30),
	Province.Terrain.HILLS: Color(0.47, 0.44, 0.28),
	Province.Terrain.MOUNTAIN: Color(0.40, 0.40, 0.43),
	Province.Terrain.DESERT: Color(0.70, 0.62, 0.40),
	Province.Terrain.FOREST: Color(0.22, 0.36, 0.24),
	Province.Terrain.VILLAGE: Color(0.50, 0.48, 0.36),
	Province.Terrain.URBAN: Color(0.55, 0.52, 0.50),
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func set_world(w: WorldState) -> void:
	world = w
	queue_redraw()

func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_action_pressed("wm_pan_left"):
		move.x += 1.0
	if Input.is_action_pressed("wm_pan_right"):
		move.x -= 1.0
	if Input.is_action_pressed("wm_pan_up"):
		move.y += 1.0
	if Input.is_action_pressed("wm_pan_down"):
		move.y -= 1.0
	if move != Vector2.ZERO:
		pan += move * 500.0 * delta * Settings.camera_speed
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.12)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_last = event.position
		elif event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			var pid := province_at(event.position)
			if pid >= 0:
				if event.button_index == MOUSE_BUTTON_LEFT:
					selected_province = pid
				province_clicked.emit(pid, event.button_index)
				queue_redraw()
	elif event is InputEventMouseMotion:
		if _dragging:
			pan += event.position - _drag_last
			_drag_last = event.position
			queue_redraw()
		else:
			var pid := province_at(event.position)
			if pid != hovered_province:
				hovered_province = pid
				province_hovered.emit(pid)
				queue_redraw()

func _zoom_at(at: Vector2, factor: float) -> void:
	var before := (at - pan) / hex_radius
	hex_radius = clampf(hex_radius * factor, 6.0, 48.0)
	pan = at - before * hex_radius
	queue_redraw()

func center_on(pid: int) -> void:
	var p := MapGrid.to_pixel(pid, hex_radius)
	pan = size * 0.5 - p
	queue_redraw()

func province_at(screen_pos: Vector2) -> int:
	if world == null:
		return -1
	var local := screen_pos - pan
	# Nearest centre wins: hexes tile tightly enough that this is exact enough
	# for clicking, and far cheaper than a point-in-polygon over 1500 cells.
	var row := int(round(local.y / (1.5 * hex_radius)))
	var best := -1
	var best_d := INF
	for dr in range(-1, 2):
		var r := row + dr
		if r < 0 or r >= MapGrid.HEIGHT:
			continue
		var w := sqrt(3.0) * hex_radius
		var col := int(round(local.x / w - (0.5 if r % 2 == 1 else 0.0)))
		for dc in range(-1, 2):
			var c := col + dc
			if c < 0 or c >= MapGrid.WIDTH:
				continue
			var idx := MapGrid.index(c, r)
			var d := MapGrid.to_pixel(idx, hex_radius).distance_to(local)
			if d < best_d:
				best_d = d
				best = idx
	if best_d > hex_radius * 1.1:
		return -1
	return best

func _draw() -> void:
	if world == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.14))
	var view := Rect2(-pan - Vector2(hex_radius * 2, hex_radius * 2),
		size + Vector2(hex_radius * 4, hex_radius * 4))
	for pid in world.provinces.keys():
		var center := MapGrid.to_pixel(int(pid), hex_radius)
		if not view.has_point(center):
			continue
		var p: Province = world.provinces[pid]
		var pts := MapGrid.corners(center + pan, hex_radius * 0.96)
		draw_colored_polygon(pts, _fill_for(p))
		if p.is_capital:
			draw_circle(center + pan, hex_radius * 0.3, Color(1, 1, 1, 0.85))
		if not p.construction.is_empty():
			draw_circle(center + pan + Vector2(hex_radius * 0.4, -hex_radius * 0.4),
				hex_radius * 0.14, UIKit.WARN)
	_draw_borders()
	_draw_armies()
	_draw_highlights()

func _fill_for(p: Province) -> Color:
	if not p.is_land():
		return TERRAIN_COLORS[Province.Terrain.OCEAN]
	if show_terrain or p.owner_id == "":
		var base: Color = TERRAIN_COLORS.get(p.terrain, Color(0.4, 0.4, 0.4))
		return base if p.owner_id == "" else base.lerp(_owner_color(p), 0.35)
	var c := _owner_color(p)
	if show_supply:
		c = Color(0.8, 0.25, 0.2).lerp(UIKit.ACCENT, clampf(p.supply, 0.0, 1.0))
	# Terrain still reads through the national colour.
	var terrain_tint: Color = TERRAIN_COLORS.get(p.terrain, Color(0.4, 0.4, 0.4))
	c = c.lerp(terrain_tint, 0.28)
	if p.unrest > 0.3:
		c = c.lerp(Color(0.6, 0.2, 0.2), p.unrest * 0.4)
	return c

func _owner_color(p: Province) -> Color:
	var n: Nation = world.nation(p.owner_id)
	return n.color if n != null else Color(0.35, 0.35, 0.35)

func _draw_borders() -> void:
	for pid in world.provinces.keys():
		var p: Province = world.provinces[pid]
		if not p.is_land() or p.owner_id == "":
			continue
		var center := MapGrid.to_pixel(int(pid), hex_radius) + pan
		if center.x < -hex_radius or center.y < -hex_radius or center.x > size.x + hex_radius or center.y > size.y + hex_radius:
			continue
		var corners := MapGrid.corners(center, hex_radius * 0.96)
		var neighbors := MapGrid.neighbors(int(pid))
		for nb in neighbors:
			var other: Province = world.provinces[nb]
			if other.owner_id == p.owner_id:
				continue
			# Draw the shared edge as a line between the two nearest corners.
			var dir := (MapGrid.to_pixel(nb, hex_radius) + pan - center).normalized()
			var best_a := -1
			var best_b := -1
			var best_score := -INF
			for i in range(6):
				var a: Vector2 = corners[i]
				var b: Vector2 = corners[(i + 1) % 6]
				var mid := ((a + b) * 0.5 - center).normalized()
				var s := mid.dot(dir)
				if s > best_score:
					best_score = s
					best_a = i
					best_b = (i + 1) % 6
			if best_a >= 0:
				var at_war: bool = _at_war(p.owner_id, other.owner_id)
				var col := Color(0.95, 0.2, 0.15) if at_war else Color(0.04, 0.05, 0.07)
				draw_line(corners[best_a], corners[best_b], col, 2.0 if at_war else 1.4)

func _at_war(a: String, b: String) -> bool:
	if a == "" or b == "":
		return false
	var na: Nation = world.nation(a)
	return na != null and na.is_at_war_with(b)

func _draw_armies() -> void:
	for a in world.all_armies():
		var p := MapGrid.to_pixel(a.province, hex_radius) + pan
		if p.x < 0 or p.y < 0 or p.x > size.x or p.y > size.y:
			continue
		var n: Nation = world.nation(a.owner_id)
		var col: Color = n.color if n != null else Color.WHITE
		var r := hex_radius * 0.34
		draw_rect(Rect2(p - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), col.darkened(0.3))
		draw_rect(Rect2(p - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), Color(0, 0, 0, 0.6), false, 1.0)
		if a.supply < 0.4:
			draw_circle(p + Vector2(r, -r), hex_radius * 0.12, UIKit.BAD)
		if not a.move_path.is_empty():
			var dest := MapGrid.to_pixel(int(a.move_path[a.move_path.size() - 1]), hex_radius) + pan
			draw_line(p, dest, col, 1.5)

func _draw_highlights() -> void:
	for pid in highlight:
		var c := MapGrid.to_pixel(int(pid), hex_radius) + pan
		draw_polyline(_closed(MapGrid.corners(c, hex_radius * 0.96)), UIKit.WARN, 2.0)
	if selected_province >= 0:
		var c2 := MapGrid.to_pixel(selected_province, hex_radius) + pan
		draw_polyline(_closed(MapGrid.corners(c2, hex_radius * 0.96)), Color.WHITE, 2.5)
	if hovered_province >= 0 and hovered_province != selected_province:
		var c3 := MapGrid.to_pixel(hovered_province, hex_radius) + pan
		draw_polyline(_closed(MapGrid.corners(c3, hex_radius * 0.96)), Color(1, 1, 1, 0.45), 1.5)
	for b in world.pending_battles:
		var c4 := MapGrid.to_pixel(int(b.get("province", 0)), hex_radius) + pan
		draw_circle(c4, hex_radius * 0.5, Color(0.95, 0.25, 0.15, 0.55))

static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if out.size() > 0:
		out.append(out[0])
	return out
