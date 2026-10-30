## Askar ko'rinishini loadout bo'yicha o'zgartiradi (USUL C: qismlarni ko'rsatish/yashirish + material tusi).
## Askar modeli (soldier.glb) qismlarga bo'lingan: shlem, jilet (Plate), cho'ntaklar, qo'lqop, etik, kitel,
## shim, niqobli bosh, ko'zoynak. Shuning uchun:
##   - kategoriya buyumi (CosmeticItem.parts) qaysi qismlar ko'rinishini belgilaydi;
##   - kamuflyaj forma / shlem / jilet qismlarini rang bilan bo'yaydi (data/soldier_parts.json), asl
##     tekstura saqlanadi; jamoa belgisi (yashil / qizil halqa) RtsSoldier da alohida, unga tegilmaydi.
## Bosh menyu, sozlash ekrani va jang sahnasi shu bitta funksiyani ishlatadi.
class_name LoadoutApplier
extends RefCounted

static var _mat_cache := {}     ## "asl material id|tus" -> bo'yalgan nusxa
static var _member := 0         ## jangda askarlar navbat bilan 3 ta jamoa a'zosi loadoutini oladi


static func apply(soldier: Node, l: SoldierLoadout) -> void:
	if soldier == null or l == null:
		return
	var meshes := {}
	for m in soldier.find_children("*", "MeshInstance3D", true, false):
		meshes[m.name] = m
	var camo_parts: Array = CampaignData._json("res://data/soldier_parts.json", {}).get("camo_parts", [])
	var camo: CamouflageData = GameSession.item("camos", l.camo)
	var camo_tint := camo.tint if camo else Color.WHITE
	var tints := {}
	var cats := {}
	for it in GameSession.items("cosmetics"):
		cats.get_or_add(it.category, []).append(it)
	for cat in cats:
		var chosen: CosmeticItem = GameSession.item("cosmetics", str(l.items.get(cat, "")))
		if chosen == null or chosen.category != cat:
			chosen = cats[cat][0]
		for it in cats[cat]:                 # kategoriyadagi hamma qismlar avval yashiriladi
			for p in it.parts:
				if meshes.has(p):
					meshes[p].visible = false
		for p in chosen.parts:
			if meshes.has(p):
				meshes[p].visible = true
				tints[p] = chosen.tint
	for name in meshes:
		var t: Color = tints.get(name, Color.WHITE)
		if name in camo_parts:
			t = t * camo_tint
		_tint(meshes[name], t)


static func _tint(mi: MeshInstance3D, t: Color) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var base := mi.mesh.surface_get_material(s)
		if not (base is StandardMaterial3D):
			continue
		if t.is_equal_approx(Color.WHITE):
			mi.set_surface_override_material(s, null)
			continue
		var key := "%d|%s" % [base.get_instance_id(), t.to_html()]
		if not _mat_cache.has(key):
			var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = base.albedo_color * t
			_mat_cache[key] = m
		mi.set_surface_override_material(s, _mat_cache[key])


## Jang sahnasi uchun: o'yinchi askariga profildagi faol loadout va qurol ko'rsatkichlarini qo'llaydi.
## GameSession yo'q bo'lsa (masalan eski testlar) hech narsa qilmaydi.
static func apply_session(soldier: Node3D, model: Node) -> void:
	var gs: Node = soldier.get_tree().root.get_node_or_null("GameSession") if soldier.is_inside_tree() else Engine.get_main_loop().root.get_node_or_null("GameSession")
	if gs == null or gs.profile == null:
		return
	var p: PlayerProfile = gs.profile
	p.loadout()
	apply(model, p.loadouts[(p.active_loadout + _member) % 3])
	_member += 1
	var w: WeaponData = gs.item("weapons", gs.profile.equipped_weapon)
	if w and w.weapon_class == "assault" and "accuracy" in soldier:
		var st := Shop.weapon_stats(w)
		soldier.accuracy *= st.accuracy / float(w.accuracy)        # modifikatsiyalar jangda ham ishlaydi
		soldier.weapon_range *= st.range / float(w.range)
		soldier.fire_interval /= maxf(0.5, st.fire_rate / float(w.fire_rate))
