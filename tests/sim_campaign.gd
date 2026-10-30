## Kampaniya mantig'ini uzoq sinash: 40 yurish, har 5 yurishda statistika (davlatlar, urushlar, qo'shinlar,
## oltin, ta'minoti uzilganlar, Global Tension). godot --headless --path . -s res://tests/sim_campaign.gd
extends SceneTree
var m
var f := 0
func _initialize() -> void:
	root.get_node("GameSession").campaign_setup = {}
	m = (load("res://campaign/campaign_map.tscn") as PackedScene).instantiate()
	root.add_child(m)
func _process(_d: float) -> bool:
	f += 1
	if f != 3:
		return false
	var d = m.data
	var r = m.rules
	m.choose_country(m._country_by_code("UZB"))
	var alive0: int = d.countries.values().filter(func(c): return c.province_count > 0).size()
	print("boshida tirik davlatlar: ", alive0, "  qo'shinlar: ", d.armies.size())
	for t in 40:
		var t0 := Time.get_ticks_msec()
		m.end_turn()
		var ms := Time.get_ticks_msec() - t0
		if (t + 1) % 5 == 0:
			var alive: Array = d.countries.values().filter(func(c): return c.province_count > 0)
			alive.sort_custom(func(a, b): return a.province_count > b.province_count)
			var regs := 0
			var unsup := 0
			for a in d.armies:
				regs += a.size
				if not a.supplied: unsup += 1
			var golds: Array = alive.map(func(c): return int(c.resources.get("gold", 0)))
			golds.sort()
			var top := ", ".join(alive.slice(0, 4).map(func(c): return "%s %d" % [c.code, c.province_count]))
			print("yurish %2d | %4d ms | tirik %3d | urushlar %3d | qo'shin %3d (%4d polk, uzilgan %2d) | oltin median %6d max %7d | eng kattalar: %s" % [
				r.turn, ms, alive.size(), r.diplomacy.war_count() if r.diplomacy.has_method("war_count") else -1, d.armies.size(), regs, unsup,
				golds[golds.size() / 2], golds.back(), top])
	var uz = d.countries[m._country_by_code("UZB")]
	print("kapitulyatsiyalar: ", r.occupation.capitulations, "  tartibsiz hududlar: ", r.occupation.unrest.size(), "  qo'shimcha ittifoqlar: ", d.extra_allies.size(), "  faza: ", r.phase)
	print("O'zbekiston (o'yinchi, yurmadi): hudud ", uz.province_count, " oltin ", uz.resources.get("gold", 0))
	return true
