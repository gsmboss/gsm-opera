class_name Pedestrians
extends Node3D
## Low-poly people strolling on pavement tiles with a swinging-limb walk cycle.
## Each person: 5 MeshInstances (body, 2 arms, 2 legs) + shadow blob; culled beyond VIEW_DIST.

const VIEW_DIST := 45.0 # fog hides them beyond this; saves draw calls

@export var city: CityBuilder
@export var player: Node3D
@export var count := 18

var _people: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 42
	var tiles: Array[Vector2i] = []
	for r in city.rows():
		for c in city.cols():
			if city.is_walkable(Vector2i(c, r)):
				tiles.append(Vector2i(c, r))
	for i in count:
		var t := tiles[_rng.randi() % tiles.size()]
		_people.append(_make_person(t))


func _make_person(tile: Vector2i) -> Dictionary:
	var p := PersonBuilder.build(_rng, VIEW_DIST)
	add_child(p.root)
	p.root.position = _random_point(tile)
	p.merge({tile = tile, dir = Vector2i.ZERO, target = p.root.position,
		speed = _rng.randf_range(1.1, 1.6), pause = 0.0})
	return p


func _physics_process(delta: float) -> void:
	var ppos := player.global_position if player else Vector3(INF, 0, INF)
	for p in _people:
		_walk(p, delta, ppos)


func _walk(p: Dictionary, delta: float, ppos: Vector3) -> void:
	var root: Node3D = p.root
	var to: Vector3 = p.target - root.position
	to.y = 0.0
	var moving := true
	if p.pause > 0.0:
		p.pause -= delta
		moving = false
	elif to.length() < 0.3:
		_pick_target(p)
		moving = false
	else:
		var fwd := to.normalized()
		var near := ppos - root.position
		near.y = 0.0
		if near.length() < 1.4 and near.dot(fwd) > 0.0: # politely wait for the player
			moving = false
		else:
			root.position += fwd * minf(p.speed * delta, to.length())
			root.rotation.y = lerp_angle(root.rotation.y, atan2(fwd.x, fwd.z), minf(1.0, 8.0 * delta))
	PersonBuilder.animate(p, moving, p.speed, delta)


## Next stop: neighbouring pavement tile (prefers straight on), sometimes a short pause.
func _pick_target(p: Dictionary) -> void:
	if _rng.randf() < 0.15:
		p.pause = _rng.randf_range(1.0, 4.0)
	var options: Array[Vector2i] = []
	for d in CityBuilder.DIRS:
		if city.is_walkable(p.tile + d) and d != -p.dir:
			options.append(d)
	if options.is_empty():
		options.append(-p.dir if p.dir != Vector2i.ZERO else Vector2i.ZERO)
	var d: Vector2i = p.dir if options.has(p.dir) and _rng.randf() < 0.6 else options.pick_random()
	p.dir = d
	p.tile += d
	p.target = _random_point(p.tile)


func _random_point(tile: Vector2i) -> Vector3:
	var half := city.tile_size * 0.3
	return city.tile_to_world(tile.x, tile.y) + Vector3(_rng.randf_range(-half, half), city.curb_height, _rng.randf_range(-half, half))
