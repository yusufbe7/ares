## Do'kon: sotib olish, yangilash, jihozlash. Credits yetmasa yoki daraja past bo'lsa false va sabab (toast).
## Hamma o'zgarish profilga yoziladi va saqlanadi (qayta ochilganda ham turadi).
class_name Shop
extends RefCounted


static func _pay(price: int, level: int) -> bool:
	var p: PlayerProfile = GameSession.profile
	if p.level() < level:
		EventBus.toast.emit(Loc.t("need_level", [level]))
		return false
	if p.credits < price:
		EventBus.toast.emit(Loc.t("no_credits"))
		return false
	GameSession.add_credits(-price)
	Shop.track("purchases")
	return true


static func buy_vehicle(id: String) -> bool:
	var v: VehicleData = GameSession.item("vehicles", id)
	var p: PlayerProfile = GameSession.profile
	if v == null or not v.available or id in p.owned_vehicles or not _pay(v.price, v.required_level):
		return false
	p.owned_vehicles.append(id)
	GameSession.save()
	EventBus.vehicle_bought.emit(id)
	return true


static func select_vehicle(id: String) -> void:
	var p: PlayerProfile = GameSession.profile
	if not (id in p.owned_vehicles):
		return
	if id in p.selected_vehicles:
		p.selected_vehicles.remove_at(p.selected_vehicles.find(id))
	else:
		p.selected_vehicles.append(id)
	GameSession.save()
	EventBus.vehicle_selected.emit(id)


static func upgrade_level(id: String, part: String) -> int:
	return int((GameSession.profile.vehicle_upgrades.get(id, {}) as Dictionary).get(part, 0))


static func upgrade(id: String, part: String) -> bool:
	var v: VehicleData = GameSession.item("vehicles", id)
	var lv := upgrade_level(id, part)
	var costs: Array = v.upgrade_costs.get(part, [])
	if v == null or lv >= costs.size() or not (id in GameSession.profile.owned_vehicles) or not _pay(int(costs[lv]), 1):
		return false
	var u: Dictionary = GameSession.profile.vehicle_upgrades.get_or_add(id, {})
	u[part] = lv + 1
	GameSession.save()
	EventBus.vehicle_selected.emit(id)
	return true


## Texnika ko'rsatkichlari yangilanishlar bilan: engine -> mobility, armor -> armor, weapon -> firepower.
static func vehicle_stats(v: VehicleData) -> Dictionary:
	var b := v.upgrade_bonus
	return {"firepower": mini(100, v.firepower + b * upgrade_level(v.id, "weapon")),
		"armor": mini(100, v.armor + b * upgrade_level(v.id, "armor")),
		"mobility": mini(100, v.mobility + b * upgrade_level(v.id, "engine"))}


static func buy_weapon(id: String) -> bool:
	var w: WeaponData = GameSession.item("weapons", id)
	var p: PlayerProfile = GameSession.profile
	if w == null or id in p.owned_weapons or not _pay(w.price, w.required_level):
		return false
	p.owned_weapons.append(id)
	GameSession.save()
	return true


static func equip_weapon(id: String) -> void:
	if id in GameSession.profile.owned_weapons:
		GameSession.profile.equipped_weapon = id
		GameSession.save()
		EventBus.weapon_equipped.emit(id)


## Qurol ko'rsatkichlari o'rnatilgan modifikatsiyalar bilan (extra: sinab ko'rish uchun qo'shimcha modifikatsiya).
static func weapon_stats(w: WeaponData, extra: AttachmentData = null) -> Dictionary:
	var st := {"damage": w.damage, "accuracy": w.accuracy, "range": w.range, "fire_rate": w.fire_rate, "mobility": w.mobility}
	var mods: Dictionary = (GameSession.profile.weapon_mods.get(w.id, {}) as Dictionary).duplicate()
	if extra:
		mods[extra.slot] = extra.id
	for slot in mods:
		var a: AttachmentData = GameSession.item("attachments", str(mods[slot]))
		if a:
			for k in a.stats:
				st[k] = clampi(int(st.get(k, 0)) + int(a.stats[k]), 0, 100)
	return st


static func install(weapon_id: String, a: AttachmentData) -> bool:
	var p: PlayerProfile = GameSession.profile
	if not (a.id in p.owned_attachments):
		if not _pay(a.price, a.required_level):
			return false
		p.owned_attachments.append(a.id)
	var m: Dictionary = p.weapon_mods.get_or_add(weapon_id, {})
	m[a.slot] = a.id
	GameSession.save()
	EventBus.weapon_equipped.emit(weapon_id)
	return true


static func uninstall(weapon_id: String, slot: String) -> void:
	(GameSession.profile.weapon_mods.get(weapon_id, {}) as Dictionary).erase(slot)
	GameSession.save()
	EventBus.weapon_equipped.emit(weapon_id)


static func owns_cosmetic(it: Resource) -> bool:
	return int(it.get("price")) == 0 or str(it.id) in GameSession.profile.owned_cosmetics or str(it.id) in GameSession.profile.owned_camos


static func buy_cosmetic(it: Resource) -> bool:
	if owns_cosmetic(it):
		return true
	if not _pay(int(it.get("price")), int(it.get("required_level")) if "required_level" in it else 1):
		return false
	if it is CamouflageData:
		GameSession.profile.owned_camos.append(it.id)
	else:
		GameSession.profile.owned_cosmetics.append(it.id)
	GameSession.save()
	return true


## Topshiriqlar hisoblagichi (data/tasks.json metric).
static func track(metric: String, n := 1) -> void:
	var d: Dictionary = GameSession.profile.daily
	d[metric] = int(d.get(metric, 0)) + n
