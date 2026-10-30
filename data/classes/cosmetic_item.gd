## Askar kiyimi / jihozi. Fayllar: res://data/cosmetics/*.tres
## parts: askar modelidagi qaysi mesh qismlari ko'rinadi (masalan ["Soldier_Helmet1"]); bo'sh = bu kategoriya yashirin.
class_name CosmeticItem
extends Resource

@export var id := ""
@export var category := "helmet"           ## uniform | helmet | vest | backpack | gloves | boots | face | patch
@export var name := ""
@export var icon: Texture2D
@export var parts: PackedStringArray = []
@export var tint := Color.WHITE            ## qism rangiga qo'shimcha tus (masalan qora qo'lqop)
@export var price := 0
@export var required_level := 1
