class_name Traffic
extends Node3D
## Cars on the road grid: right-hand lanes, random turns at crossings,
## traffic lights, car-following, and they stop for the player.
## No physics sim: AnimatableBody3D moved kinematically (player can't walk through).

signal lights_changed(phase: int)

enum Phase { NS_GREEN, NS_YELLOW, EW_GREEN, EW_YELLOW }

const CAR_MODELS: Array[String] = [
	"res://assets/kenney_vehicles/vehicle-truck-red.glb",
	"res://assets/kenney_vehicles/vehicle-truck-yellow.glb",
	"res://assets/kenney_vehicles/vehicle-truck-green.glb",
	"res://assets/kenney_vehicles/vehicle-truck-purple.glb",
]
const CAR_SCALE := 1.5
const LANE := 2.0          # metres right of road centre
const MAX_SPEED := 9.0     # m/s (~32 km/h)
const ACCEL := 4.0
const BRAKE := 10.0
const FOLLOW_GAP := 8.0
const GREEN_TIME := 9.0
const YELLOW_TIME := 2.0

@export var city: CityBuilder
@export var player: Node3D
@export var car_count := 8

var phase := Phase.NS_GREEN
var _phase_left := GREEN_TIME
var _cars: Array[Dictionary] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spawn: Array[Vector2i] = []
	for r in city.rows():
		for c in city.cols():
			var t := Vector2i(c, r)
			if city.is_road(t) and not city.is_crossing(t):
				spawn.append(t)
	for i in car_count:
		if spawn.is_empty():
			break
		var t: Vector2i = spawn.pop_at(rng.randi() % spawn.size())
		var vertical := city.is_road(t + Vector2i(0, 1)) or city.is_road(t + Vector2i(0, -1))
		var dir := Vector2i(0, 1) if vertical else Vector2i(1, 0)
		if rng.randf() < 0.5:
			dir = -dir
		_cars.append(_make_car(CAR_MODELS[i % CAR_MODELS.size()], t, dir))


func _make_car(model: String, tile: Vector2i, dir: Vector2i) -> Dictionary:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.4, 2.8) * CAR_SCALE
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape.size.y * 0.5
	body.add_child(cs)
	var vis: Node3D = load(model).instantiate()
	vis.scale = Vector3.ONE * CAR_SCALE
	body.add_child(vis)
	var blob := MeshInstance3D.new()
	blob.mesh = LowPoly.blob_shadow()
	blob.scale = Vector3(2.6, 1, 4.6)
	blob.position.y = 0.03
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(blob)
	add_child(body)
	var pos := _lane_point(tile, dir)
	body.position = pos
	body.rotation.y = atan2(dir.x, dir.y)
	return {body = body, tile = tile, dir = dir, target = pos, speed = 0.0}


func _physics_process(delta: float) -> void:
	_update_lights(delta)
	for car in _cars:
		_drive(car, delta)


# --- Traffic lights -----------------------------------------------------------

func _update_lights(delta: float) -> void:
	_phase_left -= delta
	if _phase_left > 0.0:
		return
	phase = ((phase + 1) % 4) as Phase
	_phase_left = GREEN_TIME if phase in [Phase.NS_GREEN, Phase.EW_GREEN] else YELLOW_TIME
	lights_changed.emit(phase)


## True if a car heading `dir` may enter a crossing now.
func is_green(dir: Vector2i) -> bool:
	return phase == (Phase.EW_GREEN if dir.x != 0 else Phase.NS_GREEN)


# --- Driving ------------------------------------------------------------------

func _drive(car: Dictionary, delta: float) -> void:
	var body: AnimatableBody3D = car.body
	var pos := body.position
	var to_target: Vector3 = car.target - pos
	if to_target.length() < 0.6:
		_advance(car) # may keep target (waiting at red) or teleport (map edge)
		pos = body.position
		to_target = car.target - pos
	var waiting := to_target.length() < 0.6
	var want := 0.0 if waiting or _blocked(car) else MAX_SPEED
	car.speed = move_toward(car.speed, want, (ACCEL if want > car.speed else BRAKE) * delta)
	if to_target.length() > 0.01:
		var step := minf(car.speed * delta, to_target.length())
		pos += to_target.normalized() * step
		var yaw := atan2(to_target.x, to_target.z)
		body.rotation.y = lerp_angle(body.rotation.y, yaw, minf(1.0, 6.0 * delta))
	body.position = pos


## Picks the next waypoint. Returns without change while waiting at a red light.
func _advance(car: Dictionary) -> void:
	var dir: Vector2i = car.dir
	var next: Vector2i = car.tile + dir
	if not city.is_road(next): # map edge: re-enter from the opposite edge
		var t: Vector2i = car.tile
		while city.is_road(t - dir):
			t -= dir
		car.tile = t
		car.body.position = _lane_point(t, dir)
		car.target = car.body.position
		return
	if city.is_crossing(next):
		if not is_green(dir) and not city.is_crossing(car.tile):
			return # hold at stop line (centre of the tile before the crossing)
		var options: Array[Vector2i] = []
		for d in CityBuilder.DIRS:
			if d != -dir and city.is_road(next + d):
				options.append(d)
		var nd: Vector2i = options.pick_random() if not options.is_empty() else dir
		if options.has(dir) and randf() < 0.5:
			nd = dir # prefer straight
		car.dir = nd
		car.tile = next
		car.target = _lane_point(next, nd)
		return
	car.tile = next
	car.target = _lane_point(next, dir)


func _lane_point(tile: Vector2i, dir: Vector2i) -> Vector3:
	var right := Vector3(-dir.y, 0, dir.x)
	return city.tile_to_world(tile.x, tile.y) + right * LANE


## Something within FOLLOW_GAP ahead in our lane: another car or the player.
func _blocked(car: Dictionary) -> bool:
	var pos: Vector3 = car.body.position
	var fwd := Vector3(sin(car.body.rotation.y), 0, cos(car.body.rotation.y))
	for other in _cars:
		if other != car and _ahead(pos, fwd, other.body.position, FOLLOW_GAP, 1.8):
			return true
	return player != null and _ahead(pos, fwd, player.global_position, 7.0, 2.2)


func _ahead(pos: Vector3, fwd: Vector3, p: Vector3, dist: float, half_width: float) -> bool:
	var d := p - pos
	d.y = 0.0
	var along := d.dot(fwd)
	return along > 0.5 and along < dist and absf(d.cross(fwd).y) < half_width
