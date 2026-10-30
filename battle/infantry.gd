class_name Infantry
extends BattleUnit
## A soldier. Give it a destination and it decides for itself where to run,
## which wall to put between itself and the enemy, when to go prone and when to
## stop firing and wait out the burst.

var _cover_timer: float = 0.0
var _bob: float = 0.0
var _body_mesh: MeshInstance3D
var _dragging_wounded: bool = false

func ground_offset() -> float:
	match stance:
		Stance.CROUCH: return 0.55
		Stance.PRONE: return 0.2
	return 0.9

func _build_visual() -> void:
	var color := battle.team_color(team) if battle != null else Color.GRAY
	var irregular: bool = str(data.get("look", "regular")) == "irregular"

	_body_mesh = MeshInstance3D.new()
	var caps := CapsuleMesh.new()
	caps.radius = 0.28
	caps.height = 1.7
	_body_mesh.mesh = caps
	var mat := StandardMaterial3D.new()
	# Regulars wear one issued colour; irregulars are a mix of whatever they
	# have, so no two of them look quite alike.
	if irregular:
		mat.albedo_color = color.lerp(Color(0.44, 0.36, 0.24), 0.45) \
			.darkened(_rng.randf_range(0.0, 0.22))
	else:
		mat.albedo_color = color.darkened(0.25)
	mat.roughness = 0.95
	_body_mesh.material_override = mat
	add_child(_body_mesh)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.17
	hm.height = 0.34
	head.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.52, 0.40, 0.30) if irregular else color.darkened(0.45)
	head.material_override = hmat
	head.position = Vector3(0, 1.0, 0)
	add_child(head)

	if irregular:
		# A wrapped headscarf instead of a helmet.
		var wrap := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.19
		wm.bottom_radius = 0.2
		wm.height = 0.16
		wrap.mesh = wm
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.30, 0.27, 0.22).lightened(_rng.randf_range(0.0, 0.3))
		wrap.material_override = wmat
		wrap.position = Vector3(0, 1.12, 0)
		add_child(wrap)
	else:
		var helmet := MeshInstance3D.new()
		var hmesh := SphereMesh.new()
		hmesh.radius = 0.2
		hmesh.height = 0.26
		helmet.mesh = hmesh
		var hemat := StandardMaterial3D.new()
		hemat.albedo_color = color.darkened(0.55)
		helmet.material_override = hemat
		helmet.position = Vector3(0, 1.08, 0)
		add_child(helmet)

	# Weapon, so the unit reads as armed and facing somewhere.
	var rifle := MeshInstance3D.new()
	var rm := BoxMesh.new()
	var at_weapon: bool = float(data.get("at", 0.0)) > 0.5
	rm.size = Vector3(0.09, 0.12, 1.25) if at_weapon else Vector3(0.07, 0.1, 0.95)
	rifle.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.18, 0.14, 0.10) if at_weapon else Color(0.12, 0.11, 0.1)
	rifle.material_override = rmat
	rifle.position = Vector3(0.22, 0.45, 0.4)
	add_child(rifle)

	if str(data.get("role", "")) == "recon":
		_body_mesh.material_override.albedo_color = \
			_body_mesh.material_override.albedo_color.lightened(0.15)

func _think(delta: float) -> void:
	# Carrying a man off the field takes precedence over the firefight.
	if rescuing != null:
		_do_rescue(delta)
		return
	_cover_timer -= delta
	_bob += delta * (8.0 if has_move_target else 1.5)
	if _body_mesh != null:
		var sway: float = sin(_bob) * (0.05 if has_move_target else 0.012)
		_body_mesh.rotation.z = sway

	# Under fire with nowhere to be: find the best wall and get behind it.
	var under_fire: bool = suppression > 0.2 or (attack_target != null and not hold_position)
	if under_fire and _cover_timer <= 0.0 and not has_move_target:
		_cover_timer = 1.2
		_seek_cover()

	if activity == Activity.CAPTURING and capture_point != null:
		# Stay on the point, go to ground, keep shooting.
		if stance == Stance.STAND and suppression > 0.1:
			stance = Stance.CROUCH
	_move_step(delta)
	_update_stance()

## Go to him, pick him up, carry him back. If he dies on the way, or somebody
## else got there first, drop the job and rejoin the fight.
const DRAG_SPEED_FACTOR := 0.45
const PICKUP_RANGE := 2.6

func _do_rescue(delta: float) -> void:
	var casualty: BattleUnit = rescuing
	if not is_instance_valid(casualty) or not casualty.wounded:
		_abandon_rescue()
		return
	if casualty.rescuer != self:
		_abandon_rescue()
		return

	var to_him: float = global_position.distance_to(casualty.global_position)
	if not casualty.being_dragged:
		# Still on the way: keep walking to him, re-issuing as he is static.
		if to_him > PICKUP_RANGE:
			if not has_move_target or _cover_timer <= 0.0:
				_cover_timer = 1.0
				order_move(casualty.global_position)
				rescuing = casualty
				activity = Activity.RESCUING
			_move_step(delta)
			_cover_timer -= delta
			return
		casualty.being_dragged = true
		stance = Stance.CROUCH

	# Dragging: head for our own edge, with him in tow just behind.
	var safety: Vector3 = battle.safe_point_for(team)
	var to_safety := safety - global_position
	to_safety.y = 0.0
	if to_safety.length() < 30.0:
		casualty.being_dragged = false
		casualty.recover()
		rescuing = null
		activity = Activity.IDLE
		return
	var dir := to_safety.normalized()
	_facing = _facing.lerp(dir, clampf(delta * 3.0, 0.0, 1.0)).normalized()
	global_position += dir * effective_speed() * DRAG_SPEED_FACTOR * delta
	_stick_to_ground()
	look_at_direction(_facing)
	casualty.global_position = global_position - dir * 1.4
	casualty.global_position.y = battle.terrain.height_at(
		casualty.global_position.x, casualty.global_position.z) + 0.2

func _abandon_rescue() -> void:
	if rescuing != null and is_instance_valid(rescuing):
		rescuing.being_dragged = false
		if rescuing.rescuer == self:
			rescuing.rescuer = null
	rescuing = null
	activity = Activity.IDLE

func _seek_cover() -> void:
	var threat_dir := Vector3.FORWARD
	if attack_target != null and attack_target.is_alive():
		threat_dir = (attack_target.global_position - global_position).normalized()
	else:
		threat_dir = battle.threat_direction(team, global_position)
	var slot = battle.cover.best_slot(global_position, threat_dir, 26.0, get_instance_id())
	if slot == null:
		return
	if _cover_slot != null and _cover_slot != slot:
		battle.cover.release(_cover_slot, get_instance_id())
	_cover_slot = slot
	battle.cover.take(slot, get_instance_id())
	if global_position.distance_to(slot.position) > 2.0:
		order_move(slot.position)
		activity = Activity.ENGAGING

func _update_stance() -> void:
	if suppression > 0.8:
		stance = Stance.PRONE
	elif suppression > 0.4:
		stance = Stance.CROUCH
	elif not has_move_target and attack_target != null:
		stance = Stance.CROUCH
	elif suppression < 0.1 and has_move_target:
		stance = Stance.STAND
	if _body_mesh != null:
		var target_scale := 1.0
		match stance:
			Stance.CROUCH: target_scale = 0.72
			Stance.PRONE: target_scale = 0.45
		_body_mesh.scale.y = lerpf(_body_mesh.scale.y, target_scale, 0.15)

## Down, flat, and out of the fight until somebody comes.
func _on_wounded_visual() -> void:
	if _body_mesh != null:
		_body_mesh.rotation.x = PI * 0.5
		_body_mesh.scale.y = 1.0
		_body_mesh.position.y = -0.4
	set_selected(false)

func fire_at(target: BattleUnit, distance: float) -> void:
	# An AT team shoots a rocket, which flies and can miss the way a rocket does.
	if float(data.get("at", 0.0)) > 0.5 and target.unit_class() == "vehicle":
		battle.spawn_rocket(muzzle_position(), target, team, float(data.get("damage", 10)) * 6.0)
		return
	super.fire_at(target, distance)

func _on_death_visual() -> void:
	# Leave the body: it is a map marker for where the fighting was.
	var corpse := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.26
	cm.height = 1.6
	corpse.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.2, 0.18)
	corpse.material_override = mat
	corpse.rotation.x = PI * 0.5
	corpse.position = global_position + Vector3(0, 0.2, 0)
	corpse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if battle != null and is_instance_valid(battle):
		battle.add_child(corpse)
	queue_free()
