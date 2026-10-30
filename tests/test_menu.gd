## Bosh menyu oqimi sinovi: godot --headless --path . -s res://tests/test_menu.gd
## Ekranlar ochiladi, sotib olish kreditni kamaytiradi, sozlama saqlanadi, DEPLOY jangni ochadi,
## jangdan menyuga qaytiladi, kampaniya sahnasi ochiladi.
extends SceneTree

var f := 0
var errors := 0
var sm: Node
var gs: Node
var credits0 := 0

func ok(c: bool, what: String) -> void:
	print(("OK    " if c else "XATO  ") + what)
	if not c: errors += 1

func _initialize() -> void:
	change_scene_to_file("res://ui/main.tscn")

func _process(_d: float) -> bool:
	f += 1
	sm = root.get_node("ScreenManager")
	gs = root.get_node("GameSession")
	match f:
		10:
			ok(current_scene != null and current_scene.has_method("show_screen"), "o'yin bosh menyudan boshlanadi (ui/main.tscn)")
			ok(sm.current() == "country", "birinchi ekran: davlat tanlash")
			var cs = current_scene.holder.get_child(current_scene.holder.get_child_count() - 1)
			ok(cs.has_method("_start") and cs._sel.country.code != "", "davlat tanlangan: " + cs._sel.country.code)
			cs._select(CountryInfo.by_code("UZB"), true)
			cs._diff.selected = 2
			cs._start()
			ok(sm.current() == "main" and gs.campaign_setup.country == "UZB" and gs.campaign_setup.difficulty == 3, "START -> bosh menyu, sozlamalar saqlandi")
			var pv = current_scene.preview
			ok(pv.soldiers.size() == 3 and pv.soldiers[0].get_child_count() > 0, "menyuda o'yindagi 3 askar (soldier.glb)")
			ok(pv.size.x > 100, "askarlar ko'rinishi ekran o'lchamida: %s" % pv.size)
		12:
			for id in ["campaign", "operations", "armory", "garage", "customization", "settings", "vehicles"]:
				sm.open(id)
				ok(sm.current() == id, "ekran ochildi: " + id)
			sm.back()
			ok(sm.current() == "settings", "Esc / orqaga: oldingi ekran (settings)")
			sm.open("main")
		20:
			var p = gs.profile
			credits0 = p.credits
			var v = gs.item("vehicles", "humvee")
			var had: bool = "humvee" in p.owned_vehicles
			var shop: GDScript = load("res://ui/shop.gd")        # autoload'lar tayyor bo'lgach yuklanadi
			var xp0: int = p.xp
			if not had:
				p.xp = 0
				ok(not shop.buy_vehicle("humvee") and p.credits == credits0, "daraja yetmasa sotib olinmaydi (Humvee %d-daraja)" % v.required_level)
				p.xp = 100000                                     # vaqtincha yuqori daraja
				ok(shop.buy_vehicle("humvee") and p.credits == credits0 - v.price, "Humvee sotib olindi: kredit %d -> %d" % [credits0, p.credits])
				# profilni asl holiga qaytaramiz (sinov o'yinchi saqlanmasini buzmasin)
				p.owned_vehicles.erase("humvee")
				p.credits = credits0
				p.xp = xp0
				gs.save()
			var st: GDScript = load("res://ui/settings/settings.gd")
			var s: Dictionary = st.load_all()
			s.gameplay.camera_speed = 1.7
			st.save_all(s)
			ok(is_equal_approx(float(st.load_all().gameplay.camera_speed), 1.7), "sozlama saqlanadi (camera_speed)")
			s.gameplay.camera_speed = 1.0
			st.save_all(s)
			var op = gs.item("operations", "defend")
			ok(op != null, "operatsiya topildi: defend")
			load("res://ui/deploy.gd").start(op)
		200:
			ok(current_scene != null and current_scene.scene_file_path == "res://demo/demo.tscn", "DEPLOY jang sahnasini ochdi: %s" % (current_scene.scene_file_path if current_scene else "-"))
			sm.goto_scene(sm.MAIN)
		300:
			ok(current_scene != null and current_scene.has_method("show_screen"), "jangdan bosh menyuga qaytildi")
			sm.open_campaign()
		420:
			ok(current_scene != null and current_scene.scene_file_path == "res://campaign/campaign_map.tscn", "kampaniya (dunyo xaritasi) ochildi")
			print("XATOLAR: ", errors)
			return true
	return false
