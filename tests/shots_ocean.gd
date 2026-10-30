## Okean va yaqin kadr skrinshotlari: qirg'oq yonida 4 masofa, quruqlik yaqindan, ikki marta bosish (fly_to).
extends SceneTree
var m
var f := 0
var out := "/tmp/claude-0/-home-claude/e8830df7-c78b-539d-9de2-1ed07f37074c/scratchpad/shots_o/"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	m = (load("res://campaign/campaign_map.tscn") as PackedScene).instantiate()
	root.add_child(m)
func snap(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_jpg(out + n + ".jpg", 0.9)
	print("saved ", n)
func view(p: Vector3, d: float) -> void:
	m.cam.position = Vector3(p.x, 0, p.z); m.cam.distance = d; m.cam._target_dist = d
func _process(_d: float) -> bool:
	f += 1
	var ui = m.ui
	var naples: Vector3 = m.terrain.px_to_world(Vector2((14.0 + 180.0) / 360.0 * 4320.0, (84.0 - 40.3) / 142.0 * 1704.0))
	var sea: Vector3 = m.terrain.px_to_world(Vector2((13.2 + 180.0) / 360.0 * 4320.0, (84.0 - 39.6) / 142.0 * 1704.0))
	match f:
		2:
			if ui.has_method("toggle_panels"): ui.toggle_panels()
			view(sea, 40.0)
		20: snap("01_sea_40")
		21: view(sea, 15.0)
		40: snap("02_sea_15")
		41: view(sea, 6.0)
		60: snap("03_sea_6")
		61: view(sea, 3.0)
		80: snap("04_sea_3")
		81: view(naples, 3.0)
		100: snap("05_coast_3")
		101:
			view(sea, 60.0)
			m.cam.fly_to(naples, 4.0)
		150:
			snap("06_flyto")
			print("fly ok: ", m.cam.position.distance_to(Vector3(naples.x, 0, naples.z)) < 0.5, " dist ", m.cam.distance)
			return true
	return false
