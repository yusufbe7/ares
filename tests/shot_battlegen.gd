## Har biom uchun jang maydoni skrinshoti (xvfb + vulkan): user://shots/battle_<biom>.png
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var list := ["temperate", "forest", "desert", "mountain", "city", "coast", "winter"]
	for a in OS.get_cmdline_user_args():
		list = a.split(",")
	DirAccess.make_dir_recursive_absolute("user://shots")
	for b in list:
		var m := EuropeMap.new()
		m.spec = BattleGen.generate(b, 7)
		root.add_child(m)
		var cam := Camera3D.new()
		root.add_child(cam)
		var tgt := Vector3(-20, 0, -60)
		tgt.y = m.get_height(tgt.x, tgt.z)
		cam.position = tgt + Vector3(-170, 150, 190)
		cam.look_at(tgt)
		cam.far = 3000
		cam.current = true
		for k in 40:
			await process_frame
		root.get_texture().get_image().save_png("user://shots/battle_%s.png" % b)
		var cam2 := cam
		cam2.position = tgt + Vector3(-40, 22, 70)
		cam2.look_at(tgt + Vector3(20, 0, -40))
		for k in 20:
			await process_frame
		root.get_texture().get_image().save_png("user://shots/battle_%s_near.png" % b)
		cam.free()
		m.free()
		await process_frame
		print("shot ", b)
	quit()
