## O'yin sessiyasi: profil, ma'lumot katalogi (data/*.tres), jangga chiqish sozlamalari.
## Katalog kodda emas: yangi texnika / qurol / kiyim uchun mos papkaga .tres qo'shish kifoya.
extends Node

const DIRS := {"vehicles": "res://data/vehicles/", "weapons": "res://data/weapons/", "attachments": "res://data/attachments/",
	"cosmetics": "res://data/cosmetics/", "camos": "res://data/camo/", "operations": "res://data/operations/"}

var profile: PlayerProfile
var catalog := {}               ## "vehicles" -> {id: VehicleData}, ...
## Jangga chiqish: DEPLOY bosilganda to'ldiriladi, jang sahnasi o'qiydi.
var deploy := {}                ## {"kind": "operation"|"mission", "id": "...", "battle_mode": "...", "vehicles": [...]}
var in_battle := false          ## jangdan menyuga qaytilganmi (Exit matni o'zgaradi)
var campaign_slot := -1         ## kampaniya ochilganda yuklanadigan slot (-1 yangi)
## Kampaniyadan 3D jangga: {province, biome, seed, attacker, defender, att_regiments, def_regiments,
## player_defends, method}. Jang tugaganda battle_result to'ldiriladi va kampaniya uni qo'llaydi.
var battle_request := {}
var battle_result := {}
## Davlat tanlash ekrani natijasi: {country (ISO kod), mode, difficulty 1..3, ironman, no_blocs}.
var campaign_setup := {}
## Kampaniya ochilganda kamera shu nuqtaga uchadi (xarita pikseli; Vector2(-1,-1) - yo'q).
var campaign_focus := Vector2(-1, -1)
## O'yin ochilgandan beri davlat tanlash ekrani ko'rsatildimi (bir marta, keyin bosh menyu).
var setup_shown := false
const SETUP_PATH := "user://campaign_setup.json"


func _ready() -> void:
	Loc.ensure()
	for k in DIRS:
		catalog[k] = _load_dir(DIRS[k])
	profile = SaveManager.load_profile()
	if FileAccess.file_exists(SETUP_PATH):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETUP_PATH))
		campaign_setup = j if j is Dictionary else {}
	_apply_settings()
	# FPS ko'rsatkichi (Settings > Interface > Show FPS)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_fps = Label.new()
	_fps.position = Vector2(8, 4)
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fps)


var _fps: Label


func _process(_d: float) -> void:
	_fps.visible = Settings.show_fps
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()


func _load_dir(dir: String) -> Dictionary:
	var out := {}
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var path := dir + f.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var r: Resource = load(path)
		if r and "id" in r and str(r.get("id")) != "":
			out[r.get("id")] = r
		else:
			push_warning("Katalog: o'qib bo'lmadi " + path)
	return out


func item(kind: String, id: String) -> Resource:
	return (catalog.get(kind, {}) as Dictionary).get(id)


func items(kind: String) -> Array:
	var a: Array = (catalog.get(kind, {}) as Dictionary).values()
	a.sort_custom(func(x, y): return int(x.get("price")) < int(y.get("price")) if "price" in x else str(x.id) < str(y.id))
	return a


func save_setup() -> void:
	var f := FileAccess.open(SETUP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(campaign_setup))


func save() -> void:
	SaveManager.save_profile(profile)


func add_credits(n: int) -> void:
	profile.credits = maxi(0, profile.credits + n)
	EventBus.credits_changed.emit(profile.credits, profile.supply)
	save()


func add_xp(n: int) -> void:
	profile.xp += n
	EventBus.profile_changed.emit()
	save()


## Sozlamalarni (user://settings.cfg) qo'llaydi: grafika, ovoz, til.
func _apply_settings() -> void:
	var s := Settings.load_all()
	Settings.apply(s, get_tree().root)
