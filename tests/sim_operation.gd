## Headless run of the OPERATION: godot --headless --path . -s res://tests/sim_operation.gd
extends SceneTree

var demo: Node3D
var t := 0.0
var f := 0
var worst := 0.0
var last := 0
var _acted := {}

func _initialize() -> void:
	demo = (load("res://demo/demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)

func once(k: String) -> bool:
	if _acted.has(k): return false
	_acted[k] = true
	return true

func _process(delta: float) -> bool:
	if demo.get("mode") == null:
		return true
	f += 1
	t += delta
	var now := Time.get_ticks_usec()
	if f > 20: worst = maxf(worst, (now - last) / 1000.0)
	last = now
	var op = demo.mode_node
	if t > 2 and once("squad"): op.action("squad")
	if t > 4 and once("tank"):
		op.supply = 500.0
		op.action("tank")
	if t > 6 and once("arty"):
		op.supply = 500.0
		op._on_target("artillery", op.zones[1].pos)
	if t > 8 and once("order"):
		# send every soldier to take point A
		var men: Array = demo.get_tree().get_nodes_in_group("soldiers").filter(func(s): return s.team == 0)
		demo.commander.set_selection(men)
		demo.commander._take_zone(op.zones[0])
	if t > 10 and once("shell"):
		var h = demo.map.houses[2]
		RtsExplosion.spawn(demo, h.center + Vector3(0, 2.5, 0) + Basis(Vector3.UP, h.yaw) * Vector3(0, 0, h.size.y * 0.5), 1.2)
	if t > 12 and once("bomb"):
		var h = demo.map.houses[4]
		RtsExplosion.spawn(demo, h.center + Vector3(0, 1.0, 0), 3.5)
	if t > 14 and once("trench"):
		var p: Vector3 = op.ENTRY[0] + Vector3(20, 0, -20)
		demo.on_trench_placed(Vector3(p.x, 0, p.z), Vector3(p.x + 12, 0, p.z - 4), false)
	if fmod(t, 10.0) < delta * 1.01:
		var zs := ""
		for z in op.zones: zs += "%s:%d(%.2f) " % [z.name, z.owner, z.cap]
		print("t=%3.0f fps=%3d worst=%5.1fms slots=%d used=%d reserve=%s field=[%d,%d] supply=%d %s bleed=%d" % [t, Engine.get_frames_per_second(), worst, CoverSystem.count(), CoverSystem.in_use(), op.reserve, op._field(0), op._field(1), op.supply, zs, op.bleeding])
		worst = 0.0
	if t > float(OS.get_environment("SECS") if OS.get_environment("SECS") != "" else "60"):
		return true
	return false
