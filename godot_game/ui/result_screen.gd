extends Node
## After-action report, then back to whichever game the battle belonged to.

func open(payload: Dictionary) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	UIKit.fullscreen(bg)
	bg.color = UIKit.BG
	layer.add_child(bg)

	var center := CenterContainer.new()
	UIKit.fullscreen(center)
	layer.add_child(center)
	var panel := UIKit.make_panel()
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var col := UIKit.vbox(8)
	panel.add_child(col)

	var won := bool(payload.get("player_won", false))
	col.add_child(UIKit.label(Loc.t("battle.victory") if won else Loc.t("battle.defeat"),
		34, UIKit.ACCENT if won else UIKit.BAD))
	col.add_child(UIKit.label("G'olib: %s" % str(payload.get("winner", "?")), 16))
	col.add_child(UIKit.label("Hujumchi yo'qotishlari: %d%%"
		% int(float(payload.get("attacker_losses", 0.0)) * 100.0), 14))
	col.add_child(UIKit.label("Mudofaachi yo'qotishlari: %d%%"
		% int(float(payload.get("defender_losses", 0.0)) * 100.0), 14))
	if payload.has("province"):
		var p: Province = GameState.world.province(int(payload["province"])) if GameState.world != null else null
		if p != null:
			col.add_child(UIKit.label("Hudud: %s — endi %s nazoratida" % [p.name, p.owner_id], 14, UIKit.MUTED))
	col.add_child(UIKit.spacer(12))

	var cont := UIKit.button("DAVOM ETISH", 18)
	cont.pressed.connect(func():
		if GameState.mode == GameState.Mode.GLOBAL_WAR:
			GameState.go("world", {})
		else:
			GameState.go("main_menu", {}))
	col.add_child(cont)
