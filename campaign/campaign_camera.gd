## Strategik xarita kamerasi: tepadan, biroz burchak ostida (izometrikka yaqin).
## Sichqoncha bilan surish: chap tugmani bosib sudrash yoki o'rta tugma; WASD / strelkalar; ekran cheti.
## G'ildirak: yaqinlashtirish / uzoqlashtirish (yaqinda kamera pastroq egiladi). Xarita chegarasidan chiqmaydi.
class_name CampaignCamera
extends Node3D

signal dragged

@export var min_distance := 3.0          ## yaqinda yer va okean to'lqinlari ko'rinadi
@export var max_distance := 150.0
@export var distance := 70.0
@export var bounds := Rect2(-129, -54, 258, 108)       ## xarita (x, z) chegarasi
var camera: Camera3D
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_moved := false
var _target_dist := 70.0
var picker: Callable                    ## ekran nuqtasi -> yer nuqtasi (CampaignMap.pick)
var _fly := false
var _fly_to := Vector3.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 32.0
	camera.far = 1000.0
	add_child(camera)
	camera.make_current()
	_target_dist = distance
	_update()


func pitch() -> float:
	# uzoqda tepadan qaraydi, yaqinlashganda egilib ufqqa yaqinlashadi
	var t := inverse_lerp(min_distance, max_distance, distance)
	return deg_to_rad(lerpf(42.0, 62.0, clampf(t, 0.0, 1.0)))


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		# ikki marta bosish: o'sha joyga uchib borib yaqinlashadi; g'ildirak: sichqoncha tomonga yaqinlashadi
		if mb.pressed and picker.is_valid() and (mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT \
				or mb.button_index == MOUSE_BUTTON_WHEEL_UP and _target_dist > min_distance + 0.1):
			var p: Variant = picker.call(mb.position)
			if p != null and mb.double_click:
				fly_to(p, maxf(min_distance, distance * 0.3))
			elif p != null:
				nudge_towards(p, 0.12)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_target_dist = maxf(min_distance, _target_dist * 0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_target_dist = minf(max_distance, _target_dist / 0.88)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.pressed
			if mb.pressed:
				_drag_from = mb.position
				_drag_moved = false
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		if _drag_moved or mm.position.distance_to(_drag_from) > 6.0:
			if not _drag_moved:
				_drag_moved = true
				dragged.emit()
			var k := distance * 0.0019
			position += Vector3(-mm.relative.x, 0, -mm.relative.y) * k
			_clamp()


## Chap tugma bosilib, sudrash bo'lmagan bo'lsa - bu oddiy bosish (tanlash).
func was_drag() -> bool:
	return _drag_moved


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(Keys.physical(KEY_W)) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(Keys.physical(KEY_S)) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if Input.is_key_pressed(Keys.physical(KEY_A)) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(Keys.physical(KEY_D)) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if get_viewport().get_window().has_focus() and DisplayServer.get_name() != "headless":
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x < 4: dir.x -= 1
		if mp.x > vs.x - 4: dir.x += 1
		if mp.y < 4: dir.y -= 1
		if mp.y > vs.y - 4: dir.y += 1
	if dir != Vector2.ZERO:
		position += Vector3(dir.x, 0, dir.y).normalized() * distance * 0.9 * Settings.camera_speed * delta
	if dir != Vector2.ZERO or _drag_moved and _drag:
		_fly = false
	if _fly:
		position = position.lerp(_fly_to, clampf(delta * 4.0, 0.0, 1.0))
		if position.distance_to(_fly_to) < 0.02:
			_fly = false
	distance = lerpf(distance, _target_dist, clampf(delta * 8.0, 0.0, 1.0))
	_clamp()
	_update()


func _clamp() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func _update() -> void:
	var p := pitch()
	camera.position = Vector3(0, sin(p) * distance, cos(p) * distance)
	camera.rotation = Vector3(-p, 0, 0)


## Silliq uchib borish: nuqtaga boradi va masofani dist ga keltiradi (ikki marta bosish).
func fly_to(p: Vector3, dist: float) -> void:
	_fly = true
	_fly_to = Vector3(p.x, 0, p.z)
	_target_dist = clampf(dist, min_distance, max_distance)


## G'ildirak bilan yaqinlashganda kamera sichqoncha turgan nuqta tomonga biroz suriladi.
func nudge_towards(p: Vector3, k: float) -> void:
	_fly = false
	position += (Vector3(p.x, 0, p.z) - position) * k
	_clamp()


func focus(p: Vector3) -> void:
	position = Vector3(p.x, 0, p.z)
	_clamp()
