class_name PlayerController
extends CharacterBody3D
## First-person walker. Touch via TouchControls; WASD + mouse drag on desktop.

const WALK_SPEED := 4.5
const ACCEL := 12.0
const LOOK_SENS := 0.18 # degrees per drag pixel
const PITCH_LIMIT := 80.0

@export var touch_controls: TouchControls

@onready var _head: Node3D = $Head

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group(&"player")
	if touch_controls:
		touch_controls.look_dragged.connect(_look)


func _look(delta: Vector2) -> void:
	rotation.y -= deg_to_rad(delta.x * LOOK_SENS)
	_head.rotation.x = clampf(_head.rotation.x - deg_to_rad(delta.y * LOOK_SENS),
		deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))


func _physics_process(delta: float) -> void:
	var input := touch_controls.move_vector if touch_controls else Vector2.ZERO
	if input == Vector2.ZERO:
		input = _keyboard_vector()
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized() * input.length()
	var target := dir * WALK_SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()


func _keyboard_vector() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	return v.limit_length(1.0)
