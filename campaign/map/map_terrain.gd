## Xarita yeri: relyef meshi (height.png), sun'iy yo'ldosh rangi (satellite.jpg), relyef soyasi (normal.png),
## bulutlar, yorug'lik. Hudud egaligi va boshqa ma'lumot shaderga "info" teksturasi orqali beriladi:
##   0-qator: egasi rangi (rgb), a = egasi bormi
##   1-qator: egasi id (R + G*256), B = blok raqami, A = bayroqlar (1 ittifoqchi, 2 o'yinchi, 4 ziddiyat, 8 baza)
##   2-qator: resurs rangi (rgb), a = miqdor / 3
## conquer() faqat shu teksturadagi bitta ustunni yangilaydi, rasmlar qayta yaratilmaydi.
class_name MapTerrain
extends Node3D

const PX := 0.1                 ## bitta piksel = 0.1 dunyo birligi
const HS := 0.00024             ## quruqlik balandligi: metr -> birlik (biroz bo'rttirilgan relyef)
const STEP := 4                 ## mesh har 4 pikselda bitta uch (vertex)
const CHUNK := 64               ## bitta bo'lakdagi kataklar soni
const RES_COLORS := {"grain": Color(0.93, 0.8, 0.3), "wood": Color(0.2, 0.55, 0.25), "iron": Color(0.55, 0.6, 0.7),
	"oil": Color(0.12, 0.12, 0.14), "fish": Color(0.3, 0.65, 0.9), "salt": Color(0.95, 0.95, 0.92), "stone": Color(0.62, 0.5, 0.42)}

var data: CampaignData
var mat: ShaderMaterial
var info_img: Image
var info_tex: ImageTexture
var clouds: MeshInstance3D
var _grid := PackedFloat32Array()
var _gw := 0
var _gh := 0


func build(d: CampaignData) -> void:
	data = d
	_build_info()
	_build_grid()
	_build_mesh()
	_build_clouds()
	_build_light()


# ------------------------------------------------------------------ koordinatalar
func px_to_world(px: Vector2) -> Vector3:
	return Vector3((px.x - data.width * 0.5) * PX, 0.0, (px.y - data.height * 0.5) * PX)


func world_to_px(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / PX + data.width * 0.5)), int(floor(p.z / PX + data.height * 0.5)))


func size() -> Vector2:
	return Vector2(data.width * PX, data.height * PX)


## Dunyo nuqtasidagi yer balandligi (to'rdan bilinear).
func ground_y(x: float, z: float) -> float:
	var gx := clampf((x / PX + data.width * 0.5) / STEP, 0.0, _gw - 1.001)
	var gz := clampf((z / PX + data.height * 0.5) / STEP, 0.0, _gh - 1.001)
	var i := int(gx); var j := int(gz)
	var fx := gx - i; var fz := gz - j
	var k := j * _gw + i
	return lerpf(lerpf(_grid[k], _grid[k + 1], fx), lerpf(_grid[k + _gw], _grid[k + _gw + 1], fx), fz)


# ------------------------------------------------------------------ hudud ma'lumoti teksturasi
func _build_info() -> void:
	var max_id := 1
	for i in data.provinces:
		max_id = maxi(max_id, i)
	info_img = Image.create(max_id + 1, 3, false, Image.FORMAT_RGBA8)
	for p in data.provinces.values():
		paint(p, 0)
	info_tex = ImageTexture.create_from_image(info_img)


## Bitta hudud ustunini yozadi. flags: 1 ittifoqchi, 2 o'yinchi, 4 ziddiyat, 8 baza.
func paint(p: ProvinceData, flags: int) -> void:
	var c: CountryData = data.countries.get(p.owner)
	var col := c.color if c else Color(0.5, 0.5, 0.5)
	info_img.set_pixel(p.id, 0, Color(col.r, col.g, col.b, 1.0 if c else 0.0))
	var bi := 0
	if c and c.bloc != "":
		for k in data.blocs.size():
			if data.blocs[k].id == c.bloc:
				bi = k + 1
	info_img.set_pixel(p.id, 1, Color8(p.owner & 255, p.owner >> 8, bi, flags))
	var rc: Color = RES_COLORS.get(p.resource, Color.GRAY)
	info_img.set_pixel(p.id, 2, Color(rc.r, rc.g, rc.b, clampf(p.resource_amount / 3.0, 0.0, 1.0)))


func commit() -> void:
	info_tex.update(info_img)


# ------------------------------------------------------------------ relyef
func _vert_h(x: int, y: int) -> float:
	var p := Vector2i(clampi(x, 0, data.width - 1), clampi(y, 0, data.height - 1))
	if data.id_at(p) > 0:
		return maxf(data.height_at(p) * HS, 0.03)
	return -0.04                                    # dengiz: tekis, rangi shaderda (qorong'i okean)


func _build_grid() -> void:
	_gw = data.width / STEP + 1
	_gh = data.height / STEP + 1
	_grid.resize(_gw * _gh)
	for j in _gh:
		for i in _gw:
			_grid[j * _gw + i] = _vert_h(i * STEP, j * STEP)
	var sm := _grid.duplicate()                     # tog' cho'qqilari nayzadek bo'lmasin
	for j in range(1, _gh - 1):
		for i in range(1, _gw - 1):
			var k := j * _gw + i
			if _grid[k] > 0.05:
				sm[k] = maxf(0.03, (_grid[k] * 4.0 + _grid[k - 1] + _grid[k + 1] + _grid[k - _gw] + _grid[k + _gw]) / 8.0)
	_grid = sm


func _build_mesh() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://campaign/map/campaign_terrain.gdshader")
	mat.set_shader_parameter("id_tex", load("res://map/province_ids.png"))
	mat.set_shader_parameter("info_tex", info_tex)
	# sun'iy yo'ldosh: yuqori aniqlikdagisi (16384, yaqinda yer aniq) bo'lsa o'sha, bo'lmasa oddiysi
	var sat := "res://map/satellite_hd.jpg" if ResourceLoader.exists("res://map/satellite_hd.jpg") else "res://map/satellite.jpg"
	mat.set_shader_parameter("sat_tex", load(sat) if ResourceLoader.exists(sat) else null)
	_setup_ocean(mat)
	mat.set_shader_parameter("normal_tex", load("res://map/normal.png") if ResourceLoader.exists("res://map/normal.png") else null)
	mat.set_shader_parameter("map_px", Vector2(data.width, data.height))
	var cx := int(ceil((_gw - 1) / float(CHUNK)))
	var cz := int(ceil((_gh - 1) / float(CHUNK)))
	for bz in cz:
		for bx in cx:
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(bx * CHUNK, bz * CHUNK, mini(CHUNK, _gw - 1 - bx * CHUNK), mini(CHUNK, _gh - 1 - bz * CHUNK))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


func _chunk_mesh(i0: int, j0: int, ni: int, nj: int) -> ArrayMesh:
	var w := ni + 1
	var verts := PackedVector3Array(); verts.resize(w * (nj + 1))
	var norms := PackedVector3Array(); norms.resize(verts.size())
	var uvs := PackedVector2Array(); uvs.resize(verts.size())
	var n := 0
	var sx := STEP * PX
	for j in range(j0, j0 + nj + 1):
		for i in range(i0, i0 + ni + 1):
			var k := j * _gw + i
			verts[n] = Vector3((i * STEP - data.width * 0.5) * PX, _grid[k], (j * STEP - data.height * 0.5) * PX)
			var hl := _grid[j * _gw + maxi(i - 1, 0)]; var hr := _grid[j * _gw + mini(i + 1, _gw - 1)]
			var hu := _grid[maxi(j - 1, 0) * _gw + i]; var hd := _grid[mini(j + 1, _gh - 1) * _gw + i]
			norms[n] = Vector3(hl - hr, 2.0 * sx, hu - hd).normalized()
			uvs[n] = Vector2(float(i * STEP) / data.width, float(j * STEP) / data.height)
			n += 1
	var idx := PackedInt32Array(); idx.resize(ni * nj * 6)
	n = 0
	for j in nj:
		for i in ni:
			var a := j * w + i
			idx[n] = a; idx[n + 1] = a + 1; idx[n + 2] = a + w
			idx[n + 3] = a + 1; idx[n + 4] = a + w + 1; idx[n + 5] = a + w
			n += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


## Sekin suzuvchi bulutlar / yengil tuman (shader). Kamera yaqinlashganda yo'qoladi.
func _build_clouds() -> void:
	var cm := ShaderMaterial.new()
	cm.shader = load("res://campaign/map/campaign_clouds.gdshader")
	var pm := PlaneMesh.new()
	pm.size = size() * 1.2
	pm.material = cm
	clouds = MeshInstance3D.new()
	clouds.mesh = pm
	clouds.position.y = 5.5
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(clouds)


func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(-35), 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.86)
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.68)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## Ko'rinish rejimi (0 siyosiy, 1 relyef, 2 resurs) va katakchalar: shader parametrlari, qayta yuklashsiz.
func set_param(name: String, v: Variant) -> void:
	mat.set_shader_parameter(name, v)


func set_cloud_fade(cam_distance: float) -> void:
	if clouds:
		clouds.visible = cam_distance > 45.0
		(clouds.mesh.material as ShaderMaterial).set_shader_parameter("fade", clampf((cam_distance - 45.0) / 90.0, 0.0, 1.0))


## Okean teksturalari (tools/bake_ocean.py) va ularning parametrlari (data/ocean.json). Fayl bo'lmasa okean
## avvalgidek oddiy chiziladi (shader ichida to'lqin kuchi nolga tushadi).
func _setup_ocean(m: ShaderMaterial) -> void:
	m.set_shader_parameter("height_tex", load("res://map/height.png"))
	m.set_shader_parameter("height_px", Vector2(data.width, data.height))
	var j: Dictionary = CampaignData._json("res://data/ocean.json", {})
	for t in [["ocean_disp", "res://map/ocean_disp.png"], ["ocean_nrm", "res://map/ocean_normal.png"], ["ocean_col", "res://map/ocean_color.jpg"]]:
		if ResourceLoader.exists(t[1]):
			m.set_shader_parameter(t[0], load(t[1]))
	if j.is_empty():
		return
	m.set_shader_parameter("ocean_frames", int(j.get("frames", 125)))
	m.set_shader_parameter("ocean_cols", int(j.get("cols", 12)))
	m.set_shader_parameter("ocean_grid", int(j.get("grid", 144)))
	m.set_shader_parameter("ocean_fps", float(j.get("fps", 12.0)))
	var lo: Array = j.get("disp_min", [-0.42, -0.88, -0.45])
	var hi: Array = j.get("disp_max", [0.53, 1.05, 0.47])
	m.set_shader_parameter("disp_min", Vector3(lo[0], lo[1], lo[2]))
	m.set_shader_parameter("disp_max", Vector3(hi[0], hi[1], hi[2]))
