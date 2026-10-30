## EXIT: "Ish stoliga chiqilsinmi?" (jangdan qaytilgan bo'lsa ham shu yerdan chiqiladi). Chiqishdan oldin profil saqlanadi.
class_name ExitDialog
extends RefCounted


static func ask(parent: Node) -> void:
	if parent == null:
		return
	for ch in parent.get_children():
		if ch is ConfirmDialog:
			return
	var d := ConfirmDialog.ask(parent, Loc.t("exit"), Loc.t("exit_confirm"))
	d.answered.connect(func(yes: bool):
		if yes:
			GameSession.save()
			parent.get_tree().quit())
