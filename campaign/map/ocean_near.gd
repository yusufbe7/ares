## Yaqin kadrdagi okean qatlami: kamera yaqinlashganda (masofa < 45) kamera ostida zich to'r paydo bo'ladi
## va GLB okean simulyatsiyasining haqiqiy 3D to'lqinlarini ko'rsatadi. Uzoqda o'chadi (unumdorlik).
class_name OceanNear
extends MeshInstance3D

const SUBDIV := 220
var terrain: MapTerrain
var _mat: ShaderMaterial


static func make(t: MapTerrain) -> OceanNear:
	var o := OceanNear.new()
	o.terrain = t
	return o


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://campaign/map/ocean_near.gdshader")
	var src: ShaderMaterial = terrain.mat
	for p in ["id_tex", "sat_tex", "map_px", "height_tex", "height_px", "ocean_disp", "ocean_nrm", "ocean_col",
			"ocean_frames", "ocean_cols", "ocean_grid", "ocean_fps", "disp_min", "disp_max"]:
		var v: Variant = src.get_shader_parameter(p)
		if v != null:
			_mat.set_shader_parameter(p, v)
	_mat.set_shader_parameter("map_size", Vector2(terrain.size().x, terrain.size().y))
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	pm.subdivide_width = SUBDIV
	pm.subdivide_depth = SUBDIV
	mesh = pm
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Har kadr: kamera markazi va masofasi bo'yicha joy, o'lcham va shaffoflik.
func follow(center: Vector3, cam_dist: float) -> void:
	visible = cam_dist < 45.0 and _mat.get_shader_parameter("ocean_disp") != null
	if not visible:
		return
	var r := clampf(cam_dist * 1.25, 3.0, 40.0)
	var cell := 2.0 * r / SUBDIV
	# to'r katagiga moslab suramiz: tepalar to'lqin ustida "suzib" ketmasin
	position = Vector3(snappedf(center.x, cell), -0.035, snappedf(center.z, cell))
	scale = Vector3(2.0 * r, 1.0, 2.0 * r)
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("radius", r)
	_mat.set_shader_parameter("cam_dist", cam_dist)
