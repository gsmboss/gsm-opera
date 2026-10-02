class_name BuildingData
extends Resource
## Static, shareable building definition. Never mutate at runtime (shared across instances).

@export var building_id: String = ""
@export var display_name: String = ""
@export var price: float = 0.0
@export var rent_daily: float = 0.0
@export_range(1, 5) var foot_traffic_rating: int = 1
@export var allowed_business_types: Array[String] = []


func allows(business_type: String) -> bool:
	return allowed_business_types.has(business_type)
