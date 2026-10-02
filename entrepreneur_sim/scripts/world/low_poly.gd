class_name LowPoly
extends RefCounted
## Builds flat-shaded, vertex-coloured meshes from boxes/cylinders.
## All share ONE material -> cheap batching, no textures.

static var _material: StandardMaterial3D
static var _glow: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.9
	return _material


## Unshaded vertex/instance colour: lamp bulbs, traffic lenses.
static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.vertex_color_use_as_albedo = true
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _glow


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func commit(st: SurfaceTool, mat: Material = null) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, mat if mat else material())
	return mesh


## Quad with explicit face normal; winding fixed automatically.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0: # CCW seen from front -> flip to Godot's CW
		var t := b; b = d; d = t
	st.set_color(col)
	st.set_normal(n)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


static func box(st: SurfaceTool, size: Vector3, center: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for i in 3:
		var n: Vector3 = axes[i]
		var u: Vector3 = axes[(i + 1) % 3]
		var v: Vector3 = axes[(i + 2) % 3]
		for s in [-1.0, 1.0]:
			var fn: Vector3 = n * s
			var fc: Vector3 = fn * h[i]
			var hu: Vector3 = u * h[(i + 1) % 3]
			var hv: Vector3 = v * h[(i + 2) % 3]
			quad(st, center + basis * (fc - hu - hv), center + basis * (fc + hu - hv),
				center + basis * (fc + hu + hv), center + basis * (fc - hu + hv), basis * fn, col)


static func cylinder(st: SurfaceTool, radius: float, height: float, base: Vector3, col: Color, sides := 8) -> void:
	var top := base + Vector3.UP * height
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := Vector3(cos(a1), 0, sin(a1)) * radius
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		quad(st, base + p0, base + p1, top + p1, top + p0, n, col)
		_tri(st, top, top + p0, top + p1, Vector3.UP, col)
		_tri(st, base, base + p1, base + p0, Vector3.DOWN, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b; b = c; c = t
	st.set_color(col)
	st.set_normal(n)
	for v in [a, b, c]:
		st.add_vertex(v)


## Soft round shadow blob (unshaded, alpha) for cars/people. Shared resource.
static var _blob: QuadMesh

static func blob_shadow() -> QuadMesh:
	if _blob == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.45))
		g.set_color(1, Color(0, 0, 0, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob = QuadMesh.new()
		_blob.orientation = PlaneMesh.FACE_Y
		_blob.material = mat
	return _blob
