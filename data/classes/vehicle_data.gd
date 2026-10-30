## Texnika (garaj va bozor). Fayllar: res://data/vehicles/*.tres
class_name VehicleData
extends Resource

@export var id := ""
@export var name := ""
@export var type := "tank"                 ## tank | apc | truck | jeep | heli
@export_range(0, 100) var firepower := 50
@export_range(0, 100) var armor := 50
@export_range(0, 100) var mobility := 50
@export var price := 0
@export var required_level := 1
@export var image: Texture2D               ## almashtiriladigan rasm (bo'lmasa 3D model yoki "NO IMAGE")
@export_file("*.glb", "*.tscn") var model := ""
@export var model_scale := 1.0
@export var description := ""              ## tarjima kaliti
@export var available := true              ## false: o'yinda modeli yo'q, "Tez orada"
## Yangilanishlar: {"engine": [narx1, narx2, narx3], "armor": [...], "weapon": [...]} va har daraja +bonus
@export var upgrade_costs := {"engine": [8000, 16000, 30000], "armor": [10000, 20000, 36000], "weapon": [12000, 24000, 40000]}
@export var upgrade_bonus := 6             ## har daraja ko'rsatkichga qo'shiladi
