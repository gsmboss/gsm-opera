class_name PlayerData
extends Resource
## Mutable save-state. Mutate only via EconomyManager/PropertyManager so signals fire.

@export var money: float = 5000.0
@export var owned_building_ids: Array[String] = []
@export var active_outfit_id: String = "default"
@export var rented_building_ids: Array[String] = []
@export var businesses: Dictionary[String, String] = {} # building_id -> business_type


func can_afford(amount: float) -> bool:
	return amount >= 0.0 and money >= amount


## Returns false (no change) if unaffordable.
func deduct_money(amount: float) -> bool:
	if not can_afford(amount):
		return false
	money -= amount
	return true


func add_money(amount: float) -> void:
	money += maxf(amount, 0.0)
