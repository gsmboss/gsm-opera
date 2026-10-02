class_name Pedestrians
extends Node3D
## Low-poly people strolling on pavement tiles with a swinging-limb walk cycle.
## Each person: 5 MeshInstances (body, 2 arms, 2 legs) + shadow blob; culled beyond VIEW_DIST.

const VIEW_DIST := 45.0 # fog hides them beyond this; saves draw calls
const SKIN: Array[Color] = [Color("f1c27d"), Color("e0ac69"), Color("c68642"), Color("8d5524"), Color("ffdbac")]
const SHIRT: Array[Color] = [Color("e63946"), Color("457b9d"), Color("2a9d8f"), Color("f4a261"), Color("6d597a"), Color("ffffff"), Color("264653"), Color("e9c46a")]
const PANTS: Array[Color] = [Color("1d3557"), Color("343a40"), Color("6c584c"), Color("495057"), Color("283618")]
const HAIR: Array[Color] = [Color("2b2118"), Color("4a3728"), Color("b08d57"), Color("1a1a1a"), Color("8a8a8a")]

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
	var shirt: Color = SHIRT[_rng.randi() % SHIRT.size()]
	var pants: Color = PANTS[_rng.randi() % PANTS.size()]
	var skin: Color = SKIN[_rng.randi() % SKIN.size()]
	var hair: Color = HAIR[_rng.randi() % HAIR.size()]
	var h := _rng.randf_range(0.92, 1.08) # height variation

	var root := Node3D.new()
	root.scale = Vector3.ONE * h
	# Body: torso + neck + head + hair in one mesh.
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(0.42, 0.6, 0.24), Vector3(0, 1.2, 0), shirt)
	LowPoly.box(st, Vector3(0.1, 0.08, 0.1), Vector3(0, 1.54, 0), skin)
	LowPoly.box(st, Vector3(0.24, 0.26, 0.24), Vector3(0, 1.7, 0), skin)
	LowPoly.box(st, Vector3(0.26, 0.08, 0.26), Vector3(0, 1.85, -0.01), hair)
	LowPoly.box(st, Vector3(0.26, 0.16, 0.06), Vector3(0, 1.76, -0.12), hair)
	LowPoly.box(st, Vector3(0.44, 0.1, 0.26), Vector3(0, 0.88, 0), pants) # belt/hips
	_add_mesh(root, LowPoly.commit(st), Vector3.ZERO)
	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	for sx in [-1.0, 1.0]:
		var leg := LowPoly.begin()
		LowPoly.box(leg, Vector3(0.16, 0.82, 0.18), Vector3(0, -0.41, 0), pants)
		LowPoly.box(leg, Vector3(0.17, 0.08, 0.26), Vector3(0, -0.84, 0.04), Color("222222"))
		legs.append(_add_mesh(root, LowPoly.commit(leg), Vector3(0.11 * sx, 0.88, 0)))
		var arm := LowPoly.begin()
		LowPoly.box(arm, Vector3(0.12, 0.5, 0.14), Vector3(0, -0.25, 0), shirt)
		LowPoly.box(arm, Vector3(0.1, 0.12, 0.11), Vector3(0, -0.56, 0), skin)
		arms.append(_add_mesh(root, LowPoly.commit(arm), Vector3(0.28 * sx, 1.47, 0)))
	var blob := MeshInstance3D.new()
	blob.mesh = LowPoly.blob_shadow()
	blob.scale = Vector3(0.9, 1, 0.9)
	blob.position.y = 0.02
	blob.visibility_range_end = VIEW_DIST
	root.add_child(blob)
	add_child(root)
	root.position = _random_point(tile)
	return {root = root, tile = tile, dir = Vector2i.ZERO, target = root.position,
		legs = legs, arms = arms, speed = _rng.randf_range(1.1, 1.6), phase = _rng.randf() * TAU, pause = 0.0}


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.visibility_range_end = VIEW_DIST
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


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
	# Walk cycle: swing limbs, ease back to rest when idle.
	if moving:
		p.phase += delta * p.speed * 5.0
	var swing := sin(p.phase) * 0.6 if moving else 0.0
	for i in 2:
		var s := swing * (1.0 if i == 0 else -1.0)
		p.legs[i].rotation.x = lerpf(p.legs[i].rotation.x, s, minf(1.0, 12.0 * delta))
		p.arms[i].rotation.x = lerpf(p.arms[i].rotation.x, -s * 0.8, minf(1.0, 12.0 * delta))


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
