## Total War uslubidagi strategik dunyo xaritasi (sahna ildizi). Qismlarni bir-biriga ulaydi:
##   CampaignData (ma'lumot) -> CampaignRules (o'yin mantig'i, UI siz) -> MapTerrain (yer, shader),
##   MapLabels (yozuvlar), ArmyOverlay / LayersOverlay (belgilar, qatlamlar), CampaignScreen (UI).
## UI bilan aloqa EventBus orqali. Eski API (conquer, order_move, choose_country, end_turn...) saqlangan.
class_name CampaignMap
extends Node3D

signal province_selected(id: int)
signal province_conquered(id: int, old_owner: int, new_owner: int)

const PX := MapTerrain.PX

var data: CampaignData
var rules: CampaignRules
var terrain: MapTerrain
var ocean_near: OceanNear
var labels: MapLabels
var cam: CampaignCamera
var ui: Node                    ## CampaignScreen (headless testda ham yaratiladi)
var armies_ui: ArmyOverlay
var layers: LayersOverlay
var ops: CampaignWarOps         ## hujum operatsiyalari (quruqlik / dengiz / havo)
var runner: OpsRunner           ## operatsiya animatsiyasi va jangga o'tish
var selected_id := -1
var selected_army: ArmyData = null
var choice_id := 0              ## tanlash ekranida tanlangan davlat
var hover_owner := 0
var player_id: int:
	get: return rules.player_id
var phase: String:
	get: return rules.phase
var turn: int:
	get: return rules.turn
var _label_frame := 0
var _info_dirty := true
var _ui_dirty := false          ## UI yangilanishi kadrda bir marta (botlar ko'p o'zgartirsa ham)


func _ready() -> void:
	Loc.ensure()
	data = CampaignData.new()
	data.load_all()
	rules = CampaignRules.new(data)
	ops = rules.ops
	terrain = MapTerrain.new()
	add_child(terrain)
	terrain.build(data)
	ocean_near = OceanNear.make(terrain)          # yaqin kadrdagi 3D to'lqinlar
	add_child(ocean_near)
	cam = CampaignCamera.new()
	var sz := terrain.size()
	cam.bounds = Rect2(-sz.x * 0.5, -sz.y * 0.5, sz.x, sz.y)
	cam.picker = pick                             # ikki marta bosish / g'ildirak: bosilgan joyga yaqinlashish
	add_child(cam)
	labels = MapLabels.new()
	add_child(labels)
	labels.build(self)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	layers = LayersOverlay.new()
	layers.map = self
	layer.add_child(layers)
	armies_ui = ArmyOverlay.new()
	armies_ui.map = self
	layer.add_child(armies_ui)
	runner = OpsRunner.new()
	runner.map = self
	layer.add_child(runner)
	rules.owner_changed.connect(_on_owner_changed)
	rules.state_changed.connect(func(): _info_dirty = true; _ui_dirty = true)
	rules.armies_changed.connect(func(): _info_dirty = true)
	rules.message.connect(func(t: String): EventBus.campaign_message.emit(t))
	rules.missions.completed.connect(func(m: MissionData): EventBus.campaign_message.emit(Loc.t("mission_done", [Loc.t(m.title)])))
	EventBus.map_view_changed.connect(func(mode: int): terrain.set_param("view_mode", mode))
	EventBus.map_option_changed.connect(_on_option)
	EventBus.language_changed.connect(apply_language)
	ui = (load("res://ui/campaign/campaign_screen.gd") as GDScript).new()
	add_child(ui)
	ui.setup(self)
	_apply_phase_look()
	var start := int(data.by_code.get("UZB", 0))
	if start:
		cam.focus(province_world(data.countries[start].capital))
	if GameSession.campaign_setup.is_empty() and GameSession.campaign_slot < 0:
		EventBus.campaign_message.emit(Loc.t("choose_hint"))


# ------------------------------------------------------------------ koordinatalar
func px_to_world(px: Vector2) -> Vector3:
	return terrain.px_to_world(px)


func world_to_px(p: Vector3) -> Vector2i:
	return terrain.world_to_px(p)


func ground_y(x: float, z: float) -> float:
	return terrain.ground_y(x, z)


func province_world(id: int) -> Vector3:
	var p: ProvinceData = data.provinces.get(id)
	if p == null:
		return Vector3.ZERO
	var w := terrain.px_to_world(Vector2(p.center_px) + Vector2(0.5, 0.5))
	w.y = maxf(terrain.ground_y(w.x, w.z), 0.0)
	return w


# ------------------------------------------------------------------ eski API (rules ga uzatadi)
func conquer(province_id: int, new_owner_id: int) -> void:
	rules.conquer(province_id, new_owner_id)


func order_move(a: ArmyData, target: int) -> bool:
	var ok := rules.order_move(a, target)
	if ok and a.owner == rules.player_id and a in data.armies:
		select_province(a.province)
	return ok


## Dushman hududi: hujum rejasi oynasi; o'z / ittifoqchi hududi: oddiy yurish.
func plan_or_move(a: ArmyData, target: int) -> void:
	var tp: ProvinceData = data.provinces.get(target)
	if tp == null:
		return
	if tp.owner == a.owner or data.allied(a.owner, tp.owner):
		order_move(a, target)
		return
	open_attack_plan(target, a)


func open_attack_plan(target: int, prefer: ArmyData = null) -> void:
	var w := AttackPlan.open(self, target, prefer)
	w.launched.connect(func(op: Dictionary, fast: bool, in_3d: bool): runner.run(op, fast, in_3d))


func army_in(province_id: int) -> ArmyData:
	return rules.army_in(province_id)


func strength(cid: int) -> Vector2i:
	return rules.strength(cid)


func recruit(province_id: int) -> void:
	if rules.recruit(province_id):
		select_province(province_id)


func end_turn() -> void:
	CampaignTurns.end_turn(rules)
	EventBus.turn_ended.emit(rules.turn)


func owner_of(province_id: int) -> int:
	var p: ProvinceData = data.provinces.get(province_id)
	return p.owner if p else 0


func _country_by_code(code: String) -> int:
	return int(data.by_code.get(code, 0))


func _any_province(cid: int) -> int:
	return CampaignTurns._any(data, cid)


func choose_country(cid: int) -> void:
	if not data.countries.has(cid):
		return
	rules.choose_country(cid)
	choice_id = 0
	_apply_phase_look()
	select_province(data.countries[cid].capital)
	cam.focus(province_world(data.countries[cid].capital))
	EventBus.country_chosen.emit(cid)


# ------------------------------------------------------------------ xarita yangilanishi
func _on_owner_changed(pid: int, old: int, new: int) -> void:
	labels.set_province_owner(pid, new)
	labels.mark_dirty(old)
	labels.mark_dirty(new)
	_info_dirty = true
	province_conquered.emit(pid, old, new)


## info teksturasini qayta yozadi: egasi, ittifoqchi / o'yinchi / ziddiyat / baza belgilari.
func refresh_info() -> void:
	var conf := rules.conflicts()
	var base := {}
	for b in data.bases:
		base[b.province] = true
	for p in data.provinces.values():
		var f := 0
		if rules.player_id > 0 and p.owner != rules.player_id and data.allied(rules.player_id, p.owner): f |= 1
		if p.owner == rules.player_id and rules.player_id > 0: f |= 2
		if conf.has(p.id): f |= 4
		if base.has(p.id): f |= 8
		terrain.paint(p, f)
	terrain.commit()
	_info_dirty = false


func _on_option(key: String, on: bool) -> void:
	match key:
		"borders": terrain.set_param("show_borders", on)
		"allies": terrain.set_param("show_allies", on)
		_: layers.show[key] = on


func apply_language() -> void:
	labels.apply_language()
	_label_frame = 0


func _apply_phase_look() -> void:
	var ch := rules.phase == "choose"
	terrain.set_param("province_lines", 0.15 if ch else 1.0)
	terrain.set_param("hover_owner", -1)
	terrain.set_param("hover_id", -1)
	terrain.set_param("selected_owner", choice_id if ch and choice_id > 0 else -1)
	terrain.set_param("player_owner", rules.player_id if not ch and rules.player_id > 0 else -1)
	terrain.set_param("selected_id", -1)
	hover_owner = 0
	labels.set_player_tint(rules.player_id, ch)
	_info_dirty = true
	_label_frame = 0


# ------------------------------------------------------------------ tanlash va kiritish
func pick(screen: Vector2) -> Variant:
	return MapPicker.pick(self, screen)


func province_at_screen(screen: Vector2) -> int:
	var p = pick(screen)
	return 0 if p == null else data.id_at(terrain.world_to_px(p))


func select_province(id: int) -> void:
	if rules.phase == "choose":
		preview_country(owner_of(id))
		return
	selected_id = id
	terrain.set_param("selected_id", id)
	selected_army = null
	var a := army_in(id)
	if a and a.owner == rules.player_id:
		selected_army = a
	province_selected.emit(id)
	EventBus.province_selected.emit(id)


## Tanlash ekrani: davlatni belgilaydi (o'ynash tugmasi chiqadi).
func preview_country(cid: int) -> void:
	choice_id = cid if data.countries.has(cid) else 0
	terrain.set_param("selected_owner", choice_id if choice_id > 0 else -1)
	EventBus.country_previewed.emit(choice_id)


func _hover(h: int) -> void:
	if rules.phase == "choose":
		var o := owner_of(h)
		if o != hover_owner:
			hover_owner = o
			terrain.set_param("hover_owner", o if o > 0 else -1)
			EventBus.country_hovered.emit(o)
	else:
		terrain.set_param("hover_id", h if h > 0 else -1)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Engine.get_process_frames() % 3 == 0:
		_hover(province_at_screen(e.position))
	if not (e is InputEventMouseButton) or e.pressed:
		return
	var mb := e as InputEventMouseButton
	var cl := armies_ui.hit(mb.position) if rules.phase != "choose" else {}
	if mb.button_index == MOUSE_BUTTON_LEFT and not cam.was_drag():
		if not cl.is_empty():
			if cl.armies.size() > 1:
				cam.focus(province_world(cl.armies[0].province))      # birlashgan belgi: yaqinlashamiz
				cam._target_dist = maxf(cam.min_distance, cam.distance * 0.45)
				EventBus.campaign_message.emit(Loc.t("cluster_hint"))
			else:
				select_province(cl.armies[0].province)
			return
		var pid := province_at_screen(mb.position)
		if pid == 0 and rules.phase != "choose":
			# dengiz: bitta bosish ham o'sha joyga yaqinlashtiradi (real suv va qirg'oq ko'rinadi)
			var w = pick(mb.position)
			if w != null:
				cam.fly_to(w, maxf(cam.min_distance, cam.distance * 0.5))
			return
		select_province(pid)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and rules.phase == "play" and selected_army:
		var target: int = cl.armies[0].province if not cl.is_empty() else province_at_screen(mb.position)
		if target > 0 and not runner.busy():
			plan_or_move(selected_army, target)


func blocked_rects() -> Array:
	return ui.blocked_rects() if ui and ui.has_method("blocked_rects") else []


func _process(_d: float) -> void:
	if _info_dirty:
		refresh_info()
	if _ui_dirty:
		_ui_dirty = false
		EventBus.campaign_changed.emit()
	_label_frame -= 1
	if _label_frame <= 0:
		_label_frame = 2
		labels.update(blocked_rects())
		armies_ui.avoid_rects = labels.rects
	armies_ui.rebuild()
	terrain.set_cloud_fade(cam.distance)
	terrain.set_param("cam_dist", cam.distance)
	ocean_near.follow(cam.position, cam.distance)
