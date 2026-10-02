extends Node
## Autoload "EconomyManager": single source of truth for player money + day clock.

signal money_changed(new_amount: float)
signal day_passed(day: int)
signal transaction_failed(amount: float)
signal went_into_debt(balance: float)

const SAVE_PATH := "user://player.res"
const SECONDS_PER_DAY := 240.0 # real seconds per game day (also drives day/night)
const START_HOUR := 7.0 # clock time when a new day (rent tick) begins

var player: PlayerData
var day: int = 1

var _timer: Timer
var _daily_expenses: Dictionary[String, float] = {}
var _daily_income: Dictionary[String, float] = {}


func _ready() -> void:
	player = _load_player()
	_timer = Timer.new()
	_timer.wait_time = SECONDS_PER_DAY
	_timer.timeout.connect(_on_day_tick)
	add_child(_timer)
	_timer.start()


# --- Public API ---------------------------------------------------------------

func get_money() -> float:
	return player.money


func can_afford(amount: float) -> bool:
	return player.can_afford(amount)


func spend(amount: float) -> bool:
	if player.deduct_money(amount):
		money_changed.emit(player.money)
		return true
	transaction_failed.emit(amount)
	return false


func earn(amount: float) -> void:
	if amount <= 0.0:
		return
	player.add_money(amount)
	money_changed.emit(player.money)


## Recurring daily cost (e.g. rent). amount <= 0 removes it.
func set_daily_expense(key: String, amount: float) -> void:
	_set_entry(_daily_expenses, key, amount)


## Recurring daily revenue (e.g. business). amount <= 0 removes it.
func set_daily_income(key: String, amount: float) -> void:
	_set_entry(_daily_income, key, amount)


## 0..1 through the current game day.
func get_day_progress() -> float:
	return 1.0 - _timer.time_left / _timer.wait_time if _timer else 0.0


## In-game hour 0..24 (day starts at START_HOUR).
func get_hour() -> float:
	return fmod(START_HOUR + get_day_progress() * 24.0, 24.0)


func get_clock_text() -> String:
	var h := get_hour()
	return "Day %d  %02d:%02d" % [day, int(h), int(fmod(h, 1.0) * 60.0)]


func get_daily_net() -> float:
	return _sum(_daily_income) - _sum(_daily_expenses)


func save_game() -> void:
	ResourceSaver.save(player, SAVE_PATH, ResourceSaver.FLAG_COMPRESS)


# --- Internals ----------------------------------------------------------------

func _on_day_tick() -> void:
	day += 1
	var net := get_daily_net()
	if net != 0.0:
		player.money += net # Rent is mandatory: may go negative.
		money_changed.emit(player.money)
		if player.money < 0.0:
			went_into_debt.emit(player.money)
	day_passed.emit(day)


func _set_entry(dict: Dictionary[String, float], key: String, amount: float) -> void:
	if amount > 0.0:
		dict[key] = amount
	else:
		dict.erase(key)


func _sum(dict: Dictionary[String, float]) -> float:
	var total := 0.0
	for v: float in dict.values():
		total += v
	return total


func _load_player() -> PlayerData:
	if ResourceLoader.exists(SAVE_PATH):
		var res := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerData
		if res:
			return res
	return PlayerData.new()


# Android lifecycle: freeze clock + autosave when backgrounded (OS may kill app).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			if _timer:
				_timer.paused = true
			save_game()
		NOTIFICATION_APPLICATION_RESUMED:
			if _timer:
				_timer.paused = false
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_game()
