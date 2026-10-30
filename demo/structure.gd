## A building: first a construction site that soldiers dig and build (orange footprint, dirt, rising model,
## progress label, speech bubbles), then a finished structure with HP that explosions can destroy.
class_name RtsStructure
extends Node3D

signal completed(s: RtsStructure)
signal destroyed(s: RtsStructure)

const LINES := ["MORE DIRT...", "SPADE WORK", "NEARLY DEEP ENOUGH", "KEEP DIGGING!", "PASS THE SANDBAGS", "ALMOST THERE", "DEEPER...", "HEAVE!"]

var key := ""
var def: Dictionary = {}
var team := 0
var built := false
var dead := false
var progress := 0.0
var hp := 100.0
var max_hp := 100.0
var workers: Array = []
var _model: Node3D
var _model_h := 3.0
var _frame: Decal
var _dirt: Decal
var _label: Label3D
var _overlay: StandardMaterial3D
var _tick := 0.0
var _bubble_t := 2.0
var _nav_cells := PackedInt32Array()

static var _outline_tex: Texture2D


static func create(parent: Node, p_key: String, pos: Vector3, yaw: float, p_team := 0, prebuilt := false) -> RtsStructure:
	var s := RtsStructure.new()
	s.key = p_key
	s.def = BuildDefs.STRUCTURES[p_key]
	s.team = p_team
	parent.add_child(s)
	s.global_position = pos
	s.rotation.y = yaw
	s._build_visuals()
	# units walk around buildings (wire and camo nets stay passable)
	if not s.def.get("passable", false):
		s._nav_cells = RtsNav.add_obstacle(Transform3D(Basis(Vector3.UP, yaw), pos), s.def.size, 0.15)
	if prebuilt:
		s.progress = s.def.work
		s._complete(false)
	return s


func _build_visuals() -> void:
	name = "%s_%d" % [key, get_instance_id() % 10000]
	add_to_group("structures")
	add_to_group("structures_%d" % team)
	max_hp = def.hp
	hp = max_hp * 0.35
	_model = BuildDefs.make_model(key, team)
	add_child(_model)
	var a := BuildDefs.aabb_of_node(_model)
	_model_h = maxf(1.0, a.size.y)
	var sz: Vector2 = def.size
	_frame = Decal.new()
	_frame.cull_mask = RtsGround.DECAL_LAYER
	_frame.texture_albedo = outline_texture()
	_frame.size = Vector3(sz.x + 1.2, 12.0, sz.y + 1.2)
	_frame.modulate = Color(1.0, 0.55, 0.12)
	_frame.albedo_mix = 1.0
	_frame.position.y = 2.0
	add_child(_frame)
	_dirt = Decal.new()
	_dirt.cull_mask = RtsGround.DECAL_LAYER
	_dirt.texture_albedo = load("res://addons/rts_fx/textures/scorch_decal.png")
	_dirt.size = Vector3(sz.x * 0.95, 12.0, sz.y * 0.95)
	_dirt.modulate = Color(0.5, 0.36, 0.22)
	_dirt.albedo_mix = 0.85
	_dirt.position.y = 2.0
	add_child(_dirt)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.pixel_size = 0.0005
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.78, 0.4)
	_label.render_priority = 5
	_label.position.y = _model_h + 2.0
	add_child(_label)
	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = Color(0.95, 0.6, 0.2, 0.35)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = _overlay
	_update_visual()


## White rectangle border + faint fill, tinted by Decal.modulate.
static func outline_texture() -> Texture2D:
	if _outline_tex:
		return _outline_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var e := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var c := Color(1, 1, 1, 0.16)
			if e < 4: c = Color(1, 1, 1, 0.95)
			elif e < 7: c = Color(1, 1, 1, 0.45)
			img.set_pixel(x, y, c)
	_outline_tex = ImageTexture.create_from_image(img)
	return _outline_tex


func display_name() -> String:
	return def.name


func work_fraction() -> float:
	return clampf(progress / float(def.work), 0.0, 1.0)


## Soldiers come and build. Returns how many were assigned.
func assign(soldiers: Array) -> int:
	if built or dead:
		return 0
	var n := 0
	for s in soldiers:
		if not is_instance_valid(s) or s.team != team or not s.is_commandable():
			continue
		if not workers.has(s):
			if workers.size() >= 8:
				break
			workers.append(s)
		n += 1
	for i in workers.size():
		var w: RtsSoldier = workers[i]
		if soldiers.has(w):
			w.work_on(self, slot(i, workers.size()))
	return n


## Standing spot i of n around the footprint, facing in.
func slot(i: int, n: int) -> Vector3:
	var sz: Vector2 = def.size
	var hx := sz.x * 0.5 + 0.9
	var hz := sz.y * 0.5 + 0.9
	var per := 2.0 * (hx + hz) * 2.0
	n = maxi(n, 4)
	var d := fposmod((float(i) + 0.5) / n * per + hx, per)
	var p := Vector3.ZERO
	if d < 2 * hx: p = Vector3(-hx + d, 0, -hz)
	elif d < 2 * hx + 2 * hz: p = Vector3(hx, 0, -hz + (d - 2 * hx))
	elif d < 4 * hx + 2 * hz: p = Vector3(hx - (d - 2 * hx - 2 * hz), 0, hz)
	else: p = Vector3(-hx, 0, hz - (d - 4 * hx - 2 * hz))
	return global_transform * p


func _process(delta: float) -> void:
	if built or dead:
		return
	var digging := 0
	for w in workers:
		if is_instance_valid(w) and w.work_site == self and w.is_digging():
			digging += 1
	if digging > 0:
		# more hands help, a little less each
		progress += delta * digging * (1.0 / (1.0 + 0.12 * (digging - 1)))
		hp = minf(max_hp, max_hp * (0.35 + 0.65 * work_fraction()))
	_update_visual()
	if progress >= def.work:
		_complete(true)
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 2.0
		_manage_workers()
	_bubble_t -= delta
	if _bubble_t <= 0.0 and digging > 0:
		_bubble_t = randf_range(3.0, 6.5)
		var ws := workers.filter(func(w): return is_instance_valid(w) and w.is_digging())
		if not ws.is_empty():
			var t: String = LINES[randi() % LINES.size()]
			if work_fraction() > 0.8: t = ["NEARLY DEEP ENOUGH", "ALMOST THERE", "LAST FEW!"][randi() % 3]
			RtsBubble.say(ws[randi() % ws.size()], t, 2.6)


## Drop dead / reassigned workers; call idle ones back once the fighting has moved on.
func _manage_workers() -> void:
	workers = workers.filter(func(w): return is_instance_valid(w) and w.state != RtsSoldier.State.DEAD and w.work_site == self)
	for i in workers.size():
		var w: RtsSoldier = workers[i]
		if not w.is_digging() and w.state in [RtsSoldier.State.IDLE, RtsSoldier.State.COVER] and w._nearest_enemy(70.0) == null:
			w.work_on(self, slot(i, workers.size()))


func _update_visual() -> void:
	var f := work_fraction()
	if _model:
		# first the hole is dug, then the building rises out of it
		var g := clampf((f - 0.15) / 0.85, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - g, 2.0)
		_model.visible = f > 0.15
		_model.position.y = -_model_h * (1.0 - e) * 0.95
	if _label and not built:
		_label.text = "%s  %d%%" % [String(def.name).to_upper(), int(f * 100.0)]


func _complete(announce: bool) -> void:
	built = true
	progress = def.work
	hp = max_hp
	_model.position.y = 0.0
	_model.visible = true
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = null
	if _frame: _frame.queue_free(); _frame = null
	if _dirt:
		var tw := _dirt.create_tween()
		tw.tween_property(_dirt, "albedo_mix", 0.0, 6.0)
		tw.tween_callback(_dirt.queue_free)
		_dirt = null
	if _label: _label.queue_free(); _label = null
	for w in workers:
		if is_instance_valid(w) and w.work_site == self:
			w.stop_work()
			if announce and randf() < 0.5:
				RtsBubble.say(w, ["DONE!", "BUILT!", "THAT'LL HOLD"][randi() % 3], 2.0)
	workers.clear()
	for g in def.get("groups", []):
		add_to_group(g)
	if def.get("camo", false):
		set_meta("radius", 4.0)
	if def.get("cover", false):
		var c := Marker3D.new()
		add_child(c)
		c.add_to_group("cover")
	completed.emit(self)


## Called by RtsExplosion for everything in the "structures" group.
func take_blast(at: Vector3, radius: float) -> void:
	if dead:
		return
	var sz: Vector2 = def.size
	var lp := to_local(at)
	var dx := maxf(0.0, absf(lp.x) - sz.x * 0.5)
	var dz := maxf(0.0, absf(lp.z) - sz.y * 0.5)
	var d := Vector2(dx, dz).length()
	if d > radius * 0.6:
		return
	var dmg := 70.0 * (radius / 5.0) * clampf(1.0 - d / (radius * 0.6), 0.3, 1.0)
	if not built: dmg *= 1.5
	damage(dmg)


func damage(dmg: float) -> void:
	if dead:
		return
	hp -= dmg
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	dead = true
	remove_from_group("structures"); remove_from_group("structures_%d" % team)
	for g in def.get("groups", []):
		remove_from_group(g)
	for w in workers:
		if is_instance_valid(w) and w.work_site == self:
			w.stop_work()
	workers.clear()
	RtsExplosion.spawn(get_parent(), global_position + Vector3.UP * 1.5, 2.0)
	if _label: _label.queue_free(); _label = null
	if _frame: _frame.queue_free(); _frame = null
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.03, 0.03, 0.03, 0.8)
	burnt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = burnt
	var fl := _model.get_node_or_null("Flag")
	if fl: fl.queue_free()
	for i in 4:
		get_tree().create_timer(1.5 + i * 3.0).timeout.connect(func():
			if is_inside_tree():
				RtsExplosion.spawn(get_parent(), global_position + Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2)), 0.35))
	destroyed.emit(self)
	if not built:
		RtsNav.remove_obstacle(_nav_cells)
		_nav_cells = PackedInt32Array()
		var tw := create_tween()
		tw.tween_property(_model, "position:y", -_model_h, 3.0)
		tw.tween_callback(queue_free)
