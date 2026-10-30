## Everything the player can build, train or call in, and how each building looks.
## A model is a list of parts: [glb file, offset (x, z) in metres, yaw degrees, scale].
## Each part sits with its footprint centre at the offset and its bottom on the ground.
class_name BuildDefs
extends RefCounted

const A := "res://assets/"

const STRUCTURES := {
	# ------------------------------------------------------------------ BASE
	"hq": {"name": "Command Post", "cat": "", "cost": 0, "work": 60.0, "size": Vector2(16, 14), "hp": 900.0,
		"zone": 110.0, "income": 2.0, "flag": true, "desc": "Headquarters. Lose it and the operation fails.",
		"parts": [["props/sandbag_bunker.glb", Vector2(0, -1.5), 0.0, 1.0], ["props/hesco_wall.glb", Vector2(-4.6, 5.6), 0.0, 1.0],
			["props/hesco_wall.glb", Vector2(4.6, 5.6), 0.0, 1.0], ["props/army_tent.glb", Vector2(5.3, -2.0), 90.0, 0.85],
			["props/ammo_crates.glb", Vector2(-5.8, -3.2), 15.0, 1.0]]},
	"fob": {"name": "Forward Base", "cat": "BASE", "cost": 175, "work": 120.0, "size": Vector2(14, 12), "hp": 550.0,
		"zone": 80.0, "income": 1.0, "flag": true, "desc": "Extends the build zone and adds +1 supply/s.",
		"parts": [["props/sandbag_bunker.glb", Vector2(0, -1), 0.0, 0.9], ["props/hesco_wall.glb", Vector2(-3.4, 4.6), 0.0, 1.0],
			["props/hesco_wall.glb", Vector2(3.4, 4.6), 0.0, 1.0], ["props/ammo_crates.glb", Vector2(-5.0, -2.0), 0.0, 1.0]]},
	"barracks": {"name": "Barracks", "cat": "BASE", "cost": 170, "work": 140.0, "size": Vector2(15, 8), "hp": 500.0,
		"desc": "Trains infantry.", "parts": [["container_building.glb", Vector2(0, 0), 0.0, 1.0]]},
	"factory": {"name": "Factory", "cat": "BASE", "cost": 340, "work": 220.0, "size": Vector2(20, 16), "hp": 800.0,
		"desc": "Builds vehicles and tanks.", "parts": [["industrial_building.glb", Vector2(0, 0), 0.0, 1.0]]},
	"research": {"name": "Research", "cat": "BASE", "cost": 260, "work": 170.0, "size": Vector2(9, 9), "hp": 400.0,
		"desc": "Unlocks MG nests, tanks, drones and fire support.", "antenna": true,
		"parts": [["desert_house.glb", Vector2(0, 0), 0.0, 1.3]]},
	"medical": {"name": "Field Hospital", "cat": "BASE", "cost": 120, "work": 90.0, "size": Vector2(10, 8), "hp": 300.0,
		"desc": "Wounded soldiers nearby stop bleeding and heal.", "groups": ["medical"],
		"parts": [["props/medical_tent.glb", Vector2(0, 0), 0.0, 1.0]]},
	"depot": {"name": "Supply Depot", "cat": "BASE", "cost": 150, "work": 100.0, "size": Vector2(8, 7), "hp": 300.0,
		"income": 1.5, "desc": "+1.5 supply/s.",
		"parts": [["props/army_tent.glb", Vector2(0, -1.2), 0.0, 0.8], ["props/ammo_crates.glb", Vector2(-1.2, 2.4), 0.0, 1.0],
			["props/crates_barrels.glb", Vector2(2.4, 2.4), 90.0, 0.8]]},
	# ------------------------------------------------------------------ DEFENCE
	"sandbags": {"name": "Sandbags", "cat": "DEF", "cost": 40, "work": 24.0, "size": Vector2(8, 1.6), "hp": 160.0,
		"cover": true, "desc": "Cover for infantry.", "parts": [["sandbag_wall.glb", Vector2(0, 0), 0.0, 1.0]]},
	"hesco": {"name": "HESCO Wall", "cat": "DEF", "cost": 60, "work": 30.0, "size": Vector2(4.4, 1.1), "hp": 450.0,
		"cover": true, "desc": "Earth-filled barrier: stops bullets and blast.", "parts": [["props/hesco_wall.glb", Vector2(0, 0), 0.0, 1.0]]},
	"bunker": {"name": "Bunker", "cat": "DEF", "cost": 160, "work": 70.0, "size": Vector2(5.8, 4.6), "hp": 650.0,
		"cover": true, "desc": "Sandbag bunker with a timber roof. Protects from shells.", "parts": [["props/sandbag_bunker.glb", Vector2(0, 0), 0.0, 1.0]]},
	"barriers": {"name": "Barriers", "cat": "DEF", "cost": 50, "work": 30.0, "size": Vector2(8, 3), "hp": 300.0,
		"cover": true, "desc": "Hard cover, stops vehicles.", "parts": [["props/checkpoint_barriers.glb", Vector2(0, 0), 0.0, 1.0]]},
	"mines": {"name": "Mines", "cat": "DEF", "cost": 6, "work": 10.0, "size": Vector2(5, 5), "hp": 40.0, "passable": true,
		"desc": "Hidden minefield: blows up the first enemies (or a tank) that walk over it. 3 charges.", "parts": []},
	"wire": {"name": "Barbed Wire", "cat": "DEF", "cost": 4, "work": 15.0, "size": Vector2(4.5, 1.0), "hp": 80.0,
		"groups": ["wire"], "passable": true, "desc": "Slows infantry to a crawl.", "parts": [["props/barbed_wire.glb", Vector2(0, 0), 0.0, 1.0]]},
	"hedgehog": {"name": "Hedgehogs", "cat": "DEF", "cost": 25, "work": 15.0, "size": Vector2(5.4, 1.8), "hp": 200.0,
		"desc": "Anti-tank obstacles.", "parts": [["props/hedgehog.glb", Vector2(-1.9, 0), 0.0, 1.0],
			["props/hedgehog.glb", Vector2(0, 0), 40.0, 1.0], ["props/hedgehog.glb", Vector2(1.9, 0), 15.0, 1.0]]},
	"camo": {"name": "Camo Net", "cat": "DEF", "cost": 15, "work": 24.0, "size": Vector2(7, 7), "hp": 60.0,
		"groups": ["camo"], "camo": true, "passable": true, "desc": "FPV drones can't see soldiers under it.", "parts": []},
	"mg": {"name": "MG Nest", "cat": "DEF", "cost": 220, "work": 80.0, "size": Vector2(7, 6.5), "hp": 400.0,
		"cover": true, "needs": "research", "gunner": true, "desc": "Fortified machine gun with its own gunner.",
		"parts": [["props/mg_nest.glb", Vector2(0, 0), 0.0, 1.0]]},
	# ------------------------------------------------------------------ enemy
	"stronghold": {"name": "Insurgent Stronghold", "cat": "", "cost": 0, "work": 1.0, "size": Vector2(26, 20), "hp": 1400.0,
		"flag": true, "desc": "Destroy it to win.",
		"parts": [["props/trench_bunker.glb", Vector2(0, 0), 0.0, 1.0], ["props/mg_nest.glb", Vector2(-9, 4), 90.0, 1.0],
			["props/medical_tent.glb", Vector2(8, -4), 0.0, 1.0], ["props/crates_barrels.glb", Vector2(8, 5), 90.0, 1.0],
			["props/checkpoint_barriers.glb", Vector2(-2, 9), 0.0, 1.0], ["props/crates_barrels.glb", Vector2(-9, -6), 0.0, 1.0]]},
}

## drawn, not placed: cost is per metre
const TRENCH := {"name": "Trench", "cat": "DEF", "cost": 1, "per_meter": true,
	"desc": "Draw it: click a start point, then click for every corner. Soldiers dig it, the ground really sinks. Right click to stop."}

const UNITS := {
	"rifle": {"name": "Rifle Squad", "cat": "INF", "cost": 120, "time": 14.0, "needs": "barracks", "men": 4, "desc": "4 riflemen."},
	"medic": {"name": "Medic", "cat": "INF", "cost": 70, "time": 9.0, "needs": "barracks", "men": 1, "medic": true, "desc": "Treats the wounded twice as fast."},
	"rpg": {"name": "RPG Team", "cat": "INF", "cost": 140, "time": 16.0, "needs": "barracks", "men": 2, "rpg": 4, "desc": "2 anti-tank soldiers."},
	"mgteam": {"name": "MG Team", "cat": "INF", "cost": 160, "time": 16.0, "needs": "barracks+research", "men": 2, "mg": true, "desc": "Long bursts, pins the enemy down."},
	"humvee": {"name": "Humvee", "cat": "ARMOR", "cost": 180, "time": 18.0, "needs": "factory", "desc": "Fast scout car."},
	"t72": {"name": "T-72 Tank", "cat": "ARMOR", "cost": 450, "time": 32.0, "needs": "factory+research", "desc": "Main battle tank."},
	"mi24": {"name": "Mi-24 Gunship", "cat": "ARMOR", "cost": 600, "time": 40.0, "needs": "factory+research", "desc": "Attack helicopter: rocket salvos (right-click a target or a house)."},
}

const SUPPORT := {
	"drone": {"name": "FPV Drone", "cat": "SUPPORT", "cost": 60, "cooldown": 12.0, "needs": "research", "desc": "Kamikaze drone flies to the target."},
	"artillery": {"name": "Artillery", "cat": "SUPPORT", "cost": 200, "cooldown": 45.0, "needs": "research", "desc": "6 shells on the target."},
	"airstrike": {"name": "Air Strike", "cat": "SUPPORT", "cost": 400, "cooldown": 90.0, "needs": "research", "desc": "F-117 bombing run."},
}

static var _aabbs := {}


static func get_def(key: String) -> Dictionary:
	if key == "trench": return TRENCH
	if STRUCTURES.has(key): return STRUCTURES[key]
	if UNITS.has(key): return UNITS[key]
	if SUPPORT.has(key): return SUPPORT[key]
	return {}


static func aabb_of(path: String) -> AABB:
	if _aabbs.has(path):
		return _aabbs[path]
	var n: Node3D = load(path).instantiate()
	var acc := [null]
	_merge(n, Transform3D.IDENTITY, acc, true)
	n.free()
	var a: AABB = acc[0] if acc[0] != null else AABB()
	_aabbs[path] = a
	return a


static func aabb_of_node(n: Node3D) -> AABB:
	var acc := [null]
	_merge(n, Transform3D.IDENTITY, acc, true)
	return acc[0] if acc[0] != null else AABB()


static func _merge(n: Node, xf: Transform3D, acc: Array, root := false) -> void:
	var t := xf
	if n is Node3D and not root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as Node3D).visible:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_merge(c, t, acc)


## Builds the visual model (local space, footprint centred, ground at y = 0).
static func make_model(key: String, team := 0) -> Node3D:
	var d: Dictionary = STRUCTURES[key]
	var root := Node3D.new()
	root.name = "Model"
	for p in d.parts:
		var path: String = A + p[0]
		if not ResourceLoader.exists(path):
			continue
		var a := aabb_of(path)
		var holder := Node3D.new()
		var inst: Node3D = load(path).instantiate()
		holder.add_child(inst)
		inst.position = -Vector3(a.get_center().x, a.position.y, a.get_center().z)
		holder.rotation.y = deg_to_rad(p[2])
		holder.scale = Vector3.ONE * float(p[3])
		holder.position = Vector3(p[1].x, 0, p[1].y)
		root.add_child(holder)
	if d.get("camo", false):
		root.add_child(camo_net())
	if d.get("antenna", false):
		root.add_child(_antenna(Vector3(2.6, 0, -2.6)))
	if d.get("flag", false):
		root.add_child(flag_pole(team, Vector3(-d.size.x * 0.5 + 1.0, 0, d.size.y * 0.5 - 1.0)))
	return root


static func flag_pole(team: int, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Flag"
	n.position = at
	var pole := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.05; cy.bottom_radius = 0.07; cy.height = 8.0
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.55, 0.55); pm.metallic = 0.6; pm.roughness = 0.4
	cy.material = pm
	pole.mesh = cy
	pole.position.y = 4.0
	n.add_child(pole)
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 1.3)
	cloth.mesh = q
	cloth.position = Vector3(1.35, 7.25, 0)
	cloth.material_override = flag_material(team)
	n.add_child(cloth)
	return n


static func flag_material(team: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/ui/flag_player.png" if team == 0 else "res://assets/ui/flag_insurgent.png")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	return m


static func camo_net() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(7, 7)
	pm.subdivide_width = 6; pm.subdivide_depth = 6
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.noise = noise; tex.width = 256; tex.height = 256
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.22, 0.25, 0.14), Color(0.32, 0.3, 0.18), Color(0.45, 0.42, 0.28), Color(0.55, 0.5, 0.33)])
	tex.color_ramp = g
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	pm.material = m
	mi.mesh = pm
	mi.position.y = 2.3
	root.add_child(mi)
	for c in [Vector3(3.2, 0, 3.2), Vector3(-3.2, 0, 3.2), Vector3(3.2, 0, -3.2), Vector3(-3.2, 0, -3.2)]:
		var pole := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.05; cy.bottom_radius = 0.06; cy.height = 2.3
		pole.mesh = cy
		pole.position = c + Vector3.UP * 1.15
		root.add_child(pole)
	return root


static func _antenna(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.52, 0.5); m.metallic = 0.7; m.roughness = 0.4
	var mast := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.04; cy.bottom_radius = 0.09; cy.height = 11.0
	cy.material = m
	mast.mesh = cy
	mast.position.y = 5.5
	n.add_child(mast)
	for h in [4.0, 7.0, 10.0]:
		var bar := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(1.4 - h * 0.08, 0.05, 0.05)
		bx.material = m
		bar.mesh = bx
		bar.position.y = h
		n.add_child(bar)
	var dish := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.7; sp.height = 0.5; sp.is_hemisphere = true
	sp.material = m
	dish.mesh = sp
	dish.position = Vector3(0.5, 8.0, 0)
	dish.rotation.z = deg_to_rad(70)
	n.add_child(dish)
	return n
