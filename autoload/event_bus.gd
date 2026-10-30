## Umumiy signallar shinasi. UI qismlari bir-biriga to'g'ridan-to'g'ri bog'lanmaydi, shu signallar orqali gaplashadi.
extends Node

# --- bosh menyu va profil
signal credits_changed(credits: int, supply: int)
signal vehicle_bought(id: String)
signal vehicle_selected(id: String)
signal weapon_equipped(id: String)
signal loadout_changed
signal mission_selected(id: String)
signal operation_selected(id: String)
signal settings_changed
signal language_changed
signal profile_changed
signal toast(text: String)

# --- kampaniya (dunyo xaritasi)
signal country_hovered(cid: int)
signal country_previewed(cid: int)
signal country_chosen(cid: int)
signal province_selected(id: int)
signal map_view_changed(mode: int)
signal map_option_changed(key: String, on: bool)
signal campaign_changed
signal campaign_message(text: String)
signal turn_ended(turn: int)
signal tab_changed(id: String)
signal panels_toggled(collapsed: bool)
