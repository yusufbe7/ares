class_name WorldMapView
extends Control
## The globe as a board: every country drawn and coloured by the bloc holding
## it, with the contested ground marked. Pan with the mouse, zoom with the
## wheel, click a country to select it.

signal country_clicked(id: String)
signal country_hovered(id: String)

var model: WorldModel
var selected: String = ""
var hovered: String = ""
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var show_names: bool = true
var _time: float = 0.0
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO

const LAT_LIMIT := 83.0
const OCEAN := Color(0.055, 0.085, 0.125)
const OCEAN_DEEP := Color(0.035, 0.055, 0.085)
const GRATICULE := Color(0.18, 0.28, 0.38, 0.30)
const BORDER := Color(0.05, 0.07, 0.09, 0.9)

func setup(m: WorldModel) -> void:
	model = m
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

# --- projection -------------------------------------------------------------

func _project(lonlat: Vector2) -> Vector2:
	var x := (lonlat.x + 180.0) / 360.0
	var y := (LAT_LIMIT - clampf(lonlat.y, -LAT_LIMIT, LAT_LIMIT)) / (LAT_LIMIT * 2.0)
	return Vector2(x * size.x, y * size.y) * zoom + pan

func _unproject(p: Vector2) -> Vector2:
	var q := (p - pan) / maxf(zoom, 0.01)
	var lon := q.x / maxf(size.x, 1.0) * 360.0 - 180.0
	var lat := LAT_LIMIT - q.y / maxf(size.y, 1.0) * (LAT_LIMIT * 2.0)
	return Vector2(lon, lat)

# --- input ------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_last = event.position
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var id := country_at(event.position)
			if id != "":
				selected = id
				country_clicked.emit(id)
	elif event is InputEventMouseMotion:
		if _dragging:
			pan += event.position - _drag_last
			_drag_last = event.position
		else:
			var id := country_at(event.position)
			if id != hovered:
				hovered = id
				country_hovered.emit(id)

func _zoom_at(at: Vector2, factor: float) -> void:
	var before := (at - pan) / zoom
	zoom = clampf(zoom * factor, 0.75, 9.0)
	pan = at - before * zoom

func focus_on(id: String) -> void:
	var c = model.country(id)
	if c == null:
		return
	zoom = clampf(zoom, 2.0, 9.0)
	pan = Vector2.ZERO
	pan = size * 0.5 - (_project(c.centre) - pan)

## Which country is under this point. Tested against the real outlines, so a
## click near a coast picks the right side of it.
func country_at(screen_pos: Vector2) -> String:
	if model == null:
		return ""
	var lonlat := _unproject(screen_pos)
	for id in model.order:
		var c = model.countries[id]
		for ring in c.rings:
			if Geometry2D.is_point_in_polygon(lonlat, ring):
				return id
	return ""

# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if model == null:
		return
	_draw_ocean()
	_draw_graticule()
	for id in model.order:
		_draw_country(model.countries[id])
	_draw_markers()
	if selected != "":
		_draw_selection(model.countries[selected])

func _draw_ocean() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), OCEAN_DEEP)
	# A band of lighter water around the equator keeps the globe from reading
	# as one flat sheet of colour.
	var top := _project(Vector2(-180.0, 45.0)).y
	var bottom := _project(Vector2(-180.0, -45.0)).y
	draw_rect(Rect2(Vector2(0, top), Vector2(size.x, maxf(bottom - top, 0.0))), OCEAN)

func _draw_graticule() -> void:
	for lon in range(-180, 181, 30):
		var a := _project(Vector2(float(lon), LAT_LIMIT))
		var b := _project(Vector2(float(lon), -LAT_LIMIT))
		draw_line(a, b, GRATICULE, 1.0)
	for lat in range(-60, 61, 30):
		var a2 := _project(Vector2(-180.0, float(lat)))
		var b2 := _project(Vector2(180.0, float(lat)))
		draw_line(a2, b2, GRATICULE, 1.0)
	var eq_a := _project(Vector2(-180.0, 0.0))
	var eq_b := _project(Vector2(180.0, 0.0))
	draw_line(eq_a, eq_b, Color(0.35, 0.5, 0.6, 0.4), 1.4)

func _draw_country(c) -> void:
	var base := model.faction_color(c.owner)
	var fill := base
	if c.id == hovered:
		fill = base.lightened(0.22)
	if c.contested:
		# Contested ground pulses, so the fronts are visible at a glance.
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.4)
		fill = fill.lerp(Color(0.95, 0.55, 0.25), 0.35 + pulse * 0.25)
	for ring in c.rings:
		var pts := PackedVector2Array()
		for p in ring:
			pts.append(_project(p))
		if pts.size() < 3:
			continue
		draw_colored_polygon(pts, fill)
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, BORDER, 1.0)

func _draw_markers() -> void:
	for id in model.capitals.keys():
		var c = model.country(str(id))
		if c == null:
			continue
		var at := _project(model.capitals[id])
		if at.x < -20 or at.y < -20 or at.x > size.x + 20 or at.y > size.y + 20:
			continue
		var accent := model.faction_accent(c.owner)
		# A diamond for a capital: distinct from the round unit dots in battle.
		var r := 4.0
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0, -r), at + Vector2(r, 0),
			at + Vector2(0, r), at + Vector2(-r, 0)]), accent)
		draw_arc(at, r + 2.5, 0.0, TAU, 12, Color(accent.r, accent.g, accent.b, 0.45), 1.0)

func _draw_selection(c) -> void:
	var accent := model.faction_accent(c.owner)
	for ring in c.rings:
		var pts := PackedVector2Array()
		for p in ring:
			pts.append(_project(p))
		if pts.size() < 3:
			continue
		var outline := PackedVector2Array(pts)
		outline.append(pts[0])
		draw_polyline(outline, Color.WHITE, 2.2)
		draw_polyline(outline, Color(accent.r, accent.g, accent.b, 0.5), 4.0)
