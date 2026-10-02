class_name DayNight
extends Node
## Sun arc, sky/fog/ambient colours and street-lamp glow from EconomyManager's clock.
## Cheap: no real lights for lamps (emissive bulbs only).

@export var sun: DirectionalLight3D
@export var world_env: WorldEnvironment
@export var city: CityBuilder

const SKY_DAY := Color(0.32, 0.55, 0.88)
const SKY_NIGHT := Color(0.02, 0.03, 0.09)
const HORIZON_DAY := Color(0.72, 0.82, 0.92)
const HORIZON_SUNSET := Color(0.98, 0.6, 0.38)
const HORIZON_NIGHT := Color(0.07, 0.08, 0.14)
const AMBIENT_DAY := Color(0.62, 0.66, 0.74)
const AMBIENT_NIGHT := Color(0.22, 0.26, 0.4)
const SUN_WARM := Color(1.0, 0.62, 0.38)
const SUNRISE := 6.0
const SUNSET := 20.0

var _sky: ProceduralSkyMaterial
var _env: Environment
var _lamps: MultiMeshInstance3D


func _ready() -> void:
	_env = world_env.environment
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_build_lamps()
	_apply(EconomyManager.get_hour())


func _process(_delta: float) -> void:
	_apply(EconomyManager.get_hour())


func _apply(hour: float) -> void:
	var t := (hour - SUNRISE) / (SUNSET - SUNRISE) # 0 sunrise .. 1 sunset
	var elevation := sin(t * PI)              # >0 day, <0 night
	var day := smoothstep(-0.12, 0.25, elevation)
	var warm := (1.0 - smoothstep(0.0, 0.45, elevation)) * day

	sun.rotation_degrees = Vector3(-8.0 - clampf(elevation, 0.0, 1.0) * 62.0, 90.0 - t * 180.0, 0.0)
	sun.light_energy = day
	sun.light_color = Color.WHITE.lerp(SUN_WARM, warm)
	sun.visible = day > 0.01

	var horizon := HORIZON_NIGHT.lerp(HORIZON_DAY.lerp(HORIZON_SUNSET, warm), day)
	_sky.sky_top_color = SKY_NIGHT.lerp(SKY_DAY, day)
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = horizon.darkened(0.4)
	_env.fog_light_color = horizon
	_env.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, day)
	_env.ambient_light_energy = 1.0
	_lamps.visible = day < 0.35


func _build_lamps() -> void:
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(0.45, 0.14, 0.3), Vector3.ZERO, Color(1.0, 0.86, 0.55))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = LowPoly.commit(st, LowPoly.glow_material())
	mm.instance_count = city.lamp_heads.size()
	for i in city.lamp_heads.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, city.lamp_heads[i] + Vector3(0, -0.08, 0)))
	_lamps = MultiMeshInstance3D.new()
	_lamps.multimesh = mm
	_lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.add_child(_lamps)
	# Fake light pools on the ground: additive radial quads (no real lights -> mobile-cheap).
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.45, 0.55))
	g.set_color(1, Color(1.0, 0.8, 0.45, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(8, 8)
	quad.material = mat
	var pools := MultiMesh.new()
	pools.transform_format = MultiMesh.TRANSFORM_3D
	pools.mesh = quad
	pools.instance_count = city.lamp_heads.size()
	for i in city.lamp_heads.size():
		var p := city.lamp_heads[i]
		pools.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, city.curb_height + 0.03, p.z)))
	var pool_mmi := MultiMeshInstance3D.new()
	pool_mmi.multimesh = pools
	pool_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamps.add_child(pool_mmi)
