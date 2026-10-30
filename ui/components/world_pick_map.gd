## Dunyo xaritasi (davlat tanlash): bosilgan joydagi hudud egasi tanlanadi, tanlangan davlat va uning
## blokdoshlari yoritiladi (shader). Rasm: map/satellite.jpg, hududlar: map/province_ids.png.
class_name WorldPickMap
extends TextureRect

signal picked(cid: int)

var _ids: Image
var _sel_img: Image
var _sel_tex: ImageTexture
var _owner := {}                     ## hudud id -> davlat id


func _ready() -> void:
	texture = load("res://map/satellite.jpg")
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ids = CampaignData._image("res://map/province_ids.png")
	for p in CampaignData._json("res://data/provinces.json", []):
		_owner[int(p.id)] = int(p.owner)
	_sel_img = Image.create(4096, 1, false, Image.FORMAT_R8)
	_sel_tex = ImageTexture.create_from_image(_sel_img)
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/components/world_pick_map.gdshader")
	if _ids:
		m.set_shader_parameter("ids", load("res://map/province_ids.png"))
		m.set_shader_parameter("ids_px", Vector2(_ids.get_width(), _ids.get_height()))
	m.set_shader_parameter("sel", _sel_tex)
	material = m


## Tanlangan davlat (1.0) va ittifoqchilar (0.5) hududlarini belgilaydi.
func highlight(cid: int, allies: Array) -> void:
	_sel_img.fill(Color(0, 0, 0))
	for pid in _owner:
		var o: int = _owner[pid]
		if o == cid:
			_sel_img.set_pixel(pid, 0, Color(1, 0, 0))
		elif o in allies:
			_sel_img.set_pixel(pid, 0, Color(0.5, 0, 0))
	_sel_tex.update(_sel_img)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _ids:
		var uv: Vector2 = e.position / size
		var px := Vector2i(clampi(int(uv.x * _ids.get_width()), 0, _ids.get_width() - 1), clampi(int(uv.y * _ids.get_height()), 0, _ids.get_height() - 1))
		var c := _ids.get_pixelv(px)
		var pid := int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256
		if _owner.has(pid) and _owner[pid] > 0:
			picked.emit(_owner[pid])
			accept_event()
