## Building placement: a see-through model + footprint follows the mouse (green = OK, red = not allowed),
## the build zones show as green circles on the ground. T rotates, Shift keeps placing, right click cancels.
## Also used to pick a target for fire support (kind = "target").
class_name RtsPlacer
extends Node

signal placed(key: String, pos: Vector3, yaw: float)
signal target_picked(key: String, pos: Vector3)
signal trench_placed(a: Vector3, b: Vector3, joined: bool)

var demo: Node3D
var active := false
var key := ""
var kind := "build"                 # build | target | trench
var yaw := 0.0
var valid := false
var reason := ""
var validator: Callable              # func(key, pos, yaw) -> String ("" = ok)
var _ghost: Node3D
var _foot: Decal
var _zones: Array = []
var _ghost_mat: StandardMaterial3D
var _target_ring: Decal
var trench_validator: Callable       # func(a, b) -> String ("" = ok)
var _pts: Array = []
var _preview: MeshInstance3D
const TRENCH_MAX := 30.0

static var _circle_tex: Texture2D


func setup(p_demo: Node3D) -> void:
	demo = p_demo


static func circle_texture() -> Texture2D:
	if _circle_tex:
		return _circle_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length() / c
			var col := Color(1, 1, 1, 0)
			if d <= 1.0:
				col = Color(1, 1, 1, 0.24)
				if d > 0.965: col = Color(1, 1, 1, 0.95)
			img.set_pixel(x, y, col)
	_circle_tex = ImageTexture.create_from_image(img)
	return _circle_tex


func begin(p_key: String, zones: Array) -> void:
	cancel()
	key = p_key
	kind = "build"
	active = true
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.38)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost = BuildDefs.make_model(key, 0)
	demo.add_child(_ghost)
	for m in _ghost.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = _ghost_mat
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sz: Vector2 = BuildDefs.STRUCTURES[key].size
	_foot = Decal.new()
	_foot.cull_mask = RtsGround.DECAL_LAYER
	_foot.texture_albedo = RtsStructure.outline_texture()
	_foot.size = Vector3(sz.x + 1.0, 14.0, sz.y + 1.0)
	_foot.albedo_mix = 1.0
	_ghost.add_child(_foot)
	_foot.position.y = 3.0
	for z in zones:          # [center Vector3, radius]
		var d := Decal.new()
		d.cull_mask = RtsGround.DECAL_LAYER
		d.texture_albedo = circle_texture()
		d.size = Vector3(z[1] * 2.0, 60.0, z[1] * 2.0)
		d.modulate = Color(0.45, 1.0, 0.55)
		d.albedo_mix = 1.0
		demo.add_child(d)
		d.global_position = z[0] + Vector3.UP * 10.0
		_zones.append(d)
	_follow()


func begin_target(p_key: String, radius: float) -> void:
	cancel()
	key = p_key
	kind = "target"
	active = true
	_target_ring = Decal.new()
	_target_ring.cull_mask = RtsGround.DECAL_LAYER
	_target_ring.texture_albedo = circle_texture()
	_target_ring.size = Vector3(radius * 2.0, 60.0, radius * 2.0)
	_target_ring.modulate = Color(1.0, 0.35, 0.25)
	demo.add_child(_target_ring)
	_follow()


## Trench drawing: click a start point, then click again for every corner (each leg is one trench
## segment the soldiers dig). Right click or Esc stops drawing.
func begin_trench() -> void:
	cancel()
	kind = "trench"
	key = "trench"
	active = true
	_pts.clear()
	_preview = MeshInstance3D.new()
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	demo.add_child(_preview)
	_follow()


func _trench_end(p: Vector3) -> Vector3:
	var a: Vector3 = _pts.back()
	var d := p - a
	d.y = 0
	if d.length() > TRENCH_MAX:
		d = d.normalized() * TRENCH_MAX
	return a + d


func cancel() -> void:
	active = false
	_pts.clear()
	if _preview: _preview.queue_free(); _preview = null
	if _ghost: _ghost.queue_free(); _ghost = null
	if _target_ring: _target_ring.queue_free(); _target_ring = null
	for d in _zones: d.queue_free()
	_zones.clear()


func _follow() -> void:
	var p = demo._mouse_point()
	if p == null:
		return
	if kind == "target":
		_target_ring.global_position = p + Vector3.UP * 10.0
		return
	if kind == "trench":
		if _pts.is_empty():
			_preview.mesh = RtsTrench.wire_box(demo.map, p - Vector3(0.6, 0, 0), p + Vector3(0.6, 0, 0), 1.5, 1.4, Color(0.45, 0.7, 1.0))
			return
		var te := _trench_end(p)
		reason = trench_validator.call(_pts.back(), te) if trench_validator.is_valid() else ""
		valid = reason == ""
		_preview.mesh = RtsTrench.wire_box(demo.map, _pts.back(), te, RtsTrench.HALF_W + 0.25, 1.4, Color(0.45, 0.7, 1.0) if valid else Color(1.0, 0.3, 0.25))
		return
	_ghost.global_position = p
	_ghost.rotation.y = yaw
	reason = validator.call(key, p, yaw) if validator.is_valid() else ""
	valid = reason == ""
	var col := Color(0.4, 1.0, 0.5) if valid else Color(1.0, 0.3, 0.25)
	_ghost_mat.albedo_color = Color(col.r, col.g, col.b, 0.38)
	_foot.modulate = col


func _unhandled_input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventMouseMotion:
		_follow()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_T:
			yaw += PI / 4.0
			_follow()
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			var p = demo._mouse_point()
			if p != null:
				if kind == "target":
					var k := key
					cancel()
					target_picked.emit(k, p)
				elif kind == "trench":
					if _pts.is_empty():
						_pts.append(p)
					else:
						var te := _trench_end(p)
						_follow()
						if valid:
							trench_placed.emit(_pts.back(), te, _pts.size() > 1)
							_pts.append(te)
						else:
							demo.notify("Can't dig here: " + reason)
					_follow()
				else:
					_follow()
					if valid:
						var k := key
						placed.emit(k, p, yaw)
						if not e.shift_pressed:
							cancel()
					else:
						demo.notify("Can't build here: " + reason)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		get_viewport().set_input_as_handled()
