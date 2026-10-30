## Qo'shin: qaysi davlatniki, qaysi hududda turibdi, nechta polk (son).
class_name ArmyData
extends Resource

@export var id := 0
@export var owner := 0
@export var province := 0
@export var size := 1                      ## polklar soni (belgidagi raqam)
var moved := false                         ## shu yurishda yurdimi
var busy := 0                              ## dengiz orqali o'tganda qolgan kutish yurishlari
var supplied := true                       ## ta'minot yo'li bormi (yo'q bo'lsa jarima)
