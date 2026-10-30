## Skrinshotlar: dunyo, tanlash, o'yin (uzoq / o'rta / yaqin), ko'rinish rejimlari, tillar.
extends SceneTree
var m
var f := 0
var out := "/tmp/claude-0/-home-claude/e8830df7-c78b-539d-9de2-1ed07f37074c/scratchpad/shots_w/"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Loc.set_lang("en", false)
	m = (load("res://campaign/campaign_map.tscn") as PackedScene).instantiate()
	root.add_child(m)
func snap(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_jpg(out + n + ".jpg", 0.88)
	print("saved ", n)
func view(x: float, z: float, d: float) -> void:
	m.cam.position = Vector3(x, 0, z)
	m.cam.distance = d
	m.cam._target_dist = d
func at(code: String) -> Vector3:
	return m.province_world(m.data.countries[m._country_by_code(code)].capital)
func _process(_d: float) -> bool:
	f += 1
	var bus: Node = root.get_node("EventBus")
	match f:
		2: view(10, -2, 300)
		14: snap("01_world_choose")
		15:
			var p := at("DEU"); view(p.x + 4, p.z + 6, 110)
			m.preview_country(m._country_by_code("DEU"))
			m._hover(m.data.countries[m._country_by_code("FRA")].capital)
		27: snap("02_europe_choose")
		28:
			m.choose_country(m._country_by_code("UZB"))
			var p := at("UZB"); view(p.x, p.z + 4, 120)
		40: snap("03_play_asia")
		41:
			var p := at("UZB"); view(p.x, p.z, 26)
		53: snap("04_play_near")
		54:
			bus.map_view_changed.emit(2)
			var p := at("UZB"); view(p.x - 10, p.z + 4, 90)
		66: snap("05_resource_view")
		67:
			bus.map_view_changed.emit(1)
			m.ui.toggle_panels()
			var p := at("ITA"); view(p.x, p.z + 3, 70)
		80: snap("06_terrain_collapsed")
		81:
			bus.map_view_changed.emit(0)
			bus.tab_changed.emit("economy")
		92: snap("07_economy")
		93:
			bus.tab_changed.emit("world_map")
			Loc.set_lang("ru", false); m.apply_language(); bus.language_changed.emit()
			view(10, -2, 260)
		105:
			snap("08_ru_world")
			Loc.set_lang("en", false)
			return true
	return false
