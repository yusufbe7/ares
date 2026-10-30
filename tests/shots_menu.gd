## Bosh menyu va ekranlar skrinshotlari (xvfb bilan).
extends SceneTree
var f := 0
var out := "/tmp/claude-0/-home-claude/e8830df7-c78b-539d-9de2-1ed07f37074c/scratchpad/shots_m/"
const SEQ := ["main", "campaign", "operations", "armory", "garage", "customization", "settings", "vehicles"]
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	change_scene_to_file("res://ui/main.tscn")
func snap(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_jpg(out + n + ".jpg", 0.88)
	print("saved ", n)
func _process(_d: float) -> bool:
	f += 1
	var i := f / 40
	if f % 40 == 0 and i - 1 < SEQ.size():
		snap("%02d_%s" % [i, SEQ[i - 1]])
		if i < SEQ.size():
			root.get_node("ScreenManager").open(SEQ[i])
	return f > 40 * SEQ.size() + 2
