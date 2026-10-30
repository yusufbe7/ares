## Askar ko'rinishi (qayta ishlatiladigan): SubViewport + o'yindagi askar modeli (soldier.glb) + kamera + yoritish.
## Orqa fon: o'yindagi tayyor modellardan lager (chodir, qutilar, HESCO, T-72, Mi-24), quyosh botishi, chang.
## Rejimlar: "menu" - 3 askar yonma-yon (1-si o'yinchi loadouti), "custom" - bitta askar yaqindan,
## sichqoncha bilan aylantirish (chap tugma sudrash) va g'ildirak bilan yaqinlashtirish.
class_name SoldierPreview
extends SubViewportContainer

const A := "res://assets/"
const SOLDIER := "res://assets/soldier.glb"

var viewport: SubViewport
var camera: Camera3D
var soldiers: Array[Node3D] = []
var mode := "menu"
var _yaw := 0.0
var _zoom := 1.0
var _drag := false
var _cam_target := Vector3(0, 1.2, 6.2)
var _look := Vector3(0, 1.05, 0)


func _ready() -> void:
	stretch = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.positional_shadow_atlas_size = 2048
	add_child(viewport)
	_build_env()
	_build_camp()
	for k in 3:
		soldiers.append(_soldier(Vector3((k - 1) * 1.25, 0, -0.35 * absf(k - 1)), deg_to_rad((1 - k) * 14.0), k * 0.7))
	camera = Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	camera.position = _cam_target
	camera.look_at(_look)
	refresh_loadouts()
	EventBus.loadout_changed.connect(refresh_loadouts)
	EventBus.weapon_equipped.connect(_refresh_weapons)


func _build_env() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.13, 0.17, 0.26)
	sky.sky_horizon_color = Color(0.95, 0.55, 0.28)
	sky.ground_horizon_color = Color(0.45, 0.3, 0.2)
	sky.ground_bottom_color = Color(0.08, 0.07, 0.06)
	sky.sun_angle_max = 12.0
	var s := Sky.new()
	s.sky_material = sky
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.5, 0.32)
	env.fog_density = 0.012
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-14), deg_to_rad(-128), 0)
	sun.light_color = Color(1.0, 0.72, 0.45)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	viewport.add_child(sun)
	# asosiy yorug'lik oldindan (kamera tomondan, iliq): quyosh orqada qolsa ham askarlar ko'rinib tursin
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-28), deg_to_rad(28), 0)
	key.light_color = Color(1.0, 0.82, 0.62)
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 25.0
	viewport.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.5, 2.0, 3.5)
	fill.light_color = Color(0.6, 0.7, 0.9)
	fill.light_energy = 0.9
	fill.omni_range = 10.0
	viewport.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	nt.noise = FastNoiseLite.new()
	nt.seamless = true
	gm.albedo_texture = nt
	gm.albedo_color = Color(0.42, 0.34, 0.26)
	gm.uv1_scale = Vector3(40, 40, 1)
	gm.roughness = 1.0
	ground.material_override = gm
	viewport.add_child(ground)
	# chang zarralari (quyosh nurida)
	var dust := GPUParticles3D.new()
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(6, 2, 3)
	pmat.gravity = Vector3(0.12, 0.02, 0)
	pmat.initial_velocity_min = 0.02
	pmat.initial_velocity_max = 0.12
	dust.process_material = pmat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.025)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.8, 0.55, 0.5)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = dm
	dust.draw_pass_1 = qm
	dust.amount = 160
	dust.lifetime = 9.0
	dust.position = Vector3(0, 1.8, 0)
	viewport.add_child(dust)


## Lager: o'yindagi tayyor modellar (yangi model qo'shilmagan).
func _build_camp() -> void:
	for e in [["props/army_tent.glb", Vector3(-6.5, 0, -9), 25.0, 1.0], ["props/medical_tent.glb", Vector3(8, 0, -13), -20.0, 1.0],
			["props/ammo_crates.glb", Vector3(-2.8, 0, -3.2), 15.0, 1.0], ["props/crates_barrels.glb", Vector3(3.4, 0, -3.6), -30.0, 1.0],
			["props/hesco_wall.glb", Vector3(-4.5, 0, -6), 0.0, 1.0], ["props/hesco_wall.glb", Vector3(5.5, 0, -6.5), 8.0, 1.0],
			["sandbag_wall.glb", Vector3(2.2, 0, -2.0), -10.0, 1.0], ["container_building.glb", Vector3(-15, 0, -20), 30.0, 1.0],
			["t72.glb", Vector3(10.5, 0, -16), -35.0, 1.0], ["mi24.glb", Vector3(-22, 0, -34), 60.0, 1.0],
			["props/checkpoint_barriers.glb", Vector3(-1, 0, -12), 0.0, 1.0]]:
		var path: String = A + e[0]
		if not ResourceLoader.exists(path):
			continue
		var n: Node3D = load(path).instantiate()
		n.position = e[1]
		n.rotation.y = deg_to_rad(e[2])
		n.scale = Vector3.ONE * e[3]
		viewport.add_child(n)
		for ap in n.find_children("*", "AnimationPlayer", true, false):
			(ap as AnimationPlayer).stop()


func _soldier(pos: Vector3, yaw: float, delay: float) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	viewport.add_child(root)
	if not ResourceLoader.exists(SOLDIER):
		return root
	var m: Node3D = load(SOLDIER).instantiate()
	root.add_child(m)
	var socket := m.find_child("Weapon_Socket", true, false)
	if socket:
		var w := _weapon_scene()
		if w:
			var inst := w.instantiate()
			inst.name = "Weapon"
			socket.add_child(inst)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		if ap.has_animation("Idle_Rifle"):
			ap.get_animation("Idle_Rifle").loop_mode = Animation.LOOP_LINEAR
			ap.play("Idle_Rifle")
			ap.seek(delay, true)
	return root


## 1-askar: o'yinchining faol loadouti; qolganlari 2- va 3-slot (namuna).
func refresh_loadouts() -> void:
	var p: PlayerProfile = GameSession.profile
	p.loadout()
	var order := [p.active_loadout, (p.active_loadout + 1) % 3, (p.active_loadout + 2) % 3]
	var pos := [1, 0, 2]
	for k in 3:
		if soldiers[pos[k]].get_child_count() > 0:
			LoadoutApplier.apply(soldiers[pos[k]].get_child(0), p.loadouts[order[k]])


func set_mode(m: String) -> void:
	mode = m
	_yaw = 0.0
	_zoom = 1.0
	for k in 3:
		soldiers[k].visible = m == "menu" or k == 1
	soldiers[1].rotation.y = 0.0


func _gui_input(e: InputEvent) -> void:
	if mode != "custom":
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 0.9, 0.45, 1.3)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 0.9, 0.45, 1.3)
	elif e is InputEventMouseMotion and _drag:
		_yaw += (e as InputEventMouseMotion).relative.x * 0.01


func _process(delta: float) -> void:
	if camera == null:
		return
	var mp := get_viewport().get_mouse_position() / get_viewport().get_visible_rect().size - Vector2(0.5, 0.5)
	if mode == "menu":
		# askarlar menyu va bozor paneli orasidagi bo'sh joyda turadi; yengil parallax
		_cam_target = Vector3(0.25 + mp.x * 0.35, 1.25 - mp.y * 0.15, 6.6)
		_look = Vector3(0.25, 1.0, 0)
	else:
		_cam_target = Vector3(0.0, 1.15 + (1.0 - _zoom) * 0.3, 1.2 + 3.4 * _zoom)
		_look = Vector3(0.0, 1.0 + (1.0 - _zoom) * 0.35, 0)
		soldiers[1].rotation.y = lerp_angle(soldiers[1].rotation.y, _yaw, clampf(delta * 10.0, 0.0, 1.0))
	camera.position = camera.position.lerp(_cam_target, clampf(delta * 4.0, 0.0, 1.0))
	camera.look_at(_look)


## O'yinchi taqqan qurol modeli (Armory dan), bo'lmasa AK-47.
func _weapon_scene() -> PackedScene:
	var w: Resource = GameSession.item("weapons", GameSession.profile.equipped_weapon) if GameSession.profile else null
	var p: String = str(w.model) if w and str(w.model) != "" else A + "weapons/ak47_rifle.tscn"
	return load(p) if ResourceLoader.exists(p) else null


## Qurol almashtirilganda menyudagi askarlar qo'lidagi qurol ham almashadi.
func _refresh_weapons(_id := "") -> void:
	var w := _weapon_scene()
	if w == null:
		return
	for s in soldiers:
		var socket := s.find_child("Weapon_Socket", true, false)
		if socket == null:
			continue
		for c in socket.get_children():
			c.queue_free()
		var inst := w.instantiate()
		inst.name = "Weapon"
		socket.add_child(inst)
