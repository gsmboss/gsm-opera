class_name ShopState
extends Resource
## Saved state of one running shop (lives in PlayerData.shops).

@export var building_id := ""
@export var business_type := ""
@export var level := 1
@export var xp := 0
@export var tier := 0                 # store expansion 0..2 -> shelf count
@export var cashier := false
@export var shelves: Array[Dictionary] = []    # [{product: String, count: int}]
@export var boxes: Array[Dictionary] = []      # delivered, unopened: [{product, count}]
@export var carried: Dictionary = {}           # box in the player's hands
@export var prices: Dictionary[String, float] = {}
@export var sold_today := 0
@export var revenue_today := 0.0
@export var customers_today := 0
@export var lost_today := 0


func price_of(product: String) -> float:
	return prices.get(product, float(BusinessCatalog.info(product).get("market", 1.0)))


func total_stock() -> int:
	var n := 0
	for s in shelves:
		n += int(s.count)
	return n


## Shelf indices currently holding at least one unit.
func stocked_shelves() -> Array[int]:
	var out: Array[int] = []
	for i in shelves.size():
		if int(shelves[i].count) > 0:
			out.append(i)
	return out
