class_name StreetProps
extends Node3D
## Benches, bins, planters, traffic lights and shop signs.
## Props use one MultiMesh per type; traffic-light lenses are one MultiMesh with per-instance colour.

const WOOD := Color("8b5a2b")
const METAL := Color("3d4148")
const BIN := Color("2f6b3a")
const LIGHT_OFF := Color(0.12, 0.12, 0.12)
const LENS_COLORS: Array[Color] = [Color(1, 0.15, 0.1), Color(1, 0.75, 0.1), Color(0.2, 1, 0.3)]

@export var city: CityBuilder
@export var traffic: Traffic

var _lenses: MultiMesh
var _lens_dirs: Array[Vector2i] = [] # approach dir of each light head (3 lenses each)
var _signs: Dictionary[String, Label3D] = {} # building_id -> status label
var _body := StaticBody3D.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 3
	add_child(_body)
	var benches: Array[Transform3D] = []
	var bins: Array[Transform3D] = []
	var planters: Array[Transform3D] = []
	var t := city.tile_size
	for r in city.rows():
		for c in city.cols():
			var tile := Vector2i(c, r)
			var centre := city.tile_to_world(c, r) + Vector3(0, city.curb_height, 0)
			match city.char_at(c, r):
				"p":
					# Along roads: bench facing the street + bin beside it.
					for d in CityBuilder.DIRS:
						if city.is_road(tile + d) and _rng.randf() < 0.45:
							var edge := Vector3(d.x, 0, d.y) * t * 0.36
							var side := Vector3(-d.y, 0, d.x) * t * 0.25
							var yaw := atan2(d.x, d.y)
							benches.append(Transform3D(Basis(Vector3.UP, yaw), centre + edge))
							bins.append(Transform3D(Basis.IDENTITY, centre + edge + side))
				".":
					planters.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), centre))
	_multimesh(_bench_mesh(), benches, Vector3(1.7, 0.9, 0.6))
	_multimesh(_bin_mesh(), bins, Vector3(0.5, 0.9, 0.5))
	_multimesh(_planter_mesh(), planters, Vector3(2.2, 0.5, 2.2))
	_build_traffic_lights()
	_build_signs()


# --- Meshes -------------------------------------------------------------------

func _bench_mesh() -> Mesh:
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(1.6, 0.07, 0.45), Vector3(0, 0.45, 0), WOOD)
	LowPoly.box(st, Vector3(1.6, 0.35, 0.06), Vector3(0, 0.72, -0.21), WOOD)
	for sx in [-0.7, 0.7]:
		LowPoly.box(st, Vector3(0.07, 0.45, 0.45), Vector3(sx, 0.225, 0), METAL)
		LowPoly.box(st, Vector3(0.06, 0.4, 0.06), Vector3(sx, 0.65, -0.21), METAL)
	return LowPoly.commit(st)


func _bin_mesh() -> Mesh:
	var st := LowPoly.begin()
	LowPoly.cylinder(st, 0.24, 0.8, Vector3.ZERO, BIN)
	LowPoly.cylinder(st, 0.27, 0.06, Vector3(0, 0.8, 0), METAL)
	return LowPoly.commit(st)


func _planter_mesh() -> Mesh:
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(2.0, 0.4, 2.0), Vector3(0, 0.2, 0), Color("9a9a9a"))
	LowPoly.box(st, Vector3(1.8, 0.05, 1.8), Vector3(0, 0.42, 0), Color("4a3222"))
	var flowers: Array[Color] = [Color("e63946"), Color("ffb703"), Color("ff70a6"), Color("ffffff"), Color("8338ec")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 22:
		var p := Vector3(rng.randf_range(-0.75, 0.75), 0.5, rng.randf_range(-0.75, 0.75))
		LowPoly.box(st, Vector3(0.05, 0.25, 0.05), p + Vector3(0, 0.0, 0), Color("2d6a4f"))
		LowPoly.box(st, Vector3(0.16, 0.12, 0.16), p + Vector3(0, 0.16, 0), flowers[i % flowers.size()])
	LowPoly.box(st, Vector3(0.6, 0.5, 0.6), Vector3(0, 0.7, 0), Color("40916c"))
	return LowPoly.commit(st)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], collider: Vector3) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	var shape := BoxShape3D.new()
	shape.size = collider
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xforms[i].translated_local(Vector3(0, collider.y * 0.5, 0))
		_body.add_child(cs)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# --- Traffic lights -----------------------------------------------------------

## One pole per approach at the near-right corner of each crossing, head facing the driver.
func _build_traffic_lights() -> void:
	var poles: Array[Transform3D] = []
	var lens_xf: Array[Transform3D] = []
	var corner := city.tile_size * 0.42
	for x in city.crossings:
		var centre := city.tile_to_world(x.x, x.y) + Vector3(0, city.curb_height, 0)
		for d in CityBuilder.DIRS: # d = travel direction of approaching cars
			if not city.is_road(x - d):
				continue
			var back := Vector3(-d.x, 0, -d.y)
			var right := Vector3(-d.y, 0, d.x)
			var xf := Transform3D(Basis(Vector3.UP, atan2(back.x, back.z)), centre + (back + right) * corner)
			poles.append(xf)
			for i in 3: # red, yellow, green top->bottom, on the face toward the driver
				lens_xf.append(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.35 - i * 0.27, 0.16)))
				_lens_dirs.append(d)
	var st := LowPoly.begin()
	LowPoly.cylinder(st, 0.07, 3.0, Vector3.ZERO, METAL)
	LowPoly.box(st, Vector3(0.32, 0.9, 0.26), Vector3(0, 3.08, 0), Color("1f1f1f"))
	_multimesh(LowPoly.commit(st), poles, Vector3(0.2, 3.0, 0.2))

	var lens := LowPoly.begin()
	LowPoly.box(lens, Vector3(0.18, 0.18, 0.06), Vector3.ZERO, Color.WHITE)
	_lenses = MultiMesh.new()
	_lenses.transform_format = MultiMesh.TRANSFORM_3D
	_lenses.use_colors = true
	_lenses.mesh = LowPoly.commit(lens, LowPoly.glow_material())
	_lenses.instance_count = lens_xf.size()
	for i in lens_xf.size():
		_lenses.set_instance_transform(i, lens_xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _lenses
	add_child(mmi)
	if traffic:
		traffic.lights_changed.connect(_on_lights_changed)
		_on_lights_changed(traffic.phase)


func _on_lights_changed(phase: int) -> void:
	for i in _lenses.instance_count:
		var d := _lens_dirs[i]
		var ns := d.x == 0
		var lit := 0 # 0 red, 1 yellow, 2 green
		match phase:
			Traffic.Phase.NS_GREEN: lit = 2 if ns else 0
			Traffic.Phase.NS_YELLOW: lit = 1 if ns else 0
			Traffic.Phase.EW_GREEN: lit = 0 if ns else 2
			Traffic.Phase.EW_YELLOW: lit = 0 if ns else 1
		var slot := i % 3
		_lenses.set_instance_color(i, LENS_COLORS[slot] if slot == lit else LIGHT_OFF)


# --- Shop signs ---------------------------------------------------------------

func _build_signs() -> void:
	for shop in city.shops:
		var data: BuildingData = shop.data
		var dir: Vector2i = shop.dir
		var front := Vector3(dir.x, 0, dir.y)
		var base: Vector3 = shop.pos + front * (city.tile_size * 0.5 + 0.05)
		var yaw := atan2(front.x, front.z)
		var name_lbl := _label(data.display_name, 96, Color.WHITE)
		name_lbl.position = base + Vector3(0, 5.6, 0)
		name_lbl.rotation.y = yaw
		var status := _label("", 64, Color.WHITE)
		status.position = base + Vector3(0, 4.9, 0)
		status.rotation.y = yaw
		_signs[data.building_id] = status
		_refresh_sign(data.building_id)
	PropertyManager.building_purchased.connect(_refresh_sign)
	PropertyManager.building_rented.connect(_refresh_sign)
	PropertyManager.business_started.connect(func(id: String, _t: String) -> void: _refresh_sign(id))


func _label(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 18
	l.modulate = col
	l.pixel_size = 0.01
	l.double_sided = false
	add_child(l)
	return l


func _refresh_sign(id: String) -> void:
	var lbl: Label3D = _signs.get(id)
	if lbl == null:
		return
	var biz := PropertyManager.get_business(id)
	if not PropertyManager.is_controlled(id):
		lbl.text = "FOR SALE / RENT"
		lbl.modulate = Color(1, 0.85, 0.3)
	else:
		lbl.text = biz.capitalize() if not biz.is_empty() else "Opening soon"
		lbl.modulate = Color(0.5, 1, 0.6)
