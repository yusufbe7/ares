class_name CameraRig
extends Node3D
## RTS camera: WASD to pan, wheel to zoom, Q/E to turn, and a key that snaps to
## whatever is selected.

var camera: Camera3D
var target_position: Vector3 = Vector3.ZERO
var zoom: float = 115.0
var yaw: float = 0.0
var pitch: float = -56.0
var terrain: BattleTerrain = null
var edge_scroll: bool = true

const MIN_ZOOM := 18.0
const MAX_ZOOM := 340.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 3000.0
	add_child(camera)
	_apply()

func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_action_pressed("bf_cam_fwd"):
		move.z -= 1.0
	if Input.is_action_pressed("bf_cam_back"):
		move.z += 1.0
	if Input.is_action_pressed("bf_cam_left"):
		move.x -= 1.0
	if Input.is_action_pressed("bf_cam_right"):
		move.x += 1.0
	if Input.is_action_pressed("bf_cam_rot_l"):
		yaw -= delta * 60.0
	if Input.is_action_pressed("bf_cam_rot_r"):
		yaw += delta * 60.0
	if move.length() > 0.0:
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		var speed: float = Settings.camera_speed * (28.0 + zoom * 0.45)
		target_position += basis * move.normalized() * speed * delta
	if terrain != null:
		target_position = terrain.clamp_to_map(target_position)
		target_position.y = terrain.height_at(target_position.x, target_position.z)
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, MIN_ZOOM, MAX_ZOOM)

func focus_on(pos: Vector3) -> void:
	target_position = pos

func _apply() -> void:
	if camera == null:
		return
	var basis := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var offset: Vector3 = basis * Vector3(0, 0, zoom)
	camera.global_position = target_position + offset
	camera.look_at(target_position, Vector3.UP)

## Screen point to a point on the ground, used by every click order.
func ground_from_screen(screen_pos: Vector2) -> Vector3:
	if camera == null or terrain == null:
		return Vector3.ZERO
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	# March the ray until it is under the terrain, then bisect.
	var t := 0.0
	var step := 4.0
	var last := from
	for i in range(400):
		t += step
		var p := from + dir * t
		if p.y <= terrain.height_at(p.x, p.z):
			var lo := last
			var hi := p
			for j in range(12):
				var mid := (lo + hi) * 0.5
				if mid.y <= terrain.height_at(mid.x, mid.z):
					hi = mid
				else:
					lo = mid
			return hi
		last = p
	return from + dir * 400.0
