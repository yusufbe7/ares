class_name Radio
extends RefCounted
## Unit callouts. The battlefield is much louder in the reference than a silent
## HUD can convey, so sections report what they are doing as they do it.

enum Call { ADVANCE, UNDER_FIRE, ENGAGING, PINNED, TAKING_COVER,
	ARMOUR_CALLED, AIR_CALLED, OBJECTIVE_TAKEN, MAN_DOWN, FALLING_BACK }

const LINES := {
	Call.ADVANCE: ["Oldinga!", "Harakat, harakat!", "Ketdik, siljiymiz!"],
	Call.UNDER_FIRE: ["O't ostidamiz!", "Bizni otishyapti!", "Qattiq o't!"],
	Call.ENGAGING: ["Nishon ko'rindi, otaman!", "Aloqa! O'ngdan!", "Dushman, otaman!"],
	Call.PINNED: ["Bosh ko'tarib bo'lmaydi!", "Qotib qoldik, yordam kerak!"],
	Call.TAKING_COVER: ["Panaga!", "Yerga, pana ol!"],
	Call.ARMOUR_CALLED: ["Zirh yo'lda.", "Tank chaqirildi."],
	Call.AIR_CALLED: ["Aviatsiya, qurol tayyor.", "Havo yordami yo'lda."],
	Call.OBJECTIVE_TAKEN: ["Nuqta bizda!", "Hudud nazorat ostida."],
	Call.MAN_DOWN: ["Yarador bor!", "Sanitar, bu yerga!"],
	Call.FALLING_BACK: ["Chekinamiz!", "Orqaga, orqaga!"],
}

const KIND := {
	Call.ADVANCE: "info", Call.UNDER_FIRE: "warn", Call.ENGAGING: "info",
	Call.PINNED: "bad", Call.TAKING_COVER: "warn", Call.ARMOUR_CALLED: "good",
	Call.AIR_CALLED: "good", Call.OBJECTIVE_TAKEN: "good",
	Call.MAN_DOWN: "bad", Call.FALLING_BACK: "warn",
}

## Shared cooldowns, so a whole section does not shout the same line at once.
static var _last_time: Dictionary = {}

static func say(speaker: String, call: int, cooldown: float = 6.0) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - float(_last_time.get(call, -999.0)) < cooldown:
		return
	_last_time[call] = now
	var options: Array = LINES.get(call, [])
	if options.is_empty():
		return
	var line := str(options[randi() % options.size()])
	EventBus.combat_log.emit("%s: %s" % [speaker, line], str(KIND.get(call, "info")))

static func reset() -> void:
	_last_time.clear()
