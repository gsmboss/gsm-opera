class_name TouchControls
extends Control
## Full-screen touch layer UNDER the HUD buttons (buttons win hit-tests).
## Left half: floating move stick. Right half: drag to look.

signal look_dragged(delta: Vector2)

const STICK_RADIUS := 110.0
const RING_COLOR := Color(1, 1, 1, 0.25)
const KNOB_COLOR := Color(1, 1, 1, 0.55)

var move_vector := Vector2.ZERO # read by player each physics frame

var _move_id := -1
var _look_id := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
		accept_event()
	elif event is InputEventScreenDrag:
		_on_drag(event)
		accept_event()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if e.position.x < size.x * 0.5 and _move_id == -1:
			_move_id = e.index
			_origin = e.position
			_knob = e.position
			queue_redraw()
		elif e.position.x >= size.x * 0.5 and _look_id == -1:
			_look_id = e.index
	elif e.index == _move_id:
		_move_id = -1
		move_vector = Vector2.ZERO
		queue_redraw()
	elif e.index == _look_id:
		_look_id = -1


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _move_id:
		var off := (e.position - _origin).limit_length(STICK_RADIUS)
		move_vector = off / STICK_RADIUS
		_knob = _origin + off
		queue_redraw()
	elif e.index == _look_id:
		look_dragged.emit(e.relative)


func _draw() -> void:
	if _move_id == -1:
		return
	draw_arc(_origin, STICK_RADIUS, 0.0, TAU, 32, RING_COLOR, 4.0, true)
	draw_circle(_knob, STICK_RADIUS * 0.4, KNOB_COLOR)
