## Qurol modifikatsiyasi. Fayllar: res://data/attachments/*.tres
class_name AttachmentData
extends Resource

@export var id := ""
@export var slot := "optic"                ## optic | barrel | magazine | grip
@export var name := ""
@export var stats := {}                    ## {"accuracy": 8, "mobility": -3, ...}
@export var price := 0
@export var required_level := 1
@export var icon: Texture2D
