## FPV kamikaze drone: climbs to cruise height, flies to the nearest enemy soldier or tank and dives into it.
## Soldiers under camo netting (group "camo") are not seen. Can be shot down (take_hit).
##   RtsDrone.launch(parent, from, team)
class_name RtsDrone
extends Node3D

@export var team := 1
@export var cruise_alt := 16.0
@export var speed := 24.0
@export var dive_speed := 32.0
@export var search_range := 260.0
@export var explosion_size := 0.7

var target: Node3D = null
var goal: Variant = null            ## player-ordered drone: hits the nearest enemy near this point (or the point)
var _vel := Vector3.ZERO
var _diving := false
var _dead := false
var _t := 0.0
var _think := 0.0
var _model: Node3D
var _life := 60.0


static func launch(parent: Node, from: Vector3, p_team: int) -> RtsDrone:
	var d := RtsDrone.new()
	d.team = p_team
	var path := "res://assets/fpv_drone.glb"
	if ResourceLoader.exists(path):
		d._model = load(path).instantiate()
		d._model.scale = Vector3.ONE * 1.6       # a bit bigger so it reads from the RTS camera
		d.add_child(d._model)
	parent.add_child(d)
	d.global_position = from
	return d


func _ready() -> void:
	add_to_group("drones")
	add_to_group("drones_%d" % team)
	var l := OmniLight3D.new()                  # small status LED, helps spotting it
	l.light_color = Color(1, 0.2, 0.15) if team == 1 else Color(0.3, 1, 0.4)
	l.light_energy = 0.8
	l.omni_range = 2.5
	add_child(l)


static func hidden_by_camo(n: Node3D) -> bool:
	for c in n.get_tree().get_nodes_in_group("camo"):
		var cn := c as Node3D
		var r: float = cn.get_meta("radius", 4.0)
		var d := cn.global_position - n.global_position
		d.y = 0
		if d.length() < r:
			return true
	return false


func _pick_target() -> void:
	var best: Node3D = null
	var bd := search_range
	if goal != null:
		bd = 45.0
		for s in get_tree().get_nodes_in_group("soldiers" if team == 1 else "enemies") + get_tree().get_nodes_in_group("tanks"):
			if s.get("team") == team or (s.has_method("can_fight") and not s.can_fight()) or s.get("destroyed") == true:
				continue
			var d := (s as Node3D).global_position.distance_to(goal)
			if d < bd: bd = d; best = s
		target = best
		return
	for t in get_tree().get_nodes_in_group("tanks"):
		if t.get("team") != team:
			var d := (t as Node3D).global_position.distance_to(global_position) * 0.8
			if d < bd: bd = d; best = t
	for s in get_tree().get_nodes_in_group("soldiers" if team == 1 else "enemies"):
		if s.has_method("can_fight") and s.can_fight() and not hidden_by_camo(s):
			var d := (s as Node3D).global_position.distance_to(global_position)
			if d < bd: bd = d; best = s
	target = best


func take_hit(_dmg: float, _from: Vector3) -> void:
	if _dead:
		return
	_dead = true
	# shot down: tumbles to the ground and pops
	var g := RtsGround.height(global_position.x, global_position.z)
	var tw := create_tween()
	tw.tween_property(self, "global_position", Vector3(global_position.x + randf_range(-3, 3), g + 0.1, global_position.z + randf_range(-3, 3)), 1.0).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "rotation", Vector3(randf_range(2, 5), randf_range(2, 5), 0), 1.0)
	tw.tween_callback(func():
		RtsExplosion.spawn(get_parent(), global_position, 0.35)
		queue_free())


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	_life -= delta
	_think -= delta
	if _think <= 0.0:
		_think = 0.7
		if target == null or not is_instance_valid(target) or (target.has_method("can_fight") and not target.can_fight()) or (target.get("destroyed") == true):
			_pick_target()
	if _life <= 0.0:
		take_hit(1.0, global_position)
		return
	var g := RtsGround.height(global_position.x, global_position.z)
	var goal_pt := global_position + Vector3(0, 0, 0)
	if target and is_instance_valid(target):
		var tp := target.global_position + Vector3.UP * 0.8
		var flat := Vector2(tp.x - global_position.x, tp.z - global_position.z).length()
		_diving = flat < cruise_alt * 1.4
		goal_pt = tp if _diving else Vector3(tp.x, RtsGround.height(tp.x, tp.z) + cruise_alt, tp.z)
		if global_position.distance_to(tp) < 1.8:
			_explode()
			return
	elif goal != null:
		var gp: Vector3 = goal
		gp.y = RtsGround.height(gp.x, gp.z) + 0.5
		var flat2 := Vector2(gp.x - global_position.x, gp.z - global_position.z).length()
		_diving = flat2 < cruise_alt * 1.4
		goal_pt = gp if _diving else Vector3(gp.x, gp.y + cruise_alt, gp.z)
		if global_position.distance_to(gp) < 1.8:
			_explode()
			return
	else:
		goal_pt = Vector3(global_position.x, g + cruise_alt, global_position.z)
	var desired := (goal_pt - global_position).normalized() * (dive_speed if _diving else speed)
	_vel = _vel.move_toward(desired, delta * 30.0)
	global_position += _vel * delta
	if global_position.y < g + 0.3:
		_explode()
		return
	# nose into the flight direction, a little wobble
	var flat_v := Vector3(_vel.x, 0, _vel.z)
	if flat_v.length() > 0.5:
		look_at(global_position + _vel, Vector3.UP)
		rotate_object_local(Vector3.RIGHT, -0.35)
	rotate_object_local(Vector3.FORWARD, sin(_t * 9.0) * 0.02)


func _explode() -> void:
	_dead = true
	RtsExplosion.spawn(get_parent(), global_position, explosion_size)
	queue_free()
