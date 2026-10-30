## Tugmalarni qayta belgilash. O'yin kodi tugmalarni avvalgidek "standart" nomi bilan tekshiradi
## (masalan KEY_R), shu sinf esa o'yinchi tanlagan tugmani o'sha standartga aylantiradi:
##   Keys.logical(e.keycode)  -> bosilgan tugma qaysi amalga bog'langan bo'lsa, o'sha amalning standart tugmasi
##   Keys.physical(KEY_W)     -> "kamera yuqoriga" amali hozir qaysi tugmada
## Tanlov user://settings.cfg [controls] bo'limida saqlanadi (Settings). Ro'yxatda yo'q tugmalar o'zgarmaydi.
class_name Keys
extends RefCounted

## [amal, standart tugma]. Matn: "act.<amal>" (data/lang).
const ACTIONS := [["move_up", KEY_W], ["move_down", KEY_S], ["move_left", KEY_A], ["move_right", KEY_D],
	["rotate_left", KEY_Q], ["rotate_right", KEY_E], ["squad", KEY_R], ["tank", KEY_Y], ["artillery", KEY_U],
	["build", KEY_B], ["trench", KEY_V], ["grenade", KEY_G], ["rpg", KEY_T], ["halt", KEY_H], ["focus", KEY_F],
	["season", KEY_N]]

static var _bound := {}         ## amal -> tugma
static var _by_key := {}        ## bosilgan tugma -> standart tugma
static var _loaded := false


static func default_of(action: String) -> int:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return KEY_NONE


static func load_from(controls: Dictionary) -> void:
	_bound.clear()
	_by_key.clear()
	for a in ACTIONS:
		var k := int(controls.get(a[0], a[1]))
		_bound[a[0]] = k
		_by_key[k] = a[1]
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		load_from(Settings.load_all().get("controls", {}))


static func key_of(action: String) -> int:
	_ensure()
	return int(_bound.get(action, default_of(action)))


## Bosilgan tugma -> o'yin kodi kutadigan standart tugma. Boshqa amalga o'tkazilgan standart tugma
## o'z ma'nosini yo'qotadi (KEY_NONE), ro'yxatda yo'q tugmalar o'zgarmaydi.
static func logical(pressed: int) -> int:
	_ensure()
	if _by_key.has(pressed):
		return _by_key[pressed]
	for a in ACTIONS:
		if a[1] == pressed:
			return KEY_NONE
	return pressed


## Standart tugma -> hozir unga bog'langan tugma (Input.is_key_pressed uchun).
static func physical(default_key: int) -> int:
	_ensure()
	for a in ACTIONS:
		if a[1] == default_key:
			return int(_bound.get(a[0], default_key))
	return default_key


## Shu tugma boshqa amalda bandmi? Band bo'lsa o'sha amal nomi, bo'lmasa "".
static func conflict(action: String, key: int) -> String:
	_ensure()
	for a in ACTIONS:
		if a[0] != action and int(_bound.get(a[0], a[1])) == key:
			return a[0]
	return ""
