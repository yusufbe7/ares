## Screenshots for visual checks: xvfb-run godot --path . -s res://tests/shots.gd
extends SceneTree

var demo: Node3D
var f := 0
var out := "/tmp/claude-0/-home-claude/e8830df7-c78b-539d-9de2-1ed07f37074c/scratchpad/shots/"
var plan := []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var g: GDScript = load("res://demo/demo.gd")
	g.set("_auto_mode", "assault")
	demo = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)

func cam(x: float, z: float, dist: float, yaw := 0.0, pitch := 52.0) -> void:
	demo.cam.position = Vector3(x, demo.ground_height(x, z), z)
	demo.cam.distance = dist
	demo.cam.rotation.y = deg_to_rad(yaw)
	demo.cam.pitch_deg = pitch

func snap(n: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_jpg(out + n + ".jpg", 0.85)
	print("saved ", n)

func _process(_d: float) -> bool:
	f += 1
	match f:
		5: cam(20, -135, 95, -20)
		40: snap("01_village")
		41: cam(5, -50, 110, 0)
		70: snap("02_assembly")
		71:
			cam(-5, -110, 45, -30, 48)
		100:
			snap("03_house_close")
			var h: EuropeHouse = demo.map.houses[1]
			RtsExplosion.spawn(demo, h.center + Vector3(0, 2.5, 0) + Basis(Vector3.UP, h.yaw) * Vector3(0, 0, h.size.y * 0.5), 1.2)
		112: snap("04_hit")
		160: snap("05_after")
		161:
			var h: EuropeHouse = demo.map.houses[1]
			RtsExplosion.spawn(demo, h.center + Vector3(1, 1.0, 0), 3.0)
		175: snap("06_bomb")
		260: snap("07_collapse")
		261: cam(-5, -110, 70, -30, 55)
		300: snap("08_ruin")
		301: demo.map.set_winter(false)
		330: snap("09_summer")
		331:
			demo.map.set_winter(true)
			cam(-150, 180, 120, 0)
		370:
			snap("10_far")
			return true
	return false
