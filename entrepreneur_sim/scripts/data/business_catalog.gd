class_name BusinessCatalog
extends RefCounted
## Static product data per business type + cached low-poly item meshes.

## id -> {name, cost (per unit), market (fair retail price), box (units), color, shape, lvl (unlock)}
const PRODUCTS := {
	# grocery
	"cola": {name = "Fizzy Cola", cost = 2.0, market = 4.0, box = 12, color = Color("d62828"), shape = "bottle", lvl = 1},
	"water": {name = "Water", cost = 1.0, market = 2.5, box = 12, color = Color("48cae4"), shape = "bottle", lvl = 1},
	"chips": {name = "Chips", cost = 1.5, market = 3.5, box = 12, color = Color("f77f00"), shape = "bag", lvl = 1},
	"milk": {name = "Milk", cost = 2.5, market = 4.5, box = 8, color = Color("f8f9fa"), shape = "carton", lvl = 2},
	"cereal": {name = "Cereal", cost = 3.0, market = 6.0, box = 8, color = Color("fcbf49"), shape = "box", lvl = 3},
	"candy": {name = "Candy", cost = 1.0, market = 2.5, box = 16, color = Color("ff70a6"), shape = "bag", lvl = 4},
	# cafe
	"coffee": {name = "Coffee Beans", cost = 5.0, market = 10.0, box = 8, color = Color("6f4518"), shape = "bag", lvl = 1},
	"tea": {name = "Tea", cost = 3.0, market = 6.0, box = 10, color = Color("2d6a4f"), shape = "box", lvl = 1},
	"cups": {name = "Paper Cups", cost = 1.0, market = 2.5, box = 16, color = Color("ffffff"), shape = "cup", lvl = 1},
	"cookies": {name = "Cookies", cost = 2.0, market = 4.5, box = 12, color = Color("d4a373"), shape = "box", lvl = 2},
	# bakery
	"bread": {name = "Bread", cost = 1.5, market = 3.5, box = 10, color = Color("c68b59"), shape = "loaf", lvl = 1},
	"croissant": {name = "Croissant", cost = 1.0, market = 2.5, box = 12, color = Color("e9c46a"), shape = "loaf", lvl = 1},
	"donut": {name = "Donut", cost = 1.0, market = 2.5, box = 12, color = Color("ffafcc"), shape = "cup", lvl = 2},
	"cake": {name = "Cake", cost = 6.0, market = 14.0, box = 4, color = Color("ffc8dd"), shape = "box", lvl = 3},
	# bookstore
	"novel": {name = "Novel", cost = 6.0, market = 14.0, box = 8, color = Color("277da1"), shape = "book", lvl = 1},
	"comic": {name = "Comic", cost = 3.0, market = 7.0, box = 10, color = Color("e63946"), shape = "book", lvl = 1},
	"magazine": {name = "Magazine", cost = 2.0, market = 5.0, box = 12, color = Color("ffd166"), shape = "book", lvl = 2},
	"atlas": {name = "Atlas", cost = 10.0, market = 24.0, box = 4, color = Color("43aa8b"), shape = "book", lvl = 4},
	# repair shop
	"charger": {name = "Charger", cost = 4.0, market = 10.0, box = 10, color = Color("f1f1f1"), shape = "box", lvl = 1},
	"case": {name = "Phone Case", cost = 3.0, market = 8.0, box = 12, color = Color("222222"), shape = "box", lvl = 1},
	"cable": {name = "Cable", cost = 1.5, market = 4.0, box = 16, color = Color("adb5bd"), shape = "bag", lvl = 1},
	"battery": {name = "Battery", cost = 5.0, market = 12.0, box = 10, color = Color("38b000"), shape = "box", lvl = 2},
	# tailor
	"shirt": {name = "Shirt", cost = 8.0, market = 20.0, box = 6, color = Color("4895ef"), shape = "clothes", lvl = 1},
	"jeans": {name = "Jeans", cost = 12.0, market = 30.0, box = 6, color = Color("1d3557"), shape = "clothes", lvl = 1},
	"tie": {name = "Tie", cost = 4.0, market = 10.0, box = 10, color = Color("9d0208"), shape = "clothes", lvl = 2},
	"jacket": {name = "Jacket", cost = 25.0, market = 60.0, box = 4, color = Color("7f5539"), shape = "clothes", lvl = 3},
}

const TYPES := {
	"grocery": ["cola", "water", "chips", "milk", "cereal", "candy"],
	"cafe": ["coffee", "tea", "cups", "cookies"],
	"bakery": ["bread", "croissant", "donut", "cake"],
	"bookstore": ["novel", "comic", "magazine", "atlas"],
	"repair_shop": ["charger", "case", "cable", "battery"],
	"tailor": ["shirt", "jeans", "tie", "jacket"],
}

## Interior colour theme per type: [wall, floor, accent]
const THEMES := {
	"grocery": [Color("f1faee"), Color("cfd8dc"), Color("2a9d8f")],
	"cafe": [Color("f4e3c7"), Color("8d6e63"), Color("6f4518")],
	"bakery": [Color("fff1e6"), Color("d7ccc8"), Color("e76f51")],
	"bookstore": [Color("e9edc9"), Color("795548"), Color("264653")],
	"repair_shop": [Color("dee2e6"), Color("6c757d"), Color("f77f00")],
	"tailor": [Color("f8edeb"), Color("a1887f"), Color("6d597a")],
}

const SHELF_LEVELS := 4
const SHELF_COLS := 6
const SHELF_CAPACITY := SHELF_LEVELS * SHELF_COLS
const CASHIER_WAGE := 80.0
const EXPAND_COST: Array[float] = [3000.0, 7000.0]   # tier 0->1, 1->2
const EXPAND_LEVEL: Array[int] = [2, 4]              # store level required
const SHELVES_PER_TIER: Array[int] = [4, 6, 8]

static var _meshes: Dictionary[String, Mesh] = {}


static func products_for(type: String) -> Array:
	return TYPES.get(type, [])


static func info(product: String) -> Dictionary:
	return PRODUCTS.get(product, {})


static func xp_to_next(level: int) -> int:
	return 20 + level * 15


## Purchase probability for a customer who wants `product` at `price`.
static func buy_chance(product: String, price: float) -> float:
	var r := price / float(info(product).market)
	return clampf(1.6 - 0.8 * r, 0.0, 1.0)


## Shared mesh per product (one shelf slot, ~0.25 m).
static func item_mesh(product: String) -> Mesh:
	if _meshes.has(product):
		return _meshes[product]
	var p := info(product)
	var c: Color = p.color
	var st := LowPoly.begin()
	match p.shape:
		"bottle":
			LowPoly.cylinder(st, 0.05, 0.2, Vector3.ZERO, c, 6)
			LowPoly.cylinder(st, 0.025, 0.07, Vector3(0, 0.2, 0), c.darkened(0.2), 6)
			LowPoly.cylinder(st, 0.051, 0.06, Vector3(0, 0.08, 0), Color.WHITE, 6)
		"bag":
			LowPoly.box(st, Vector3(0.16, 0.22, 0.07), Vector3(0, 0.11, 0), c)
			LowPoly.box(st, Vector3(0.1, 0.06, 0.071), Vector3(0, 0.13, 0), Color("ffe066"))
		"carton":
			LowPoly.box(st, Vector3(0.1, 0.2, 0.1), Vector3(0, 0.1, 0), c)
			LowPoly.box(st, Vector3(0.101, 0.06, 0.101), Vector3(0, 0.12, 0), Color("4895ef"))
		"cup":
			LowPoly.cylinder(st, 0.055, 0.12, Vector3.ZERO, c, 8)
		"loaf":
			LowPoly.box(st, Vector3(0.2, 0.1, 0.12), Vector3(0, 0.05, 0), c)
			LowPoly.box(st, Vector3(0.18, 0.04, 0.1), Vector3(0, 0.11, 0), c.lightened(0.15))
		"book":
			LowPoly.box(st, Vector3(0.05, 0.22, 0.16), Vector3(0, 0.11, 0), c)
		"clothes":
			LowPoly.box(st, Vector3(0.2, 0.08, 0.16), Vector3(0, 0.04, 0), c)
			LowPoly.box(st, Vector3(0.2, 0.08, 0.16), Vector3(0, 0.12, 0), c.lightened(0.1))
		_: # box
			LowPoly.box(st, Vector3(0.16, 0.2, 0.1), Vector3(0, 0.1, 0), c)
			LowPoly.box(st, Vector3(0.161, 0.05, 0.101), Vector3(0, 0.15, 0), Color.WHITE)
	var mesh := LowPoly.commit(st)
	_meshes[product] = mesh
	return mesh
