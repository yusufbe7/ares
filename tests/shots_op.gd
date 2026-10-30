extends SceneTree
var demo: Node3D
var f := 0
var out := "/tmp/claude-0/-home-claude/e8830df7-c78b-539d-9de2-1ed07f37074c/scratchpad/shots_op/"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	demo = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
func snap(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_jpg(out + n + ".jpg", 0.85)
	print("saved ", n)
func _process(_d: float) -> bool:
	f += 1
	var op = demo.mode_node
	match f:
		30: snap("01_start")
		31:
			demo.cam.position = Vector3(25, demo.ground_height(25, -140), -140)
			demo.cam.distance = 120.0
			op.artillery(op.zones[1].pos + Vector3(10, 0, 20), 12.0, 6, 1)
		45: snap("02_village_warning")
		46:
			op.supply = 300
			op.open_build()
		55:
			snap("03_radial")
			op.hud._radial.visible = false
		120:
			snap("04_after_arty")
			return true
	return false
