extends Node
## Small three-language string table. Loc.t("key") falls back to English, then
## to the key itself.

const STRINGS := {
	"menu.play": {"uz": "JANGNI BOSHLASH", "en": "START BATTLE", "ru": "НАЧАТЬ БОЙ"},
	"menu.settings": {"uz": "SOZLAMALAR", "en": "SETTINGS", "ru": "НАСТРОЙКИ"},
	"menu.exit": {"uz": "CHIQISH", "en": "EXIT", "ru": "ВЫХОД"},
	"common.back": {"uz": "Orqaga", "en": "Back", "ru": "Назад"},
	"battle.supply": {"uz": "Ta'minot", "en": "Supply", "ru": "Снабжение"},
	"battle.victory": {"uz": "G'ALABA", "en": "VICTORY", "ru": "ПОБЕДА"},
	"battle.defeat": {"uz": "MAG'LUBIYAT", "en": "DEFEAT", "ru": "ПОРАЖЕНИЕ"},
}

func t(key: String) -> String:
	if not STRINGS.has(key):
		return key
	var row: Dictionary = STRINGS[key]
	var lang := Settings.language
	if row.has(lang):
		return str(row[lang])
	if row.has("en"):
		return str(row["en"])
	return key
