## Bitta hudud (viloyat). Ma'lumot data/provinces.json, data/neighbors.json va map/province_ids.png dan.
class_name ProvinceData
extends Resource

@export var id := 0                        ## province_ids.png dagi rang: id = R + G * 256
@export var name := ""
@export var owner := 0                     ## egasi: CountryData.id
@export var neighbors := PackedInt32Array()   ## quruqlik orqali qo'shnilar
@export var sea := {}                      ## dengiz orqali qo'shnilar: id -> masofa (km)
@export var population := 0
@export var gdp_musd := 0.0                ## YaIM ulushi, million $ (davlat YaIMi aholi ulushiga qarab)
@export var resource := ""                 ## grain, wood, iron, oil, fish, salt, stone
@export var resource_amount := 1           ## 1..3
@export var coastal := false
@export var area_km2 := 0
@export var elevation_m := 0
@export var center_px := Vector2i.ZERO     ## hudud ichidagi, chegaradan eng uzoq nuqta (belgi va yozuv shu yerda)
@export var pixels := 0                    ## rasmdagi piksellar soni


## Quruqlik va dengiz qo'shnilari birga.
func all_neighbors() -> Array:
	var out: Array = Array(neighbors)
	for k in sea:
		out.append(int(k))
	return out


func is_sea_link(other: int) -> bool:
	return sea.has(other)
