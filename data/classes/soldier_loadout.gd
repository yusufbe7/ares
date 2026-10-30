## Askar jihozlari: kategoriya -> tanlangan buyum id, kamuflyaj, qurol, slot nomi.
class_name SoldierLoadout
extends Resource

@export var slot_name := "Loadout 1"
@export var items := {"uniform": "uniform_standard", "helmet": "helmet_combat", "vest": "vest_plate_pouches",
	"backpack": "backpack_none", "gloves": "gloves_tactical", "boots": "boots_combat", "face": "face_mask_glasses", "patch": "patch_none"}
@export var camo := "olive"
@export var weapon := "ak74"


func to_dict() -> Dictionary:
	return {"slot_name": slot_name, "items": items.duplicate(), "camo": camo, "weapon": weapon}


static func from_dict(d: Dictionary) -> SoldierLoadout:
	var l := SoldierLoadout.new()
	l.slot_name = str(d.get("slot_name", l.slot_name))
	var it: Variant = d.get("items", {})
	if it is Dictionary:
		for k in it:
			l.items[k] = str(it[k])
	l.camo = str(d.get("camo", l.camo))
	l.weapon = str(d.get("weapon", l.weapon))
	return l
