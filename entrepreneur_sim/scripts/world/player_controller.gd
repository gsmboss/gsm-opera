class_name PlayerController
extends CharacterBody3D
## Minimal mover: drag anywhere on left screen half = virtual stick; arrows/WASD on desktop.

const SPEED := 6.0
const STICK_RADIUS := 120.0 # px of drag for full speed

@onready var _cam: Camera3D = $Camera3D
@onready var _body: Node3D = $Body

var _touch_id := -1
var _touch_origin := Vector2.ZERO
var _stick := Vector2.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group(&"player")
	_cam.position = Vector3(0, 9, 8)
	_cam.look_at(global_position + Vector3.UP)


# _unhandled_input: GUI buttons consume their touches first.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1 and event.position.x < get_viewport().get_visible_rect().size.x * 0.5:
			_touch_id = event.index
			_touch_origin = event.position
		elif not event.pressed and event.index == _touch_id:
			_touch_id = -1
			_stick = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_stick = ((event.position - _touch_origin) / STICK_RADIUS).limit_length(1.0)


func _physics_process(delta: float) -> void:
	var dir := _stick
	if dir == Vector2.ZERO:
		dir = Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	velocity.x = dir.x * SPEED
	velocity.z = dir.y * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	if dir != Vector2.ZERO:
		_body.rotation.y = atan2(-dir.x, -dir.y) # face move direction
