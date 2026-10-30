extends Node
## Main menu over a small 3D camp scene, so the first thing the game shows is
## the game and not a flat list.

var _time: float = 0.0
var _soldiers: Array = []

func open(_payload: Dictionary) -> void:
	_build_backdrop()
	_build_ui()

func _build_backdrop() -> void:
	var world := Node3D.new()
	add_child(world)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 7.0)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	cam.fov = 55.0
	world.add_child(cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-14, 150, 0)
	sun.light_color = Color(1.0, 0.72, 0.45)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.2, 0.33)
	sm.sky_horizon_color = Color(0.85, 0.5, 0.3)
	sm.ground_bottom_color = Color(0.1, 0.1, 0.12)
	sm.ground_horizon_color = Color(0.35, 0.28, 0.22)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_density = 0.01
	env.fog_light_color = Color(0.5, 0.4, 0.35)
	env_node.environment = env
	world.add_child(env_node)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.21, 0.17)
	gmat.roughness = 1.0
	ground.material_override = gmat
	ground.position = Vector3(0, -1.2, 0)
	world.add_child(ground)

	# Three soldiers around a fire, the first one in the player's loadout.
	for i in range(3):
		var s := _make_soldier(Color(0.33, 0.36, 0.28) if i > 0 else Color(0.4, 0.45, 0.33))
		var ang := TAU * float(i) / 3.0 + 0.6
		s.position = Vector3(cos(ang) * 1.9, -1.2, sin(ang) * 1.9 - 1.0)
		s.rotation.y = -ang + PI * 0.5
		world.add_child(s)
		_soldiers.append(s)

	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 3.0
	fire.omni_range = 9.0
	fire.position = Vector3(0, -0.7, -1.0)
	world.add_child(fire)

	# A vehicle parked behind them for scale.
	var tank := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(3.2, 1.3, 6.4)
	tank.mesh = tb
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.17, 0.18, 0.15)
	tank.material_override = tmat
	tank.position = Vector3(-6.5, -0.5, -6.0)
	tank.rotation.y = 0.5
	world.add_child(tank)

func _make_soldier(color: Color) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.26
	cm.height = 1.65
	body.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	body.material_override = mat
	body.position = Vector3(0, 0.85, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	hm.height = 0.32
	head.mesh = hm
	head.material_override = mat
	head.position = Vector3(0, 1.75, 0)
	root.add_child(head)
	var rifle := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.07, 0.1, 0.92)
	rifle.mesh = rb
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.1, 0.09, 0.08)
	rifle.material_override = rmat
	rifle.position = Vector3(0.2, 1.1, 0.35)
	root.add_child(rifle)
	return root

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := MarginContainer.new()
	UIKit.fullscreen(root)
	root.add_theme_constant_override("margin_left", 64)
	root.add_theme_constant_override("margin_top", 48)
	root.add_theme_constant_override("margin_bottom", 48)
	layer.add_child(root)

	var col := UIKit.vbox(10)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.custom_minimum_size = Vector2(340, 0)
	root.add_child(col)

	col.add_child(UIKit.title("WORLD FRONTIER"))
	col.add_child(UIKit.label("Global strategiya va 3D jang maydoni", 14, UIKit.MUTED))
	col.add_child(UIKit.label("2041 — muqobil tarix", 12, UIKit.MUTED))
	col.add_child(UIKit.spacer(20))

	var entries := [
		{"text": "CUSTOM BATTLE", "hint": "O'zing xohlagan ikkita armiyani tuzib jang qil.",
		"action": func(): GameState.go("custom_battle", {})},
		{"text": "CAMPAIGN", "hint": "Topshiriqlar va ketma-ket janglar.",
		"action": func(): GameState.go("campaign", {})},
		{"text": "MULTIPLAYER", "hint": "Do'stlar bilan onlayn jang va global urush.",
		"action": func(): GameState.go("lobby", {})},
		{"text": "SANDBOX", "hint": "Erkin tajriba: texnika va botlarni sina.",
		"action": func(): GameState.go("custom_battle", {"sandbox": true})},
		{"text": "GLOBAL WAR", "hint": "Dunyo xaritasi, diplomatiya, iqtisod va urushlar.",
		"action": _start_global_war},
	]
	for e in entries:
		var b := UIKit.button(str(e["text"]))
		b.tooltip_text = str(e["hint"])
		b.pressed.connect(e["action"])
		col.add_child(b)

	col.add_child(UIKit.spacer(6))
	var load_btn := UIKit.button("DAVOM ETISH", 15)
	load_btn.pressed.connect(_continue_game)
	col.add_child(load_btn)

	var set_btn := UIKit.button(Loc.t("menu.settings"), 15)
	set_btn.pressed.connect(func(): GameState.go("settings", {}))
	col.add_child(set_btn)

	var exit_btn := UIKit.button(Loc.t("menu.exit"), 15)
	exit_btn.pressed.connect(func(): get_tree().quit())
	col.add_child(exit_btn)

	col.add_child(UIKit.spacer(14))
	var hint := UIKit.label(
		"CUSTOM BATTLE — xarita, fasl, ob-havo, ikkala armiya va g'alaba shartini o'zing tanlaysan.\n"
		+ "GLOBAL WAR — davlat tanlab, dunyo xaritasida urush olib borasan.", 13, UIKit.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

func _process(delta: float) -> void:
	_time += delta
	for i in range(_soldiers.size()):
		var s: Node3D = _soldiers[i]
		if is_instance_valid(s):
			s.position.y = -1.2 + sin(_time * 1.3 + float(i)) * 0.015

func _start_global_war() -> void:
	Net.start_offline()
	GameState.mode = GameState.Mode.GLOBAL_WAR
	GameState.start_new_world(0)
	GameState.go("nation_select", {})

func _continue_game() -> void:
	if GameState.load_world():
		GameState.mode = GameState.Mode.GLOBAL_WAR
		if GameState.local_nation == "":
			GameState.go("nation_select", {})
		else:
			GameState.go("world", {})
	else:
		GameState.notify("Saqlangan o'yin topilmadi.", "warn")
