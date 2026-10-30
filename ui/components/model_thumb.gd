## 3D model miniatyurasi: o'z SubViewport ida bir marta (yoki aylanib) chiziladi. Rasm bo'lmasa ishlatiladi.
## model bo'sh yoki topilmasa "NO IMAGE" ko'rinadi.
class_name ModelThumb
extends SubViewportContainer

var model_path := ""
var spin := false
var model_scale := 1.0
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D


static func make(path: String, sz: Vector2, p_spin := false, sc := 1.0) -> Control:
	if path == "" or not ResourceLoader.exists(path):
		return UiKit.image_slot(null, sz)
	var t := ModelThumb.new()
	t.model_path = path
	t.spin = p_spin
	t.model_scale = sc
	t.custom_minimum_size = sz
	t.stretch = true
	return t


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS     # avto-kadrlashdan keyin spin bo'lmasa to'xtaydi
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-140), 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.86, 0.7)
	_vp.add_child(sun)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	var m: Node3D = load(model_path).instantiate()
	_pivot.add_child(m)
	for ap in m.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	_pivot.rotation.y = deg_to_rad(-35)
	var aabb := _aabb(m)
	m.position = -aabb.get_center()
	m.position.y = -aabb.position.y - aabb.size.y * 0.5
	_cam = Camera3D.new()
	_cam.fov = 28.0
	var r := aabb.size.length() * 0.5 / model_scale
	_cam.position = Vector3(0, r * 0.55, r * 2.3)
	_vp.add_child(_cam)
	_cam.look_at(Vector3.ZERO)


static func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		var x := (mi as Node3D).global_transform if (mi as Node3D).is_inside_tree() else _xf(mi, n)
		b = x * b
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))


static func _xf(mi: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := mi
	while c and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


var _frame := 0
var _framed := 0


func _process(delta: float) -> void:
	_frame += 1
	# avto-kadrlash: suyakli (skinned) modellarda mesh chegarasi noto'g'ri bo'ladi, shuning uchun
	# birinchi render'dagi haqiqiy tasvir chegarasiga qarab model markazga suriladi va masofa moslanadi
	if _framed < 2 and _frame >= 3 + _framed * 3 and _vp and _vp.size.x > 8:
		_autoframe()
		_framed += 1
		if _framed >= 2 and not spin:
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if spin and _pivot and _framed >= 2:
		_pivot.rotation.y += delta * 0.5


func _autoframe() -> void:
	var img := _vp.get_texture().get_image()
	if img == null:
		return
	var r := img.get_used_rect()
	if r.size.x < 4 or r.size.y < 4:
		return
	var vs := Vector2(_vp.size)
	var d := _cam.global_position.length()
	var wpp := 2.0 * d * tan(deg_to_rad(_cam.fov) * 0.5) / vs.y      # dunyo birligi / piksel
	var off := (Vector2(r.get_center()) - vs * 0.5) * wpp
	var b := _cam.global_transform.basis
	var m: Node3D = _pivot.get_child(0)
	m.global_position -= b.x * off.x - b.y * off.y
	var fill := maxf(r.size.x / (vs.x * 0.86), r.size.y / (vs.y * 0.8))
	if spin:
		fill *= 1.35          # aylanganda yon tomondan uzunroq ko'rinadi: kadrdan chiqmasin
	_cam.position *= clampf(fill, 0.3, 3.0)
	_cam.look_at(Vector3.ZERO)


## Garaj: sichqoncha bilan aylantirish.
func rotate_by(dx: float) -> void:
	if _pivot:
		_pivot.rotation.y += dx
