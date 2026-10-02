extends Node
## Autoload "BusinessManager": supermarket-style shop simulation.
## Orders -> boxes at the door -> shelves -> customers -> checkout -> money + XP.
## While the player is away, only shops with a cashier keep selling (hourly sim).

signal shop_changed(building_id: String)
signal sale_made(building_id: String, amount: float)
signal level_up(building_id: String, level: int)
signal notify(text: String)

const OPEN_HOUR := 8
const CLOSE_HOUR := 22
const MAX_BOXES := 8

var live_shop_id := "" # shop the player is inside (real-time sim runs there instead)

var _last_hour := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	PropertyManager.business_started.connect(_on_business_started)
	EconomyManager.day_passed.connect(_on_day_passed)
	for id: String in _shops():
		_sync_wage(id)


func _shops() -> Dictionary[String, ShopState]:
	return EconomyManager.player.shops


func get_shop(id: String) -> ShopState:
	return _shops().get(id)


func is_open() -> bool:
	var h := EconomyManager.get_hour()
	return h >= OPEN_HOUR and h < CLOSE_HOUR


## Customers per in-game hour.
func customer_rate(id: String) -> float:
	var data := PropertyManager.get_building(id)
	var traffic := data.foot_traffic_rating if data else 2
	var s := get_shop(id)
	return 0.6 * traffic + 0.3 * (s.level if s else 1) + 0.4 * (s.tier if s else 0)


# --- Setup --------------------------------------------------------------------

func _on_business_started(id: String, type: String) -> void:
	var s := get_shop(id)
	if s and s.business_type == type:
		return
	s = ShopState.new()
	s.building_id = id
	s.business_type = type
	for i in BusinessCatalog.SHELVES_PER_TIER[0]:
		s.shelves.append({product = "", count = 0})
	var first: String = BusinessCatalog.products_for(type)[0]
	s.boxes.append({product = first, count = int(BusinessCatalog.info(first).box)}) # free starter box
	_shops()[id] = s
	shop_changed.emit(id)


# --- Player actions -----------------------------------------------------------

func order_box(id: String, product: String) -> bool:
	var s := get_shop(id)
	var p := BusinessCatalog.info(product)
	if s == null or p.is_empty():
		return false
	if s.level < int(p.lvl):
		notify.emit("Unlocks at level %d" % p.lvl)
		return false
	if s.boxes.size() >= MAX_BOXES:
		notify.emit("Delivery area is full")
		return false
	if not EconomyManager.spend(float(p.cost) * int(p.box)):
		notify.emit("Not enough money")
		return false
	s.boxes.append({product = product, count = int(p.box)})
	shop_changed.emit(id)
	return true


## Moves box `idx` from the delivery pile into the player's hands.
func pick_up_box(id: String, idx: int) -> bool:
	var s := get_shop(id)
	if s == null or idx < 0 or idx >= s.boxes.size() or not get_carried(id).is_empty():
		return false
	set_carried(id, s.boxes.pop_at(idx))
	shop_changed.emit(id)
	return true


func put_back_box(id: String) -> void:
	var s := get_shop(id)
	var c := get_carried(id)
	if s and not c.is_empty():
		s.boxes.append(c)
		set_carried(id, {})
		shop_changed.emit(id)


## Fills shelf from the carried box. Returns units moved.
func stock_shelf(id: String, shelf_idx: int) -> int:
	var s := get_shop(id)
	var c := get_carried(id)
	if s == null or c.is_empty() or shelf_idx >= s.shelves.size():
		return 0
	var shelf: Dictionary = s.shelves[shelf_idx]
	if shelf.product != "" and shelf.product != c.product and int(shelf.count) > 0:
		notify.emit("Shelf holds %s" % BusinessCatalog.info(shelf.product).name)
		return 0
	var n := mini(int(c.count), BusinessCatalog.SHELF_CAPACITY - int(shelf.count))
	if n <= 0:
		notify.emit("Shelf is full")
		return 0
	shelf.product = c.product
	shelf.count = int(shelf.count) + n
	c.count = int(c.count) - n
	if int(c.count) <= 0:
		set_carried(id, {})
	shop_changed.emit(id)
	return n


## Carried box is stored on the state so it survives autosave.
func get_carried(id: String) -> Dictionary:
	var s := get_shop(id)
	return s.carried if s else {}


func set_carried(id: String, box: Dictionary) -> void:
	var s := get_shop(id)
	if s:
		s.carried = box


func set_price(id: String, product: String, price: float) -> void:
	var s := get_shop(id)
	if s:
		s.prices[product] = snappedf(maxf(price, 0.1), 0.1)
		shop_changed.emit(id)


func set_cashier(id: String, hired: bool) -> void:
	var s := get_shop(id)
	if s:
		s.cashier = hired
		_sync_wage(id)
		shop_changed.emit(id)


func expand(id: String) -> bool:
	var s := get_shop(id)
	if s == null or s.tier >= BusinessCatalog.EXPAND_COST.size():
		return false
	if s.level < BusinessCatalog.EXPAND_LEVEL[s.tier]:
		notify.emit("Needs store level %d" % BusinessCatalog.EXPAND_LEVEL[s.tier])
		return false
	if not EconomyManager.spend(BusinessCatalog.EXPAND_COST[s.tier]):
		notify.emit("Not enough money")
		return false
	s.tier += 1
	while s.shelves.size() < BusinessCatalog.SHELVES_PER_TIER[s.tier]:
		s.shelves.append({product = "", count = 0})
	shop_changed.emit(id)
	return true


# --- Customers ----------------------------------------------------------------

## A customer takes one unit from a shelf. Returns product id or "".
func take_item(id: String, shelf_idx: int) -> String:
	var s := get_shop(id)
	if s == null or shelf_idx >= s.shelves.size():
		return ""
	var shelf: Dictionary = s.shelves[shelf_idx]
	if int(shelf.count) <= 0:
		return ""
	shelf.count = int(shelf.count) - 1
	shop_changed.emit(id)
	return shelf.product


## Would a customer buy this product at the current price?
func wants(id: String, product: String) -> bool:
	return _rng.randf() < BusinessCatalog.buy_chance(product, get_shop(id).price_of(product))


func checkout(id: String, items: Array[String]) -> float:
	var s := get_shop(id)
	if s == null or items.is_empty():
		return 0.0
	var total := 0.0
	for p in items:
		total += s.price_of(p)
	EconomyManager.earn(total)
	s.sold_today += items.size()
	s.revenue_today += total
	s.customers_today += 1
	s.xp += items.size()
	while s.xp >= BusinessCatalog.xp_to_next(s.level):
		s.xp -= BusinessCatalog.xp_to_next(s.level)
		s.level += 1
		level_up.emit(id, s.level)
		notify.emit("Store level %d!" % s.level)
	sale_made.emit(id, total)
	shop_changed.emit(id)
	return total


func customer_lost(id: String) -> void:
	var s := get_shop(id)
	if s:
		s.lost_today += 1


# --- Background sim -----------------------------------------------------------

func _process(_delta: float) -> void:
	var h := int(EconomyManager.get_hour())
	if h == _last_hour:
		return
	_last_hour = h
	if not is_open():
		return
	for id: String in _shops():
		var s := _shops()[id]
		if s.cashier and id != live_shop_id:
			_simulate_hour(id, s)


func _simulate_hour(id: String, s: ShopState) -> void:
	var n := maxi(0, roundi(customer_rate(id) + _rng.randf_range(-1.0, 1.0)))
	for i in n:
		var basket: Array[String] = []
		for k in _rng.randi_range(1, 4):
			var stocked := s.stocked_shelves()
			if stocked.is_empty():
				break
			var idx: int = stocked[_rng.randi() % stocked.size()]
			if wants(id, s.shelves[idx].product):
				basket.append(take_item(id, idx))
		if basket.is_empty():
			customer_lost(id)
		else:
			checkout(id, basket)


func _on_day_passed(_day: int) -> void:
	for s: ShopState in _shops().values():
		s.sold_today = 0
		s.revenue_today = 0.0
		s.customers_today = 0
		s.lost_today = 0


func _sync_wage(id: String) -> void:
	var s := get_shop(id)
	EconomyManager.set_daily_expense("staff:" + id, BusinessCatalog.CASHIER_WAGE if s and s.cashier else 0.0)
