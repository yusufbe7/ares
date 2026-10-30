## Kampaniya missiyasi (res://data/missions/*.tres).
## Maqsad hudud qat'iy id emas, qoida bilan beriladi (o'yinchi istalgan davlatni tanlashi mumkin):
##   target_rule: "" | "richest_enemy_neighbor" | "weakest_neighbor_border" | "nearest_enemy_capital"
## objectives: [{"type": ..., "count": n, "text": "tarjima kaliti"}]
##   type: declare_war | win_battles | capture_target | supply_target | own_provinces_plus | own_provinces_mult
## rewards: {"gold": n, "supply": n, "xp": n}
class_name MissionData
extends Resource

@export var id := ""
@export var order := 0
@export var title := ""                    ## tarjima kaliti
@export_multiline var briefing := ""       ## tarjima kaliti
@export var image: Texture2D               ## almashtiriladigan rasm (bo'lmasa "NO IMAGE")
@export var target_rule := ""
@export var objectives: Array[Dictionary] = []
@export var rewards := {}
@export var requires := ""                 ## oldingi missiya id (ochilish sharti)
@export_range(1, 3) var difficulty := 1   ## 1 oson, 2 o'rta, 3 qiyin
