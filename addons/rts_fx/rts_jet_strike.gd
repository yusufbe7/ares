## Airstrike: a jet flies over the target line and drops a stick of bombs.
## RtsJetStrike.call_in(parent, "res://assets/f117.glb", center, direction)
class_name RtsJetStrike
extends Node3D

@export var speed := 110.0
@export var altitude := 70.0
@export var bombs := 6
@export var bomb_spacing := 9.0
@export var bomb_size := 3.0
@export var model_forward := Vector3(0, 0, 1)   # F-117 nose points +Z

var center := Vector3.ZERO
var dir := Vector3.FORWARD
var _start := Vector3.ZERO
var _travel := 0.0
var _total := 0.0
var _dropped := 0

static func call_in(parent: Node, jet_scene_path: String, p_center: Vector3, p_dir := Vector3.ZERO) -> RtsJetStrike:
	var j := RtsJetStrike.new()
	j.center = p_center
	j.dir = (p_dir if p_dir.length() > 0.1 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))).normalized()
	if ResourceLoader.exists(jet_scene_path):
		j.add_child((load(jet_scene_path) as PackedScene).instantiate())
	parent.add_child(j)
	return j

func _ready() -> void:
	_start = center - dir * 450.0 + Vector3.UP * altitude
	_total = 900.0
	global_position = _start
	# point the model's nose along the flight direction
	var ang := (model_forward * Vector3(1, 0, 1)).normalized().signed_angle_to(dir, Vector3.UP)
	rotation.y = ang

func _process(delta: float) -> void:
	_travel += speed * delta
	global_position = _start + dir * _travel
	# release point: bombs fall ~2 s, so release ahead of the target
	var fall_t := sqrt(2.0 * altitude / 9.8)
	var lead := speed * fall_t
	while _dropped < bombs:
		var along := (_dropped - (bombs - 1) * 0.5) * bomb_spacing
		var release_at := 450.0 + along - lead
		if _travel < release_at:
			break
		var hit := center + dir * along + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		hit.y = RtsGround.height(hit.x, hit.z)
		get_tree().create_timer(fall_t).timeout.connect(func(): RtsExplosion.spawn(get_parent(), hit, bomb_size))
		_dropped += 1
	if _travel > _total:
		queue_free()
