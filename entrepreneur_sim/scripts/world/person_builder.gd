class_name PersonBuilder
extends RefCounted
## Procedural low-poly person: body mesh + 2 legs + 2 arms (pivoted for a walk cycle).

const SKIN: Array[Color] = [Color("f1c27d"), Color("e0ac69"), Color("c68642"), Color("8d5524"), Color("ffdbac")]
const SHIRT: Array[Color] = [Color("e63946"), Color("457b9d"), Color("2a9d8f"), Color("f4a261"), Color("6d597a"), Color("ffffff"), Color("264653"), Color("e9c46a")]
const PANTS: Array[Color] = [Color("1d3557"), Color("343a40"), Color("6c584c"), Color("495057"), Color("283618")]
const HAIR: Array[Color] = [Color("2b2118"), Color("4a3728"), Color("b08d57"), Color("1a1a1a"), Color("8a8a8a")]


## Returns {root, legs, arms, phase}. `shirt` overrides random colour (e.g. staff uniform).
static func build(rng: RandomNumberGenerator, view_dist := 45.0, layers := 1, shirt := Color(0, 0, 0, 0)) -> Dictionary:
	if shirt.a == 0.0:
		shirt = SHIRT[rng.randi() % SHIRT.size()]
	var pants: Color = PANTS[rng.randi() % PANTS.size()]
	var skin: Color = SKIN[rng.randi() % SKIN.size()]
	var hair: Color = HAIR[rng.randi() % HAIR.size()]
	var root := Node3D.new()
	root.scale = Vector3.ONE * rng.randf_range(0.92, 1.08)
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(0.42, 0.6, 0.24), Vector3(0, 1.2, 0), shirt)
	LowPoly.box(st, Vector3(0.1, 0.08, 0.1), Vector3(0, 1.54, 0), skin)
	LowPoly.box(st, Vector3(0.24, 0.26, 0.24), Vector3(0, 1.7, 0), skin)
	LowPoly.box(st, Vector3(0.26, 0.08, 0.26), Vector3(0, 1.85, -0.01), hair)
	LowPoly.box(st, Vector3(0.26, 0.16, 0.06), Vector3(0, 1.76, -0.12), hair)
	LowPoly.box(st, Vector3(0.44, 0.1, 0.26), Vector3(0, 0.88, 0), pants)
	_part(root, LowPoly.commit(st), Vector3.ZERO, view_dist, layers)
	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	for sx in [-1.0, 1.0]:
		var leg := LowPoly.begin()
		LowPoly.box(leg, Vector3(0.16, 0.82, 0.18), Vector3(0, -0.41, 0), pants)
		LowPoly.box(leg, Vector3(0.17, 0.08, 0.26), Vector3(0, -0.84, 0.04), Color("222222"))
		legs.append(_part(root, LowPoly.commit(leg), Vector3(0.11 * sx, 0.88, 0), view_dist, layers))
		var arm := LowPoly.begin()
		LowPoly.box(arm, Vector3(0.12, 0.5, 0.14), Vector3(0, -0.25, 0), shirt)
		LowPoly.box(arm, Vector3(0.1, 0.12, 0.11), Vector3(0, -0.56, 0), skin)
		arms.append(_part(root, LowPoly.commit(arm), Vector3(0.28 * sx, 1.47, 0), view_dist, layers))
	var blob := MeshInstance3D.new()
	blob.mesh = LowPoly.blob_shadow()
	blob.scale = Vector3(0.9, 1, 0.9)
	blob.position.y = 0.02
	blob.visibility_range_end = view_dist
	blob.layers = layers
	root.add_child(blob)
	return {root = root, legs = legs, arms = arms, phase = rng.randf() * TAU}


## Swing limbs while moving, ease to rest when idle.
static func animate(p: Dictionary, moving: bool, speed: float, delta: float) -> void:
	if moving:
		p.phase += delta * speed * 5.0
	var swing := sin(p.phase) * 0.6 if moving else 0.0
	var k := minf(1.0, 12.0 * delta)
	for i in 2:
		var s := swing * (1.0 if i == 0 else -1.0)
		p.legs[i].rotation.x = lerpf(p.legs[i].rotation.x, s, k)
		p.arms[i].rotation.x = lerpf(p.arms[i].rotation.x, -s * 0.8, k)


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, view_dist: float, layers: int) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.visibility_range_end = view_dist
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
