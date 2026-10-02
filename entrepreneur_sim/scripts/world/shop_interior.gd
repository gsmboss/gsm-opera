class_name ShopInterior
extends Node3D
## Supermarket-style shop interior, built once far from the city (camera far-plane hides the city).
## Look-to-interact via a centre-screen ray: pick up delivery boxes, stock shelves,
## check out customers at the register, exit through the door.
## Visuals live on render layer 2 so the city sun doesn't light them.

const LAYER := 2               # visual layer bit value (layer 2)
const PICK_MASK := 4           # physics layer 3 "interactables"
const REACH := 3.6
const MAX_CUSTOMERS := 6
const PATIENCE := 45.0
const WALK := 1.4
const SPAWN := Vector3(0, 1.0, 5.4)
const DOOR_IN := Vector3(0, 0, 6.0)
const DOOR_OUT := Vector3(0, 0, 8.5)
const COUNTER := Vector3(3.9, 0, 4.6)
const CASHIER_POS := Vector3(5.0, 0, 4.6)
const PILE := Vector3(-4.7, 0, 5.6)
## Shelf slots: [position, yaw]; front faces local +Z after yaw.
const SHELF_SLOTS := [
	[Vector3(-5.6, 0, -4.5), PI * 0.5], [Vector3(-5.6, 0, -1.5), PI * 0.5],
	[Vector3(5.6, 0, -4.5), -PI * 0.5], [Vector3(5.6, 0, -1.5), -PI * 0.5],
	[Vector3(-1.6, 0, -6.6), 0.0], [Vector3(1.6, 0, -6.6), 0.0],
	[Vector3(-5.6, 0, 1.5), PI * 0.5], [Vector3(0, 0, -2.5), 0.0],
]

@export var player: PlayerController
@export var city: CityBuilder
@export var building_ui: MobileBuildingUI
@export var shop_ui: ShopUI

var shop_id := ""
var _state: ShopState
var _active := false
var _outside_xf: Transform3D
var _rng := RandomNumberGenerator.new()

var _static: Node3D          # room geometry, rebuilt per business type
var _shelves: Array[Dictionary] = [] # {body, mm: MultiMesh, label: Label3D, front: Vector3}
var _box_nodes: Node3D
var _customers: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _spawn_left := 2.0
var _cashier: Dictionary = {}
var _cashier_timer := 0.0
var _target := {}            # current ray target meta {kind, idx}
var _checkout_customer: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	visible = false
	building_ui.enter_shop_requested.connect(enter)
	shop_ui.action_pressed.connect(_on_action)
	shop_ui.exit_pressed.connect(exit)
	shop_ui.checkout_finished.connect(_on_checkout_finished)
	BusinessManager.shop_changed.connect(_on_shop_changed)
	BusinessManager.sale_made.connect(func(id: String, amount: float) -> void:
		if id == shop_id: shop_ui.notify("+$%.2f" % amount))
	BusinessManager.notify.connect(shop_ui.notify)


# --- Enter / exit ---------------------------------------------------------------

func enter(id: String) -> void:
	_state = BusinessManager.get_shop(id)
	if _state == null:
		return
	shop_id = id
	_active = true
	visible = true
	BusinessManager.live_shop_id = id
	_outside_xf = player.global_transform
	_build_room()
	_rebuild_dynamic()
	player.global_position = to_global(SPAWN)
	player.rotation = Vector3.ZERO # face -Z: towards the shelves
	player.velocity = Vector3.ZERO
	shop_ui.show_inside(true, id)
	_spawn_left = 1.5


func exit() -> void:
	if not _active:
		return
	BusinessManager.put_back_box(shop_id)
	player.set_carry(null)
	shop_ui.close_checkout()
	for c in _customers:
		c.root.queue_free()
	_customers.clear()
	_queue.clear()
	_checkout_customer = {}
	_active = false
	visible = false
	BusinessManager.live_shop_id = ""
	# Back outside, in front of the shop door, facing the street.
	var dir := Vector2i(0, 1)
	var pos := _outside_xf.origin
	for s in city.shops:
		if s.data.building_id == shop_id:
			dir = s.dir
			pos = s.pos + Vector3(dir.x, 0, dir.y) * city.tile_size * 0.9 + Vector3(0, 1.0, 0)
	player.global_position = pos
	player.rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
	shop_ui.show_inside(false, "")
	shop_id = ""


# --- Room -----------------------------------------------------------------------

func _build_room() -> void:
	if _static:
		_static.queue_free()
	_static = Node3D.new()
	add_child(_static)
	var theme: Array = BusinessCatalog.THEMES.get(_state.business_type, BusinessCatalog.THEMES.grocery)
	var wall: Color = theme[0]
	var floor_c: Color = theme[1]
	var accent: Color = theme[2]
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(12, 0.1, 14), Vector3(0, -0.05, 0), floor_c)
	for i in 6: # floor tile stripes
		LowPoly.box(st, Vector3(12, 0.002, 0.05), Vector3(0, 0.001, -6 + i * 2.4), floor_c.darkened(0.15))
	LowPoly.box(st, Vector3(12, 0.1, 14), Vector3(0, 3.65, 0), Color("f5f5f5"))           # ceiling
	LowPoly.box(st, Vector3(12, 3.6, 0.2), Vector3(0, 1.8, -7.1), wall)                    # back
	LowPoly.box(st, Vector3(0.2, 3.6, 14), Vector3(-6.1, 1.8, 0), wall)                    # left
	LowPoly.box(st, Vector3(0.2, 3.6, 14), Vector3(6.1, 1.8, 0), wall)                     # right
	LowPoly.box(st, Vector3(5, 3.6, 0.2), Vector3(-3.5, 1.8, 7.1), wall)                   # front L
	LowPoly.box(st, Vector3(5, 3.6, 0.2), Vector3(3.5, 1.8, 7.1), wall)                    # front R
	LowPoly.box(st, Vector3(2, 1.2, 0.2), Vector3(0, 3.0, 7.1), wall)                      # above door
	LowPoly.box(st, Vector3(12, 0.5, 0.05), Vector3(0, 0.25, -6.98), accent)               # skirting
	LowPoly.box(st, Vector3(12, 0.25, 0.05), Vector3(0, 3.2, -6.98), accent)               # back stripe
	LowPoly.box(st, Vector3(1.9, 2.35, 0.08), Vector3(0, 1.18, 7.0), Color("8ecae6"))      # glass door
	LowPoly.box(st, Vector3(0.08, 2.4, 0.12), Vector3(0, 1.2, 6.98), Color("adb5bd"))       # door frame
	LowPoly.box(st, Vector3(1.0, 1.0, 2.6), COUNTER + Vector3(0, 0.5, 0), accent)          # counter
	LowPoly.box(st, Vector3(1.1, 0.06, 2.7), COUNTER + Vector3(0, 1.03, 0), Color("e9ecef"))
	LowPoly.box(st, Vector3(1.0, 0.04, 0.6), Vector3(-4.7, 0.02, 4.8) , Color("ffd166"))   # delivery mat
	for z in [-4.0, 0.0, 4.0]: # ceiling light panels
		for x in [-3.0, 3.0]:
			LowPoly.box(st, Vector3(1.6, 0.04, 0.5), Vector3(x, 3.58, z), Color.WHITE)
	for i in 3: # posters on the back wall
		LowPoly.box(st, Vector3(1.4, 0.9, 0.03), Vector3(-3.5 + i * 3.5, 2.45, -6.98), accent.lightened(0.2 * i))
		LowPoly.box(st, Vector3(1.0, 0.18, 0.035), Vector3(-3.5 + i * 3.5, 2.45, -6.97), Color.WHITE)
	for x in [-1.6, 1.6]: # potted plants either side of the door
		LowPoly.cylinder(st, 0.25, 0.45, Vector3(x, 0, 6.5), Color("bc6c25"))
		LowPoly.box(st, Vector3(0.5, 0.6, 0.5), Vector3(x, 0.75, 6.5), Color("40916c"))
		LowPoly.box(st, Vector3(0.35, 0.35, 0.35), Vector3(x, 1.2, 6.5), Color("52b788"))
	_mesh(_static, LowPoly.commit(st))
	# Register (pick target) on the counter.
	var reg := LowPoly.begin()
	LowPoly.box(reg, Vector3(0.45, 0.25, 0.4), Vector3(0, 0.125, 0), Color("343a40"))
	LowPoly.box(reg, Vector3(0.4, 0.28, 0.04), Vector3(0, 0.42, -0.1), Color("212529"))
	LowPoly.box(reg, Vector3(0.34, 0.2, 0.01), Vector3(0, 0.42, -0.075), Color("4cc9f0"))
	var reg_mi := _mesh(_static, LowPoly.commit(reg))
	reg_mi.position = COUNTER + Vector3(0, 1.06, -0.5)
	reg_mi.rotation.y = PI * 0.5
	# Colliders: walls/floor/counter block the player; door + register are pick targets.
	var walls := StaticBody3D.new()
	_static.add_child(walls)
	for b in [[Vector3(12, 0.2, 14), Vector3(0, -0.1, 0)], [Vector3(12, 3.6, 0.2), Vector3(0, 1.8, -7.1)],
			[Vector3(0.2, 3.6, 14), Vector3(-6.1, 1.8, 0)], [Vector3(0.2, 3.6, 14), Vector3(6.1, 1.8, 0)],
			[Vector3(12, 3.6, 0.2), Vector3(0, 1.8, 7.1)], [Vector3(1.0, 1.1, 2.6), COUNTER + Vector3(0, 0.55, 0)]]:
		_box_shape(walls, b[0], b[1])
	_pick_body(_static, "register", 0, Vector3(0.6, 0.6, 0.6), reg_mi.position + Vector3(0, 0.25, 0))
	_pick_body(_static, "door", 0, Vector3(2.0, 2.4, 0.3), Vector3(0, 1.2, 6.9))
	# Light: one omni for the whole room (layer-2 only).
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.2, 0)
	lamp.omni_range = 14.0
	lamp.light_energy = 0.75
	lamp.light_color = Color(1.0, 0.96, 0.9)
	lamp.light_cull_mask = LAYER
	_static.add_child(lamp)
	_build_shelves()


func _build_shelves() -> void:
	_shelves.clear()
	var frame := LowPoly.begin()
	var metal := Color("dee2e6")
	LowPoly.box(frame, Vector3(2.0, 0.08, 0.5), Vector3(0, 0.08, 0), metal)
	for y in [0.5, 0.95, 1.4, 1.85]:
		LowPoly.box(frame, Vector3(2.0, 0.04, 0.5), Vector3(0, y, 0), metal)
	LowPoly.box(frame, Vector3(2.0, 1.9, 0.05), Vector3(0, 0.95, -0.24), metal.darkened(0.1))
	for sx in [-1.0, 1.0]:
		LowPoly.box(frame, Vector3(0.05, 1.9, 0.5), Vector3(sx, 0.95, 0), metal.darkened(0.2))
	var frame_mesh := LowPoly.commit(frame)
	for i in _state.shelves.size():
		var slot: Array = SHELF_SLOTS[i]
		var holder := Node3D.new()
		holder.position = slot[0]
		holder.rotation.y = slot[1]
		_static.add_child(holder)
		_mesh(holder, frame_mesh)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = BusinessCatalog.SHELF_CAPACITY
		for lvl in BusinessCatalog.SHELF_LEVELS:
			for col in BusinessCatalog.SHELF_COLS:
				mm.set_instance_transform(lvl * BusinessCatalog.SHELF_COLS + col,
					Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.25), Vector3(-0.75 + col * 0.3, 0.12 + lvl * 0.45, 0.02)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = LAYER
		holder.add_child(mmi)
		var label := Label3D.new()
		label.position = Vector3(0, 2.05, 0.2)
		label.font_size = 40
		label.pixel_size = 0.005
		label.outline_size = 10
		label.layers = LAYER
		holder.add_child(label)
		var body := _pick_body(holder, "shelf", i, Vector3(2.0, 1.9, 0.5), Vector3(0, 0.95, 0))
		body.collision_layer = 1 | PICK_MASK # also blocks the player
		_shelves.append({mm = mm, label = label,
			front = holder.position + Vector3(sin(slot[1]), 0, cos(slot[1])) * 0.85})


## Shelf contents, price tags, delivery pile, cashier: cheap refresh on every shop change.
func _rebuild_dynamic() -> void:
	if _shelves.size() != _state.shelves.size():
		_build_room()
	for i in _shelves.size():
		var data: Dictionary = _state.shelves[i]
		var sh: Dictionary = _shelves[i]
		var mm: MultiMesh = sh.mm
		if data.product != "":
			if mm.mesh != BusinessCatalog.item_mesh(data.product):
				mm.mesh = BusinessCatalog.item_mesh(data.product)
			mm.visible_instance_count = int(data.count)
			var info := BusinessCatalog.info(data.product)
			sh.label.text = "%s  $%.2f  (%d)" % [info.name, _state.price_of(data.product), data.count]
			sh.label.modulate = Color.WHITE if int(data.count) > 0 else Color(1, 0.5, 0.4)
		else:
			mm.visible_instance_count = 0
			sh.label.text = "Empty shelf"
			sh.label.modulate = Color(0.8, 0.8, 0.8)
	_rebuild_boxes()
	_sync_cashier()
	player.set_carry(_box_mesh(BusinessManager.get_carried(shop_id).get("product", "")) if not BusinessManager.get_carried(shop_id).is_empty() else null)


func _rebuild_boxes() -> void:
	if _box_nodes:
		_box_nodes.queue_free()
	_box_nodes = Node3D.new()
	add_child(_box_nodes)
	for i in _state.boxes.size():
		var b: Dictionary = _state.boxes[i]
		var pos := PILE + Vector3((i % 2) * 0.7, 0, -(i / 2) * 0.65)
		var mi := _mesh(_box_nodes, _box_mesh(b.product))
		mi.position = pos
		_pick_body(_box_nodes, "box", i, Vector3(0.55, 0.45, 0.45), pos + Vector3(0, 0.22, 0))


static var _box_meshes: Dictionary[String, Mesh] = {}

## Cardboard carton with a product-coloured label.
func _box_mesh(product: String) -> Mesh:
	if _box_meshes.has(product):
		return _box_meshes[product]
	var c: Color = BusinessCatalog.info(product).get("color", Color.WHITE)
	var st := LowPoly.begin()
	LowPoly.box(st, Vector3(0.5, 0.4, 0.4), Vector3(0, 0.2, 0), Color("c8a165"))
	LowPoly.box(st, Vector3(0.3, 0.16, 0.405), Vector3(0, 0.22, 0), c)
	LowPoly.box(st, Vector3(0.505, 0.04, 0.1), Vector3(0, 0.4, 0), Color("a0763c")) # tape
	_box_meshes[product] = LowPoly.commit(st)
	return _box_meshes[product]


func _sync_cashier() -> void:
	if _state.cashier and _cashier.is_empty():
		_cashier = PersonBuilder.build(_rng, 60.0, LAYER, BusinessCatalog.THEMES.get(_state.business_type, [0, 0, Color.RED])[2])
		add_child(_cashier.root)
		_cashier.root.position = CASHIER_POS
		_cashier.root.rotation.y = -PI * 0.5
	elif not _state.cashier and not _cashier.is_empty():
		_cashier.root.queue_free()
		_cashier = {}


func _on_shop_changed(id: String) -> void:
	if _active and id == shop_id:
		_rebuild_dynamic()


# --- Helpers ----------------------------------------------------------------------

func _mesh(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.layers = LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box_shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _pick_body(parent: Node3D, kind: String, idx: int, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PICK_MASK
	body.collision_mask = 0
	body.set_meta(&"kind", kind)
	body.set_meta(&"idx", idx)
	_box_shape(body, size, pos)
	parent.add_child(body)
	return body


# --- Look-to-interact ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_update_target()
	_update_customers(delta)
	_update_cashier(delta)


func _update_target() -> void:
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * REACH, PICK_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_target = {}
	if hit and hit.collider.has_meta(&"kind"):
		_target = {kind = hit.collider.get_meta(&"kind"), idx = hit.collider.get_meta(&"idx")}
	shop_ui.set_action(_action_text())


func _action_text() -> String:
	var carried := BusinessManager.get_carried(shop_id)
	var kind: String = _target.get("kind", "")
	if not carried.is_empty():
		if kind == "shelf":
			var shelf: Dictionary = _state.shelves[_target.idx]
			var free := BusinessCatalog.SHELF_CAPACITY - int(shelf.count)
			if shelf.product != "" and shelf.product != carried.product and int(shelf.count) > 0:
				return "Shelf: %s" % BusinessCatalog.info(shelf.product).name
			return "Stock shelf +%d" % mini(int(carried.count), free)
		return "Put box back"
	match kind:
		"box":
			var b: Dictionary = _state.boxes[_target.idx]
			return "Pick up %s x%d" % [BusinessCatalog.info(b.product).name, b.count]
		"register":
			var front := _front_customer()
			if front.is_empty():
				return ""
			return "Checkout · %d item%s" % [front.basket.size(), "" if front.basket.size() == 1 else "s"]
		"door":
			return "Exit shop"
	return ""


func _on_action() -> void:
	if not _active:
		return
	var carried := BusinessManager.get_carried(shop_id)
	var kind: String = _target.get("kind", "")
	if not carried.is_empty():
		if kind == "shelf":
			var n := BusinessManager.stock_shelf(shop_id, _target.idx)
			if n > 0:
				shop_ui.notify("Stocked +%d" % n)
		else:
			BusinessManager.put_back_box(shop_id)
		return
	match kind:
		"box":
			BusinessManager.pick_up_box(shop_id, _target.idx)
		"register":
			var front := _front_customer()
			if not front.is_empty() and _checkout_customer.is_empty():
				_checkout_customer = front
				var prices: Array[float] = []
				for p: String in front.basket:
					prices.append(_state.price_of(p))
				shop_ui.open_checkout(front.basket, prices)
		"door":
			exit()


func _on_checkout_finished() -> void:
	if _checkout_customer.is_empty():
		return
	_serve(_checkout_customer)
	_checkout_customer = {}


# --- Customers --------------------------------------------------------------------

func _update_customers(delta: float) -> void:
	if BusinessManager.is_open():
		_spawn_left -= delta
		if _spawn_left <= 0.0:
			var hour_secs := EconomyManager.SECONDS_PER_DAY / 24.0
			_spawn_left = hour_secs / maxf(BusinessManager.customer_rate(shop_id), 0.1) * _rng.randf_range(0.6, 1.4)
			if _customers.size() < MAX_CUSTOMERS and not _product_shelves().is_empty():
				_spawn_customer()
	for c in _customers.duplicate():
		_tick_customer(c, delta)


func _spawn_customer() -> void:
	var c := PersonBuilder.build(_rng, 60.0, LAYER)
	add_child(c.root)
	c.root.position = DOOR_OUT
	var options := _product_shelves()
	var wants: Array[int] = []
	for k in _rng.randi_range(1, mini(4, options.size() + 1)):
		wants.append(options[_rng.randi() % options.size()])
	c.merge({state = "browse", wants = wants, basket = [] as Array[String], path = [DOOR_IN] as Array[Vector3],
		wait = 0.0, patience = PATIENCE})
	_route_to_next_shelf(c)
	_customers.append(c)


## Shelves that have ever been assigned a product (empty ones still attract shoppers -> "out of stock").
func _product_shelves() -> Array[int]:
	var out: Array[int] = []
	for i in _state.shelves.size():
		if _state.shelves[i].product != "":
			out.append(i)
	return out


func _route_to_next_shelf(c: Dictionary) -> void:
	if c.wants.is_empty():
		_join_queue(c)
		return
	var front: Vector3 = _shelves[c.wants[0]].front
	var aisle := -3.2 if front.x < 0.0 else 3.2
	if absf(front.x) > 4.0:
		aisle = front.x * 0.6
	c.path.append(Vector3(aisle, 0, c.root.position.z if c.path.is_empty() else c.path[-1].z))
	c.path.append(Vector3(aisle, 0, front.z))
	c.path.append(front)


func _tick_customer(c: Dictionary, delta: float) -> void:
	var root: Node3D = c.root
	var moving := false
	if not c.path.is_empty():
		var to: Vector3 = c.path[0] - root.position
		to.y = 0.0
		if to.length() < 0.15:
			c.path.pop_front()
			if c.path.is_empty():
				_arrived(c)
		else:
			moving = true
			root.position += to.normalized() * minf(WALK * delta, to.length())
			root.rotation.y = lerp_angle(root.rotation.y, atan2(to.x, to.z), minf(1.0, 10.0 * delta))
	elif c.state == "pick":
		c.wait -= delta
		if c.wait <= 0.0:
			_pick_item(c)
	elif c.state == "queue":
		c.patience -= delta
		root.rotation.y = lerp_angle(root.rotation.y, PI * 0.5, minf(1.0, 8.0 * delta))
		if c.patience <= 0.0 and c != _checkout_customer:
			_give_up(c)
	PersonBuilder.animate(c, moving, WALK, delta)


func _arrived(c: Dictionary) -> void:
	match c.state:
		"browse":
			c.state = "pick"
			c.wait = _rng.randf_range(0.6, 1.4)
		"leave":
			_customers.erase(c)
			c.root.queue_free()


func _pick_item(c: Dictionary) -> void:
	var idx: int = c.wants.pop_front()
	var shelf: Dictionary = _state.shelves[idx]
	if int(shelf.count) > 0 and BusinessManager.wants(shop_id, shelf.product):
		c.basket.append(BusinessManager.take_item(shop_id, idx))
	elif int(shelf.count) <= 0 and shelf.product != "":
		shop_ui.notify("%s is out of stock!" % BusinessCatalog.info(shelf.product).name)
	c.state = "browse"
	_route_to_next_shelf(c)


func _join_queue(c: Dictionary) -> void:
	if c.basket.is_empty():
		BusinessManager.customer_lost(shop_id)
		_leave(c)
		return
	c.state = "queue"
	_queue.append(c)
	c.path.append(Vector3(2.9, 0, c.root.position.z if absf(c.root.position.x) < 3.5 else 0.0))
	_reposition_queue()


func _queue_slot(k: int) -> Vector3:
	return Vector3(2.9, 0, 4.4 - k * 0.9)


func _reposition_queue() -> void:
	for k in _queue.size():
		var c: Dictionary = _queue[k]
		var slot := _queue_slot(k)
		if c.path.is_empty() or c.path[-1] != slot:
			c.path.append(slot)


func _front_customer() -> Dictionary:
	if _queue.is_empty():
		return {}
	var c: Dictionary = _queue[0]
	return c if c.path.is_empty() else {}


func _serve(c: Dictionary) -> void:
	BusinessManager.checkout(shop_id, c.basket)
	_queue.erase(c)
	_reposition_queue()
	_leave(c)


func _give_up(c: Dictionary) -> void:
	for p: String in c.basket: # put goods back
		for s in _state.shelves:
			if s.product == p and int(s.count) < BusinessCatalog.SHELF_CAPACITY:
				s.count = int(s.count) + 1
				break
	BusinessManager.customer_lost(shop_id)
	shop_ui.notify("A customer left the queue")
	_queue.erase(c)
	_reposition_queue()
	_leave(c)
	_on_shop_changed(shop_id)


func _leave(c: Dictionary) -> void:
	c.state = "leave"
	c.path.clear()
	c.path.append(Vector3(1.2, 0, 5.4))
	c.path.append(DOOR_IN)
	c.path.append(DOOR_OUT)


func _update_cashier(delta: float) -> void:
	if not _state.cashier:
		return
	var front := _front_customer()
	if front.is_empty() or front == _checkout_customer:
		_cashier_timer = 0.0
		return
	_cashier_timer += delta
	if _cashier_timer >= 0.7 * front.basket.size() + 0.8:
		_cashier_timer = 0.0
		_serve(front)
