class_name Minimap
extends Control
## Sector radar. The whole battlefield at a glance: your own men, whatever is
## currently spotted, the ground being fought over, and where the camera is
## looking. Clicking it sends the camera there.

signal jump_requested(world_pos: Vector3)

var battle: Battle
var rig: CameraRig

const BG := Color(0.07, 0.11, 0.09, 0.92)
const GRID := Color(0.25, 0.45, 0.32, 0.35)
const EDGE := Color(0.40, 0.75, 0.50, 0.8)

func setup(b: Battle, r: CameraRig) -> void:
	battle = b
	rig = r
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var pressed_click: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	var dragging: bool = event is InputEventMouseMotion \
		and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if pressed_click or dragging:
		jump_requested.emit(_map_to_world(event.position))

func _world_to_map(pos: Vector3) -> Vector2:
	var half := battle.terrain.map_size * 0.5
	var t := Vector2((pos.x + half) / battle.terrain.map_size,
		(pos.z + half) / battle.terrain.map_size)
	return Vector2(t.x * size.x, t.y * size.y)

func _map_to_world(p: Vector2) -> Vector3:
	var half := battle.terrain.map_size * 0.5
	var x := (p.x / maxf(size.x, 1.0)) * battle.terrain.map_size - half
	var z := (p.y / maxf(size.y, 1.0)) * battle.terrain.map_size - half
	return battle.terrain.ground_point(x, z)

func _draw() -> void:
	if battle == null or battle.terrain == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for i in range(1, 4):
		var f := float(i) / 4.0
		draw_line(Vector2(size.x * f, 0), Vector2(size.x * f, size.y), GRID, 1.0)
		draw_line(Vector2(0, size.y * f), Vector2(size.x, size.y * f), GRID, 1.0)

	# Ground worth holding.
	for p in battle.director.points:
		var c := battle.team_color(p.owner_team) if p.owner_team >= 0 else Color(0.7, 0.7, 0.7)
		var at := _world_to_map(p.position)
		var r: float = p.radius / battle.terrain.map_size * size.x
		draw_circle(at, r, Color(c.r, c.g, c.b, 0.22))
		draw_arc(at, r, 0.0, TAU, 20, c, 1.5)
	if battle.director.hold_zone != null:
		var z = battle.director.hold_zone
		var zc := battle.team_color(z.owner_team) if z.owner_team >= 0 else Color.WHITE
		draw_arc(_world_to_map(z.position), z.radius / battle.terrain.map_size * size.x,
			0.0, TAU, 28, zc, 2.0)

	# Command posts, when the battle is about them.
	for t in battle.objectives:
		if t != null and is_instance_valid(t):
			var at2 := _world_to_map(t.global_position)
			draw_rect(Rect2(at2 - Vector2(3, 3), Vector2(6, 6)), battle.team_color(t.team))

	# Everyone we can actually see. Enemies only while spotted, which is what
	# makes the radar worth reading rather than a cheat sheet.
	for u in battle.units:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		var mine: bool = u.team == battle.player_team
		if not mine and not u.visible:
			continue
		var at3 := _world_to_map(u.global_position)
		if u.wounded:
			draw_circle(at3, 2.2, Color(0.95, 0.72, 0.25))
			continue
		var col := battle.team_color(u.team)
		if u.unit_class() == "vehicle":
			draw_rect(Rect2(at3 - Vector2(2, 2), Vector2(4, 4)), col)
		elif u.is_air():
			draw_arc(at3, 3.0, 0.0, TAU, 8, col, 1.2)
		else:
			draw_circle(at3, 1.6, col)

	# Where the camera is looking.
	if rig != null:
		var focus := _world_to_map(rig.target_position)
		var box: float = clampf(rig.zoom / battle.terrain.map_size * size.x * 1.4, 6.0, size.x)
		draw_rect(Rect2(focus - Vector2(box, box) * 0.5, Vector2(box, box)),
			Color(1, 1, 1, 0.65), false, 1.2)
	draw_rect(Rect2(Vector2.ZERO, size), EDGE, false, 1.5)
