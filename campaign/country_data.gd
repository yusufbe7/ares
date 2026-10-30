## Davlat. Ma'lumot data/countries.json dan.
class_name CountryData
extends Resource

@export var id := 0
@export var code := ""                     ## ISO uch harfli kod (UZB, TUR...)
@export var iso2 := ""                     ## ikki harfli kod (bayroq o'rnida ko'rsatiladi)
@export var name := ""
@export var color := Color.WHITE
@export var controller := "bot"            ## "player" yoki "bot"
@export var capital := 0                   ## poytaxt hududi (ProvinceData.id)
@export var population := 0                ## Natural Earth POP_EST
@export var gdp_musd := 0                  ## Natural Earth GDP_MD (million $)
@export var resources := {}                ## {"gold": 400, "supply": 100, "manpower": 2000}
var province_count := 0                    ## o'yin davomida hisoblanadi
var bloc := ""                             ## data/blocs.json dagi blok id (bo'lmasa "")
