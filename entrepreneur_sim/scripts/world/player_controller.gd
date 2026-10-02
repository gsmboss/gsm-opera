class_name PlayerController
extends CharacterBody3D
## First-person walker. Touch via TouchControls; WASD + mouse drag on desktop.
## Head bob, swaying low-poly arms, footstep + city ambience audio.

const WALK_SPEED := 4.5
const ACCEL := 12.0
const LOOK_SENS := 0.18 # degrees per drag pixel
const PITCH_LIMIT := 80.0
const BOB_FREQ := 1.9   # steps per metre-ish
const BOB_AMP := 0.045
const SLEEVE := Color("2b4c7e")
const SKIN := Color("e0ac69")

@export var touch_controls: TouchControls

@onready var _head: Node3D = $Head
@onready var _cam: Camera3D = $Head/Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _bob_phase := 0.0
var _head_base_y := 0.0
var _arms := Node3D.new()
var _steps := AudioStreamPlayer.new()


func _ready() -> void:
	add_to_group(&"player")
	_head_base_y = _head.position.y
	if touch_controls:
		touch_controls.look_dragged.connect(_look)
	_build_arms()
	_setup_audio()


func _look(delta: Vector2) -> void:
	rotation.y -= deg_to_rad(delta.x * LOOK_SENS)
	_head.rotation.x = clampf(_head.rotation.x - deg_to_rad(delta.y * LOOK_SENS),
		deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))
	_arms.rotation.y += deg_to_rad(delta.x * LOOK_SENS) * 0.15 # lag sway


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
	_animate(delta)


## Head bob + arm sway scale with ground speed; footsteps loop while walking.
func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var k := clampf(speed / WALK_SPEED, 0.0, 1.0)
	if k > 0.05 and is_on_floor():
		_bob_phase += speed * delta * BOB_FREQ
	var bob := sin(_bob_phase * TAU) * BOB_AMP * k
	_head.position.y = lerpf(_head.position.y, _head_base_y + bob, minf(1.0, 14.0 * delta))
	_head.position.x = cos(_bob_phase * PI) * BOB_AMP * 0.5 * k
	_arms.position = Vector3(cos(_bob_phase * PI) * 0.012, absf(sin(_bob_phase * PI)) * -0.02, 0) * k
	_arms.rotation.y = lerpf(_arms.rotation.y, 0.0, minf(1.0, 8.0 * delta))
	var walking := k > 0.2 and is_on_floor()
	if walking and not _steps.playing:
		_steps.play()
	elif not walking and _steps.playing:
		_steps.stop()
	_steps.pitch_scale = 0.85 + 0.3 * k


## Right hand holding a smartphone in the lower-right corner (camera space).
func _build_arms() -> void:
	_cam.near = 0.03
	_cam.add_child(_arms)
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(0.072, 0.145, 0.01), Vector3.ZERO, Color("1b1b1f"))          # phone body
	LowPoly.box(st, Vector3(0.062, 0.125, 0.002), Vector3(0, 0, 0.006), Color("4cc9f0"))  # screen
	LowPoly.box(st, Vector3(0.082, 0.075, 0.03), Vector3(0.004, -0.05, -0.02), SKIN)     # palm
	LowPoly.box(st, Vector3(0.02, 0.05, 0.02), Vector3(-0.042, -0.015, 0.004), SKIN)     # thumb
	LowPoly.box(st, Vector3(0.085, 0.26, 0.085), Vector3(0.012, -0.21, -0.03), SLEEVE)   # sleeve
	var hand := MeshInstance3D.new()
	hand.mesh = LowPoly.commit(st)
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hand.position = Vector3(0.21, -0.2, -0.4)
	hand.scale = Vector3.ONE * 0.85
	hand.rotation_degrees = Vector3(-8, -14, -6)
	_arms.add_child(hand)


func _setup_audio() -> void:
	var step_stream := load("res://assets/audio/footsteps.ogg") as AudioStreamOggVorbis
	step_stream.loop = true
	_steps.stream = step_stream
	_steps.volume_db = -8.0
	add_child(_steps)
	var amb_stream := load("res://assets/audio/city_ambience.ogg") as AudioStreamOggVorbis
	amb_stream.loop = true
	var amb := AudioStreamPlayer.new()
	amb.stream = amb_stream
	amb.volume_db = -14.0
	amb.autoplay = true
	add_child(amb)


func _keyboard_vector() -> Vector2:
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	return v.limit_length(1.0)
