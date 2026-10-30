## Qurol (Armory). Fayllar: res://data/weapons/*.tres
class_name WeaponData
extends Resource

@export var id := ""
@export var name := ""
@export var weapon_class := "assault"      ## assault | sniper | lmg | shotgun | pistol
@export_range(0, 100) var damage := 50
@export_range(0, 100) var accuracy := 50
@export_range(0, 100) var range := 50
@export_range(0, 100) var fire_rate := 50
@export_range(0, 100) var mobility := 50
@export var price := 0
@export var required_level := 1
@export var slots: PackedStringArray = ["optic", "barrel", "magazine", "grip"]
@export var image: Texture2D
@export_file("*.glb", "*.tscn") var model := ""
@export var model_scale := 1.0
