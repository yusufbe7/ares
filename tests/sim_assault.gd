## Headless smoke test: godot --headless --path . -s res://tests/sim_assault.gd
extends SceneTree

var demo: Node3D
var t := 0.0
var _shots := 0

func _initialize() -> void:
	var g: GDScript = load("res://demo/demo.gd")
	g.set("_auto_mode", OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "assault")
	var scn: PackedScene = load("res://demo/demo.tscn")
	demo = scn.instantiate()
	root.add_child(demo)
	print("started")

func _process(delta: float) -> bool:
	if demo.get("mode") == null:
		return true
	t += delta
	if demo.mode == "assault" and _shots < 6 and t > 3.0 + _shots * 2.0:
		var h: EuropeHouse = demo.map.houses[_shots % 3]
		var p: Vector3 = h.center + Vector3(0, 2.0, 0) + Basis(Vector3.UP, h.yaw) * Vector3(0, 0, h.size.y * 0.5)
		RtsExplosion.spawn(demo, p, 1.2 if _shots < 3 else 3.5)
		print("t=%.1f blast at %s  -> %s integrity %.2f ruined=%s" % [t, p, h.name, h.integrity(), h.ruined])
		_shots += 1
	if int(t * 10) % 50 == 0 and fmod(t, 5.0) < delta * 1.01:
		var act := 0
		for hh in demo.map.houses:
			act += hh.get_node("Debris").get_child_count()
		var ea: int = demo._alive(demo.enemies).size()
		var pa: int = demo._alive(demo.squad).size()
		print("t=%.0f  fps=%d  debris=%d  active=%d  ours=%d  insurgents=%d" % [t, Engine.get_frames_per_second(), act, EuropeHouse._active.size(), pa, ea])
	if t > float(OS.get_environment("SECS") if OS.get_environment("SECS") != "" else "30"):
		for hh in demo.map.houses:
			print(hh.name, " integrity=%.2f ruined=%s" % [hh.integrity(), hh.ruined])
		return true
	return false
