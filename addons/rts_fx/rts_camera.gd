## RTS camera rig: WASD / screen-edge pan, mouse wheel zoom, Q/E rotate, explosion shake.
## Add this node to the scene; it creates its own Camera3D.
class_name RtsCamera
extends Node3D

@export var pitch_deg := 55.0
@export var distance := 60.0
@export var min_distance := 20.0
@export var max_distance := 160.0
@export var pan_speed := 0.9        # multiplied by distance
@export var edge_pan := true
@export var fov := 30.0

var camera: Camera3D
var _trauma := 0.0
var _t := 0.0

func _ready() -> void:
	add_to_group("rts_camera")
	camera = Camera3D.new()
	camera.fov = fov
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	_update_cam()

func add_shake(amount: float, at: Vector3) -> void:
	var d := at.distance_to(global_position)
	var fall := clampf(1.0 - d / 140.0, 0.15, 1.0)
	_trauma = clampf(_trauma + amount * fall, 0.0, 1.0)

var _mmb := false

func _unhandled_input(e: InputEvent) -> void:
	# middle mouse drag pans the map
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_MIDDLE:
		_mmb = e.pressed
	if e is InputEventMouseMotion and _mmb:
		var rel: Vector2 = (e as InputEventMouseMotion).relative
		var k := distance * 0.0016
		var move: Vector3 = (global_basis.x * -rel.x + global_basis.z * -rel.y) * k
		move.y = 0
		global_position += move
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(min_distance, distance * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(max_distance, distance * 1.1)

func _process(delta: float) -> void:
	_t += delta
	var dir := Vector2.ZERO
	if Input.is_key_pressed(Keys.physical(KEY_W)): dir.y -= 1
	if Input.is_key_pressed(Keys.physical(KEY_S)): dir.y += 1
	if Input.is_key_pressed(Keys.physical(KEY_A)): dir.x -= 1
	if Input.is_key_pressed(Keys.physical(KEY_D)): dir.x += 1
	if edge_pan and get_viewport().get_window().has_focus():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x < 6: dir.x -= 1
		if mp.x > vs.x - 6: dir.x += 1
		if mp.y < 6: dir.y -= 1
		if mp.y > vs.y - 6: dir.y += 1
	if Input.is_key_pressed(Keys.physical(KEY_Q)): rotate_y(delta * 1.2)
	if Input.is_key_pressed(Keys.physical(KEY_E)): rotate_y(-delta * 1.2)
	if dir != Vector2.ZERO:
		var move := (global_basis.x * dir.x + global_basis.z * dir.y)
		move.y = 0
		global_position += move.normalized() * pan_speed * Settings.camera_speed * distance * delta
	_trauma = max(0.0, _trauma - delta * 0.9)
	# follow the ground so hills don't swallow the view
	var gy := RtsGround.height(global_position.x, global_position.z)
	global_position.y = lerpf(global_position.y, gy, clampf(delta * 3.0, 0.0, 1.0))
	_update_cam()

func _update_cam() -> void:
	var p := deg_to_rad(pitch_deg)
	camera.position = Vector3(0, sin(p) * distance, cos(p) * distance)
	camera.rotation = Vector3(-p, 0, 0)
	var sh := _trauma * _trauma
	if sh > 0.0:
		camera.position += Vector3(sin(_t * 47.0), sin(_t * 39.0 + 1.7), 0) * sh * 0.025 * distance
		camera.rotation.z = sin(_t * 31.0 + 0.5) * sh * 0.03

## Ground point under the mouse (y = ground_y plane).
func mouse_ground_point(ground_y := 0.0) -> Variant:
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	if abs(d.y) < 0.0001:
		return null
	var t := (ground_y - o.y) / d.y
	if t < 0:
		return null
	return o + d * t
