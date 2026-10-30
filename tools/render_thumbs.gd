## Texnika miniatyuralari: data/vehicles/*.tres dagi 3D modellarni render qilib ui/thumbs/<id>.png ga saqlaydi.
## Ishga tushirish (oyna kerak): godot --path . -s res://tools/render_thumbs.gd
## Rasm kartalarda VehicleData.image bo'lmasa ishlatiladi; o'zingizning renderingiz bilan almashtirish mumkin.
extends SceneTree

const OUT := "res://ui/thumbs/"
const SIZE := Vector2i(1600, 1000)
var _list: Array = []
var _vp: SubViewport
var _k := -1
var _wait := 0


func _initialize() -> void:
	for f in DirAccess.get_files_at("res://data/vehicles/"):
		if f.ends_with(".tres"):
			var v: Resource = load("res://data/vehicles/" + f)
			if v and str(v.model) != "" and ResourceLoader.exists(v.model):
				_list.append(v)
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-35), 0)
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.87, 0.7)
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(150), 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)


func _process(_d: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0 and _k >= 0:
			var img := _vp.get_texture().get_image()
			var path: String = OUT + str(_list[_k].id) + ".png"
			img.save_png(ProjectSettings.globalize_path(path))
			print("saved ", path)
		return false
	_k += 1
	for c in _vp.get_children():
		if c.has_meta("model"):
			c.free()
	if _k >= _list.size():
		return true
	var v: Resource = _list[_k]
	var pivot := Node3D.new()
	pivot.set_meta("model", true)
	_vp.add_child(pivot)
	var m: Node3D = load(v.model).instantiate()
	pivot.add_child(m)
	for ap in m.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	var bb := ModelThumb._aabb(m)
	m.position = -bb.get_center()
	pivot.rotation.y = deg_to_rad(-38)
	var cam := Camera3D.new()
	cam.set_meta("model", true)
	cam.fov = 26.0
	_vp.add_child(cam)
	# kadrga sig'ishi uchun masofa: eng katta o'lcham bo'yicha
	var r := maxf(bb.size.x, maxf(bb.size.y * 1.6, bb.size.z)) * 0.5
	var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.0
	cam.position = Vector3(0, dist * 0.32, dist)
	cam.look_at(Vector3(0, -bb.size.y * 0.05, 0))
	cam.make_current()
	_wait = 6
	return false
