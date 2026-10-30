## Kamuflyaj (forma, shlem, jilet rangi). Fayllar: res://data/camo/*.tres
## Kamuflyaj asl teksturani almashtirmaydi, uni rang bilan bo'yaydi (tint), jamoa belgisi o'zgarmaydi.
class_name CamouflageData
extends Resource

@export var id := ""
@export var name := ""
@export var tint := Color.WHITE
@export var texture: Texture2D             ## ixtiyoriy naqsh teksturasi
@export var icon: Texture2D
@export var price := 0
