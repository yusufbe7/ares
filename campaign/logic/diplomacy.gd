## Diplomatiya poydevori: war_state jadvali (urush / tinchlik).
## Qoida: urushda bo'lmagan davlat hududiga hujum qilib bo'lmaydi, avval urush e'lon qilinadi.
## Hamma tinchlikda boshlaydi. Ittifoqchilar (bir blok) bir-biriga urush e'lon qila olmaydi.
class_name CampaignDiplomacy
extends RefCounted

signal war_declared(a: int, b: int)
signal peace_made(a: int, b: int)

var data: CampaignData
var _wars := {}                 ## "a:b" (a < b) -> boshlangan yurish


func _init(d: CampaignData) -> void:
	data = d


static func _key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func at_war(a: int, b: int) -> bool:
	return a != b and _wars.has(_key(a, b))


## Hujum qilish mumkinmi: egasiz hudud yoki urushdagi davlat.
func can_attack(attacker: int, target_owner: int) -> bool:
	return target_owner == 0 or at_war(attacker, target_owner)


func can_declare(a: int, b: int) -> bool:
	return a != b and data.countries.has(a) and data.countries.has(b) and not at_war(a, b) and not data.allied(a, b)


func declare_war(a: int, b: int, turn := 0) -> bool:
	if not can_declare(a, b):
		return false
	_wars[_key(a, b)] = turn
	war_declared.emit(a, b)
	return true


func make_peace(a: int, b: int) -> void:
	if _wars.erase(_key(a, b)):
		peace_made.emit(a, b)


## Davlat urushda bo'lgan davlatlar.
func enemies_of(cid: int) -> Array:
	var out := []
	for k in _wars:
		var p: PackedStringArray = k.split(":")
		var a := int(p[0]); var b := int(p[1])
		if a == cid: out.append(b)
		elif b == cid: out.append(a)
	return out


## Davlat yo'q bo'lganda uning urushlari ham tugaydi.
func forget(cid: int) -> void:
	for e in enemies_of(cid):
		_wars.erase(_key(cid, e))


func to_dict() -> Dictionary:
	return _wars.duplicate()


func from_dict(d: Dictionary) -> void:
	_wars = d.duplicate()
