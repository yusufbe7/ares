## Jang maydoni generatori: har biom uchun maydon yasaladi, EuropeMap unda quriladi, vaqt o'lchanadi.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var biomes := ["temperate", "forest", "desert", "mountain", "city", "coast", "winter"]
	var fails := 0
	for b in biomes:
		var t0 := Time.get_ticks_msec()
		var spec: Dictionary = BattleGen.generate(b, 7)
		var t1 := Time.get_ticks_msec()
		var ok: bool = spec.heights.size() == 1025 * 1025 and spec.layout.zones.size() == 3 and spec.nav.get_width() == 300
		var nveg := 0
		for c in spec.vegetation:
			for t in spec.vegetation[c]:
				nveg += spec.vegetation[c][t].size()
		var m := EuropeMap.new()
		m.spec = spec
		root.add_child(m)
		if not m.is_node_ready():
			await process_frame
		var t2 := Time.get_ticks_msec()
		ok = ok and m.houses.size() == spec.village.size()
		print("%s %-10s gen %4d ms  build %4d ms  houses %2d  veg %4d  water %s" % ["OK  " if ok else "FAIL", b, t1 - t0, t2 - t1, spec.village.size(), nveg, spec.water])
		if not ok:
			fails += 1
		m.free()
	# bir xil seed - bir xil maydon
	var a: Dictionary = BattleGen.generate("desert", 3)
	var c: Dictionary = BattleGen.generate("desert", 3)
	var same: bool = a.heights == c.heights and str(a.layout) == str(c.layout)
	print(("OK  " if same else "FAIL") + " deterministic")
	if not same:
		fails += 1
	print("DONE fails=%d" % fails)
	quit(fails)
