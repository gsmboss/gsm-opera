class_name CityBuilder
extends Node3D
## Builds a tile city from an ASCII map at runtime.
## One MultiMeshInstance3D per tile type -> ~15 draw calls for the whole city.
## Legend:
##  . grass   T trees   t tall trees   p pavement   f fountain
##  | road N-S   - road E-W   L lightposts N-S   l lightposts E-W   + crossing
##  a b c d g  buildings (auto-face nearest road)
##  1..9  purchasable shop -> shop_data[n-1], spawns a BuildingSpot at its door

const MODELS := "res://assets/kenney_city/"
const TILES := {
	".": "grass", "T": "grass-trees", "t": "grass-trees-tall",
	"p": "pavement", "f": "pavement-fountain",
	"|": "road-straight", "-": "road-straight",
	"L": "road-straight-lightposts", "l": "road-straight-lightposts",
	"+": "road-intersection",
	"a": "building-small-a", "b": "building-small-b", "c": "building-small-c",
	"d": "building-small-d", "g": "building-garage",
}
const ROADS := "|-Ll+"
const GROUND_Y := 0.06 # model-space top of pavement/grass (road = 0)
const SHOP_MODEL := "building-small-d" # green awning = storefront
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

@export var tile_size := 8.0 # metres per tile (models are 1x1)
@export var curb_height := 0.15 # metres; model ground layer (0..0.06) is squashed to this
@export var shop_data: Array[BuildingData] = []
@export_multiline var map := """\
tTt|TtTtT|tTt
Tab|cdbga|adT
Tgp|ppppp|paT
---+-l-l-+---
Tdp|ppppp|pcT
t1pLpT.TpLpbt
Tcp|p.f.p|p2T
tapLpT.TpLpdt
Tbp|ppppp|paT
---+-l-l-+---
Tgp|ppppp|pcT
Tdb|acgdb|baT
tTt|TtTtT|tTt"""

var _rows: PackedStringArray
var _xforms: Dictionary[String, Array] = {} # model -> Array[Transform3D]
var _body: StaticBody3D


func _ready() -> void:
	_rows = map.strip_edges().split("\n")
	_body = StaticBody3D.new()
	add_child(_body)
	for r in _rows.size():
		for c in _rows[r].length():
			_place(c, r, _rows[r][c])
	for model: String in _xforms:
		_build_multimesh(model, _xforms[model])
	_add_ground_and_bounds()


## Tile (c, r) -> world position of tile centre (map centred on origin).
func tile_to_world(c: int, r: int) -> Vector3:
	return Vector3((c - (_cols() - 1) * 0.5) * tile_size, 0.0, (r - (_rows.size() - 1) * 0.5) * tile_size)


func _cols() -> int:
	return _rows[0].length()


func _place(c: int, r: int, ch: String) -> void:
	var model: String = TILES.get(ch, "")
	var yaw := 0.0
	var shop_idx := -1
	if ch.is_valid_int():
		model = SHOP_MODEL
		shop_idx = ch.to_int() - 1
	if model.is_empty():
		return
	if ch == "-" or ch == "l":
		yaw = PI * 0.5 # road models run N-S by default
	var dir := Vector2i.ZERO
	if model.begins_with("building"):
		dir = _face_road(c, r)
		yaw = atan2(dir.x, dir.y) # model door faces +Z
	var pos := tile_to_world(c, r)
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos) # unscaled: mesh is pre-scaled
	_xforms.get_or_add(model, []).append(xf)
	_add_collider(model, pos)
	if shop_idx >= 0 and shop_idx < shop_data.size():
		_add_spot(shop_data[shop_idx], pos + Vector3(dir.x, 0, dir.y) * tile_size * 0.85)


## Direction to the nearest road within 2 tiles (prefers distance 1).
func _face_road(c: int, r: int) -> Vector2i:
	for dist in [1, 2]:
		for d in DIRS:
			if ROADS.contains(_char_at(c + d.x * dist, r + d.y * dist)):
				return d
	return DIRS[0]


func _char_at(c: int, r: int) -> String:
	if r < 0 or r >= _rows.size() or c < 0 or c >= _rows[r].length():
		return ""
	return _rows[r][c]


func _build_multimesh(model: String, xforms: Array) -> void:
	var src: Node = load(MODELS + model + ".glb").instantiate()
	var mesh_node := src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _scaled_mesh(mesh_node.mesh, tile_size)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = model
	mmi.multimesh = mm
	add_child(mmi)
	src.free() # only the mesh resource is kept


## Bakes scale into vertices once (no per-instance scale).
## Ground layer (y <= 0.06) is squashed to curb_height so sidewalks are walkable;
## everything above keeps true scale and is shifted down to stay attached.
func _scaled_mesh(src: Mesh, s: float) -> ArrayMesh:
	var flat := curb_height / GROUND_Y
	var drop := GROUND_Y * s - curb_height
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts.size():
			var p := verts[v]
			var y := p.y * flat if p.y <= GROUND_Y + 0.001 else p.y * s - drop
			verts[v] = Vector3(p.x * s, y, p.z * s)
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, src.surface_get_material(i))
	return out


func _add_collider(model: String, pos: Vector3) -> void:
	var size := Vector3.ZERO
	if model.begins_with("building"):
		size = Vector3(0.92, 2.0, 0.92) * tile_size
	elif model.begins_with("grass-trees"):
		size = Vector3(0.7, 0.5, 0.7) * tile_size
	elif model == "pavement-fountain":
		size = Vector3(0.45, 0.1, 0.45) * tile_size
	if size == Vector3.ZERO:
		return
	_add_box(size, pos + Vector3(0, size.y * 0.5, 0))


func _add_box(size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	_body.add_child(cs)


func _add_spot(data: BuildingData, pos: Vector3) -> void:
	var spot := BuildingSpot.new()
	spot.name = "Spot_" + data.building_id
	spot.data = data
	spot.position = pos + Vector3(0, 1.5, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	spot.add_child(cs)
	add_child(spot)


## Walkable floor at tile-top height, far grass plane to the horizon, edge walls.
func _add_ground_and_bounds() -> void:
	var w := _cols() * tile_size
	var h := _rows.size() * tile_size
	var top := curb_height * 0.5 # between asphalt (0) and sidewalk
	_add_box(Vector3(w, 1.0, h), Vector3(0, top - 0.5, 0))
	for s in [-1, 1]:
		_add_box(Vector3(w, 20, 1), Vector3(0, 10, s * h * 0.5))
		_add_box(Vector3(1, 20, h), Vector3(s * w * 0.5, 10, 0))
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.72, 0.5)
	plane.material = mat
	var far := MeshInstance3D.new()
	far.mesh = plane
	far.position.y = -0.05 # below asphalt
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
