class_name BuildingSpot
extends Area3D
## Trigger zone in front of a building. Needs a CollisionShape3D child.
## UI discovers spots via GROUP and listens to the signals below.

signal player_entered_spot(spot: BuildingSpot)
signal player_exited_spot(spot: BuildingSpot)

const GROUP := &"building_spots"

@export var data: BuildingData
@export var player_group: StringName = &"player"
@export_range(1, 32) var player_layer: int = 2 # matches [layer_names] "player"

var player_inside := false


func _ready() -> void:
	add_to_group(GROUP)
	monitorable = false # nothing needs to detect us -> cheaper broadphase
	collision_layer = 0
	collision_mask = 1 << (player_layer - 1) # scan player layer only
	PropertyManager.register_building(data)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func get_building_id() -> String:
	return data.building_id if data else ""


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(player_group) and not player_inside:
		player_inside = true
		player_entered_spot.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(player_group) and player_inside:
		player_inside = false
		player_exited_spot.emit(self)
