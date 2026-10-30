extends Node
## Tiny three-language string table. Loc.t("key") returns the active language,
## falling back to English and then to the key itself.

const STRINGS := {
	"menu.play": {"uz": "O'YNASH", "en": "PLAY", "ru": "ИГРАТЬ"},
	"menu.global_war": {"uz": "GLOBAL URUSH", "en": "GLOBAL WAR", "ru": "ГЛОБАЛЬНАЯ ВОЙНА"},
	"menu.battle_arena": {"uz": "JANG ARENASI", "en": "BATTLE ARENA", "ru": "БОЕВАЯ АРЕНА"},
	"menu.multiplayer": {"uz": "ONLAYN", "en": "MULTIPLAYER", "ru": "ОНЛАЙН"},
	"menu.settings": {"uz": "SOZLAMALAR", "en": "SETTINGS", "ru": "НАСТРОЙКИ"},
	"menu.exit": {"uz": "CHIQISH", "en": "EXIT", "ru": "ВЫХОД"},
	"common.back": {"uz": "Orqaga", "en": "Back", "ru": "Назад"},
	"common.ready": {"uz": "Tayyor", "en": "Ready", "ru": "Готов"},
	"common.cancel": {"uz": "Bekor qilish", "en": "Cancel", "ru": "Отмена"},
	"common.confirm": {"uz": "Tasdiqlash", "en": "Confirm", "ru": "Подтвердить"},
	"world.select_nation": {"uz": "Davlat tanlang", "en": "Select a nation", "ru": "Выберите страну"},
	"world.economy": {"uz": "Iqtisodiyot", "en": "Economy", "ru": "Экономика"},
	"world.diplomacy": {"uz": "Diplomatiya", "en": "Diplomacy", "ru": "Дипломатия"},
	"world.army": {"uz": "Armiya", "en": "Army", "ru": "Армия"},
	"world.declare_war": {"uz": "Urush e'lon qilish", "en": "Declare war", "ru": "Объявить войну"},
	"world.propose_peace": {"uz": "Tinchlik taklifi", "en": "Propose peace", "ru": "Предложить мир"},
	"world.alliance": {"uz": "Ittifoq", "en": "Alliance", "ru": "Альянс"},
	"world.vote_open": {"uz": "Ovoz berish ochildi", "en": "Vote opened", "ru": "Голосование открыто"},
	"battle.deploy": {"uz": "JANGGA KIRISH", "en": "DEPLOY", "ru": "В БОЙ"},
	"battle.tickets": {"uz": "Zaxira", "en": "Tickets", "ru": "Резерв"},
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
