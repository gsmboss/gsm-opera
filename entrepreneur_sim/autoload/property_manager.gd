extends Node
## Autoload "PropertyManager": building catalog, tenure and business assignment.

signal building_purchased(building_id: String)
signal building_rented(building_id: String)
signal business_started(building_id: String, business_type: String)
signal action_failed(building_id: String, reason: String)

enum Tenure { NONE, OWNED, RENTED }

const INCOME_PER_TRAFFIC := 45.0 # daily income per foot-traffic star

var _catalog: Dictionary = {}  # id -> BuildingData
var _tenure: Dictionary = {}   # id -> Tenure (only non-NONE stored)
var _business: Dictionary = {} # id -> business_type


func _ready() -> void:
	# Restore ownership from save (catalog fills in later as spots register).
	for id: String in EconomyManager.player.owned_building_ids:
		_tenure[id] = Tenure.OWNED


# --- Catalog ------------------------------------------------------------------

## Called by BuildingSpot on _ready. Idempotent.
func register_building(data: BuildingData) -> void:
	if data and not data.building_id.is_empty():
		_catalog[data.building_id] = data


func get_building(id: String) -> BuildingData:
	return _catalog.get(id)


func get_tenure(id: String) -> Tenure:
	return _tenure.get(id, Tenure.NONE)


func get_business(id: String) -> String:
	return _business.get(id, "")


func is_controlled(id: String) -> bool:
	return _tenure.has(id)


# --- Actions ------------------------------------------------------------------

## Buying also converts an existing rental (stops rent).
func purchase(id: String) -> bool:
	var data := get_building(id)
	if data == null:
		return _fail(id, "Unknown building")
	if get_tenure(id) == Tenure.OWNED:
		return _fail(id, "Already owned")
	if not EconomyManager.spend(data.price):
		return _fail(id, "Not enough money")
	_tenure[id] = Tenure.OWNED
	EconomyManager.set_daily_expense(_rent_key(id), 0.0)
	EconomyManager.player.owned_building_ids.append(id)
	building_purchased.emit(id)
	return true


## Pays first day upfront, then rent is charged on each day tick.
func rent(id: String) -> bool:
	var data := get_building(id)
	if data == null:
		return _fail(id, "Unknown building")
	if is_controlled(id):
		return _fail(id, "Already controlled")
	if not EconomyManager.spend(data.rent_daily):
		return _fail(id, "Not enough money")
	_tenure[id] = Tenure.RENTED
	EconomyManager.set_daily_expense(_rent_key(id), data.rent_daily)
	building_rented.emit(id)
	return true


func start_business(id: String, business_type: String) -> bool:
	var data := get_building(id)
	if data == null:
		return _fail(id, "Unknown building")
	if not is_controlled(id):
		return _fail(id, "Buy or rent first")
	if not data.allows(business_type):
		return _fail(id, "Type not allowed here")
	if get_business(id) == business_type:
		return _fail(id, "Already running")
	_business[id] = business_type
	EconomyManager.set_daily_income(_income_key(id), data.foot_traffic_rating * INCOME_PER_TRAFFIC)
	business_started.emit(id, business_type)
	return true


# --- Internals ----------------------------------------------------------------

func _fail(id: String, reason: String) -> bool:
	action_failed.emit(id, reason)
	return false


func _rent_key(id: String) -> String:
	return "rent:" + id


func _income_key(id: String) -> String:
	return "biz:" + id
