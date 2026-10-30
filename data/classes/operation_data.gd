## Operatsiya (tezkor jang rejimi). Fayllar: res://data/operations/*.tres
class_name OperationData
extends Resource

@export var id := ""
@export var mode := "attack"               ## recon | defend | attack | escort
@export var name := ""                     ## tarjima kaliti
@export var description := ""              ## tarjima kaliti
@export var image: Texture2D
@export var reward_credits := 0
@export var reward_xp := 0
@export var battle_mode := "operation"     ## jang sahnasidagi rejim (demo.gd: operation | assault | survival | conquest)
@export var available := true              ## false: "Tez orada"
@export var map_pos := Vector2(0.5, 0.5)   ## operatsiyalar xaritasidagi joy (0..1)
